import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models.dart';
import 'poster_cache_manager.dart';

abstract final class ZhuyingColors {
  static const canvas = Color(0xFF111210);
  static const surface = Color(0xFF1A1B18);
  static const surfaceRaised = Color(0xFF242521);
  static const line = Color(0xFF30312C);
  static const text = Color(0xFFF3F0E8);
  static const muted = Color(0xFFA6A69D);
  static const amber = Color(0xFFE9B66E);
  static const green = Color(0xFF9BB7A0);
  static const coral = Color(0xFFD88570);
}

class SearchField extends StatelessWidget {
  const SearchField({
    this.controller,
    this.focusNode,
    this.readOnly = false,
    this.heroEnabled = true,
    this.autofocus = false,
    this.hintText = '搜索片名或关键词',
    this.suffixIcon,
    this.onTap,
    this.onSubmitted,
    this.onChanged,
    super.key,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool readOnly;
  final bool heroEnabled;
  final bool autofocus;
  final String hintText;
  final Widget? suffixIcon;
  final VoidCallback? onTap;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final field = Material(
      color: Colors.transparent,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        readOnly: readOnly,
        autofocus: autofocus,
        enableInteractiveSelection: !readOnly,
        textInputAction: TextInputAction.search,
        onTap: onTap,
        onSubmitted: onSubmitted,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hintText,
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: suffixIcon,
          isDense: true,
        ),
      ),
    );
    return heroEnabled
        ? Hero(tag: 'zhuying.search-field', child: field)
        : field;
  }
}

Duration motionDuration(
  BuildContext context,
  bool reduceMotion,
  Duration duration,
) => reduceMotion || MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : duration;

