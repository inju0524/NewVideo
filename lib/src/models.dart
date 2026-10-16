import 'dart:convert';

enum SourceKind { cms, m3u, jellyfin, emby }

enum SourceHealth { pending, available, error, unsupported }

class SearchOutcome {
  const SearchOutcome({
    required this.enabledSourceCount,
    required this.searchableSourceCount,
    required this.failedSourceCount,
    this.localMatchCount = 0,
    this.remoteMatchCount = 0,
  });

  final int enabledSourceCount;
  final int searchableSourceCount;
  final int failedSourceCount;
  final int localMatchCount;
  final int remoteMatchCount;
}

class SearchCounts {
  const SearchCounts({required this.localMatches, required this.remoteMatches});

  final int localMatches;
  final int remoteMatches;
}

class MediaEpisode {
  const MediaEpisode({required this.title, required this.url, this.id = ''});

  final String title;
  final String url;
  final String id;

  String get progressKey => id.isEmpty ? title : id;
}

class MediaSource {
  const MediaSource({
    required this.id,
    required this.name,
    required this.endpoint,
    this.kind = SourceKind.cms,
    this.requiresAuth = false,
    this.enabled = true,
    this.health = SourceHealth.pending,
    this.statusMessage = '待刷新',
  });

  final String id;
  final String name;
  final String endpoint;
  final SourceKind kind;
  final bool requiresAuth;
  final bool enabled;
  final SourceHealth health;
  final String statusMessage;

  MediaSource copyWith({
    bool? enabled,
    bool? requiresAuth,
    SourceHealth? health,
    String? statusMessage,
  }) {
    return MediaSource(
      id: id,
      name: name,
      endpoint: endpoint,
      kind: kind,
      requiresAuth: requiresAuth ?? this.requiresAuth,
      enabled: enabled ?? this.enabled,
      health: health ?? this.health,
      statusMessage: statusMessage ?? this.statusMessage,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'endpoint': endpoint,
    'kind': kind.name,
    'requiresAuth': requiresAuth,
    'enabled': enabled,
    'health': health.name,
    'statusMessage': statusMessage,
  };

  factory MediaSource.fromJson(Map<String, dynamic> json) => MediaSource(
    id: json['id'] as String,
    name: json['name'] as String,
    endpoint: json['endpoint'] as String,
    kind: SourceKind.values.firstWhere(
      (value) => value.name == json['kind'],
      orElse: () => SourceKind.cms,
    ),
    requiresAuth: json['requiresAuth'] as bool? ?? false,
    enabled: json['enabled'] as bool? ?? true,
    health: SourceHealth.values.firstWhere(
      (value) => value.name == json['health'],
      orElse: () => SourceHealth.pending,
    ),
    statusMessage: json['statusMessage'] as String? ?? '待刷新',
  );
}

const defaultSources = [
  MediaSource(
    id: 'preset-bfzy',
    name: '暴风点播',
    endpoint: 'https://bfzyapi.com/api.php/provide/vod',
    statusMessage: '预置源',
  ),
  MediaSource(
    id: 'preset-ffzy',
    name: '非凡影视',
    endpoint: 'https://api.ffzyapi.com/api.php/provide/vod',
    statusMessage: '预置源',
  ),
  MediaSource(
    id: 'preset-lzi',
    name: '量子影视',
    endpoint: 'https://cj.lziapi.com/api.php/provide/vod/',
    statusMessage: '预置源',
  ),
  // Community endpoints from the public LibreTV discussion. Keep these
  // opt-in because each catalog can contain tens of thousands of entries.
  MediaSource(
    id: 'public-360zy',
    name: '360点播',
    endpoint: 'https://360zy.com/api.php/provide/vod/',
    enabled: false,
    statusMessage: '公开源，手动启用',
  ),
  MediaSource(
    id: 'public-apibdzy',
    name: '百度资源',
    endpoint: 'https://api.apibdzy.com/api.php/provide/vod/',
    enabled: false,
    statusMessage: '公开源，手动启用',
  ),
  MediaSource(
    id: 'public-guangsu',
    name: '光速资源',
    endpoint: 'https://api.guangsuapi.com/api.php/provide/vod/from/gsm3u8',
    enabled: false,
    statusMessage: '公开源，手动启用',
  ),
  MediaSource(
    id: 'public-yhzy',
    name: '樱花资源',
    endpoint: 'https://m3u8.apiyhzy.com/api.php/provide/vod/',
    enabled: false,
    statusMessage: '公开源，手动启用',
  ),
  MediaSource(
    id: 'public-wujin',
    name: '无尽资源',
    endpoint: 'https://api.wujinapi.com/api.php/provide/vod/',
    enabled: false,
    statusMessage: '公开源，手动启用',
  ),
  MediaSource(
    id: 'public-uku',
    name: 'U酷资源',
    endpoint: 'https://api.ukuapi.com/api.php/provide/vod/',
    enabled: false,
    statusMessage: '公开源，手动启用',
  ),
  MediaSource(
    id: 'public-xinlang',
    name: '新浪资源',
    endpoint: 'https://api.xinlangapi.com/xinlangapi.php/provide/vod/',
    enabled: false,
    statusMessage: '公开源，手动启用',
  ),
];

class MediaItem {
  const MediaItem({
    required this.id,
    required this.title,
    required this.sourceId,
    required this.sourceName,
    this.posterUrl = '',
    this.thumbnailUrl = '',
    this.year = '',
    this.region = '',
    this.genre = '',
    this.genres = const [],
    this.rating = '',
    this.description = '',
    this.remarks = '',
    this.episodes = const [],
    this.posterHeaders = const {},
    this.durationSeconds = 0,
    this.progressSeconds = 0,
    this.progressEpisodeId = '',
    this.progressEpisodeTitle = '',
    this.isDemo = false,
  });

