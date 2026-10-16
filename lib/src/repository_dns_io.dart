import 'dart:io';

Future<bool> isPublicRepositoryHost(String host) async {
  final normalized = host.toLowerCase();
  if (normalized == 'localhost' ||
      normalized.endsWith('.localhost') ||
      normalized.endsWith('.local') ||
      normalized.endsWith('.internal') ||
      InternetAddress.tryParse(normalized) != null) {
    return false;
  }
  try {
    final addresses = await InternetAddress.lookup(normalized)
        .timeout(const Duration(seconds: 5));
    return addresses.isNotEmpty && addresses.every(_isPublicAddress);
  } on Object {
    return false;
  }
}

bool _isPublicAddress(InternetAddress address) {
  if (address.type == InternetAddressType.IPv4) {
    final bytes = address.rawAddress;
    final first = bytes[0];
    final second = bytes[1];
    return first != 0 &&
        first != 10 &&
        first != 127 &&
        first < 224 &&
        !(first == 100 && second >= 64 && second <= 127) &&
        !(first == 169 && second == 254) &&
        !(first == 172 && second >= 16 && second <= 31) &&
        !(first == 192 && (second == 0 || second == 168)) &&
        !(first == 192 && second == 88 && bytes[2] == 99) &&
        !(first == 198 && (second == 18 || second == 19 || second == 51)) &&
        !(first == 203 && second == 0 && bytes[2] == 113);
  }
  if (address.type == InternetAddressType.IPv6) {
    final bytes = address.rawAddress;
    return bytes.length == 16 &&
        (bytes[0] & 0xe0) == 0x20 &&
        !(bytes[0] == 0x20 &&
            bytes[1] == 0x01 &&
            bytes[2] == 0x0d &&
            bytes[3] == 0xb8);
  }
  return false;
}
