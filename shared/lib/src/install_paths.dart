/// A name made safe for a folder: letters, digits, `-` and `_` only, runs of
/// anything else become one `_`. `Lumina Samples` → `Lumina_Samples`,
/// `Barrel` → `Barrel`.
String installFolderName(String name) {
  final cleaned = name.trim().replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '');
  return cleaned.isEmpty ? 'Listing' : cleaned;
}

/// Whether [path] is a safe relative forward-slash path: not absolute, no
/// drive letter, no `..`/`.` segments, no backslashes or NULs. Both the server
/// (on upload) and installers (on install) check every path with this.
bool isSafeRelativePath(String path) {
  if (path.isEmpty || path.contains('\\') || path.contains('\u0000')) return false;
  if (path.startsWith('/') || RegExp(r'^[A-Za-z]:').hasMatch(path)) return false;
  for (final segment in path.split('/')) {
    if (segment.isEmpty || segment == '..' || segment == '.') return false;
  }
  return true;
}
