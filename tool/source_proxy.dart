import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const _defaultPort = 8124;
const _forwardRequestHeaders = {
  'accept',
  'authorization',
  'if-modified-since',
  'if-none-match',
  'range',
  'referer',
  'user-agent',
  'x-emby-token',
  'x-subscription',
};
const _hopByHopHeaders = {
  'connection',
  'content-encoding',
  'content-length',
  'keep-alive',
  'proxy-authenticate',
  'proxy-authorization',
  'set-cookie',
  'te',
  'trailer',
  'transfer-encoding',
  'upgrade',
};
const _maxPublicConfigBytes = 2 * 1024 * 1024;

Future<void> main(List<String> args) async {
  final port = _readPort(args);
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  stdout.writeln('Source proxy listening on http://127.0.0.1:$port');

  await for (final request in server) {
    unawaited(_handle(request));
  }
}

int _readPort(List<String> args) {
  for (var index = 0; index + 1 < args.length; index++) {
    if (args[index] == '--port') {
      return int.tryParse(args[index + 1]) ?? _defaultPort;
    }
  }
  return _defaultPort;
}

Future<void> _handle(HttpRequest request) async {
  _addCorsHeaders(request.response);
  if (request.method == 'OPTIONS') {
    request.response.statusCode = HttpStatus.noContent;
    await request.response.close();
    return;
  }

  if (request.method != 'GET') {
    await _writeError(request.response, HttpStatus.methodNotAllowed, '仅支持 GET');
    return;
  }

  if (request.uri.path == '/health') {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode({'ok': true}));
    await request.response.close();
    return;
  }

  if (request.uri.path != '/proxy') {
    await _writeError(request.response, HttpStatus.notFound, '代理路径不存在');
    return;
  }

  final rawTarget = request.uri.queryParameters['url'];
  if (rawTarget == null || rawTarget.length > 8192) {
    await _writeError(request.response, HttpStatus.badRequest, '目标地址无效');
    return;
  }
  final target = Uri.tryParse(rawTarget);
  if (target == null ||
      !{'http', 'https'}.contains(target.scheme) ||
      target.host.isEmpty ||
      target.userInfo.isNotEmpty ||
      target.fragment.isNotEmpty) {
    await _writeError(request.response, HttpStatus.badRequest, '目标地址无效');
    return;
  }
  final publicConfig = request.uri.queryParameters['publicConfig'] == '1';

  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12)
    ..idleTimeout = const Duration(seconds: 30)
    ..autoUncompress = true;
  try {
    var destination = target;
    late HttpClientResponse upstreamResponse;
    for (var redirect = 0; redirect <= 4; redirect++) {
      if (publicConfig && !await _isPublicDestination(destination)) {
        await _writeError(
          request.response,
          HttpStatus.badRequest,
          '只允许访问公网配置地址',
        );
        return;
      }
      final upstreamRequest = await client
          .getUrl(destination)
          .timeout(const Duration(seconds: 12));
      upstreamRequest.followRedirects = !publicConfig;
      request.headers.forEach((name, values) {
        if (_forwardRequestHeaders.contains(name.toLowerCase())) {
          upstreamRequest.headers.set(name, values.join(', '));
        }
      });

      upstreamResponse = await upstreamRequest.close().timeout(
        const Duration(seconds: 20),
      );
      if (!publicConfig || !upstreamResponse.isRedirect) break;
      final location = upstreamResponse.headers.value(
        HttpHeaders.locationHeader,
      );
      if (location == null || redirect == 4) {
        await upstreamResponse.drain<void>();
        await _writeError(
          request.response,
          HttpStatus.badGateway,
          '配置重定向次数过多或目标无效',
        );
        return;
      }
      final nextDestination = destination.resolve(location);
      await upstreamResponse.drain<void>();
      if (!{'http', 'https'}.contains(nextDestination.scheme) ||
          nextDestination.userInfo.isNotEmpty ||
          nextDestination.fragment.isNotEmpty ||
          nextDestination.host.isEmpty) {
        await _writeError(request.response, HttpStatus.badGateway, '配置重定向目标无效');
        return;
      }
      destination = nextDestination;
    }
    if (publicConfig &&
        upstreamResponse.contentLength > _maxPublicConfigBytes) {
      await upstreamResponse.drain<void>();
      await _writeError(
        request.response,
        HttpStatus.requestEntityTooLarge,
        '配置文件超过 2 MB',
      );
      return;
    }
    request.response.statusCode = upstreamResponse.statusCode;
    upstreamResponse.headers.forEach((name, values) {
      if (!_hopByHopHeaders.contains(name.toLowerCase()) &&
          !(publicConfig && name.toLowerCase() == 'x-source-config-url')) {
        request.response.headers.set(name, values.join(', '));
      }
    });
    if (publicConfig &&
        upstreamResponse.statusCode >= 200 &&
        upstreamResponse.statusCode < 300) {
      request.response.headers.set('X-Source-Config-URL', destination);
    }
    if (_isHlsPlaylist(destination, upstreamResponse)) {
      request.response.headers.set('Cache-Control', 'no-store');
      final body = await utf8.decoder.bind(upstreamResponse).join();
      final rewritten = _rewriteHlsPlaylist(body, destination, request);
      request.response.headers.removeAll(HttpHeaders.contentLengthHeader);
      request.response.headers.contentType ??= ContentType(
        'application',
        'vnd.apple.mpegurl',
        charset: 'utf-8',
      );
      request.response.write(rewritten);
      await request.response.close();
    } else {
      request.response.headers.set(
        'Cache-Control',
        _proxyCacheControl(request, upstreamResponse),
      );
      if (publicConfig) {
        final builder = BytesBuilder(copy: false);
        await for (final chunk in upstreamResponse) {
          if (builder.length + chunk.length > _maxPublicConfigBytes) {
            request.response.headers.removeAll(HttpHeaders.contentLengthHeader);
            request.response
              ..statusCode = HttpStatus.requestEntityTooLarge
              ..headers.contentType = ContentType.json
              ..write(jsonEncode({'error': '配置文件超过 2 MB'}));
            await request.response.close();
            return;
          }
          builder.add(chunk);
        }
        request.response.add(builder.takeBytes());
        await request.response.close();
      } else {
        await upstreamResponse.pipe(request.response);
      }
    }
  } on TimeoutException {
    await _writeError(request.response, HttpStatus.gatewayTimeout, '源站请求超时');
  } on SocketException {
    await _writeError(request.response, HttpStatus.badGateway, '无法连接源站');
  } on HttpException {
    await _writeError(request.response, HttpStatus.badGateway, '源站响应无效');
  } on Object {
    await _writeError(request.response, HttpStatus.badGateway, '代理请求失败');
  } finally {
    client.close(force: true);
  }
}

