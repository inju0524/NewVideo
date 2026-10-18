import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zhuying/src/app_store.dart';
import 'package:zhuying/src/models.dart';
import 'package:zhuying/src/source_importer.dart';
import 'package:zhuying/src/theme/app_theme.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  test(
    'search history is deduplicated, bounded, removable, and persistent',
    () async {
      final store = AppStore();
      await store.addSearchTerm('  Arrival  ');
      await store.addSearchTerm('arrival');
      for (var index = 0; index < 12; index++) {
        await store.addSearchTerm('term $index');
      }

      expect(store.searchHistory, hasLength(10));
      expect(store.searchHistory.first, 'term 11');
      expect(store.searchHistory, isNot(contains('Arrival')));

      await store.removeSearchTerm('TERM 10');
      expect(store.searchHistory, isNot(contains('term 10')));
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getStringList('zhuying.searchHistory.v1'),
        store.searchHistory,
      );

      await store.clearSearchHistory();
      expect(store.searchHistory, isEmpty);
      expect(preferences.getStringList('zhuying.searchHistory.v1'), isNull);
      store.dispose();
    },
  );

  test(
    'built-in theme selection is persistent and validates theme ids',
    () async {
      final store = AppStore();
      await store.setTheme('mitsuri');

      expect(store.themeId, 'mitsuri');
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('zhuying.theme.v1'), 'mitsuri');
      store.dispose();

      final restored = AppStore();
      await restored.initialize(refresh: false);
      expect(restored.themeId, 'mitsuri');
      expect(
        ZhuyingThemes.byId(restored.themeId).primary,
        ZhuyingThemes.mitsuri.primary,
      );

      await restored.setTheme('theme-that-does-not-exist');
      expect(restored.themeId, 'default');
      expect(
        ZhuyingThemes.byId(restored.themeId).primary,
        ZhuyingThemes.defaultTheme.primary,
      );
      expect(preferences.getString('zhuying.theme.v1'), 'default');

      await restored.setTheme('cinema-light');
      expect(restored.themeId, 'cinema-light');
      expect(ZhuyingThemes.byId(restored.themeId).isLight, isTrue);
      expect(preferences.getString('zhuying.theme.v1'), 'cinema-light');
      restored.dispose();

      final lightRestored = AppStore();
      await lightRestored.initialize(refresh: false);
      expect(lightRestored.themeId, 'cinema-light');
      expect(ZhuyingThemes.byId(lightRestored.themeId).isLight, isTrue);
      lightRestored.dispose();
    },
  );

  test(
    'CMS list and detail requests retain imported authentication headers',
    () async {
      final source = MediaSource(
        id: 'cms-auth-test',
        name: 'Private CMS',
        endpoint: 'https://media.example/api.php/provide/vod',
        requiresAuth: true,
      );
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        if (request.url.queryParameters['ac'] == 'list') {
          return http.Response(
            jsonEncode({
              'list': [
                {'vod_id': '7', 'vod_name': 'Private movie'},
              ],
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'list': [
              {
                'vod_id': '7',
                'vod_name': 'Private movie',
                'vod_play_url': 'one\$https://media.example/one.m3u8',
              },
            ],
          }),
          200,
        );
      });
      final store = AppStore(client: client);
      store.sources = [source];
      await store.addImport(
        SourceImportResult(
          sources: [source],
          headersBySourceId: {
            source.id: {'X-Subscription': 'local-secret'},
          },
        ),
      );

      await store.refreshSources();
      final details = await store.loadDetails(
        store.catalog.singleWhere((item) => item.sourceId == source.id),
      );
      final preferences = await SharedPreferences.getInstance();
      final headers = await store.requestHeaders(source.id);

      expect(details.episodes.single.url, 'https://media.example/one.m3u8');
      expect(requests.map((request) => request.headers['X-Subscription']), [
        'local-secret',
        'local-secret',
      ]);
      expect(headers['X-Subscription'], 'local-secret');
      expect(
        preferences.getString('zhuying.sources.v1'),
        isNot(contains('local-secret')),
      );
      store.dispose();
    },
  );

  test('web source requests are routed through the local proxy', () async {
    final source = MediaSource(
      id: 'cms-web-proxy-test',
      name: 'Web CMS',
      endpoint: 'https://media.example/api.php/provide/vod',
    );
    final requests = <http.Request>[];
    final store = AppStore(
      useWebProxy: true,
      webProxyEndpoint: Uri.parse('http://127.0.0.1:8124/proxy'),
      client: MockClient((request) async {
        requests.add(request);
        final target = Uri.parse(request.url.queryParameters['url']!);
        expect(target.host, 'media.example');
        if (target.queryParameters['ac'] == 'list') {
          expect(target.queryParameters['pg'], '1');
          return http.Response(
            jsonEncode({
              'list': [
                {'vod_id': '1', 'vod_name': 'Proxy movie'},
              ],
            }),
            200,
          );
        }
        expect(target.queryParameters['ac'], 'detail');
        expect(target.queryParameters['ids'], '1');
        return http.Response(
          jsonEncode({
            'list': [
              {
                'vod_id': '1',
                'vod_name': 'Proxy movie',
                'vod_pic': 'https://images.example/poster.jpg',
              },
            ],
          }),
          200,
        );
      }),
    );
    store.sources = [source];

    await store.refreshSources();

    expect(requests, hasLength(2));
    expect(
      requests.every((request) => request.url.host == '127.0.0.1'),
      isTrue,
    );
    expect(requests.every((request) => request.url.path == '/proxy'), isTrue);
    expect(store.sources.single.health, SourceHealth.available);
    expect(store.catalog.any((item) => item.title == 'Proxy movie'), isTrue);
    final posterUrl = Uri.parse(store.catalog.single.posterUrl);
    expect(posterUrl.host, '127.0.0.1');
    expect(posterUrl.path, '/proxy');
    expect(
      posterUrl.queryParameters['url'],
      'https://images.example/poster.jpg',
    );
    store.dispose();
  });

  test('web playback URLs are routed through the local proxy', () {
    final store = AppStore(
      useWebProxy: true,
      webProxyEndpoint: Uri.parse('http://127.0.0.1:8124/proxy'),
    );

    final proxyUrl = Uri.parse(
      store.playbackUrl('https://media.example/video/index.m3u8?token=abc'),
    );

    expect(proxyUrl.path, '/proxy');
    expect(
      proxyUrl.queryParameters['url'],
      'https://media.example/video/index.m3u8?token=abc',
    );
    expect(store.playbackUrl(proxyUrl.toString()), proxyUrl.toString());
    store.dispose();
  });

  test(
    'CMS refresh uses details to fill poster images missing from list rows',
    () async {
      final source = MediaSource(
        id: 'cms-poster-test',
        name: 'Poster CMS',
        endpoint: 'https://media.example/api.php/provide/vod',
      );
      final requests = <http.Request>[];
      final store = AppStore(
        client: MockClient((request) async {
          requests.add(request);
          if (request.url.queryParameters['ac'] == 'list') {
            return http.Response(
              jsonEncode({
                'list': [
                  {'vod_id': '12', 'vod_name': 'Poster movie'},
                ],
              }),
              200,
            );
          }
          return http.Response(
            jsonEncode({
              'list': [
                {
                  'vod_id': '12',
                  'vod_name': 'Poster movie',
                  'vod_pic': 'https://images.example/poster-12.jpg',
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      store.sources = [source];

      await store.refreshSources();

      expect(requests, hasLength(2));
      expect(requests.last.url.queryParameters['ac'], 'detail');
      expect(requests.last.url.queryParameters['ids'], '12');
      expect(
        store.catalog.single.posterUrl,
        'https://images.example/poster-12.jpg',
      );
      store.dispose();
    },
  );

  test(
    'source catalog replaces the demo catalog when sources return items',
    () async {
      final source = MediaSource(
        id: 'cms-real-catalog-test',
        name: 'Real CMS',
        endpoint: 'https://media.example/api.php/provide/vod',
      );
      final store = AppStore(
        client: MockClient((_) async {
          return http.Response(
            jsonEncode({
              'list': [
                {'vod_id': '1', 'vod_name': 'Real movie'},
              ],
            }),
            200,
          );
        }),
      );
      store.sources = [source];

      await store.refreshSources();

      expect(store.catalog.map((item) => item.title), ['Real movie']);
      expect(store.allMedia.first.title, 'Real movie');
      expect(store.allMedia.any((item) => item.isDemo), isFalse);
      store.dispose();
    },
  );

  test('category pagination can load every reported CMS page', () async {
    final source = MediaSource(
      id: 'cms-pages-test',
      name: 'Paged CMS',
      endpoint: 'https://media.example/api.php/provide/vod',
    );
    final store = AppStore(
      client: MockClient((request) async {
        final query = request.url.queryParameters;
        if (query['ac'] == 'list') {
          final page = int.parse(query['pg']!);
          final rows = [
            for (var index = 0; index < (page == 1 ? 20 : 2); index++)
              {'vod_id': '${page}_$index', 'vod_name': 'Movie ${page}_$index'},
          ];
          return http.Response(jsonEncode({'pagecount': 2, 'list': rows}), 200);
        }
        return http.Response(jsonEncode({'list': const []}), 200);
      }),
    );
    store.sources = [source];

    await store.refreshSources();

    expect(store.catalog, hasLength(20));
    expect(store.hasMoreCatalog, isTrue);

    await store.loadMoreCatalog();

    expect(store.catalog, hasLength(22));
    expect(store.catalog.any((item) => item.id == '${source.id}:2_1'), isTrue);
    store.dispose();
  });

  test(
    'CMS categories use source-specific type IDs and independent pages',
    () async {
      final first = MediaSource(
        id: 'cms-category-first',
        name: 'First CMS',
        endpoint: 'https://first.example/api.php/provide/vod',
      );
      final second = MediaSource(
        id: 'cms-category-second',
        name: 'Second CMS',
        endpoint: 'https://second.example/api.php/provide/vod',
      );
      final categoryRequests = <Uri>[];
      final store = AppStore(
        client: MockClient((request) async {
          final query = request.url.queryParameters;
          if (query['at'] == 'xml') {
            final id = request.url.host == 'first.example' ? '41' : '907';
            return http.Response(
              '<rss><class><ty id="$id">恐怖片</ty></class></rss>',
              200,
              headers: {'content-type': 'text/xml; charset=utf-8'},
            );
          }
          if (query['t'] != null) {
            categoryRequests.add(request.url);
            return http.Response(
              jsonEncode({
                'pagecount': 2,
                'list': [
                  for (var index = 0; index < 20; index++)
                    {
                      'vod_id': '${query['t']}-${query['pg']}-$index',
                      'vod_name':
                          'Horror ${query['t']} page ${query['pg']} $index',
                      'type_name': '电影片',
                      'vod_pic': 'https://images.example/$index.jpg',
                    },
                ],
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return http.Response(
            jsonEncode({
              'pagecount': 1,
              'list': [
                {
                  'vod_id': 'home-${request.url.host}',
                  'vod_name': 'Home item',
                  'type_name': '剧情片',
                  'vod_pic': 'https://images.example/home.jpg',
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      )..sources = [first, second];

      await store.refreshSources();
      await store.loadMoreCatalog(genres: const ['恐怖']);

      expect(categoryRequests.map((uri) => uri.queryParameters['t']).toSet(), {
        '41',
        '907',
      });
      expect(
        categoryRequests.every((uri) => uri.queryParameters['pg'] == '1'),
        isTrue,
      );
      expect(
        store.categoryMedia.where((item) => item.genreLabels.contains('恐怖')),
        hasLength(40),
      );
      expect(store.hasMoreCategoryPages(genres: const ['恐怖']), isTrue);

      await store.loadMoreCatalog(genres: const ['恐怖']);

      expect(
        categoryRequests.where((uri) => uri.queryParameters['pg'] == '2'),
        hasLength(2),
      );
      expect(
        store.categoryMedia.where((item) => item.genreLabels.contains('恐怖')),
        hasLength(80),
      );
      store.dispose();
    },
  );

  test('category pages fill missing poster URLs from CMS details', () async {
    final source = MediaSource(
      id: 'cms-category-posters',
      name: 'Poster category CMS',
      endpoint: 'https://posters.example/api.php/provide/vod',
    );
    final detailRequests = <Uri>[];
    final requests = <Uri>[];
    final store = AppStore(
      client: MockClient((request) async {
        requests.add(request.url);
        final query = request.url.queryParameters;
        if (query['at'] == 'xml') {
          return http.Response(
            '<rss><class><ty id="5">恐怖片</ty></class></rss>',
            200,
            headers: {'content-type': 'text/xml; charset=utf-8'},
          );
        }
        if (query['ac'] == 'detail') {
          detailRequests.add(request.url);
          return http.Response(
            jsonEncode({
              'list': [
                {
                  'vod_id': 'missing-poster',
                  'vod_name': 'Missing poster',
                  'vod_pic': 'https://images.example/restored.jpg',
                },
              ],
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'pagecount': 1,
            'list': [
              {
                'vod_id': 'missing-poster',
                'vod_name': 'Missing poster',
                'type_name': '电影片',
              },
              {
                'vod_id': 'has-poster',
                'vod_name': 'Existing poster',
                'type_name': '电影片',
                'vod_pic': 'https://images.example/existing.jpg',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    )..sources = [source];

    await store.refreshSources();
    await store.loadMoreCatalog(genres: const ['恐怖']);

    expect(
      requests
          .where((uri) => uri.queryParameters['ac'] == 'list')
          .map((uri) => uri.queryParameters),
      contains(containsPair('t', '5')),
      reason: 'Requests: $requests',
    );
    final categoryItems = store.categoryMedia
        .where((item) => item.genreLabels.contains('恐怖'))
        .toList();
    expect(
      detailRequests,
      hasLength(1),
      reason:
          'Requests: $requests; catalog=${store.catalog.map((item) => '${item.title}:${item.posterUrl}')}; category=${categoryItems.map((item) => '${item.title}:${item.posterUrl}')}',
    );
    expect(detailRequests.single.queryParameters['ids'], 'missing-poster');
    expect(
      categoryItems
          .singleWhere((item) => item.title == 'Missing poster')
          .posterUrl,
      'https://images.example/restored.jpg',
    );
    expect(
      categoryItems
          .singleWhere((item) => item.title == 'Existing poster')
          .posterUrl,
      'https://images.example/existing.jpg',
    );
    store.dispose();
  });

  test(
    'category falls back to directory pages when CMS types are unavailable',
    () async {
      final source = MediaSource(
        id: 'cms-category-fallback',
        name: 'Fallback CMS',
        endpoint: 'https://fallback.example/api.php/provide/vod',
      );
      final requestedPages = <int>[];
      final store = AppStore(
        client: MockClient((request) async {
          final query = request.url.queryParameters;
          if (query['at'] == 'xml') {
            return http.Response('not xml', 200);
          }
          final page = int.parse(query['pg']!);
          requestedPages.add(page);
          return http.Response(
            jsonEncode({
              'pagecount': 14,
              'list': [
                {
                  'vod_id': '$page',
                  'vod_name': 'Page $page',
                  'vod_class': page >= 12 ? '喜剧片' : '动作片',
                  'vod_pic': 'https://images.example/$page.jpg',
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      )..sources = [source];

      await store.refreshSources();
      requestedPages.clear();
      await store.loadMoreCatalog(genres: const ['喜剧']);

      expect(requestedPages, [1, 2]);
      expect(
        store.categoryMedia.where((item) => item.genreLabels.contains('喜剧')),
        isEmpty,
      );
      expect(store.hasMoreCategoryPages(genres: const ['喜剧']), isTrue);

      await store.loadMoreCatalog(genres: const ['喜剧']);

      expect(requestedPages, [1, 2, 3, 4]);
      expect(
        store.categoryMedia.where((item) => item.genreLabels.contains('喜剧')),
        isEmpty,
      );

      for (var batch = 0; batch < 4; batch++) {
        await store.loadMoreCatalog(genres: const ['喜剧']);
      }

      expect(requestedPages, [for (var page = 1; page <= 12; page++) page]);
      expect(
        store.categoryMedia.where((item) => item.genreLabels.contains('喜剧')),
        hasLength(1),
      );
      store.dispose();
    },
  );

  test(
    'catalog refresh loads one fast page and category loads two more',
    () async {
      final source = MediaSource(
        id: 'cms-refresh-page-cap',
        name: 'Large CMS',
        endpoint: 'https://media.example/api.php/provide/vod',
      );
      final requestedPages = <int>[];
      final store = AppStore(
        client: MockClient((request) async {
          requestedPages.add(int.parse(request.url.queryParameters['pg']!));
          return http.Response(
            jsonEncode({
              'pagecount': 5000,
              'list': [
                {
                  'vod_id': request.url.queryParameters['pg'],
                  'vod_name': 'Page ${request.url.queryParameters['pg']}',
                  'vod_pic': 'https://images.example/poster.jpg',
                },
              ],
            }),
            200,
          );
        }),
      )..sources = [source];

      await store.refreshSources();

      expect(requestedPages, [1]);
      expect(store.catalog, hasLength(1));
      expect(store.hasMoreCatalog, isTrue);
      expect(store.sources.single.health, SourceHealth.available);

      await store.loadMoreCatalog();

      expect(requestedPages, [1, 2, 3]);
      expect(store.catalog, hasLength(3));
      store.dispose();
    },
  );

  test(
    'search publishes local matches before bounded source requests finish',
    () async {
      final source = MediaSource(
        id: 'cms-search-fast',
        name: 'Search CMS',
        endpoint: 'https://media.example/api.php/provide/vod',
      );
      final releaseRequest = Completer<void>();
      final requests = <http.Request>[];
      const cached = MediaItem(
        id: 'cms-search-fast:cached',
        title: 'Cached Sunrise',
        sourceId: 'cms-search-fast',
        sourceName: 'Search CMS',
      );
      final store =
          AppStore(
              client: MockClient((request) async {
                requests.add(request);
                await releaseRequest.future;
                return http.Response(
                  jsonEncode({
                    'pagecount': 5000,
                    'list': [
                      {
                        'vod_id': 'remote',
                        'vod_name': 'Remote Sunrise',
                        'vod_pic': 'https://images.example/remote.jpg',
                      },
                    ],
                  }),
                  200,
                );
              }),
            )
            ..sources = [source]
            ..catalog = const [cached];
      final streamedResults = <List<MediaItem>>[];
      final streamedCounts = <SearchCounts>[];
      SearchOutcome? searchOutcome;

      final search = store.search(
        'Sunrise',
        onResults: streamedResults.add,
        onCounts: streamedCounts.add,
        onComplete: (outcome) => searchOutcome = outcome,
      );

      expect(streamedResults.first.map((item) => item.id), [cached.id]);
      await Future<void>.delayed(Duration.zero);
      expect(requests, hasLength(1));
      expect(requests.single.url.queryParameters['pg'], '1');
      expect(requests.single.url.queryParameters['wd'], 'Sunrise');

      releaseRequest.complete();
      final results = await search;

      expect(results.map((item) => item.title), [
        'Cached Sunrise',
        'Remote Sunrise',
      ]);
      expect(streamedCounts.last.localMatches, 1);
      expect(streamedCounts.last.remoteMatches, 1);
      expect(searchOutcome?.localMatchCount, 1);
      expect(searchOutcome?.remoteMatchCount, 1);
      expect(requests, hasLength(1));
      store.dispose();
    },
  );

  test('source status distinguishes DNS and network failures', () async {
    final source = MediaSource(
      id: 'cms-dns-failure',
      name: 'Offline CMS',
      endpoint: 'https://offline.example/api.php/provide/vod',
    );
    final store = AppStore(
      client: MockClient(
        (_) async => throw const SocketException('Failed host lookup'),
      ),
    )..sources = [source];

    await store.refreshSources();

    expect(store.sources.single.health, SourceHealth.error);
    expect(store.sources.single.statusMessage, '网络不可达或 DNS 解析失败');
    expect(store.refreshMessage, contains('片源连接失败'));
    store.dispose();
  });

  test(
    'network resume before initialization retries a failed first refresh',
    () async {
      final source = MediaSource(
        id: 'cms-early-resume',
        name: 'Early resume CMS',
        endpoint: 'https://early-resume.example/api.php/provide/vod',
      );
      final retryFinished = Completer<void>();
      var requests = 0;
      final store = AppStore(
        client: MockClient((_) async {
          requests++;
          if (requests == 1) return http.Response('', 503);
          return http.Response(
            jsonEncode({
              'pagecount': 1,
              'list': [
                {
                  'vod_id': 'reconnected',
                  'vod_name': 'Reconnected after startup',
                  'vod_pic': 'https://images.example/reconnected.jpg',
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      )..sources = [source];
      store.addListener(() {
        if (requests == 2 &&
            !store.isRefreshing &&
            store.sources.single.health == SourceHealth.available &&
            !retryFinished.isCompleted) {
          retryFinished.complete();
        }
      });

      await store.retryUnavailableSources();
      await store.initialize();
      await retryFinished.future.timeout(const Duration(seconds: 2));

      expect(requests, 2);
      expect(store.sources.single.health, SourceHealth.available);
      expect(store.catalog.single.title, 'Reconnected after startup');
      store.dispose();
    },
  );

  test('network resume retries a failed first source refresh', () async {
    final source = MediaSource(
      id: 'cms-resume-retry',
      name: 'Resume retry CMS',
      endpoint: 'https://resume.example/api.php/provide/vod',
    );
    final availableSource = MediaSource(
      id: 'cms-resume-available',
      name: 'Already available CMS',
      endpoint: 'https://available.example/api.php/provide/vod',
    );
    final firstRequestStarted = Completer<void>();
    final releaseFirstRequest = Completer<http.Response>();
    final retryFinished = Completer<void>();
    var failedSourceRequests = 0;
    var availableSourceRequests = 0;
    final store = AppStore(
      client: MockClient((request) async {
        if (request.url.host == 'resume.example') {
          failedSourceRequests++;
          if (failedSourceRequests == 1) {
            firstRequestStarted.complete();
            return releaseFirstRequest.future;
          }
          return http.Response(
            jsonEncode({
              'pagecount': 1,
              'list': [
                {
                  'vod_id': 'reconnected',
                  'vod_name': 'Reconnected movie',
                  'vod_pic': 'https://images.example/reconnected.jpg',
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        availableSourceRequests++;
        return http.Response(
          jsonEncode({
            'pagecount': 1,
            'list': [
              {
                'vod_id': 'still-available',
                'vod_name': 'Still available movie',
                'vod_pic': 'https://images.example/still-available.jpg',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    await store.initialize(refresh: false);
    store.sources = [source, availableSource];
    store.addListener(() {
      if (failedSourceRequests == 2 &&
          !store.isRefreshing &&
          store.sources.first.health == SourceHealth.available &&
          !retryFinished.isCompleted) {
        retryFinished.complete();
      }
    });

    final initialRefresh = store.refreshSources();
    await firstRequestStarted.future;
    await store.retryUnavailableSources();
    releaseFirstRequest.complete(http.Response('', 503));
    await initialRefresh;
    await retryFinished.future.timeout(const Duration(seconds: 2));

    expect(failedSourceRequests, 2);
    expect(availableSourceRequests, 1);
    expect(store.sources.first.health, SourceHealth.available);
    expect(
      store.catalog.map((item) => item.title),
      containsAll(['Reconnected movie', 'Still available movie']),
    );

    await store.retryUnavailableSources();
    expect(failedSourceRequests, 2);
    expect(availableSourceRequests, 1);
    store.dispose();
  });

  test(
    'CMS refresh replaces cached items gradually while later pages are pending',
    () async {
      final source = MediaSource(
        id: 'cms-progressive-test',
        name: 'Progressive CMS',
        endpoint: 'https://media.example/api.php/provide/vod',
      );
      final secondPageStarted = Completer<void>();
      final releaseSecondPage = Completer<void>();
      final requests = <http.Request>[];
      final store = AppStore(
        client: MockClient((request) async {
          requests.add(request);
          final query = request.url.queryParameters;
          if (query['ac'] != 'list') {
            return http.Response(jsonEncode({'list': const []}), 200);
          }
          if (query['pg'] == '1') {
            return http.Response(
              jsonEncode({
                'pagecount': 2,
                'list': [
                  {
                    'vod_id': 'first',
                    'vod_name': 'First page movie',
                    'vod_pic': 'https://images.example/first.jpg',
                  },
                ],
              }),
              200,
            );
          }
          secondPageStarted.complete();
          await releaseSecondPage.future;
          return http.Response(
            jsonEncode({
              'pagecount': 2,
              'list': [
                {
                  'vod_id': 'second',
                  'vod_name': 'Second page movie',
                  'vod_pic': 'https://images.example/second.jpg',
                },
              ],
            }),
            200,
          );
        }),
      );
      store.sources = [source];
      store.homeSnapshot = const [
        MediaItem(
          id: 'cms-progressive-test:old',
          title: 'Cached movie',
          sourceId: 'cms-progressive-test',
          sourceName: 'Progressive CMS',
        ),
      ];

      await store.refreshSources();
      expect(store.catalog.map((item) => item.title), ['First page movie']);

      final loadMore = store.loadMoreCatalog();
      await secondPageStarted.future;

      expect(store.isLoadingMoreCatalog, isTrue);
      expect(store.catalog.map((item) => item.title), ['First page movie']);
      expect(store.homeMedia.map((item) => item.title), [
        'First page movie',
        'Cached movie',
      ]);
      expect(
        requests.where(
          (request) => request.url.queryParameters['ac'] == 'detail',
        ),
        isEmpty,
      );

      releaseSecondPage.complete();
      await loadMore;

      expect(store.catalog.map((item) => item.title), [
        'First page movie',
        'Second page movie',
      ]);
      expect(
        store.homeSnapshot.map((item) => item.title),
        containsAll(['First page movie', 'Cached movie']),
      );
      store.dispose();
    },
  );

  test(
    'source variant search finds the same title in another source',
    () async {
      final current = MediaSource(
        id: 'cms-current-source',
        name: 'Current CMS',
        endpoint: 'https://current.example/api.php/provide/vod',
      );
      final alternate = MediaSource(
        id: 'cms-alternate-source',
        name: 'Alternate CMS',
        endpoint: 'https://alternate.example/api.php/provide/vod',
      );
      final store = AppStore(
        client: MockClient((request) async {
          final host = request.url.host;
          final query = request.url.queryParameters;
          if (query['ac'] == 'list' && host == 'current.example') {
            return http.Response(
              jsonEncode({
                'list': [
                  {'vod_id': '1', 'vod_name': 'Same Film'},
                ],
              }),
              200,
            );
          }
          if (query['ac'] == 'list' && host == 'alternate.example') {
            return http.Response(
              jsonEncode({
                'list': [
                  {'vod_id': '2', 'vod_name': 'Same Film [HD]'},
                ],
              }),
              200,
            );
          }
          if (query['ac'] == 'detail' && host == 'alternate.example') {
            return http.Response(
              jsonEncode({
                'list': [
                  {
                    'vod_id': '2',
                    'vod_name': 'Same Film [HD]',
                    'vod_play_url':
                        '第01集\$https://alternate.example/video.m3u8',
                  },
                ],
              }),
              200,
            );
          }
          return http.Response(jsonEncode({'list': const []}), 200);
        }),
      );
      store.sources = [current, alternate];
      await store.refreshSources();
      final currentItem = store.catalog.singleWhere(
        (item) => item.sourceId == current.id,
      );

      final variants = await store.findSourceVariants(currentItem);

      expect(variants.map((item) => item.sourceId), [alternate.id]);
      expect(
        store.sources
            .where((source) => source.id == alternate.id)
            .single
            .statusMessage,
        '1 部影片',
      );
      store.dispose();
    },
  );

  test(
    'Jellyfin series details produce authenticated episode streams',
    () async {
      final requests = <http.Request>[];
      final store = AppStore(
        client: MockClient((request) async {
          requests.add(request);
          if (request.url.path.endsWith('/Shows/series-1/Episodes')) {
            return http.Response(
              jsonEncode({
                'Items': [
                  {
                    'Id': 'episode-2',
                    'Name': 'Second light',
                    'ParentIndexNumber': 1,
                    'IndexNumber': 2,
                  },
                  {
                    'Id': 'episode-1',
                    'Name': 'First light',
                    'ParentIndexNumber': 1,
                    'IndexNumber': 1,
                  },
                ],
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/Items')) {
            return http.Response(
              jsonEncode({
                'Items': [
                  {
                    'Id': 'series-1',
                    'Name': 'Northern lights',
                    'Type': 'Series',
                    'ImageTags': {'Primary': 'poster-tag'},
                  },
                ],
              }),
              200,
            );
          }
          return http.Response('missing', 404);
        }),
      );
      await store.initialize(refresh: false);
      await store.addMediaServer(
        name: 'Home library',
        endpoint: 'http://jellyfin.example:8096/jellyfin',
        kind: SourceKind.jellyfin,
        token: 'server-secret',
      );
      final source = store.sources.singleWhere(
        (value) => value.kind == SourceKind.jellyfin,
      );
      final details = await store.loadDetails(
        MediaItem(
          id: '${source.id}:series-1',
          title: 'Northern lights',
          sourceId: source.id,
          sourceName: source.name,
          remarks: '剧集',
        ),
      );
      final storage = const FlutterSecureStorage();
      final storedHeaders = await storage.read(
        key: 'zhuying.source.${source.id}.headers',
      );
      final preferences = await SharedPreferences.getInstance();

      expect(details.episodes.map((episode) => episode.title), [
        'S1 E1 · First light',
        'S1 E2 · Second light',
      ]);
      expect(
        details.episodes.first.url,
        'http://jellyfin.example:8096/jellyfin/Videos/episode-1/stream?Static=true',
      );
      final serverRequests = requests.where(
        (request) => request.url.host == 'jellyfin.example',
      );
      expect(serverRequests, isNotEmpty);
      expect(
        serverRequests.every(
          (request) => request.headers['X-Emby-Token'] == 'server-secret',
        ),
        isTrue,
      );
      expect(jsonDecode(storedHeaders!)['X-Emby-Token'], 'server-secret');
      expect(
        preferences.getString('zhuying.sources.v1'),
        isNot(contains('server-secret')),
      );
      store.dispose();
    },
  );

  test(
    'source refresh preserves disabled state from saved preferences',
    () async {
      final savedSource = defaultSources.first.copyWith(enabled: false);
      SharedPreferences.setMockInitialValues({
        'zhuying.sources.v1': jsonEncode([savedSource.toJson()]),
      });
      final store = AppStore(
        client: MockClient((_) async => http.Response('', 200)),
      );

      await store.initialize(refresh: false);
      await store.refreshSources();

      expect(
        store.sources
            .firstWhere((source) => source.id == savedSource.id)
            .enabled,
        isFalse,
      );
      expect(store.allMedia, isEmpty);
      store.dispose();
    },
  );

  test('initialization restores a bounded home snapshot separately', () async {
    final source = MediaSource(
      id: 'home-cache-source',
      name: 'Home cache source',
      endpoint: 'https://media.example/api.php/provide/vod',
    );
    final cachedItems = [
      for (var index = 0; index < 35; index++)
        MediaItem(
          id: '${source.id}:$index',
          title: 'Cached movie $index',
          sourceId: source.id,
          sourceName: source.name,
        ),
    ];
    SharedPreferences.setMockInitialValues({
      'zhuying.sources.v1': jsonEncode([source.toJson()]),
      'zhuying.homeSnapshot.v1': encodeMediaList(cachedItems),
    });
    final store = AppStore();

    await store.initialize(refresh: false);

    expect(store.homeSnapshot, hasLength(30));
    expect(store.homeMedia, hasLength(30));
    expect(store.catalog, isEmpty);
    expect(
      store.allMedia.any((item) => item.title.startsWith('Cached')),
      isFalse,
    );
    expect(store.categoryMedia, hasLength(30));
    expect(
      store.categoryMedia.every((item) => item.title.startsWith('Cached')),
      isTrue,
    );
    store.dispose();
  });

  test('failed source refresh keeps the last home snapshot', () async {
    final source = MediaSource(
      id: 'home-cache-failure-source',
      name: 'Home cache source',
      endpoint: 'https://media.example/api.php/provide/vod',
    );
    final savedSources = [
      for (final preset in defaultSources) preset.copyWith(enabled: false),
      source,
    ];
    const cachedItem = MediaItem(
      id: 'home-cache-failure-source:old',
      title: 'Last available title',
      sourceId: 'home-cache-failure-source',
      sourceName: 'Home cache source',
    );
    SharedPreferences.setMockInitialValues({
      'zhuying.sources.v1': jsonEncode(
        savedSources.map((value) => value.toJson()).toList(),
      ),
      'zhuying.homeSnapshot.v1': encodeMediaList([cachedItem]),
    });
    final store = AppStore(
      client: MockClient((_) async => http.Response('offline', 503)),
    );
    await store.initialize(refresh: false);

    await store.refreshSources();

    expect(store.homeMedia.map((item) => item.title), ['Last available title']);
    final preferences = await SharedPreferences.getInstance();
    final savedHome = jsonDecode(
      preferences.getString('zhuying.homeSnapshot.v1')!,
    ) as List<dynamic>;
    expect(savedHome, hasLength(1));
    store.dispose();
  });

  test(
    'successful refresh updates the home snapshot without truncating catalog',
    () async {
      final source = MediaSource(
        id: 'home-cache-success-source',
        name: 'Home source',
        endpoint: 'https://media.example/api.php/provide/vod',
      );
      final store = AppStore(
        client: MockClient((request) async {
          if (request.url.queryParameters['ac'] == 'list') {
            return http.Response(
              jsonEncode({
                'pagecount': 1,
                'list': [
                  for (var index = 0; index < 35; index++)
                    {
                      'vod_id': '$index',
                      'vod_name': 'Fresh movie $index',
                      'vod_pic': 'https://images.example/$index.jpg',
                    },
                ],
              }),
              200,
            );
          }
          return http.Response(jsonEncode({'list': const []}), 200);
        }),
      )..sources = [source];

      await store.refreshSources();

      expect(store.catalog, hasLength(35));
      expect(store.homeSnapshot, hasLength(30));
      expect(store.homeMedia, hasLength(30));
      final preferences = await SharedPreferences.getInstance();
      final savedHome = jsonDecode(
        preferences.getString('zhuying.homeSnapshot.v1')!,
      ) as List<dynamic>;
      expect(savedHome, hasLength(30));
      store.dispose();
    },
  );

  test(
    'initialization migrates older saved sources to include new defaults',
    () async {
      SharedPreferences.setMockInitialValues({
        'zhuying.sources.v1': jsonEncode([
          for (final source in defaultSources.take(3)) source.toJson(),
        ]),
      });
      final store = AppStore();

      await store.initialize(refresh: false);
      final preferences = await SharedPreferences.getInstance();
      final saved = jsonDecode(
        preferences.getString('zhuying.sources.v1')!,
      ) as List<dynamic>;

      expect(store.sources.length, defaultSources.length);
      expect(
        store.sources.map((source) => source.id),
        contains('public-360zy'),
      );
      expect(saved.length, defaultSources.length);
      store.dispose();
    },
  );

  test(
    'initialization migrates saved public source state by endpoint',
    () async {
      final oldGuangsu = MediaSource(
        id: 'public-guangsu',
        name: '光速资源',
        endpoint: 'https://api.guangsuapi.com/api.php/provide/vod/from/gsm3u8',
        requiresAuth: true,
        enabled: true,
      );
      final oldUku = MediaSource(
        id: 'public-uku',
        name: 'U酷资源',
        endpoint: 'https://api.ukuapi.com/api.php/provide/vod/',
        requiresAuth: true,
        enabled: true,
      );
      SharedPreferences.setMockInitialValues({
        'zhuying.sources.v1': jsonEncode([
          oldGuangsu.toJson(),
          oldUku.toJson(),
        ]),
      });
      const storage = FlutterSecureStorage();
      await storage.write(
        key: 'zhuying.source.public-guangsu.headers',
        value: jsonEncode({'X-Subscription': 'keep-me'}),
      );
      await storage.write(
        key: 'zhuying.source.public-uku.headers',
        value: jsonEncode({'X-Subscription': 'do-not-move'}),
      );
      final store = AppStore();

      await store.initialize(refresh: false);

      final guangsu = store.sources.singleWhere(
        (source) => source.id == 'public-guangsu',
      );
      final uku = store.sources.singleWhere(
        (source) => source.id == 'public-uku88',
      );
      expect(guangsu.enabled, isTrue);
      expect(guangsu.endpoint, contains('api.guangsuapi.com'));
      expect(uku.enabled, isFalse);
      expect(uku.requiresAuth, isFalse);
      expect(await store.requestHeaders('public-guangsu'), {
        'X-Subscription': 'keep-me',
      });
      expect(await store.requestHeaders('public-uku88'), isEmpty);
      expect(
        await storage.read(key: 'zhuying.source.public-uku.headers'),
        isNull,
      );
      store.dispose();
    },
  );

  test(
    'catalog de-duplicates sources by normalized title and edition',
    () async {
      const sourceA = 'dedup-source-a';
      const sourceB = 'dedup-source-b';
      const sourceC = 'dedup-source-c';
      final store = AppStore()
        ..sources = [
          for (final entry in [
            (sourceA, 'Source A'),
            (sourceB, 'Source B'),
            (sourceC, 'Source C'),
          ])
            MediaSource(
              id: entry.$1,
              name: entry.$2,
              endpoint: 'https://${entry.$1}.example/api.php/provide/vod',
            ),
        ]
        ..catalog = const [
          MediaItem(
            id: '$sourceA:1',
            title: 'The Same Film (2020) [HD]',
            sourceId: sourceA,
            sourceName: 'Source A',
          ),
          MediaItem(
            id: '$sourceB:2',
            title: 'The Same Film',
            sourceId: sourceB,
            sourceName: 'Source B',
            year: '2020',
          ),
          MediaItem(
            id: '$sourceC:3',
            title: 'The Same Film',
            sourceId: sourceC,
            sourceName: 'Source C',
            year: '2024',
          ),
          MediaItem(
            id: '$sourceC:4',
            title: 'The Same Film 第02季',
            sourceId: sourceC,
            sourceName: 'Source C',
            year: '2024',
          ),
          MediaItem(
            id: '$sourceB:5',
            title: 'The Same Film',
            sourceId: sourceB,
            sourceName: 'Source B',
          ),
        ];

      expect(store.allMedia, hasLength(4));
      expect(
        store.allMedia.map((item) => item.id),
        contains(anyOf('$sourceA:1', '$sourceB:2')),
      );
      expect(store.allMedia.map((item) => item.id), contains('$sourceB:5'));
      store.dispose();
    },
  );
}
