import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_filament/filament.dart' show FilamentWeb, SphericalHarmonics;
import 'package:lumina_widgets/lumina_game.dart' as lm;
import 'package:vector_math/vector_math_64.dart';

import 'package:lumina_marketplace_web/src/features/listing/model_viewer/orbit_camera.dart';

/// The 3D view's scene on the Lumina web runtime: a [lm.LuminaGame]
/// whose world holds the preview model, a neutral studio (a light grey sky
/// with ambient image-based light, a shadow-casting key light and a ground
/// that catches the shadow) and a camera actor the orbit camera drives.
///
/// This library is deferred (see `preview_runtime.dart`): its code, the
/// Lumina runtime and flutter_filament's web bindings load only when a 3D
/// view opens.

/// Loads flutter_filament's WebAssembly module from [moduleUrl] (served next
/// to the app by the marketplace, `filament/`). The web `FilamentWidget` asks
/// for the default URL later; the module loader keeps this first load.
Future<void> loadRenderer({required String moduleUrl}) => FilamentWeb.ensureInitialized(moduleUrl: moduleUrl);

Widget buildPreviewViewport({
  required Key key,
  required Uint8List glb,
  required OrbitCamera camera,
  required VoidCallback onReady,
  required void Function(Object error) onError,
}) =>
    _PreviewViewport(key: key, glb: glb, camera: camera, onReady: onReady, onError: onError);

/// glTF → Lumina: the preview mesh is served from memory under this path.
const _previewPath = 'marketplace/preview.glb';
const _groundPath = 'marketplace/ground.glb';

/// Studio backdrop: the sky and the ground share a light neutral grey, so the
/// ground fades into the background instead of ending at a horizon.
const _backdrop = 0.56;

class _PreviewViewport extends StatefulWidget {
  const _PreviewViewport({
    super.key,
    required this.glb,
    required this.camera,
    required this.onReady,
    required this.onError,
  });

  final Uint8List glb;
  final OrbitCamera camera;
  final VoidCallback onReady;
  final void Function(Object error) onError;

  @override
  State<_PreviewViewport> createState() => _PreviewViewportState();
}

class _PreviewViewportState extends State<_PreviewViewport> {
  @override
  void initState() {
    super.initState();
    // The engine's platform, asset bundle and video seams, as a game's
    // launcher fills them.
    lm.LuminaWidgets.ensureInitialized();
  }

  late final _PreviewGame _game = _PreviewGame(
    glb: widget.glb,
    camera: widget.camera,
    onReady: () {
      if (mounted) widget.onReady();
    },
    onError: (e) {
      if (mounted) widget.onError(e);
    },
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        _game.aspect = constraints.maxHeight > 0 ? constraints.maxWidth / constraints.maxHeight : 16 / 9;
        // No headless swap chain: FilamentWidget presents every frame into
        // its canvas; the ticker only advances the world.
        return lm.LuminaGameWidget(game: _game, useHeadlessSwapChain: false);
      });
}

class _PreviewGame extends lm.LuminaGame {
  _PreviewGame({required this.glb, required this.camera, required this.onReady, required this.onError});

  final Uint8List glb;
  final OrbitCamera camera;
  final VoidCallback onReady;
  final void Function(Object error) onError;

  /// Viewport width / height, for framing.
  double aspect = 16 / 9;

  late lm.LuminaStaticMeshComponent _mesh;
  late lm.LuminaStaticMeshComponent _ground;
  late lm.LuminaCameraComponent _camera;
  bool _framed = false;
  bool _reported = false;
  int _ticksSinceFramed = 0;
  int _syncedRevision = -1;

  late final Uint8List _groundGlb = lm.PrimitiveGlbFactory.build(
    shape: 'plane',
    sizeX: 100,
    sizeY: 1,
    sizeZ: 100,
    colorHex: '#8F8F8F',
  );

  Future<Uint8List> _assets(String path) async => switch (path) {
        _previewPath => glb,
        _groundPath => _groundGlb,
        _ => throw StateError('The 3D view has no asset $path'),
      };

  @override
  lm.LuminaObject? build(lm.LuminaBuildContext context) {
    _mesh = lm.LuminaStaticMeshComponent(meshAssetPath: _previewPath, assetProvider: _assets);
    // A 1 m plane in world units, scaled to the model once its bounds are known.
    _ground = lm.LuminaStaticMeshComponent(
      meshAssetPath: _groundPath,
      assetProvider: _assets,
      assetUnitScale: 1,
      castShadows: false,
    );
    _camera = lm.LuminaCameraComponent(fieldOfViewInDegrees: camera.fovDegrees)..isActive = true;
    // The key light comes from high on the camera's left and slightly
    // behind it, so the ground shadow falls back and to the right.
    final keyDirection = Vector3(0.45, -0.85, -0.3)..normalize();
    final key = lm.LuminaDirectionalLightComponent(
      rotation: Quaternion.fromTwoVectors(Vector3(0, 0, -1), keyDirection),
      intensity: 90000,
      castShadows: true,
      color: Vector3(1.0, 0.97, 0.93),
    );
    final sky = lm.LuminaSkyComponent.color(
      color: Vector4(_backdrop, _backdrop, _backdrop, 1),
      // Soft studio fill: brighter from above than from below.
      ambientSh: SphericalHarmonics(bands: 2, coefficients: [
        0.70, 0.70, 0.72, // L00: the even fill
        0.22, 0.22, 0.24, // L1-1 (+Y): more light from above
        0.00, 0.00, 0.00, // L10
        0.00, 0.00, 0.00, // L11
      ]),
      iblIntensity: 28000,
      skyIntensity: 30000,
    );

    _mesh.loaded.then((_) => _frame(), onError: (Object e) => _fail(e));
    _ground.loaded.then((_) {}, onError: (Object e) => _fail(e));

    return lm.LuminaNodeGroup(children: [
      lm.LuminaActor(key: const lm.LuminaObjectKey('preview_sky'), root: sky),
      lm.LuminaActor(key: const lm.LuminaObjectKey('preview_key_light'), root: key),
      lm.LuminaActor(key: const lm.LuminaObjectKey('preview_ground'), root: _ground),
      lm.LuminaActor(key: const lm.LuminaObjectKey('preview_model'), root: _mesh),
      lm.LuminaActor(key: const lm.LuminaObjectKey('preview_camera'), root: _camera),
    ]);
  }

  void _fail(Object e) {
    if (_reported) return;
    _reported = true;
    onError(e);
  }

  void _frame() {
    final bounds = _mesh.localBounds;
    if (bounds == null) {
      _fail(StateError('The model has no geometry to show.'));
      return;
    }
    camera.frame(bounds.min, bounds.max, aspect: aspect);
    // The ground sits under the model and reaches far past it.
    final size = camera.radius * 60;
    _ground.owner?.actorLocation = Vector3(camera.target.x, bounds.min.y, camera.target.z);
    _ground.owner?.actorScale = Vector3(size / 100, 1, size / 100);
    _framed = true;
  }

  @override
  void tickGame(double deltaTime) {
    if (camera.revision != _syncedRevision) {
      _syncedRevision = camera.revision;
      _camera
        ..relativeLocation = camera.eye
        ..relativeRotation = camera.rotation
        ..nearClipPlane = camera.nearClip
        ..farClipPlane = camera.farClip;
    }
    super.tickGame(deltaTime);
    // The widget renders after each tick: a few ticks after framing, the
    // model is on screen (textures upload asynchronously in the meantime).
    if (_framed && !_reported && ++_ticksSinceFramed >= 6) {
      _reported = true;
      onReady();
    }
  }
}
