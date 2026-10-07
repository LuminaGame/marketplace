import 'dart:typed_data';

import 'package:shadcn_flutter/shadcn_flutter.dart';

// The Lumina scene is a deferred library: dart2js splits it (with the Lumina
// runtime and flutter_filament's web bindings) into its own part files, which
// the browser fetches only when a 3D view opens. Off the web — the widget
// tests on the VM — the stub stands in: it has no WebGL2 to render with.
import 'package:lumina_marketplace_web/src/features/listing/model_viewer/lumina_preview_scene_stub.dart' if (dart.library.js_interop) 'lumina_preview_scene.dart' deferred as scene;
import 'package:lumina_marketplace_web/src/features/listing/model_viewer/orbit_camera.dart';

/// Where the web build serves flutter_filament's WebAssembly module and its
/// loader (`tool/sync_filament_module.dart` copies them into `web/filament/`).
const String filamentModuleUrl = 'filament/flutter_filament.js';

/// Loads the Lumina web runtime on demand and builds its viewport.
abstract final class LuminaPreviewRuntime {
  static Future<void>? _code;
  static bool _codeLoaded = false;

  /// Whether the runtime's code has been loaded — false until a 3D view opens.
  static bool get isCodeLoaded => _codeLoaded;

  /// Loads the deferred Lumina scene library.
  static Future<void> loadCode() => _code ??= scene.loadLibrary().then((_) => _codeLoaded = true).catchError((Object e) {
        _code = null;
        throw e;
      });

  /// Loads flutter_filament's WebAssembly module (after [loadCode]); throws
  /// where there is no WebGL2 renderer.
  static Future<void> loadRenderer() => scene.loadRenderer(moduleUrl: filamentModuleUrl);

  /// The live viewport: a Lumina game showing [glb] from [camera].
  /// [onReady] fires once the model is framed and drawn, [onError] when the
  /// scene cannot show it.
  static Widget viewport({
    required Key key,
    required Uint8List glb,
    required OrbitCamera camera,
    required VoidCallback onReady,
    required void Function(Object error) onError,
  }) =>
      scene.buildPreviewViewport(key: key, glb: glb, camera: camera, onReady: onReady, onError: onError);
}
