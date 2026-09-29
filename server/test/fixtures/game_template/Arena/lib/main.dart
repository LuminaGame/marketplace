// GENERATED CODE - DO NOT MODIFY BY HAND
// Lumina Engine 0.0.1 Auto-Generated Launcher
// ignore_for_file: unused_import

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lumina/lumina_runtime.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as shadcn;
import 'levels/l_default_level.dart';
import 'game/arena_game_mode.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Every asset the level names is read from the app bundle (pubspec.yaml
  // bundles contents/), so the same game runs on desktop and on the web.
  LuminaAssets.defaultProvider = (path) async {
    final data = await rootBundle.load(path);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  };
  runApp(const MyLuminaGameApp());
}

/// The game: a declarative world that starts in `L_DefaultLevel`.
class ArenaGame extends LuminaGame {
  @override
  LuminaObject? build(LuminaBuildContext context) {
    final world = context.world;
    if (world != null) {
      if (world.getSubsystem<LuminaCollisionSubsystem>() == null) {
        world.registerSubsystem(LuminaCollisionSubsystem());
      }
      if (world.getSubsystem<LuminaInputSubsystem>() == null) {
        world.registerSubsystem(LuminaInputSubsystem());
      }
      world.gameMode ??= ArenaGameMode();
      // Project Settings > Physics (cm/s², authoring Z-up).
      world.gravityZ = -980.0000;
    }
    // The level's actors mount straight into the world's persistent level
    // (and its script actor alongside them) so beginPlay, the tick pipeline
    // and the game mode's player-start search all see them.
    final level = LDefaultLevel();
    final levelScript = level.scriptActor;
    return LuminaNodeGroup(children: [
      ...?level.build(context)?.children,
      if (levelScript != null) levelScript,
    ]);
  }
}

class MyLuminaGameApp extends StatelessWidget {
  const MyLuminaGameApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'arena',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const Scaffold(body: shadcn.ShadcnLayer(theme: shadcn.ThemeData.dark(), child: _GameHost())),
    );
  }
}

/// Bridges Flutter keyboard and mouse events into the running world's
/// [LuminaInputSubsystem], so the keys bound by the project's `Gameplay`
/// mapping context actually reach the possessed pawn.
class _GameHost extends StatefulWidget {
  const _GameHost();

  @override
  State<_GameHost> createState() => _GameHostState();
}

class _GameHostState extends State<_GameHost> {
  final ArenaGame _game = ArenaGame();
  final FocusNode _focusNode = FocusNode();
  StreamSubscription<MouseCaptureEvent>? _mouseEvents;
  MouseCaptureSupport? _captureSupport;
  bool _isCaptured = false;

  static final Map<LogicalKeyboardKey, LuminaKey> _keyMap = <LogicalKeyboardKey, LuminaKey>{
    LogicalKeyboardKey.keyW: LuminaKey.keyW,
    LogicalKeyboardKey.keyA: LuminaKey.keyA,
    LogicalKeyboardKey.keyS: LuminaKey.keyS,
    LogicalKeyboardKey.keyD: LuminaKey.keyD,
    LogicalKeyboardKey.space: LuminaKey.keySpace,
    LogicalKeyboardKey.shiftLeft: LuminaKey.keyLeftShift,
    LogicalKeyboardKey.controlLeft: LuminaKey.keyLeftControl,
    LogicalKeyboardKey.altLeft: LuminaKey.keyLeftAlt,
  };

  LuminaInputSubsystem? get _input => _game.world?.getSubsystem<LuminaInputSubsystem>();

  @override
  void initState() {
    super.initState();
    _initMouseCapture();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      final size = box?.size;
      final centre = size != null ? Offset(size.width / 2, size.height / 2) : null;
      _capture(centre);
    });
  }

  Future<void> _initMouseCapture() async {
    final backend = LuminaMouseCapture.backend;
    _mouseEvents = backend.events.listen((event) {
      if (event is MouseCaptureMotion) {
        final input = _input;
        if (input != null) {
          input.injectAnalog(LuminaKey.mouseX, event.dx);
          input.injectAnalog(LuminaKey.mouseY, event.dy);
        }
      } else if (event is MouseCaptureLocked) {
        _isCaptured = true;
      } else if (event is MouseCaptureLost) {
        _isCaptured = false;
      }
    });
    _captureSupport = await backend.support();
  }

  void _capture([Offset? centre]) {
    LuminaMouseCapture.backend.capture(centre: centre);
    _isCaptured = true;
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    final key = _keyMap[event.logicalKey];
    final input = _input;
    if (key == null || input == null) return KeyEventResult.ignored;
    if (event is KeyDownEvent) {
      input.injectKeyDown(key);
    } else if (event is KeyUpEvent) {
      input.injectKeyUp(key);
    }
    return KeyEventResult.handled;
  }

  void _onPointerDelta(PointerEvent event) {
    if (_captureSupport?.relativeMotion == true) return;
    final input = _input;
    if (input == null) return;
    input.injectAnalog(LuminaKey.mouseX, event.delta.dx);
    input.injectAnalog(LuminaKey.mouseY, event.delta.dy);
  }

  @override
  void dispose() {
    _mouseEvents?.cancel();
    LuminaMouseCapture.backend.release();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: MouseRegion(
        // The game owns the mouse: pointer lock and relative motion keep it
        // from escaping the window while turning.
        cursor: SystemMouseCursors.none,
        onHover: _onPointerDelta,
        child: Listener(
          onPointerDown: (event) {
            _focusNode.requestFocus();
            if (!_isCaptured) {
              final box = context.findRenderObject() as RenderBox?;
              final size = box?.size;
              final centre = size != null ? Offset(size.width / 2, size.height / 2) : null;
              _capture(centre);
            }
          },
          onPointerMove: _onPointerDelta,
          // The widgets the game's Blueprints add to the viewport (Create
          // Widget → Add to Viewport) render above the 3D view.
          child: Stack(
            fit: StackFit.expand,
            children: [
              LuminaGameWidget(game: _game),
              LuminaWidgetLayer.forGame(game: _game),
            ],
          ),
        ),
      ),
    );
  }
}
