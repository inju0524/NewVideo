import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;

import 'models.dart';
import 'repository_dns.dart';

class SourceImportResult {
  const SourceImportResult({
    this.sources = const [],
    this.items = const [],
    this.headersBySourceId = const {},
    this.skippedScripts = 0,
    this.childRepositories = const [],
  });

  final List<MediaSource> sources;
  final List<MediaItem> items;
  final Map<String, Map<String, String>> headersBySourceId;
  final int skippedScripts;
  final List<SourceRepository> childRepositories;

  bool get isEmpty => sources.isEmpty && items.isEmpty;
}

class SourceRepository {
  const SourceRepository({
    required this.name,
    required this.url,
    this.description = '',
  });

  final String name;
  final String url;
  final String description;
}

class RemoteSourceImportResult {
  const RemoteSourceImportResult({
    this.sources = const [],
    this.headersBySourceId = const {},
    this.skippedScripts = 0,
    this.fetchedConfigs = 0,
    this.failedConfigs = 0,
    this.truncated = false,
  });

  final List<MediaSource> sources;
  final Map<String, Map<String, String>> headersBySourceId;
  final int skippedScripts;
  final int fetchedConfigs;
  final int failedConfigs;
  final bool truncated;
}

class SourceImporter {
  const SourceImporter();

  static String idFor(String value) => _stableId(value);

  static const publicRepositories = [
    SourceRepository(name: '哈基米', url: 'https://17264.kstore.space/哈基米.png'),
    SourceRepository(name: '真心', url: 'https://www.252035.xyz/z/FongMi.json'),
    SourceRepository(
      name: '分享',
      url: 'https://raw.githubusercontent.com/maoystv/6/main/000.json',
    ),
    SourceRepository(
      name: '东篱线路',
      url: 'https://raw.githubusercontent.com/chitue/dongliTV/main/api.json',
    ),
    SourceRepository(name: '游魂多仓', url: 'https://www.iyouhun.com/tv/dc'),
  ];

  static const maxFileBytes = 50 * 1024 * 1024;
  static const maxArchiveEntries = 1200;
  static const maxArchiveTextBytes = 8 * 1024 * 1024;
  static const maxTextEntryBytes = 1024 * 1024;
  static const maxRemoteConfigs = 48;
  static const maxRemoteSources = 160;
  static const maxRemoteConfigBytes = 2 * 1024 * 1024;

  SourceImportResult parseFile(String filename, Uint8List bytes) {
    if (bytes.length > maxFileBytes) {
      throw const FormatException('文件超过 50 MB，未导入');
    }

    if (filename.toLowerCase().endsWith('.zip')) {
      return _parseZip(bytes);
    }
    return _parseText(filename, utf8.decode(bytes, allowMalformed: true));
  }

