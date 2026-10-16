import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zhuying/src/app_store.dart';
import 'package:zhuying/src/models.dart';
import 'package:zhuying/src/zhuying_app.dart';
import 'package:zhuying/src/ui/catalog_pages.dart';
import 'package:zhuying/src/ui/detail_page.dart';
import 'package:zhuying/src/ui/widgets.dart';

void main() {
  testWidgets('source management shows the preconfigured sources', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(body: SourcesPage(store: AppStore())),
      ),
    );

    expect(find.text('片源管理'), findsOneWidget);
    expect(find.text('暴风点播'), findsOneWidget);
    expect(find.text('非凡影视'), findsOneWidget);
    expect(find.text('量子影视'), findsOneWidget);
  });

  testWidgets('media server form keeps the API token obscured', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(body: SourcesPage(store: AppStore())),
      ),
    );

    await tester.tap(find.byTooltip('添加媒体服务器'));
    await tester.pumpAndSettle();

    expect(find.text('添加媒体服务器'), findsOneWidget);
    expect(find.text('Jellyfin'), findsOneWidget);
    expect(find.text('Emby'), findsOneWidget);
    final tokenField = tester.widget<TextField>(find.byType(TextField).last);
    expect(tokenField.obscureText, isTrue);
  });

  testWidgets('mobile navigation has four tabs and groups personal pages', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = AppStore();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: AppShell(store: store),
      ),
    );
    await tester.pump();

    expect(find.byType(NavigationDestination), findsNWidgets(4));
    expect(find.text('首页'), findsOneWidget);
    expect(find.text('分类'), findsOneWidget);
    expect(find.text('片源'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
    expect(find.byIcon(Icons.hub_outlined), findsOneWidget);

    await tester.tap(find.text('我的'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('观看历史'), findsOneWidget);
    expect(find.text('收藏'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);

    await tester.tap(find.text('收藏'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('我的收藏'), findsOneWidget);
    expect(find.text('还没有收藏'), findsOneWidget);

    await tester.tap(find.text('历史'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('还没有观看记录'), findsOneWidget);

    await tester.tap(find.text('设置').first);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('自动播放下一集'), findsOneWidget);
    expect(find.byType(NavigationDestination), findsNWidgets(4));
    store.dispose();
  });

  testWidgets('search opens immediately with history and returns to home', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = AppStore()
      ..searchHistory = const ['Arrival', 'Spirited Away'];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: AppShell(store: store),
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(SearchField).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('最近搜索'), findsOneWidget);
    expect(find.text('Arrival'), findsOneWidget);
    expect(find.text('Spirited Away'), findsOneWidget);

    await tester.tap(find.byTooltip('删除搜索记录：Arrival'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(store.searchHistory, isNot(contains('Arrival')));
    expect(find.text('Arrival'), findsNothing);

    await tester.tap(find.byTooltip('返回'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('今晚看点什么'), findsOneWidget);
    store.dispose();
  });

  testWidgets('continue watching shows episode time and hides duplicates', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const watched = MediaItem(
      id: 'continue-1',
      title: 'Watched title',
      sourceId: 'continue-source',
      sourceName: 'Test source',
      durationSeconds: 1800,
      progressSeconds: 1080,
      progressEpisodeId: 'episode-4',
      progressEpisodeTitle: '第04集',
    );
    const duplicate = MediaItem(
      id: 'continue-duplicate',
      title: 'Watched title',
      sourceId: 'another-source',
      sourceName: 'Another source',
    );
    final store = AppStore()
      ..catalog = const [watched, duplicate]
      ..history = const [watched, duplicate];

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: AppShell(store: store),
      ),
    );
    await tester.pump();

    expect(find.text('第4集 · 剩余12分钟'), findsOneWidget);
    final progress = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator).first,
    );
    expect(progress.value, closeTo(0.6, 0.001));
    expect(find.textContaining('Watched'), findsOneWidget);

    store.dispose();
  });

  testWidgets(
    'search displays cached results alongside source failures and resets filters',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final goodSource = MediaSource(
        id: 'search-good',
        name: 'Available source',
        endpoint: 'https://good.example/api.php/provide/vod',
      );
      final failedSource = MediaSource(
        id: 'search-failed',
        name: 'Unavailable source',
        endpoint: 'https://failed.example/api.php/provide/vod',
      );
      final catalog = [
        for (var index = 0; index < 77; index++)
          MediaItem(
            id: 'search-item-$index',
            title: '猫片电影 $index',
            sourceId: goodSource.id,
            sourceName: goodSource.name,
            genre: index.isEven ? '剧情' : '动作',
          ),
      ];
      final store =
          AppStore(
              client: MockClient((request) async {
                if (request.url.host == 'failed.example') {
                  return http.Response('', 500);
                }
                return http.Response('{"list":[]}', 200);
              }),
            )
            ..sources = [goodSource, failedSource]
            ..catalog = catalog;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: SearchPage(store: store, initialQuery: '', onOpenItem: (_) {}),
        ),
      );
      await tester.enterText(find.byType(TextField), '猫片');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();

      expect(find.text('77 部影片'), findsOneWidget);
      expect(find.text('部分片源连接失败，以下为当前可用的搜索结果。'), findsOneWidget);
      expect(find.text('猫片电影 0'), findsWidgets);
      expect(find.byType(PosterCard), findsNWidgets(36));
      expect(find.textContaining('本地片库 77 部'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, '剧情'));
      await tester.pump();
      expect(find.text('39 部影片'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '电影');
      await tester.pump();
      expect(find.text('77 部影片'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, '全部类型'), findsOneWidget);
      expect(find.text('猫片电影 0'), findsWidgets);

      store.dispose();
    },
  );

  testWidgets('home places continue watching after the recommendation banner', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const watched = MediaItem(
      id: 'home-watched',
      title: 'Watched movie',
      sourceId: 'preset-bfzy',
      sourceName: 'Test source',
      durationSeconds: 100,
      progressSeconds: 40,
    );
    const featured = MediaItem(
      id: 'home-featured',
      title: 'Featured movie',
      sourceId: 'preset-bfzy',
      sourceName: 'Test source',
    );
    const recommended = MediaItem(
      id: 'home-recommended',
      title: 'Recommended movie',
      sourceId: 'preset-bfzy',
      sourceName: 'Test source',
    );
    final store = AppStore()
      ..catalog = const [featured, recommended]
      ..history = const [watched];

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: HomePage(
            store: store,
            onOpenItem: (_) {},
            onHistory: () {},
            onSearch: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    final bannerY = tester.getTopLeft(find.text('Featured movie')).dy;
    final continueY = tester.getTopLeft(find.text('接着看')).dy;
    final recommendationsY = tester.getTopLeft(find.text('为你挑选')).dy;
    expect(bannerY, lessThan(continueY));
    expect(continueY, lessThan(recommendationsY));

    store.dispose();
  });

  testWidgets('first home load shows placeholders instead of demo titles', (
    tester,
  ) async {
    final store = AppStore();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: HomePage(
            store: store,
            onOpenItem: (_) {},
            onHistory: () {},
            onSearch: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('home-hero-placeholder')), findsOneWidget);
    expect(find.text('演示片单'), findsNothing);
    expect(find.text('片源暂时没有返回影片'), findsNothing);
    store.dispose();
  });

  testWidgets('categories show common genres and support multi-select', (
    tester,
  ) async {
    final store = AppStore()
      ..catalog = [
        const MediaItem(
          id: 'category-horror',
          title: 'Horror Thriller',
          sourceId: 'local-category',
          sourceName: '测试片源',
          genre: '恐怖',
          genres: ['恐怖', '惊悚'],
          isDemo: true,
        ),
        const MediaItem(
          id: 'category-comedy',
          title: 'Comedy',
          sourceId: 'local-category',
          sourceName: '测试片源',
          genre: 'Comedy',
          genres: ['Comedy'],
          isDemo: true,
        ),
        const MediaItem(
          id: 'category-thriller',
          title: 'Thriller',
          sourceId: 'local-category',
          sourceName: '测试片源',
          genre: '惊悚',
          genres: ['惊悚'],
          isDemo: true,
        ),
      ];

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: CategoriesPage(store: store, onOpenItem: (_) {}),
        ),
      ),
    );

    expect(find.widgetWithText(ChoiceChip, '恐怖'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '伦理'), findsOneWidget);
    expect(find.text('3 部影片'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, '恐怖'));
    await tester.pump();
    expect(find.text('1 部影片'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, '惊悚'));
    await tester.pump();
    expect(find.text('2 部影片'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, '全部'));
    await tester.pump();
    expect(find.text('3 部影片'), findsOneWidget);

    final comedyChoice = find.widgetWithText(ChoiceChip, '喜剧');
    await tester.ensureVisible(comedyChoice);
    await tester.tap(comedyChoice);
    await tester.pump();
    expect(find.text('1 部影片'), findsOneWidget);

    await tester.tap(find.text('筛选 · 1'));
    await tester.pumpAndSettle();
    expect(find.text('年份'), findsOneWidget);
    expect(find.text('地区'), findsOneWidget);
    expect(find.text('片源'), findsOneWidget);
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
  });

  testWidgets('search shares multi-select genres and common category types', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store =
        AppStore(
            client: MockClient((_) async => http.Response('{"list":[]}', 200)),
          )
          ..sources = [
            const MediaSource(
              id: 'search-genres',
              name: 'Test source',
              endpoint: 'https://search-genres.example/api.php/provide/vod',
            ),
          ]
          ..catalog = const [
            MediaItem(
              id: 'search-genre-horror',
              title: 'Horror',
              sourceId: 'search-genres',
              sourceName: 'Test source',
              genres: ['恐怖', '悬疑'],
              year: '2024',
              region: '中国',
            ),
            MediaItem(
              id: 'search-genre-comedy',
              title: 'Comedy',
              sourceId: 'search-genres',
              sourceName: 'Test source',
              genres: ['喜剧'],
            ),
          ];

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: SearchPage(store: store, initialQuery: '', onOpenItem: (_) {}),
      ),
    );
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'horror');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ChoiceChip, '伦理'), findsOneWidget);
    final horror = find.widgetWithText(ChoiceChip, '恐怖');
    final mystery = find.widgetWithText(ChoiceChip, '悬疑');
    await tester.ensureVisible(horror);
    await tester.tap(horror);
    await tester.pump();
    await tester.ensureVisible(mystery);
    await tester.tap(mystery);
    await tester.pump();
    expect(find.text('1 部影片'), findsOneWidget);
    await tester.ensureVisible(find.text('筛选 · 2'));
    expect(find.text('筛选 · 2'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNothing);

    await tester.tap(find.text('筛选 · 2'));
    await tester.pumpAndSettle();
    expect(find.text('年份'), findsOneWidget);
    expect(find.text('地区'), findsOneWidget);
    expect(find.text('片源'), findsOneWidget);
    expect(find.text('全部年份'), findsOneWidget);
    expect(find.text('全部地区'), findsOneWidget);
    expect(find.text('全部片源'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<String>), findsNWidgets(3));

    await tester.tap(find.byType(DropdownButtonFormField<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('2024').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用筛选'));
    await tester.pumpAndSettle();
    expect(find.text('筛选 · 3'), findsOneWidget);

    store.dispose();
  });

  testWidgets('category grid loads the next batch when scrolling near bottom', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final source = MediaSource(
      id: 'scroll-category',
      name: 'Scroll category',
      endpoint: 'https://scroll.example/api.php/provide/vod',
    );
    final requestedPages = <int>[];
    final store = AppStore(
      client: MockClient((request) async {
        final query = request.url.queryParameters;
        if (query['at'] == 'xml') {
          return http.Response(
            '<rss><class><ty id="8">喜剧片</ty></class></rss>',
            200,
            headers: {'content-type': 'text/xml; charset=utf-8'},
          );
        }
        if (query['ac'] != 'list') {
          return http.Response('{"list":[]}', 200);
        }
        final page = int.parse(query['pg']!);
        requestedPages.add(page);
        return http.Response(
          jsonEncode({
            'pagecount': 8,
            'list': [
              for (var index = 0; index < 20; index++)
                {
                  'vod_id': 'movie-$page-$index',
                  'vod_name': 'Movie $page $index',
                  'vod_class': '喜剧片',
                  'vod_pic': 'https://images.example/$page-$index.jpg',
                },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    )..sources = [source];

    await store.refreshSources();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: CategoriesPage(store: store, onOpenItem: (_) {}),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(requestedPages, [1, 2, 3]);
    expect(find.text('继续载入分类影片'), findsNothing);
    final scrollView = tester.widget<CustomScrollView>(
      find.byType(CustomScrollView).first,
    );
    final position = scrollView.controller!.position;
    await tester.drag(
      find.byType(CustomScrollView).first,
      Offset(0, -position.maxScrollExtent - 800),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(requestedPages.take(5), [1, 2, 3, 4, 5]);
    expect(requestedPages.length.isOdd, isTrue);
    expect(find.byType(PosterCard), findsWidgets);
    store.dispose();
  });

  testWidgets('category zero-results can load later catalog pages', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    final source = MediaSource(
      id: 'category-paging',
      name: '分类分页源',
      endpoint: 'https://media.example/api.php/provide/vod',
    );
    final store = AppStore(
      client: MockClient((request) async {
        if (request.url.queryParameters['at'] == 'xml') {
          return http.Response(
            '<rss><class><ty id="8">喜剧片</ty></class></rss>',
            200,
          );
        }
        if (request.url.queryParameters['t'] != null) {
          return http.Response(
            jsonEncode({
              'pagecount': 1,
              'list': [
                {
                  'vod_id': 'comedy-1',
                  'vod_name': 'Comedy Film',
                  'type_name': '电影片',
                  'vod_pic': 'https://images.example/comedy.jpg',
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (request.url.queryParameters['ac'] != 'list') {
          return http.Response(
            jsonEncode({'list': const []}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        final page = int.parse(request.url.queryParameters['pg']!);
        final rows = page == 1
            ? [
                for (var index = 0; index < 20; index++)
                  {
                    'vod_id': 'action-$index',
                    'vod_name': 'Action $index',
                    'type_name': '动作',
                    'vod_pic': 'https://images.example/$index.jpg',
                  },
              ]
            : [
                {
                  'vod_id': 'comedy-1',
                  'vod_name': 'Comedy Film',
                  'type_name': 'Comedy',
                  'vod_pic': 'https://images.example/comedy.jpg',
                },
              ];
        return http.Response(
          jsonEncode({'pagecount': 2, 'list': rows}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    )..sources = [source];

    await store.refreshSources();
    expect(
      store.sources.single.health,
      SourceHealth.available,
      reason: store.sources.single.statusMessage,
    );
    expect(store.categoryMedia, hasLength(20));
    expect(store.hasMoreCatalog, isTrue);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: AnimatedBuilder(
            animation: store,
            builder: (context, _) =>
                CategoriesPage(store: store, onOpenItem: (_) {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final comedyFilter = find.widgetWithText(ChoiceChip, '喜剧');
    await tester.ensureVisible(comedyFilter);
    await tester.tap(comedyFilter);
    await tester.pump();
    expect(tester.widget<ChoiceChip>(comedyFilter).selected, isTrue);
    await tester.pumpAndSettle();
    expect(find.text('1 部影片'), findsOneWidget);
    expect(find.text('Comedy Film'), findsWidgets);
    store.dispose();
  });

  testWidgets('player opens in a 16:9 inline layout with details below', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = AppStore()
      ..catalog = const [
        MediaItem(
          id: 'player-related',
          title: 'Related title',
          sourceId: 'player-test',
          sourceName: '测试线路',
          genre: '悬疑',
        ),
      ];
    const item = MediaItem(
      id: 'player-item',
      title: 'Player title',
      sourceId: 'player-test',
      sourceName: '测试线路',
      year: '2025',
      genre: '悬疑',
      rating: '8.6',
      description: '剧情简介内容',
      episodes: [
        MediaEpisode(title: '第01集', url: 'https://media.example/one.mp4'),
        MediaEpisode(title: '第02集', url: 'https://media.example/two.mp4'),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: PlayerPage(
          store: store,
          item: item,
          episode: item.episodes.first,
        ),
      ),
    );
    await tester.pump();

    final frame = tester.getRect(find.byType(AspectRatio).first);
    expect(frame.width, closeTo(390, 1));
    expect(frame.height, closeTo(frame.width * 9 / 16, 1));
    expect(find.text('Player title'), findsOneWidget);
    expect(find.text('正在播放  ·  第01集'), findsOneWidget);
    expect(find.text('评分 8.6'), findsOneWidget);
    expect(find.text('收藏'), findsOneWidget);
    expect(find.text('追剧'), findsOneWidget);
    expect(find.text('切换线路'), findsOneWidget);
    expect(find.text('下载'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, '第01集'), findsOneWidget);

    await tester.tap(find.text('追剧'));
    await tester.pump();
    expect(find.text('已追剧'), findsOneWidget);
    expect(store.follows, contains(item.id));

    store.dispose();
  });

  testWidgets('sensor rotation switches the player between inline and focus', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (_) async => null);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = AppStore();
    const item = MediaItem(
      id: 'rotation-player-item',
      title: 'Rotation player',
      sourceId: 'rotation-test',
      sourceName: '测试线路',
      episodes: [MediaEpisode(title: '第01集', url: 'not-a-playback-url')],
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: PlayerPage(
          store: store,
          item: item,
          episode: item.episodes.first,
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('player-focus-layout')), findsNothing);

    tester.view.physicalSize = const Size(844, 390);
    tester.binding.handleMetricsChanged();
    await tester.pump();
    expect(find.byKey(const ValueKey('player-focus-layout')), findsOneWidget);

    tester.view.physicalSize = const Size(390, 844);
    tester.binding.handleMetricsChanged();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('player-focus-layout')), findsNothing);

    store.dispose();
  });

  testWidgets(
    'detail poster stays as the player hero through loading and back',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final store = AppStore();
      const item = MediaItem(
        id: 'hero-roundtrip-item',
        title: 'Hero roundtrip title',
        sourceId: 'demo-source',
        sourceName: 'Test source',
        episodes: [MediaEpisode(title: '第01集', url: 'not-a-playback-url')],
        isDemo: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: MediaDetailsPage(store: store, item: item),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('立即播放'));
      await tester.pumpAndSettle();

      expect(find.text('播放地址无效，请更换片源后重试'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) => widget is Hero && widget.tag == item.id,
        ),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('返回'));
      await tester.pumpAndSettle();
      expect(find.text('Hero roundtrip title'), findsOneWidget);
      expect(find.text('立即播放'), findsOneWidget);

      store.dispose();
    },
  );
}
