import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

import 'models.dart';
import 'source_importer.dart';

class AppStore extends ChangeNotifier {
  AppStore({
    http.Client? client,
    FlutterSecureStorage? secureStorage,
    bool? useWebProxy,
    Uri? webProxyEndpoint,
  }) : _client = client ?? http.Client(),
       _secureStorage = secureStorage ?? const FlutterSecureStorage(),
       _useWebProxy = useWebProxy ?? kIsWeb,
       _webProxyEndpoint =
           webProxyEndpoint ?? Uri.parse(_defaultWebProxyEndpoint);

  static const _sourcesKey = 'zhuying.sources.v1';
  static const _historyKey = 'zhuying.history.v1';
  static const _searchHistoryKey = 'zhuying.searchHistory.v1';
  static const _favoritesKey = 'zhuying.favorites.v1';
  static const _followsKey = 'zhuying.follows.v1';
  static const _favoriteItemsKey = 'zhuying.favoriteItems.v1';
  static const _homeSnapshotKey = 'zhuying.homeSnapshot.v1';
  static const _localItemsKey = 'zhuying.localItems.v1';
  static const _motionKey = 'zhuying.reduceMotion.v1';
  static const _autoplayKey = 'zhuying.autoplayNext.v1';
  static const _initialCatalogPages = 1;
  static const _catalogPagesPerLoadMore = 2;
  static const _maxCategoryPagesPerLoad = 2;
  static const _categoryResultTarget = 36;
  static const _maxCatalogPages = 200;
  static const _cmsDetailBatchSize = 100;
  static const _defaultCmsPageSize = 20;
  static const _defaultMediaServerPageSize = 100;
  static const _maxHomeSnapshotItems = 30;
  static const _maxSearchResults = 120;
  static const _maxSearchHistory = 10;
  static const _sourceConcurrency = 4;
  static const _requestTimeout = Duration(seconds: 12);
  static const _searchTimeout = Duration(seconds: 8);
  static const _defaultWebProxyEndpoint = String.fromEnvironment(
    'ZH_SOURCE_PROXY',
    defaultValue: 'http://127.0.0.1:8124/proxy',
  );

  final http.Client _client;
  final FlutterSecureStorage _secureStorage;
  final bool _useWebProxy;
  final Uri _webProxyEndpoint;

  List<MediaSource> sources = defaultSources;
  List<MediaItem> catalog = const [];
  List<MediaItem> homeSnapshot = const [];
  List<MediaItem> history = const [];
  List<String> searchHistory = const [];
  List<MediaItem> localItems = const [];
  List<MediaItem> favoriteItems = const [];
  Set<String> favorites = {};
  Set<String> follows = {};
  bool isRefreshing = false;
  bool hasInitialized = false;
  bool reduceMotion = false;
  bool autoplayNext = true;
  String? refreshMessage;
  bool isLoadingMoreCatalog = false;
  bool _disposed = false;
  final Map<String, int> _catalogNextPage = {};
  final Map<String, Map<String, MediaItem>> _categoryItemsByQuery = {};
  final Map<String, Map<String, int>> _categoryNextPagesByQuery = {};
  final Set<String> _loadedCategoryQueries = {};
  final Map<String, List<_CmsTypeCategory>> _cmsTypeCategories = {};
  final Map<String, Map<String, Map<String, dynamic>>>
  _cmsPosterDetailsBySource = {};
  final Map<String, Set<String>> _cmsPosterDetailsAttemptedBySource = {};
  ({List<String> genres, String? year, String? region, String? sourceName})?
  _queuedCategoryQuery;
  int _searchGeneration = 0;

  List<MediaItem> get allMedia {
    final activeIds = enabledSources.map((source) => source.id).toSet();
    return _uniqueItems(
      [
        ...catalog,
        ...localItems,
        ...favoriteItems,
      ].where((item) => item.isDemo || activeIds.contains(item.sourceId)),
    );
  }

  List<MediaItem> get categoryMedia {
    final activeIds = enabledSources.map((source) => source.id).toSet();
    final merged = <String, MediaItem>{};
    for (final item in [
      ...catalog,
      ...homeSnapshot,
      ...localItems,
      ...favoriteItems,
      ..._categoryItemsByQuery.values.expand((items) => items.values),
    ].where((item) => item.isDemo || activeIds.contains(item.sourceId))) {
      final existing = merged[item.id];
      if (existing == null) {
        merged[item.id] = item;
        continue;
      }
      merged[item.id] = _mergeMediaItem(existing, item);
    }
    return merged.values.toList();
  }

  List<MediaSource> get enabledSources =>
      sources.where((source) => source.enabled).toList();

  int get localSearchableItemCount {
    final activeSourceIds = enabledSources.map((source) => source.id).toSet();
    return _uniqueItems(
      [...allMedia, ...homeSnapshot].where(
        (item) => !item.isDemo && activeSourceIds.contains(item.sourceId),
      ),
    ).length;
  }

  bool get hasMoreCatalog => _catalogNextPage.isNotEmpty;

  bool hasMoreCategoryPages({
    Iterable<String> genres = const [],
    String? year,
    String? region,
    String? sourceName,
  }) {
    final key = _categoryQueryKey(
      genres: genres,
      year: year,
      region: region,
      sourceName: sourceName,
    );
    return !_loadedCategoryQueries.contains(key) ||
        (_categoryNextPagesByQuery[key]?.isNotEmpty ?? false);
  }

  void cancelPendingSearch() => _searchGeneration++;

  List<MediaItem> get homeMedia {
    final activeSourceIds = enabledSources.map((source) => source.id).toSet();
    final currentItems = allMedia.where((item) => !item.isDemo).toList();
    final currentItemIds = currentItems.map((item) => item.id).toSet();
    final cachedItems = homeSnapshot.where(
      (item) =>
          activeSourceIds.contains(item.sourceId) &&
          !currentItemIds.contains(item.id),
    );
    return _uniqueItems([...currentItems, ...cachedItems])
        .take(_maxHomeSnapshotItems)
        .toList();
  }

  Future<List<MediaItem>> findSourceVariants(MediaItem item) async {
    final titleKey = _sourceTitleKey(item.title);
    if (titleKey.isEmpty) return const [];

    var variants = allMedia
        .where(
          (candidate) =>
              candidate.id != item.id &&
              candidate.sourceId != item.sourceId &&
              _sourceTitleKey(candidate.title) == titleKey,
        )
        .toList();
    if (variants.isEmpty) {
      try {
        final results = await search(item.title);
        variants = results
            .where(
              (candidate) =>
                  candidate.id != item.id &&
                  candidate.sourceId != item.sourceId &&
                  _sourceTitleKey(candidate.title) == titleKey,
            )
            .toList();
      } on Object {
        // Keep the already loaded catalog available when source search fails.
      }
    }
    return _uniqueItems(variants);
  }

  Future<void> initialize({bool refresh = true}) async {
    final preferences = await SharedPreferences.getInstance();
    final storedSources = preferences.getString(_sourcesKey);
    if (storedSources != null) {
      try {
        final decoded = jsonDecode(storedSources) as List<dynamic>;
        final imported = decoded
            .map((value) => MediaSource.fromJson(value as Map<String, dynamic>))
            .toList();
        final known = <String>{};
        final byId = {
          for (final source in imported)
            if (known.add(source.id)) source.id: source,
        };
        final merged = <MediaSource>[
          for (final source in defaultSources) byId.remove(source.id) ?? source,
          ...byId.values,
        ];
        sources = merged;

        // Older installs only have the original preset IDs persisted. Write
        // the merged list back so newly published defaults become visible
        // without discarding the user's enabled state or custom sources.
        if (merged.length != imported.length) await _saveSources();
      } on Object {
        sources = defaultSources;
      }
    }

    final activeSourceIds = enabledSources.map((source) => source.id).toSet();
    homeSnapshot = _readMediaList(preferences.getString(_homeSnapshotKey))
        .where(
          (item) => !item.isDemo && activeSourceIds.contains(item.sourceId),
        )
        .take(_maxHomeSnapshotItems)
        .toList();
    catalog = const [];
    reduceMotion = preferences.getBool(_motionKey) ?? false;
    autoplayNext = preferences.getBool(_autoplayKey) ?? true;
    hasInitialized = true;
    notifyListeners();

    history = await _attachPosterHeaders(
      _readMediaList(preferences.getString(_historyKey)),
    );
    searchHistory = (preferences.getStringList(_searchHistoryKey) ?? const [])
        .take(_maxSearchHistory)
        .toList();
    localItems = _readMediaList(preferences.getString(_localItemsKey));
    favorites = preferences.getStringList(_favoritesKey)?.toSet() ?? {};
    follows = preferences.getStringList(_followsKey)?.toSet() ?? {};
    favoriteItems = await _attachPosterHeaders(
      _readMediaList(preferences.getString(_favoriteItemsKey)),
    );
    homeSnapshot = await _attachPosterHeaders(homeSnapshot);
    notifyListeners();
    if (refresh) unawaited(refreshSources());
  }