  Future<RemoteSourceImportResult> importRepositories(
    Iterable<SourceRepository> repositories, {
    required http.Client client,
    Uri? webProxyEndpoint,
    Future<bool> Function(String host)? hostValidator,
  }) async {
    final validateHost = hostValidator ?? isPublicRepositoryHost;
    final pending = repositories.toList();
    final visited = <String>{};
    final sourcesByEndpoint = <String, MediaSource>{};
    final headersBySourceId = <String, Map<String, String>>{};
    var skippedScripts = 0;
    var fetchedConfigs = 0;
    var failedConfigs = 0;
    var truncated = false;
    var attemptedConfigs = 0;

    while (pending.isNotEmpty && attemptedConfigs < maxRemoteConfigs) {
      final batch = <SourceRepository>[];
      while (pending.isNotEmpty &&
          batch.length < 4 &&
          attemptedConfigs + batch.length < maxRemoteConfigs) {
        final repository = pending.removeAt(0);
        final uri = _safeRepositoryUri(repository.url);
        if (uri != null && visited.add(uri.toString())) batch.add(repository);
      }
      if (batch.isEmpty) continue;
      attemptedConfigs += batch.length;

      final results = await Future.wait(
        batch.map((repository) async {
          final uri = _safeRepositoryUri(repository.url)!;
          try {
            final fetched = await _fetchRemoteBytes(
              uri,
              client: client,
              webProxyEndpoint: webProxyEndpoint,
              hostValidator: validateHost,
            );
            return (
              repository: repository,
              uri: fetched.uri,
              bytes: fetched.bytes,
            );
          } on Object {
            return (repository: repository, uri: uri, bytes: null);
          }
        }),
      );

      for (final fetched in results) {
        if (fetched.bytes == null) {
          failedConfigs++;
          continue;
        }
        try {
          final parsed = parseRemoteConfig(
            fetched.repository.name,
            fetched.uri,
            fetched.bytes!,
          );
          fetchedConfigs++;
          skippedScripts += parsed.skippedScripts;
          headersBySourceId.addAll(parsed.headersBySourceId);
          final sourceCandidates = parsed.sources
              .take(maxRemoteSources - sourcesByEndpoint.length)
              .toList();
          if (sourceCandidates.length < parsed.sources.length) {
            truncated = true;
          }
          for (var start = 0; start < sourceCandidates.length; start += 8) {
            final end = start + 8 < sourceCandidates.length
                ? start + 8
                : sourceCandidates.length;
            final batch = sourceCandidates.sublist(start, end);
            final publicSources = await Future.wait(
              batch.map((source) async {
                final sourceUri = Uri.parse(source.endpoint);
                return _isPublicHostSyntax(sourceUri.host) &&
                    await validateHost(sourceUri.host);
              }),
            );
            for (var index = 0; index < batch.length; index++) {
              if (!publicSources[index]) continue;
              final source = batch[index];
              sourcesByEndpoint.putIfAbsent(
                source.endpoint,
                () => source.copyWith(
                  enabled: false,
                  statusMessage: '公开仓导入，默认关闭',
                ),
              );
            }
          }
          pending.addAll(parsed.childRepositories);
          if (sourcesByEndpoint.length >= maxRemoteSources) {
            truncated = true;
            break;
          }
        } on Object {
          failedConfigs++;
        }
        if (fetchedConfigs >= maxRemoteConfigs) break;
      }
    }
    if (pending.isNotEmpty) truncated = true;
    return RemoteSourceImportResult(
      sources: sourcesByEndpoint.values.take(maxRemoteSources).toList(),
      headersBySourceId: headersBySourceId,
      skippedScripts: skippedScripts,
      fetchedConfigs: fetchedConfigs,
      failedConfigs: failedConfigs,
      truncated: truncated,
    );
  }

  SourceImportResult parseRemoteConfig(String name, Uri uri, Uint8List bytes) {
    if (bytes.length > maxRemoteConfigBytes) {
      throw const FormatException('配置文件超过 2 MB');
    }
    final text = utf8.decode(bytes, allowMalformed: true);
    if (text.trimLeft().toLowerCase().startsWith('<')) {
      throw const FormatException('仓库返回的是网页，不是 JSON 配置');
    }
    return _parseText(name, text, baseUri: uri);
  }

