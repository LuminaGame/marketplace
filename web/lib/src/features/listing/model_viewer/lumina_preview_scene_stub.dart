import 'dart:typed_data';

import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'orbit_camera.dart';

/// Off the web (the VM widget tests) there is no browser canvas: the 3D view
/// reports that it needs one. The web build uses `lumina_preview_scene.dart`.
Future<void> loadRenderer({required String moduleUrl}) async =>
    throw UnsupportedError('The 3D view needs a browser with WebGL2.');

Widget buildPreviewViewport({
  required Key key,
  required Uint8List glb,
  required OrbitCamera camera,
  required VoidCallback onReady,
  required void Function(Object error) onError,
}) =>
    throw UnsupportedError('The 3D view needs a browser with WebGL2.');
