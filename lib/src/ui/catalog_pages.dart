import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app_store.dart';
import '../models.dart';
import '../source_importer.dart';
import 'widgets.dart';

const _commonGenres = [
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
  final genres = items.expand((item) => item.genreLabels).toSet().toList();
  genres.sort();
  return genres;
}

class CategoriesPage extends StatefulWidget {
  const CategoriesPage({
    required this.store,
    required this.onOpenItem,
    super.key,
  });

  final AppStore store;
  final ValueChanged<MediaItem> onOpenItem;

  @override
  State<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends State<CategoriesPage> {
  Set<String> _genres = {};
  String _year = '全部年份';
  String _region = '全部地区';
  String _source = '全部片源';
  bool _showMoreGenres = false;

  @override
  Widget build(BuildContext context) {
    final discoveredGenres = _genresFromItems(widget.store.allMedia);
    final moreGenres = discoveredGenres
        .where((genre) => !_commonGenres.contains(genre))
        .toList();
    final sources = [
      '全部片源',
      ...widget.store.enabledSources.map((source) => source.name).toSet(),
    ];
    final years = _sortedValues(widget.store.allMedia.map((item) => item.year))
      ..insert(0, '全部年份');
    final regions = _sortedValues(
      widget.store.allMedia.map((item) => item.region),
    )..insert(0, '全部地区');
    final items = widget.store.allMedia.where((item) {
      final genreMatch =
          _genres.isEmpty || item.genreLabels.any(_genres.contains);
      final yearMatch = _year == '全部年份' || item.year == _year;
      final regionMatch = _region == '全部地区' || item.region == _region;
      final sourceMatch = _source == '全部片源' || item.sourceName == _source;
      return genreMatch && yearMatch && regionMatch && sourceMatch;
    }).toList();
    final gridKey = [
      ..._genres.toList()..sort(),
      _year,
      _region,
      _source,
      ...items.take(3).map((item) => item.id),
    ].join('|');

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(title: '片库分类'),
          const SizedBox(height: 22),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _FilterChoice(
                label: '全部',
                selected: _genres.isEmpty,
                onTap: () => setState(() => _genres = {}),
              ),
              ..._commonGenres.map((genre) {
                return _FilterChoice(
                  label: genre,
                  selected: _genres.contains(genre),
                  onTap: () => _toggleGenre(genre),
                );
              }),
              if (moreGenres.isNotEmpty)
                TextButton.icon(
                  onPressed: () =>
                      setState(() => _showMoreGenres = !_showMoreGenres),
                  icon: Icon(
                    _showMoreGenres
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    size: 17,
                  ),
                  label: Text(_showMoreGenres ? '收起更多' : '更多类型'),
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
              widget.store.reduceMotion,
              const Duration(milliseconds: 200),
            ),
            curve: Curves.easeInOutCubic,
            alignment: Alignment.topCenter,
            child: _showMoreGenres
                ? Padding(
                    padding: const EdgeInsets.only(top: 7),
                    child: Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: moreGenres
                          .map(
                            (genre) => _FilterChoice(
                              label: genre,
                              selected: _genres.contains(genre),
                              onTap: () => _toggleGenre(genre),
                            ),
                          )
                          .toList(),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _FilterDropdown(
                label: _year,
                options: years,
                icon: Icons.calendar_month_outlined,
                onChanged: (value) => setState(() => _year = value),
              ),
              _FilterDropdown(
                label: _region,
                options: regions,
                icon: Icons.public_outlined,
                onChanged: (value) => setState(() => _region = value),
              ),
              _FilterDropdown(
                label: _source,
                options: sources,
                icon: Icons.lan_outlined,
                onChanged: (value) => setState(() => _source = value),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            '${items.length} 部影片',
            style: const TextStyle(color: ZhuyingColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 14),
          if (items.isEmpty)
            const EmptyState(icon: Icons.category_outlined, title: '这个分类还没有影片')
          else
            Column(
              children: [
                _PageGrid(
                  key: ValueKey('category-$gridKey'),
                  items: items,
                  store: widget.store,
                  onOpenItem: widget.onOpenItem,
                ),
                if (widget.store.hasMoreCatalog)
                  Padding(
                    padding: const EdgeInsets.only(top: 22),
                    child: OutlinedButton.icon(
                      onPressed: widget.store.isLoadingMoreCatalog
                          ? null
                          : widget.store.loadMoreCatalog,
                      icon: widget.store.isLoadingMoreCatalog
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.downloading_rounded, size: 18),
                      label: const Text('载入更多分类影片'),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  void _toggleGenre(String genre) {
    setState(() {
      final next = {..._genres};
      if (!next.add(genre)) next.remove(genre);
      _genres = next;
    });
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
  String _genre = '全部类型';
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
      _genre = '全部类型';
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
    final genres = [
      '全部类型',
      ..._results.expand((item) => item.genreLabels).toSet().toList()..sort(),
    ];
    final activeGenre = genres.contains(_genre) ? _genre : '全部类型';
    final sources = [
      '全部片源',
      ...widget.store.enabledSources.map((source) => source.name).toSet(),
    ];
    final years = _sortedValues(_results.map((item) => item.year))
      ..insert(0, '全部年份');
    final regions = _sortedValues(_results.map((item) => item.region))
      ..insert(0, '全部地区');
    final filtered = _results.where((item) {
      return (activeGenre == '全部类型' ||
              item.genreLabels.contains(activeGenre)) &&
          (_year == '全部年份' || item.year == _year) &&
          (_region == '全部地区' || item.region == _region) &&
          (_source == '全部片源' || item.sourceName == _source);
    }).toList();

    return Scaffold(
      backgroundColor: ZhuyingColors.canvas,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: ZhuyingColors.line)),
              ),
              child: Row(
                children: [
                  IconButton(
                    tooltip: '返回',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_rounded),
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
                              icon: const Icon(Icons.close_rounded),
                            ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                key: const PageStorageKey<String>('search-content'),
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 36),
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
                      const Padding(
                        padding: EdgeInsets.only(top: 42),
                        child: EmptyState(
                          icon: Icons.search_rounded,
                          title: '搜索影片',
                          detail: '输入片名、演员或关键词查找影片。',
                        ),
                      ),
                    if (_controller.text.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          for (final genre in genres.take(8))
                            _FilterChoice(
                              label: genre,
                              selected: genre == activeGenre,
                              onTap: () => setState(() => _genre = genre),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _FilterDropdown(
                            label: _year,
                            options: years,
                            icon: Icons.calendar_month_outlined,
                            onChanged: (value) => setState(() => _year = value),
                          ),
                          _FilterDropdown(
                            label: _region,
                            options: regions,
                            icon: Icons.public_outlined,
                            onChanged: (value) =>
                                setState(() => _region = value),
                          ),
                          _FilterDropdown(
                            label: _source,
                            options: sources,
                            icon: Icons.lan_outlined,
                            onChanged: (value) =>
                                setState(() => _source = value),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${filtered.length} 部影片',
                              style: const TextStyle(
                                color: ZhuyingColors.muted,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          if (_searching)
                            const SizedBox(
                              width: 15,
                              height: 15,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '本地片库 ${widget.store.localSearchableItemCount} 部'
                        '  ·  本地匹配 $_localMatchCount'
                        '  ·  片源新增 $_remoteMatchCount',
                        style: const TextStyle(
                          color: ZhuyingColors.muted,
                          fontSize: 10,
                        ),
                      ),
                      const SizedBox(height: 14),
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
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('重试'),
                          ),
                        )
                      else if (_searchFailed)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Text(
                            _failedSourceCount >= _searchableSourceCount
                                ? '片源暂时无法连接，以下为本地已保存的匹配结果。'
                                : '部分片源连接失败，以下为当前可用的搜索结果。',
                            style: const TextStyle(
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
                            'search-$activeGenre-$_year-$_region-$_source-${filtered.map((item) => item.id).take(3).join(',')}',
                          ),
                          items: filtered,
                          store: widget.store,
                          onOpenItem: widget.onOpenItem,
                        ),
                      if (filtered.isEmpty && _searching)
                        const Padding(
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
        const SizedBox(height: 10),
        for (final term in terms)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const Icon(Icons.history_rounded, size: 19),
            title: Text(term, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => onSelect(term),
            trailing: IconButton(
              tooltip: '删除搜索记录：$term',
              onPressed: () async => onRemove(term),
              icon: const Icon(Icons.close_rounded, size: 18),
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
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 36),
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
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
        ),
        const SizedBox(height: 18),
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
  const MinePage({required this.store, required this.onOpenItem, super.key});

  final AppStore store;
  final ValueChanged<MediaItem> onOpenItem;

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
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 34),
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
                  style: const TextStyle(
                    color: ZhuyingColors.muted,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(height: 18),
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
              const SizedBox(height: 22),
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
        const SizedBox(height: 18),
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
  const SourcesPage({required this.store, super.key});

  final AppStore store;

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
                  decoration: const InputDecoration(labelText: '名称'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: urlController,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(
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
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 36),
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
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                  IconButton(
                    tooltip: '按地址添加',
                    onPressed: _addUrl,
                    icon: const Icon(Icons.add_link_rounded),
                  ),
                  IconButton(
                    tooltip: '添加媒体服务器',
                    onPressed: _addMediaServer,
                    icon: const Icon(Icons.storage_rounded),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _importing ? null : _pickSource,
                    icon: _importing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload_file_rounded, size: 18),
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
                    const SizedBox(height: 12),
                    Align(alignment: Alignment.centerRight, child: tools),
                  ],
                );
              }
              return SectionTitle(title: '片源管理', trailing: tools);
            },
          ),
          const SizedBox(height: 7),
          Text(
            '$available / ${widget.store.sources.length} 个片源可连接',
            style: const TextStyle(color: ZhuyingColors.muted, fontSize: 12),
          ),
          const SizedBox(height: 20),
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
                const SizedBox(height: 18),
                TextFormField(
                  controller: _name,
                  enabled: !_saving,
                  decoration: const InputDecoration(labelText: '名称（可选）'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _endpoint,
                  enabled: !_saving,
                  keyboardType: TextInputType.url,
                  autocorrect: false,
                  decoration: const InputDecoration(
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
                const SizedBox(height: 12),
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
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: ZhuyingColors.coral,
                      fontSize: 12,
                    ),
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
              ? const SizedBox(
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
      padding: const EdgeInsets.fromLTRB(28, 28, 28, 36),
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
        const SizedBox(height: 20),
        _SettingGroup(
          title: '播放',
          children: [
            SwitchListTile(
              value: store.autoplayNext,
              onChanged: store.setAutoplayNext,
              title: const Text('自动播放下一集'),
              secondary: const Icon(Icons.skip_next_rounded),
              contentPadding: EdgeInsets.zero,
              activeTrackColor: ZhuyingColors.green,
            ),
          ],
        ),
        const SizedBox(height: 20),
        _SettingGroup(
          title: '显示',
          children: [
            SwitchListTile(
              value: store.reduceMotion,
              onChanged: store.setReduceMotion,
              title: const Text('减少动态效果'),
              secondary: const Icon(Icons.motion_photos_off_outlined),
              contentPadding: EdgeInsets.zero,
              activeTrackColor: ZhuyingColors.green,
            ),
          ],
        ),
        const SizedBox(height: 20),
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
        const SizedBox(height: 24),
        const Text(
          '烛影  ·  版本 1.0.0',
          style: TextStyle(color: ZhuyingColors.muted, fontSize: 11),
        ),
      ],
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

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.label,
    required this.options,
    required this.icon,
    required this.onChanged,
  });

  final String label;
  final List<String> options;
  final IconData icon;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = options.contains(label) ? label : options.first;
    return SizedBox(
      width: 156,
      child: DropdownButtonFormField<String>(
        initialValue: selected,
        isExpanded: true,
        decoration: InputDecoration(
          prefixIcon: Icon(icon, size: 17),
          isDense: true,
        ),
        items: options
            .map(
              (value) => DropdownMenuItem(
                value: value,
                child: Text(value, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      ),
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
                padding: const EdgeInsets.only(top: 20),
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _visibleCount += _pageSize),
                  icon: const Icon(Icons.expand_more_rounded, size: 18),
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
      padding: const EdgeInsets.only(bottom: 10),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: ZhuyingColors.text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${item.sourceName}  ·  已观看 $watched 分钟${total > 0 ? ' / $total 分钟' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: ZhuyingColors.muted,
                            fontSize: 11,
                          ),
                        ),
                        const SizedBox(height: 10),
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
                const Padding(
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
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: ZhuyingColors.surface,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: ZhuyingColors.line),
          borderRadius: BorderRadius.circular(7),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: Icon(icon, color: ZhuyingColors.amber),
          title: Text(
            source.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          subtitle: Row(
            children: [
              SourceStatusDot(health: source.health),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  '${source.statusMessage}  ·  $host',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: ZhuyingColors.muted,
                    fontSize: 11,
                  ),
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
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
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
          style: const TextStyle(
            color: ZhuyingColors.amber,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 7),
        Material(
          color: ZhuyingColors.surface,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: ZhuyingColors.line),
            borderRadius: BorderRadius.circular(7),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Column(children: children),
          ),
        ),
      ],
    );
  }
}
