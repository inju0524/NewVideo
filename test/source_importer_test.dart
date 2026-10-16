import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
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
