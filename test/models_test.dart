import 'package:flutter_test/flutter_test.dart';
import 'package:zhuying/src/models.dart';

void main() {
  test('includes verified public CMS sources as opt-in defaults', () {
    final publicSources = defaultSources
        .where((source) => source.id.startsWith('public-'))
        .toList();

    expect(publicSources, hasLength(7));
    expect(publicSources.every((source) => !source.enabled), isTrue);
    expect(
      publicSources.every(
        (source) => Uri.parse(source.endpoint).scheme == 'https',
      ),
      isTrue,
    );
    expect(
      publicSources.map((source) => source.name),
      containsAll(['360点播', '百度资源', '光速资源', '樱花资源', '无尽资源']),
    );
  });

  test('CMS playback prefers direct media URLs over share pages', () {
    final source = MediaSource(
      id: 'cms-playback-test',
      name: 'CMS',
      endpoint: 'https://media.example/api.php/provide/vod',
    );

    final item = MediaItem.fromCms({
      'vod_id': '1',
      'vod_name': 'Movie',
      'vod_play_url':
          '第01集\$https://vip.example/share/episode-1'
          '\$\$\$'
          '第01集\$https://cdn.example/video/episode-1/index.m3u8'
          '#第02集\$https://cdn.example/video/episode-2.mp4',
    }, source: source);

    expect(item.episodes.map((episode) => episode.url), [
      'https://cdn.example/video/episode-1/index.m3u8',
      'https://cdn.example/video/episode-2.mp4',
    ]);
  });

  test('persists episode identity for resume playback', () {
    final item = MediaItem(
      id: 'server-demo:movie',
      title: 'Demo',
      sourceId: 'server-demo',
      sourceName: 'Jellyfin',
      progressSeconds: 123,
      durationSeconds: 600,
      progressEpisodeId: 'episode-2',
      progressEpisodeTitle: 'S1 E2 · Second light',
    );

    final restored = MediaItem.fromJson(item.toJson());

    expect(restored.progressSeconds, 123);
    expect(restored.durationSeconds, 600);
    expect(restored.progressEpisodeId, 'episode-2');
    expect(restored.progressEpisodeTitle, 'S1 E2 · Second light');
  });

  test('normalizes and preserves all CMS genre labels', () {
    final source = MediaSource(
      id: 'cms-genre-test',
      name: 'CMS',
      endpoint: 'https://media.example/api.php/provide/vod',
    );

    final item = MediaItem.fromCms({
      'vod_id': '2',
      'vod_name': 'Multi Genre Movie',
      'type_name': '剧情片,爱情,悬疑,日韩动漫',
    }, source: source);

    expect(item.genre, '剧情');
    expect(item.genres, ['剧情', '爱情', '悬疑', '动画']);
  });

  test('normalizes common English CMS genres to Chinese filter labels', () {
    expect(normalizeGenres('Comedy,Romance,Action,Science Fiction,Horror'), [
      '喜剧',
      '爱情',
      '动作',
      '科幻',
      '恐怖',
    ]);
  });

  test('classifies only movies and series as recommendation content', () {
    final source = MediaSource(
      id: 'cms-content-type-test',
      name: 'CMS',
      endpoint: 'https://media.example/api.php/provide/vod',
    );

    final movie = MediaItem.fromCms({
      'vod_id': 'movie',
      'vod_name': 'Movie',
      'type_name': '电影片',
    }, source: source);
    final series = MediaItem.fromCms({
      'vod_id': 'series',
      'vod_name': 'Series',
      'type_name': '连续剧',
    }, source: source);
    final variety = MediaItem.fromCms({
      'vod_id': 'variety',
      'vod_name': 'Variety',
      'type_name': '综艺',
    }, source: source);

    expect(movie.contentType, MediaContentType.movie);
    expect(series.contentType, MediaContentType.series);
    expect(variety.contentType, MediaContentType.other);
    expect(movie.isMovieOrSeries, isTrue);
    expect(series.isMovieOrSeries, isTrue);
    expect(variety.isMovieOrSeries, isFalse);
    expect(
      MediaItem.fromJson(movie.toJson()).contentType,
      MediaContentType.movie,
    );
  });

  test('prefers CMS genre metadata over broad source type names', () {
    final item = MediaItem.fromCms(
      {
        'vod_id': 'genre-priority',
        'vod_name': 'Night Watch',
        'type_name': '电影片',
        'vod_class': '恐怖片,悬疑',
      },
      source: MediaSource(
        id: 'cms-genre-priority',
        name: 'CMS',
        endpoint: 'https://media.example/api.php/provide/vod',
      ),
    );

    expect(item.genreLabels, ['恐怖', '悬疑']);
  });

  test('reads CMS ratings and preserves them in local history JSON', () {
    final item = MediaItem.fromCms(
      {
        'vod_id': '3',
        'vod_name': 'Rated movie',
        'vod_score': '8.6',
        'vod_play_url': '正片\$https://media.example/movie.mp4',
      },
      source: MediaSource(
        id: 'cms-rating-test',
        name: 'CMS',
        endpoint: 'https://media.example/api.php/provide/vod',
      ),
    );

    expect(item.rating, '8.6');
    expect(MediaItem.fromJson(item.toJson()).rating, '8.6');
  });

  test('reads and persists only an explicit CMS thumbnail URL', () {
    final source = MediaSource(
      id: 'cms-thumbnail-test',
      name: 'CMS',
      endpoint: 'https://media.example/api.php/provide/vod',
    );
    final item = MediaItem.fromCms({
      'vod_id': 'thumb-1',
      'vod_name': 'Thumbnail movie',
      'vod_pic': 'https://images.example/poster.jpg',
      'vod_pic_thumb': 'https://images.example/poster-small.jpg',
    }, source: source);
    final restored = MediaItem.fromJson(item.toJson());

    expect(item.posterUrl, 'https://images.example/poster.jpg');
    expect(item.thumbnailUrl, 'https://images.example/poster-small.jpg');
    expect(restored.thumbnailUrl, item.thumbnailUrl);

    final noThumbnail = MediaItem.fromCms({
      'vod_id': 'no-thumb',
      'vod_name': 'Full-size only',
      'vod_pic': 'https://images.example/full.jpg',
    }, source: source);
    expect(noThumbnail.thumbnailUrl, isEmpty);
  });

  test('reads legacy media JSON without a genres field', () {
    final item = MediaItem.fromJson({
      'id': 'legacy-1',
      'title': 'Legacy Movie',
      'sourceId': 'source-1',
      'sourceName': '旧片源',
      'genre': '恐怖片',
    });

    expect(item.genre, '恐怖');
    expect(item.genreLabels, ['恐怖']);
    expect(item.toJson()['genres'], ['恐怖']);
  });
}
