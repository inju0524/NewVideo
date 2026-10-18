import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_store.dart';
import 'models.dart';
import 'platform/branding_web_stub.dart'
    if (dart.library.js_interop) 'platform/branding_web.dart'
    as platform_branding;
import 'theme/app_theme.dart';
import 'ui/catalog_pages.dart';
import 'ui/detail_page.dart';
import 'ui/widgets.dart';

class ZhuyingApp extends StatefulWidget {
  const ZhuyingApp({this.store, super.key});

  final AppStore? store;

  @override
  State<ZhuyingApp> createState() => _ZhuyingAppState();
}

class _ZhuyingAppState extends State<ZhuyingApp> with WidgetsBindingObserver {
  static const _appIconChannel = MethodChannel('zhuying/app-icon');
  late final AppStore _store;
  late String _themeId;
  bool _platformBrandingReady = false;
  Timer? _resumeRetryTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _store = widget.store ?? AppStore();
    _themeId = _store.themeId;
    _store.addListener(_handleStoreChanged);
    unawaited(_initializeStore());
  }

  Future<void> _initializeStore() async {
    await _store.initialize();
    if (mounted) {
      _platformBrandingReady = true;
      if (_themeId != _store.themeId) {
        setState(() => _themeId = _store.themeId);
      }
      await _syncPlatformBranding(ZhuyingThemes.byId(_store.themeId));
    }
  }

  void _handleStoreChanged() {
    if (!mounted || _themeId == _store.themeId) return;
    final nextThemeId = _store.themeId;
    setState(() => _themeId = nextThemeId);
    if (_platformBrandingReady) {
      unawaited(_syncPlatformBranding(ZhuyingThemes.byId(nextThemeId)));
    }
  }

  Future<void> _syncPlatformBranding(ZhuyingThemeDefinition definition) async {
    if (kIsWeb) {
      platform_branding.updateWebBranding(
        title: definition.brandName,
        faviconPath: definition.isMitsuri
            ? 'icons/Icon-Mitsuri-192.png'
            : 'favicon.png',
        appleTouchIconPath: definition.isMitsuri
            ? 'icons/Icon-Mitsuri-192.png'
            : 'icons/Icon-192.png',
        manifestPath: definition.isMitsuri
            ? 'manifest-mitsuri.json'
            : 'manifest.json',
      );
      return;
    }
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS &&
        defaultTargetPlatform != TargetPlatform.windows) {
      return;
    }
    try {
      await _appIconChannel.invokeMethod<void>('setLauncherIcon', {
        'isMitsuri': definition.isMitsuri,
        'brandName': definition.brandName,
      });
    } on MissingPluginException {
      // Keep the in-app branding available when native icon switching is absent.
    } on PlatformException {
      // A platform launcher may reject an icon update; the app theme still applies.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    _resumeRetryTimer?.cancel();
    _resumeRetryTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) unawaited(_store.retryUnavailableSources());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resumeRetryTimer?.cancel();
    _store.removeListener(_handleStoreChanged);
    _store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final definition = ZhuyingThemes.byId(_themeId);
    ZhuyingColors.setActive(definition);
    return MaterialApp(
      title: definition.brandName,
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(definition),
      themeAnimationDuration: const Duration(milliseconds: 420),
      themeAnimationCurve: Curves.easeInOutCubic,
      home: AppShell(store: _store),
    );
  }

  ThemeData _buildTheme(ZhuyingThemeDefinition definition) => definition
      .toThemeData()
      .copyWith(extensions: [ZhuyingThemeExtension(definition)]);
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
          final nativeDockVisible = _isNativeIosDock && !desktop;
          final immersiveMitsuri = context.zhuyingTheme.isMitsuri && !desktop;
          final nativeBottomInset = _isNativeIosDock
              ? MediaQuery.viewPaddingOf(context).bottom
              : 0.0;
          final dockBottomInset = nativeDockVisible ? nativeBottomInset : 0.0;
          final safeBottomInset = MediaQuery.paddingOf(context).bottom;
          final themedDockClearance = immersiveMitsuri
              ? 112.0 +
                    (dockBottomInset > safeBottomInset
                        ? dockBottomInset
                        : safeBottomInset)
              : 0.0;
          final dockClearance = nativeDockVisible
              ? 112.0 + dockBottomInset
              : themedDockClearance;
          return Scaffold(
            extendBody: nativeDockVisible || immersiveMitsuri,
            body: ZhuyingThemeBackdrop(
              reduceMotion: widget.store.reduceMotion,
              showCharacter:
                  !(_selectedIndex == 0 && context.zhuyingTheme.isMitsuri),
              child: SafeArea(
                bottom: !desktop &&
                    !nativeDockVisible &&
                    !immersiveMitsuri,
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
                          if (!(_selectedIndex == 0 &&
                              context.zhuyingTheme.isMitsuri))
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
                                        _tabPage(
                                          index,
                                          eased,
                                          nativeBottomInset: nativeBottomInset,
                                          dockClearance: dockClearance,
                                          nativeDockVisible: nativeDockVisible,
                                        ),
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
            ),
            bottomNavigationBar: desktop
                ? null
                : _isNativeIosDock
                ? _NativeIosDock(
                    selectedIndex: _selectedIndex,
                    onSelected: _select,
                    channel: _nativeDockChannel,
                    theme: ZhuyingThemes.byId(widget.store.themeId),
                    bottomInset: dockBottomInset,
                  )
                : context.zhuyingTheme.isMitsuri
                ? _MitsuriNavigationBar(
                    selectedIndex: _selectedIndex,
                    destinations: _destinations,
                    onSelected: _select,
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

  Widget _tabPage(
    int index,
    double transitionValue, {
    required double nativeBottomInset,
    required double dockClearance,
    required bool nativeDockVisible,
  }) {
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
        nativeBottomInset: nativeBottomInset,
      ),
      1 => CategoriesPage(
        store: widget.store,
        onOpenItem: _openItem,
        dockClearance: dockClearance,
      ),
      2 => SourcesPage(store: widget.store, dockClearance: dockClearance),
      _ => MinePage(
        store: widget.store,
        onOpenItem: _openItem,
        dockClearance: dockClearance,
      ),
    };
    // Keep pages transparent only when they sit beneath a translucent dock.
    final pageSurface = context.zhuyingTheme.isMitsuri || nativeDockVisible
        ? page
        : ColoredBox(color: ZhuyingColors.canvas, child: page);
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
              child: _RetainedPage(key: ValueKey(index), child: pageSurface),
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

class _MitsuriNavigationBar extends StatelessWidget {
  const _MitsuriNavigationBar({
    required this.selectedIndex,
    required this.destinations,
    required this.onSelected,
  });

  final int selectedIndex;
  final List<_Destination> destinations;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(10, 0, 10, bottomInset + 8),
      child: SizedBox(
        height: 72,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: ZhuyingColors.primary.withValues(alpha: 0.12),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: RoundedBorderFrame(
                  borderRadius: BorderRadius.circular(30),
                  borderColor: ZhuyingColors.accent.withValues(alpha: 0.5),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: DecoratedBox(
                      decoration: const BoxDecoration(color: Color(0x8A160F18)),
                      child: Row(
                        children: [
                          Expanded(
                            child: SizedBox.expand(
                              key: const ValueKey(
                                'mitsuri-dock-leading-spacer',
                              ),
                            ),
                          ),
                          for (
                            var index = 0;
                            index < destinations.length;
                            index++
                          )
                            Expanded(
                              child: _MitsuriDockItem(
                                destination: destinations[index],
                                selected: selectedIndex == index,
                                onTap: () => onSelected(index),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: (MediaQuery.sizeOf(context).width - 20) / 10 - 48,
              bottom: -10,
              width: 96,
              height: 102,
              child: _MitsuriDockCharacter(
                asset: context.zhuyingTheme.chibiAsset,
                key: const ValueKey('mitsuri-dock-character'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MitsuriDockCharacter extends StatelessWidget {
  const _MitsuriDockCharacter({required this.asset, super.key});

  final String? asset;

  @override
  Widget build(BuildContext context) {
    if (asset == null) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.bottomCenter,
      child: Image.asset(
        asset!,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}

class _MitsuriDockItem extends StatelessWidget {
  const _MitsuriDockItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final _Destination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: destination.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: AnimatedContainer(
          duration: motionDuration(
            context,
            false,
            const Duration(milliseconds: 220),
          ),
          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
          decoration: BoxDecoration(
            color: selected
                ? ZhuyingColors.primary.withValues(alpha: 0.22)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected ? destination.selectedIcon : destination.icon,
                size: 21,
                color: selected ? ZhuyingColors.primary : ZhuyingColors.text,
              ),
              const SizedBox(height: 3),
              Text(
                destination.label,
                style: TextStyle(
                  color: selected ? ZhuyingColors.primary : ZhuyingColors.muted,
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NativeIosDock extends StatefulWidget {
  const _NativeIosDock({
    required this.selectedIndex,
    required this.onSelected,
    required this.channel,
    required this.theme,
    required this.bottomInset,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final MethodChannel channel;
  final ZhuyingThemeDefinition theme;
  final double bottomInset;

  @override
  State<_NativeIosDock> createState() => _NativeIosDockState();
}

class _NativeIosDockState extends State<_NativeIosDock> {
  @override
  void initState() {
    super.initState();
    widget.channel.setMethodCallHandler(_handleNativeSelection);
    unawaited(_applyNativeTheme());
  }

  @override
  void didUpdateWidget(covariant _NativeIosDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channel != widget.channel) {
      oldWidget.channel.setMethodCallHandler(null);
      widget.channel.setMethodCallHandler(_handleNativeSelection);
    }
    if (oldWidget.selectedIndex != widget.selectedIndex ||
        oldWidget.theme.id != widget.theme.id) {
      unawaited(_applyNativeTheme());
    }
  }

  Future<void> _handleNativeSelection(MethodCall call) async {
    if (call.method == 'selected' && call.arguments is int) {
      widget.onSelected(call.arguments as int);
    }
  }

  Future<void> _applyNativeTheme() async {
    try {
      await widget.channel.invokeMethod<void>('theme', {
        'isMitsuri': widget.theme.isMitsuri,
        'isLight': widget.theme.isLight,
        'primary': widget.theme.primary.toARGB32(),
        'muted': widget.theme.muted.toARGB32(),
        'selectedIndex': widget.selectedIndex,
      });
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
    final characterClearance = widget.theme.isMitsuri ? 44.0 : 0.0;
    const dockHeight = 84.0;
    return Padding(
      padding: EdgeInsets.only(bottom: widget.bottomInset),
      child: SizedBox(
        height: dockHeight + characterClearance,
        child: UiKitView(
          viewType: 'zhuying/native-glass-dock',
          creationParams: {
            'selectedIndex': widget.selectedIndex,
            'isMitsuri': widget.theme.isMitsuri,
            'isLight': widget.theme.isLight,
            'primary': widget.theme.primary.toARGB32(),
            'muted': widget.theme.muted.toARGB32(),
          },
          creationParamsCodec: const StandardMessageCodec(),
          onPlatformViewCreated: (_) async {
            await _applyNativeTheme();
          },
        ),
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
      decoration: BoxDecoration(
        color: ZhuyingColors.surface,
        border: Border(right: BorderSide(color: ZhuyingColors.line)),
      ),
      padding: EdgeInsets.fromLTRB(18, 22, 14, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _BrandMark(),
          SizedBox(height: 36),
          for (var index = 0; index < destinations.length; index++)
            _RailItem(
              destination: destinations[index],
              selected: index == selectedIndex,
              onTap: () => onSelect(index),
            ),
          const Spacer(),
          Container(height: 1, color: ZhuyingColors.line),
          SizedBox(height: 14),
          Row(
            children: [
              Icon(Icons.lan_outlined, size: 16, color: ZhuyingColors.green),
              SizedBox(width: 8),
              Text(
                '$sourceCount 个片源',
                style: TextStyle(color: ZhuyingColors.muted, fontSize: 12),
              ),
            ],
          ),
          SizedBox(height: 7),
          Text(
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
    final theme = context.zhuyingTheme;
    final radius = BorderRadius.circular(theme.isMitsuri ? 12 : 7);
    final mark = SizedBox(
      width: 36,
      height: 36,
      child: ClipRRect(
        borderRadius: radius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.isMitsuri || theme.isLight
                ? theme.surface
                : Colors.black,
          ),
          child: Image.asset(
            key: ValueKey('brand-logo-${theme.id}'),
            theme.logoAsset,
            semanticLabel: theme.brandName,
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
          ),
        ),
      ),
    );
    return Row(
      children: [
        mark,
        SizedBox(width: 10),
        if (theme.isMitsuri)
          _MitsuriGradientText(
            theme.brandName,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              fontFamily: theme.displayFontFamily,
            ),
          )
        else
          Text(
            theme.brandName,
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
      padding: EdgeInsets.only(bottom: 5),
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
                SizedBox(width: 12),
                Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  size: 19,
                  color: selected ? ZhuyingColors.amber : ZhuyingColors.muted,
                ),
                SizedBox(width: 12),
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
      padding: EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: ZhuyingColors.line)),
      ),
      child: Row(
        children: [
          if (MediaQuery.sizeOf(context).width < 900) ...[
            const _BrandMark(),
            SizedBox(width: 16),
          ] else
            Expanded(
              child: Text(
                widget.destinations[widget.selectedIndex.clamp(0, 3)].label,
                style: TextStyle(
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
            SizedBox(
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
              icon: Icon(Icons.refresh_rounded, size: 20),
            ),
          if (MediaQuery.sizeOf(context).width < 650 &&
              widget.selectedIndex != 0)
            IconButton(
              tooltip: '搜索',
              onPressed: widget.onOpenSearch,
              icon: Icon(Icons.search_rounded, size: 19),
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
    this.nativeBottomInset = 0,
    super.key,
  });

  final AppStore store;
  final ValueChanged<MediaItem> onOpenItem;
  final VoidCallback onHistory;
  final ValueChanged<String> onSearch;
  final double nativeBottomInset;

  @override
  Widget build(BuildContext context) {
    final items = store.homeMedia;
    final continueItems = _uniqueContinueItems(store.history);
    final continuedTitles = store.history
        .map((item) => _continueTitleKey(item.title))
        .toSet();
    final recommendationItems = items
        .where((item) => item.isMovieOrSeries)
        .toList();
    final freshItems = recommendationItems
        .where(
          (item) => !continuedTitles.contains(_continueTitleKey(item.title)),
        )
        .toList();
    final hero = freshItems.isEmpty ? null : freshItems.first;
    final recommendations = freshItems.length > 1
        ? freshItems.skip(1).take(12).toList()
        : <MediaItem>[];
    final loadingHome = !store.hasInitialized || store.isRefreshing;
    if (context.zhuyingTheme.isMitsuri) {
      return _MitsuriHomeLayout(
        store: store,
        onOpenItem: onOpenItem,
        onHistory: onHistory,
        onSearch: onSearch,
        nativeBottomInset: nativeBottomInset,
        items: items,
        continueItems: continueItems,
        recommendationItems: recommendationItems,
        freshItems: freshItems,
        hero: hero,
        recommendations: recommendations,
        loadingHome: loadingHome,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth < 700 ? 18.0 : 36.0;
        final nativeDock =
            !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
        final bottomPadding = constraints.maxWidth < 700
            ? nativeDock
                  ? 112.0 + nativeBottomInset
                  : 34.0
            : 34.0;
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            horizontal,
            26,
            horizontal,
            bottomPadding,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
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
                      style: TextStyle(
                        color: ZhuyingColors.muted,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
              if (constraints.maxWidth < 650) ...[
                SizedBox(height: 18),
                SearchField(
                  heroEnabled: MediaQuery.sizeOf(context).width < 650,
                  readOnly: true,
                  onTap: () => onSearch(''),
                  hintText: '搜索片名或关键词',
                ),
              ],
              SizedBox(height: 22),
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
                    : SizedBox(key: ValueKey('home-hero-empty'), height: 0),
              ),
              SizedBox(height: 30),
              if (continueItems.isNotEmpty) ...[
                SectionTitle(
                  title: '接着看',
                  trailing: TextButton(
                    onPressed: onHistory,
                    child: const Text('观看历史'),
                  ),
                ),
                SizedBox(height: 14),
                SizedBox(
                  height: 118,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: continueItems.take(6).length,
                    separatorBuilder: (_, _) => SizedBox(width: 12),
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
                SizedBox(height: 30),
              ],
              SectionTitle(
                title: '为你挑选',
                trailing: Text(
                  '${freshItems.length} 部',
                  style: TextStyle(color: ZhuyingColors.muted, fontSize: 12),
                ),
              ),
              SizedBox(height: 15),
              if (recommendations.isEmpty && loadingHome)
                const _HomeLoadingGrid()
              else if (recommendations.isEmpty)
                EmptyState(
                  icon: Icons.movie_filter_outlined,
                  title: hero != null
                      ? '暂时没有更多影片'
                      : recommendationItems.isEmpty && items.isNotEmpty
                      ? '暂无电影或电视剧推荐'
                      : store.history.isEmpty
                      ? '片源暂时没有返回影片'
                      : '暂时没有新片推荐',
                  detail: hero != null
                      ? '刷新片源，查看更多影片。'
                      : recommendationItems.isEmpty && items.isNotEmpty
                      ? '今日推荐只展示电影和电视剧，其他内容可在分类或搜索中查看。'
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

class _MitsuriHomeLayout extends StatelessWidget {
  const _MitsuriHomeLayout({
    required this.store,
    required this.onOpenItem,
    required this.onHistory,
    required this.onSearch,
    required this.nativeBottomInset,
    required this.items,
    required this.continueItems,
    required this.recommendationItems,
    required this.freshItems,
    required this.hero,
    required this.recommendations,
    required this.loadingHome,
  });

  final AppStore store;
  final ValueChanged<MediaItem> onOpenItem;
  final VoidCallback onHistory;
  final ValueChanged<String> onSearch;
  final double nativeBottomInset;
  final List<MediaItem> items;
  final List<MediaItem> continueItems;
  final List<MediaItem> recommendationItems;
  final List<MediaItem> freshItems;
  final MediaItem? hero;
  final List<MediaItem> recommendations;
  final bool loadingHome;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 650;
        final side = narrow ? 18.0 : 34.0;
        // The Mitsuri dock floats above the page on compact screens. Keep a
        // generous scroll tail so the promo scene and the last poster row can
        // always be brought fully above the dock and its safe area.
        final bottomPadding = narrow
            ? 118.0 +
                  (nativeBottomInset > 0
                      ? nativeBottomInset
                      : MediaQuery.paddingOf(context).bottom)
            : 34.0;
        final railItems = recommendations.isNotEmpty
            ? recommendations.take(12).toList()
            : freshItems.skip(1).take(12).toList();
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(side, 0, side, bottomPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MitsuriIntroStage(
                height: narrow ? 302 : 338,
                heroEnabled: narrow,
                onSearch: () => onSearch(''),
                onRefresh: store.refreshSources,
                refreshing: store.isRefreshing,
                refreshMessage: store.refreshMessage,
              ),
              SizedBox(height: narrow ? 1 : 7),
              AnimatedSwitcher(
                duration: motionDuration(
                  context,
                  store.reduceMotion,
                  const Duration(milliseconds: 260),
                ),
                child: hero != null
                    ? _MitsuriHeroFeature(
                        key: ValueKey('mitsuri-hero-${hero!.id}'),
                        item: hero!,
                        onTap: () => onOpenItem(hero!),
                        reduceMotion: store.reduceMotion,
                        // A wide poster stage leaves room for the real content
                        // and keeps the floating dock out of the first frame.
                        height: narrow ? 304 : 420,
                      )
                    : loadingHome
                    ? _HomeHeroPlaceholder(
                        key: const ValueKey('mitsuri-hero-placeholder'),
                        height: narrow ? 304 : 420,
                      )
                    : const SizedBox.shrink(
                        key: ValueKey('mitsuri-hero-empty'),
                      ),
              ),
              if (continueItems.isNotEmpty) ...[
                SizedBox(height: 28),
                _MitsuriTitleRow(
                  title: '接着看',
                  trailing: TextButton(
                    onPressed: onHistory,
                    child: const Text('观看历史'),
                  ),
                ),
                SizedBox(height: 12),
                SizedBox(
                  height: 118,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsetsDirectional.only(start: 4, end: 8),
                    itemCount: continueItems.take(6).length,
                    separatorBuilder: (_, _) => SizedBox(width: 12),
                    itemBuilder: (context, index) => _ContinueTile(
                      item: continueItems[index],
                      onTap: () => onOpenItem(continueItems[index]),
                      reduceMotion: store.reduceMotion,
                    ),
                  ),
                ),
              ],
              SizedBox(height: 30),
              _MitsuriTitleRow(
                title: '为你挑选',
                trailing: Text('${freshItems.length} 部'),
              ),
              SizedBox(height: 14),
              if (railItems.isEmpty && loadingHome)
                const _HomeLoadingGrid()
              else if (railItems.isEmpty)
                EmptyState(
                  icon: Icons.movie_filter_outlined,
                  title: hero != null
                      ? '暂时没有更多影片'
                      : recommendationItems.isEmpty && items.isNotEmpty
                      ? '暂无电影或电视剧推荐'
                      : store.history.isEmpty
                      ? '片源暂时没有返回影片'
                      : '暂时没有新片推荐',
                  detail: '刷新片源，或在片源管理中添加其他来源。',
                )
              else
                _MitsuriPosterRail(
                  items: railItems,
                  favorites: store.favorites,
                  onOpenItem: onOpenItem,
                  onFavorite: store.toggleFavorite,
                  reduceMotion: store.reduceMotion,
                ),
              SizedBox(height: 28),
              _MitsuriPromoCard(),
            ],
          ),
        );
      },
    );
  }
}

class _MitsuriIntroStage extends StatelessWidget {
  const _MitsuriIntroStage({
    required this.height,
    required this.heroEnabled,
    required this.onSearch,
    required this.onRefresh,
    required this.refreshing,
    required this.refreshMessage,
  });

  final double height;
  final bool heroEnabled;
  final VoidCallback onSearch;
  final VoidCallback onRefresh;
  final bool refreshing;
  final String? refreshMessage;

  @override
  Widget build(BuildContext context) {
    final theme = context.zhuyingTheme;
    final narrow = MediaQuery.sizeOf(context).width < 650;
    const portraitScale = 0.6;
    final portraitWidth = (narrow ? 252.0 : 274.0) * portraitScale;
    final portraitHeight = portraitWidth / 0.665;
    return SizedBox(
      key: const ValueKey('mitsuri-intro-stage'),
      height: height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.canvas,
                    theme.canvas.withValues(alpha: 0.72),
                    theme.surface.withValues(alpha: 0.64),
                  ],
                ),
              ),
            ),
          ),
          if (theme.atmosphereAsset != null)
            Positioned.fill(
              child: IgnorePointer(
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (bounds) => LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.white.withValues(alpha: 0.82),
                      Colors.white.withValues(alpha: 0.72),
                      Colors.white.withValues(alpha: 0.3),
                      Colors.transparent,
                    ],
                    stops: const [0, 0.58, 0.84, 1],
                  ).createShader(bounds),
                  child: Opacity(
                    opacity: 0.58,
                    child: Image.asset(
                      theme.atmosphereAsset!,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                ),
              ),
            ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    theme.canvas.withValues(alpha: 0.9),
                    theme.canvas.withValues(alpha: 0.58),
                    theme.canvas.withValues(alpha: 0.04),
                  ],
                  stops: const [0, 0.48, 1],
                ),
              ),
            ),
          ),
          Positioned(
            right: 10,
            bottom: 25,
            width: portraitWidth,
            height: portraitHeight,
            child: IgnorePointer(
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (bounds) => LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white,
                    Colors.white,
                    Colors.white.withValues(alpha: 0.95),
                    Colors.white.withValues(alpha: 0.5),
                    Colors.transparent,
                  ],
                  stops: const [0, 0.66, 0.78, 0.9, 1],
                ).createShader(bounds),
                child: Image.asset(
                  key: const ValueKey('mitsuri-main-portrait'),
                  theme.characterBustAsset ?? theme.characterAsset!,
                  fit: BoxFit.contain,
                  alignment: Alignment.topCenter,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (context, error, stackTrace) =>
                      const SizedBox(),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 22,
            right: narrow ? 110 : 140,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 45,
                  height: 45,
                  child: RoundedBorderFrame(
                    borderRadius: BorderRadius.circular(15),
                    borderColor: Colors.white.withValues(alpha: 0.32),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: theme.surface.withValues(alpha: 0.58),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Image.asset(
                            key: ValueKey('brand-logo-${theme.id}-hero'),
                            theme.logoAsset,
                            semanticLabel: theme.brandName,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _MitsuriGradientText(
                      theme.brandName,
                      style: TextStyle(
                        fontFamily: theme.displayFontFamily,
                        fontSize: 25,
                        height: 1.05,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'MITSURI EDITION · 01',
                      style: TextStyle(
                        color: theme.accent,
                        fontSize: 8,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '「小Y专属定制·YSK赠」',
                      style: TextStyle(
                        color: theme.muted.withValues(alpha: 0.9),
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Mitsuri',
                      style: TextStyle(
                        color: const Color(0xFFFFC3D8),
                        fontFamily: theme.signatureFontFamily,
                        fontSize: 22,
                        height: 0.95,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Positioned(
            right: 2,
            top: 20,
            child: IconButton.filledTonal(
              tooltip: '刷新片源',
              onPressed: refreshing ? null : onRefresh,
              icon: Icon(
                refreshing
                    ? Icons.hourglass_top_rounded
                    : Icons.refresh_rounded,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 25,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: _MitsuriGradientText(
                              '今晚看点什么',
                              maxLines: 1,
                              style: TextStyle(
                                fontFamily: theme.displayFontFamily,
                                fontSize: narrow ? 28 : 32,
                                height: 1.08,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            key: const ValueKey('mitsuri-heading-flower'),
                            Icons.local_florist_rounded,
                            size: 17,
                            color: theme.primary,
                          ),
                        ],
                      ),
                    ),
                    if (refreshMessage != null && !narrow) ...[
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          refreshMessage!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: theme.muted, fontSize: 10),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                _MitsuriSearchField(heroEnabled: heroEnabled, onTap: onSearch),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MitsuriGradientText extends StatelessWidget {
  const _MitsuriGradientText(this.text, {required this.style, this.maxLines});

  final String text;
  final TextStyle style;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final theme = context.zhuyingTheme;
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (bounds) => LinearGradient(
        colors: [
          const Color(0xFFFFF7FA),
          theme.accent,
          const Color(0xFFD8ED9B),
        ],
        stops: const [0, 0.62, 1],
      ).createShader(bounds),
      child: Text(
        text,
        maxLines: maxLines,
        overflow: maxLines == null ? TextOverflow.clip : TextOverflow.ellipsis,
        style: style.copyWith(color: Colors.white),
      ),
    );
  }
}

class _MitsuriTitleRow extends StatelessWidget {
  const _MitsuriTitleRow({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: _MitsuriGradientText(
                  title,
                  maxLines: 1,
                  style: TextStyle(
                    fontFamily: context.zhuyingTheme.displayFontFamily,
                    fontSize: 25,
                    height: 1,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(width: 8),
              Icon(
                Icons.local_florist_rounded,
                size: 16,
                color: ZhuyingColors.primary,
              ),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class _MitsuriSearchField extends StatelessWidget {
  const _MitsuriSearchField({required this.heroEnabled, required this.onTap});

  final bool heroEnabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.zhuyingTheme;
    final radius = BorderRadius.circular(30);
    final field = Container(
      key: const ValueKey('mitsuri-search-field'),
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: theme.primary.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: RoundedBorderFrame(
        borderRadius: radius,
        borderColor: Colors.white.withValues(alpha: 0.23),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(color: const Color(0x801A111C)),
            child: Stack(
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: radius,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.center,
                          colors: [
                            Colors.white.withValues(alpha: 0.09),
                            Colors.white.withValues(alpha: 0.015),
                            Colors.transparent,
                          ],
                          stops: const [0, 0.22, 0.52],
                        ),
                      ),
                    ),
                  ),
                ),
                TextField(
                  readOnly: true,
                  onTap: onTap,
                  style: TextStyle(color: theme.text, fontSize: 15),
                  decoration: InputDecoration(
                    hintText: '搜索片名或关键词',
                    hintStyle: TextStyle(
                      color: theme.muted.withValues(alpha: 0.92),
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      size: 24,
                      color: theme.text,
                    ),
                    suffixIcon: Padding(
                      padding: const EdgeInsetsDirectional.only(end: 15),
                      child: Icon(
                        Icons.local_florist_rounded,
                        size: 19,
                        color: theme.accent,
                      ),
                    ),
                    filled: false,
                    fillColor: Colors.transparent,
                    hoverColor: Colors.transparent,
                    focusColor: Colors.transparent,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 15,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    return heroEnabled
        ? Hero(
            tag: 'zhuying.search-field',
            child: Material(color: Colors.transparent, child: field),
          )
        : field;
  }
}

class _MitsuriHeroFeature extends StatelessWidget {
  const _MitsuriHeroFeature({
    required this.item,
    required this.onTap,
    required this.reduceMotion,
    required this.height,
    super.key,
  });

  final MediaItem item;
  final VoidCallback onTap;
  final bool reduceMotion;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = context.zhuyingTheme;
    final radius = BorderRadius.circular(23);
    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: theme.primary.withValues(alpha: 0.1),
            blurRadius: 25,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: RoundedBorderFrame(
        borderRadius: radius,
        borderColor: Colors.white.withValues(alpha: 0.24),
        child: Material(
          color: theme.surface,
          child: InkWell(
            onTap: onTap,
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
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.black.withValues(alpha: 0.88),
                        Colors.black.withValues(alpha: 0.58),
                        Colors.black.withValues(alpha: 0.14),
                      ],
                      stops: const [0, 0.58, 1],
                    ),
                  ),
                ),
                if (theme.ribbonAsset != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Image.asset(
                        theme.ribbonAsset!,
                        fit: BoxFit.fill,
                        filterQuality: FilterQuality.high,
                        errorBuilder: (context, error, stackTrace) =>
                            const SizedBox.shrink(),
                      ),
                    ),
                  ),
                Positioned(
                  left: 22,
                  right: 22,
                  bottom: 22,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.local_movies_rounded,
                              size: 16,
                              color: theme.primary,
                            ),
                            const SizedBox(width: 7),
                            Text(
                              item.isDemo
                                  ? '${theme.brandName} · 演示片单'
                                  : '${theme.brandName} · 今日推荐',
                              style: TextStyle(
                                color: theme.primary,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _MitsuriGradientText(
                          item.title,
                          maxLines: 2,
                          style: TextStyle(
                            fontFamily: theme.displayFontFamily,
                            fontSize: height < 360 ? 27 : 32,
                            height: 1.08,
                            fontWeight: FontWeight.w600,
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
                        const SizedBox(height: 14),
                        _MitsuriWatchButton(onTap: onTap),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  right: 18,
                  top: 14,
                  child: IgnorePointer(
                    child: Text(
                      'Mitsuri',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontFamily: theme.signatureFontFamily,
                        fontSize: 25,
                      ),
                    ),
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

class _MitsuriWatchButton extends StatelessWidget {
  const _MitsuriWatchButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = context.zhuyingTheme;
    final radius = BorderRadius.circular(26);
    return RoundedBorderFrame(
      borderRadius: radius,
      borderColor: Colors.white.withValues(alpha: 0.42),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Ink(
              decoration: const BoxDecoration(color: Color(0xB8231522)),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              theme.primary.withValues(alpha: 0.36),
                              theme.primary.withValues(alpha: 0.14),
                              theme.secondary.withValues(alpha: 0.2),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 19,
                      vertical: 11,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.play_arrow_rounded,
                          size: 20,
                          color: theme.text,
                        ),
                        const SizedBox(width: 7),
                        Text(
                          '查看影片',
                          style: TextStyle(
                            color: theme.text,
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: radius,
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.center,
                            colors: [
                              Colors.white.withValues(alpha: 0.13),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MitsuriPosterRail extends StatelessWidget {
  const _MitsuriPosterRail({
    required this.items,
    required this.favorites,
    required this.onOpenItem,
    required this.onFavorite,
    required this.reduceMotion,
  });

  final List<MediaItem> items;
  final Set<String> favorites;
  final ValueChanged<MediaItem> onOpenItem;
  final ValueChanged<MediaItem> onFavorite;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width < 500 ? 132.0 : 166.0;
    return SizedBox(
      height: width / 0.69 + 62,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsetsDirectional.only(start: 4, end: 6),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          final item = items[index];
          final favorite = favorites.contains(item.id);
          return SizedBox(
            width: width,
            child: Semantics(
              button: true,
              label: '打开 ${item.title}',
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => onOpenItem(item),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            MediaPoster(
                              url: item.posterUrl,
                              thumbnailUrl: item.thumbnailUrl,
                              title: item.title,
                              headers: item.posterHeaders,
                              reduceMotion: reduceMotion,
                            ),
                            Positioned(
                              top: 8,
                              right: 8,
                              child: IconButton(
                                tooltip: favorite ? '取消收藏' : '收藏',
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.black.withValues(
                                    alpha: 0.64,
                                  ),
                                  foregroundColor: favorite
                                      ? ZhuyingColors.primary
                                      : Colors.white,
                                ),
                                onPressed: () => onFavorite(item),
                                icon: Icon(
                                  favorite
                                      ? Icons.bookmark
                                      : Icons.bookmark_border,
                                  size: 18,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 9),
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: ZhuyingColors.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      [
                        item.year,
                        item.genre,
                      ].where((value) => value.isNotEmpty).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: ZhuyingColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MitsuriPromoCard extends StatelessWidget {
  const _MitsuriPromoCard();

  @override
  Widget build(BuildContext context) {
    final theme = context.zhuyingTheme;
    const radius = BorderRadius.all(Radius.circular(22));
    return Material(
      color: theme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: theme.line.withValues(alpha: 0.85)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: 126,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.surface,
                      theme.surfaceRaised.withValues(alpha: 0.72),
                    ],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: CustomPaint(
                painter: _MitsuriRibbonPainter(theme, subtle: true),
              ),
            ),
            Positioned(
              left: 6,
              bottom: 0,
              width: 106,
              height: 122,
              child: Image.asset(theme.chibiAsset!, fit: BoxFit.contain),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(116, 22, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '蜜璃的观影时光',
                    style: TextStyle(
                      color: theme.text,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 7),
                  Text(
                    '把喜欢的故事，收藏进今晚的心动片单。',
                    maxLines: 2,
                    style: TextStyle(
                      color: theme.muted,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                  Spacer(),
                  Text(
                    'love every scene  ♡',
                    style: TextStyle(
                      color: theme.accent,
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
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

class _MitsuriRibbonPainter extends CustomPainter {
  const _MitsuriRibbonPainter(this.theme, {this.subtle = false});

  final ZhuyingThemeDefinition theme;
  final bool subtle;

  @override
  void paint(Canvas canvas, Size size) {
    final alpha = subtle ? 0.17 : 0.42;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = subtle ? 1.2 : 1.8
      ..shader = LinearGradient(
        colors: [
          theme.primary.withValues(alpha: alpha),
          theme.secondary.withValues(alpha: alpha * 0.75),
        ],
      ).createShader(Offset.zero & size);
    final path = Path()
      ..moveTo(-size.width * 0.08, size.height * 0.78)
      ..cubicTo(
        size.width * 0.14,
        size.height * 0.5,
        size.width * 0.35,
        size.height * 0.98,
        size.width * 0.62,
        size.height * 0.63,
      )
      ..cubicTo(
        size.width * 0.78,
        size.height * 0.42,
        size.width * 0.93,
        size.height * 0.52,
        size.width * 1.08,
        size.height * 0.18,
      );
    canvas.drawPath(path, paint);

    // A small, deliberately irregular petal field gives the header and promo
    // surfaces a sense of depth without turning every component into a neon
    // sticker. These are painted once per surface, so they stay inexpensive
    // while scrolling.
    final petalAlpha = subtle ? 0.18 : 0.34;
    final petals = [
      (0.11, 0.18, 0.72, 0.18),
      (0.34, 0.44, 0.52, -0.46),
      (0.68, 0.2, 0.68, 0.26),
      (0.86, 0.62, 0.48, -0.22),
      (0.58, 0.82, 0.42, 0.36),
    ];
    for (var index = 0; index < petals.length; index++) {
      final (x, y, scale, rotation) = petals[index];
      final center = Offset(size.width * x, size.height * y);
      final petalPaint = Paint()
        ..color = (index.isEven ? theme.primary : theme.accent).withValues(
          alpha: petalAlpha,
        );
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(rotation);
      final petal = Path()
        ..moveTo(0, -10 * scale)
        ..cubicTo(9 * scale, -7 * scale, 10 * scale, 5 * scale, 0, 10 * scale)
        ..cubicTo(
          -10 * scale,
          5 * scale,
          -9 * scale,
          -7 * scale,
          0,
          -10 * scale,
        )
        ..close();
      canvas.drawPath(petal, petalPaint);
      canvas.restore();
    }

    final heartPaint = Paint()
      ..color = theme.primary.withValues(alpha: subtle ? 0.14 : 0.25);
    for (final (x, y, scale) in [(0.77, 0.22, 0.52), (0.18, 0.7, 0.38)]) {
      final center = Offset(size.width * x, size.height * y);
      final heart = Path()
        ..moveTo(center.dx, center.dy + 8 * scale)
        ..cubicTo(
          center.dx - 15 * scale,
          center.dy - 1 * scale,
          center.dx - 8 * scale,
          center.dy - 10 * scale,
          center.dx,
          center.dy - 3 * scale,
        )
        ..cubicTo(
          center.dx + 8 * scale,
          center.dy - 10 * scale,
          center.dx + 15 * scale,
          center.dy - 1 * scale,
          center.dx,
          center.dy + 8 * scale,
        )
        ..close();
      canvas.drawPath(heart, heartPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _MitsuriRibbonPainter oldDelegate) => false;
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
              if (!reduceMotion) Positioned.fill(child: _CurtainLight()),
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
              if (context.zhuyingTheme.characterAsset != null)
                Positioned(
                  right: -8,
                  bottom: -28,
                  width: (height * 0.62).clamp(154.0, 250.0).toDouble(),
                  height: height * 1.35,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: 0.2,
                      child: Image.asset(
                        context.zhuyingTheme.characterAsset!,
                        fit: BoxFit.contain,
                        alignment: Alignment.bottomRight,
                        filterQuality: FilterQuality.medium,
                      ),
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
                          Icon(
                            Icons.wb_twilight_rounded,
                            size: 15,
                            color: ZhuyingColors.amber,
                          ),
                          SizedBox(width: 7),
                          Text(
                            item.isDemo
                                ? '${context.zhuyingTheme.brandName} · 演示片单'
                                : '${context.zhuyingTheme.brandName} · 今日推荐',
                            style: TextStyle(
                              color: ZhuyingColors.amber,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 9),
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          height: 1.12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 9),
                      Text(
                        [
                          item.year,
                          item.region,
                          item.genre,
                          item.remarks,
                        ].where((value) => value.isNotEmpty).join('  ·  '),
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      if (item.description.isNotEmpty) ...[
                        SizedBox(height: 8),
                        Text(
                          item.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            height: 1.45,
                          ),
                        ),
                      ],
                      SizedBox(height: 15),
                      FilledButton.icon(
                        onPressed: onTap,
                        icon: Icon(Icons.play_arrow_rounded, size: 19),
                        label: const Text('查看影片'),
                        style: FilledButton.styleFrom(
                          backgroundColor: ZhuyingColors.amber,
                          foregroundColor: const Color(0xFF211A10),
                          padding: EdgeInsets.symmetric(
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
            Center(
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
                  SizedBox(height: 12),
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
            child: Center(
              child: Icon(
                Icons.movie_outlined,
                color: ZhuyingColors.line,
                size: 26,
              ),
            ),
          ),
        ),
        SizedBox(height: 9),
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
        SizedBox(height: 7),
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
    if (context.zhuyingTheme.isMitsuri) {
      return _buildMitsuriTile(context);
    }
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
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 5),
                child: SizedBox(
                  width: 78,
                  child: AspectRatio(
                    aspectRatio: 0.78,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
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
                ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.all(12),
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
                          style: TextStyle(
                            color: ZhuyingColors.text,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        _continueProgressText(item),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: ZhuyingColors.amber,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 9),
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

  Widget _buildMitsuriTile(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(11));
    return SizedBox(
      width: 276,
      child: Material(
        color: ZhuyingColors.surface,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.all(5),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: SizedBox(
                    width: 74,
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
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(9),
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
                            style: TextStyle(
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
                          style: TextStyle(
                            color: ZhuyingColors.amber,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 9),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: item.progress,
                            minHeight: 4,
                            color: ZhuyingColors.amber,
                            backgroundColor: ZhuyingColors.line,
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
        padding: EdgeInsets.symmetric(vertical: 20),
        child: Text(
          '暂无影片',
          style: TextStyle(color: ZhuyingColors.muted, fontSize: 12),
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