  List<MediaItem> _readMediaList(String? encoded) {
    if (encoded == null) return const [];
    try {
      return (jsonDecode(encoded) as List<dynamic>)
          .map((value) => MediaItem.fromJson(value as Map<String, dynamic>))
          .toList();
    } on Object {
      return const [];
    }
  }

  Future<void> refreshSources() async {
    if (isRefreshing || isLoadingMoreCatalog) return;
    isRefreshing = true;
    refreshMessage = null;
    notifyListeners();

    final refreshedSourceIds = <String>{};
    _catalogNextPage.clear();
    final streamedItems = <String, Map<String, MediaItem>>{};
    final previousHomeSnapshot = homeSnapshot;
    void publishItems(MediaSource source, List<MediaItem> items) {
      if (_disposed) return;
      if (items.isNotEmpty) refreshedSourceIds.add(source.id);
      final sourceItems = streamedItems.putIfAbsent(
        source.id,
        () => <String, MediaItem>{},
      );
      for (final item in items) {
        sourceItems[item.id] = item;
      }
      final activeSourceIds = enabledSources.map((source) => source.id).toSet();
      final streamedHomeItems = streamedItems.values
          .expand((itemsById) => itemsById.values)
          .where((item) => activeSourceIds.contains(item.sourceId));
      final retainedHomeItems = previousHomeSnapshot.where(
        (item) =>
            activeSourceIds.contains(item.sourceId) &&
            !(streamedItems[item.sourceId]?.containsKey(item.id) ?? false),
      );
      homeSnapshot = _uniqueItems([...streamedHomeItems, ...retainedHomeItems])
          .take(_maxHomeSnapshotItems)
          .toList();
      final visibleItems = [
        ...catalog.where(
          (item) => !item.isDemo && !refreshedSourceIds.contains(item.sourceId),
        ),
        ...streamedItems.values.expand((itemsById) => itemsById.values),
      ];
      _updateSource(
        source.copyWith(
          health: SourceHealth.available,
          statusMessage: items.isEmpty
              ? '已连接，暂无影片'
              : '正在载入 · ${sourceItems.length} 部',
        ),
      );
      if (visibleItems.isNotEmpty) {
        catalog = _uniqueItems(visibleItems);
        refreshMessage = '正在载入影片 · ${catalog.length} 部';
      }
      notifyListeners();
    }

    final results = await _mapConcurrent(
      enabledSources.where((source) => source.kind != SourceKind.m3u).toList(),
      _sourceConcurrency,
      (source) => _fetchCatalog(
        source,
        onItems: (items) => publishItems(source, items),
      ),
    );
    final updated = <String, MediaSource>{};
    final items = <MediaItem>[];
    for (final result in results) {
      updated[result.source.id] = result.source;
      items.addAll(result.items);
    }
    sources = [
      for (final source in sources)
        if (updated[source.id] case final result?)
          source.copyWith(
            health: result.health,
            statusMessage: result.statusMessage,
          )
        else
          source,
    ];
    final activeIds = enabledSources.map((source) => source.id).toSet();
    final currentItems = items.where(
      (item) => activeIds.contains(item.sourceId),
    );
    if (currentItems.isNotEmpty) {
      catalog = _uniqueItems(currentItems);
      refreshMessage = '已载入 ${catalog.length} 部影片';
      final retainedHomeItems = previousHomeSnapshot.where(
        (item) =>
            activeIds.contains(item.sourceId) &&
            !(streamedItems[item.sourceId]?.containsKey(item.id) ?? false),
      );
      homeSnapshot = _uniqueItems([...currentItems, ...retainedHomeItems])
          .take(_maxHomeSnapshotItems)
          .toList();
      await _saveHomeSnapshot();
    } else {
      catalog = catalog.where((item) => !item.isDemo).toList();
      homeSnapshot = previousHomeSnapshot;
      final failedSources = sources
          .where(
            (source) =>
                source.enabled &&
                source.kind != SourceKind.m3u &&
                source.health == SourceHealth.error,
          )
          .length;
      refreshMessage = enabledSources.isEmpty
          ? '没有启用的片源'
          : failedSources == 0
          ? '片源已连接，但暂时没有影片'
          : '$failedSources 个片源连接失败，请查看片源状态';
    }
    isRefreshing = false;
    await _saveSources();
    notifyListeners();
    _drainQueuedCategoryQuery();
  }

  Future<void> loadMoreCatalog({
    Iterable<String> genres = const [],
    String? year,
    String? region,
    String? sourceName,
    int pageLimit = _catalogPagesPerLoadMore,
  }) async {
    final selectedGenres = normalizeGenres(genres).toSet();
    if (selectedGenres.isNotEmpty ||
        year != null ||
        region != null ||
        sourceName != null) {
      await _loadMoreGenreCatalog(
        genres: selectedGenres,
        year: year,
        region: region,
        sourceName: sourceName,
      );
      return;
    }
    if (isRefreshing || isLoadingMoreCatalog || _catalogNextPage.isEmpty) {
      return;
    }
    isLoadingMoreCatalog = true;
    notifyListeners();
    final sourcesById = {
      for (final source in enabledSources) source.id: source,
    };
    _catalogNextPage.removeWhere(
      (sourceId, _) => !sourcesById.containsKey(sourceId),
    );
    void publish(MediaSource source, List<MediaItem> items) {
      if (_disposed || items.isEmpty) return;
      catalog = _uniqueItems([
        ...catalog.where((item) => !item.isDemo),
        ...items,
      ]);
      _updateSource(
        source.copyWith(
          health: SourceHealth.available,
          statusMessage:
              '已载入 ${catalog.where((item) => item.sourceId == source.id).length} 部影片',
        ),
      );
      refreshMessage = '已载入 ${catalog.length} 部影片';
      notifyListeners();
    }

    try {
      final sourcesToFetch = _catalogNextPage.entries
          .map((entry) => (source: sourcesById[entry.key], page: entry.value))
          .where((entry) => entry.source != null)
          .toList();
      final results = await _mapConcurrent(
        sourcesToFetch,
        _sourceConcurrency,
        (entry) => _fetchSource(
          entry.source!,
          startPage: entry.page,
          pageLimit: pageLimit,
          fetchMissingPosters: true,
          onItems: (items) => publish(entry.source!, items),
        ),
      );
      _applySourceResults({
        for (final result in results) result.source.id: result.source,
      });
    } finally {
      isLoadingMoreCatalog = false;
      notifyListeners();
      _drainQueuedCategoryQuery();
    }
  }

