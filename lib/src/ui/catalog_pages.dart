import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_store.dart';
import '../models.dart';
import '../source_importer.dart';
import '../theme/app_theme.dart';
import 'widgets.dart';

const commonGenres = [
  '剧情',
  '喜剧',
  '爱情',
  '动作',
  '科幻',
  '惊悚',
  '悬疑',
  '恐怖',
  '犯罪',
  '动画',
  '家庭',
  '奇幻',
  '战争',
  '青春',
  '伦理',
];

List<String> _genresFromItems(Iterable<MediaItem> items) {
  final genres = items
      .expand((item) => normalizeGenres(item.genreLabels))
      .toSet()
      .toList();
  genres.sort();
  return genres;
}

class CategoriesPage extends StatefulWidget {
  const CategoriesPage({
    required this.store,
    required this.onOpenItem,
    this.dockClearance = 0,
    super.key,
  });

  final AppStore store;
  final ValueChanged<MediaItem> onOpenItem;
  final double dockClearance;

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  final ScrollController _scrollController = ScrollController();
  Set<String> _genres = {};
  String _year = '全部年份';
  String _region = '全部地区';
  String _source = '全部片源';
  bool _showMoreGenres = false;
  bool _didPrefetchCatalog = false;
  bool _userScrollArmed = false;
  int _underfilledBatches = 0;
  bool _underfilledFillScheduled = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    widget.store.addListener(_onStoreChanged);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _maybePrefetchCatalog(),
    );
  }

  @override
  void didUpdateWidget(covariant CategoriesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      oldWidget.store.removeListener(_onStoreChanged);
      widget.store.addListener(_onStoreChanged);
    }
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onStoreChanged() {
    if (!mounted) return;
    setState(() {});
    _maybePrefetchCatalog();
    _scheduleUnderfilledFill();
    _onScroll();
  }

  void _maybePrefetchCatalog() {
    if (_didPrefetchCatalog ||
        _hasServerFilters ||
        widget.store.isRefreshing ||
        widget.store.isLoadingMoreCatalog ||
        !widget.store.hasMoreCatalog) {
      return;
    }
    _didPrefetchCatalog = true;
    unawaited(_loadNextBatch());
  }

  void _onScroll() {
    if (!_scrollController.hasClients ||
        !_userScrollArmed ||
        _scrollController.position.extentAfter > 520 ||
        widget.store.isLoadingMoreCatalog ||
        !_hasMore) {
      return;
    }
    _userScrollArmed = false;
    unawaited(_loadSelectedCategory());
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification &&
        notification.dragDetails != null) {
      _userScrollArmed = true;
      _onScroll();
    }
    return false;
  }

  bool get _hasServerFilters =>
      _genres.isNotEmpty ||
      _year != '全部年份' ||
      _region != '全部地区' ||
      _source != '全部片源';

  int get _visibleItemTarget {
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 1280
        ? 7
        : width >= 1000
        ? 6
        : width >= 760
        ? 5
        : width >= 520
        ? 4
        : 3;
    return columns * 4;
  }

  bool _matchesFilters(MediaItem item) {
    final genreMatch =
        _genres.isEmpty ||
        normalizeGenres(item.genreLabels).any(_genres.contains);
    return genreMatch &&
        (_year == '全部年份' || item.year == _year) &&
        (_region == '全部地区' || item.region == _region) &&
        (_source == '全部片源' || item.sourceName == _source);
  }

  bool get _hasMore => _hasServerFilters
      ? widget.store.hasMoreCategoryPages(
          genres: _genres,
          year: _year == '全部年份' ? null : _year,
          region: _region == '全部地区' ? null : _region,
          sourceName: _source == '全部片源' ? null : _source,
        )
      : widget.store.hasMoreCatalog;

  void _scheduleUnderfilledFill() {
    final matchingCount = widget.store.categoryMedia
        .where(_matchesFilters)
        .length;
    if (!_hasServerFilters ||
        !_hasMore ||
        matchingCount >= _visibleItemTarget ||
        widget.store.isLoadingMoreCatalog ||
        _underfilledBatches >= 2 ||
        _underfilledFillScheduled) {
      return;
    }
    _underfilledFillScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _underfilledFillScheduled = false;
      if (!mounted ||
          widget.store.isLoadingMoreCatalog ||
          !_hasMore ||
          widget.store.categoryMedia.where(_matchesFilters).length >=
              _visibleItemTarget) {
        return;
      }
      _underfilledBatches++;
      unawaited(_loadSelectedCategory());
    });
  }

  Future<void> _loadNextBatch() => widget.store.loadMoreCatalog(
    genres: _genres,
    year: _year == '全部年份' ? null : _year,
    region: _region == '全部地区' ? null : _region,
    sourceName: _source == '全部片源' ? null : _source,
    pageLimit: 2,
  );

  Future<void> _loadSelectedCategory() => _loadNextBatch();

  void _resetEmptySearchBudget() {
    _underfilledBatches = 0;
    _userScrollArmed = false;
  }

  void _toggleGenre(String genre) {
    setState(() {
      final next = {..._genres};
      if (!next.add(genre)) next.remove(genre);
      _genres = next;
      _resetEmptySearchBudget();
    });
    if (_hasServerFilters) unawaited(_loadSelectedCategory());
  }

  @override
  Widget build(BuildContext context) {
    final availableItems = widget.store.categoryMedia;
    final discoveredGenres = _genresFromItems(availableItems);
    final sources = [
      '全部片源',
      ...widget.store.enabledSources.map((source) => source.name).toSet(),
    ];
    final years = _sortedValues(availableItems.map((item) => item.year))
      ..insert(0, '全部年份');
    final regions = _sortedValues(availableItems.map((item) => item.region))
      ..insert(0, '全部地区');
    final items = availableItems.where(_matchesFilters).toList();
    final activeFilterCount =
        _genres.length +
        (_year == '全部年份' ? 0 : 1) +
        (_region == '全部地区' ? 0 : 1) +
        (_source == '全部片源' ? 0 : 1);
    final hasMore = _hasMore;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scheduleUnderfilledFill();
    });

    return NotificationListener<ScrollNotification>(
      onNotification: _onScrollNotification,
      child: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(28, 28, 28, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionTitle(title: '片库分类'),
                  SizedBox(height: 22),
                  GenreFilterBar(
                    genres: discoveredGenres,
                    selected: _genres,
                    expanded: _showMoreGenres,
                    allLabel: '全部',
                    onExpandedChanged: (value) =>
                        setState(() => _showMoreGenres = value),
                    onToggle: _toggleGenre,
                    onClear: () => setState(() => _genres = {}),
                  ),
                  SizedBox(height: 14),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          final selection =
                              await showModalBottomSheet<
                                _CategoryFilterSelection
                              >(
                                context: context,
                                useSafeArea: true,
                                isScrollControlled: true,
                                builder: (context) => _CategoryFilterSheet(
                                  years: years,
                                  regions: regions,
                                  sources: sources,
                                  initial: _CategoryFilterSelection(
                                    year: _year,
                                    region: _region,
                                    source: _source,
                                  ),
                                ),
                              );
                          if (selection == null || !mounted) return;
                          setState(() {
                            _year = selection.year;
                            _region = selection.region;
                            _source = selection.source;
                            _resetEmptySearchBudget();
                          });
                          unawaited(_loadSelectedCategory());
                        },
                        icon: Icon(Icons.tune_rounded, size: 18),
                        label: Text(
                          activeFilterCount == 0
                              ? '筛选'
                              : '筛选 · $activeFilterCount',
                        ),
                      ),
                      if (activeFilterCount > 0) ...[
                        SizedBox(width: 8),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _genres = {};
                              _year = '全部年份';
                              _region = '全部地区';
                              _source = '全部片源';
                              _resetEmptySearchBudget();
                            });
                          },
                          child: const Text('重置'),
                        ),
                      ],
                    ],
                  ),
                  SizedBox(height: 22),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        '${items.length} 部影片',
                        style: TextStyle(
                          color: ZhuyingColors.text,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        widget.store.isLoadingMoreCatalog
                            ? '已载入 ${availableItems.length} 部 · 正在继续加载'
                            : '已载入 ${availableItems.length} 部',
                        style: TextStyle(
                          color: ZhuyingColors.muted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 14),
                ],
              ),
            ),
          ),
          if (items.isNotEmpty)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(28, 14, 28, 0),
              sliver: SliverLayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.crossAxisExtent;
                  final columns = width >= 1280
                      ? 7
                      : width >= 1000
                      ? 6
                      : width >= 760
                      ? 5
                      : width >= 520
                      ? 4
                      : 3;
                  return SliverGrid.builder(
                    itemCount: items.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 14,
                      mainAxisSpacing: 17,
                      childAspectRatio: 0.48,
                    ),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return PosterCard(
                        key: ValueKey(item.id),
                        item: item,
                        onTap: () => widget.onOpenItem(item),
                        favorite: widget.store.favorites.contains(item.id),
                        onFavorite: () => widget.store.toggleFavorite(item),
                        reduceMotion: widget.store.reduceMotion,
                      );
                    },
                  );
                },
              ),
            )
          else if (availableItems.isEmpty)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(28, 20, 28, 0),
              sliver: SliverToBoxAdapter(
                child: EmptyState(
                  icon: widget.store.isRefreshing
                      ? Icons.downloading_rounded
                      : Icons.video_library_outlined,
                  title: widget.store.isRefreshing ? '正在载入片库' : '片库暂时没有影片',
                  detail: widget.store.isRefreshing
                      ? '影片载入后会显示在这里。'
                      : widget.store.refreshMessage ?? '刷新片源后再试。',
                  action: widget.store.isRefreshing
                      ? null
                      : TextButton.icon(
                          onPressed: widget.store.refreshSources,
                          icon: Icon(Icons.refresh_rounded),
                          label: const Text('刷新片源'),
                        ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: EdgeInsets.fromLTRB(28, 20, 28, 0),
              sliver: SliverToBoxAdapter(
                child: EmptyState(
                  icon: Icons.filter_alt_off_outlined,
                  title: '当前已加载影片中没有匹配项',
                  detail: hasMore
                      ? '正在后台查找符合条件的影片。'
                      : '已检查当前可用的 ${availableItems.length} 部影片，可重置或调整筛选条件。',
                  action: !hasMore
                      ? TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _genres = {};
                              _year = '全部年份';
                              _region = '全部地区';
                              _source = '全部片源';
                              _resetEmptySearchBudget();
                            });
                          },
                          icon: Icon(Icons.filter_alt_off_outlined),
                          label: const Text('重置筛选'),
                        )
                      : null,
                ),
              ),
            ),
          if (widget.store.isLoadingMoreCatalog || hasMore)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(28, 24, 28, 36),
              sliver: SliverToBoxAdapter(
                child: Center(
                  child: widget.store.isLoadingMoreCatalog
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            SizedBox(width: 10),
                            Text('正在加载影片…'),
                          ],
                        )
                      : SizedBox(height: 2),
                ),
              ),
            ),
          SliverToBoxAdapter(
            child: SizedBox(height: 36 + widget.dockClearance),
          ),
        ],
      ),
    );
  }
}

