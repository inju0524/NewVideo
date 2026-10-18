import 'package:web/web.dart' as web;

void updateWebBranding({
  required String title,
  required String faviconPath,
  required String appleTouchIconPath,
  required String manifestPath,
}) {
  web.document.title = title;
  final icon = web.document.querySelector('link[rel="icon"]');
  if (icon != null) (icon as web.HTMLLinkElement).href = faviconPath;
  final appleTitle = web.document.querySelector(
    'meta[name="apple-mobile-web-app-title"]',
  );
  if (appleTitle != null) {
    (appleTitle as web.HTMLMetaElement).content = title;
  }
  final appleIcon = web.document.querySelector('link[rel="apple-touch-icon"]');
  if (appleIcon != null) {
    (appleIcon as web.HTMLLinkElement).href = appleTouchIconPath;
  }
  final manifest = web.document.querySelector('#pwa-manifest');
  if (manifest != null) {
    (manifest as web.HTMLLinkElement).href = manifestPath;
  }
}