  Future<({Uri uri, Uint8List bytes})> _fetchRemoteBytes(
    Uri uri, {
    required http.Client client,
    Uri? webProxyEndpoint,
    required Future<bool> Function(String host) hostValidator,
  }) async {
    var target = uri;
    for (var redirect = 0; redirect <= 4; redirect++) {
      if (!await hostValidator(target.host)) {
        throw const FormatException('配置地址解析到非公网 IP，已拒绝');
      }
      final requestUri = webProxyEndpoint == null
          ? target
          : webProxyEndpoint.replace(
              queryParameters: {
                ...webProxyEndpoint.queryParameters,
                'url': target.toString(),
                'publicConfig': '1',
              },
            );
      final request = http.Request('GET', requestUri)
        ..followRedirects = false
        ..headers['Accept'] = 'application/json, text/plain, */*';
      final response = await client
          .send(request)
          .timeout(const Duration(seconds: 12));
      if (response.isRedirect ||
          const {301, 302, 303, 307, 308}.contains(response.statusCode)) {
        if (webProxyEndpoint != null) {
          await response.stream.drain<void>();
          throw const FormatException('配置代理返回了意外重定向');
        }
        final location = response.headers['location'];
        if (location == null || redirect == 4) {
          await response.stream.drain<void>();
          throw const FormatException('配置重定向次数过多');
        }
        final redirected = _safeRepositoryUri(
          target.resolve(location).toString(),
        );
        await response.stream.drain<void>();
        if (redirected == null || !await hostValidator(redirected.host)) {
          throw const FormatException('配置重定向到非公网地址，已拒绝');
        }
        target = redirected;
        continue;
      }
      if (response.statusCode != 200) {
        await response.stream.drain<void>();
        throw FormatException('配置服务器返回 HTTP ${response.statusCode}');
      }
      if (response.contentLength != null &&
          response.contentLength! > maxRemoteConfigBytes) {
        await response.stream.drain<void>();
        throw const FormatException('配置文件超过 2 MB');
      }
      if (webProxyEndpoint != null) {
        final finalUriValue = response.headers['x-source-config-url'];
        final finalUri = finalUriValue == null
            ? null
            : _safeRepositoryUri(finalUriValue);
        if (finalUri == null || !await hostValidator(finalUri.host)) {
          await response.stream.drain<void>();
          throw const FormatException('配置代理未提供有效的最终配置地址');
        }
        target = finalUri;
      }
      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 12),
      )) {
        if (builder.length + chunk.length > maxRemoteConfigBytes) {
          throw const FormatException('配置文件超过 2 MB');
        }
        builder.add(chunk);
      }
      return (uri: target, bytes: builder.takeBytes());
    }
    throw const FormatException('配置重定向次数过多');
  }

  static Uri? _safeRepositoryUri(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme.toLowerCase()) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      return null;
    }
    if (!_isPublicHostSyntax(uri.host)) return null;
    return uri;
  }

  static bool _isPublicHostSyntax(String rawHost) {
    final host = rawHost.toLowerCase();
    if (host == 'localhost' ||
        host.endsWith('.localhost') ||
        host.endsWith('.local') ||
        host.endsWith('.internal')) {
      return false;
    }
    if (host.contains(':') ||
        RegExp(r'^\d{1,3}(?:\.\d{1,3}){3}$').hasMatch(host)) {
      return false;
    }
    return true;
  }

  static bool _looksLikeScriptEndpoint(String rawEndpoint) {
    final path = Uri.tryParse(rawEndpoint)?.path.toLowerCase() ?? '';
    return RegExp(r'\.(js|mjs|jar|dex|apk)$').hasMatch(path);
  }

  SourceImportResult _parseZip(Uint8List bytes) {
    var entryCount = 0;
    var textBytes = 0;
    final archive = ZipDecoder().decodeBytes(
      bytes,
      callback: (entry) {
        entryCount++;
        if (entryCount > maxArchiveEntries) {
          throw const FormatException('ZIP 文件包含过多条目');
        }
        if (_isTextEntry(entry.name)) {
          if (entry.size > maxTextEntryBytes ||
              textBytes + entry.size > maxArchiveTextBytes) {
            throw const FormatException('ZIP 配置文本超过安全解析限制');
          }
          textBytes += entry.size;
        }
      },
    );

    final sources = <MediaSource>[];
    final items = <MediaItem>[];
    final headersBySourceId = <String, Map<String, String>>{};
    var skippedScripts = 0;
    for (final entry in archive.files) {
      if (!entry.isFile || entry.isSymbolicLink) continue;
      final lowerName = entry.name.toLowerCase();
      if (!(lowerName.endsWith('.json') ||
          lowerName.endsWith('.txt') ||
          lowerName.endsWith('.m3u') ||
          lowerName.endsWith('.m3u8'))) {
        continue;
      }
      if (entry.size > maxTextEntryBytes) continue;
      final content = entry.readBytes();
      if (content == null) continue;
      final result = _parseText(
        entry.name,
        utf8.decode(content, allowMalformed: true),
      );
      sources.addAll(result.sources);
      items.addAll(result.items);
      headersBySourceId.addAll(result.headersBySourceId);
      skippedScripts += result.skippedScripts;
    }
    return SourceImportResult(
      sources: _uniqueSources(sources),
      items: items,
      headersBySourceId: headersBySourceId,
      skippedScripts: skippedScripts,
    );
  }

  SourceImportResult _parseText(String filename, String text, {Uri? baseUri}) {
    final normalized = text.replaceFirst('\uFEFF', '');
    final trimmed = normalized.trimLeft();
    if (RegExp(r'#EXT-X-(TARGETDURATION|STREAM-INF|MEDIA-SEQUENCE)')
        .hasMatch(trimmed)) {
      throw const FormatException('这是 HLS 分片清单，请导入频道列表或添加可播放的完整地址');
    }
    if (trimmed.startsWith('#EXTM3U')) return _parseM3u(filename, normalized);

    final jsonCandidate = _normalizeJsonc(normalized);
    final jsonTrimmed = jsonCandidate.trimLeft();
    if (jsonTrimmed.startsWith('{') || jsonTrimmed.startsWith('[')) {
      try {
        final decoded = jsonDecode(jsonCandidate);
        if (decoded is Map<String, dynamic>) {
          return _parseJson(filename, decoded, baseUri: baseUri);
        }
        if (decoded is List) {
          return _parseJson(filename, {
            'sites': [
              for (final value in decoded)
                if (value is Map) {'type': 1, ...value},
            ],
          }, baseUri: baseUri);
        }
      } on FormatException catch (error) {
        throw FormatException('配置 JSON 格式无效：${error.message}');
      }
    }

    return _parseUrlList(filename, normalized);
  }

  SourceImportResult _parseJson(
    String filename,
    Map<String, dynamic> json, {
    Uri? baseUri,
  }) {
    final sources = <MediaSource>[];
    final childRepositories = <SourceRepository>[];
    final headersBySourceId = <String, Map<String, String>>{};
    var skippedScripts = 0;
    final sites = json['sites'];
    if (sites is List) {
      for (final rawSite in sites) {
        if (rawSite is! Map) continue;
        final site = Map<String, dynamic>.from(rawSite);
        final type = site['type']?.toString();
        if (type == '3' || type == '4') {
          skippedScripts++;
          continue;
        }
        if (type != '0' && type != '1') {
          continue;
        }
        final rawEndpoint = site['api']?.toString() ?? '';
        final endpoint = _safeEndpoint(_resolveConfigUrl(rawEndpoint, baseUri));
        if (endpoint == null) continue;
        if (_looksLikeScriptEndpoint(endpoint)) {
          skippedScripts++;
          continue;
        }
        if (baseUri != null && !_isPublicHostSyntax(Uri.parse(endpoint).host)) {
          continue;
        }
        final name = site['name']?.toString().trim();
        final id = _stableId(endpoint);
        final headers = _readHeaders(site['header'] ?? site['headers']);
        if (headers.isNotEmpty) headersBySourceId[id] = headers;
        sources.add(
          MediaSource(
            id: id,
            name: name == null || name.isEmpty ? _nameFromUri(endpoint) : name,
            endpoint: endpoint,
            requiresAuth: headers.isNotEmpty,
          ),
        );
      }
    } else {
      final rawEndpoint =
          json['api']?.toString() ?? json['url']?.toString() ?? '';
      final endpoint = _safeEndpoint(_resolveConfigUrl(rawEndpoint, baseUri));
      if (endpoint != null) {
        if (_looksLikeScriptEndpoint(endpoint)) {
          return SourceImportResult(skippedScripts: skippedScripts + 1);
        }
        if (baseUri != null && !_isPublicHostSyntax(Uri.parse(endpoint).host)) {
          return SourceImportResult(skippedScripts: skippedScripts);
        }
        final name = json['name']?.toString().trim();
        final id = _stableId(endpoint);
        final headers = _readHeaders(json['header'] ?? json['headers']);
        if (headers.isNotEmpty) headersBySourceId[id] = headers;
        sources.add(
          MediaSource(
            id: id,
            name: name == null || name.isEmpty ? _nameFromUri(endpoint) : name,
            endpoint: endpoint,
            requiresAuth: headers.isNotEmpty,
          ),
        );
      }
    }

    final rawUrls = json['urls'];
    if (rawUrls is List) {
      for (final rawRepository in rawUrls) {
        final repository = rawRepository is Map
            ? Map<String, dynamic>.from(rawRepository)
            : null;
        final rawUrl = repository == null
            ? rawRepository?.toString() ?? ''
            : repository['url']?.toString() ??
                  repository['src']?.toString() ??
                  '';
        final safe = _safeRepositoryUri(_resolveConfigUrl(rawUrl, baseUri));
        if (safe == null) continue;
        final childName = repository?['name']?.toString().trim();
        if (childRepositories.length >= maxRemoteConfigs) continue;
        childRepositories.add(
          SourceRepository(
            name: childName == null || childName.isEmpty
                ? _nameFromUri(safe.toString())
                : childName,
            url: safe.toString(),
          ),
        );
      }
    }

    return SourceImportResult(
      sources: _uniqueSources(sources),
      headersBySourceId: headersBySourceId,
      skippedScripts: skippedScripts,
      childRepositories: childRepositories,
    );
  }

  static String _resolveConfigUrl(String raw, Uri? baseUri) {
    final value = raw.trim();
    if (value.isEmpty || baseUri == null) return value;
    if (value.startsWith('//')) return '${baseUri.scheme}:$value';
    final parsed = Uri.tryParse(value);
    if (parsed == null) return '';
    if (parsed.hasScheme || parsed.hasAuthority) return value;
    if (!(value.startsWith('./') ||
        value.startsWith('../') ||
        value.startsWith('/') ||
        value.contains('/') ||
        RegExp(
          r'\.(php|json)(?:$|[?#])',
          caseSensitive: false,
        ).hasMatch(value))) {
      return '';
    }
    return baseUri.resolveUri(parsed).toString();
  }

  static String _normalizeJsonc(String input) {
    final withoutComments = StringBuffer();
    var quote = '';
    var escaped = false;
    var lineComment = false;
    var blockComment = false;
    for (var index = 0; index < input.length; index++) {
      final char = input[index];
      final next = index + 1 < input.length ? input[index + 1] : '';
      if (lineComment) {
        if (char == '\n' || char == '\r') {
          lineComment = false;
          withoutComments.write(char);
        }
        continue;
      }
      if (blockComment) {
        if (char == '*' && next == '/') {
          blockComment = false;
          index++;
        } else if (char == '\n' || char == '\r') {
          withoutComments.write(char);
        }
        continue;
      }
      if (quote.isNotEmpty) {
        withoutComments.write(char);
        if (escaped) {
          escaped = false;
        } else if (char == r'\') {
          escaped = true;
        } else if (char == quote) {
          quote = '';
        }
        continue;
      }
      if (char == '"') {
        quote = char;
        withoutComments.write(char);
      } else if (char == '/' && next == '/') {
        lineComment = true;
        index++;
      } else if (char == '/' && next == '*') {
        blockComment = true;
        index++;
      } else {
        withoutComments.write(char);
      }
    }

    final clean = withoutComments.toString();
    final output = StringBuffer();
    quote = '';
    escaped = false;
    for (var index = 0; index < clean.length; index++) {
      final char = clean[index];
      if (quote.isNotEmpty) {
        output.write(char);
        if (escaped) {
          escaped = false;
        } else if (char == r'\') {
          escaped = true;
        } else if (char == quote) {
          quote = '';
        }
        continue;
      }
      if (char == '"') {
        quote = char;
        output.write(char);
      } else if (char == ',') {
        var lookahead = index + 1;
        while (lookahead < clean.length &&
            RegExp(r'\s').hasMatch(clean[lookahead])) {
          lookahead++;
        }
        if (lookahead >= clean.length ||
            (clean[lookahead] != '}' && clean[lookahead] != ']')) {
          output.write(char);
        }
      } else {
        output.write(char);
      }
    }
    return output.toString();
  }

  SourceImportResult _parseUrlList(String filename, String text) {
    final sources = <MediaSource>[];
    final items = <MediaItem>[];
    final playlistId = 'playlist-${_stableId('$filename:$text')}';
    final playlistName = filename.replaceFirst(RegExp(r'\.[^.]+$'), '');
    String group = '直播';
    for (final line in const LineSplitter().convert(text)) {
      if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
      if (line.contains(',#genre#')) {
        group = line.split(',').first.trim();
        continue;
      }
      final match = RegExp(r'https?://[^\s"<>|,]+').firstMatch(line);
      if (match == null) continue;
      final endpoint = _safeEndpoint(
        match.group(0)!.replaceFirst(RegExp(r'[\])}]+$'), ''),
      );
      if (endpoint == null) continue;
      final path = Uri.parse(endpoint).path.toLowerCase();
      final comma = line.indexOf(',');
      final textPlaylist = comma >= 0 && comma < match.start;
      if (textPlaylist || RegExp(r'\.(m3u8|mp4|m4v|webm|ts)$').hasMatch(path)) {
        final label = textPlaylist
            ? line.substring(0, comma).trim()
            : line
                  .substring(0, match.start)
                  .replaceFirst(RegExp(r'[:：]\s*$'), '')
                  .trim();
        items.add(
          MediaItem(
            id: '$playlistId:${items.length}',
            title: label.isEmpty ? _nameFromUri(endpoint) : label,
            sourceId: playlistId,
            sourceName: playlistName,
            genre: group,
            remarks: '直播',
            episodes: [MediaEpisode(title: '播放', url: endpoint)],
          ),
        );
        continue;
      }
      final labelMatch = RegExp(r'^\s*(?:\d+\s*)?([^:：]+)[:：]')
          .firstMatch(line);
      final label = labelMatch?.group(1)?.trim();
      sources.add(
        MediaSource(
          id: _stableId(endpoint),
          name: label == null || label.isEmpty ? _nameFromUri(endpoint) : label,
          endpoint: endpoint,
        ),
      );
    }
    if (items.isNotEmpty) {
      sources.add(
        MediaSource(
          id: playlistId,
          name: playlistName,
          endpoint: 'local://$playlistId',
          kind: SourceKind.m3u,
          health: SourceHealth.available,
          statusMessage: '${items.length} 个频道',
        ),
      );
    }
    return SourceImportResult(sources: _uniqueSources(sources), items: items);
  }

  SourceImportResult _parseM3u(String filename, String text) {
    final sourceId = 'playlist-${_stableId('$filename:$text')}';
    final sourceName = filename.replaceFirst(RegExp(r'\.[^.]+$'), '');
    final items = <MediaItem>[];
    String? title;
    String? group;
    for (final line in const LineSplitter().convert(text)) {
      final value = line.trim();
      if (value.startsWith('#EXTINF:')) {
        final comma = value.lastIndexOf(',');
        title = comma >= 0 ? value.substring(comma + 1).trim() : '未命名频道';
        group = RegExp(r'group-title="([^"]*)"')
            .firstMatch(value)
            ?.group(1)
            ?.trim();
        continue;
      }
      if (value.startsWith('#') || value.isEmpty) continue;
      final url = _safeEndpoint(value);
      if (url == null) continue;
      final itemTitle = title ?? _nameFromUri(url);
      items.add(
        MediaItem(
          id: '$sourceId:${items.length}',
          title: itemTitle,
          sourceId: sourceId,
          sourceName: sourceName,
          genre: group ?? '直播',
          remarks: '直播',
          episodes: [MediaEpisode(title: '直播', url: url)],
        ),
      );
      title = null;
      group = null;
    }

    return SourceImportResult(
      sources: [
        MediaSource(
          id: sourceId,
          name: sourceName,
          endpoint: 'local://$sourceId',
          kind: SourceKind.m3u,
          health: SourceHealth.available,
          statusMessage: '${items.length} 个频道',
        ),
      ],
      items: items,
    );
  }

  static String? _safeEndpoint(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    const sensitiveKeys = {
      'token',
      'access_token',
      'authorization',
      'auth',
      'password',
      'passwd',
      'secret',
      'sign',
      'signature',
      'apikey',
      'api_key',
      'key',
    };
    if (uri.queryParameters.keys.any(
      (key) =>
          sensitiveKeys.contains(key.toLowerCase()) ||
          RegExp(r'token|auth|pass|secret|sign|key|cred|session|ticket|user')
              .hasMatch(key.toLowerCase()),
    )) {
      return null;
    }
    return uri.toString();
  }

  static String _nameFromUri(String value) {
    final host = Uri.tryParse(value)?.host ?? '';
    return host.isEmpty ? '导入片源' : host;
  }

  static bool _isTextEntry(String name) {
    final lowerName = name.toLowerCase();
    return lowerName.endsWith('.json') ||
        lowerName.endsWith('.txt') ||
        lowerName.endsWith('.m3u') ||
        lowerName.endsWith('.m3u8');
  }

  static Map<String, String> _readHeaders(Object? raw) {
    Object? value = raw;
    if (value is String) {
      try {
        value = jsonDecode(value);
      } on FormatException {
        return const {};
      }
    }
    if (value is! Map) return const {};
    final headers = <String, String>{};
    var totalLength = 0;
    for (final entry in value.entries) {
      final name = entry.key.toString().trim();
      final content = entry.value.toString();
      if (!RegExp(r'^[a-zA-Z0-9-]{1,80}$').hasMatch(name) ||
          const {
            'host',
            'content-length',
            'connection',
          }.contains(name.toLowerCase()) ||
          content.contains('\r') ||
          content.contains('\n') ||
          content.length > 4096) {
        continue;
      }
      totalLength += name.length + content.length;
      if (totalLength > 8192) return const {};
      headers[name] = content;
    }
    return headers;
  }

  static String _stableId(String value) {
    var hash = 0x811c9dc5;
    for (final codeUnit in value.codeUnits) {
      hash = ((hash ^ codeUnit) * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  static List<MediaSource> _uniqueSources(List<MediaSource> sources) {
    final seen = <String>{};
    return sources.where((source) => seen.add(source.endpoint)).toList();
  }
}
