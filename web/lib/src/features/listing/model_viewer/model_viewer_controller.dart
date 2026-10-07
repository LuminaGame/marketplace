import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:lumina_marketplace_shared/lumina_marketplace_shared.dart';

import 'package:lumina_marketplace_web/src/features/listing/model_viewer/orbit_camera.dart';
import 'package:lumina_marketplace_web/src/features/listing/model_viewer/preview_download.dart';
import 'package:lumina_marketplace_web/src/features/listing/model_viewer/preview_runtime.dart';

/// Where a 3D view is on its way to a rendered model.
enum ViewerStage {
  idle('3D view'),
  loadingRuntime('Loading the Lumina runtime…'),
  loadingRenderer('Starting the renderer…'),
  downloading('Downloading the model…'),
  preparing('Preparing the scene…'),
  ready('3D view ready'),
  error('3D view error');

  const ViewerStage(this.label);
  final String label;

  bool get isLoading => this != idle && this != ready && this != error;
}

/// The state of one listing's 3D view: loads the Lumina runtime,
/// the renderer and the preview model in stages with a combined [progress],
/// then waits for the scene to report its first frame ([sceneReady]).
///
/// The page owns it, so the downloaded model and the camera survive the
/// viewer being remounted (fullscreen) and switching back to the images.
class ModelViewerController extends ChangeNotifier {
  ModelViewerController({
    required this.client,
    required this.version,
  });

  final MarketplaceClient client;

  /// The listing version whose preview model is shown.
  final ListingVersion version;

  final OrbitCamera camera = OrbitCamera();

  ViewerStage _stage = ViewerStage.idle;
  ViewerStage get stage => _stage;

  double _progress = 0;

  /// 0…1 over every stage.
  double get progress => _progress;

  String? _error;
  String? get error => _error;

  Uint8List? _model;

  /// The preview model once downloaded and verified.
  Uint8List? get model => _model;

  /// Bumped each time a scene should be (re)built from [model].
  int sceneGeneration = 0;

  bool _disposed = false;

  // Progress share of each stage (the rest is preparing the scene).
  static const _runtimeShare = 0.10;
  static const _downloadShare = 0.40;
  static const _rendererShare = 0.40;
  static const _preparingAt = _runtimeShare + _downloadShare + _rendererShare;

  void _set(ViewerStage stage, double progress) {
    if (_disposed) return;
    _stage = stage;
    _progress = progress.clamp(0.0, 1.0);
    notifyListeners();
  }

  /// Starts loading (no-op while loading or once ready).
  Future<void> open() async {
    if (_stage.isLoading || _stage == ViewerStage.ready) return;
    _error = null;
    try {
      _set(ViewerStage.loadingRuntime, 0);
      await LuminaPreviewRuntime.loadCode();
      if (_model == null) {
        _set(ViewerStage.downloading, _runtimeShare);
        _model = await downloadPreviewModel(
          client,
          version.previewModelUrl!,
          expectedSha256: version.previewModelSha256,
          expectedSize: version.previewModelSize,
          onProgress: (f) => _set(ViewerStage.downloading, _runtimeShare + f * _downloadShare),
        );
      }
      _set(ViewerStage.loadingRenderer, _runtimeShare + _downloadShare);
      await LuminaPreviewRuntime.loadRenderer();
      sceneGeneration++;
      _set(ViewerStage.preparing, _preparingAt);
    } catch (e) {
      fail(e);
    }
  }

  /// The scene drew its first frame of the framed model.
  void sceneReady() {
    if (_stage == ViewerStage.preparing) _set(ViewerStage.ready, 1);
  }

  /// The scene (or a loading step) failed.
  void fail(Object e) {
    _error = switch (e) {
      UnsupportedError(:final message) => message ?? '$e',
      PreviewDownloadException(:final message) => message,
      MarketplaceException(:final message) => message,
      _ => 'The 3D view could not load this model: $e',
    };
    _set(ViewerStage.error, _progress);
  }

  /// A remounted viewer (fullscreen) builds a fresh scene from the cached
  /// model: back to [ViewerStage.preparing] until it reports its first frame.
  void remount() {
    if (_stage == ViewerStage.ready && _model != null) {
      sceneGeneration++;
      _set(ViewerStage.preparing, _preparingAt);
    }
  }

  /// Tries again after an error.
  Future<void> retry() {
    _stage = ViewerStage.idle;
    return open();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
