import 'repository_dns_stub.dart'
    if (dart.library.io) 'repository_dns_io.dart'
    as platform;

Future<bool> isPublicRepositoryHost(String host) =>
    platform.isPublicRepositoryHost(host);
