class_name SettingDef
extends RefCounted
## One server setting: its type, its bounds, who may change it, and what it is
## for. Schema, not value — `ServerSettings` holds the values.
##
## **Why this is declared in code and not as one `.tres` per setting**, when
## CLAUDE.md §2 says tuning numbers belong in a resource. That rule is about the
## *game*: numbers a designer tunes in the inspector, where the resource IS the
## editing surface. A server setting is edited by an operator on a headless box
## with no Godot on it, so its editing surface is a text file and a console
## command — and what a `.tres` cannot carry is exactly what makes those two work:
## a range to validate against, a permission to check, a sentence to print in
## `help`, and the knowledge that changing it needs a restart. Seventy of those
## as seventy resource files would also be seventy files nobody could read as a
## list.
##
## So: the schema is here, in one place, and the *values* live in `server.cfg`,
## which is an ordinary INI an operator can open. Both `set` on the console and
## the settings tab of the in-game admin panel are generated from this — neither
## has a hand-written list of what exists, which is why adding a setting is one
## line and never two.

## Dotted, `section/key`. The section becomes the INI section, so it is also how
## the file groups itself for a human reading it.
var key: String = ""
## A Variant TYPE_* constant. Only BOOL, INT, FLOAT and STRING are supported —
## anything structured (the room list, the ban list) is its own file, because a
## nested value in an INI is a thing operators cannot edit safely.
var type: int = TYPE_STRING
var default_value: Variant = ""
## One line, printed by `help <key>`, shown under the field in the admin panel,
## and written above the key as a comment when the file is generated.
var description: String = ""

## Numeric bounds, inclusive. Ignored for other types.
var minimum: float = -INF
var maximum: float = INF
## When non-empty, the value must be one of these. Turns a text field into a
## dropdown in the admin panel and gives `set` something to say when refused.
var choices: PackedStringArray = PackedStringArray()

## Read at boot and never again. The admin panel marks these, and `set` says so
## rather than pretending the change took effect — a port that silently did not
## move is worse than one that refused to.
var requires_restart: bool = false
## The permission node needed to change it. Reading is a lesser right than
## writing, and some of these are read-protected too — see `secret`.
var permission: String = "server.settings.write"
## Never printed, never sent to a client, never written to a log: passwords and
## tokens. The admin panel shows "(set)" or "(unset)" and offers to replace it.
var secret: bool = false


static func make(setting_key: String, setting_type: int, value: Variant,
		text: String) -> SettingDef:
	var def := SettingDef.new()
	def.key = setting_key
	def.type = setting_type
	def.default_value = value
	def.description = text
	return def


func with_range(low: float, high: float) -> SettingDef:
	minimum = low
	maximum = high
	return self


func with_choices(options: Array[String]) -> SettingDef:
	choices = PackedStringArray(options)
	return self


func needs_restart() -> SettingDef:
	requires_restart = true
	return self


func as_secret() -> SettingDef:
	secret = true
	return self


func section() -> String:
	return key.get_slice("/", 0)


func leaf() -> String:
	return key.substr(key.find("/") + 1)


## Parse a value out of text — a console argument, an INI entry, a field in the
## admin panel — and say why if it will not fit. Returns `[ok, value, reason]`.
##
## One parser for all three front-ends on purpose. A setting that accepts "yes"
## on the console and refuses it in the file is a setting that will be reported
## as a bug by somebody who was right.
func parse(text: String) -> Array:
	var trimmed := text.strip_edges()
	match type:
		TYPE_BOOL:
			return _parse_bool(trimmed)
		TYPE_INT:
			return _parse_int(trimmed)
		TYPE_FLOAT:
			return _parse_float(trimmed)
	return _parse_text(trimmed)


func _parse_bool(text: String) -> Array:
	var lowered := text.to_lower()
	if lowered in ["true", "yes", "on", "1"]:
		return [true, true, ""]
	if lowered in ["false", "no", "off", "0"]:
		return [true, false, ""]
	return [false, null, "expected true/false"]


func _parse_int(text: String) -> Array:
	if not text.is_valid_int():
		return [false, null, "expected a whole number"]
	return _bounded(float(text.to_int()), text.to_int())


func _parse_float(text: String) -> Array:
	if not text.is_valid_float():
		return [false, null, "expected a number"]
	return _bounded(text.to_float(), text.to_float())


func _parse_text(text: String) -> Array:
	if not choices.is_empty() and not choices.has(text):
		return [false, null, "expected one of: %s" % ", ".join(choices)]
	return [true, text, ""]


func _bounded(as_float: float, value: Variant) -> Array:
	if as_float < minimum or as_float > maximum:
		return [false, null, "must be between %s and %s" % [_bound(minimum), _bound(maximum)]]
	return [true, value, ""]


func _bound(v: float) -> String:
	if v == INF:
		return "∞"
	if v == -INF:
		return "-∞"
	return str(v) if type == TYPE_FLOAT else str(int(v))


## How the value should be shown. Secrets never reveal themselves, not even to
## the owner: a value that can be read back out of a log is a value that leaks.
func display(value: Variant) -> String:
	if secret:
		return "(set)" if str(value) != "" else "(unset)"
	return str(value)
