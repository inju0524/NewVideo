import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import '../app_store.dart';
import '../models.dart';
import 'player_fullscreen_stub.dart'
    if (dart.library.html) 'player_fullscreen_web.dart';
import 'widgets.dart';

PageRouteBuilder<void> _mediaPageRoute(
  Widget page, {
  required BuildContext context,
  required bool reduceMotion,
}) {
  final duration = motionDuration(
    context,
    reduceMotion,
    const Duration(milliseconds: 160),
  );
  return PageRouteBuilder<void>(
    transitionDuration: duration,
    reverseTransitionDuration: motionDuration(
      context,
      reduceMotion,
      const Duration(milliseconds: 140),
    ),
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(opacity: curved, child: child);
    },
  );
}

class MediaDetailsPage extends StatefulWidget {
  const MediaDetailsPage({required this.store, required this.item, super.key});

  final AppStore store;
  final MediaItem item;

  @override
  State<MediaDetailsPage> createState() => _MediaDetailsPageState();
}

class _MediaDetailsPageState extends State<MediaDetailsPage> {
  late MediaItem _item;
  bool _loading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final details = await widget.store.loadDetails(widget.item);
      if (!mounted) return;
      setState(() {
        _item = details;
        _loading = false;
      });
    } on SourceRequestException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = error.message;
      });
    } on Object {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = '详情加载失败，请重试';
      });
    }
  }

  MediaEpisode? get _resumeEpisode {
    if (_item.progressSeconds <= 0 || _item.episodes.isEmpty) return null;
    return _item.episodes.firstWhere(
      (entry) => entry.progressKey == _item.progressEpisodeId,
      orElse: () => _item.episodes.first,
    );
  }

  Future<void> _play(MediaEpisode episode, {bool resume = true}) async {
    final playItem = resume
        ? _item
        : _item.copyWith(
            durationSeconds: 0,
            progressSeconds: 0,
            progressEpisodeId: '',
            progressEpisodeTitle: '',
          );
    await Navigator.of(context).push(
      _mediaPageRoute(
        PlayerPage(store: widget.store, item: playItem, episode: episode),
        context: context,
        reduceMotion: widget.store.reduceMotion,
      ),
    );
    if (!mounted) return;
    final saved = widget.store.history.where((entry) => entry.id == _item.id);
    setState(() {
      _item = _item.copyWith(
        progressSeconds: saved.isEmpty ? 0 : saved.first.progressSeconds,
        durationSeconds: saved.isEmpty ? 0 : saved.first.durationSeconds,
        progressEpisodeId: saved.isEmpty ? '' : saved.first.progressEpisodeId,
        progressEpisodeTitle: saved.isEmpty
            ? ''
            : saved.first.progressEpisodeTitle,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final isFavorite = widget.store.favorites.contains(_item.id);
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 760;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 56,
              child: Row(
                children: [
                  IconButton(
                    tooltip: '返回',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: isFavorite ? '取消收藏' : '收藏',
                    onPressed: () => widget.store.toggleFavorite(_item),
                    icon: AnimatedBuilder(
                      animation: widget.store,
                      builder: (context, _) {
                        final favorite = widget.store.favorites.contains(
                          _item.id,
                        );
                        return Icon(
                          favorite ? Icons.bookmark : Icons.bookmark_border,
                          color: favorite
                              ? ZhuyingColors.amber
                              : ZhuyingColors.text,
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DetailHero(
                      item: _item,
                      wide: wide,
                      reduceMotion: widget.store.reduceMotion,
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        wide ? 44 : 20,
                        24,
                        wide ? 44 : 20,
                        34,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  _item.title,
                                  style: TextStyle(
                                    color: ZhuyingColors.text,
                                    fontSize: wide ? 28 : 24,
                                    height: 1.15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (_loading)
                                const Padding(
                                  padding: EdgeInsets.only(top: 8, left: 10),
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 9),
                          Text(
                            [
                              _item.year,
                              _item.region,
                              _item.genre,
                              _item.remarks,
                              _item.sourceName,
                            ].where((value) => value.isNotEmpty).join('  ·  '),
                            style: const TextStyle(
                              color: ZhuyingColors.muted,
                              fontSize: 12,
                            ),
                          ),
                          if (_item.description.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 820),
                              child: Text(
                                _item.description,
                                style: const TextStyle(
                                  color: Color(0xFFD2D0C9),
                                  fontSize: 13,
                                  height: 1.65,
                                ),
                              ),
                            ),
                          ],
                          if (_item.episodes.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                FilledButton.icon(
                                  onPressed: () {
                                    final episode = _resumeEpisode;
                                    _play(
                                      episode ?? _item.episodes.first,
                                      resume: episode != null,
                                    );
                                  },
                                  icon: const Icon(Icons.play_arrow_rounded),
                                  label: Text(
                                    _resumeEpisode == null
                                        ? '立即播放'
                                        : '继续播放  ${_formatTime(Duration(seconds: _item.progressSeconds))}',
                                  ),
                                ),
                                if (_resumeEpisode != null)
                                  OutlinedButton.icon(
                                    onPressed: () => _play(
                                      _item.episodes.first,
                                      resume: false,
                                    ),
                                    icon: const Icon(Icons.replay_rounded),
                                    label: const Text('从头播放'),
                                  ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 23),
                          if (_item.episodes.isEmpty)
                            _UnavailableEpisodes(
                              isLoading: _loading,
                              onRetry: _loadDetails,
                              message: _errorMessage,
                            )
                          else ...[
                            SectionTitle(
                              title: '选集',
                              trailing: Text(
                                '${_item.episodes.length} 集',
                                style: const TextStyle(
                                  color: ZhuyingColors.muted,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            _EpisodeGrid(
                              episodes: _item.episodes,
                              onPlay: _play,
                            ),
                          ],
                        ],
                      ),
                    ),
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

class _DetailHero extends StatelessWidget {
  const _DetailHero({
    required this.item,
    required this.wide,
    required this.reduceMotion,
  });

  final MediaItem item;
  final bool wide;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final height = wide ? 315.0 : 240.0;
    return SizedBox(
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
              fallbackFontSize: 20,
              reduceMotion: reduceMotion,
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  ZhuyingColors.canvas.withValues(alpha: 0.02),
                  ZhuyingColors.canvas.withValues(alpha: 0.36),
                  ZhuyingColors.canvas,
                ],
                stops: const [0, 0.62, 1],
              ),
            ),
          ),
          Positioned(
            left: wide ? 44 : 20,
            right: wide ? 44 : 20,
            bottom: 20,
            child: Row(
              children: [
                const Icon(
                  Icons.wb_twilight_rounded,
                  color: ZhuyingColors.amber,
                  size: 16,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    item.isDemo ? '演示内容' : item.sourceName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ZhuyingColors.text,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EpisodeGrid extends StatelessWidget {
  const _EpisodeGrid({required this.episodes, required this.onPlay});

  final List<MediaEpisode> episodes;
  final ValueChanged<MediaEpisode> onPlay;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760
            ? 6
            : constraints.maxWidth >= 520
            ? 4
            : 3;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: episodes.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            mainAxisExtent: 44,
          ),
          itemBuilder: (context, index) {
            final episode = episodes[index];
            return OutlinedButton.icon(
              onPressed: () => onPlay(episode),
              icon: const Icon(Icons.play_arrow_rounded, size: 17),
              label: Text(
                episode.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: ZhuyingColors.text,
                side: const BorderSide(color: ZhuyingColors.line),
                padding: const EdgeInsets.symmetric(horizontal: 9),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _UnavailableEpisodes extends StatelessWidget {
  const _UnavailableEpisodes({
    required this.isLoading,
    required this.onRetry,
    this.message,
  });

  final bool isLoading;
  final VoidCallback onRetry;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      decoration: BoxDecoration(
        color: ZhuyingColors.surface,
        border: Border.all(color: ZhuyingColors.line),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: ZhuyingColors.amber),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message ?? (isLoading ? '正在加载选集' : '当前片源未提供可播放选集'),
              style: const TextStyle(color: ZhuyingColors.muted, fontSize: 12),
            ),
          ),
          TextButton.icon(
            onPressed: isLoading ? null : onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 17),
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }
}

class PlayerPage extends StatefulWidget {
  const PlayerPage({
    required this.store,
    required this.item,
    required this.episode,
    super.key,
  });

  final AppStore store;
  final MediaItem item;
  final MediaEpisode episode;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> with WidgetsBindingObserver {
  late MediaItem _playItem;
  late MediaEpisode _episode;
  final GlobalKey<_PlayerSurfaceState> _playerSurfaceKey =
      GlobalKey<_PlayerSurfaceState>();
  VideoPlayerController? _controller;
  StreamSubscription<bool>? _fullscreenSubscription;
  bool _initialized = false;
  bool _hasError = false;
  bool _switchingEpisode = false;
  bool _isFullscreen = false;
  bool _fullscreenTransitioning = false;
  bool _lockLandscapeForFullscreen = false;
  bool _restoreSensorAfterPortrait = false;
  bool? _pendingBrowserFullscreen;
  bool? _pendingSensorLandscape;
  bool _browserFullscreenActive = false;
  bool _browserFullscreenRequested = false;
  bool _descriptionExpanded = false;
  int _lastSavedSecond = -5;
  int _episodeIndex = 0;
  int _loadId = 0;
  bool _completionHandled = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _playItem = widget.item;
    _episode = widget.episode;
    _episodeIndex = _playItem.episodes.indexOf(widget.episode);
    if (_episodeIndex < 0) _episodeIndex = 0;
    _fullscreenSubscription = playerFullscreenChanges().listen(
      _handleBrowserFullscreenChange,
    );
    _createController();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _syncSensorOrientation(),
    );
  }

  @override
  void didChangeMetrics() => _syncSensorOrientation();

  void _syncSensorOrientation() {
    if (!mounted || kIsWeb || !_supportsSensorFullscreen) {
      return;
    }
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return;
    final size = views.first.physicalSize;
    if (size.isEmpty) return;
    final landscape = size.width > size.height;
    if (_restoreSensorAfterPortrait) {
      if (landscape) return;
      _restoreSensorAfterPortrait = false;
      unawaited(SystemChrome.setPreferredOrientations(const []));
    }
    if (_lockLandscapeForFullscreen && _isFullscreen) return;
    if (landscape == _isFullscreen) return;
    if (_fullscreenTransitioning) {
      _pendingSensorLandscape = landscape;
      return;
    }
    if (landscape) {
      unawaited(_enterFullscreen(lockLandscape: false));
    } else {
      unawaited(_exitFullscreen(forcePortrait: false));
    }
  }

  Future<void> _createController() async {
    final loadId = ++_loadId;
    final uri = Uri.tryParse(widget.store.playbackUrl(_episode.url));
    if (uri == null ||
        uri.host.isEmpty ||
        !{'http', 'https'}.contains(uri.scheme)) {
      if (mounted && loadId == _loadId) {
        setState(() {
          _hasError = true;
          _switchingEpisode = false;
          _errorMessage = '播放地址无效，请更换片源后重试';
        });
      }
      return;
    }
    try {
      final headers = await widget.store.requestHeaders(_playItem.sourceId);
      if (!mounted || loadId != _loadId) return;
      if (kIsWeb && headers.isNotEmpty) {
        throw const SourceRequestException(
          '浏览器预览无法携带视频认证请求头，请在 Android 或 iOS 客户端播放',
        );
      }
      final controller = VideoPlayerController.networkUrl(
        uri,
        httpHeaders: headers,
      );
      _controller = controller;
      await controller.initialize().timeout(const Duration(seconds: 20));
      if (!mounted || loadId != _loadId) return;
      final resumeKey = _playItem.progressEpisodeId;
      if (_playItem.progressSeconds > 0 &&
          (resumeKey == _episode.progressKey ||
              resumeKey.isEmpty && _episodeIndex == 0)) {
        await controller.seekTo(Duration(seconds: _playItem.progressSeconds));
      }
      if (!mounted || loadId != _loadId) return;
      _lastSavedSecond = controller.value.position.inSeconds;
      controller.addListener(_onVideoChanged);
      setState(() {
        _initialized = true;
        _switchingEpisode = false;
      });
      try {
        await controller.play();
      } on Object {
        // Browsers can block autoplay. The controls remain available for a
        // user-initiated play instead of treating that as a source failure.
        await controller.pause();
      }
    } on Object catch (error) {
      if (!mounted || loadId != _loadId) return;
      setState(() {
        _hasError = true;
        _switchingEpisode = false;
        _errorMessage = _playerErrorMessage(error);
      });
    }
  }

  void _onVideoChanged() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || !mounted) {
      return;
    }
    final value = controller.value;
    if (value.hasError && !_hasError) {
      setState(() {
        _hasError = true;
        _errorMessage = value.errorDescription ?? '播放失败，请重试';
      });
      return;
    }
    final second = value.position.inSeconds;
    if ((second - _lastSavedSecond).abs() >= 5 ||
        value.isCompleted && !_completionHandled) {
      _lastSavedSecond = second;
      widget.store.updateProgress(
        _playItem,
        second,
        value.duration.inSeconds,
        episode: _episode,
      );
    }
    if (value.isCompleted) _completionHandled = true;
    if (value.isCompleted &&
        widget.store.autoplayNext &&
        !_switchingEpisode &&
        _episodeIndex + 1 < _playItem.episodes.length) {
      _switchEpisode(_episodeIndex + 1);
    }
  }

  Future<void> _switchEpisode(int index) async {
    if (_switchingEpisode || index < 0 || index >= _playItem.episodes.length) {
      return;
    }
    final previous = _controller;
    _saveProgress();
    ++_loadId;
    _controller = null;
    setState(() {
      _switchingEpisode = true;
      _initialized = false;
      _hasError = false;
      _errorMessage = null;
      _episodeIndex = index;
      _episode = _playItem.episodes[index];
    });
    previous?.removeListener(_onVideoChanged);
    await previous?.dispose();
    if (!mounted) return;
    _lastSavedSecond = -5;
    _completionHandled = false;
    await _createController();
  }

  void _saveProgress() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    unawaited(
      widget.store.updateProgress(
        _playItem,
        controller.value.position.inSeconds,
        controller.value.duration.inSeconds,
        episode: _episode,
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _saveProgress();
      unawaited(_controller?.pause());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _fullscreenSubscription?.cancel();
    ++_loadId;
    if (_isFullscreen) {
      unawaited(exitPlayerFullscreen());
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
      unawaited(SystemChrome.setPreferredOrientations(const []));
    }
    _saveProgress();
    _controller?.removeListener(_onVideoChanged);
    unawaited(_controller?.dispose());
    super.dispose();
  }

  Future<void> _toggleFullscreen() async {
    if (_isFullscreen) {
      await _exitFullscreen();
      return;
    }

    await _enterFullscreen(lockLandscape: !kIsWeb);
  }

  Future<void> _enterFullscreen({required bool lockLandscape}) async {
    if (_isFullscreen || _fullscreenTransitioning) return;
    _fullscreenTransitioning = true;
    _lockLandscapeForFullscreen = lockLandscape;
    if (mounted) setState(() => _isFullscreen = true);
    try {
      if (kIsWeb) {
        _browserFullscreenRequested = true;
        // The browser may leave requestFullscreen pending in an embedded
        // preview even though the user gesture was accepted. The app-level
        // focus layout must not wait for that optional enhancement.
        unawaited(
          requestPlayerFullscreen().then((entered) {
            if (mounted) _browserFullscreenActive = entered;
          }),
        );
      } else {
        if (lockLandscape) {
          await SystemChrome.setPreferredOrientations(const [
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]);
        }
        await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
    } on Object catch (error) {
      debugPrint('Could not configure fullscreen mode: $error');
      _lockLandscapeForFullscreen = false;
      _browserFullscreenRequested = false;
      _browserFullscreenActive = false;
    } finally {
      _browserFullscreenRequested = false;
      _finishFullscreenTransition();
    }
  }

  @override
  Future<bool> didPopRoute() async {
    if (_isFullscreen) {
      await _exitFullscreen();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _handleBack();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: PopScope(
        canPop: !_isFullscreen,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _isFullscreen) unawaited(_exitFullscreen());
        },
        child: Scaffold(
          backgroundColor: _isFullscreen ? Colors.black : ZhuyingColors.canvas,
          body: _isFullscreen
              ? KeyedSubtree(
                  key: const ValueKey('player-focus-layout'),
                  child: _buildFocusLayout(),
                )
              : SafeArea(top: true, bottom: false, child: _buildInlineLayout()),
        ),
      ),
    );
  }

  Widget _buildInlineLayout() {
    return Column(
      children: [
        _buildVideoFrame(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 36),
            child: AnimatedBuilder(
              animation: widget.store,
              builder: (context, _) => _buildPlayerContent(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFocusLayout() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final aspectRatio = _initialized && !_hasError
            ? _controller!.value.aspectRatio
            : 16 / 9;
        return SizedBox.expand(
          child: Center(
            child: AspectRatio(
              aspectRatio: aspectRatio,
              child: _buildVideoSurface(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildVideoFrame() {
    return SizedBox(
      width: double.infinity,
      child: AspectRatio(aspectRatio: 16 / 9, child: _buildVideoSurface()),
    );
  }

  Widget _buildVideoSurface() {
    final showVideo = _initialized && _controller != null && !_hasError;
    return Stack(
      fit: StackFit.expand,
      children: [
        Hero(
          tag: _playItem.id,
          child: MediaPoster(
            url: _playItem.posterUrl,
            thumbnailUrl: _playItem.thumbnailUrl,
            title: '',
            headers: _playItem.posterHeaders,
            fallbackFontSize: 20,
            reduceMotion: widget.store.reduceMotion,
          ),
        ),
        if (showVideo)
          Positioned.fill(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: motionDuration(
                context,
                widget.store.reduceMotion,
                const Duration(milliseconds: 240),
              ),
              curve: Curves.easeOutCubic,
              builder: (context, opacity, child) =>
                  Opacity(opacity: opacity, child: child),
              child: _PlayerSurface(
                key: _playerSurfaceKey,
                controller: _controller!,
                itemTitle: _playItem.title,
                episodeTitle: _episode.title,
                episodes: _playItem.episodes,
                episodeIndex: _episodeIndex,
                onBack: _handleBack,
                onPrevious: _episodeIndex > 0
                    ? () => _switchEpisode(_episodeIndex - 1)
                    : null,
                onNext: _episodeIndex + 1 < _playItem.episodes.length
                    ? () => _switchEpisode(_episodeIndex + 1)
                    : null,
                onSelectEpisode: _switchEpisode,
                onFullscreen: _toggleFullscreen,
                isFullscreen: _isFullscreen,
              ),
            ),
          )
        else
          Positioned.fill(
            child: _PlayerStatusSurface(
              title: _playItem.title,
              episodeTitle: _episode.title,
              onBack: _handleBack,
              child: _hasError
                  ? _PlayerError(onRetry: _retry, message: _errorMessage)
                  : _PlayerLoading(
                      message: _switchingEpisode ? '正在切换选集' : '正在连接片源',
                    ),
            ),
          ),
      ],
    );
  }

  Widget _buildPlayerContent() {
    final related = _relatedItems;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PlayerInfo(
          item: _playItem,
          episode: _episode,
          expanded: _descriptionExpanded,
          onToggleDescription: _playItem.description.isEmpty
              ? null
              : () => setState(
                  () => _descriptionExpanded = !_descriptionExpanded,
                ),
        ),
        const SizedBox(height: 18),
        _PlayerActions(
          isFavorite: widget.store.favorites.contains(_playItem.id),
          isFollowing: widget.store.follows.contains(_playItem.id),
          onFavorite: () => widget.store.toggleFavorite(_playItem),
          onFollow: () => widget.store.toggleFollow(_playItem),
          onSource: _showSourcePicker,
          onDownload: _showDownloadMessage,
        ),
        const SizedBox(height: 24),
        _PlayerEpisodeSection(
          episodes: _playItem.episodes,
          currentIndex: _episodeIndex,
          onSelect: _switchEpisode,
          onShowAll: _showEpisodeSheet,
        ),
        const SizedBox(height: 28),
        if (related.isNotEmpty) ...[
          const SectionTitle(title: '相关推荐'),
          const SizedBox(height: 14),
          SizedBox(
            height: 226,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: related.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final item = related[index];
                return _RelatedMediaTile(
                  item: item,
                  onTap: () => _openRelated(item),
                  reduceMotion: widget.store.reduceMotion,
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  List<MediaItem> get _relatedItems {
    final genres = _playItem.genreLabels.toSet();
    return widget.store.allMedia
        .where(
          (item) =>
              item.id != _playItem.id &&
              (genres.isEmpty || item.genreLabels.any(genres.contains)),
        )
        .take(8)
        .toList();
  }

  void _handleBack() {
    if (_isFullscreen) {
      unawaited(_exitFullscreen());
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _handleBrowserFullscreenChange(bool fullscreen) async {
    if (!mounted) return;
    if (_fullscreenTransitioning) {
      _pendingBrowserFullscreen = fullscreen;
      return;
    }
    if (fullscreen) {
      if (_browserFullscreenRequested) {
        _browserFullscreenActive = true;
      }
      return;
    }
    // A rejected Fullscreen API request can still produce a stale false event.
    // Only a confirmed browser fullscreen session is allowed to leave the
    // app-level focus layout.
    if (_browserFullscreenActive && _isFullscreen) {
      _browserFullscreenActive = false;
      await _exitFullscreen(browserAlreadyExited: true);
    }
  }

  void _finishFullscreenTransition() {
    _fullscreenTransitioning = false;
    final pending = _pendingBrowserFullscreen;
    _pendingBrowserFullscreen = null;
    if (pending != null) {
      unawaited(_handleBrowserFullscreenChange(pending));
    }
    if (_pendingSensorLandscape != null) {
      _pendingSensorLandscape = null;
      _syncSensorOrientation();
    }
  }

  Future<void> _exitFullscreen({
    bool browserAlreadyExited = false,
    bool forcePortrait = true,
  }) async {
    if (!_isFullscreen || _fullscreenTransitioning) return;
    _fullscreenTransitioning = true;
    _lockLandscapeForFullscreen = false;
    if (mounted) setState(() => _isFullscreen = false);
    try {
      if (!browserAlreadyExited) await exitPlayerFullscreen();
      _browserFullscreenRequested = false;
      _browserFullscreenActive = false;
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      if (forcePortrait && !kIsWeb && _supportsSensorFullscreen) {
        _restoreSensorAfterPortrait = true;
        await SystemChrome.setPreferredOrientations(const [
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
      } else {
        _restoreSensorAfterPortrait = false;
        await SystemChrome.setPreferredOrientations(const []);
      }
    } on Object catch (error) {
      debugPrint('Could not restore fullscreen system UI: $error');
    } finally {
      _finishFullscreenTransition();
    }
  }

  bool get _supportsSensorFullscreen =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _showEpisodeSheet() async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: ZhuyingColors.surface,
      showDragHandle: true,
      builder: (context) => _EpisodeSheet(
        episodes: _playItem.episodes,
        currentIndex: _episodeIndex,
      ),
    );
    if (selected != null) await _switchEpisode(selected);
  }

  Future<void> _showSourcePicker() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('正在查找其他播放线路')));
    final candidates = await widget.store.findSourceVariants(_playItem);
    if (!mounted) return;
    messenger.hideCurrentSnackBar();
    if (candidates.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('当前影片没有其他可用线路')));
      return;
    }
    final selected = await showModalBottomSheet<MediaItem>(
      context: context,
      backgroundColor: ZhuyingColors.surface,
      showDragHandle: true,
      builder: (context) =>
          _SourceSheet(currentSource: _playItem.sourceName, items: candidates),
    );
    if (selected == null || !mounted) return;
    await _switchSource(selected);
  }

  Future<void> _switchSource(MediaItem sourceItem) async {
    try {
      final details = await widget.store.loadDetails(sourceItem);
      if (!mounted) return;
      if (details.episodes.isEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('该线路没有可播放选集')));
        return;
      }
      final nextIndex = details.episodes.indexWhere(
        (episode) => episode.title == _episode.title,
      );
      _saveProgress();
      _playItem = details;
      await _replaceController(nextIndex < 0 ? 0 : nextIndex);
    } on SourceRequestException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('线路切换失败，请稍后重试')));
      }
    }
  }

  Future<void> _replaceController(int index) async {
    if (index < 0 || index >= _playItem.episodes.length) return;
    final previous = _controller;
    ++_loadId;
    _controller = null;
    if (mounted) {
      setState(() {
        _switchingEpisode = true;
        _initialized = false;
        _hasError = false;
        _errorMessage = null;
        _episodeIndex = index;
        _episode = _playItem.episodes[index];
      });
    }
    previous?.removeListener(_onVideoChanged);
    await previous?.dispose();
    if (!mounted) return;
    _lastSavedSecond = -5;
    _completionHandled = false;
    await _createController();
  }

  void _showDownloadMessage() {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('远程片源暂不支持下载到本地')));
  }

  Future<void> _openRelated(MediaItem item) async {
    await Navigator.of(context).push(
      _mediaPageRoute(
        MediaDetailsPage(store: widget.store, item: item),
        context: context,
        reduceMotion: widget.store.reduceMotion,
      ),
    );
  }

  Future<void> _retry() async {
    if (_hasError) {
      ++_loadId;
      final previous = _controller;
      _controller = null;
      previous?.removeListener(_onVideoChanged);
      await previous?.dispose();
      if (!mounted) return;
      setState(() {
        _hasError = false;
        _initialized = false;
        _errorMessage = null;
        _completionHandled = false;
      });
      await _createController();
    }
  }

  String _playerErrorMessage(Object error) {
    if (error is SourceRequestException) return error.message;
    if (error is TimeoutException) return '播放连接超时，请重试';
    return '播放失败，检查片源或网络后重试';
  }
}

class _PlayerLoading extends StatelessWidget {
  const _PlayerLoading({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.38),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: ZhuyingColors.amber,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayerStatusSurface extends StatelessWidget {
  const _PlayerStatusSurface({
    required this.title,
    required this.episodeTitle,
    required this.onBack,
    required this.child,
  });

  final String title;
  final String episodeTitle;
  final VoidCallback onBack;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Align(
          alignment: Alignment.topCenter,
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 6, 14, 24),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black87, Colors.transparent],
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  tooltip: '返回',
                  onPressed: onBack,
                  color: Colors.white,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                Expanded(
                  child: Text(
                    '$title  ·  $episodeTitle',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PlayerSurface extends StatefulWidget {
  const _PlayerSurface({
    super.key,
    required this.controller,
    required this.itemTitle,
    required this.episodeTitle,
    required this.episodes,
    required this.episodeIndex,
    required this.onBack,
    required this.onPrevious,
    required this.onNext,
    required this.onSelectEpisode,
    required this.onFullscreen,
    required this.isFullscreen,
  });

  final VideoPlayerController controller;
  final String itemTitle;
  final String episodeTitle;
  final List<MediaEpisode> episodes;
  final int episodeIndex;
  final VoidCallback onBack;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final ValueChanged<int> onSelectEpisode;
  final VoidCallback onFullscreen;
  final bool isFullscreen;

  @override
  State<_PlayerSurface> createState() => _PlayerSurfaceState();
}

class _PlayerSurfaceState extends State<_PlayerSurface> {
  Timer? _hideTimer;
  bool _controlsVisible = true;
  double _lastVolume = 1;

  VideoPlayerController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(_onControllerChanged);
    _scheduleHide();
  }

  @override
  void didUpdateWidget(covariant _PlayerSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      controller.addListener(_onControllerChanged);
      _controlsVisible = true;
      _scheduleHide();
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    if (!controller.value.isPlaying) {
      _hideTimer?.cancel();
      _hideTimer = null;
    } else if (_controlsVisible && _hideTimer == null) {
      _scheduleHide();
    }
  }

  void _scheduleHide() {
    if (!_controlsVisible || !controller.value.isPlaying) return;
    if (_hideTimer != null) return;
    _hideTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() => _controlsVisible = false);
      _hideTimer = null;
    });
  }

  void _toggleControls() {
    if (_controlsVisible) {
      _hideTimer?.cancel();
      _hideTimer = null;
      setState(() => _controlsVisible = false);
    } else {
      setState(() => _controlsVisible = true);
      _hideTimer?.cancel();
      _hideTimer = null;
      _scheduleHide();
    }
  }

  void _showControls() {
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _hideTimer?.cancel();
    _hideTimer = null;
    _scheduleHide();
  }

  Future<void> _togglePlayback() async {
    _showControls();
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
  }

  Future<void> _seekBy(int seconds) async {
    final value = controller.value;
    final target = value.position + Duration(seconds: seconds);
    final clamped = target < Duration.zero
        ? Duration.zero
        : target > value.duration
        ? value.duration
        : target;
    _showControls();
    await controller.seekTo(clamped);
  }

  Future<void> _toggleMute() async {
    _showControls();
    if (controller.value.volume > 0) {
      _lastVolume = controller.value.volume;
      await controller.setVolume(0);
    } else {
      await controller.setVolume(_lastVolume <= 0 ? 1 : _lastVolume);
    }
  }

  Future<void> _setSpeed(double speed) async {
    try {
      await controller.setPlaybackSpeed(speed);
      _showControls();
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('当前设备不支持该播放速度')));
    }
  }

  Future<void> _showVolumeDialog() async {
    _showControls();
    var volume = controller.value.volume;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('音量'),
            content: Row(
              children: [
                Icon(
                  volume == 0
                      ? Icons.volume_off_rounded
                      : Icons.volume_up_rounded,
                ),
                Expanded(
                  child: Slider(
                    value: volume,
                    onChanged: (value) {
                      volume = value;
                      setDialogState(() {});
                      controller.setVolume(value);
                    },
                  ),
                ),
                Text('${(volume * 100).round()}%'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('完成'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showEpisodes() async {
    _showControls();
    final selected = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: ZhuyingColors.surface,
      showDragHandle: true,
      builder: (context) {
        final height = MediaQuery.sizeOf(context).height * 0.72;
        return SafeArea(
          child: SizedBox(
            height: height,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Text(
                    '选集  ${widget.episodes.length} 集',
                    style: const TextStyle(
                      color: ZhuyingColors.text,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    itemCount: widget.episodes.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 3),
                    itemBuilder: (context, index) {
                      final episode = widget.episodes[index];
                      final selected = index == widget.episodeIndex;
                      return ListTile(
                        dense: true,
                        selected: selected,
                        selectedTileColor: ZhuyingColors.amber.withValues(
                          alpha: 0.12,
                        ),
                        leading: Icon(
                          selected
                              ? Icons.play_circle_filled_rounded
                              : Icons.play_circle_outline_rounded,
                          color: selected
                              ? ZhuyingColors.amber
                              : ZhuyingColors.muted,
                        ),
                        title: Text(
                          episode.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => Navigator.of(context).pop(index),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (selected != null && selected != widget.episodeIndex) {
      widget.onSelectEpisode(selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) => LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          return Stack(
            fit: StackFit.expand,
            children: [
              VideoPlayer(controller),
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _toggleControls,
                  child: const SizedBox.expand(),
                ),
              ),
              AnimatedOpacity(
                opacity: _controlsVisible ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: Column(
                    children: [
                      SafeArea(
                        left: widget.isFullscreen,
                        top: widget.isFullscreen,
                        right: widget.isFullscreen,
                        bottom: false,
                        child: _topOverlay(),
                      ),
                      const Spacer(),
                      SafeArea(
                        left: widget.isFullscreen,
                        top: false,
                        right: widget.isFullscreen,
                        bottom: widget.isFullscreen,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              child: VideoProgressIndicator(
                                controller,
                                allowScrubbing: true,
                                colors: const VideoProgressColors(
                                  playedColor: ZhuyingColors.amber,
                                  bufferedColor: Colors.white38,
                                  backgroundColor: Colors.white12,
                                ),
                                padding: const EdgeInsets.only(
                                  top: 5,
                                  bottom: 5,
                                ),
                              ),
                            ),
                            compact ? _compactBar(value) : _wideBar(value),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (!value.isPlaying && !value.isBuffering)
                Center(
                  child: Material(
                    color: Colors.black.withValues(alpha: 0.55),
                    shape: const CircleBorder(),
                    child: IconButton(
                      tooltip: '播放',
                      onPressed: _togglePlayback,
                      color: ZhuyingColors.amber,
                      iconSize: 38,
                      icon: const Icon(Icons.play_arrow_rounded),
                    ),
                  ),
                ),
              if (value.isBuffering)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.62),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: ZhuyingColors.amber,
                                ),
                              ),
                              SizedBox(width: 9),
                              Text(
                                '正在缓冲',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _topOverlay() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          _controlIcon(
            tooltip: '返回',
            icon: Icons.arrow_back_rounded,
            onPressed: widget.onBack,
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Text(
              '${widget.itemTitle}  ·  ${widget.episodeTitle}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _wideBar(VideoPlayerValue value) {
    return Container(
      color: Colors.black.withValues(alpha: 0.82),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          _coreControls(),
          const SizedBox(width: 8),
          Expanded(child: _timeText(value)),
          PopupMenuButton<double>(
            tooltip: '播放速度',
            initialValue: value.playbackSpeed,
            onSelected: _setSpeed,
            itemBuilder: (context) => [
              for (final speed in _speeds)
                PopupMenuItem<double>(
                  value: speed,
                  child: Text(_speedLabel(speed)),
                ),
            ],
            child: _menuLabel(_speedLabel(value.playbackSpeed)),
          ),
          SizedBox(
            width: 108,
            child: Slider(
              value: value.volume,
              min: 0,
              max: 1,
              onChanged: (volume) => controller.setVolume(volume),
            ),
          ),
          _controlIcon(
            tooltip: value.volume == 0 ? '取消静音' : '静音',
            icon: value.volume == 0
                ? Icons.volume_off_rounded
                : Icons.volume_up_rounded,
            onPressed: _toggleMute,
          ),
          _controlIcon(
            tooltip: '选集',
            icon: Icons.playlist_play_rounded,
            onPressed: _showEpisodes,
          ),
          _controlIcon(
            tooltip: widget.isFullscreen ? '退出全屏' : '全屏',
            icon: widget.isFullscreen
                ? Icons.fullscreen_exit_rounded
                : Icons.fullscreen_rounded,
            onPressed: widget.onFullscreen,
          ),
        ],
      ),
    );
  }

  Widget _compactBar(VideoPlayerValue value) {
    return Container(
      color: Colors.black.withValues(alpha: 0.84),
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _compactCoreControls(),
          const SizedBox(width: 4),
          Expanded(child: _timeText(value)),
          _moreControls(value),
          _controlIcon(
            tooltip: widget.isFullscreen ? '退出全屏' : '全屏',
            icon: widget.isFullscreen
                ? Icons.fullscreen_exit_rounded
                : Icons.fullscreen_rounded,
            onPressed: widget.onFullscreen,
          ),
        ],
      ),
    );
  }

  Widget _compactCoreControls() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _controlIcon(
          tooltip: '快退 10 秒',
          icon: Icons.replay_10_rounded,
          onPressed: () => _seekBy(-10),
        ),
        _controlIcon(
          tooltip: controller.value.isPlaying ? '暂停' : '播放',
          icon: controller.value.isPlaying
              ? Icons.pause_rounded
              : Icons.play_arrow_rounded,
          color: ZhuyingColors.amber,
          onPressed: _togglePlayback,
        ),
        _controlIcon(
          tooltip: '快进 30 秒',
          icon: Icons.forward_30_rounded,
          onPressed: () => _seekBy(30),
        ),
      ],
    );
  }

  Widget _moreControls(VideoPlayerValue value) {
    return PopupMenuButton<String>(
      tooltip: '更多播放控制',
      padding: EdgeInsets.zero,
      icon: const Icon(Icons.more_horiz_rounded),
      onSelected: (action) {
        switch (action) {
          case 'previous':
            widget.onPrevious?.call();
          case 'next':
            widget.onNext?.call();
          case 'episodes':
            _showEpisodes();
          case 'volume':
            _showVolumeDialog();
          default:
            if (action.startsWith('speed:')) {
              final speed = double.tryParse(action.substring(6));
              if (speed != null) _setSpeed(speed);
            }
        }
      },
      itemBuilder: (context) => [
        if (widget.onPrevious != null)
          const PopupMenuItem<String>(value: 'previous', child: Text('上一集')),
        if (widget.onNext != null)
          const PopupMenuItem<String>(value: 'next', child: Text('下一集')),
        const PopupMenuItem<String>(value: 'episodes', child: Text('选集')),
        const PopupMenuItem<String>(value: 'volume', child: Text('音量')),
        const PopupMenuDivider(),
        for (final speed in _speeds)
          PopupMenuItem<String>(
            value: 'speed:$speed',
            child: Text('速度  ${_speedLabel(speed)}'),
          ),
      ],
    );
  }

  Widget _coreControls() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _controlIcon(
          tooltip: '上一集',
          icon: Icons.skip_previous_rounded,
          onPressed: widget.onPrevious,
        ),
        _controlIcon(
          tooltip: '快退 10 秒',
          icon: Icons.replay_10_rounded,
          onPressed: () => _seekBy(-10),
        ),
        _controlIcon(
          tooltip: controller.value.isPlaying ? '暂停' : '播放',
          icon: controller.value.isPlaying
              ? Icons.pause_rounded
              : Icons.play_arrow_rounded,
          color: ZhuyingColors.amber,
          onPressed: _togglePlayback,
        ),
        _controlIcon(
          tooltip: '快进 30 秒',
          icon: Icons.forward_30_rounded,
          onPressed: () => _seekBy(30),
        ),
        _controlIcon(
          tooltip: '下一集',
          icon: Icons.skip_next_rounded,
          onPressed: widget.onNext,
        ),
      ],
    );
  }

  Widget _timeText(VideoPlayerValue value) {
    return Text(
      '${_formatTime(value.position)} / ${_formatTime(value.duration)}',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.right,
      style: const TextStyle(color: Colors.white70, fontSize: 11),
    );
  }

  Widget _menuLabel(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        label,
        style: const TextStyle(color: Colors.white70, fontSize: 11),
      ),
    );
  }

  Widget _controlIcon({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
    Color? color,
  }) {
    return SizedBox(
      width: 40,
      height: 42,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        color: color ?? Colors.white,
        icon: Icon(icon, size: 20),
      ),
    );
  }
}

const _speeds = [0.75, 1.0, 1.25, 1.5, 2.0];

String _speedLabel(double speed) => speed == speed.roundToDouble()
    ? '${speed.toInt()}x'
    : '${speed.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '')}x';

class _PlayerInfo extends StatelessWidget {
  const _PlayerInfo({
    required this.item,
    required this.episode,
    required this.expanded,
    required this.onToggleDescription,
  });

  final MediaItem item;
  final MediaEpisode episode;
  final bool expanded;
  final VoidCallback? onToggleDescription;

  @override
  Widget build(BuildContext context) {
    final labels = [
      if (item.rating.isNotEmpty) '评分 ${item.rating}',
      if (item.year.isNotEmpty) item.year,
      ...item.genreLabels.take(3),
      if (item.region.isNotEmpty) item.region,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: ZhuyingColors.text,
            fontSize: 21,
            height: 1.18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          '正在播放  ·  ${episode.title}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: ZhuyingColors.amber,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (labels.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [for (final label in labels) _MetaPill(label: label)],
          ),
        ],
        if (item.description.isNotEmpty) ...[
          const SizedBox(height: 14),
          AnimatedCrossFade(
            firstChild: Text(
              item.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: ZhuyingColors.muted,
                fontSize: 13,
                height: 1.6,
              ),
            ),
            secondChild: Text(
              item.description,
              style: const TextStyle(
                color: ZhuyingColors.muted,
                fontSize: 13,
                height: 1.6,
              ),
            ),
            crossFadeState: expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 180),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onToggleDescription,
              icon: Icon(
                expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                size: 17,
              ),
              label: Text(expanded ? '收起简介' : '展开简介'),
              style: TextButton.styleFrom(
                foregroundColor: ZhuyingColors.muted,
                padding: const EdgeInsets.symmetric(horizontal: 0),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ZhuyingColors.surfaceRaised,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: ZhuyingColors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Text(
          label,
          style: const TextStyle(color: ZhuyingColors.muted, fontSize: 11),
        ),
      ),
    );
  }
}

class _PlayerActions extends StatelessWidget {
  const _PlayerActions({
    required this.isFavorite,
    required this.isFollowing,
    required this.onFavorite,
    required this.onFollow,
    required this.onSource,
    required this.onDownload,
  });

  final bool isFavorite;
  final bool isFollowing;
  final VoidCallback onFavorite;
  final VoidCallback onFollow;
  final VoidCallback onSource;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _PlayerActionButton(
          icon: isFavorite
              ? Icons.bookmark_rounded
              : Icons.bookmark_border_rounded,
          label: isFavorite ? '已收藏' : '收藏',
          selected: isFavorite,
          onPressed: onFavorite,
        ),
        _PlayerActionButton(
          icon: isFollowing
              ? Icons.notifications_active_rounded
              : Icons.notifications_none_rounded,
          label: isFollowing ? '已追剧' : '追剧',
          selected: isFollowing,
          onPressed: onFollow,
        ),
        _PlayerActionButton(
          icon: Icons.alt_route_rounded,
          label: '切换线路',
          onPressed: onSource,
        ),
        _PlayerActionButton(
          icon: Icons.download_outlined,
          label: '下载',
          onPressed: onDownload,
        ),
      ],
    );
  }
}

class _PlayerActionButton extends StatelessWidget {
  const _PlayerActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 17),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: selected ? ZhuyingColors.amber : ZhuyingColors.text,
        side: BorderSide(
          color: selected ? ZhuyingColors.amber : ZhuyingColors.line,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    );
  }
}

class _PlayerEpisodeSection extends StatelessWidget {
  const _PlayerEpisodeSection({
    required this.episodes,
    required this.currentIndex,
    required this.onSelect,
    required this.onShowAll,
  });

  final List<MediaEpisode> episodes;
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    final previewCount = episodes.length > 30 ? 30 : episodes.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          title: '选集',
          trailing: TextButton.icon(
            onPressed: episodes.length > previewCount ? onShowAll : null,
            icon: const Icon(Icons.grid_view_rounded, size: 16),
            label: Text('${episodes.length} 集'),
            style: TextButton.styleFrom(
              foregroundColor: ZhuyingColors.muted,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ),
        const SizedBox(height: 10),
        if (episodes.isEmpty)
          const Text(
            '当前片源没有可播放选集',
            style: TextStyle(color: ZhuyingColors.muted, fontSize: 12),
          )
        else
          SizedBox(
            height: 40,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: previewCount,
              separatorBuilder: (_, _) => const SizedBox(width: 7),
              itemBuilder: (context, index) {
                final episode = episodes[index];
                final selected = index == currentIndex;
                return ChoiceChip(
                  label: Text(episode.title),
                  selected: selected,
                  onSelected: (_) => onSelect(index),
                  labelStyle: TextStyle(
                    color: selected
                        ? const Color(0xFF241B0D)
                        : ZhuyingColors.text,
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                  selectedColor: ZhuyingColors.amber,
                  backgroundColor: ZhuyingColors.surface,
                  side: BorderSide(
                    color: selected ? ZhuyingColors.amber : ZhuyingColors.line,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  showCheckmark: false,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _RelatedMediaTile extends StatelessWidget {
  const _RelatedMediaTile({
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
      width: 128,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(7),
                child: MediaPoster(
                  url: item.posterUrl,
                  thumbnailUrl: item.thumbnailUrl,
                  title: '',
                  headers: item.posterHeaders,
                  fallbackFontSize: 12,
                  reduceMotion: reduceMotion,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: ZhuyingColors.text,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              [
                item.year,
                item.genre,
              ].where((value) => value.isNotEmpty).join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: ZhuyingColors.muted, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}

class _EpisodeSheet extends StatelessWidget {
  const _EpisodeSheet({required this.episodes, required this.currentIndex});

  final List<MediaEpisode> episodes;
  final int currentIndex;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                '全部选集  ${episodes.length} 集',
                style: const TextStyle(
                  color: ZhuyingColors.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 180,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  mainAxisExtent: 42,
                ),
                itemCount: episodes.length,
                itemBuilder: (context, index) {
                  final selected = index == currentIndex;
                  return OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(index),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: selected
                          ? const Color(0xFF241B0D)
                          : ZhuyingColors.text,
                      backgroundColor: selected
                          ? ZhuyingColors.amber
                          : Colors.transparent,
                      side: BorderSide(
                        color: selected
                            ? ZhuyingColors.amber
                            : ZhuyingColors.line,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    child: Text(
                      episodes[index].title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceSheet extends StatelessWidget {
  const _SourceSheet({required this.currentSource, required this.items});

  final String currentSource;
  final List<MediaItem> items;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 0, 4, 10),
              child: Text(
                '选择播放线路',
                style: TextStyle(
                  color: ZhuyingColors.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ListTile(
              dense: true,
              leading: const Icon(
                Icons.check_circle_rounded,
                color: ZhuyingColors.amber,
              ),
              title: Text(currentSource),
              subtitle: const Text('当前线路'),
            ),
            for (final item in items)
              ListTile(
                dense: true,
                leading: const Icon(
                  Icons.alt_route_rounded,
                  color: ZhuyingColors.muted,
                ),
                title: Text(item.sourceName),
                subtitle: Text(
                  item.episodes.isEmpty
                      ? '需要加载详情'
                      : '${item.episodes.length} 集可播放',
                ),
                onTap: () => Navigator.of(context).pop(item),
              ),
          ],
        ),
      ),
    );
  }
}

class _PlayerError extends StatelessWidget {
  const _PlayerError({required this.onRetry, this.message});

  final VoidCallback onRetry;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.56),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.signal_wifi_connected_no_internet_4_rounded,
              color: ZhuyingColors.coral,
              size: 32,
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                message ?? '播放失败，检查片源或网络后重试',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
            const SizedBox(height: 12),
            IconButton.filledTonal(
              tooltip: '重试',
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatTime(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  final hours = duration.inHours;
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}