class GenreFilterBar extends StatelessWidget {
  const GenreFilterBar({
    required this.genres,
    required this.selected,
    required this.expanded,
    required this.allLabel,
    required this.onExpandedChanged,
    required this.onToggle,
    required this.onClear,
    super.key,
  });

  final List<String> genres;
  final Set<String> selected;
  final bool expanded;
  final String allLabel;
  final ValueChanged<bool> onExpandedChanged;
  final ValueChanged<String> onToggle;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final additional = genres
        .where((genre) => !commonGenres.contains(genre))
        .toList();
    final visibleCommon = <String>{
      ...commonGenres,
      ...selected.where((genre) => !commonGenres.contains(genre)),
    }.toList();
    final allSelected = selected.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 7,
          runSpacing: 7,
          children: [
            _FilterChoice(
              label: allLabel,
              selected: allSelected,
              onTap: onClear,
            ),
            for (final genre in visibleCommon)
              _FilterChoice(
                label: genre,
                selected: selected.contains(genre),
                onTap: () => onToggle(genre),
              ),
            if (additional.isNotEmpty)
              TextButton.icon(
                onPressed: () => onExpandedChanged(!expanded),
                icon: Icon(
                  expanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 17,
                ),
                label: Text(expanded ? '收起更多' : '更多类型'),
                style: TextButton.styleFrom(
                  foregroundColor: ZhuyingColors.muted,
                  visualDensity: VisualDensity.compact,
                ),
              ),
          ],
        ),
        AnimatedSize(
          duration: motionDuration(
            context,
            false,
            const Duration(milliseconds: 200),
          ),
          curve: Curves.easeInOutCubic,
          alignment: Alignment.topCenter,
          child: expanded && additional.isNotEmpty
              ? Padding(
                  padding: EdgeInsets.only(top: 7),
                  child: Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      for (final genre in additional)
                        _FilterChoice(
                          label: genre,
                          selected: selected.contains(genre),
                          onTap: () => onToggle(genre),
                        ),
                    ],
                  ),
                )
              : SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

class _CategoryFilterSelection {
  const _CategoryFilterSelection({
    required this.year,
    required this.region,
    required this.source,
  });

  final String year;
  final String region;
  final String source;
}

class _CategoryFilterSheet extends StatefulWidget {
  const _CategoryFilterSheet({
    required this.years,
    required this.regions,
    required this.sources,
    required this.initial,
  });

