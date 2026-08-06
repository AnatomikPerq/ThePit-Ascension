class_name DirectoryDef
extends Resource
## Which directory a copy of the game reads its server list from.
##
## A resource rather than a constant in a script because it is a setting of the
## build, not of the code: whoever ships this decides where the list lives, and
## somebody running their own community should be able to point their players at
## their own without touching a line of GDScript. It lives at
## `data/net/directory.tres`, which the content fingerprint deliberately skips —
## the list a client reads has nothing to do with whether it can simulate the
## same pit as a server, and forcing everyone to update because a URL moved would
## be exactly backwards.
##
## Empty `url` is a working configuration and not a mistake: the browser then
## shows what is on the local network and what the player has saved, which is
## every server that ever existed before a directory did.

const PATH := "res://data/net/directory.tres"

@export var url: String = ""
## Off means the game never makes an HTTP request at all. For a build that must
## not talk to anything the player did not ask it to.
@export var enabled: bool = true
## Shown in the browser when the list is empty, so that "no servers" and "no
## directory configured" are not the same blank screen.
@export_multiline var about: String = ""

static var _shipped: DirectoryDef


## What this build ships with. Loaded once — it is read every time the browser
## refreshes, and re-reading a resource per refresh is the sort of thing that is
## free until it is not.
static func shipped() -> DirectoryDef:
	if _shipped == null:
		_shipped = ResourceLoader.load(PATH) as DirectoryDef
	if _shipped == null:
		_shipped = DirectoryDef.new()
	return _shipped


## The base URL actually in force, with the two overrides applied in order of how
## deliberate they are: what the build ships with, then what the player wrote in
## their own settings file, then what was passed on the command line. The last is
## how the probe in tools/ points a real client at a real directory it started a
## second ago.
static func resolve(saved: String = "") -> String:
	var chosen := shipped().url
	if saved.strip_edges() != "":
		chosen = saved
	var argued := ServerBoot.argument("directory-url")
	if argued != "":
		chosen = argued
	return chosen.strip_edges().rstrip("/")


static func url_for(base: String, path: String) -> String:
	return "%s%s" % [base.rstrip("/"), path]
