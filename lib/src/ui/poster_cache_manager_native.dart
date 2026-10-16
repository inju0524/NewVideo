import 'package:cached_network_image_ce/cached_network_image.dart'
    show BaseCacheManager, ConnectionParameters, LruCleanupStrategy;
// ignore: implementation_imports
import 'package:cached_network_image_ce/src/cache/default_cache_manager.dart'
    show DefaultCacheManager;
import 'package:path_provider/path_provider.dart';

final BaseCacheManager posterCacheManager = DefaultCacheManager(
  stalePeriod: const Duration(days: 365),
  maxNrOfCacheObjects: 300,
  connectionParameters: ConnectionParameters(
    connectionTimeout: const Duration(seconds: 8),
    requestTimeout: const Duration(seconds: 20),
  ),
  cacheDirectoryProvider: getApplicationSupportDirectory,
  metadataDirectoryProvider: getApplicationSupportDirectory,
  cleanupStrategy: const LruCleanupStrategy(),
);