  Future<void> _loadMoreGenreCatalog({
    required Set<String> genres,
    String? year,
    String? region,
    String? sourceName,
  }) async {
    final queryKey = _categoryQueryKey(
      genres: genres,
      year: year,
      region: region,
      sourceName: sourceName,
    );
    if (isRefreshing) {
      _queuedCategoryQuery = (
        genres: genres.toList(),
        year: year,
        region: region,
        sourceName: sourceName,
      );
      return;
    }
    if (isLoadingMoreCatalog) {
      _queuedCategoryQuery = (
        genres: genres.toList(),
        year: year,
        region: region,
        sourceName: sourceName,
      );
      return;
    }
    if (_loadedCategoryQueries.contains(queryKey) &&
        (_categoryNextPagesByQuery[queryKey]?.isEmpty ?? true)) {
      return;
    }
    isLoadingMoreCatalog = true;
    notifyListeners();
    try {
      final sourcesById = {
        for (final source in enabledSources) source.id: source,
      };
      var routes = _categoryNextPagesByQuery[queryKey] ?? <String, int>{};
      if (!_loadedCategoryQueries.contains(queryKey)) {
        final cmsSources = enabledSources
            .where(
              (source) =>
                  source.kind == SourceKind.cms &&
                  (sourceName == null || source.name == sourceName),
            )
            .toList();
        final typeLists = await _mapConcurrent(
          cmsSources,
          _sourceConcurrency,
          _fetchCmsTypes,
        );
        routes = <String, int>{};
        for (var index = 0; index < cmsSources.length; index++) {
          final source = cmsSources[index];
          final matchedTypes = typeLists[index]
              .where((type) => genres.contains(type.genre))
              .toList();
          if (matchedTypes.isEmpty) {
            routes['${source.id}|fallback'] = 1;
          } else {
            for (final type in matchedTypes) {
              routes['${source.id}|${type.id}|${type.genre}'] = 1;
            }
          }
        }
        _categoryNextPagesByQuery[queryKey] = routes;
        _loadedCategoryQueries.add(queryKey);
        for (final source in enabledSources.where(
          (source) =>
              source.kind != SourceKind.cms &&
              source.kind != SourceKind.m3u &&
              (sourceName == null || source.name == sourceName),
        )) {
          routes['${source.id}|fallback'] = 1;
        }
      }
      bool hasEnoughItems() {
        final matches = _categoryItemsByQuery[queryKey]?.values.where((item) {
          return (genres.isEmpty || item.genreLabels.any(genres.contains)) &&
              (year == null || item.year == year) &&
              (region == null || item.region == region) &&
              (sourceName == null || item.sourceName == sourceName);
        }).length;
        return (matches ?? 0) >= _categoryResultTarget;
      }

      final failedRoutes = <String, int>{};
      var pagesFetched = 0;
      while (routes.keys.any((route) => !failedRoutes.containsKey(route)) &&
          pagesFetched < _maxCategoryPagesPerLoad &&
          (pagesFetched == 0 || !hasEnoughItems())) {
        final requestedRoutes = routes.entries
            .where((entry) => !failedRoutes.containsKey(entry.key))
            .toList();
        final results = await _mapConcurrent(
          requestedRoutes,
          _sourceConcurrency,
          (entry) async {
            final parts = entry.key.split('|');
            final source = sourcesById[parts.first];
            if (source == null) return null;
            final categoryId = parts.length > 2 && parts[1] != 'fallback'
                ? parts[1]
                : null;
            final routeGenre = parts.length > 2 ? parts[2] : null;
            final result = source.kind == SourceKind.cms
                ? await _fetchSource(
                    source,
                    startPage: entry.value,
                    pageLimit: 1,
                    categoryId: categoryId,
                    year: year,
                    region: region,
                    trackCatalogPagination: false,
                    fetchMissingPosters: true,
                  )
                : await _fetchMediaServer(
                    source,
                    genres: genres.toList(),
                    startIndex: (entry.value - 1) * _defaultCmsPageSize,
                  );
            final items = [
              for (final item in result.items)
                if (routeGenre != null)
                  item.copyWith(
                    genre: routeGenre,
                    genres: normalizeGenres([...item.genreLabels, routeGenre]),
                  )
                else
                  item,
            ];
            return _CategoryRouteResult(
              entry.key,
              source,
              entry.value,
              _SourceFetchResult(
                result.source,
                items,
                nextPage: result.nextPage,
              ),
            );
          },
        );

        final nextRoutes = <String, int>{};
        final updatedSources = <String, MediaSource>{};
        final queryItems = _categoryItemsByQuery.putIfAbsent(
          queryKey,
          () => <String, MediaItem>{},
        );
        for (final routeResult in results.whereType<_CategoryRouteResult>()) {
          final source = routeResult.source;
          if (source == null) continue;
          updatedSources[source.id] = routeResult.result.source;
          if (routeResult.result.source.health == SourceHealth.error) {
            failedRoutes[routeResult.routeKey] = routeResult.requestPage;
            continue;
          }
          for (final item in routeResult.result.items) {
            final genreMatch =
                genres.isEmpty || item.genreLabels.any(genres.contains);
            if (genreMatch &&
                (year == null || item.year == year) &&
                (region == null || item.region == region) &&
                (sourceName == null || item.sourceName == sourceName)) {
              queryItems[item.id] = _mergeMediaItem(queryItems[item.id], item);
            }
          }
          if (routeResult.result.nextPage case final nextPage?) {
            nextRoutes[routeResult.routeKey] = nextPage;
          }
        }
        nextRoutes.addAll(failedRoutes);
        _categoryNextPagesByQuery[queryKey] = nextRoutes;
        routes = nextRoutes;
        _applySourceResults(updatedSources);
        pagesFetched++;
        notifyListeners();
      }
    } finally {
      isLoadingMoreCatalog = false;
      notifyListeners();
      _drainQueuedCategoryQuery();
    }
  }

  void _drainQueuedCategoryQuery() {
    final queued = _queuedCategoryQuery;
    _queuedCategoryQuery = null;
    if (queued == null || _disposed || isRefreshing || isLoadingMoreCatalog) {
      if (queued != null) _queuedCategoryQuery = queued;
      return;
    }
    unawaited(
      _loadMoreGenreCatalog(
        genres: queued.genres.toSet(),
        year: queued.year,
        region: queued.region,
        sourceName: queued.sourceName,
      ),
    );
  }

  Future<List<_CmsTypeCategory>> _fetchCmsTypes(MediaSource source) async {
    final cached = _cmsTypeCategories[source.id];
    if (cached != null) return cached;
    try {
      final headers = await requestHeaders(source.id);
      final response = await _get(
        _requestUri(source.endpoint, const {
          'ac': 'list',
          'at': 'xml',
          'pg': '1',
        }),
        headers: headers,
      );
      _checkResponse(response);
      final body = utf8.decode(response.bodyBytes, allowMalformed: true).trim();
      final document = XmlDocument.parse(body);
      final types = <_CmsTypeCategory>[];
      final seen = <String>{};
      for (final element in document.findAllElements('ty')) {
        final id = element.getAttribute('id')?.trim() ?? '';
        if (id.isEmpty) continue;
        final genres = normalizeGenres(element.innerText);
        for (final genre in genres) {
          if (seen.add('$id|$genre')) {
            types.add(_CmsTypeCategory(id: id, genre: genre));
          }
        }
      }
      _cmsTypeCategories[source.id] = types;
      return types;
    } on Object {
      // Sources without the standard XML category tree use catalog paging.
      return const [];
    }
  }

  static String _categoryQueryKey({
    required Iterable<String> genres,
    String? year,
    String? region,
    String? sourceName,
  }) => [
    ...normalizeGenres(genres).toList()..sort(),
    year ?? '',
    region ?? '',
    sourceName ?? '',
  ].join('|');

