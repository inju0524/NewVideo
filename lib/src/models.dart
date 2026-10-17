import 'dart:convert';

enum SourceKind { cms, m3u, jellyfin, emby }

enum SourceHealth { pending, available, error, unsupported }

/// The broad catalog type used for surfaces that need consistent poster
/// quality. Genre labels remain separate because a movie or series can have
/// several genres.
enum MediaContentType { unknown, movie, series, other }

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
    id: 'public-ffzy-cj',
    name: '非凡采集',
    endpoint: 'https://cj.ffzyapi.com/api.php/provide/vod/',
    enabled: false,
    statusMessage: '内置源，手动启用',
  ),
  MediaSource(
    id: 'public-ffzy-backup',
    name: '非凡备用',
    endpoint: 'https://ffzy1.tv/api.php/provide/vod',
    enabled: false,
    statusMessage: '内置源，手动启用',
  ),
  MediaSource(
    id: 'preset-lzi',
    name: '量子影视',
    endpoint: 'https://cj.lziapi.com/api.php/provide/vod/',
    statusMessage: '预置源',
  ),
  MediaSource(
    id: 'public-ruyi',
    name: '如意资源',
    endpoint: 'https://cj.rycjapi.com/api.php/provide/vod',
    enabled: false,
    statusMessage: '内置源，手动启用',
  ),
  MediaSource(
    id: 'public-360zy',
    name: '360点播',
    endpoint: 'https://360zy.com/api.php/provide/vod/',
    enabled: false,
    statusMessage: '内置源，手动启用',
  ),
  MediaSource(
    id: 'public-apibdzy',
    name: '百度资源',
    endpoint: 'https://api.apibdzy.com/api.php/provide/vod/',
    enabled: false,
    statusMessage: '内置源，手动启用',
  ),
  MediaSource(
    id: 'public-guangsu',
    name: '光速资源',
    endpoint: 'https://api.guangsuapi.com/api.php/provide/vod/',
    enabled: false,
    statusMessage: '内置源，手动启用',
  ),
  MediaSource(
    id: 'public-maoyan',
    name: '猫眼资源',
    endpoint: 'https://api.maoyanapi.top/api.php/provide/vod/at/json',
    enabled: false,
    statusMessage: '内置源，手动启用',
  ),
  MediaSource(
    id: 'public-uku88',
    name: 'U酷资源',
    endpoint: 'https://api.ukuapi88.com/api.php/provide/vod/',
    enabled: false,
    statusMessage: '内置源，手动启用',
  ),
  MediaSource(
    id: 'public-wsyzy',
    name: 'Wsy资源',
    endpoint: 'https://api.wsyzy.net/api.php/provide/vod',
    enabled: false,
    statusMessage: '内置源，手动启用',
  ),
  MediaSource(
    id: 'public-xinlang',
    name: '新浪资源',
    endpoint: 'https://api.xinlangapi.com/xinlangapi.php/provide/vod/at/xml',
    enabled: false,
    statusMessage: '内置源，手动启用',
  ),
  MediaSource(
    id: 'public-zuid',
    name: '最大资源',
    endpoint: 'https://api.zuidapi.com/api.php/provide/vod/?ac=list',
    enabled: false,
    statusMessage: '内置源，手动启用',
  ),
  MediaSource(
    id: 'public-dbzy',
    name: '豆瓣资源',
    endpoint: 'https://caiji.dbzy5.com/api.php/provide/vod',
    enabled: false,
    statusMessage: '内置源，手动启用',
  ),
  MediaSource(
    id: 'public-dytt',
    name: '电影天堂',
    endpoint: 'https://caiji.dyttzyapi.com/api.php/provide/vod',
    enabled: false,
    statusMessage: '内置源，手动启用',
  ),
  MediaSource(
    id: 'public-maotai',
    name: '茅台资源',
    endpoint: 'https://caiji.maotaizy.cc/api.php/provide/vod',
    enabled: false,
    statusMessage: '内置源，手动启用',
  ),
  MediaSource(
    id: 'public-hhzy',
    name: '火焰狐妖',
    endpoint: 'https://hhzyapi.com/api.php/provide/vod/?ac=list',
    enabled: false,
    statusMessage: '内置源，手动启用',
  ),
  MediaSource(
    id: 'public-jszy',
    name: '极速资源',
    endpoint: 'https://jszyapi.com/api.php/provide/vod/',
    enabled: false,
    statusMessage: '内置源，手动启用',
  ),
  MediaSource(
    id: 'public-jyzy',
    name: '金鹰资源',
    endpoint: 'https://jyzyapi.com/provide/vod/from/jinyingm3u8/at/json',
    enabled: false,
    statusMessage: '内置源，手动启用',
  ),
  MediaSource(
    id: 'public-p2100',
    name: '飘零资源',
    endpoint: 'https://p2100.net/api.php/provide/vod/',
    enabled: false,
    statusMessage: '内置源，手动启用',
  ),
  MediaSource(
    id: 'public-suoni',
    name: '索尼资源',
    endpoint: 'https://suoniapi.com/api.php/provide/vod/',
    enabled: false,
    statusMessage: '内置源，手动启用',
  ),
  MediaSource(
    id: 'public-huya',
    name: '虎牙采集',
    endpoint: 'https://www.huyaapi.com/api.php/provide/vod/',
    enabled: false,
    statusMessage: '内置源，手动启用',
  ),
  MediaSource(
    id: 'public-mdzy',
    name: '魔都资源',
    endpoint: 'https://www.mdzyapi.com/api.php/provide/vod',
    enabled: false,
    statusMessage: '内置源，手动启用',
  ),
  MediaSource(
    id: 'public-hongniu',
    name: '红牛资源',
    endpoint: 'https://www.hongniuzy2.com/api.php/provide/vod/',
    enabled: false,
    statusMessage: '内置源，手动启用',
  ),
  MediaSource(
    id: 'public-aosika',
    name: '奥斯卡资源',
    endpoint: 'https://aosikazy.com/api.php/provide/vod',
    enabled: false,
    statusMessage: '内置源，手动启用',
  ),
  MediaSource(
    id: 'public-aidan',
    name: '艾旦影视',
    endpoint: 'https://lovedan.net/api.php/provide/vod',
    enabled: false,
    statusMessage: '内置源，手动启用',
  ),
  MediaSource(
    id: 'public-senlin',
    name: '森林资源',
    endpoint: 'https://slapibf.com/api.php/provide/vod',
    enabled: false,
    statusMessage: '内置源，手动启用',
  ),
  MediaSource(
    id: 'public-shandian',
    name: '闪电资源',
    endpoint: 'https://sdzyapi.com/api.php/provide/vod',
    enabled: false,
    statusMessage: '内置源，手动启用',
  ),
  MediaSource(
    id: 'public-niuniu',
    name: '牛牛资源',
    endpoint: 'https://api.niuniuzy.me/api.php/provide/vod',
    enabled: false,
    statusMessage: '内置源，手动启用',
  ),
  MediaSource(
    id: 'public-yaya',
    name: '丫丫资源',
    endpoint: 'https://cj.yayazy.net/api.php/provide/vod',
    enabled: false,
    statusMessage: '内置源，手动启用',
  ),
  MediaSource(
    id: 'public-subocaiji',
    name: '速博资源',
    endpoint: 'https://subocaiji.com/api.php/provide/vod',
    enabled: false,
    statusMessage: '内置源，手动启用',
  ),
  MediaSource(
    id: 'public-wujin',
    name: '无尽资源',
    endpoint: 'https://api.wujinapi.com/api.php/provide/vod',
    enabled: false,
    statusMessage: '内置源，手动启用',
  ),
  MediaSource(
    id: 'public-yinghua',
    name: '樱花资源',
    endpoint: 'https://m3u8.apiyhzy.com/api.php/provide/vod',
    enabled: false,
    statusMessage: '内置源，手动启用',
  ),
  MediaSource(
    id: 'public-ikun',
    name: '爱坤资源',
    endpoint: 'https://ikunzyapi.com/api.php/provide/vod',
    enabled: false,
    statusMessage: '内置源，手动启用',
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
    this.contentType = MediaContentType.unknown,
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
  final MediaContentType contentType;
  final bool isDemo;

  bool get isMovieOrSeries =>
      contentType == MediaContentType.movie ||
      contentType == MediaContentType.series;

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
    MediaContentType? contentType,
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
      contentType: contentType ?? this.contentType,
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
    'contentType': contentType.name,
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
    final contentType = parseMediaContentType(
      json['contentType'] ?? json['mediaType'] ?? json['type'],
      remarks: json['remarks'] as String? ?? '',
    );
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
      contentType: contentType,
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
    final contentType = parseMediaContentType([
      json['type_name'],
      json['vod_type_name'],
      json['vod_type'],
      json['media_type'],
      json['type'],
    ], remarks: _text(json['vod_remarks'] ?? json['remarks']));
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
      contentType: contentType,
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

/// Converts source-specific broad type labels to the types used by the home
/// recommendation surface. Unknown labels stay unknown so a source cannot
/// accidentally put a low-confidence poster into today's recommendations.
MediaContentType parseMediaContentType(Object? raw, {String remarks = ''}) {
  if (raw is MediaContentType) return raw;
  final values = raw is Iterable ? raw : [raw];
  for (final value in values) {
    final labels = _text(value).split(RegExp(r'[,，/|、>]+'));
    for (final label in labels) {
      final parsed = _parseMediaContentTypeLabel(label);
      if (parsed != MediaContentType.unknown) return parsed;
    }
  }
  return _parseMediaContentTypeLabel(remarks);
}

MediaContentType _parseMediaContentTypeLabel(String raw) {
  final value = raw.trim().toLowerCase();
  if (value.isEmpty) return MediaContentType.unknown;
  if ({
    'movie',
    'film',
    'feature film',
    '电影',
    '电影片',
    '剧情片',
    '喜剧片',
    '爱情片',
    '动作片',
    '科幻片',
    '惊悚片',
    '悬疑片',
    '恐怖片',
    '犯罪片',
    '伦理片',
    '家庭片',
    '奇幻片',
    '战争片',
    '青春片',
    '冒险片',
    '灾难片',
    '传记片',
    '历史片',
    '武侠片',
    '古装片',
    '音乐片',
    '歌舞片',
  }.contains(value)) {
    return MediaContentType.movie;
  }
  if ({
    'series',
    'tv',
    'tv show',
    'tvshow',
    'tv series',
    'television series',
    '电视剧',
    '连续剧',
    '剧集',
  }.contains(value)) {
    return MediaContentType.series;
  }
  if ({
    '综艺',
    '综艺片',
    '动漫',
    '动画',
    '动画片',
    '纪录',
    '纪录片',
    '短剧',
    '体育',
    '资讯',
    '少儿',
    'variety',
    'animation',
    'anime',
    'documentary',
    'short drama',
    'other',
  }.contains(value)) {
    return MediaContentType.other;
  }
  if (value.endsWith('剧') &&
      (value.contains('国产') ||
          value.contains('大陆') ||
          value.contains('内地') ||
          value.contains('港台') ||
          value.contains('香港') ||
          value.contains('台湾') ||
          value.contains('日韩') ||
          value.contains('韩国') ||
          value.contains('日本') ||
          value.contains('泰国') ||
          value.contains('欧美') ||
          value.contains('海外') ||
          value.contains('网'))) {
    return MediaContentType.series;
  }
  return MediaContentType.unknown;
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