  final List<String> years;
  final List<String> regions;
  final List<String> sources;
  final _CategoryFilterSelection initial;

  @override
  State<_CategoryFilterSheet> createState() => _CategoryFilterSheetState();
}

class _CategoryFilterSheetState extends State<_CategoryFilterSheet> {
  late String _year = widget.initial.year;
  late String _region = widget.initial.region;
  late String _source = widget.initial.source;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 8, 20, 20 + bottomInset),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ZhuyingColors.line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '筛选影片',
                      style: TextStyle(
                        color: ZhuyingColors.text,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(onPressed: _reset, child: const Text('重置')),
                ],
              ),
              SizedBox(height: 8),
              _CategoryFilterField(
                title: '年份',
                icon: Icons.calendar_month_outlined,
                value: _year,
                options: widget.years,
                onChanged: (value) => setState(() => _year = value),
              ),
              SizedBox(height: 14),
              _CategoryFilterField(
                title: '地区',
                icon: Icons.public_outlined,
                value: _region,
                options: widget.regions,
                onChanged: (value) => setState(() => _region = value),
              ),
              SizedBox(height: 14),
              _CategoryFilterField(
                title: '片源',
                icon: Icons.lan_outlined,
                value: _source,
                options: widget.sources,
                onChanged: (value) => setState(() => _source = value),
              ),
              SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(
                    _CategoryFilterSelection(
                      year: _year,
                      region: _region,
                      source: _source,
                    ),
                  ),
                  child: const Text('应用筛选'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _reset() {
    setState(() {
      _year = '全部年份';
      _region = '全部地区';
      _source = '全部片源';
    });
  }
}

class _CategoryFilterField extends StatelessWidget {
  const _CategoryFilterField({
    required this.title,
    required this.icon,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String title;
  final IconData icon;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = options.contains(value) ? value : options.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: ZhuyingColors.muted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: selected,
          isExpanded: true,
          decoration: InputDecoration(
            prefixIcon: Icon(icon, size: 18),
            isDense: true,
          ),
          items: options
              .map(
                (option) => DropdownMenuItem(
                  value: option,
                  child: Text(option, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: (next) {
            if (next != null) onChanged(next);
          },
        ),
      ],
    );
  }
}

class SearchPage extends StatefulWidget {
  const SearchPage({
    required this.store,
    required this.initialQuery,
    required this.onOpenItem,
    this.heroEnabled = true,
    super.key,
  });

