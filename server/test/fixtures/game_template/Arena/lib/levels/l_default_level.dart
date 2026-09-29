// GENERATED CODE - DO NOT MODIFY BY HAND
// Lumina Engine 0.0.1 Auto-Generated Level Code
// ignore_for_file: unused_import, prefer_const_constructors

import 'package:flutter/foundation.dart' show ValueKey;
import 'package:lumina/lumina_runtime.dart';
import 'package:vector_math/vector_math_64.dart';
import '../game/arena_game_mode.dart';

/// Level `L_DefaultLevel` as authored in Lumina Studio.
class LDefaultLevel extends LuminaLevel {
  LDefaultLevel({super.key})
      : super(name: 'L_DefaultLevel', scriptActor: _LDefaultLevelScript(), children: [
          // PlayerStart
          LuminaPlayerStart(key: const ValueKey('act_player_start'), location: Vector3(0.0000, 100.0000, 600.0000), rotation: luminaAuthoringRotation(0.0000, 0.0000, 0.0000)),
          // DirectionalLight_Sun
          LuminaActor(key: const ValueKey('act_sun'), root: LuminaDirectionalLightComponent(location: Vector3(0.0000, 800.0000, 400.0000), rotation: luminaAuthoringRotation(-50.0000, 0.0000, -30.0000), color: Vector3(1.0000, 0.9490, 0.8784), intensity: 100000.0000, sunAngularRadius: 0.5450, castShadows: true, visible: true)),
          // SkyAtmosphere_Env
          LuminaActor(key: const ValueKey('act_sky'), root: LuminaSkyComponent.color(color: Vector4(0.3529, 0.5255, 0.7765, 1.0), location: Vector3(0.0000, 0.0000, 0.0000), rotation: luminaAuthoringRotation(0.0000, 0.0000, 0.0000), skyIntensity: 30000.0000, iblIntensity: 30000.0000)),
          // Floor
          LuminaPrimitiveActor(key: const ValueKey('act_floor'), location: Vector3(0.0000, 0.0000, 0.0000), rotation: luminaAuthoringRotation(0.0000, 0.0000, 0.0000), scale: Vector3(1.0000, 1.0000, 1.0000), shape: luminaPrimitiveShapeFrom('plane'), size: Vector3(2000.0000, 0.0000, 2000.0000), color: Vector3(0.4314, 0.4627, 0.5059)),
          // Wall_North
          LuminaPrimitiveActor(key: const ValueKey('act_wall_n'), location: Vector3(0.0000, 150.0000, -1000.0000), rotation: luminaAuthoringRotation(0.0000, 0.0000, 0.0000), scale: Vector3(1.0000, 1.0000, 1.0000), shape: luminaPrimitiveShapeFrom('box'), size: Vector3(2000.0000, 300.0000, 30.0000), color: Vector3(0.5451, 0.5765, 0.6314)),
          // Wall_South
          LuminaPrimitiveActor(key: const ValueKey('act_wall_s'), location: Vector3(0.0000, 150.0000, 1000.0000), rotation: luminaAuthoringRotation(0.0000, 0.0000, 0.0000), scale: Vector3(1.0000, 1.0000, 1.0000), shape: luminaPrimitiveShapeFrom('box'), size: Vector3(2000.0000, 300.0000, 30.0000), color: Vector3(0.5451, 0.5765, 0.6314)),
          // Wall_East
          LuminaPrimitiveActor(key: const ValueKey('act_wall_e'), location: Vector3(1000.0000, 150.0000, 0.0000), rotation: luminaAuthoringRotation(0.0000, 0.0000, 0.0000), scale: Vector3(1.0000, 1.0000, 1.0000), shape: luminaPrimitiveShapeFrom('box'), size: Vector3(30.0000, 300.0000, 2000.0000), color: Vector3(0.5451, 0.5765, 0.6314)),
          // Wall_West
          LuminaPrimitiveActor(key: const ValueKey('act_wall_w'), location: Vector3(-1000.0000, 150.0000, 0.0000), rotation: luminaAuthoringRotation(0.0000, 0.0000, 0.0000), scale: Vector3(1.0000, 1.0000, 1.0000), shape: luminaPrimitiveShapeFrom('box'), size: Vector3(30.0000, 300.0000, 2000.0000), color: Vector3(0.5451, 0.5765, 0.6314)),
          // Crate_A
          LuminaPrimitiveActor(key: const ValueKey('act_crate_a'), location: Vector3(-300.0000, 50.0000, -200.0000), rotation: luminaAuthoringRotation(0.0000, 0.0000, 0.0000), scale: Vector3(1.0000, 1.0000, 1.0000), shape: luminaPrimitiveShapeFrom('box'), size: Vector3(100.0000, 100.0000, 100.0000), color: Vector3(0.6902, 0.4784, 0.2706)),
          // Crate_B
          LuminaPrimitiveActor(key: const ValueKey('act_crate_b'), location: Vector3(-300.0000, 150.0000, -200.0000), rotation: luminaAuthoringRotation(0.0000, 0.0000, 0.0000), scale: Vector3(1.0000, 1.0000, 1.0000), shape: luminaPrimitiveShapeFrom('box'), size: Vector3(100.0000, 100.0000, 100.0000), color: Vector3(0.6902, 0.4784, 0.2706)),
          // Crate_C
          LuminaPrimitiveActor(key: const ValueKey('act_crate_c'), location: Vector3(300.0000, 30.0000, -300.0000), rotation: luminaAuthoringRotation(0.0000, 0.0000, 0.0000), scale: Vector3(1.0000, 1.0000, 1.0000), shape: luminaPrimitiveShapeFrom('box'), size: Vector3(140.0000, 60.0000, 140.0000), color: Vector3(0.5569, 0.3843, 0.2118)),
          // Pillar
          LuminaPrimitiveActor(key: const ValueKey('act_pillar'), location: Vector3(400.0000, 150.0000, 400.0000), rotation: luminaAuthoringRotation(0.0000, 0.0000, 0.0000), scale: Vector3(1.0000, 1.0000, 1.0000), shape: luminaPrimitiveShapeFrom('cylinder'), size: Vector3(80.0000, 300.0000, 80.0000), color: Vector3(0.6588, 0.6784, 0.7216)),
        ]);
}

/// Applies the level environment (post-process) when play begins,
/// and — when the level authors a PlayerStart — makes sure the game
/// mode is installed and the local player is logged in and possessed.
class _LDefaultLevelScript extends LuminaLevelScriptActor {
  _LDefaultLevelScript() : super(key: const ValueKey('L_DefaultLevel_script'));

  /// The controller created by the game mode at begin play.
  LuminaPlayerController? playerController;

  @override
  void onBeginPlay() {
    super.onBeginPlay();
    final w = world;
    if (w == null) return;
    if (w.getSubsystem<LuminaCollisionSubsystem>() == null) {
      w.registerSubsystem(LuminaCollisionSubsystem());
    }
    if (w.getSubsystem<LuminaInputSubsystem>() == null) {
      w.registerSubsystem(LuminaInputSubsystem());
    }
    var mode = w.gameMode;
    if (mode == null) {
      mode = ArenaGameMode();
      w.gameMode = mode;
      mode.initGame(w);
    }
    playerController = mode.login();
  }

  @override
  void onTick(double deltaTime) {
    super.onTick(deltaTime);
    playerController?.onTick(deltaTime);
  }
}
