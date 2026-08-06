class_name ChatService
extends Node
## Chat, and the reason mute exists.
##
## The game had no chat before there was a server to moderate, and it is here
## because moderation without it is a set of verbs with nothing to apply them to:
## you cannot mute somebody who cannot speak. It is deliberately small — a line
## of text, to the room you are in or to the whole server — and every part of it
## can be turned off by an operator who does not want it (`moderation/chat`).
##
## Four things happen to a message before anybody sees it, in this order, and the
## order is the point: refused first, then trimmed, then filtered, then
## delivered. A muted player's message is never filtered, never logged as
## content, and never reaches a room — the cheapest check comes first because a
## flood is exactly the case where the later ones are expensive.

const SCOPE_ROOM := "room"
const SCOPE_SERVER := "server"
const SCOPE_SYSTEM := "system"

var server: PitServer

## Per-account buckets. Keyed by account rather than peer so that reconnecting
## does not reset somebody's allowance.
var _limit: RateLimiter = RateLimiter.make(0.6, 6.0)


func _ready() -> void:
	_configure()
	server.settings.changed.connect(func(key: String, _v: Variant) -> void:
		if key.begins_with("moderation/chat"):
			_configure())


func _configure() -> void:
	var per_ten := float(server.settings.get_int("moderation/chat_per_10s"))
	_limit.configure(per_ten / 10.0, per_ten)


## Somebody typed something. Returns quietly on every refusal — the sender is
## told, and nobody else learns that they tried.
func say(peer: ServerPeer, raw: String) -> void:
	if not server.settings.get_bool("moderation/chat"):
		server.hub_notice(peer.peer_id, "CHAT IS OFF ON THIS SERVER")
		return
	var refusal := _refusal_for(peer, raw)
	if refusal != "":
		server.hub_notice(peer.peer_id, refusal)
		return

	var text := _trim(raw)
	var filtered := _filter(peer, text)
	if filtered.is_empty():
		server.hub_notice(peer.peer_id, "THAT MESSAGE WAS NOT SENT")
		return

	var entry := _entry(SCOPE_ROOM, peer.name_text(), filtered["text"], peer.account.role)
	_deliver_to_room(peer.room_id, entry)
	if server.settings.get_bool("moderation/log_chat"):
		server.logger.info("chat", "[room %d] %s: %s"
			% [peer.room_id, peer.name_text(), filtered["text"]])
	if filtered["warn"]:
		server.moderation.auto_warn(peer, "language", "the chat filter")


func _refusal_for(peer: ServerPeer, raw: String) -> String:
	if peer.account == null or not peer.may(Permissions.CHAT_SEND):
		return "YOU MAY NOT SPEAK HERE"
	if peer.account.is_muted():
		return "YOU ARE MUTED"
	if peer.room_id == 0:
		return "JOIN A ROOM FIRST"
	if raw.strip_edges() == "":
		return " "
	if not peer.may(Permissions.CHAT_BYPASS_FILTER) and not _limit.allow(peer.account.id):
		return "SLOW DOWN"
	return ""


## Cut to length, and strip the control characters that would otherwise let one
## message look like several, or like a line the server printed.
func _trim(raw: String) -> String:
	var limit := server.settings.get_int("moderation/chat_max_length")
	var out := ""
	for i in raw.length():
		var code := raw.unicode_at(i)
		if code >= 32 and code != 127:
			out += raw[i]
	return out.strip_edges().substr(0, limit)


## Returns {"text": String, "warn": bool}, or empty to drop the message.
func _filter(peer: ServerPeer, text: String) -> Dictionary:
	var words := server.settings.get_list("moderation/word_filter")
	if words.is_empty() or peer.may(Permissions.CHAT_BYPASS_FILTER):
		return {"text": text, "warn": false}
	var lowered := text.to_lower()
	var hit := false
	var masked := text
	for word in words:
		if word == "" or not lowered.contains(word):
			continue
		hit = true
		masked = _mask(masked, word)
	if not hit:
		return {"text": text, "warn": false}
	match server.settings.get_text("moderation/word_filter_action"):
		"block":
			return {}
		"warn":
			return {"text": text, "warn": true}
		_:
			return {"text": masked, "warn": false}


func _mask(text: String, word: String) -> String:
	var out := text
	var stars := "*".repeat(word.length())
	var at := out.to_lower().find(word)
	while at >= 0:
		out = out.substr(0, at) + stars + out.substr(at + word.length())
		at = out.to_lower().find(word, at + word.length())
	return out


func _entry(scope: String, who: String, text: String, who_role: String) -> Dictionary:
	return {
		"scope": scope,
		"from": who,
		"role": who_role,
		"text": text,
		"at": Time.get_datetime_string_from_system(false, true),
	}


func _deliver_to_room(room_id: int, entry: Dictionary) -> void:
	var room := server.rooms.get_room(room_id)
	if room == null:
		return
	room.remember(entry, server.settings.get_int("moderation/chat_history"))
	for peer_id in room.members:
		Hub.rpc_id(peer_id, &"chat_message", entry)


## An announcement to everybody on the server, from a moderator or the console.
func announce(from: String, text: String) -> void:
	var entry := _entry(SCOPE_SERVER, from, text, Permissions.ROLE_ADMIN)
	for peer_id in server.peers:
		Hub.rpc_id(peer_id, &"chat_message", entry)
	server.logger.info("chat", "[announce] %s: %s" % [from, text])


## The server speaking for itself: somebody was kicked, a run is about to start.
## Deliberately a different scope so a client can style it as not being a person.
func system(room_id: int, text: String) -> void:
	var entry := _entry(SCOPE_SYSTEM, "server", text, Permissions.ROLE_OWNER)
	if room_id == 0:
		for peer_id in server.peers:
			Hub.rpc_id(peer_id, &"chat_message", entry)
		return
	_deliver_to_room(room_id, entry)


## What a player is shown on walking into a room, so that arriving mid-
## conversation is not arriving in silence.
func send_backlog(peer_id: int, room_id: int) -> void:
	var room := server.rooms.get_room(room_id)
	if room == null or room.chat.is_empty():
		return
	Hub.rpc_id(peer_id, &"chat_backlog", room.chat.duplicate())
