import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<bool> requestPlayerFullscreen() async {
  final element = web.document.documentElement;
  if (element == null) return false;
  try {
    await element.requestFullscreen().toDart;
    return web.document.fullscreenElement != null;
  } on Object {
    return false;
  }
}

Future<void> exitPlayerFullscreen() async {
  if (web.document.fullscreenElement == null) return;
  try {
    await web.document.exitFullscreen().toDart;
  } on Object {
    // The browser can reject exit requests while the page is changing state.
  }
}

Stream<bool> playerFullscreenChanges() {
  return web.EventStreamProviders.fullscreenChangeEvent
      .forTarget(web.document)
      .map((_) => web.document.fullscreenElement != null);
}
