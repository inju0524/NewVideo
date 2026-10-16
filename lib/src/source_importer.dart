import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'models.dart';

class SourceImportResult {
  const SourceImportResult({
    this.sources = const [],
    this.items = const [],
    this.headersBySourceId = const {},
    this.skippedScripts = 0,
  });

  final List<MediaSource> sources;
  final List<MediaItem> items;
  final Map<String, Map<String, String>> headersBySourceId;
  final int skippedScripts;

  bool get isEmpty => sources.isEmpty && items.isEmpty;
}

class SourceImporter {
  const SourceImporter();

  static String idFor(String value) => _stableId(value);

  static const maxFileBytes = 50 * 1024 * 1024;
  static const maxArchiveEntries = 1200;
  static const maxArchiveTextBytes = 8 * 1024 * 1024;
  static const maxTextEntryBytes = 1024 * 1024;

  SourceImportResult parseFile(String filename, Uint8List bytes) {
    if (bytes.length > maxFileBytes) {
      throw const FormatException('文件超过 50 MB，未导入');
    }

    if (filename.toLowerCase().endsWith('.zip')) {
      return _parseZip(bytes);
    }
    return _parseText(filename, utf8.decode(bytes, allowMalformed: true));
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

  SourceImportResult _parseText(String filename, String text) {
    final normalized = text.replaceFirst('\uFEFF', '');
    final trimmed = normalized.trimLeft();
    if (RegExp(r'#EXT-X-(TARGETDURATION|STREAM-INF|MEDIA-SEQUENCE)')
        .hasMatch(trimmed)) {
      throw const FormatException('这是 HLS 分片清单，请导入频道列表或添加可播放的完整地址');
    }
    if (trimmed.startsWith('#EXTM3U')) return _parseM3u(filename, normalized);

    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      try {
        final decoded = jsonDecode(normalized);
        if (decoded is Map<String, dynamic>) {
          return _parseJson(filename, decoded);
        }
        if (decoded is List) {
          return _parseJson(filename, {
            'sites': [
              for (final value in decoded)
                if (value is Map) {'type': 1, ...value},
            ],
          });
        }
      } on FormatException {
        // Fall through to plain-text URL parsing.
      }
    }

    return _parseUrlList(filename, normalized);
  }

  SourceImportResult _parseJson(String filename, Map<String, dynamic> json) {
    final sources = <MediaSource>[];
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
          skippedScripts++;
          continue;
        }
        final endpoint = _safeEndpoint(site['api']?.toString() ?? '');
        if (endpoint == null) continue;
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
      final endpoint = _safeEndpoint(
        json['api']?.toString() ?? json['url']?.toString() ?? '',
      );
      if (endpoint != null) {
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

    return SourceImportResult(
      sources: _uniqueSources(sources),
      headersBySourceId: headersBySourceId,
      skippedScripts: skippedScripts,
    );
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
