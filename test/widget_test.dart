import 'dart:async';
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:zhuying/src/app_store.dart';
import 'package:zhuying/src/models.dart';
import 'package:zhuying/src/theme/app_theme.dart';
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

  testWidgets('public repository picker only exposes importable repositories', (
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
        home: Scaffold(body: SourcesPage(store: store)),
      ),
    );
    await tester.tap(find.byTooltip('导入公开片源仓'));
    await tester.pumpAndSettle();

    expect(find.text('导入公开片源仓'), findsOneWidget);
    expect(find.text('哈基米'), findsOneWidget);
    expect(find.text('分享'), findsOneWidget);
    expect(find.text('饭太硬'), findsNothing);
    expect(find.text('全选'), findsOneWidget);
    expect(find.text('导入 0 个'), findsOneWidget);
    await tester.tap(find.text('哈基米'));
    await tester.pump();
    expect(find.text('导入 1 个'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    store.dispose();
  });

  testWidgets(
    'app retries failed sources after returning from a permission prompt',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final source = MediaSource(
        id: 'app-resume-retry',
        name: 'Resume retry source',
        endpoint: 'https://resume.example/api.php/provide/vod',
      );
      var requestCount = 0;
      final store = AppStore(
        client: MockClient((request) async {
          requestCount++;
          if (requestCount == 1) return http.Response('', 503);
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
        }),
      )..sources = [source];

      await tester.pumpWidget(ZhuyingApp(store: store));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(store.sources.single.health, SourceHealth.error);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(requestCount, 2);
      expect(store.sources.single.health, SourceHealth.available);
      expect(store.catalog.single.title, 'Reconnected movie');
    },
  );

  testWidgets('app restores and switches the active brand with its theme', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'zhuying.theme.v1': 'mitsuri'});
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = AppStore()..sources = [];
    await tester.pumpWidget(ZhuyingApp(store: store));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));

    expect(store.themeId, 'mitsuri');
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).title, '我爱看电视');
    final mitsuriLogo = tester.widget<Image>(
      find.byKey(const ValueKey('brand-logo-mitsuri-hero')),
    );
    expect(
      (mitsuriLogo.image as AssetImage).assetName,
      'assets/branding/mitsuri-logo-transparent.png',
    );

    await store.setTheme('default');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));

    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).title, '玄览');
    expect(
      tester
          .widget<Image>(find.byKey(const ValueKey('brand-logo-default')))
          .image,
      isA<AssetImage>(),
    );
    expect(
      (tester
                  .widget<Image>(
                    find.byKey(const ValueKey('brand-logo-default')),
                  )
                  .image
              as AssetImage)
          .assetName,
      'assets/branding/xuanlan-logo.jpg',
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('Mitsuri compact shell extends themed pages behind the dock', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'zhuying.theme.v1': 'mitsuri'});
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = AppStore()..sources = [];
    await tester.pumpWidget(ZhuyingApp(store: store));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));

    final shell = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(shell.extendBody, isTrue);
    final shellSafeArea = tester.widget<SafeArea>(find.byType(SafeArea).first);
    expect(shellSafeArea.bottom, isFalse);

    await tester.tap(find.text('分类'));
    await tester.pump(const Duration(milliseconds: 300));
    final categoryTail = tester.widget<SliverToBoxAdapter>(
      find.byType(SliverToBoxAdapter).last,
    );
    expect((categoryTail.child as SizedBox).height, 148);

    await store.setTheme('default');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    final defaultShell = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(defaultShell.extendBody, isFalse);
    final defaultSafeArea = tester.widget<SafeArea>(
      find.byType(SafeArea).first,
    );
    expect(defaultSafeArea.bottom, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('page dock clearance is optional and theme scoped', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = AppStore()..sources = [];
    Future<void> pumpPage(Widget page, ZhuyingThemeDefinition theme) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme.toThemeData().copyWith(
            extensions: [ZhuyingThemeExtension(theme)],
          ),
          home: Scaffold(body: page),
        ),
      );
    }

    await pumpPage(
      CategoriesPage(store: store, onOpenItem: (_) {}),
      ZhuyingThemes.defaultTheme,
    );
    final defaultCategoryTail = tester.widget<SliverToBoxAdapter>(
      find.byType(SliverToBoxAdapter).last,
    );
    expect((defaultCategoryTail.child as SizedBox).height, 36);

    await pumpPage(
      CategoriesPage(store: store, onOpenItem: (_) {}, dockClearance: 112),
      ZhuyingThemes.mitsuri,
    );
    final mitsuriCategoryTail = tester.widget<SliverToBoxAdapter>(
      find.byType(SliverToBoxAdapter).last,
    );
    expect((mitsuriCategoryTail.child as SizedBox).height, 148);

    await pumpPage(
      SourcesPage(store: store, dockClearance: 112),
      ZhuyingThemes.mitsuri,
    );
    expect(
      tester
          .widget<SingleChildScrollView>(
            find.byType(SingleChildScrollView).first,
          )
          .padding,
      const EdgeInsets.fromLTRB(28, 28, 28, 148),
    );

    await pumpPage(
      MinePage(store: store, onOpenItem: (_) {}, dockClearance: 112),
      ZhuyingThemes.mitsuri,
    );
    expect(
      tester
          .widget<SingleChildScrollView>(
            find.byType(SingleChildScrollView).first,
          )
          .padding,
      const EdgeInsets.fromLTRB(22, 22, 22, 146),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });

  testWidgets('Mitsuri dock character is centered over its disabled slot', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'zhuying.theme.v1': 'mitsuri'});
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = AppStore()..sources = [];
    await tester.pumpWidget(ZhuyingApp(store: store));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));

    final spacer = tester.getRect(
      find.byKey(const ValueKey('mitsuri-dock-leading-spacer')),
    );
    final character = tester.getRect(
      find.byKey(const ValueKey('mitsuri-dock-character')),
    );
    expect(character.center.dx, closeTo(spacer.center.dx, 0.5));

    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('iOS home scroll tails clear the native dock in both themes', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = AppStore()..sources = [];

    Future<void> pumpHome(ZhuyingThemeDefinition definition) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: definition.toThemeData().copyWith(
            extensions: [ZhuyingThemeExtension(definition)],
          ),
          home: Scaffold(
            body: HomePage(
              store: store,
              onOpenItem: (_) {},
              onHistory: () {},
              onSearch: (_) {},
              nativeBottomInset: 34,
            ),
          ),
        ),
      );
    }

    await pumpHome(ZhuyingThemes.defaultTheme);
    final defaultScroll = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView).first,
    );
    expect(defaultScroll.padding, const EdgeInsets.fromLTRB(18, 26, 18, 146));

    await pumpHome(ZhuyingThemes.mitsuri);
    await tester.pump(const Duration(milliseconds: 300));
    final mitsuriScroll = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView).first,
    );
    expect(mitsuriScroll.padding, const EdgeInsets.fromLTRB(18, 0, 18, 152));
    store.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

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
    await tester.ensureVisible(find.textContaining('作者：INJU银烛'));
    expect(find.textContaining('作者：INJU银烛'), findsOneWidget);
    expect(find.text('github.com/inju0524/NewVideo'), findsOneWidget);
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
      contentType: MediaContentType.movie,
    );
    const featured = MediaItem(
      id: 'home-featured',
      title: 'Featured movie',
      sourceId: 'preset-bfzy',
      sourceName: 'Test source',
      contentType: MediaContentType.movie,
    );
    const recommended = MediaItem(
      id: 'home-recommended',
      title: 'Recommended movie',
      sourceId: 'preset-bfzy',
      sourceName: 'Test source',
      contentType: MediaContentType.series,
    );
    const excluded = MediaItem(
      id: 'home-excluded',
      title: 'Variety show',
      sourceId: 'preset-bfzy',
      sourceName: 'Test source',
      contentType: MediaContentType.other,
    );
    final store = AppStore()
      ..catalog = const [featured, recommended, excluded]
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
    expect(find.text('Variety show'), findsNothing);

    store.dispose();
  });

  testWidgets('Mitsuri home branding stays inside its theme', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const featured = MediaItem(
      id: 'mitsuri-featured',
      title: 'Mitsuri theme feature',
      sourceId: 'preset-bfzy',
      sourceName: 'Test source',
      contentType: MediaContentType.movie,
    );
    final store = AppStore()..catalog = const [featured];
    final definition = ZhuyingThemes.mitsuri;
    await tester.pumpWidget(
      MaterialApp(
        theme: definition.toThemeData().copyWith(
          extensions: [ZhuyingThemeExtension(definition)],
        ),
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

    expect(find.text('我爱看电视'), findsOneWidget);
    expect(find.text('MITSURI EDITION · 01'), findsOneWidget);
    expect(find.text('「小Y专属定制·YSK赠」'), findsOneWidget);
    expect(find.text('今晚看点什么'), findsOneWidget);
    expect(find.text('我爱看电视 · 今日推荐'), findsOneWidget);
    expect(find.text('烛影'), findsNothing);
    expect(
      ZhuyingThemes.mitsuri.logoAsset,
      'assets/branding/mitsuri-logo-transparent.png',
    );
    final heroLogo = tester.widget<Image>(
      find.byKey(const ValueKey('brand-logo-mitsuri-hero')),
    );
    expect((heroLogo.image as AssetImage).assetName, definition.logoAsset);
    final portraitRect = tester.getRect(
      find.byKey(const ValueKey('mitsuri-main-portrait')),
    );
    final stageRect = tester.getRect(
      find.byKey(const ValueKey('mitsuri-intro-stage')),
    );
    final searchRect = tester.getRect(
      find.byKey(const ValueKey('mitsuri-search-field')),
    );
    final bannerRect = tester.getRect(
      find.byKey(const ValueKey('mitsuri-hero-mitsuri-featured')),
    );
    final headingRect = tester.getRect(find.text('今晚看点什么'));
    final flowerRect = tester.getRect(
      find.byKey(const ValueKey('mitsuri-heading-flower')),
    );
    expect(portraitRect.width, closeTo(151.2, 0.1));
    expect(stageRect.height, closeTo(302, 0.1));
    expect(portraitRect.bottom, closeTo(searchRect.bottom, 0.1));
    expect(searchRect.right - portraitRect.right, closeTo(10, 0.1));
    expect(bannerRect.top - searchRect.bottom, closeTo(26, 0.1));
    expect(flowerRect.left - headingRect.right, closeTo(8, 0.1));
    expect(headingRect.top, lessThan(240));
    final searchField = tester.widget<TextField>(find.byType(TextField));
    expect(searchField.decoration!.filled, isFalse);
    expect(searchField.decoration!.fillColor, Colors.transparent);
    store.dispose();
  });

  testWidgets(
    'Mitsuri search Hero can open and return without Material errors',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final store = AppStore()..catalog = const [];
      final definition = ZhuyingThemes.mitsuri;
      await tester.pumpWidget(
        MaterialApp(
          theme: definition.toThemeData().copyWith(
            extensions: [ZhuyingThemeExtension(definition)],
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: HomePage(
                store: store,
                onOpenItem: (_) {},
                onHistory: () {},
                onSearch: (_) {
                  Navigator.of(context).push<void>(
                    PageRouteBuilder<void>(
                      pageBuilder: (context, animation, secondaryAnimation) =>
                          SearchPage(
                            store: store,
                            initialQuery: '',
                            onOpenItem: (_) {},
                            heroEnabled: true,
                          ),
                      transitionsBuilder: (
                        context,
                        animation,
                        secondaryAnimation,
                        child,
                      ) => FadeTransition(opacity: animation, child: child),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(TextField).first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      await tester.pump(const Duration(milliseconds: 240));
      expect(find.byTooltip('返回'), findsOneWidget);

      await tester.tap(find.byTooltip('返回'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      await tester.pump(const Duration(milliseconds: 240));

      expect(tester.takeException(), isNull);
      expect(find.text('今晚看点什么'), findsOneWidget);
      store.dispose();
    },
  );

  testWidgets('default home uses Xuanlan branding', (tester) async {
    const featured = MediaItem(
      id: 'default-featured',
      title: 'Default theme feature',
      sourceId: 'preset-bfzy',
      sourceName: 'Test source',
      contentType: MediaContentType.movie,
    );
    final store = AppStore()..catalog = const [featured];
    final definition = ZhuyingThemes.defaultTheme;
    await tester.pumpWidget(
      MaterialApp(
        theme: definition.toThemeData().copyWith(
          extensions: [ZhuyingThemeExtension(definition)],
        ),
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

    expect(find.text('玄览 · 今日推荐'), findsOneWidget);
    expect(find.text('烛影'), findsNothing);
    expect(
      ZhuyingThemes.defaultTheme.logoAsset,
      'assets/branding/xuanlan-logo.jpg',
    );
    expect(find.text('我爱看电视'), findsNothing);
    expect(find.text('今晚看点什么'), findsOneWidget);
    store.dispose();
  });

  testWidgets(
    'theme options draw rounded borders above their clipped content',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final store = AppStore();
      final definition = ZhuyingThemes.defaultTheme;
      final lightDefinition = ZhuyingThemes.cinemaLight;
      expect(lightDefinition.toThemeData().brightness, Brightness.light);
      expect(
        lightDefinition.toThemeData().colorScheme.onSurface,
        lightDefinition.text,
      );
      expect(
        ZhuyingThemes.defaultTheme.toThemeData().brightness,
        Brightness.dark,
      );
      expect(ZhuyingThemes.mitsuri.toThemeData().brightness, Brightness.dark);
      await tester.pumpWidget(
        MaterialApp(
          theme: definition.toThemeData().copyWith(
            extensions: [ZhuyingThemeExtension(definition)],
          ),
          home: Scaffold(body: SettingsPage(store: store)),
        ),
      );
      await tester.pump();

      final tile = tester.widget<RoundedBorderFrame>(
        find.byKey(const ValueKey('theme-option-default')),
      );
      expect(tile.borderRadius, BorderRadius.circular(8));
      expect(tile.borderWidth, 1.5);
      expect(tile.borderColor, definition.primary);

      final outerDecoration = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byKey(const ValueKey('theme-option-default')),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect(outerDecoration.position, DecorationPosition.foreground);

      final mitsuriTile = tester.widget<RoundedBorderFrame>(
        find.byKey(const ValueKey('theme-option-mitsuri')),
      );
      expect(mitsuriTile.borderRadius, BorderRadius.circular(8));
      expect(mitsuriTile.borderWidth, 1);
      expect(mitsuriTile.borderColor, ZhuyingThemes.mitsuri.line);

      final lightTile = tester.widget<RoundedBorderFrame>(
        find.byKey(const ValueKey('theme-option-cinema-light')),
      );
      expect(lightTile.borderRadius, BorderRadius.circular(8));
      expect(lightTile.borderColor, lightDefinition.line);
      expect(find.text('影院亮色'), findsOneWidget);
      store.dispose();
    },
  );

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

    final originalPlatform = VideoPlayerPlatform.instance;
    final fakePlatform = _SeekTestVideoPlatform();
    VideoPlayerPlatform.instance = fakePlatform;
    addTearDown(() => VideoPlayerPlatform.instance = originalPlatform);

    final store = AppStore();
    const item = MediaItem(
      id: 'rotation-player-item',
      title: 'Rotation player',
      sourceId: 'rotation-test',
      sourceName: '测试线路',
      episodes: [
        MediaEpisode(title: '第01集', url: 'https://media.example/video.mp4'),
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
    expect(find.byKey(const ValueKey('player-focus-layout')), findsNothing);

    tester.view.physicalSize = const Size(844, 390);
    tester.binding.handleMetricsChanged();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('player-focus-layout')), findsOneWidget);
    final viewport = tester.getRect(
      find.byKey(const ValueKey('player-control-viewport')),
    );
    final video = tester.getRect(find.byType(VideoPlayer));
    final lock = tester.getRect(find.byKey(const ValueKey('player-seek-lock')));
    expect(viewport, const Rect.fromLTWH(0, 0, 844, 390));
    expect(video.width / video.height, closeTo(16 / 9, 0.01));
    expect(lock.center.dy, closeTo(viewport.center.dy, 1));
    expect(viewport.right - lock.right, closeTo(40, 1));

    tester.view.physicalSize = const Size(390, 844);
    tester.binding.handleMetricsChanged();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('player-focus-layout')), findsNothing);

    store.dispose();
  });

  testWidgets('player seeking and lock work with touch and mouse', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final originalPlatform = VideoPlayerPlatform.instance;
    final fakePlatform = _SeekTestVideoPlatform();
    VideoPlayerPlatform.instance = fakePlatform;
    addTearDown(() => VideoPlayerPlatform.instance = originalPlatform);

    final store = AppStore();
    const item = MediaItem(
      id: 'seek-lock-player',
      title: 'Seek lock player',
      sourceId: 'seek-source',
      sourceName: 'Test source',
      episodes: [
        MediaEpisode(title: '第01集', url: 'https://example.com/video.mp4'),
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
    await tester.pump();
    await tester.pump();

    Future<void> dragPlayer({
      PointerDeviceKind kind = PointerDeviceKind.touch,
    }) async {
      final gesture = await tester.startGesture(
        const Offset(100, 100),
        kind: kind,
      );
      await gesture.moveBy(const Offset(100, 0));
      await gesture.up();
      if (kind == PointerDeviceKind.mouse) await gesture.removePointer();
    }

    await dragPlayer();
    await tester.pump();
    expect(fakePlatform.seekPositions, hasLength(1));

    await dragPlayer(kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(fakePlatform.seekPositions, hasLength(2));

    final hover = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: 0,
    );
    await hover.addPointer(location: const Offset(100, 100));
    await hover.moveBy(const Offset(100, 0));
    await hover.removePointer();
    await tester.pump();
    expect(fakePlatform.seekPositions, hasLength(2));

    final videoRect = tester.getRect(find.byType(VideoPlayer));
    final lockFinder = find.byKey(const ValueKey('player-seek-lock'));
    final lockRect = tester.getRect(lockFinder);
    expect(lockRect.center.dy, closeTo(videoRect.center.dy, 1));
    expect(videoRect.right - lockRect.right, closeTo(40, 1));
    expect(
      tester.getCenter(find.byIcon(Icons.lock_open_rounded)),
      lockRect.center,
    );
    expect(
      tester
          .widget<Material>(
            find
                .ancestor(of: lockFinder, matching: find.byType(Material))
                .first,
          )
          .color,
      const Color.fromRGBO(0, 0, 0, 0.84),
    );

    await tester.tap(find.byTooltip('锁定滑动调节进度'));
    await tester.pump();
    expect(find.byTooltip('解锁滑动调节进度'), findsOneWidget);
    expect(
      tester
          .widget<AbsorbPointer>(
            find.byKey(const ValueKey('player-locked-control-bar')),
          )
          .absorbing,
      isTrue,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('player-locked-control-bar')),
        matching: find.byType(ColorFiltered),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('快退 10 秒'), warnIfMissed: false);
    await tester.pump();
    expect(fakePlatform.seekPositions, hasLength(2));

    await tester.pump(const Duration(seconds: 4));
    await tester.pump(const Duration(milliseconds: 200));
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const ValueKey('player-controls-opacity')),
          )
          .opacity,
      0,
    );

    await dragPlayer();
    await tester.pump();
    await dragPlayer(kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(fakePlatform.seekPositions, hasLength(2));

    await tester.tapAt(videoRect.center);
    await tester.pump();
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const ValueKey('player-controls-opacity')),
          )
          .opacity,
      1,
    );

    await tester.tap(find.byTooltip('解锁滑动调节进度'));
    await tester.pump();
    await dragPlayer();
    await tester.pump();
    expect(fakePlatform.seekPositions, hasLength(3));

    await tester.tap(find.byTooltip('暂停'));
    await tester.pump();
    final playCallsBeforeLockedTap = fakePlatform.playCalls;
    await tester.tap(find.byTooltip('锁定滑动调节进度'));
    await tester.pump();
    expect(
      tester
          .widget<AbsorbPointer>(
            find.byKey(const ValueKey('player-locked-center-play')),
          )
          .absorbing,
      isTrue,
    );
    await tester.tap(
      find.byKey(const ValueKey('player-locked-center-play')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(fakePlatform.playCalls, playCallsBeforeLockedTap);

    store.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
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

class _SeekTestVideoPlatform extends VideoPlayerPlatform {
  int _nextPlayerId = 0;
  final Map<int, StreamController<VideoEvent>> _events = {};
  final List<Duration> seekPositions = [];
  int playCalls = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final playerId = _nextPlayerId++;
    final events = StreamController<VideoEvent>();
    _events[playerId] = events;
    events.add(
      VideoEvent(
        eventType: VideoEventType.initialized,
        duration: const Duration(minutes: 20),
        size: const Size(1920, 1080),
      ),
    );
    return playerId;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _events[playerId]!.stream;

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> play(int playerId) async {
    playCalls++;
  }

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {
    seekPositions.add(position);
  }

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Future<void> dispose(int playerId) async {
    await _events.remove(playerId)?.close();
  }

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const ColoredBox(color: Colors.black);
}