  final AppStore store;
  final String initialQuery;
  final ValueChanged<MediaItem> onOpenItem;
  final bool heroEnabled;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  Timer? _debounce;
  List<MediaItem> _results = const [];
  Set<String> _genres = {};
  bool _showAllSearchGenres = false;
  String _source = '全部片源';
  String _year = '全部年份';
  String _region = '全部地区';
  bool _searching = false;
  bool _searchFailed = false;
  bool _searchUnsupported = false;
  bool _hasSearched = false;
  int _failedSourceCount = 0;
  int _searchableSourceCount = 0;
  int _localMatchCount = 0;
  int _remoteMatchCount = 0;
  String _activeTerm = '';
  final Set<String> _removedSearchTerms = {};
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStoreChanged);
    _controller = TextEditingController(text: widget.initialQuery);
    _focusNode = FocusNode();
    _results = widget.store.allMedia;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Future<void>.delayed(
        motionDuration(
          context,
          widget.store.reduceMotion,
          const Duration(milliseconds: 400),
        ),
        () {
          if (mounted) _focusNode.requestFocus();
        },
      );
      if (widget.initialQuery.trim().isNotEmpty) {
        _runSearch(widget.initialQuery, saveToHistory: true);
      }
    });
    if (widget.initialQuery.trim().isEmpty &&
        widget.store.searchHistory.isNotEmpty) {
      _results = const [];
    }
  }

  @override
  void didUpdateWidget(covariant SearchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialQuery != widget.initialQuery) {
      _controller.text = widget.initialQuery;
      _runSearch(widget.initialQuery, saveToHistory: true);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.store.removeListener(_onStoreChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _removeSearchTerm(String term) async {
    setState(() => _removedSearchTerms.add(term.toLowerCase()));
    await widget.store.removeSearchTerm(term);
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _runSearch(value, remote: false, saveToHistory: false);
    if (value.trim().isEmpty) return;
    _debounce = Timer(
      const Duration(milliseconds: 650),
      () => _runSearch(value, remote: true, saveToHistory: false),
    );
  }

  Future<void> _runSearch(
    String value, {
    bool remote = true,
    bool saveToHistory = true,
  }) async {
    _debounce?.cancel();
    final currentRequest = ++_requestId;
    final term = value.trim();
    final queryChanged = term != _activeTerm;
    if (queryChanged) {
      _activeTerm = term;
      _genres = {};
      _showAllSearchGenres = false;
      _source = '全部片源';
      _year = '全部年份';
      _region = '全部地区';
      _failedSourceCount = 0;
      _searchableSourceCount = 0;
      _localMatchCount = 0;
      _remoteMatchCount = 0;
    }
    if (term.isEmpty) {
      widget.store.cancelPendingSearch();
      setState(() {
        _results = const [];
        _searching = false;
        _searchFailed = false;
        _searchUnsupported = false;
        _hasSearched = false;
        _localMatchCount = 0;
        _remoteMatchCount = 0;
      });
      return;
    }
    _removedSearchTerms.remove(term.toLowerCase());
    if (saveToHistory) unawaited(widget.store.addSearchTerm(term));
    if (mounted) {
      setState(() {
        _searching = remote;
        _searchFailed = false;
        _searchUnsupported = false;
        _hasSearched = remote;
        if (queryChanged) _results = const [];
      });
    }
    final result = await widget.store.search(
      term,
      remote: remote,
      onCounts: (counts) {
        if (!mounted || currentRequest != _requestId) return;
        setState(() {
          _localMatchCount = counts.localMatches;
          _remoteMatchCount = counts.remoteMatches;
        });
      },
      onComplete: (outcome) {
        if (!mounted || currentRequest != _requestId) return;
        setState(() {
          _searchFailed =
              outcome.enabledSourceCount == 0 ||
              (outcome.searchableSourceCount > 0 &&
                  outcome.failedSourceCount > 0);
          _searchUnsupported =
              outcome.enabledSourceCount > 0 &&
              outcome.searchableSourceCount == 0;
          _failedSourceCount = outcome.failedSourceCount;
          _searchableSourceCount = outcome.searchableSourceCount;
          _localMatchCount = outcome.localMatchCount;
          _remoteMatchCount = outcome.remoteMatchCount;
        });
      },
      onResults: (results) {
        if (!mounted || currentRequest != _requestId) return;
        setState(() => _results = results);
      },
    );
    if (!mounted || currentRequest != _requestId) return;
    setState(() {
      _results = result;
      _searching = false;
      _hasSearched = remote;
    });
  }

  @override
  Widget build(BuildContext context) {
    final discoveredGenres = _genresFromItems(_results);
    final sources = [
      '全部片源',
      ...widget.store.enabledSources.map((source) => source.name).toSet(),
    ];
    final years = _sortedValues(_results.map((item) => item.year))
      ..insert(0, '全部年份');
    final regions = _sortedValues(_results.map((item) => item.region))
      ..insert(0, '全部地区');
    final filtered = _results.where((item) {
      return (_genres.isEmpty ||
              normalizeGenres(item.genreLabels).any(_genres.contains)) &&
          (_year == '全部年份' || item.year == _year) &&
          (_region == '全部地区' || item.region == _region) &&
          (_source == '全部片源' || item.sourceName == _source);
    }).toList();
    final activeFilterCount =
        _genres.length +
        (_year == '全部年份' ? 0 : 1) +
        (_region == '全部地区' ? 0 : 1) +
        (_source == '全部片源' ? 0 : 1);

    return Scaffold(
      backgroundColor: ZhuyingColors.canvas,
      body: ZhuyingThemeBackdrop(
        reduceMotion: widget.store.reduceMotion,
        child: SafeArea(
          child: Column(
            children: [
              Container(
                height: 64,
                padding: EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: ZhuyingColors.line)),
                ),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: '返回',
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: Icon(Icons.arrow_back_rounded),
                    ),
                    Expanded(
                      child: SearchField(
                        heroEnabled: widget.heroEnabled,
                        controller: _controller,
                        focusNode: _focusNode,
                        hintText: '搜索片名或关键词',
                        onChanged: _onChanged,
                        onSubmitted: (value) => _runSearch(value),
                        suffixIcon: _controller.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: '清空搜索',
                                onPressed: () {
                                  _controller.clear();
                                  _runSearch('', remote: false);
                                },
                                icon: Icon(Icons.close_rounded),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  key: const PageStorageKey<String>('search-content'),
                  padding: EdgeInsets.fromLTRB(22, 22, 22, 36),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_controller.text.isEmpty &&
                          widget.store.searchHistory.isNotEmpty)
                        _SearchHistorySection(
                          terms: widget.store.searchHistory
                              .where(
                                (term) => !_removedSearchTerms.contains(
                                  term.toLowerCase(),
                                ),
                              )
                              .toList(),
                          onSelect: (term) {
                            _controller.text = term;
                            _runSearch(term);
                          },
                          onRemove: _removeSearchTerm,
                          onClear: widget.store.clearSearchHistory,
                        ),
                      if (_controller.text.isEmpty &&
                          widget.store.searchHistory.isEmpty)
                        Padding(
                          padding: EdgeInsets.only(top: 42),
                          child: EmptyState(
                            icon: Icons.search_rounded,
                            title: '搜索影片',
                            detail: '输入片名、演员或关键词查找影片。',
                          ),
                        ),
                      if (_controller.text.isNotEmpty) ...[
                        SizedBox(height: 4),
                        GenreFilterBar(
                          genres: discoveredGenres,
                          selected: _genres,
                          expanded: _showAllSearchGenres,
                          allLabel: '全部类型',
                          onExpandedChanged: (value) =>
                              setState(() => _showAllSearchGenres = value),
                          onToggle: (genre) => setState(() {
                            final next = {..._genres};
                            if (!next.add(genre)) next.remove(genre);
                            _genres = next;
                          }),
                          onClear: () => setState(() => _genres = {}),
                        ),
                        SizedBox(height: 8),
                        Wrap(
                          spacing: 10,
                          runSpacing: 6,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () async {
                                final selection =
                                    await showModalBottomSheet<
                                      _CategoryFilterSelection
                                    >(
                                      context: context,
                                      useSafeArea: true,
                                      isScrollControlled: true,
                                      builder: (context) =>
                                          _CategoryFilterSheet(
                                            years: years,
                                            regions: regions,
                                            sources: sources,
                                            initial: _CategoryFilterSelection(
                                              year: _year,
                                              region: _region,
                                              source: _source,
                                            ),
                                          ),
                                    );
                                if (selection == null || !mounted) return;
                                setState(() {
                                  _year = selection.year;
                                  _region = selection.region;
                                  _source = selection.source;
                                });
                              },
                              icon: Icon(Icons.tune_rounded, size: 17),
                              label: Text(
                                activeFilterCount == 0
                                    ? '筛选'
                                    : '筛选 · $activeFilterCount',
                              ),
                            ),
                            if (activeFilterCount > 0)
                              TextButton(
                                onPressed: () => setState(() {
                                  _genres = {};
                                  _year = '全部年份';
                                  _region = '全部地区';
                                  _source = '全部片源';
                                }),
                                child: const Text('重置'),
                              ),
                          ],
                        ),
                        SizedBox(height: 24),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${filtered.length} 部影片',
                                style: TextStyle(
                                  color: ZhuyingColors.muted,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            if (_searching)
                              SizedBox(
                                width: 15,
                                height: 15,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                          ],
                        ),
                        SizedBox(height: 5),
                        Text(
                          '本地片库 ${widget.store.localSearchableItemCount} 部'
                          '  ·  本地匹配 $_localMatchCount'
                          '  ·  片源新增 $_remoteMatchCount',
                          style: TextStyle(
                            color: ZhuyingColors.muted,
                            fontSize: 10,
                          ),
                        ),
                        SizedBox(height: 14),
                        if (_searchUnsupported && filtered.isEmpty)
                          const EmptyState(
                            icon: Icons.info_outline_rounded,
                            title: '当前片源暂不支持搜索',
                            detail: '启用 CMS、Jellyfin 或 Emby 片源后即可搜索。',
                          )
                        else if (_searchFailed && filtered.isEmpty)
                          EmptyState(
                            icon: Icons.wifi_off_rounded,
                            title: widget.store.enabledSources.isEmpty
                                ? '没有启用片源'
                                : _failedSourceCount >= _searchableSourceCount
                                ? '片源暂时无法连接'
                                : '部分片源连接失败',
                            detail: widget.store.enabledSources.isEmpty
                                ? '请先到片源页面启用至少一个片源。'
                                : _failedSourceCount >= _searchableSourceCount
                                ? '检查网络或片源状态后重试。'
                                : '部分片源未返回结果，请检查网络或稍后重试。',
                            action: TextButton.icon(
                              onPressed: () => _runSearch(_controller.text),
                              icon: Icon(Icons.refresh_rounded),
                              label: const Text('重试'),
                            ),
                          )
                        else if (_searchFailed)
                          Padding(
                            padding: EdgeInsets.only(bottom: 14),
                            child: Text(
                              _failedSourceCount >= _searchableSourceCount
                                  ? '片源暂时无法连接，以下为本地已保存的匹配结果。'
                                  : '部分片源连接失败，以下为当前可用的搜索结果。',
                              style: TextStyle(
                                color: ZhuyingColors.muted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        if (!_searchUnsupported &&
                            !_searchFailed &&
                            filtered.isEmpty &&
                            !_searching &&
                            _hasSearched)
                          const EmptyState(
                            icon: Icons.search_off_rounded,
                            title: '没有找到匹配影片',
                            detail: '试试更短的片名或其他关键词。',
                          ),
                        if (filtered.isNotEmpty)
                          _PageGrid(
                            key: ValueKey(
                              'search-${_genres.toList()..sort()}-$_year-$_region-$_source-${filtered.map((item) => item.id).take(3).join(',')}',
                            ),
                            items: filtered,
                            store: widget.store,
                            onOpenItem: widget.onOpenItem,
                          ),
                        if (filtered.isEmpty && _searching)
                          Padding(
                            padding: EdgeInsets.symmetric(vertical: 18),
                            child: Center(
                              child: Text(
                                '正在搜索片源…',
                                style: TextStyle(
                                  color: ZhuyingColors.muted,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                      ],
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

class _SearchHistorySection extends StatelessWidget {
  const _SearchHistorySection({
    required this.terms,
    required this.onSelect,
    required this.onRemove,
    required this.onClear,
  });

  final List<String> terms;
  final ValueChanged<String> onSelect;
  final Future<void> Function(String) onRemove;
  final Future<void> Function() onClear;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          title: '最近搜索',
          trailing: TextButton(
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('清空搜索记录？'),
                  content: const Text('此操作只会删除本机保存的搜索词。'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('清空'),
                    ),
                  ],
                ),
              );
              if (confirmed == true) await onClear();
            },
            child: const Text('清空'),
          ),
        ),
        SizedBox(height: 10),
        for (final term in terms)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: Icon(Icons.history_rounded, size: 19),
            title: Text(term, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => onSelect(term),
            trailing: IconButton(
              tooltip: '删除搜索记录：$term',
              onPressed: () async => onRemove(term),
              icon: Icon(Icons.close_rounded, size: 18),
            ),
          ),
      ],
    );
  }
}

class HistoryPage extends StatelessWidget {
  const HistoryPage({required this.store, required this.onOpenItem, super.key});

  final AppStore store;
  final ValueChanged<MediaItem> onOpenItem;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(28, 28, 28, 36),
      child: _HistoryContent(store: store, onOpenItem: onOpenItem),
    );
  }
}

class _HistoryContent extends StatelessWidget {
  const _HistoryContent({required this.store, required this.onOpenItem});

  final AppStore store;
  final ValueChanged<MediaItem> onOpenItem;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          title: '观看历史',
          trailing: store.history.isEmpty
              ? null
              : IconButton(
                  tooltip: '清空历史',
                  onPressed: () => _confirmClear(context),
                  icon: Icon(Icons.delete_outline_rounded),
                ),
        ),
        SizedBox(height: 18),
        if (store.history.isEmpty)
          const EmptyState(
            icon: Icons.history_rounded,
            title: '还没有观看记录',
            detail: '播放过的影片会出现在这里。',
          )
        else
          ...store.history.map(
            (item) => _HistoryRow(
              item: item,
              onTap: () => onOpenItem(item),
              reduceMotion: store.reduceMotion,
            ),
          ),
      ],
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空观看历史？'),
        content: const Text('此操作只会删除本机保存的观看记录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed == true) await store.clearHistory();
  }
}

