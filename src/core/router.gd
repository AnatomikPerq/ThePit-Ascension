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
const LOBBY_SCENE := "res://scenes/Lobby.tscn"
## The browser: everywhere there is to play, from the main menu's one
## MULTIPLAYER button.
const MULTIPLAYER_SCENE := "res://scenes/ui/MultiplayerMenu.tscn"
## Connecting to a dedicated server, and the room browser once connected.
const CONNECT_SCENE := "res://scenes/ui/ServerConnect.tscn"
const SERVER_LOBBY_SCENE := "res://scenes/ui/ServerLobby.tscn"

## A swap is built now and applied on the next idle frame, so two requests in
## the same frame — a button press and the key bound to the same thing, or the
## host's restart arriving while its own local call is still pending — would
## build two scenes and immediately free one of them. First request wins.
var _pending: bool = false


## A dedicated server is this same binary with `--server`, and the directory
## that lists servers is the same binary again with `--directory`, so the
## decision of which program this process is has to be made somewhere very
## early. Here is that place: the router is the only thing that swaps scenes,
## and it already runs before the main scene is looked at.
##
## The main scene is still the menu, and it is built and immediately replaced.
## That costs one frame on a server that will then run for weeks, and it buys a
## project with one main scene instead of two more that have to be kept in step
## with the first.
func _ready() -> void:
	if ServerBoot.flag("help"):
		print(ServerBoot.usage())
		get_tree().quit(0)
		return
	if ServerBoot.directory_wanted():
		_swap((load(ServerBoot.DIRECTORY_SCENE) as PackedScene).instantiate())
	elif ServerBoot.wanted():
		_swap((load(ServerBoot.SERVER_SCENE) as PackedScene).instantiate())


func to_menu() -> void:
	_swap((load(MENU_SCENE) as PackedScene).instantiate())


## The server browser. One button on the main menu leads here, and everything
## multiplayer is reachable from it.
func to_multiplayer() -> void:
	_swap((load(MULTIPLAYER_SCENE) as PackedScene).instantiate())


## Where a player goes to type a server address, or arrives with one already
## filled in after picking a row in the browser. Filled in BEFORE the swap: the
## scene reads these in `_ready()`, which runs when it enters the tree, so there
## is no window in which the form is drawn empty and then rewritten.
func to_server_connect(address: String = "", port: int = 0,
		server_name: String = "") -> void:
	var screen := (load(CONNECT_SCENE) as PackedScene).instantiate()
	if address != "":
		screen.prefill_address = address
		screen.prefill_port = port if port > 0 else NetProtocol.DEFAULT_PORT
		screen.prefill_name = server_name
	_swap(screen)


## The room browser on a dedicated server, and the room once you are in one.
## Both are the same scene: they are one screen with two halves, and swapping
## between them would throw away the chat that runs down the side of both.
func to_server_lobby() -> void:
	_swap((load(SERVER_LOBBY_SCENE) as PackedScene).instantiate())


func to_lobby() -> void:
	_swap((load(LOBBY_SCENE) as PackedScene).instantiate())


## 0 = roll a fresh seed. A session passes the shared one, and the session it
## belongs to.
##
## The world's NODE NAME comes from the room. Node paths are how the replication
## layer addresses everything, and a dedicated server holds several worlds in one
## tree — so room 3's world is `/root/World3` on the server and `/root/World3` on
## every client in that room, and a packet for one room can no longer be
## delivered to another. Solo play and a peer-to-peer host are room 0, which is
## the plain `World` the game has always used.
func start_run(world_seed: int = 0, session: NetSession = null) -> void:
	var world: Node = (load(WORLD_SCENE) as PackedScene).instantiate()
	world.world_seed = world_seed
	if session != null:
		world.session = session
		world.name = session.world_name()
	_swap(world)


## Restart rolls a fresh layout, exactly like the pre-refactor reload did.
func restart_run() -> void:
	start_run(0)


func _swap(next: Node) -> void:
	if _pending:
		next.free()
		return
	_pending = true
	# Deferred, like change_scene_to_file: the caller is usually deep inside
	# input handling or a signal from the scene about to be freed.
	_apply_swap.call_deferred(next)


func _apply_swap(next: Node) -> void:
	_pending = false
	get_tree().paused = false
	var old := get_tree().current_scene
	if is_instance_valid(old):
		old.free()
	get_tree().root.add_child(next)
	get_tree().current_scene = next
