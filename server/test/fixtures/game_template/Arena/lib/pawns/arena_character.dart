// ArenaCharacter — your first-person character.
//
// Lumina Studio generated this file once, when the project was created. It is
// ordinary source you own: the editor's level and main.dart regeneration never
// rewrites it. Extend it inside the BEGIN/END USER CODE regions (or anywhere
// else you like).
//
// ignore_for_file: prefer_const_constructors

import 'dart:math' as math;

import 'package:lumina/lumina_runtime.dart';
import 'package:vector_math/vector_math_64.dart';

/// The input actions the `Gameplay` mapping context drives. They mirror the
/// `IA_Move` / `IA_Look` / `IA_Jump` entries in arena.lmproject,
/// which you can rebind in Project Settings > Input.
const LuminaInputAction iaMove = LuminaInputAction('IA_Move', valueType: InputValueType.axis2D);
const LuminaInputAction iaLook = LuminaInputAction('IA_Look', valueType: InputValueType.axis2D);
const LuminaInputAction iaJump = LuminaInputAction('IA_Jump');

/// Places a key's raw 1D value onto one axis of a 2D action, scaled — the
/// Enhanced Input "swizzle axis" + "scalar" pair in a single modifier.
class AxisPlacementModifier extends LuminaInputModifier {
  final double toX;
  final double toY;

  const AxisPlacementModifier({this.toX = 0.0, this.toY = 0.0});

  @override
  LuminaInputActionValue modify(LuminaInputActionValue rawValue, double deltaTime) {
    final raw = rawValue.asAxis1D;
    return LuminaInputActionValue.raw(rawValue.type, raw * toX, raw * toY, 0.0);
  }
}

/// Builds the `Gameplay` mapping context: WASD on the move axes, the mouse on
/// the look axes, Space to jump.
LuminaInputMappingContext buildGameplayMappingContext() {
  final context = LuminaInputMappingContext();
  context.mapKey(LuminaKey.keyW, iaMove, modifiers: const [AxisPlacementModifier(toY: 1.0)]);
  context.mapKey(LuminaKey.keyS, iaMove, modifiers: const [AxisPlacementModifier(toY: -1.0)]);
  context.mapKey(LuminaKey.keyA, iaMove, modifiers: const [AxisPlacementModifier(toX: -1.0)]);
  context.mapKey(LuminaKey.keyD, iaMove, modifiers: const [AxisPlacementModifier(toX: 1.0)]);
  context.mapKey(LuminaKey.mouseX, iaLook, modifiers: const [AxisPlacementModifier(toX: 1.0)]);
  context.mapKey(LuminaKey.mouseY, iaLook, modifiers: const [AxisPlacementModifier(toY: -1.0)]);
  context.mapKey(LuminaKey.keySpace, iaJump);
  return context;
}

/// The player character spawned by `ArenaGameMode` at the level's
/// `PlayerStart`.
class ArenaCharacter extends LuminaCharacter {
  /// The eye. Sits at [baseEyeHeight] above the capsule origin.
  late final LuminaCameraComponent cameraComponent;

  /// Input component carrying this character's action bindings.
  late final LuminaInputComponent inputComponent;

  /// Degrees of yaw/pitch per pixel of mouse movement.
  double lookSensitivity = 0.15;

  // BEGIN USER CODE: fields
  // END USER CODE

  ArenaCharacter({super.key, super.location, super.rotation}) : super(baseEyeHeight: 160.0) {
    characterMovement.maxWalkSpeed = 600.0;
    characterMovement.jumpZVelocity = 500.0;
    characterMovement.airControl = 0.35;
    // Full-height jumps however briefly Jump is held.
    characterMovement.jumpCutMultiplier = 1.0;
    bUseControllerRotationYaw = true;

    cameraComponent = LuminaCameraComponent(
      location: Vector3(0.0, baseEyeHeight, 0.0),
    )..isActive = true;
    addComponent(cameraComponent);

    // BEGIN USER CODE: constructor
    // END USER CODE
  }

  @override
  void onBeginPlay() {
    super.onBeginPlay();
    onSetupInput();
  }

  /// Registers the gameplay mapping context and binds the actions. Called once
  /// when play begins; override or extend to add your own bindings.
  void onSetupInput() {
    final currentWorld = world;
    if (currentWorld == null) return;

    var subsystem = currentWorld.getSubsystem<LuminaInputSubsystem>();
    subsystem ??= currentWorld.registerSubsystem(LuminaInputSubsystem());
    subsystem.addMappingContext(buildGameplayMappingContext());

    inputComponent = LuminaInputComponent();
    addComponent(inputComponent);

    inputComponent.bindAction(iaMove, TriggerState.triggered, onMove);
    inputComponent.bindAction(iaLook, TriggerState.triggered, onLook);
    inputComponent.bindAction(iaJump, TriggerState.started, onJump);
    inputComponent.bindAction(iaJump, TriggerState.completed, onStopJumping);

    // BEGIN USER CODE: input
    // END USER CODE
  }

  /// Drives the character along the control rotation's forward/right axes.
  void onMove(LuminaInputActionValue value) {
    final axis = value.asAxis2D;
    if (axis.x == 0.0 && axis.y == 0.0) return;
    final yawRadians = (controller?.controlRotation.y ?? 0.0) * math.pi / 180.0;
    final forward = Vector3(math.sin(yawRadians), 0.0, -math.cos(yawRadians));
    final right = Vector3(math.cos(yawRadians), 0.0, math.sin(yawRadians));
    characterMovement.addInputVector(forward, axis.y);
    characterMovement.addInputVector(right, axis.x);
  }

  /// Feeds mouse deltas to the controller. Pitch is clamped to +/-89.9 by
  /// [LuminaPlayerController.onTick] — do not clamp it again here.
  void onLook(LuminaInputActionValue value) {
    final axis = value.asAxis2D;
    addControllerYawInput(axis.x * lookSensitivity);
    addControllerPitchInput(axis.y * lookSensitivity);
  }

  /// Jumps through the character movement component.
  void onJump(LuminaInputActionValue value) {
    jump();
  }

  /// Releases the jump (IA_Jump Completed).
  void onStopJumping(LuminaInputActionValue value) {
    characterMovement.stopJumping();
  }

  // BEGIN USER CODE: class_body
  // END USER CODE
}