enum _MineSection { history, favorites, settings }

class MinePage extends StatefulWidget {
  const MinePage({
    required this.store,
    required this.onOpenItem,
    this.dockClearance = 0,
    super.key,
  });

  final AppStore store;
  final ValueChanged<MediaItem> onOpenItem;
  final double dockClearance;

  @override
  State<MinePage> createState() => _MinePageState();
}

class _MinePageState extends State<MinePage> {
  _MineSection _section = _MineSection.history;

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final favoriteItems = store.allMedia
        .where((item) => store.favorites.contains(item.id))
        .toList();
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(22, 22, 22, 34 + widget.dockClearance),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionTitle(
                title: '我的',
                trailing: Text(
                  '观看 ${store.history.length}  ·  收藏 ${store.favorites.length}',
                  style: TextStyle(color: ZhuyingColors.muted, fontSize: 11),
                ),
              ),
              SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<_MineSection>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: _MineSection.history,
                      icon: Icon(Icons.history_rounded),
                      label: Text('历史'),
                    ),
                    ButtonSegment(
                      value: _MineSection.favorites,
                      icon: Icon(Icons.bookmark_border_rounded),
                      label: Text('收藏'),
                    ),
                    ButtonSegment(
                      value: _MineSection.settings,
                      icon: Icon(Icons.settings_outlined),
                      label: Text('设置'),
                    ),
                  ],
                  selected: {_section},
                  onSelectionChanged: (value) =>
                      setState(() => _section = value.single),
                ),
              ),
              SizedBox(height: 22),
              AnimatedSwitcher(
                duration: motionDuration(
                  context,
                  store.reduceMotion,
                  const Duration(milliseconds: 240),
                ),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: KeyedSubtree(
                  key: ValueKey(_section),
                  child: switch (_section) {
                    _MineSection.history => _HistoryContent(
                      store: store,
                      onOpenItem: widget.onOpenItem,
                    ),
                    _MineSection.favorites => _FavoritesContent(
                      items: favoriteItems,
                      store: store,
                      onOpenItem: widget.onOpenItem,
                    ),
                    _MineSection.settings => _SettingsContent(store: store),
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FavoritesContent extends StatelessWidget {
  const _FavoritesContent({
    required this.items,
    required this.store,
    required this.onOpenItem,
  });

  final List<MediaItem> items;
  final AppStore store;
  final ValueChanged<MediaItem> onOpenItem;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(title: '我的收藏', trailing: Text('${items.length} 部')),
        SizedBox(height: 18),
        if (items.isEmpty)
          const EmptyState(
            icon: Icons.bookmark_border_rounded,
            title: '还没有收藏',
            detail: '收藏的影片会集中显示在这里。',
          )
        else
          _PageGrid(items: items, store: store, onOpenItem: onOpenItem),
      ],
    );
  }
}

class SourcesPage extends StatefulWidget {
  const SourcesPage({required this.store, this.dockClearance = 0, super.key});

  final AppStore store;
  final double dockClearance;

  @override
  State<SourcesPage> createState() => _SourcesPageState();
}

class _SourcesPageState extends State<SourcesPage> {
  bool _importing = false;