  Future<List<MediaItem>> search(
    String query, {
    void Function(List<MediaItem> results)? onResults,
    void Function(SearchCounts counts)? onCounts,
    void Function(SearchOutcome outcome)? onComplete,
    bool remote = true,
  }) async {
    final generation = ++_searchGeneration;
    final term = query.trim();
    if (term.isEmpty) {
      onCounts?.call(const SearchCounts(localMatches: 0, remoteMatches: 0));
      return allMedia.where((item) => !item.isDemo).toList();
    }
    final activeSourceIds = enabledSources.map((source) => source.id).toSet();
    final localMatches = _uniqueItems(
      [...allMedia, ...homeSnapshot].where((item) {
        return !item.isDemo &&
            activeSourceIds.contains(item.sourceId) &&
            (item.title.toLowerCase().contains(term.toLowerCase()) ||
                item.genreLabels.any(
                  (genre) => genre.toLowerCase().contains(term.toLowerCase()),
                ) ||
                item.region.toLowerCase().contains(term.toLowerCase()));
      }).toList(),
    );
    if (!remote) {
      final matches = localMatches.take(_maxSearchResults).toList();
      onCounts?.call(
        SearchCounts(localMatches: localMatches.length, remoteMatches: 0),
      );
      onResults?.call(matches);
      return matches;
    }
    final streamedItems = <String, List<MediaItem>>{};
    void publishResults() {
      final combined = _uniqueItems([
        ...localMatches,
        ...streamedItems.values.expand((items) => items),
      ]);
      final localIds = localMatches.map((item) => item.id).toSet();
      onCounts?.call(
        SearchCounts(
          localMatches: localMatches.length,
          remoteMatches: combined
              .where((item) => !localIds.contains(item.id))
              .length,
        ),
      );
      onResults?.call(combined.take(_maxSearchResults).toList());
    }

    publishResults();
    final searchSources = enabledSources
        .where((source) => source.kind != SourceKind.m3u)
        .toList();
    final results = await _mapConcurrent(
      searchSources,
      _sourceConcurrency,
      (source) => _fetchCatalog(
        source,
        query: term,
        onItems: (items) {
          if (generation != _searchGeneration) return;
          streamedItems[source.id] = items;
          _updateSource(
            source.copyWith(
              health: SourceHealth.available,
              statusMessage: '搜索到 ${items.length} 部影片',
            ),
          );
          publishResults();
        },
      ),
      shouldContinue: () => generation == _searchGeneration,
    );
    if (generation != _searchGeneration) {
      return localMatches.take(_maxSearchResults).toList();
    }
    final updated = {
      for (final result in results) result.source.id: result.source,
    };
    _applySourceResults(updated);
    notifyListeners();
    final activeIds = enabledSources.map((source) => source.id).toSet();
    final localIds = localMatches.map((item) => item.id).toSet();
    final finalResults = _uniqueItems([
      ...localMatches,
      ...results
          .expand((result) => result.items)
          .where((item) => activeIds.contains(item.sourceId)),
    ]).take(_maxSearchResults).toList();
    onResults?.call(finalResults);
    final failedSources = results
        .where((result) => result.source.health == SourceHealth.error)
        .length;
    onComplete?.call(
      SearchOutcome(
        enabledSourceCount: enabledSources.length,
        searchableSourceCount: searchSources.length,
        failedSourceCount: failedSources,
        localMatchCount: localMatches.length,
        remoteMatchCount: finalResults
            .where((item) => !localIds.contains(item.id))
            .length,
      ),
    );
    return finalResults;
  }

  Future<void> addSearchTerm(String value) async {
    final term = value.trim();
    if (term.isEmpty) return;
    final normalized = term.toLowerCase();
    searchHistory = [
      term,
      ...searchHistory.where((entry) => entry.toLowerCase() != normalized),
    ].take(_maxSearchHistory).toList();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(_searchHistoryKey, searchHistory);
    notifyListeners();
  }

  Future<void> removeSearchTerm(String value) async {
    final normalized = value.toLowerCase();
    searchHistory = searchHistory
        .where((entry) => entry.toLowerCase() != normalized)
        .toList();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(_searchHistoryKey, searchHistory);
    notifyListeners();
  }