Future<bool> _isPublicDestination(Uri target) async {
  final addresses = InternetAddress.tryParse(target.host) != null
      ? [InternetAddress(target.host)]
      : await InternetAddress.lookup(target.host)
            .timeout(const Duration(seconds: 5));
  return addresses.isNotEmpty && addresses.every(_isPublicAddress);
}

bool _isPublicAddress(InternetAddress address) {
  final bytes = address.rawAddress;
  if (address.type == InternetAddressType.IPv4) {
    final first = bytes[0];
    final second = bytes[1];
    return first != 0 &&
        first != 10 &&
        first != 127 &&
        first < 224 &&
        !(first == 100 && second >= 64 && second <= 127) &&
        !(first == 169 && second == 254) &&
        !(first == 172 && second >= 16 && second <= 31) &&
        !(first == 192 && (second == 0 || second == 168)) &&
        !(first == 192 && second == 88 && bytes[2] == 99) &&
        !(first == 198 && (second == 18 || second == 19 || second == 51)) &&
        !(first == 203 && second == 0 && bytes[2] == 113);
  }
  if (bytes.length == 16) {
    final first = bytes[0];
    final second = bytes[1];
    return first >= 0x20 &&
        first <= 0x3f &&
        !(first == 0x20 &&
            second == 0x01 &&
            bytes[2] == 0x0d &&
            bytes[3] == 0xb8);
  }
  return false;
}

