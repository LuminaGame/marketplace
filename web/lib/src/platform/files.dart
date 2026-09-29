import 'dart:typed_data';

import 'files_io.dart' if (dart.library.js_interop) 'files_web.dart' as impl;

/// A file the user picked.
class PickedFile {
  const PickedFile(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

/// Picks files from the user's machine: the browser's file dialog on the web.
abstract interface class FileSource {
  /// [extensions] without dots (`zip`, `json`, `png`). Null when cancelled.
  Future<PickedFile?> pick({required List<String> extensions});
}

/// Hands downloaded bytes to the user: a browser download on the web.
abstract interface class FileSaver {
  Future<void> save(String name, List<int> bytes, {String mimeType = 'application/octet-stream'});
}

/// The platform's picker (browser `<input type=file>` on the web).
FileSource platformFileSource() => impl.platformFileSource();

/// The platform's saver (a browser download on the web).
FileSaver platformFileSaver() => impl.platformFileSaver();

/// Opens [url] in a new browser tab (license texts). A no-op outside the
/// browser.
void openExternal(String url) => impl.openExternal(url);

/// Puts the browser window in (or out of) fullscreen, for the 3D view.
/// A no-op outside the browser or when the browser refuses.
void setBrowserFullscreen(bool on) => impl.setBrowserFullscreen(on);
