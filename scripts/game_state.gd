extends Node
## Autoload singleton that persists progress across scene reloads.

const MAX_LEVEL: int = 3
const GAME_SCENE: String = "res://scenes/game.tscn"

var current_level: int = 1

func is_final_level() -> bool:
	return current_level >= MAX_LEVEL

## Advance to the next level and reload the gameplay scene.
## Caller is responsible for checking is_final_level() first (the final
## level shows a You Win overlay instead of advancing).
func next_level() -> void:
	current_level += 1
	get_tree().paused = false
	get_tree().change_scene_to_file(GAME_SCENE)

## Reset to level 1 and reload (used by the Game Over / You Win restart button).
func restart() -> void:
	current_level = 1
	get_tree().paused = false
	get_tree().change_scene_to_file(GAME_SCENE)
