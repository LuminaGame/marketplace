// ArenaGameMode — the rules of your game.
//
// Lumina Studio generated this file once, when the project was created. It is
// ordinary source you own: the editor's level and main.dart regeneration never
// rewrites it.

import 'package:lumina/lumina_runtime.dart';

import '../pawns/arena_character.dart';

/// Spawns a [ArenaCharacter] at the level's `PlayerStart` and possesses it
/// with the local player's controller.
class ArenaGameMode extends LuminaGameMode {
  ArenaGameMode()
      : super(
          defaultPawnFactory: () => ArenaCharacter(),
          playerControllerFactory: () => LuminaPlayerController(playerName: 'Player'),
        );

  // BEGIN USER CODE: class_body
  // END USER CODE
}