String _proxyCacheControl(
  HttpRequest request,
  HttpClientResponse upstreamResponse,
) {
  final mimeType = upstreamResponse.headers.contentType?.mimeType.toLowerCase();
  final cacheControl =
      upstreamResponse.headers
          .value(HttpHeaders.cacheControlHeader)
          ?.toLowerCase() ??
      '';
  final hasCredentials =
      request.headers.value(HttpHeaders.authorizationHeader) != null ||
      request.headers.value('x-emby-token') != null ||
      request.headers.value('x-subscription') != null;
  if (upstreamResponse.statusCode >= 200 &&
      upstreamResponse.statusCode < 300 &&
      mimeType?.startsWith('image/') == true &&
      !hasCredentials &&
      !cacheControl.contains('no-store') &&
      !cacheControl.contains('no-cache')) {
    return 'private, max-age=86400';
  }
  return 'no-store';
}

bool _isHlsPlaylist(Uri target, HttpClientResponse response) {
  if (response.statusCode < 200 || response.statusCode >= 300) return false;
  final path = target.path.toLowerCase();
  if (path.endsWith('.m3u8') || path.endsWith('.m3u')) return true;
  final mime = response.headers.contentType?.mimeType.toLowerCase() ?? '';
  return mime == 'application/vnd.apple.mpegurl' ||
      mime == 'application/x-mpegurl' ||
      mime == 'audio/mpegurl' ||
      mime == 'audio/x-mpegurl';
}

String _rewriteHlsPlaylist(String playlist, Uri source, HttpRequest request) {
  final lines = playlist.split('\n');
  return lines
      .map((line) {
        final newline = line.endsWith('\r') ? '\r' : '';
        final content = newline.isEmpty
            ? line
            : line.substring(0, line.length - 1);
        if (content.trim().isEmpty || content.trimLeft().startsWith('#')) {
          return _rewriteHlsUriAttributes(content, source, request) + newline;
        }
        final resolved = source.resolve(content.trim());
        return _proxyUri(request, resolved).toString() + newline;
      })
      .join('\n');
}

String _rewriteHlsUriAttributes(String line, Uri source, HttpRequest request) {
  return line.replaceAllMapped(RegExp(r'URI="([^"]+)"'), (match) {
    final rawUri = match.group(1)!;
    final resolved = source.resolve(rawUri);
    return 'URI="${_proxyUri(request, resolved)}"';
  });
}

Uri _proxyUri(HttpRequest request, Uri target) {
  final host = request.headers.value('host');
  final base = host == null || host.isEmpty
      ? Uri(
          scheme: 'http',
          host: '127.0.0.1',
          port: request.connectionInfo?.localPort ?? _defaultPort,
          path: '/proxy',
        )
      : Uri.parse('http://$host').replace(path: '/proxy');
  return base.replace(queryParameters: {'url': target.toString()});
}

void _addCorsHeaders(HttpResponse response) {
  response.headers
    ..set('Access-Control-Allow-Origin', '*')
    ..set('Access-Control-Allow-Methods', 'GET, OPTIONS')
    ..set(
      'Access-Control-Allow-Headers',
      'Accept, Authorization, Content-Type, Range, X-Emby-Token, X-Subscription',
    )
    ..set(
      'Access-Control-Expose-Headers',
      'Accept-Ranges, Content-Length, Content-Range, Content-Type, Location, X-Source-Config-URL',
    );
}

Future<void> _writeError(
  HttpResponse response,
  int statusCode,
  String message,
) async {
  response.headers.contentType = ContentType(
    'application',
    'json',
    charset: 'utf-8',
  );
  response.statusCode = statusCode;
  response.add(utf8.encode(jsonEncode({'error': message})));
  await response.close();
}
