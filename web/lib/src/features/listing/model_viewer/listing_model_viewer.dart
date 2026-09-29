import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../../theme/marketplace_theme.dart';
import 'model_viewer_controller.dart';
import 'preview_runtime.dart';

/// The listing page's 3D view: the Lumina viewport with mouse
/// orbit / pan / zoom, an overlay toolbar (reset view, fullscreen), the
/// staged loading progress and the error state.
///
/// Its state lives in [controller], so the page can remount it (fullscreen)
/// without downloading the model again.
class ListingModelViewer extends StatefulWidget {
  const ListingModelViewer({
    super.key,
    required this.controller,
    required this.fullscreen,
    required this.onToggleFullscreen,
  });

  final ModelViewerController controller;
  final bool fullscreen;
  final VoidCallback onToggleFullscreen;

  @override
  State<ListingModelViewer> createState() => _ListingModelViewerState();
}

class _ListingModelViewerState extends State<ListingModelViewer> {
  ModelViewerController get _c => widget.controller;

  /// Buttons held since the last pointer down.
  int _buttons = 0;

  @override
  void initState() {
    super.initState();
    // Right-drag pans: keep the browser's context menu off the viewport.
    if (kIsWeb) BrowserContextMenu.disableContextMenu();
    if (_c.stage == ViewerStage.ready) {
      _c.remount();
    } else {
      _c.open();
    }
  }

  @override
  void dispose() {
    if (kIsWeb) BrowserContextMenu.enableContextMenu();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent e) => _buttons = e.buttons;

  void _onPointerMove(PointerMoveEvent e, double height) {
    if (_c.stage != ViewerStage.ready) return;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    final buttons = e.buttons != 0 ? e.buttons : _buttons;
    if (buttons & (kSecondaryMouseButton | kMiddleMouseButton) != 0 || (buttons & kPrimaryButton != 0 && shift)) {
      _c.camera.pan(e.delta.dx, e.delta.dy, height);
    } else if (buttons & kPrimaryButton != 0) {
      _c.camera.orbit(e.delta.dx, e.delta.dy);
    }
  }

  void _onPointerSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent || _c.stage != ViewerStage.ready) return;
    // The viewer, not the page, takes the wheel while the cursor is on it.
    GestureBinding.instance.pointerSignalResolver.register(e, (event) {
      _c.camera.zoom((event as PointerScrollEvent).scrollDelta.dy);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        final stage = _c.stage;
        final model = _c.model;
        final showScene = model != null && (stage == ViewerStage.preparing || stage == ViewerStage.ready);
        return Semantics(
          container: true,
          label: stage.isLoading ? '3D view loading: ${stage.label}' : stage.label,
          child: ColoredBox(
            color: const Color(0xFF8E8E8E),
            child: LayoutBuilder(builder: (context, constraints) {
              return Stack(fit: StackFit.expand, children: [
                if (showScene)
                  Listener(
                    onPointerDown: _onPointerDown,
                    onPointerMove: (e) => _onPointerMove(e, constraints.maxHeight),
                    onPointerSignal: _onPointerSignal,
                    child: GestureDetector(
                      onDoubleTap: _c.camera.reset,
                      child: LuminaPreviewRuntime.viewport(
                        key: ValueKey('lumina_preview_scene_${_c.sceneGeneration}'),
                        glb: model,
                        camera: _c.camera,
                        onReady: _c.sceneReady,
                        onError: _c.fail,
                      ),
                    ),
                  ),
                if (stage.isLoading) _LoadingOverlay(stage: stage, progress: _c.progress),
                if (stage == ViewerStage.error) _ErrorOverlay(message: _c.error ?? 'The 3D view failed.', onRetry: _c.retry),
                if (stage == ViewerStage.ready) ...[
                  Positioned(top: 10, right: 10, child: _toolbar()),
                  const Positioned(left: 12, bottom: 10, child: _ControlsHint()),
                ],
              ]);
            }),
          ),
        );
      },
    );
  }

  Widget _toolbar() => Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: MarketColors.popover.withValues(alpha: 0.86),
          border: Border.all(color: MarketColors.border),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Tooltip(
            tooltip: (context) => const TooltipContainer(child: Text('Reset view')),
            child: IconButton.ghost(
              key: const ValueKey('viewer_reset'),
              icon: const Icon(LucideIcons.rotateCcw, size: 15),
              size: ButtonSize.small,
              onPressed: _c.camera.reset,
            ).semanticsLabel('Reset view'),
          ),
          Tooltip(
            tooltip: (context) => TooltipContainer(child: Text(widget.fullscreen ? 'Exit fullscreen' : 'Fullscreen')),
            child: IconButton.ghost(
              key: const ValueKey('viewer_fullscreen'),
              icon: Icon(widget.fullscreen ? LucideIcons.minimize : LucideIcons.maximize, size: 15),
              size: ButtonSize.small,
              onPressed: widget.onToggleFullscreen,
            ).semanticsLabel(widget.fullscreen ? 'Exit fullscreen' : 'Fullscreen'),
          ),
        ]),
      );
}

extension on Widget {
  Widget semanticsLabel(String label) => Semantics(button: true, label: label, child: this);
}

class _LoadingOverlay extends StatelessWidget {
  const _LoadingOverlay({required this.stage, required this.progress});
  final ViewerStage stage;
  final double progress;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: MarketColors.card,
        child: Center(
          child: SizedBox(
            width: 300,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Icon(LucideIcons.box, size: 28, color: MarketColors.mutedForeground),
              const SizedBox(height: 14),
              Progress(key: const ValueKey('viewer_progress'), progress: progress),
              const SizedBox(height: 10),
              Text(stage.label, textAlign: TextAlign.center).small().muted(),
              const SizedBox(height: 4),
              Text('${(progress * 100).round()}%', textAlign: TextAlign.center).xSmall().muted(),
            ]),
          ),
        ),
      );
}

class _ErrorOverlay extends StatelessWidget {
  const _ErrorOverlay({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: MarketColors.card,
        child: Center(
          child: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(LucideIcons.triangleAlert, size: 26, color: MarketColors.destructive),
              const SizedBox(height: 12),
              const Text('The 3D view could not start').semiBold(),
              const SizedBox(height: 6),
              Text(message, key: const ValueKey('viewer_error'), textAlign: TextAlign.center).small().muted(),
              const SizedBox(height: 14),
              OutlineButton(
                key: const ValueKey('viewer_retry'),
                leading: const Icon(LucideIcons.refreshCw, size: 13),
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
            ]),
          ),
        ),
      );
}

class _ControlsHint extends StatelessWidget {
  const _ControlsHint();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: MarketColors.popover.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(3),
        ),
        child: const Text('Drag to orbit · Right-drag or Shift+drag to pan · Scroll to zoom · Double-click to reset',
                style: TextStyle(fontSize: 11, color: MarketColors.secondaryForeground))
            .xSmall(),
      );
}
