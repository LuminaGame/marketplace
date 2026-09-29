import 'dart:io';

import 'files.dart';

/// Outside the browser (widget tests, desktop runs) there is no file dialog;
/// callers inject a [FileSource]. Saving writes into the system temp dir.
FileSource platformFileSource() => const _NoDialogFileSource();

FileSaver platformFileSaver() => const _TempDirFileSaver();

class _NoDialogFileSource implements FileSource {
  const _NoDialogFileSource();
  @override
  Future<PickedFile?> pick({required List<String> extensions}) async =>
      throw UnsupportedError('No file dialog outside the browser; inject a FileSource.');
}

class _TempDirFileSaver implements FileSaver {
  const _TempDirFileSaver();
  @override
  Future<void> save(String name, List<int> bytes, {String mimeType = 'application/octet-stream'}) async {
    final dir = Directory.systemTemp.createTempSync('mkt_download_');
    File('${dir.path}/${name.split('/').last}').writeAsBytesSync(bytes);
  }
}

void openExternal(String url) {}

void setBrowserFullscreen(bool on) {}
