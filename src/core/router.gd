extends Node
## Router — the one place scenes are swapped and runs are started.
##
## It exists so a run can be PARAMETERIZED: change_scene_to_file() cannot set
## World.world_seed before _ready() generates the level, and the multiplayer
## host needs exactly that seam — every peer must start an identical run from
## a shared seed. Scene transitions also stop stepping on each other here:
## every swap lands unpaused, whatever state the old scene died in.
##
## Pause ownership stays split on purpose: World's run state machine owns
## pausing DURING a run; the router owns the boundary between scenes.

const MENU_SCENE := "res://scenes/MainMenu.tscn"
const WORLD_SCENE := "res://scenes/World.tscn"


func to_menu() -> void:
	_swap((load(MENU_SCENE) as PackedScene).instantiate())


## 0 = roll a fresh seed. The multiplayer host passes the shared one.
func start_run(world_seed: int = 0) -> void:
	var world: Node = (load(WORLD_SCENE) as PackedScene).instantiate()
	world.world_seed = world_seed
	_swap(world)


## Restart rolls a fresh layout, exactly like the pre-refactor reload did.
func restart_run() -> void:
	start_run(0)


func _swap(next: Node) -> void:
	# Deferred, like change_scene_to_file: the caller is usually deep inside
	# input handling or a signal from the scene about to be freed.
	_apply_swap.call_deferred(next)


func _apply_swap(next: Node) -> void:
	get_tree().paused = false
	var old := get_tree().current_scene
	if is_instance_valid(old):
		old.free()
	get_tree().root.add_child(next)
	get_tree().current_scene = next
