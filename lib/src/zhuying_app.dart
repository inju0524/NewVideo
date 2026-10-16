import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_store.dart';
import 'models.dart';
import 'ui/catalog_pages.dart';
import 'ui/detail_page.dart';
import 'ui/widgets.dart';

class ZhuyingApp extends StatefulWidget {
  const ZhuyingApp({super.key});

  @override
  State<ZhuyingApp> createState() => _ZhuyingAppState();
}

class _ZhuyingAppState extends State<ZhuyingApp> {
  late final AppStore _store;

  @override
  void initState() {
    super.initState();
    _store = AppStore();
    _store.initialize();
  }

  @override
  void dispose() {
    _store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '烛影',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: AppShell(store: _store),
    );
  }

  ThemeData _buildTheme() {
    final scheme = ColorScheme.fromSeed(
      seedColor: ZhuyingColors.amber,
      brightness: Brightness.dark,
      surface: ZhuyingColors.surface,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme.copyWith(
        primary: ZhuyingColors.amber,
        secondary: ZhuyingColors.green,
        surface: ZhuyingColors.surface,
        onSurface: ZhuyingColors.text,
      ),
      scaffoldBackgroundColor: ZhuyingColors.canvas,
      textTheme: ThemeData.dark().textTheme.apply(
        bodyColor: ZhuyingColors.text,
        displayColor: ZhuyingColors.text,
      ),
      dividerColor: ZhuyingColors.line,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: ZhuyingColors.surface,
        hintStyle: const TextStyle(color: ZhuyingColors.muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: const BorderSide(color: ZhuyingColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: const BorderSide(color: ZhuyingColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: const BorderSide(color: ZhuyingColors.amber, width: 1.2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: ZhuyingColors.surfaceRaised,
        contentTextStyle: const TextStyle(color: ZhuyingColors.text),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: ZhuyingColors.surface,
        indicatorColor: ZhuyingColors.amber.withValues(alpha: 0.14),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.selected)
                ? ZhuyingColors.amber
                : ZhuyingColors.muted,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({required this.store, super.key});

  final AppStore store;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell>
    with SingleTickerProviderStateMixin {
  static const _nativeDockChannel = MethodChannel('zhuying/native-dock');
  late final AnimationController _tabTransition;
  int _selectedIndex = 0;
  int _previousIndex = 0;
  final _visitedTabs = <bool>[true, false, false, false];

  static const _destinations = [
    _Destination('首页', Icons.home_outlined, Icons.home_rounded),
    _Destination('分类', Icons.grid_view_outlined, Icons.grid_view_rounded),
    _Destination('片源', Icons.hub_outlined, Icons.hub_rounded),
    _Destination('我的', Icons.person_outline_rounded, Icons.person_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _tabTransition =
        AnimationController(
          vsync: this,
          value: 1,
          duration: const Duration(milliseconds: 260),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed && mounted) {
            setState(() => _previousIndex = _selectedIndex);
          }
        });
  }

  void _select(int index) {
    if (index == _selectedIndex) return;
    final duration = motionDuration(
      context,
      widget.store.reduceMotion,
      const Duration(milliseconds: 260),
    );
    setState(() {
      _previousIndex = _selectedIndex;
      _selectedIndex = index;
      _visitedTabs[index] = true;
    });
    if (duration == Duration.zero) {
      _tabTransition.value = 1;
      setState(() => _previousIndex = _selectedIndex);
    } else {
      _tabTransition.duration = duration;
      _tabTransition.forward(from: 0);
    }
  }

  void _openSearch([String value = '', bool fromSearchField = false]) {
    Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        transitionDuration: motionDuration(
          context,
          widget.store.reduceMotion,
          const Duration(milliseconds: 360),
        ),
        reverseTransitionDuration: motionDuration(
          context,
          widget.store.reduceMotion,
          const Duration(milliseconds: 260),
        ),
        pageBuilder: (context, animation, secondaryAnimation) => SearchPage(
          store: widget.store,
          initialQuery: value,
          onOpenItem: _openItem,
          heroEnabled: fromSearchField,
        ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(opacity: curved, child: child);
        },
      ),
    );
  }

  void _openItem(MediaItem item) {
    final saved = widget.store.history.where((entry) => entry.id == item.id);
    if (saved.isNotEmpty) {
      item = item.copyWith(
        progressSeconds: saved.first.progressSeconds,
        durationSeconds: saved.first.durationSeconds,
        progressEpisodeId: saved.first.progressEpisodeId,
        progressEpisodeTitle: saved.first.progressEpisodeTitle,
      );
    }
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: motionDuration(
          context,
          widget.store.reduceMotion,
          const Duration(milliseconds: 360),
        ),
        reverseTransitionDuration: motionDuration(
          context,
          widget.store.reduceMotion,
          const Duration(milliseconds: 260),
        ),
        pageBuilder: (context, animation, secondaryAnimation) =>
            MediaDetailsPage(store: widget.store, item: item),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.025),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= 900;
          return Scaffold(
            body: SafeArea(
              bottom: !desktop,
              child: Row(
                children: [
                  if (desktop)
                    _DesktopNavigation(
                      selectedIndex: _selectedIndex,
                      destinations: _destinations,
                      onSelect: _select,
                      sourceCount: widget.store.sources.length,
                    ),
                  Expanded(
                    child: Column(
                      children: [
                        _TopBar(
                          selectedIndex: _selectedIndex,
                          destinations: _destinations,
                          onOpenSearch: () => _openSearch(''),
                          onOpenSearchField: () => _openSearch('', true),
                          store: widget.store,
                        ),
                        Expanded(
                          child: AnimatedBuilder(
                            animation: _tabTransition,
                            builder: (context, _) {
                              final eased = Curves.easeInOutCubic.transform(
                                _tabTransition.value,
                              );
                              return Stack(
                                fit: StackFit.expand,
                                children: [
                                  for (var index = 0; index < 4; index++)
                                    if (_visitedTabs[index])
                                      _tabPage(index, eased),
                                ],
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            bottomNavigationBar: desktop
                ? null
                : _isNativeIosDock
                ? _NativeIosDock(
                    selectedIndex: _selectedIndex,
                    onSelected: _select,
                    channel: _nativeDockChannel,
                  )
                : NavigationBar(
                    selectedIndex: _selectedIndex,
                    onDestinationSelected: _select,
                    destinations: _destinations.map((destination) {
                      return NavigationDestination(
                        icon: Icon(destination.icon),
                        selectedIcon: Icon(destination.selectedIcon),
                        label: destination.label,
                      );
                    }).toList(),
                  ),
          );
        },
      ),
    );
  }

  Widget _tabPage(int index, double transitionValue) {
    final selected = index == _selectedIndex;
    final transitioningOut =
        index == _previousIndex && _previousIndex != _selectedIndex;
    final visible = selected || transitioningOut;
    final opacity = selected
        ? transitionValue
        : transitioningOut
        ? 1 - transitionValue
        : 0.0;
    final page = switch (index) {
      0 => HomePage(
        store: widget.store,
        onOpenItem: _openItem,
        onHistory: () => _select(3),
        onSearch: (value) => _openSearch(value, true),
      ),
      1 => CategoriesPage(store: widget.store, onOpenItem: _openItem),
      2 => SourcesPage(store: widget.store),
      _ => MinePage(store: widget.store, onOpenItem: _openItem),
    };
    return Offstage(
      offstage: !visible,
      child: TickerMode(
        enabled: selected,
        child: IgnorePointer(
          ignoring: !selected,
          child: Opacity(
            opacity: opacity,
            child: HeroMode(
              enabled: selected,
              child: _RetainedPage(key: ValueKey(index), child: page),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tabTransition.dispose();
    super.dispose();
  }

  bool get _isNativeIosDock =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
}

class _NativeIosDock extends StatefulWidget {
  const _NativeIosDock({
    required this.selectedIndex,
    required this.onSelected,
    required this.channel,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final MethodChannel channel;

  @override
  State<_NativeIosDock> createState() => _NativeIosDockState();
}

class _NativeIosDockState extends State<_NativeIosDock> {
  @override
  void initState() {
    super.initState();
    widget.channel.setMethodCallHandler(_handleNativeSelection);
  }

  @override
  void didUpdateWidget(covariant _NativeIosDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channel != widget.channel) {
      oldWidget.channel.setMethodCallHandler(null);
      widget.channel.setMethodCallHandler(_handleNativeSelection);
    }
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _selectNativeTab();
    }
  }

  Future<void> _handleNativeSelection(MethodCall call) async {
    if (call.method == 'selected' && call.arguments is int) {
      widget.onSelected(call.arguments as int);
    }
  }

  Future<void> _selectNativeTab() async {
    try {
      await widget.channel.invokeMethod<void>('select', widget.selectedIndex);
    } on MissingPluginException {
      // The platform view may not have been created yet.
    } on PlatformException {
      // Keep Flutter navigation responsive if the native bar is unavailable.
    }
  }

  @override
  void dispose() {
    widget.channel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return SizedBox(
      height: 58 + bottomInset,
      child: UiKitView(
        viewType: 'zhuying/native-glass-dock',
        creationParams: {
          'selectedIndex': widget.selectedIndex,
          'bottomInset': bottomInset,
        },
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: (_) => _selectNativeTab(),
      ),
    );
  }
}

class _RetainedPage extends StatefulWidget {
  const _RetainedPage({required this.child, super.key});

  final Widget child;

  @override
  State<_RetainedPage> createState() => _RetainedPageState();
}

class _RetainedPageState extends State<_RetainedPage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

class _Destination {
  const _Destination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class _DesktopNavigation extends StatelessWidget {
  const _DesktopNavigation({
    required this.selectedIndex,
    required this.destinations,
    required this.onSelect,
    required this.sourceCount,
  });

  final int selectedIndex;
  final List<_Destination> destinations;
  final ValueChanged<int> onSelect;
  final int sourceCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 224,
      decoration: const BoxDecoration(
        color: ZhuyingColors.surface,
        border: Border(right: BorderSide(color: ZhuyingColors.line)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 22, 14, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _BrandMark(),
          const SizedBox(height: 36),
          for (var index = 0; index < destinations.length; index++)
            _RailItem(
              destination: destinations[index],
              selected: index == selectedIndex,
              onTap: () => onSelect(index),
            ),
          const Spacer(),
          Container(height: 1, color: ZhuyingColors.line),
          const SizedBox(height: 14),
          Row(
            children: [
              const Icon(
                Icons.lan_outlined,
                size: 16,
                color: ZhuyingColors.green,
              ),
              const SizedBox(width: 8),
              Text(
                '$sourceCount 个片源',
                style: const TextStyle(
                  color: ZhuyingColors.muted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          const Text(
            '本地片库',
            style: TextStyle(color: ZhuyingColors.muted, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: ZhuyingColors.amber.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(7),
          ),
          child: const Icon(
            Icons.local_movies_outlined,
            color: ZhuyingColors.amber,
            size: 19,
          ),
        ),
        const SizedBox(width: 10),
        const Text(
          '烛影',
          style: TextStyle(
            color: ZhuyingColors.text,
            fontSize: 19,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _Destination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Material(
        color: selected
            ? ZhuyingColors.amber.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: SizedBox(
            height: 44,
            child: Row(
              children: [
                const SizedBox(width: 12),
                Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  size: 19,
                  color: selected ? ZhuyingColors.amber : ZhuyingColors.muted,
                ),
                const SizedBox(width: 12),
                Text(
                  destination.label,
                  style: TextStyle(
                    color: selected ? ZhuyingColors.text : ZhuyingColors.muted,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatefulWidget {
  const _TopBar({
    required this.selectedIndex,
    required this.destinations,
    required this.onOpenSearch,
    required this.onOpenSearchField,
    required this.store,
  });

  final int selectedIndex;
  final List<_Destination> destinations;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenSearchField;
  final AppStore store;

  @override
  State<_TopBar> createState() => _TopBarState();
}

class _TopBarState extends State<_TopBar> {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 70,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: ZhuyingColors.line)),
      ),
      child: Row(
        children: [
          if (MediaQuery.sizeOf(context).width < 900) ...[
            const _BrandMark(),
            const SizedBox(width: 16),
          ] else
            Expanded(
              child: Text(
                widget.destinations[widget.selectedIndex.clamp(0, 3)].label,
                style: const TextStyle(
                  color: ZhuyingColors.text,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
          if (MediaQuery.sizeOf(context).width >= 650)
            SizedBox(
              width: MediaQuery.sizeOf(context).width < 900 ? 260 : 360,
              child: SearchField(
                readOnly: true,
                hintText: '搜索片名或关键词',
                onTap: widget.onOpenSearchField,
              ),
            ),
          const Spacer(),
          if (widget.store.isRefreshing)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: ZhuyingColors.amber,
              ),
            )
          else
            IconButton(
              tooltip: '刷新片源',
              onPressed: widget.store.refreshSources,
              icon: const Icon(Icons.refresh_rounded, size: 20),
            ),
          if (MediaQuery.sizeOf(context).width < 650 &&
              widget.selectedIndex != 0)
            IconButton(
              tooltip: '搜索',
              onPressed: widget.onOpenSearch,
              icon: const Icon(Icons.search_rounded, size: 19),
            ),
        ],
      ),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({
    required this.store,
    required this.onOpenItem,
    required this.onHistory,
    required this.onSearch,
    super.key,
  });

  final AppStore store;
  final ValueChanged<MediaItem> onOpenItem;
  final VoidCallback onHistory;
  final ValueChanged<String> onSearch;

  @override
  Widget build(BuildContext context) {
    final items = store.homeMedia;
    final continueItems = _uniqueContinueItems(store.history);
    final continuedTitles = store.history
        .map((item) => _continueTitleKey(item.title))
        .toSet();
    final freshItems = items
        .where(
          (item) => !continuedTitles.contains(_continueTitleKey(item.title)),
        )
        .toList();
    final hero = freshItems.isEmpty ? null : freshItems.first;
    final recommendations = freshItems.length > 1
        ? freshItems.skip(1).take(12).toList()
        : <MediaItem>[];
    final loadingHome = !store.hasInitialized || store.isRefreshing;
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth < 700 ? 18.0 : 36.0;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(horizontal, 26, horizontal, 34),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '今晚看点什么',
                      style: TextStyle(
                        color: ZhuyingColors.text,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (store.refreshMessage != null &&
                      constraints.maxWidth > 600)
                    Text(
                      store.refreshMessage!,
                      style: const TextStyle(
                        color: ZhuyingColors.muted,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
              if (constraints.maxWidth < 650) ...[
                const SizedBox(height: 18),
                SearchField(
                  heroEnabled: MediaQuery.sizeOf(context).width < 650,
                  readOnly: true,
                  onTap: () => onSearch(''),
                  hintText: '搜索片名或关键词',
                ),
              ],
              const SizedBox(height: 22),
              AnimatedSwitcher(
                duration: motionDuration(
                  context,
                  store.reduceMotion,
                  const Duration(milliseconds: 220),
                ),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: hero != null
                    ? _HeroFeature(
                        key: ValueKey('home-hero-${hero.id}'),
                        item: hero,
                        onTap: () => onOpenItem(hero),
                        height: constraints.maxWidth < 650 ? 270 : 340,
                        reduceMotion: store.reduceMotion,
                      )
                    : loadingHome
                    ? _HomeHeroPlaceholder(
                        key: const ValueKey('home-hero-placeholder'),
                        height: constraints.maxWidth < 650 ? 270 : 340,
                      )
                    : const SizedBox(
                        key: ValueKey('home-hero-empty'),
                        height: 0,
                      ),
              ),
              const SizedBox(height: 30),
              if (continueItems.isNotEmpty) ...[
                SectionTitle(
                  title: '接着看',
                  trailing: TextButton(
                    onPressed: onHistory,
                    child: const Text('观看历史'),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 118,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: continueItems.take(6).length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final item = continueItems[index];
                      return _ContinueTile(
                        item: item,
                        onTap: () => onOpenItem(item),
                        reduceMotion: store.reduceMotion,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 30),
              ],
              SectionTitle(
                title: '为你挑选',
                trailing: Text(
                  '${freshItems.length} 部',
                  style: const TextStyle(
                    color: ZhuyingColors.muted,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 15),
              if (recommendations.isEmpty && loadingHome)
                const _HomeLoadingGrid()
              else if (recommendations.isEmpty)
                EmptyState(
                  icon: Icons.movie_filter_outlined,
                  title: hero != null
                      ? '暂时没有更多影片'
                      : store.history.isEmpty
                      ? '片源暂时没有返回影片'
                      : '暂时没有新片推荐',
                  detail: hero != null
                      ? '刷新片源，查看更多影片。'
                      : store.history.isEmpty
                      ? '刷新片源，或在片源管理中添加其他来源。'
                      : '已看过的影片集中显示在“接着看”中。',
                )
              else
                _PosterGrid(
                  items: recommendations,
                  onOpenItem: onOpenItem,
                  favorites: store.favorites,
                  onFavorite: store.toggleFavorite,
                  reduceMotion: store.reduceMotion,
                ),
            ],
          ),
        );
      },
    );
  }
}

class _HeroFeature extends StatelessWidget {
  const _HeroFeature({
    required this.item,
    required this.onTap,
    required this.height,
    required this.reduceMotion,
    super.key,
  });

  final MediaItem item;
  final VoidCallback onTap;
  final double height;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ZhuyingColors.surface,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Hero(
                tag: item.id,
                child: MediaPoster(
                  url: item.posterUrl,
                  thumbnailUrl: item.thumbnailUrl,
                  title: '',
                  headers: item.posterHeaders,
                  fallbackFontSize: 24,
                  reduceMotion: reduceMotion,
                ),
              ),
              if (!reduceMotion) const Positioned.fill(child: _CurtainLight()),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Colors.black.withValues(alpha: 0.92),
                      Colors.black.withValues(alpha: 0.56),
                      Colors.black.withValues(alpha: 0.08),
                    ],
                    stops: const [0, 0.56, 1],
                  ),
                ),
              ),
              Positioned(
                left: 24,
                right: 24,
                bottom: 25,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.wb_twilight_rounded,
                            size: 15,
                            color: ZhuyingColors.amber,
                          ),
                          const SizedBox(width: 7),
                          Text(
                            item.isDemo ? '烛影 · 演示片单' : '烛影 · 今日推荐',
                            style: const TextStyle(
                              color: ZhuyingColors.amber,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 9),
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          height: 1.12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Text(
                        [
                          item.year,
                          item.region,
                          item.genre,
                          item.remarks,
                        ].where((value) => value.isNotEmpty).join('  ·  '),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                      if (item.description.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          item.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            height: 1.45,
                          ),
                        ),
                      ],
                      const SizedBox(height: 15),
                      FilledButton.icon(
                        onPressed: onTap,
                        icon: const Icon(Icons.play_arrow_rounded, size: 19),
                        label: const Text('查看影片'),
                        style: FilledButton.styleFrom(
                          backgroundColor: ZhuyingColors.amber,
                          foregroundColor: const Color(0xFF211A10),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 11,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeHeroPlaceholder extends StatelessWidget {
  const _HomeHeroPlaceholder({required this.height, super.key});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ZhuyingColors.surface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Stack(
          children: [
            const Center(
              child: Icon(
                Icons.local_movies_outlined,
                size: 46,
                color: ZhuyingColors.line,
              ),
            ),
            Positioned(
              left: 24,
              bottom: 25,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 116,
                    height: 10,
                    decoration: BoxDecoration(
                      color: ZhuyingColors.surfaceRaised,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: 210,
                    height: 22,
                    decoration: BoxDecoration(
                      color: ZhuyingColors.surfaceRaised,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeLoadingGrid extends StatelessWidget {
  const _HomeLoadingGrid();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1320
            ? 7
            : constraints.maxWidth >= 1050
            ? 6
            : constraints.maxWidth >= 780
            ? 5
            : constraints.maxWidth >= 540
            ? 4
            : 3;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: columns * 2,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 14,
            mainAxisSpacing: 17,
            childAspectRatio: 0.48,
          ),
          itemBuilder: (context, index) => const _HomeLoadingCard(),
        );
      },
    );
  }
}

class _HomeLoadingCard extends StatelessWidget {
  const _HomeLoadingCard();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 0.69,
          child: ColoredBox(
            color: ZhuyingColors.surfaceRaised,
            child: const Center(
              child: Icon(
                Icons.movie_outlined,
                color: ZhuyingColors.line,
                size: 26,
              ),
            ),
          ),
        ),
        const SizedBox(height: 9),
        FractionallySizedBox(
          widthFactor: 0.78,
          child: Container(
            height: 10,
            decoration: BoxDecoration(
              color: ZhuyingColors.surfaceRaised,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
        const SizedBox(height: 7),
        FractionallySizedBox(
          widthFactor: 0.48,
          child: Container(
            height: 8,
            decoration: BoxDecoration(
              color: ZhuyingColors.surfaceRaised,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ],
    );
  }
}

class _CurtainLight extends StatefulWidget {
  const _CurtainLight();

  @override
  State<_CurtainLight> createState() => _CurtainLightState();
}

class _CurtainLightState extends State<_CurtainLight>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final center = Curves.easeInOutSine.transform(_controller.value);
            return DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    ZhuyingColors.amber.withValues(alpha: 0.16),
                    Colors.transparent,
                  ],
                  stops: [
                    (center - 0.3).clamp(0.0, 1.0),
                    center,
                    (center + 0.3).clamp(0.0, 1.0),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ContinueTile extends StatelessWidget {
  const _ContinueTile({
    required this.item,
    required this.onTap,
    required this.reduceMotion,
  });

  final MediaItem item;
  final VoidCallback onTap;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 276,
      child: Material(
        color: ZhuyingColors.surface,
        borderRadius: BorderRadius.circular(7),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Row(
            children: [
              SizedBox(
                width: 78,
                child: AspectRatio(
                  aspectRatio: 0.78,
                  child: MediaPoster(
                    url: item.posterUrl,
                    thumbnailUrl: item.thumbnailUrl,
                    title: '',
                    headers: item.posterHeaders,
                    fallbackFontSize: 13,
                    reduceMotion: reduceMotion,
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        height: 20,
                        child: Text(
                          _compactContinueTitle(item.title),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          softWrap: false,
                          style: const TextStyle(
                            color: ZhuyingColors.text,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _continueProgressText(item),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: ZhuyingColors.amber,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 9),
                      LinearProgressIndicator(
                        value: item.progress,
                        minHeight: 4,
                        color: ZhuyingColors.amber,
                        backgroundColor: ZhuyingColors.line,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _compactContinueTitle(String title) {
  if (title.length <= 12) return title;
  return '${title.substring(0, 12)}…';
}

List<MediaItem> _uniqueContinueItems(Iterable<MediaItem> items) {
  final seenIds = <String>{};
  final seenTitles = <String>{};
  return items.where((item) {
    final title = _continueTitleKey(item.title);
    return seenIds.add(item.id) && (title.isEmpty || seenTitles.add(title));
  }).toList();
}

String _continueTitleKey(String title) =>
    title.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

String _continueProgressText(MediaItem item) {
  final episode = _continueEpisodeLabel(
    item.progressEpisodeTitle.isEmpty
        ? item.progressEpisodeId
        : item.progressEpisodeTitle,
  );
  final remainingSeconds = item.durationSeconds > 0
      ? (item.durationSeconds - item.progressSeconds).clamp(
          0,
          item.durationSeconds,
        )
      : null;
  final remaining = remainingSeconds == null
      ? null
      : (remainingSeconds + 59) ~/ 60;
  final timeLabel = remaining == null ? null : '剩余$remaining分钟';

  if (episode != null) {
    return timeLabel == null ? episode : '$episode · $timeLabel';
  }
  if (timeLabel != null) return timeLabel;
  if (item.progressSeconds > 0) {
    return '已观看${(item.progressSeconds / 60).floor()}分钟';
  }
  return '继续观看';
}

String? _continueEpisodeLabel(String raw) {
  final title = raw.trim();
  if (title.isEmpty) return null;
  final numbered = RegExp(r'第\s*0*(\d+)\s*集').firstMatch(title);
  if (numbered != null) return '第${numbered.group(1)}集';
  final seasonEpisode = RegExp(
    r'\bS\d+\s*E0*(\d+)\b',
    caseSensitive: false,
  ).firstMatch(title);
  if (seasonEpisode != null) return '第${seasonEpisode.group(1)}集';
  final episode = RegExp(
    r'\b(?:EP?|episode)\s*0*(\d+)\b',
    caseSensitive: false,
  ).firstMatch(title);
  return episode == null ? null : '第${episode.group(1)}集';
}

class _PosterGrid extends StatelessWidget {
  const _PosterGrid({
    required this.items,
    required this.onOpenItem,
    required this.favorites,
    required this.onFavorite,
    required this.reduceMotion,
  });

  final List<MediaItem> items;
  final ValueChanged<MediaItem> onOpenItem;
  final Set<String> favorites;
  final ValueChanged<MediaItem> onFavorite;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Text(
          '暂无影片',
          style: const TextStyle(color: ZhuyingColors.muted, fontSize: 12),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1320
            ? 7
            : width >= 1050
            ? 6
            : width >= 780
            ? 5
            : width >= 540
            ? 4
            : 3;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 14,
            mainAxisSpacing: 17,
            childAspectRatio: 0.48,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            return AnimatedSwitcher(
              duration: motionDuration(
                context,
                reduceMotion,
                const Duration(milliseconds: 180),
              ),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) =>
                  FadeTransition(opacity: animation, child: child),
              child: PosterCard(
                key: ValueKey(item.id),
                item: item,
                onTap: () => onOpenItem(item),
                favorite: favorites.contains(item.id),
                onFavorite: () => onFavorite(item),
                reduceMotion: reduceMotion,
              ),
            );
          },
        );
      },
    );
  }
}