  Future<void> clearSearchHistory() async {
    searchHistory = const [];
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_searchHistoryKey);
    notifyListeners();
  }

  Future<MediaItem> loadDetails(MediaItem item) async {
    if (item.isDemo) return item;
    MediaSource? source;
    for (final candidate in sources) {
      if (candidate.id == item.sourceId) {
        source = candidate;
        break;
      }
    }
    if (source == null || !source.enabled) {
      throw const SourceRequestException('片源已移除或禁用，请先在片源管理中启用');
    }
    if (item.episodes.isNotEmpty || source.kind == SourceKind.m3u) return item;
    if (source.kind == SourceKind.jellyfin || source.kind == SourceKind.emby) {
      return _loadMediaServerDetails(item, source);
    }
    if (source.kind != SourceKind.cms) return item;
    final contentId = item.id.split(':').last;
    try {
      final uri = _requestUri(source.endpoint, {
        'ac': 'detail',
        'ids': contentId,
      });
      final headers = await requestHeaders(source.id);
      final response = await _get(uri, headers: headers);
      _checkResponse(response);
      final list = _extractRows(response);
      if (list.isEmpty || list.first is! Map) {
        throw const SourceRequestException('片源未返回影片详情');
      }
      final details = MediaItem.fromCms(
        Map<String, dynamic>.from(list.first as Map),
        source: source,
        posterHeaders: headers,
      );
      return _withProgress(_withProxyPoster(details), item);
    } on SourceRequestException {
      rethrow;
    } on TimeoutException {
      throw const SourceRequestException('详情加载超时，请重试');
    } on Object catch (error) {
      throw SourceRequestException(_describeFailure(error));
    }
  }

  Future<void> addImport(SourceImportResult result) async {
    final merged = [...sources];
    for (final incoming in result.sources) {
      final existingIndex = merged.indexWhere(
        (source) => source.endpoint == incoming.endpoint,
      );
      final id = existingIndex < 0 ? incoming.id : merged[existingIndex].id;
      final headers = result.headersBySourceId[incoming.id];
      if (headers != null && headers.isNotEmpty) {
        await _writeHeaders(id, headers);
      }
      if (existingIndex < 0) {
        merged.add(incoming);
      } else if (headers != null && headers.isNotEmpty) {
        merged[existingIndex] = merged[existingIndex].copyWith(
          requiresAuth: true,
        );
      }
    }
    sources = merged;
    localItems = _uniqueItems([...localItems, ...result.items]);
    await _saveSources();
    await _saveLocalItems();
    notifyListeners();
  }

  Future<void> removeSource(String id) async {
    sources = sources.where((source) => source.id != id).toList();
    localItems = localItems.where((item) => item.sourceId != id).toList();
    catalog = catalog.where((item) => item.sourceId != id).toList();
    homeSnapshot = homeSnapshot.where((item) => item.sourceId != id).toList();
    await _secureStorage.delete(key: _headersKey(id));
    await _saveSources();
    await _saveLocalItems();
    await _saveHomeSnapshot();
    notifyListeners();
  }

  Future<void> setSourceEnabled(String id, bool enabled) async {
    sources = [
      for (final source in sources)
        if (source.id == id) source.copyWith(enabled: enabled) else source,
    ];
    await _saveSources();
    notifyListeners();
    if (enabled) unawaited(refreshSources());
  }

  Future<void> toggleFavorite(MediaItem item) async {
    if (!favorites.add(item.id)) favorites.remove(item.id);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(_favoritesKey, favorites.toList());
    favoriteItems = [
      if (favorites.contains(item.id)) item,
      ...favoriteItems.where(
        (entry) => entry.id != item.id && favorites.contains(entry.id),
      ),
    ];
    await preferences.setString(
      _favoriteItemsKey,
      encodeMediaList(favoriteItems),
    );
    notifyListeners();
  }

  Future<void> toggleFollow(MediaItem item) async {
    if (!follows.add(item.id)) follows.remove(item.id);
    notifyListeners();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(_followsKey, follows.toList());
  }

  Future<void> updateProgress(
    MediaItem item,
    int seconds,
    int durationSeconds, {
    MediaEpisode? episode,
  }) async {
    if (seconds <= 0) return;
    if (durationSeconds > 0 && seconds >= durationSeconds) {
      history = history.where((entry) => entry.id != item.id).toList();
    } else {
      final updated = item.copyWith(
        durationSeconds: durationSeconds,
        progressSeconds: seconds,
        progressEpisodeId: episode?.progressKey,
        progressEpisodeTitle: episode?.title,
      );
      history = [
        updated,
        ...history.where((entry) => entry.id != item.id),
      ].take(100).toList();
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_historyKey, encodeMediaList(history));
    notifyListeners();
  }

  String playbackUrl(String rawUrl) {
    final uri = Uri.tryParse(rawUrl);
    if (!_useWebProxy ||
        uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty) {
      return rawUrl;
    }
    if (uri.scheme == _webProxyEndpoint.scheme &&
        uri.host == _webProxyEndpoint.host &&
        uri.port == _webProxyEndpoint.port &&
        uri.path == _webProxyEndpoint.path) {
      return rawUrl;
    }
    return _webProxyEndpoint
        .replace(
          queryParameters: {
            ..._webProxyEndpoint.queryParameters,
            'url': uri.toString(),
          },
        )
        .toString();
  }

  Future<void> clearHistory() async {
    history = const [];
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_historyKey);
    notifyListeners();
  }

  Future<void> setReduceMotion(bool value) async {
    reduceMotion = value;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_motionKey, value);
    notifyListeners();
  }

  Future<void> setAutoplayNext(bool value) async {
    autoplayNext = value;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_autoplayKey, value);
    notifyListeners();
  }

  Future<void> addMediaServer({
    required String name,
    required String endpoint,
    required SourceKind kind,
    required String token,
  }) async {
    final uri = Uri.tryParse(endpoint.trim());
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !{SourceKind.jellyfin, SourceKind.emby}.contains(kind)) {
      throw const FormatException('服务器地址无效');
    }
    final normalizedPath = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
    final normalizedEndpoint = uri.replace(path: normalizedPath).toString();
    if (token.trim().isEmpty ||
        token.contains('\r') ||
        token.contains('\n') ||
        token.length > 4096) {
      throw const FormatException('请输入有效的服务器 API Token');
    }
    final id =
        'server-${SourceImporter.idFor('${kind.name}:$normalizedEndpoint')}';
    final headers = {'X-Emby-Token': token.trim()};
    await _writeHeaders(id, headers);
    final source = MediaSource(
      id: id,
      name: name.trim().isEmpty ? kind.name : name.trim(),
      endpoint: normalizedEndpoint,
      kind: kind,
      requiresAuth: headers.isNotEmpty,
    );
    sources = [...sources.where((current) => current.id != id), source];
    await _saveSources();
    notifyListeners();
    await refreshSources();
  }

  Future<Map<String, String>> requestHeaders(String sourceId) async {
    final source = sources.where((value) => value.id == sourceId);
    if (source.isEmpty || !source.first.requiresAuth) return const {};
    try {
      final encoded = await _secureStorage.read(key: _headersKey(sourceId));
      if (encoded == null) {
        throw const SourceRequestException('认证信息缺失，请重新添加片源或服务器');
      }
      final decoded = jsonDecode(encoded);
      if (decoded is! Map || decoded.isEmpty) {
        throw const SourceRequestException('认证信息无效，请重新添加片源或服务器');
      }
      return {
        for (final entry in decoded.entries)
          entry.key.toString(): entry.value.toString(),
      };
    } on SourceRequestException {
      rethrow;
    } on Object {
      throw const SourceRequestException('安全存储不可用，请稍后重试');
    }
  }

  Future<void> _saveSources() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _sourcesKey,
      jsonEncode(sources.map((source) => source.toJson()).toList()),
    );
  }

  Future<void> _saveLocalItems() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_localItemsKey, encodeMediaList(localItems));
  }

  Future<void> _saveHomeSnapshot() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _homeSnapshotKey,
      encodeMediaList(homeSnapshot.take(_maxHomeSnapshotItems).toList()),
    );
  }

  Future<void> _writeHeaders(
    String sourceId,
    Map<String, String> headers,
  ) async {
    if (headers.isEmpty) {
      await _secureStorage.delete(key: _headersKey(sourceId));
    } else {
      await _secureStorage.write(
        key: _headersKey(sourceId),
        value: jsonEncode(headers),
      );
    }
  }

  static String _headersKey(String sourceId) =>
      'zhuying.source.$sourceId.headers';

  Future<List<MediaItem>> _attachPosterHeaders(List<MediaItem> items) async {
    final headersBySource = <String, Map<String, String>>{};
    for (final sourceId in items.map((item) => item.sourceId).toSet()) {
      Map<String, String> headers = const {};
      try {
        headers = await requestHeaders(sourceId);
      } on SourceRequestException {
        // Keep the saved record visible even if credentials need to be replaced.
      }
      headersBySource[sourceId] = headers;
    }
    return [
      for (final item in items)
        _withProxyPoster(
          item,
        ).copyWith(posterHeaders: headersBySource[item.sourceId] ?? const {}),
    ];
  }

  Future<_SourceFetchResult> _fetchSource(
    MediaSource source, {
    String? query,
    int startPage = 1,
    int pageLimit = _initialCatalogPages,
    String? categoryId,
    String? year,
    String? region,
    bool trackCatalogPagination = true,
    bool fetchMissingPosters = true,
    void Function(List<MediaItem> items)? onItems,
  }) async {
    try {
      final headers = await requestHeaders(source.id);
      final firstPage = await _fetchCmsPage(
        source,
        headers: headers,
        page: startPage,
        query: query,
        categoryId: categoryId,
        year: year,
        region: region,
      );
      final rawList = [...firstPage.rows];
      List<MediaItem> mapRows(
        Iterable<dynamic> rows, [
        Map<String, dynamic> detailsById = const {},
      ]) {
        return rows
            .whereType<Map>()
            .map((value) {
              final row = Map<String, dynamic>.from(value);
              final id = (row['vod_id'] ?? row['id'])?.toString();
              final merged = <String, dynamic>{...row, ...?detailsById[id]};
              return _withProxyPoster(
                MediaItem.fromCms(
                  merged,
                  source: source,
                  posterHeaders: headers,
                ),
              );
            })
            .where((item) => item.title.isNotEmpty)
            .toList();
      }

      onItems?.call(mapRows(firstPage.rows));
      final pendingItems = <MediaItem>[];
      final pageCount = firstPage.pageCount;
      final shouldProbePages =
          firstPage.rows.isNotEmpty &&
          (pageCount != null || firstPage.rows.length >= _defaultCmsPageSize);
      final lastAllowedPage = startPage + pageLimit - 1;
      final lastPage = query != null
          ? startPage
          : pageCount == null
          ? lastAllowedPage
          : pageCount < lastAllowedPage
          ? pageCount
          : lastAllowedPage;
      final seenPageKeys = <String>{
        for (final row in firstPage.rows) ?_cmsRowKey(row),
      };
      var nextPage = startPage + 1;
      var reachedEnd =
          pageCount != null && startPage >= pageCount ||
          firstPage.rows.isEmpty ||
          pageCount == null && firstPage.rows.length < _defaultCmsPageSize;
      if (query == null && shouldProbePages) {
        for (var page = startPage + 1; page <= lastPage; page++) {
          _CmsPage fetchedPage;
          try {
            fetchedPage = await _fetchCmsPage(
              source,
              headers: headers,
              page: page,
              query: query,
              categoryId: categoryId,
              year: year,
              region: region,
            );
          } on Object {
            nextPage = page;
            break;
          }
          if (fetchedPage.rows.isEmpty) {
            reachedEnd = true;
            break;
          }
          final newRows = fetchedPage.rows.where((row) {
            final key = _cmsRowKey(row);
            return key == null || seenPageKeys.add(key);
          }).toList();
          if (newRows.isEmpty) {
            reachedEnd = true;
            break;
          }
          rawList.addAll(newRows);
          pendingItems.addAll(mapRows(newRows));
          nextPage = page + 1;
          if (page == lastPage) {
            onItems?.call(List.of(pendingItems));
            pendingItems.clear();
          }
          if (pageCount == null &&
              fetchedPage.rows.length < _defaultCmsPageSize) {
            reachedEnd = true;
            break;
          }
          if (pageCount != null && page >= pageCount) {
            reachedEnd = true;
            break;
          }
        }
      }
      if (pendingItems.isNotEmpty) onItems?.call(List.of(pendingItems));
      if (query == null && categoryId == null && trackCatalogPagination) {
        if (!reachedEnd && nextPage <= _maxCatalogPages) {
          _catalogNextPage[source.id] = nextPage;
        } else {
          _catalogNextPage.remove(source.id);
        }
      }
      final missingPosterIds = <String>{};
      for (final value in rawList.whereType<Map>()) {
        final row = Map<String, dynamic>.from(value);
        final id = (row['vod_id'] ?? row['id'])?.toString();
        if (id == null || id.isEmpty) continue;
        if (MediaItem.fromCms(row, source: source).posterUrl.isEmpty) {
          missingPosterIds.add(id);
        }
      }
      final posterDetails = _cmsPosterDetailsBySource.putIfAbsent(
        source.id,
        () => <String, Map<String, dynamic>>{},
      );
      final attemptedPosterIds = _cmsPosterDetailsAttemptedBySource.putIfAbsent(
        source.id,
        () => <String>{},
      );
      final ids = query == null && fetchMissingPosters
          ? missingPosterIds
                .where((id) => !attemptedPosterIds.contains(id))
                .toList()
          : <String>[];
      final detailsById = <String, Map<String, dynamic>>{
        for (final entry in posterDetails.entries)
          if (missingPosterIds.contains(entry.key)) entry.key: entry.value,
      };
      if (ids.isNotEmpty) {
        for (var start = 0; start < ids.length; start += _cmsDetailBatchSize) {
          final end = start + _cmsDetailBatchSize > ids.length
              ? ids.length
              : start + _cmsDetailBatchSize;
          try {
            final detailResponse = await _get(
              _requestUri(source.endpoint, {
                'ac': 'detail',
                'ids': ids.sublist(start, end).join(','),
              }),
              headers: headers,
            );
            _checkResponse(detailResponse);
            for (final row in _extractRows(detailResponse).whereType<Map>()) {
              final id = (row['vod_id'] ?? row['id'])?.toString();
              if (id != null) {
                final details = Map<String, dynamic>.from(row);
                detailsById[id] = details;
                final posterFields = _cmsPosterFields(details);
                if (posterFields.isNotEmpty) posterDetails[id] = posterFields;
              }
            }
            attemptedPosterIds.addAll(ids.sublist(start, end));
            final batchDetails = <String, Map<String, dynamic>>{};
            for (final id in ids.sublist(start, end)) {
              final details = detailsById[id];
              if (details != null) batchDetails[id] = details;
            }
            if (batchDetails.isNotEmpty) {
              onItems?.call(
                mapRows(
                  rawList.where((row) {
                    if (row is! Map) return false;
                    final id = (row['vod_id'] ?? row['id'])?.toString();
                    return id != null && batchDetails.containsKey(id);
                  }),
                  batchDetails,
                ),
              );
            }
          } on Object {
            // A failed metadata request should not make a working catalog unavailable.
          }
        }
      }
      final items = mapRows(rawList, detailsById);
      return _SourceFetchResult(
        source.copyWith(
          health: SourceHealth.available,
          statusMessage: '${items.length} 部影片',
        ),
        items,
        nextPage: reachedEnd || nextPage > _maxCatalogPages ? null : nextPage,
      );
    } on SourceRequestException catch (error) {
      return _SourceFetchResult(
        source.copyWith(
          health: SourceHealth.error,
          statusMessage: error.message,
        ),
        const [],
      );
    } on TimeoutException {
      return _SourceFetchResult(
        source.copyWith(health: SourceHealth.error, statusMessage: '连接超时'),
        const [],
      );
    } on Object catch (error) {
      return _SourceFetchResult(
        source.copyWith(
          health: SourceHealth.error,
          statusMessage: _describeFailure(error),
        ),
        const [],
      );
    }
  }

  static Map<String, dynamic> _cmsPosterFields(Map<String, dynamic> row) {
    const posterKeys = {
      'vod_pic',
      'pic',
      'cover',
      'vod_pic_thumb',
      'vod_pic_small',
      'pic_thumb',
      'pic_small',
      'vod_thumb',
      'cover_thumb',
      'cover_small',
      'thumbnail',
      'thumb',
    };
    return {
      for (final entry in row.entries)
        if (posterKeys.contains(entry.key) &&
            entry.value?.toString().trim().isNotEmpty == true)
          entry.key: entry.value,
    };
  }

  Future<_CmsPage> _fetchCmsPage(
    MediaSource source, {
    required Map<String, String> headers,
    required int page,
    String? query,
    String? categoryId,
    String? year,
    String? region,
  }) async {
    final params = <String, String>{'ac': 'list', 'pg': '$page'};
    if (query != null && query.isNotEmpty) params['wd'] = query;
    if (categoryId != null && categoryId.isNotEmpty) params['t'] = categoryId;
    if (year != null && year.isNotEmpty) params['y'] = year;
    if (region != null && region.isNotEmpty) params['a'] = region;
    final response = await _get(
      _requestUri(source.endpoint, params),
      headers: headers,
      timeout: query == null ? _requestTimeout : _searchTimeout,
    );
    _checkResponse(response);
    return _extractCmsPage(response);
  }

  Future<_SourceFetchResult> _fetchMediaServer(
    MediaSource source, {
    String? query,
    List<String> genres = const [],
    int startIndex = 0,
    void Function(List<MediaItem> items)? onItems,
  }) async {
    try {
      final headers = await requestHeaders(source.id);
      final endpoint = Uri.parse(source.endpoint).resolve('Items');
      final pageSize = genres.isEmpty
          ? _defaultMediaServerPageSize
          : _defaultCmsPageSize;
      final params = <String, String>{
        'Recursive': 'true',
        'IncludeItemTypes': 'Movie,Series',
        'Fields': 'Overview,Genres,PrimaryImageAspectRatio',
        'Limit': '$pageSize',
        'StartIndex': '$startIndex',
        'SortBy': 'DateCreated',
        'SortOrder': 'Descending',
      };
      if (query != null && query.isNotEmpty) params['SearchTerm'] = query;
      if (genres.isNotEmpty) params['Genres'] = genres.join(',');
      final response = await _get(
        _requestUri(endpoint.toString(), params),
        headers: headers,
        timeout: query == null ? _requestTimeout : _searchTimeout,
      );
      _checkResponse(response);
      final payload = jsonDecode(utf8.decode(response.bodyBytes));
      if (payload is! Map || payload['Items'] is! List) {
        throw const SourceRequestException('服务器目录格式无法识别');
      }
      final rows = payload['Items'] as List;
      final items = rows
          .whereType<Map>()
          .map(
            (row) => _mediaServerItem(
              Map<String, dynamic>.from(row),
              source,
              headers,
            ),
          )
          .where((item) => item.title.isNotEmpty)
          .toList();
      onItems?.call(items);
      final total = _positiveInt(payload['TotalRecordCount']);
      final nextPage = total != null && startIndex + rows.length < total
          ? startIndex ~/ pageSize + 2
          : null;
      return _SourceFetchResult(
        source.copyWith(
          health: SourceHealth.available,
          statusMessage: '${items.length} 部影片',
        ),
        items,
        nextPage: nextPage,
      );
    } on SourceRequestException catch (error) {
      return _SourceFetchResult(
        source.copyWith(
          health: SourceHealth.error,
          statusMessage: error.message,
        ),
        const [],
      );
    } on TimeoutException {
      return _SourceFetchResult(
        source.copyWith(health: SourceHealth.error, statusMessage: '连接超时'),
        const [],
      );
    } on Object catch (error) {
      return _SourceFetchResult(
        source.copyWith(
          health: SourceHealth.error,
          statusMessage: _describeFailure(error),
        ),
        const [],
      );
    }
  }

  Future<_SourceFetchResult> _fetchCatalog(
    MediaSource source, {
    String? query,
    void Function(List<MediaItem> items)? onItems,
  }) => source.kind == SourceKind.cms
      ? _fetchSource(source, query: query, onItems: onItems)
      : _fetchMediaServer(source, query: query, onItems: onItems);

  MediaItem _mediaServerItem(
    Map<String, dynamic> row,
    MediaSource source,
    Map<String, String> headers,
  ) {
    final id = row['Id']?.toString() ?? '';
    final genres = row['Genres'];
    final regions = row['ProductionLocations'];
    final imageTags = row['ImageTags'];
    final hasPoster = imageTags is Map && imageTags['Primary'] != null;
    final normalizedGenres = normalizeGenres(genres);
    return MediaItem(
      id: '${source.id}:$id',
      title: row['Name']?.toString() ?? '',
      sourceId: source.id,
      sourceName: source.name,
      posterUrl: !hasPoster || id.isEmpty
          ? ''
          : _proxyImageUrl(
              Uri.parse(source.endpoint)
                  .resolve('Items/${Uri.encodeComponent(id)}/Images/Primary')
                  .replace(queryParameters: {'maxWidth': '800'})
                  .toString(),
            ),
      thumbnailUrl: !hasPoster || id.isEmpty
          ? ''
          : _proxyImageUrl(
              Uri.parse(source.endpoint)
                  .resolve('Items/${Uri.encodeComponent(id)}/Images/Primary')
                  .replace(queryParameters: {'maxWidth': '240'})
                  .toString(),
            ),
      posterHeaders: headers,
      description: row['Overview']?.toString() ?? '',
      rating: (row['CommunityRating'] ?? row['CriticRating'])?.toString() ?? '',
      year: row['ProductionYear']?.toString() ?? '',
      genre: normalizedGenres.isEmpty ? '' : normalizedGenres.first,
      genres: normalizedGenres,
      region: regions is List && regions.isNotEmpty
          ? regions.first.toString()
          : '',
      remarks: row['Type'] == 'Series' ? '剧集' : '电影',
      durationSeconds: ((row['RunTimeTicks'] as num? ?? 0) / 10000000).floor(),
    );
  }

  Future<MediaItem> _loadMediaServerDetails(
    MediaItem item,
    MediaSource source,
  ) async {
    try {
      final headers = await requestHeaders(source.id);
      final contentId = item.id.substring(source.id.length + 1);
      final base = Uri.parse(source.endpoint);
      final response = await _get(
        _requestUri(base.resolve('Items').toString(), {
          'Ids': contentId,
          'Fields': 'Overview,Genres,MediaSources,CommunityRating,CriticRating',
        }),
        headers: headers,
      );
      _checkResponse(response);
      final payload = jsonDecode(utf8.decode(response.bodyBytes));
      final rows = payload is Map ? payload['Items'] : null;
      if (rows is! List || rows.isEmpty || rows.first is! Map) {
        throw const SourceRequestException('服务器未返回影片详情');
      }
      final row = Map<String, dynamic>.from(rows.first as Map);
      final episodes = <MediaEpisode>[];
      if (row['Type'] == 'Series') {
        final episodeResponse = await _get(
          _requestUri(
            base
                .resolve('Shows/${Uri.encodeComponent(contentId)}/Episodes')
                .toString(),
            const {},
          ),
          headers: headers,
        );
        _checkResponse(episodeResponse);
        final episodePayload = jsonDecode(
          utf8.decode(episodeResponse.bodyBytes),
        );
        final episodeRows = episodePayload is Map
            ? episodePayload['Items']
            : null;
        if (episodeRows is! List) {
          throw const SourceRequestException('服务器选集格式无法识别');
        }
        final sorted = episodeRows.whereType<Map>().toList()
          ..sort((first, second) {
            final seasonOrder = (first['ParentIndexNumber'] as num? ?? 0)
                .compareTo(second['ParentIndexNumber'] as num? ?? 0);
            return seasonOrder != 0
                ? seasonOrder
                : (first['IndexNumber'] as num? ?? 0).compareTo(
                    second['IndexNumber'] as num? ?? 0,
                  );
          });
        for (final episode in sorted) {
          final id = episode['Id']?.toString() ?? '';
          if (id.isEmpty ||
              episode['IsMissing'] == true ||
              episode['LocationType'] == 'Virtual') {
            continue;
          }
          final season = episode['ParentIndexNumber']?.toString() ?? '';
          final number = episode['IndexNumber']?.toString() ?? '';
          final name = episode['Name']?.toString() ?? '未命名选集';
          episodes.add(
            _serverEpisode(
              base,
              id,
              season.isEmpty || number.isEmpty
                  ? name
                  : 'S$season E$number · $name',
            ),
          );
        }
      } else {
        episodes.add(_serverEpisode(base, contentId, '正片'));
      }
      return _withProgress(
        _mediaServerItem(row, source, headers).copyWith(episodes: episodes),
        item,
      );
    } on SourceRequestException {
      rethrow;
    } on TimeoutException {
      throw const SourceRequestException('详情加载超时，请重试');
    } on Object catch (error) {
      throw SourceRequestException(_describeFailure(error));
    }
  }

  static MediaEpisode _serverEpisode(Uri base, String id, String title) =>
      MediaEpisode(
        id: id,
        title: title,
        url: base
            .resolve('Videos/${Uri.encodeComponent(id)}/stream')
            .replace(queryParameters: {'Static': 'true'})
            .toString(),
      );

  static MediaItem _withProgress(MediaItem details, MediaItem saved) =>
      details.copyWith(
        durationSeconds: saved.durationSeconds > 0
            ? saved.durationSeconds
            : details.durationSeconds,
        progressSeconds: saved.progressSeconds,
        progressEpisodeId: saved.progressEpisodeId,
        progressEpisodeTitle: saved.progressEpisodeTitle,
      );

  MediaItem _withProxyPoster(MediaItem item) => item.copyWith(
    posterUrl: _proxyImageUrl(item.posterUrl),
    thumbnailUrl: _proxyImageUrl(item.thumbnailUrl),
  );

  String _proxyImageUrl(String imageUrl) {
    final image = Uri.tryParse(imageUrl);
    if (!_useWebProxy ||
        image == null ||
        !{'http', 'https'}.contains(image.scheme) ||
        image.host.isEmpty) {
      return imageUrl;
    }
    if (image.scheme == _webProxyEndpoint.scheme &&
        image.host == _webProxyEndpoint.host &&
        image.port == _webProxyEndpoint.port &&
        image.path == _webProxyEndpoint.path) {
      return imageUrl;
    }
    return _webProxyEndpoint
        .replace(
          queryParameters: {
            ..._webProxyEndpoint.queryParameters,
            'url': image.toString(),
          },
        )
        .toString();
  }

  static String _describeFailure(Object error) {
    final message = error.toString().toLowerCase();
    if (error is FormatException || message.contains('xml')) {
      return '接口返回格式无法识别';
    }
    if (message.contains('handshakeexception') ||
        message.contains('certificate_verify_failed') ||
        message.contains('tls') ||
        message.contains('ssl')) {
      return 'TLS 证书验证失败';
    }
    if (message.contains('failed host lookup') ||
        message.contains('socketexception') ||
        message.contains('network is unreachable') ||
        message.contains('connection refused')) {
      return '网络不可达或 DNS 解析失败';
    }
    if (kIsWeb) return '连接失败：请检查代理或跨域（CORS）设置';
    return '请求失败，请检查网络与片源地址';
  }

  Future<http.Response> _get(
    Uri uri, {
    Map<String, String> headers = const {},
    Duration timeout = _requestTimeout,
  }) {
    final requestHeaders = <String, String>{
      'Accept': 'application/json, text/plain, */*',
      ...headers,
    };
    if (!kIsWeb) requestHeaders['User-Agent'] = 'Zhuying/1.0 Flutter';
    return _client.get(uri, headers: requestHeaders).timeout(timeout);
  }

  Future<List<R>> _mapConcurrent<T, R>(
    List<T> values,
    int concurrency,
    Future<R> Function(T value) operation, {
    bool Function()? shouldContinue,
  }) async {
    if (values.isEmpty) return <R>[];
    final results = List<R?>.filled(values.length, null);
    var nextIndex = 0;
    Future<void> worker() async {
      while (nextIndex < values.length && (shouldContinue?.call() ?? true)) {
        final index = nextIndex++;
        results[index] = await operation(values[index]);
      }
    }

    final workerCount = values.length < concurrency
        ? values.length
        : concurrency;
    await Future.wait([
      for (var index = 0; index < workerCount; index++) worker(),
    ]);
    return [for (final result in results) ?result];
  }

  void _updateSource(MediaSource updated) {
    sources = [
      for (final source in sources)
        if (source.id == updated.id)
          source.copyWith(
            health: updated.health,
            statusMessage: updated.statusMessage,
          )
        else
          source,
    ];
  }

  void _applySourceResults(Map<String, MediaSource> updated) {
    sources = [
      for (final source in sources)
        if (updated[source.id] case final result?)
          source.copyWith(
            health: result.health,
            statusMessage: result.statusMessage,
          )
        else
          source,
    ];
  }

  static void _checkResponse(http.Response response) {
    if (response.statusCode == 200) return;
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw SourceRequestException('认证或访问被拒绝（HTTP ${response.statusCode}）');
    }
    throw SourceRequestException('服务器返回 HTTP ${response.statusCode}');
  }

  Uri _requestUri(String endpoint, Map<String, String> params) {
    final uri = Uri.parse(endpoint);
    final upstream = uri.replace(
      queryParameters: {...uri.queryParameters, ...params},
    );
    if (!_useWebProxy) return upstream;
    return _webProxyEndpoint.replace(
      queryParameters: {
        ..._webProxyEndpoint.queryParameters,
        'url': upstream.toString(),
      },
    );
  }

  static _CmsPage _extractCmsPage(http.Response response) {
    final body = utf8.decode(response.bodyBytes, allowMalformed: true).trim();
    if (body.isEmpty) return const _CmsPage(rows: []);
    if (body.startsWith('<')) {
      try {
        final document = XmlDocument.parse(body);
        final rows = document
            .findAllElements('video')
            .map(
              (element) => <String, dynamic>{
                for (final child in element.children.whereType<XmlElement>())
                  if (child.name.local == 'dl')
                    'vod_play_url': child
                        .findElements('dd')
                        .map((entry) => entry.innerText.trim())
                        .join(r'$$$')
                  else
                    switch (child.name.local) {
                      'id' => 'vod_id',
                      'name' => 'vod_name',
                      'pic' => 'vod_pic',
                      'type' => 'type_name',
                      'des' => 'vod_content',
                      'year' => 'vod_year',
                      'area' => 'vod_area',
                      'note' => 'vod_remarks',
                      final name => name,
                    }: child.innerText
                        .trim(),
              },
            )
            .toList();
        final pageCount =
            _positiveInt(_xmlText(document, 'pagecount')) ??
            _pageCountFromTotal(
              total: _positiveInt(_xmlText(document, 'total')),
              limit: _positiveInt(_xmlText(document, 'limit')),
            );
        return _CmsPage(rows: rows, pageCount: pageCount);
      } on XmlException {
        throw const FormatException('片源 XML 格式无效');
      }
    }
    try {
      final payload = jsonDecode(body);
      if (payload is! Map) return const _CmsPage(rows: []);
      final data = payload['data'];
      final dataMap = data is Map ? data : null;
      final list =
          payload['list'] ?? (dataMap?['list'] ?? (data is List ? data : null));
      if (list is List) {
        final pageCount =
            _positiveInt(
              payload['pagecount'] ??
                  payload['pageCount'] ??
                  payload['page_count'] ??
                  dataMap?['pagecount'] ??
                  dataMap?['pageCount'] ??
                  dataMap?['page_count'],
            ) ??
            _pageCountFromTotal(
              total: _positiveInt(payload['total'] ?? dataMap?['total']),
              limit: _positiveInt(
                payload['limit'] ??
                    payload['pagesize'] ??
                    dataMap?['limit'] ??
                    dataMap?['pagesize'],
              ),
            );
        return _CmsPage(rows: list, pageCount: pageCount);
      }
    } on FormatException {
      throw const FormatException('片源 JSON 格式无效');
    }
    throw const FormatException('片源未返回可识别的影片列表');
  }

  static List<dynamic> _extractRows(http.Response response) =>
      _extractCmsPage(response).rows;

  static int? _positiveInt(Object? value) {
    final parsed = value is num ? value.toInt() : int.tryParse('$value');
    return parsed != null && parsed > 0 ? parsed : null;
  }

  static int? _pageCountFromTotal({int? total, int? limit}) {
    if (total == null || limit == null || limit <= 0) return null;
    return (total + limit - 1) ~/ limit;
  }

  static String? _xmlText(XmlDocument document, String name) {
    final elements = document.findAllElements(name);
    return elements.isEmpty ? null : elements.first.innerText.trim();
  }

  static String? _cmsRowKey(Object row) {
    if (row is! Map) return null;
    final id = row['vod_id'] ?? row['id'];
    if (id != null && id.toString().trim().isNotEmpty) {
      return 'id:${id.toString()}';
    }
    final title = row['vod_name'] ?? row['name'] ?? row['title'];
    if (title != null && title.toString().trim().isNotEmpty) {
      return 'title:${_sourceTitleKey(title.toString())}';
    }
    return null;
  }

  static String _sourceTitleKey(String title) {
    var value = title.trim().toLowerCase();
    for (final pattern in [
      RegExp(r'\[[^\]]*\]'),
      RegExp(r'【[^】]*】'),
      RegExp(r'\([^)]*\)'),
      RegExp(r'（[^）]*）'),
    ]) {
      value = value.replaceAll(pattern, '');
    }
    value = value.replaceFirst(
      RegExp(r'(第?\d+(?:季|部|篇)|season\s*\d+|s\d+)$'),
      '',
    );
    return value.replaceAll(RegExp(r'''[\s.,!?，。！？：:；;、/\\|_+&·•\-'" ]'''), '');
  }

  static List<MediaItem> _uniqueItems(Iterable<MediaItem> items) {
    final unique = <String, MediaItem>{};
    for (final item in items) {
      unique.update(
        item.id,
        (existing) => _mergeMediaItem(existing, item),
        ifAbsent: () => item,
      );
    }
    return unique.values.toList();
  }

  static MediaItem _mergeMediaItem(MediaItem? existing, MediaItem incoming) {
    if (existing == null) return incoming;
    final genres = normalizeGenres([
      ...existing.genreLabels,
      ...incoming.genreLabels,
    ]);
    return existing.copyWith(
      posterUrl: existing.posterUrl.isEmpty
          ? incoming.posterUrl
          : existing.posterUrl,
      thumbnailUrl: existing.thumbnailUrl.isEmpty
          ? incoming.thumbnailUrl
          : existing.thumbnailUrl,
      year: existing.year.isEmpty ? incoming.year : existing.year,
      region: existing.region.isEmpty ? incoming.region : existing.region,
      genre: genres.isEmpty ? existing.genre : genres.first,
      genres: genres,
      rating: existing.rating.isEmpty ? incoming.rating : existing.rating,
      description: existing.description.isEmpty
          ? incoming.description
          : existing.description,
      remarks: existing.remarks.isEmpty ? incoming.remarks : existing.remarks,
      episodes: existing.episodes.isEmpty
          ? incoming.episodes
          : existing.episodes,
      posterHeaders: existing.posterHeaders.isEmpty
          ? incoming.posterHeaders
          : existing.posterHeaders,
    );
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _client.close();
    super.dispose();
  }
}

class SourceRequestException implements Exception {
  const SourceRequestException(this.message);

  final String message;
}

class _SourceFetchResult {
  const _SourceFetchResult(this.source, this.items, {this.nextPage});

  final MediaSource source;
  final List<MediaItem> items;
  final int? nextPage;
}

class _CmsTypeCategory {
  const _CmsTypeCategory({required this.id, required this.genre});

  final String id;
  final String genre;
}

class _CategoryRouteResult {
  const _CategoryRouteResult(
    this.routeKey,
    this.source,
    this.requestPage,
    this.result,
  );

  final String routeKey;
  final MediaSource? source;
  final int requestPage;
  final _SourceFetchResult result;
}

class _CmsPage {
  const _CmsPage({required this.rows, this.pageCount});

  final List<dynamic> rows;
  final int? pageCount;
}