  Future<void> _pickSource() async {
    final file = await FilePicker.pickFile(
      dialogTitle: '导入片源配置',
      type: FileType.custom,
      allowedExtensions: const ['txt', 'json', 'zip', 'm3u', 'm3u8'],
    );
    if (file == null || !mounted) return;
    setState(() => _importing = true);
    try {
      final size = await file.length();
      if (size == null || size > SourceImporter.maxFileBytes) {
        throw const FormatException('文件超过 50 MB，未导入');
      }
      final bytes = await file.readAsBytes();
      final result = SourceImporter().parseFile(file.name, bytes);
      await widget.store.addImport(result);
      unawaited(widget.store.refreshSources());
      if (!mounted) return;
      final addedCount = result.sources.length;
      final message = result.isEmpty
          ? '没有发现可识别的源'
          : '已导入 $addedCount 个源与 ${result.items.length} 个频道'
                '${result.skippedScripts > 0 ? '，跳过 ${result.skippedScripts} 个脚本源' : ''}';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } on Object catch (error) {
      if (!mounted) return;
      final message = error is FormatException ? error.message : '文件读取失败';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _importPublicSources() async {
    if (_importing) return;
    final repositories = await showDialog<List<SourceRepository>>(
      context: context,
      builder: (_) => const _PublicRepositoryDialog(),
    );
    if (repositories == null || repositories.isEmpty || !mounted) return;
    setState(() => _importing = true);
    try {
      final result = await widget.store.importPublicRepositories(repositories);
      if (!mounted) return;
      final message =
          StringBuffer(
              result.sources.isEmpty
                  ? '未发现可直接使用的 CMS 源'
                  : '已添加 ${result.sources.length} 个 CMS 源，默认关闭',
            )
            ..write('；读取 ${result.fetchedConfigs} 个配置')
            ..write('；跳过 ${result.skippedScripts} 个 JS/JAR 爬虫源')
            ..write('；${result.failedConfigs} 个配置不可用');
      if (result.truncated) message.write('；已达到导入数量限制');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message.toString())));
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is FormatException ? error.message : '公开配置导入失败，请检查网络后重试',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _addUrl() async {
    final nameController = TextEditingController();
    final urlController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('添加片源'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(labelText: '名称'),
                ),
                SizedBox(height: 12),
                TextField(
                  controller: urlController,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: '标准 API 或播放地址',
                    hintText: 'https://example.com/api.php/provide/vod',
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final name = nameController.text.trim();
      final url = urlController.text.trim();
      final result = SourceImporter().parseFile(
        'source.txt',
        utf8.encode('${name.isEmpty ? '自定义片源' : name}: $url'),
      );
      if (result.isEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('地址无效，或包含不支持的凭证参数')));
      } else {
        try {
          await widget.store.addImport(result);
          await widget.store.refreshSources();
        } on Object {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(const SnackBar(content: Text('片源保存失败，请重试')));
          }
        }
      }
    }
    // The dialog route retains its fields until the closing animation finishes.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    nameController.dispose();
    urlController.dispose();
  }

  Future<void> _addMediaServer() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _MediaServerDialog(store: widget.store),
    );
  }

  @override
  Widget build(BuildContext context) {
    final available = widget.store.sources
        .where((source) => source.health == SourceHealth.available)
        .length;
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(28, 28, 28, 36 + widget.dockClearance),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final tools = Wrap(
                spacing: 4,
                children: [
                  IconButton(
                    tooltip: '刷新全部片源',
                    onPressed: widget.store.isRefreshing
                        ? null
                        : widget.store.refreshSources,
                    icon: Icon(Icons.refresh_rounded),
                  ),
                  IconButton(
                    tooltip: '按地址添加',
                    onPressed: _addUrl,
                    icon: Icon(Icons.add_link_rounded),
                  ),
                  IconButton(
                    tooltip: '添加媒体服务器',
                    onPressed: _addMediaServer,
                    icon: Icon(Icons.storage_rounded),
                  ),
                  IconButton(
                    tooltip: '导入公开片源仓',
                    onPressed: _importing ? null : _importPublicSources,
                    icon: _importing
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(Icons.cloud_download_outlined),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _importing ? null : _pickSource,
                    icon: _importing
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(Icons.upload_file_rounded, size: 18),
                    label: const Text('导入'),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ],
              );
              if (constraints.maxWidth < 440) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SectionTitle(title: '片源管理'),
                    SizedBox(height: 12),
                    Align(alignment: Alignment.centerRight, child: tools),
                  ],
                );
              }
              return SectionTitle(title: '片源管理', trailing: tools);
            },
          ),
          SizedBox(height: 7),
          Text(
            '$available / ${widget.store.sources.length} 个片源可连接',
            style: TextStyle(color: ZhuyingColors.muted, fontSize: 12),
          ),
          SizedBox(height: 20),
          if (widget.store.sources.isEmpty)
            const EmptyState(
              icon: Icons.lan_outlined,
              title: '还没有片源',
              detail: '导入 JSON、TXT、ZIP 或 M3U 配置。',
            )
          else
            ...widget.store.sources.map(
              (source) => _SourceRow(
                source: source,
                onEnabled: (value) =>
                    widget.store.setSourceEnabled(source.id, value),
                onRemove: () => widget.store.removeSource(source.id),
              ),
            ),
        ],
      ),
    );
  }
}

class _PublicRepositoryDialog extends StatefulWidget {
  const _PublicRepositoryDialog();

  @override
  State<_PublicRepositoryDialog> createState() =>
      _PublicRepositoryDialogState();
}

class _PublicRepositoryDialogState extends State<_PublicRepositoryDialog> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    final repositories = SourceImporter.publicRepositories;
    return AlertDialog(
      title: const Text('导入公开片源仓'),
      content: SizedBox(
        width: 520,
        height: (MediaQuery.sizeOf(context).height * 0.62)
            .clamp(240.0, 460.0)
            .toDouble(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('全选'),
              value: _selected.isEmpty
                  ? false
                  : _selected.length == repositories.length
                  ? true
                  : null,
              tristate: true,
              onChanged: (value) => setState(() {
                if (value == true) {
                  _selected
                    ..clear()
                    ..addAll(repositories.map((repository) => repository.url));
                } else {
                  _selected.clear();
                }
              }),
            ),
            Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: repositories.length,
                itemBuilder: (context, index) {
                  final repository = repositories[index];
                  return CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _selected.contains(repository.url),
                    title: Text(repository.name),
                    subtitle: Text(
                      repository.description.isEmpty
                          ? repository.url
                          : '${repository.description} · ${repository.url}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onChanged: (value) => setState(() {
                      if (value == true) {
                        _selected.add(repository.url);
                      } else {
                        _selected.remove(repository.url);
                      }
                    }),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.of(context).pop([
                  for (final repository in repositories)
                    if (_selected.contains(repository.url)) repository,
                ]),
          child: Text('导入 ${_selected.length} 个'),
        ),
      ],
    );
  }
}

