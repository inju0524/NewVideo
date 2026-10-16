import 'package:cached_network_image_ce/cached_network_image.dart';

final BaseCacheManager posterCacheManager = DefaultCacheManager(
  stalePeriod: const Duration(days: 365),
  maxNrOfCacheObjects: 300,
);
