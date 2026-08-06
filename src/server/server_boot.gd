class_name ServerBoot
extends Object
## Which of the three programs in this binary this process is, and what it was
## told on the command line.
##
## One binary does all three jobs. `thepit --server` is the dedicated server,
## `thepit --directory` is the service that lists dedicated servers, and the same
## executable with no flag is the game. A dedicated-server export preset also
## sets the `dedicated_server` feature, so a build made specifically to be a
## server needs no flag at all — but the flag keeps working, which is what makes
## it possible to run either out of a source checkout with nothing exported:
##
##   godot --headless --path . -- --server
##   godot --headless --path . -- --directory
##
## Everything after `--` is ours; an exported binary's own arguments are read
## too, so both invocations behave the same.

const SERVER_SCENE := "res://scenes/server/Server.tscn"
const DIRECTORY_SCENE := "res://scenes/server/Directory.tscn"


## Should this process be a server rather than the game?
static func wanted() -> bool:
	return flag("server") or OS.has_feature("dedicated_server")


## Should it be the directory service instead? Checked before `wanted()`, so
## `--server --directory` is the directory rather than an argument that quietly
## does nothing.
static func directory_wanted() -> bool:
	return flag("directory")


## Every argument this process was given, from both places Godot keeps them.
## `--` separates the engine's from ours when running from a checkout; an
## exported binary has no separator and puts everything in the first list.
static func arguments() -> PackedStringArray:
	var out := PackedStringArray(OS.get_cmdline_user_args())
	out.append_array(OS.get_cmdline_args())
	return out


static func flag(name: String) -> bool:
	return arguments().has("--%s" % name)


## `--key value` or `--key=value`, both accepted, because both are what people
## type. Returns `fallback` when it was not given.
static func argument(name: String, fallback: String = "") -> String:
	var args := arguments()
	var flagged := "--%s" % name
	for i in args.size():
		if args[i] == flagged and i + 1 < args.size():
			return args[i + 1]
		if args[i].begins_with("%s=" % flagged):
			return args[i].substr(flagged.length() + 1)
	return fallback


## `--set key=value`, repeatable. Overrides anything in server.cfg for this run
## and is not written back, so a temporary change stays temporary:
##
##   thepit --server --set network/port=24570 --set log/level=debug
##
## The one that earns its keep is `--set storage/dir=...` on a machine running
## two servers out of one install.
static func overrides() -> Array[String]:
	var out: Array[String] = []
	var args := arguments()
	for i in args.size():
		if args[i] == "--set" and i + 1 < args.size():
			out.append(args[i + 1])
		elif args[i].begins_with("--set="):
			out.append(args[i].substr(6))
	return out


## Resolve a configured path against the folder the program lives in, not
## against whatever the working directory happens to be. A server started by a
## service manager, a shortcut or a scheduled task gets a working directory
## nobody chose, and "server-data appeared somewhere else this time" is not a
## thing an operator should ever have to debug.
static func absolute(wanted: String) -> String:
	if wanted.is_absolute_path():
		return wanted
	var base := ProjectSettings.globalize_path("res://")
	return base.path_join(wanted.trim_prefix("./")).simplify_path()


## What `--help` prints. Kept here next to the parsing so the two cannot drift.
static func usage() -> String:
	return """
The PIT: Ascension — dedicated server and server directory

  thepit --server [options]
  thepit --directory [options]
  godot --headless --path . -- --server [options]

  --server              run as a dedicated server rather than the game
  --directory           run as the service that LISTS dedicated servers, so
                        they appear in the browser inside the game
  --data <dir>          where accounts, bans, logs and server.cfg live
                        (default: the storage/dir setting)
  --port <n>            shorthand for --set network/port=<n>, or, on the
                        directory, --set listing/port=<n>
  --set <key>=<value>   override one setting for this run only; repeatable
  --help                this

Everything else is configured in server.cfg, which is written out on the first
run with every setting and a description of each. Change it and restart, or use
`set <key> <value>` on the console to change it while running. The two programs
write different files: run each in its own --data directory.
""".strip_edges()