class _MediaServerDialog extends StatefulWidget {
  const _MediaServerDialog({required this.store});

  final AppStore store;

  @override
  State<_MediaServerDialog> createState() => _MediaServerDialogState();
}

class _MediaServerDialogState extends State<_MediaServerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _endpoint = TextEditingController();
  final _token = TextEditingController();
  SourceKind _kind = SourceKind.jellyfin;
  bool _saving = false;
  bool _obscureToken = true;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _endpoint.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.store.addMediaServer(
        name: _name.text,
        endpoint: _endpoint.text,
        kind: _kind,
        token: _token.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error is FormatException ? error.message : '无法保存认证信息，请稍后重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加媒体服务器'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<SourceKind>(
                  segments: const [
                    ButtonSegment(
                      value: SourceKind.jellyfin,
                      label: Text('Jellyfin'),
                    ),
                    ButtonSegment(value: SourceKind.emby, label: Text('Emby')),
                  ],
                  selected: {_kind},
                  onSelectionChanged: _saving
                      ? null
                      : (values) => setState(() => _kind = values.single),
                ),
                SizedBox(height: 18),
                TextFormField(
                  controller: _name,
                  enabled: !_saving,
                  decoration: InputDecoration(labelText: '名称（可选）'),
                ),
                SizedBox(height: 12),
                TextFormField(
                  controller: _endpoint,
                  enabled: !_saving,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: '服务器地址',
                    hintText: 'https://media.example.com/',
                  ),
                  validator: (value) {
                    final uri = Uri.tryParse(value?.trim() ?? '');
                    if (uri == null ||
                        !{'http', 'https'}.contains(uri.scheme) ||
                        uri.host.isEmpty ||
                        uri.userInfo.isNotEmpty ||
                        uri.hasQuery ||
                        uri.hasFragment) {
                      return '请输入完整的 HTTP 或 HTTPS 服务器地址';
                    }
                    return null;
                  },
                ),
                SizedBox(height: 12),
                TextFormField(
                  controller: _token,
                  enabled: !_saving,
                  obscureText: _obscureToken,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'API Token',
                    suffixIcon: IconButton(
                      tooltip: _obscureToken ? '显示 Token' : '隐藏 Token',
                      onPressed: () =>
                          setState(() => _obscureToken = !_obscureToken),
                      icon: Icon(
                        _obscureToken
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                      ),
                    ),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? '请输入服务器 API Token'
                      : null,
                ),
                if (_error != null) ...[
                  SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(color: ZhuyingColors.coral, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('添加'),
        ),
      ],
    );
  }
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({required this.store, super.key});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(28, 28, 28, 36),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: _SettingsContent(store: store),
      ),
    );
  }
}

class _SettingsContent extends StatelessWidget {
  const _SettingsContent({required this.store});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(title: '设置'),
        SizedBox(height: 20),
        _SettingGroup(
          title: '播放',
          children: [
            SwitchListTile(
              value: store.autoplayNext,
              onChanged: store.setAutoplayNext,
              title: const Text('自动播放下一集'),
              secondary: Icon(Icons.skip_next_rounded),
              contentPadding: EdgeInsets.zero,
              activeTrackColor: ZhuyingColors.green,
            ),
          ],
        ),
        SizedBox(height: 20),
        _SettingGroup(
          title: '显示',
          children: [
            SwitchListTile(
              value: store.reduceMotion,
              onChanged: store.setReduceMotion,
              title: const Text('减少动态效果'),
              secondary: Icon(Icons.motion_photos_off_outlined),
              contentPadding: EdgeInsets.zero,
              activeTrackColor: ZhuyingColors.green,
            ),
          ],
        ),
        SizedBox(height: 20),
        _SettingGroup(
          title: '主题',
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 10),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth < 420 ? 1 : 2;
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: ZhuyingThemes.all.length,
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      mainAxisExtent: 92,
                    ),
                    itemBuilder: (context, index) {
                      final theme = ZhuyingThemes.all[index];
                      return _ThemeOptionTile(
                        theme: theme,
                        selected: store.themeId == theme.id,
                        onTap: () => store.setTheme(theme.id),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
        SizedBox(height: 20),
        _SettingGroup(
          title: '本机数据',
          children: const [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.cloud_off_outlined),
              title: Text('仅保存在本机'),
              subtitle: Text('片源、收藏与观看进度不会同步到云端'),
            ),
          ],
        ),
        SizedBox(height: 20),
        _SettingGroup(
          title: '关于',
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.movie_creation_outlined),
              title: Text(context.zhuyingTheme.brandName),
              subtitle: const Text(
                '作者：INJU银烛\n跨平台影视浏览与播放应用，支持标准订阅源、分类筛选和播放进度记录。',
              ),
              trailing: IconButton(
                tooltip: '打开 GitHub 仓库',
                onPressed: () => _openProjectRepository(context),
                icon: Icon(Icons.open_in_new_rounded),
              ),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.code_rounded),
              title: const Text('GitHub 项目'),
              subtitle: const Text('github.com/inju0524/NewVideo'),
              onTap: () => _openProjectRepository(context),
            ),
          ],
        ),
        SizedBox(height: 24),
        Text(
          '${context.zhuyingTheme.brandName}  ·  版本 1.0.5',
          style: TextStyle(color: ZhuyingColors.muted, fontSize: 11),
        ),
      ],
    );
  }

  Future<void> _openProjectRepository(BuildContext context) async {
    final uri = Uri.parse('https://github.com/inju0524/NewVideo');
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('无法打开 GitHub，请检查网络连接')));
    }
  }
}

class _ThemeOptionTile extends StatelessWidget {
  const _ThemeOptionTile({
    required this.theme,
    required this.selected,
    required this.onTap,
  });

