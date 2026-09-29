import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'files.dart';

FileSource platformFileSource() => const _BrowserFileSource();

FileSaver platformFileSaver() => const _BrowserFileSaver();

class _BrowserFileSource implements FileSource {
  const _BrowserFileSource();

  @override
  Future<PickedFile?> pick({required List<String> extensions}) {
    final completer = Completer<PickedFile?>();
    final input = web.HTMLInputElement()
      ..type = 'file'
      ..accept = extensions.map((e) => '.$e').join(',')
      ..style.display = 'none';
    web.document.body!.append(input);
    input.onchange = ((web.Event _) {
      final file = input.files?.item(0);
      input.remove();
      if (file == null) {
        completer.complete(null);
        return;
      }
      file.arrayBuffer().toDart.then((buffer) {
        completer.complete(PickedFile(file.name, buffer.toDart.asUint8List()));
      }, onError: completer.completeError);
    }).toJS;
    input.oncancel = ((web.Event _) {
      input.remove();
      if (!completer.isCompleted) completer.complete(null);
    }).toJS;
    input.click();
    return completer.future;
  }
}

class _BrowserFileSaver implements FileSaver {
  const _BrowserFileSaver();

  @override
  Future<void> save(String name, List<int> bytes, {String mimeType = 'application/octet-stream'}) async {
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final blob = web.Blob([data.toJS].toJS, web.BlobPropertyBag(type: mimeType));
    final url = web.URL.createObjectURL(blob);
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = name
      ..style.display = 'none';
    web.document.body!.append(anchor);
    anchor.click();
    anchor.remove();
    Timer(const Duration(seconds: 30), () => web.URL.revokeObjectURL(url));
  }
}

void openExternal(String url) => web.window.open(url, '_blank', 'noopener');

void setBrowserFullscreen(bool on) {
  try {
    if (on && web.document.fullscreenElement == null) {
      web.document.documentElement?.requestFullscreen().toDart.catchError((Object _) => null);
    } else if (!on && web.document.fullscreenElement != null) {
      web.document.exitFullscreen().toDart.catchError((Object _) => null);
    }
  } catch (_) {
    // Fullscreen is a nicety: the viewer still fills the window without it.
  }
}