class SectionTitle extends StatelessWidget {
  const SectionTitle({required this.title, this.trailing, super.key});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: ZhuyingColors.text,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class PosterCard extends StatelessWidget {
  const PosterCard({
    required this.item,
    required this.onTap,
    this.favorite = false,
    this.onFavorite,
    this.reduceMotion = false,
    super.key,
  });

  final MediaItem item;
  final VoidCallback onTap;
  final bool favorite;
  final VoidCallback? onFavorite;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '打开 ${item.title}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 0.69,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Hero(
                    tag: item.id,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child: MediaPoster(
                        url: item.posterUrl,
                        thumbnailUrl: item.thumbnailUrl,
                        title: item.title,
                        headers: item.posterHeaders,
                        reduceMotion: reduceMotion,
                      ),
                    ),
                  ),
                  if (item.remarks.isNotEmpty)
                    Positioned(
                      left: 7,
                      right: 7,
                      bottom: 7,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.72),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 4,
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 86),
                            child: ClipRect(
                              child: Text(
                                item.remarks,
                                softWrap: false,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (onFavorite != null)
                    Positioned(
                      top: 3,
                      right: 3,
                      child: IconButton(
                        tooltip: favorite ? '取消收藏' : '收藏',
                        visualDensity: VisualDensity.compact,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black.withValues(alpha: 0.64),
                          foregroundColor: favorite
                              ? ZhuyingColors.amber
                              : Colors.white,
                        ),
                        onPressed: onFavorite,
                        icon: Icon(
                          favorite ? Icons.bookmark : Icons.bookmark_border,
                          size: 18,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 9),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: ZhuyingColors.text,
                fontSize: 13,
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
              style: const TextStyle(color: ZhuyingColors.muted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class MediaPoster extends StatefulWidget {
  const MediaPoster({
    required this.url,
    required this.title,
    required this.headers,
    this.thumbnailUrl = '',
    this.fallbackFontSize = 18,
    this.reduceMotion = false,
    super.key,
  });

  final String url;
  final String thumbnailUrl;
  final String title;
  final Map<String, String> headers;
  final double fallbackFontSize;
  final bool reduceMotion;

  @override
  State<MediaPoster> createState() => _MediaPosterState();
}

class _MediaPosterState extends State<MediaPoster> {
  static const _loadTimeout = Duration(seconds: 8);

  Timer? _timeoutTimer;
  bool _timedOut = false;
  bool _fullImageLoaded = false;
  bool _imageLoadCallbackScheduled = false;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    _startTimeout();
  }

  @override
  void didUpdateWidget(covariant MediaPoster oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.thumbnailUrl != widget.thumbnailUrl ||
        oldWidget.headers != widget.headers) {
      _attempt = 0;
      _fullImageLoaded = false;
      _imageLoadCallbackScheduled = false;
      _startTimeout();
    }
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    super.dispose();
  }

  void _startTimeout() {
    _timeoutTimer?.cancel();
    _timedOut = false;
    if (widget.url.isEmpty) return;
    _timeoutTimer = Timer(_loadTimeout, () {
      if (mounted) setState(() => _timedOut = true);
    });
  }

  void _retry() {
    setState(() {
      _attempt++;
      _fullImageLoaded = false;
      _imageLoadCallbackScheduled = false;
    });
    _startTimeout();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.url.isEmpty) return _fallback();
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final cacheWidth = width.isFinite && width > 0
            ? (width * MediaQuery.devicePixelRatioOf(context))
                  .round()
                  .clamp(1, 1600)
                  .toInt()
            : null;
        final motionDisabled =
            widget.reduceMotion || MediaQuery.disableAnimationsOf(context);
        final useThumbnail =
            widget.thumbnailUrl.isNotEmpty && widget.thumbnailUrl != widget.url;
        return Stack(
          fit: StackFit.expand,
          children: [
            _fallback(),
            if (useThumbnail)
              AnimatedOpacity(
                opacity: _fullImageLoaded ? 0 : 1,
                duration: motionDisabled
                    ? Duration.zero
                    : const Duration(milliseconds: 260),
                child: ClipRect(
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
                    child: CachedNetworkImage(
                      imageUrl: widget.thumbnailUrl,
                      key: ValueKey('thumb:${widget.thumbnailUrl}#$_attempt'),
                      cacheManager: posterCacheManager,
                      cacheKey: widget.thumbnailUrl,
                      httpHeaders: widget.headers,
                      maxWidthDiskCache: width.isFinite && width > 0
                          ? (width *
                                    MediaQuery.devicePixelRatioOf(context) *
                                    0.5)
                                .round()
                                .clamp(1, 800)
                                .toInt()
                          : null,
                      fit: BoxFit.cover,
                      fadeInDuration: Duration.zero,
                      fadeOutDuration: Duration.zero,
                      animate: false,
                      imageRenderMethodForWeb: kIsWeb
                          ? ImageRenderMethodForWeb.HttpGet
                          : ImageRenderMethodForWeb.HtmlImage,
                      imageBuilder: (context, imageProvider) => Image(
                        image: imageProvider,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.low,
                      ),
                      placeholder: (context, url) => const SizedBox.expand(),
                      errorBuilder: (context, error, stackTrace) =>
                          const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            CachedNetworkImage(
              imageUrl: widget.url,
              key: ValueKey('${widget.url}#$_attempt'),
              cacheManager: posterCacheManager,
              cacheKey: widget.url,
              httpHeaders: widget.headers,
              maxWidthDiskCache: cacheWidth,
              fit: BoxFit.cover,
              fadeInDuration: motionDisabled
                  ? Duration.zero
                  : const Duration(milliseconds: 260),
              fadeOutDuration: motionDisabled
                  ? Duration.zero
                  : const Duration(milliseconds: 100),
              animate: !motionDisabled,
              imageRenderMethodForWeb: kIsWeb
                  ? ImageRenderMethodForWeb.HttpGet
                  : ImageRenderMethodForWeb.HtmlImage,
              imageBuilder: (context, imageProvider) {
                _timeoutTimer?.cancel();
                _markFullImageLoaded();
                return Image(image: imageProvider, fit: BoxFit.cover);
              },
              placeholder: (context, url) => useThumbnail
                  ? const SizedBox.expand()
                  : _timedOut
                  ? _fallback(canRetry: true)
                  : _fallback(),
              errorBuilder: (context, error, stackTrace) {
                _timeoutTimer?.cancel();
                return useThumbnail
                    ? Align(
                        alignment: Alignment.topRight,
                        child: _retryButton(),
                      )
                    : _fallback(canRetry: true);
              },
            ),
            if (useThumbnail && _timedOut)
              Positioned(top: 0, right: 0, child: _retryButton()),
          ],
        );
      },
    );
  }

  void _markFullImageLoaded() {
    if (_fullImageLoaded || _imageLoadCallbackScheduled) return;
    _imageLoadCallbackScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _fullImageLoaded = true;
        _imageLoadCallbackScheduled = false;
      });
    });
  }

  Widget _fallback({bool canRetry = false}) => ColoredBox(
    color: ZhuyingColors.surfaceRaised,
    child: Stack(
      fit: StackFit.expand,
      children: [
        if (widget.title.isEmpty)
          const Center(
            child: Icon(Icons.movie_outlined, color: ZhuyingColors.muted),
          )
        else
          Padding(
            padding: const EdgeInsets.all(12),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Text(
                widget.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: ZhuyingColors.text,
                  fontSize: widget.fallbackFontSize,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        if (canRetry)
          Positioned(
            right: 0,
            top: 0,
            child: IconButton(
              tooltip: '重新加载封面',
              visualDensity: VisualDensity.compact,
              onPressed: _retry,
              icon: const Icon(Icons.refresh_rounded, size: 18),
            ),
          ),
      ],
    ),
  );

  Widget _retryButton() => IconButton(
    tooltip: '重新加载封面',
    visualDensity: VisualDensity.compact,
    style: IconButton.styleFrom(
      backgroundColor: Colors.black.withValues(alpha: 0.58),
      foregroundColor: Colors.white,
    ),
    onPressed: _retry,
    icon: const Icon(Icons.refresh_rounded, size: 18),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    this.detail,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: ZhuyingColors.amber, size: 34),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                color: ZhuyingColors.text,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (detail != null) ...[
              const SizedBox(height: 6),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: ZhuyingColors.muted, height: 1.5),
              ),
            ],
            ?action,
          ],
        ),
      ),
    );
  }
}

class SourceStatusDot extends StatelessWidget {
  const SourceStatusDot({required this.health, super.key});

  final SourceHealth health;

  @override
  Widget build(BuildContext context) {
    final color = switch (health) {
      SourceHealth.available => ZhuyingColors.green,
      SourceHealth.error => ZhuyingColors.coral,
      SourceHealth.unsupported => ZhuyingColors.muted,
      SourceHealth.pending => ZhuyingColors.amber,
    };
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
