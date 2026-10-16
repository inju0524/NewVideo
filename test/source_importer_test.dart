import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:zhuying/src/models.dart';
import 'package:zhuying/src/source_importer.dart';

void main() {
  const importer = SourceImporter();

  test(
    'imports standard TVBox APIs and counts scripts without executing them',
    () {
      final json = {
        'sites': [
          {
            'name': 'CMS JSON',
            'type': 1,
            'api': 'https://media.example/api.php/provide/vod',
          },
          {
            'name': 'CMS XML',
            'type': 0,
            'api': 'https://media.example/xml.php',
          },
          {
            'name': 'Spider',
            'type': 3,
            'api': 'https://media.example/spider.js',
          },
          {
            'name': 'Unsupported type',
            'type': 9,
            'api': 'https://media.example/custom',
          },
        ],
      };

      final result = importer.parseFile(
        'sources.json',
        Uint8List.fromList(utf8.encode(jsonEncode(json))),
      );

      expect(result.sources.map((source) => source.name), [
        'CMS JSON',
        'CMS XML',
      ]);
      expect(result.skippedScripts, 1);
    },
  );

  test('parses JSONC multi-repository files and ignores script sources', () {
    const config = '''
// Repository header
{
  "urls": [
    {"name": "nested", "url": "./child.json"},
  ],
  "sites": [
    {"name": "CMS", "type": 1, "api": "https://media.example/api.php/provide/vod"},
    {"name": "Spider", "type": 3, "api": "csp_Test"},
  ],
}
''';
    final parsed = importer.parseRemoteConfig(
      'root',
      Uri.parse('https://configs.example/path/root.json'),
      Uint8List.fromList(utf8.encode(config)),
    );

    expect(
      parsed.sources.single.endpoint,
      'https://media.example/api.php/provide/vod',
    );
    expect(parsed.sources.single.enabled, isTrue);
    expect(parsed.skippedScripts, 1);
    expect(
      parsed.childRepositories.single.url,
      'https://configs.example/path/child.json',
    );
  });

  test(
    'imports nested repositories and leaves imported sources disabled',
    () async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/root.json')) {
          return http.Response('''
        {
          "urls": [{"name":"Nested","url":"https://configs.example/child.json"}],
          "sites": [{"name":"Root CMS","type":1,"api":"https://root.example/api.php/provide/vod"}]
        }
        ''', 200);
        }
        if (request.url.path.endsWith('/child.json')) {
          return http.Response('''
        {"sites":[
          {"name":"Child CMS","type":0,"api":"https://child.example/xml.php"},
          {"name":"Spider","type":3,"api":"csp_Test"}
        ]}
        ''', 200);
        }
        return http.Response('missing', 404);
      });

      final result = await const SourceImporter().importRepositories(
        const [
          SourceRepository(
            name: 'Root',
            url: 'https://configs.example/root.json',
          ),
        ],
        client: client,
        hostValidator: (_) async => true,
      );

      expect(result.fetchedConfigs, 2);
      expect(result.failedConfigs, 0);
      expect(result.skippedScripts, 1);
      expect(result.sources.map((source) => source.name), [
        'Root CMS',
        'Child CMS',
      ]);
      expect(result.sources.every((source) => !source.enabled), isTrue);
      client.close();
    },
  );

  test(
    'resolves nested repository URLs against the final redirect URL',
    () async {
      final requests = <Uri>[];
      final client = MockClient((request) async {
        requests.add(request.url);
        if (request.url.path == '/root.json') {
          return http.Response(
            '',
            302,
            headers: {'location': '/resolved/root.json'},
          );
        }
        if (request.url.path == '/resolved/root.json') {
          return http.Response(
            '{"urls":[{"name":"Nested","url":"./child.json"}],'
            '"sites":[{"name":"Root","type":1,"api":"https://root.example/api.php/provide/vod"}]}',
            200,
          );
        }
        if (request.url.path == '/resolved/child.json') {
          return http.Response(
            '{"sites":[{"name":"Child","type":1,"api":"https://child.example/api.php/provide/vod"}]}',
            200,
          );
        }
        return http.Response('missing', 404);
      });

      final result = await const SourceImporter().importRepositories(
        const [
          SourceRepository(
            name: 'Root',
            url: 'https://config.example/root.json',
          ),
        ],
        client: client,
        hostValidator: (_) async => true,
      );

      expect(result.fetchedConfigs, 2);
      expect(result.failedConfigs, 0);
      expect(result.sources.map((source) => source.name), ['Root', 'Child']);
      expect(requests.map((uri) => uri.toString()), [
        'https://config.example/root.json',
        'https://config.example/resolved/root.json',
        'https://config.example/resolved/child.json',
      ]);
      client.close();
    },
  );

  test(
    'uses final config URL returned by web proxy for nested repositories',
    () async {
      final proxiedTargets = <String>[];
      final client = MockClient((request) async {
        final target = request.url.queryParameters['url']!;
        proxiedTargets.add(target);
        if (target == 'https://config.example/root.json') {
          return http.Response(
            '{"urls":[{"name":"Nested","url":"./child.json"}],'
            '"sites":[{"name":"Root","type":1,"api":"https://root.example/api.php/provide/vod"}]}',
            200,
            headers: {
              'x-source-config-url': 'https://cdn.example/resolved/root.json',
            },
          );
        }
        if (target == 'https://cdn.example/resolved/child.json') {
          return http.Response(
            '{"sites":[{"name":"Child","type":1,"api":"https://child.example/api.php/provide/vod"}]}',
            200,
            headers: {
              'x-source-config-url': 'https://cdn.example/resolved/child.json',
            },
          );
        }
        return http.Response('missing', 404);
      });

      final result = await const SourceImporter().importRepositories(
        const [
          SourceRepository(
            name: 'Root',
            url: 'https://config.example/root.json',
          ),
        ],
        client: client,
        webProxyEndpoint: Uri.parse('http://proxy.example/proxy'),
        hostValidator: (_) async => true,
      );

      expect(result.fetchedConfigs, 2);
      expect(result.failedConfigs, 0);
      expect(result.sources.map((source) => source.name), ['Root', 'Child']);
      expect(proxiedTargets, [
        'https://config.example/root.json',
        'https://cdn.example/resolved/child.json',
      ]);
      client.close();
    },
  );

  test('rejects repository redirects to IP addresses', () async {
    final client = MockClient((request) async {
      return http.Response(
        '',
        302,
        headers: {'location': 'http://127.0.0.1/private'},
      );
    });

    final result = await const SourceImporter().importRepositories(
      const [
        SourceRepository(
          name: 'Redirect',
          url: 'https://config.example/root.json',
        ),
      ],
      client: client,
      hostValidator: (_) async => true,
    );

    expect(result.failedConfigs, 1);
    expect(result.sources, isEmpty);
    client.close();
  });

  test('drops APIs that resolve to non-public addresses', () async {
    final client = MockClient((_) async {
      return http.Response(
        '{"sites":[{"name":"Private","type":1,"api":"https://private.example/api.php/provide/vod"}]}',
        200,
      );
    });
    final result = await const SourceImporter().importRepositories(
      const [
        SourceRepository(
          name: 'Private config',
          url: 'https://config.example/root.json',
        ),
      ],
      client: client,
      hostValidator: (host) async => host != 'private.example',
    );

    expect(result.fetchedConfigs, 1);
    expect(result.sources, isEmpty);
    client.close();
  });

  test('imports M3U entries as local playable channels', () {
    const playlist = '''
#EXTM3U
#EXTINF:-1 tvg-name="News" group-title="News",World News
https://media.example/live/news.m3u8
#EXTINF:-1 group-title="Sports",Sports One
https://media.example/live/sports.m3u8
''';

    final result = importer.parseFile(
      'channels.m3u',
      Uint8List.fromList(utf8.encode(playlist)),
    );

    expect(result.sources.single.kind.name, 'm3u');
    expect(result.items.map((item) => item.title), [
      'World News',
      'Sports One',
    ]);
    expect(result.items.first.episodes.single.url, contains('.m3u8'));
  });

  test('does not persist source URLs carrying credential parameters', () {
    const text = '''
Public: https://media.example/api.php/provide/vod
Private: https://media.example/api.php/provide/vod?token=secret
''';

    final result = importer.parseFile(
      'sources.txt',
      Uint8List.fromList(utf8.encode(text)),
    );

    expect(result.sources, hasLength(1));
    expect(result.sources.single.name, 'Public');
  });

  test('reads JSON configs from ZIP without extracting archive entries', () {
    final archive = Archive()
      ..addFile(
        ArchiveFile.string(
          'config/api.json',
          jsonEncode({
            'sites': [
              {
                'name': 'ZIP source',
                'type': 1,
                'api': 'https://media.example/api.php/provide/vod',
              },
            ],
          }),
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'scripts/ignored.js',
          'throw new Error("must not run");',
        ),
      );
    final bytes = ZipEncoder().encode(archive);

    final result = importer.parseFile('bundle.zip', Uint8List.fromList(bytes));

    expect(result.sources.single.name, 'ZIP source');
    expect(result.skippedScripts, 0);
  });

  test('imports plain text channel lists as a local playlist', () {
    const text = '''
News,#genre#
World News,http://media.example/live/news.m3u8
Movie,http://media.example/video/movie.mp4
CMS API:https://media.example/api.php/provide/vod
''';

    final result = importer.parseFile(
      'channels.txt',
      Uint8List.fromList(utf8.encode(text)),
    );

    expect(result.sources, hasLength(2));
    expect(result.sources.last.kind, SourceKind.m3u);
    expect(result.items.map((item) => item.title), ['World News', 'Movie']);
    expect(result.items.first.genre, 'News');
  });

  test('rejects a standalone HLS segment manifest', () {
    expect(
      () => importer.parseFile(
        'stream.m3u8',
        Uint8List.fromList(utf8.encode('#EXTM3U\n#EXT-X-TARGETDURATION:6\n')),
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
