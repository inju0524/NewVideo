Future<bool> isPublicRepositoryHost(String host) async {
  final normalized = host.toLowerCase();
  return normalized.isNotEmpty &&
      normalized != 'localhost' &&
      !normalized.endsWith('.localhost') &&
      !normalized.endsWith('.local') &&
      !normalized.endsWith('.internal') &&
      !RegExp(r'^\d{1,3}(?:\.\d{1,3}){3}$').hasMatch(normalized) &&
      !normalized.contains(':');
}