  final String id;
  final String title;
  final String sourceId;
  final String sourceName;
  final String posterUrl;
  final String thumbnailUrl;
  final String year;
  final String region;
  final String genre;
  final List<String> genres;
  final String rating;
  final String description;
  final String remarks;
  final List<MediaEpisode> episodes;
  final Map<String, String> posterHeaders;
  final int durationSeconds;
  final int progressSeconds;
  final String progressEpisodeId;
  final String progressEpisodeTitle;
  final bool isDemo;

  /// All labels used by filters. Legacy items only have [genre].
  List<String> get genreLabels => genres.isNotEmpty
      ? genres
      : genre.isEmpty
      ? const []
      : [genre];

  double get progress => durationSeconds <= 0
      ? 0
      : (progressSeconds / durationSeconds).clamp(0, 1).toDouble();

  MediaItem copyWith({
    String? posterUrl,
    String? thumbnailUrl,
    String? year,
    String? region,
    String? genre,
    List<String>? genres,
    String? rating,
    String? description,
    String? remarks,
    List<MediaEpisode>? episodes,
    Map<String, String>? posterHeaders,
    int? durationSeconds,
    int? progressSeconds,
    String? progressEpisodeId,
    String? progressEpisodeTitle,
  }) {
    return MediaItem(
      id: id,
      title: title,
      sourceId: sourceId,
      sourceName: sourceName,
      posterUrl: posterUrl ?? this.posterUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      year: year ?? this.year,
      region: region ?? this.region,
      genre: genre ?? this.genre,
      genres: genres ?? (genre == null ? this.genres : normalizeGenres(genre)),
      rating: rating ?? this.rating,
      description: description ?? this.description,
      remarks: remarks ?? this.remarks,
      episodes: episodes ?? this.episodes,
      posterHeaders: posterHeaders ?? this.posterHeaders,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      progressSeconds: progressSeconds ?? this.progressSeconds,
      progressEpisodeId: progressEpisodeId ?? this.progressEpisodeId,
      progressEpisodeTitle: progressEpisodeTitle ?? this.progressEpisodeTitle,
      isDemo: isDemo,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'sourceId': sourceId,
    'sourceName': sourceName,
    'posterUrl': posterUrl,
    'thumbnailUrl': thumbnailUrl,
    'year': year,
    'region': region,
    'genre': genre,
    'genres': genreLabels,
    'rating': rating,
    'description': description,
    'remarks': remarks,
    'episodes': sourceId.startsWith('playlist-')
        ? [
            for (final episode in episodes)
              {'title': episode.title, 'url': episode.url},
          ]
        : const [],
    'durationSeconds': durationSeconds,
    'progressSeconds': progressSeconds,
    'progressEpisodeId': progressEpisodeId,
    'progressEpisodeTitle': progressEpisodeTitle,
    'isDemo': isDemo,
  };

  factory MediaItem.fromJson(Map<String, dynamic> json) {
    final episodes = (json['sourceId'] as String? ?? '').startsWith('playlist-')
        ? (json['episodes'] as List<dynamic>? ?? const [])
              .whereType<Map>()
              .map(
                (value) => MediaEpisode(
                  title: value['title']?.toString() ?? '',
                  url: value['url']?.toString() ?? '',
                ),
              )
              .where(
                (episode) =>
                    episode.title.isNotEmpty &&
                    _validHttpUrl(episode.url) != null,
              )
              .toList()
        : const <MediaEpisode>[];
    final savedGenres = normalizeGenres(json['genres']);
    final restoredGenres = savedGenres.isNotEmpty
        ? savedGenres
        : normalizeGenres(json['genre']);
    return MediaItem(
      id: json['id'] as String,
      title: json['title'] as String,
      sourceId: json['sourceId'] as String? ?? '',
      sourceName: json['sourceName'] as String? ?? '本地记录',
      posterUrl: json['posterUrl'] as String? ?? '',
      thumbnailUrl: json['thumbnailUrl'] as String? ?? '',
      year: json['year'] as String? ?? '',
      region: json['region'] as String? ?? '',
      genre: restoredGenres.isEmpty ? '' : restoredGenres.first,
      genres: restoredGenres,
      rating: json['rating'] as String? ?? '',
      description: json['description'] as String? ?? '',
      remarks: json['remarks'] as String? ?? '',
      episodes: episodes,
      posterHeaders: const {},
      durationSeconds: json['durationSeconds'] as int? ?? 0,
      progressSeconds: json['progressSeconds'] as int? ?? 0,
      progressEpisodeId: json['progressEpisodeId'] as String? ?? '',
      progressEpisodeTitle: json['progressEpisodeTitle'] as String? ?? '',
      isDemo: json['isDemo'] as bool? ?? false,
    );
  }

  factory MediaItem.fromCms(
    Map<String, dynamic> json, {
    required MediaSource source,
    Map<String, String> posterHeaders = const {},
  }) {
    final sourceId = _text(json['vod_id'] ?? json['id']);
    final title = _text(json['vod_name'] ?? json['title'] ?? json['name']);
    final rawImage = _text(json['vod_pic'] ?? json['pic'] ?? json['cover']);
    final posterUrl = _validHttpUrl(rawImage) ?? '';
    final rawThumbnail = _text(
      json['vod_pic_thumb'] ??
          json['vod_pic_small'] ??
          json['pic_thumb'] ??
          json['pic_small'] ??
          json['vod_thumb'] ??
          json['cover_thumb'] ??
          json['cover_small'] ??
          json['thumbnail'] ??
          json['thumb'],
    );
    final thumbnailUrl = _validHttpUrl(rawThumbnail) ?? '';
    final rawClass = _firstNonEmptyText([
      json['vod_class'],
      json['vod_genre'],
      json['genre'],
      json['type_name'],
    ]);
    final genres = normalizeGenres(rawClass);
    final episodes = _parseEpisodes(_text(json['vod_play_url']));

    return MediaItem(
      id: '${source.id}:${sourceId.isEmpty ? title : sourceId}',
      title: title.isEmpty ? '未命名影片' : title,
      sourceId: source.id,
      sourceName: source.name,
      posterUrl: posterUrl,
      thumbnailUrl: thumbnailUrl,
      year: _text(json['vod_year'] ?? json['year']),
      region: _text(json['vod_area'] ?? json['area']),
      genre: genres.isEmpty ? '' : genres.first,
      genres: genres,
      rating: _text(
        json['vod_score'] ??
            json['vod_douban_score'] ??
            json['score'] ??
            json['rating'],
      ),
      description: _stripMarkup(
        _text(json['vod_content'] ?? json['content'] ?? json['description']),
      ),
      remarks: _text(json['vod_remarks'] ?? json['remarks']),
      episodes: episodes,
      posterHeaders: posterHeaders,
    );
  }

  static List<MediaEpisode> _parseEpisodes(String raw) {
    if (raw.isEmpty) return const [];
    final directEntries = <MediaEpisode>[];
    final fallbackEntries = <MediaEpisode>[];
    for (final group in raw.split(r'$$$')) {
      for (final item in group.split('#')) {
        final separator = item.indexOf(r'$');
        if (separator < 1 || separator == item.length - 1) continue;
        final name = item.substring(0, separator).trim();
        final url = _validHttpUrl(item.substring(separator + 1).trim());
        if (url == null || _isPlaybackPage(url)) continue;
        final episode = MediaEpisode(
          title: name.isEmpty ? '播放' : name,
          url: url,
        );
        if (_isDirectMediaUrl(url)) {
          directEntries.add(episode);
        } else {
          fallbackEntries.add(episode);
        }
      }
    }
    return _uniqueEpisodes(
      directEntries.isNotEmpty ? directEntries : fallbackEntries,
    );
  }

  static bool _isDirectMediaUrl(String raw) {
    final uri = Uri.parse(raw);
    return RegExp(
      r'\.(m3u8|mp4|m4v|webm|ts)$',
      caseSensitive: false,
    ).hasMatch(uri.path);
  }

  static bool _isPlaybackPage(String raw) {
    final path = Uri.parse(raw).path.toLowerCase();
    return path.contains('/share/') ||
        path.endsWith('.html') ||
        path.endsWith('.htm');
  }

  static List<MediaEpisode> _uniqueEpisodes(Iterable<MediaEpisode> episodes) {
    final seen = <String>{};
    return episodes.where((episode) => seen.add(episode.url)).toList();
  }
}

/// Splits source-specific type strings and maps common aliases to the labels
/// used by the catalog filters. Unknown labels remain available as-is.
List<String> normalizeGenres(Object? raw) {
  final values = raw is Iterable ? raw : [raw];
  final result = <String>[];
  for (final value in values) {
    for (final part in _text(value).split(RegExp(r'[,，/|、]'))) {
      final label = _normalizeGenreLabel(part);
      if (label.isNotEmpty && !result.contains(label)) result.add(label);
    }
  }
  return result;
}

String _normalizeGenreLabel(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return '';
  const nonGenreCategories = {'电影', '电影片', '连续剧', '电视剧', '综艺', '综艺片', '电视节目'};
  if (nonGenreCategories.contains(value)) return '';
  if (RegExp(r'^(国产|大陆|内地|港台|香港|台湾|韩国|日本|泰国|欧美|海外)剧$').hasMatch(value)) {
    return '';
  }
  final lowerValue = value.toLowerCase();
  const aliases = {
    '剧情片': '剧情',
    '喜剧片': '喜剧',
    '爱情片': '爱情',
    '动作片': '动作',
    '科幻片': '科幻',
    '惊悚片': '惊悚',
    '悬疑片': '悬疑',
    '恐怖片': '恐怖',
    '犯罪片': '犯罪',
    '动画片': '动画',
    '家庭片': '家庭',
    '奇幻片': '奇幻',
    '战争片': '战争',
    '青春片': '青春',
    '伦理片': '伦理',
    '纪录片': '纪录',
    '冒险片': '冒险',
    '灾难片': '灾难',
    '传记片': '传记',
    '历史片': '历史',
    '武侠片': '武侠',
    '古装片': '古装',
    '音乐片': '音乐',
    '歌舞片': '歌舞',
    '动漫': '动画',
  };
  const englishAliases = {
    'drama': '剧情',
    'comedy': '喜剧',
    'romance': '爱情',
    'romantic': '爱情',
    'action': '动作',
    'science fiction': '科幻',
    'sci-fi': '科幻',
    'scifi': '科幻',
    'thriller': '惊悚',
    'suspense': '悬疑',
    'mystery': '悬疑',
    'horror': '恐怖',
    'crime': '犯罪',
    'animation': '动画',
    'anime': '动画',
    'family': '家庭',
    'fantasy': '奇幻',
    'war': '战争',
    'youth': '青春',
    'teen': '青春',
    'erotic': '伦理',
    'documentary': '纪录',
    'adventure': '冒险',
    'disaster': '灾难',
    'biography': '传记',
    'history': '历史',
    'wuxia': '武侠',
    'costume': '古装',
    'music': '音乐',
    'musical': '歌舞',
  };
  if (englishAliases[lowerValue] case final normalized?) return normalized;
  if (value.endsWith('动漫')) return '动画';
  return aliases[value] ?? value;
}

String _text(Object? value) => value?.toString().trim() ?? '';

String _firstNonEmptyText(Iterable<Object?> values) {
  for (final value in values) {
    final text = _text(value);
    if (text.isNotEmpty) return text;
  }
  return '';
}

String? _validHttpUrl(String raw) {
  final uri = Uri.tryParse(raw);
  if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
    return null;
  }
  if (uri.host.isEmpty) {
    return null;
  }
  return uri.toString();
}

String _stripMarkup(String value) {
  return value
      .replaceAll(RegExp(r'<[^>]*>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String encodeMediaList(List<MediaItem> items) =>
    jsonEncode(items.map((item) => item.toJson()).toList());