  final ZhuyingThemeDefinition theme;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (!theme.isMitsuri) return _buildDefaultTile();
    final radius = BorderRadius.circular(8);
    return RoundedBorderFrame(
      key: ValueKey('theme-option-${theme.id}'),
      borderRadius: radius,
      borderColor: selected ? theme.primary : theme.line,
      borderWidth: selected ? 1.5 : 1,
      child: Material(
        color: theme.surface,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        theme.surface,
                        theme.surfaceRaised.withValues(alpha: 0.88),
                      ],
                    ),
                  ),
                ),
              ),
              if (theme.chibiAsset != null)
                Positioned(
                  right: 3,
                  bottom: 0,
                  width: 58,
                  height: 76,
                  child: Opacity(
                    opacity: selected ? 0.78 : 0.46,
                    child: Image.asset(theme.chibiAsset!, fit: BoxFit.contain),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 11, 66, 10),
                child: _buildTileContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTileContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: theme.primary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: theme.primary.withValues(alpha: 0.4),
                    blurRadius: 7,
                  ),
                ],
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                theme.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: theme.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, size: 17, color: theme.primary),
          ],
        ),
        SizedBox(height: 7),
        Text(
          theme.description,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: theme.muted, fontSize: 10, height: 1.25),
        ),
      ],
    );
  }

  Widget _buildDefaultTile() {
    final radius = BorderRadius.circular(8);
    return RoundedBorderFrame(
      key: ValueKey('theme-option-${theme.id}'),
      borderRadius: radius,
      borderColor: selected ? theme.primary : theme.line,
      borderWidth: selected ? 1.5 : 1,
      child: Material(
        color: theme.surface,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        theme.surface,
                        theme.surfaceRaised.withValues(alpha: 0.88),
                      ],
                    ),
                  ),
                ),
              ),
              if (theme.chibiAsset != null)
                Positioned(
                  right: -4,
                  bottom: -12,
                  width: 74,
                  height: 108,
                  child: Opacity(
                    opacity: selected ? 0.78 : 0.46,
                    child: Image.asset(theme.chibiAsset!, fit: BoxFit.contain),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 11, 76, 10),
                child: _buildTileContent(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilterChoice extends StatelessWidget {
  const _FilterChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      visualDensity: VisualDensity.compact,
      labelStyle: TextStyle(
        color: selected ? ZhuyingColors.amber : ZhuyingColors.muted,
        fontSize: 12,
        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
      ),
      side: BorderSide(
        color: selected
            ? ZhuyingColors.amber.withValues(alpha: 0.55)
            : ZhuyingColors.line,
      ),
      backgroundColor: ZhuyingColors.surface,
      selectedColor: ZhuyingColors.amber.withValues(alpha: 0.11),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    );
  }
}

List<String> _sortedValues(Iterable<String> values) {
  final filtered = values.where((value) => value.isNotEmpty).toSet().toList();
  filtered.sort((first, second) => second.compareTo(first));
  return filtered;
}

class _PageGrid extends StatefulWidget {
  const _PageGrid({
    required this.items,
    required this.store,
    required this.onOpenItem,
    super.key,
  });

  final List<MediaItem> items;
  final AppStore store;
  final ValueChanged<MediaItem> onOpenItem;

  @override
  State<_PageGrid> createState() => _PageGridState();
}

class _PageGridState extends State<_PageGrid> {
  static const _pageSize = 36;
  var _visibleCount = _pageSize;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1280
            ? 7
            : width >= 1000
            ? 6
            : width >= 760
            ? 5
            : width >= 520
            ? 4
            : 3;
        final visibleCount = _visibleCount.clamp(0, widget.items.length);
        return Column(
          children: [
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: visibleCount,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 14,
                mainAxisSpacing: 17,
                childAspectRatio: 0.48,
              ),
              itemBuilder: (context, index) {
                final item = widget.items[index];
                return AnimatedSwitcher(
                  duration: motionDuration(
                    context,
                    widget.store.reduceMotion,
                    const Duration(milliseconds: 180),
                  ),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) =>
                      FadeTransition(opacity: animation, child: child),
                  child: PosterCard(
                    key: ValueKey(item.id),
                    item: item,
                    onTap: () => widget.onOpenItem(item),
                    favorite: widget.store.favorites.contains(item.id),
                    onFavorite: () => widget.store.toggleFavorite(item),
                    reduceMotion: widget.store.reduceMotion,
                  ),
                );
              },
            ),
            if (visibleCount < widget.items.length)
              Padding(
                padding: EdgeInsets.only(top: 20),
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _visibleCount += _pageSize),
                  icon: Icon(Icons.expand_more_rounded, size: 18),
                  label: Text('加载更多影片（${widget.items.length - visibleCount}）'),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.item,
    required this.onTap,
    required this.reduceMotion,
  });

  final MediaItem item;
  final VoidCallback onTap;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final watched = item.progressSeconds ~/ 60;
    final total = item.durationSeconds ~/ 60;
    return Padding(
      padding: EdgeInsets.only(bottom: 10),
      child: Material(
        color: ZhuyingColors.surface,
        borderRadius: BorderRadius.circular(7),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 106,
            child: Row(
              children: [
                SizedBox(
                  width: 72,
                  height: 106,
                  child: MediaPoster(
                    url: item.posterUrl,
                    thumbnailUrl: item.thumbnailUrl,
                    title: '',
                    headers: item.posterHeaders,
                    fallbackFontSize: 12,
                    reduceMotion: reduceMotion,
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: ZhuyingColors.text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: 5),
                        Text(
                          '${item.sourceName}  ·  已观看 $watched 分钟${total > 0 ? ' / $total 分钟' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: ZhuyingColors.muted,
                            fontSize: 11,
                          ),
                        ),
                        SizedBox(height: 10),
                        LinearProgressIndicator(
                          value: item.progress,
                          minHeight: 3,
                          color: ZhuyingColors.amber,
                          backgroundColor: ZhuyingColors.line,
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Icon(
                    Icons.play_arrow_rounded,
                    color: ZhuyingColors.amber,
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

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.source,
    required this.onEnabled,
    required this.onRemove,
  });

  final MediaSource source;
  final ValueChanged<bool> onEnabled;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final host = source.kind == SourceKind.m3u
        ? '本地播放列表'
        : Uri.tryParse(source.endpoint)?.host ?? '本地源';
    final icon = source.kind == SourceKind.m3u
        ? Icons.live_tv_outlined
        : Icons.dns_outlined;
    return Padding(
      padding: EdgeInsets.only(bottom: 9),
      child: Material(
        color: ZhuyingColors.surface,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: ZhuyingColors.line),
          borderRadius: BorderRadius.circular(7),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: Icon(icon, color: ZhuyingColors.amber),
          title: Text(
            source.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          subtitle: Row(
            children: [
              SourceStatusDot(health: source.health),
              SizedBox(width: 7),
              Flexible(
                child: Text(
                  '${source.statusMessage}  ·  $host',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: ZhuyingColors.muted, fontSize: 11),
                ),
              ),
            ],
          ),
          trailing: SizedBox(
            width: 112,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: '移除片源',
                  onPressed: onRemove,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.delete_outline_rounded, size: 18),
                ),
                Switch(
                  value: source.enabled,
                  onChanged: onEnabled,
                  activeTrackColor: ZhuyingColors.green,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingGroup extends StatelessWidget {
  const _SettingGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: ZhuyingColors.amber,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: 7),
        Material(
          color: ZhuyingColors.surface,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: ZhuyingColors.line),
            borderRadius: BorderRadius.circular(7),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Column(children: children),
          ),
        ),
      ],
    );
  }
}
