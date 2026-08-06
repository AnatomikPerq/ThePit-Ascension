class_name ServerAdminFeed
extends Object
## The same facts the console prints, as data a table can be built from.
##
## The admin panel could have run `players` and parsed the text back out, and
## that is exactly what this exists to avoid: a UI that scrapes its own server's
## console output breaks the first time a column is widened. The commands stay
## the operator's interface; this is the panel's.
##
## Every request is filtered by what the asker may see, here rather than in the
## panel. A client decides what to draw; it never decides what it is allowed to
## know.

const MAX_ROWS: int = 200


static func build(server: PitServer, peer: ServerPeer, kind: String,
		args: Dictionary) -> Dictionary:
	match kind:
		"overview":
			return _overview(server, peer)
		"players":
			return _players(server, peer)
		"rooms":
			return _rooms(server, peer)
		"settings":
			return _settings(server, peer)
		"bans":
			return _bans(server, peer)
		"accounts":
			return _accounts(server, peer, str(args.get("filter", "")))
	return _log(server, peer, int(args.get("lines", 60)))


static func _overview(server: PitServer, peer: ServerPeer) -> Dictionary:
	if not peer.may(Permissions.SERVER_STATUS):
		return {}
	return {
		"name": server.settings.get_text("server/name"),
		"motd": server.settings.get_text("server/motd"),
		"build": NetProtocol.build_id(),
		"status": server.status_line(),
		"uptime": int(server.uptime_seconds()),
		"players": server.peers.size(),
		"max_players": server.settings.get_int("network/max_players"),
		"rooms": server.rooms.count(),
		"max_rooms": server.settings.get_int("rooms/max_rooms"),
		"accounts": server.accounts.count(),
		"bans": server.bans.count(),
		"auth": server.settings.get_text("auth/mode"),
		"guard": server.settings.get_text("protection/movement_guard"),
		"may": _rights_summary(peer),
	}


## What the panel should offer at all. Sending it means a button that would only
## ever say "you may not do that" is never drawn.
static func _rights_summary(peer: ServerPeer) -> Dictionary:
	return {
		"kick": peer.may(Permissions.PLAYER_KICK),
		"ban": peer.may(Permissions.PLAYER_BAN),
		"mute": peer.may(Permissions.PLAYER_MUTE),
		"inspect": peer.may(Permissions.PLAYER_INSPECT),
		"rooms": peer.may(Permissions.ROOM_CLOSE_ANY),
		"settings_read": peer.may(Permissions.SERVER_SETTINGS_READ),
		"settings_write": peer.may(Permissions.SERVER_SETTINGS_WRITE),
		"accounts": peer.may(Permissions.ACCOUNT_LIST),
		"roles": peer.may(Permissions.ACCOUNT_ROLE),
		"log": peer.may(Permissions.SERVER_LOG),
		"stop": peer.may(Permissions.SERVER_STOP),
	}


static func _players(server: PitServer, peer: ServerPeer) -> Dictionary:
	if not peer.may(Permissions.PLAYER_LIST):
		return {}
	var may_inspect := peer.may(Permissions.PLAYER_INSPECT)
	var only_here := not server.settings.get_bool("moderation/staff_see_all_rooms") \
			and not peer.may(Permissions.PLAYER_INSPECT)
	var rows: Array = []
	for peer_id in server.peers:
		var other: ServerPeer = server.peers[peer_id]
		if only_here and other.room_id != peer.room_id:
			continue
		var row := other.info()
		# The address and the account id are the two things a player list must
		# not carry to somebody who may not inspect people.
		rows.append(row if may_inspect else ServerPeer.redact(row))
	return {"players": rows}


static func _rooms(server: PitServer, peer: ServerPeer) -> Dictionary:
	if not peer.may(Permissions.SERVER_STATUS):
		return {}
	var rows: Array = []
	for room_id in server.rooms.rooms:
		var room: Room = server.rooms.rooms[room_id]
		var row := room.info()
		row["members"] = room.members.size()
		row["world"] = room.world_name()
		row["running"] = room.running()
		rows.append(row)
	return {"rooms": rows}


static func _settings(server: PitServer, peer: ServerPeer) -> Dictionary:
	if not peer.may(Permissions.SERVER_SETTINGS_READ):
		return {}
	var rows: Array = []
	for key in server.settings.defs:
		var def: SettingDef = server.settings.defs[key]
		rows.append({
			"key": key,
			"section": def.section(),
			"type": def.type,
			# Never the raw value for a secret: the panel shows "(set)" and can
			# offer to replace it, which is all anybody needs.
			"value": def.display(server.settings.get_value(key)),
			"raw": "" if def.secret else str(server.settings.get_value(key)),
			"default": def.display(def.default_value),
			"description": def.description,
			"choices": Array(def.choices),
			"minimum": def.minimum if def.minimum != -INF else 0.0,
			"maximum": def.maximum if def.maximum != INF else 0.0,
			"bounded": def.minimum != -INF or def.maximum != INF,
			"restart": def.requires_restart,
			"secret": def.secret,
		})
	return {"settings": rows, "writable": peer.may(Permissions.SERVER_SETTINGS_WRITE)}


static func _bans(server: PitServer, peer: ServerPeer) -> Dictionary:
	if not peer.may(Permissions.PLAYER_UNBAN):
		return {}
	var rows: Array = []
	for entry in server.bans.all():
		rows.append(entry)
	return {"bans": rows.slice(0, MAX_ROWS)}


static func _accounts(server: PitServer, peer: ServerPeer, filter: String) -> Dictionary:
	if not peer.may(Permissions.ACCOUNT_LIST):
		return {}
	var rows: Array = []
	for account in server.accounts.search(filter, MAX_ROWS):
		rows.append({
			"name": account.name,
			"role": account.role,
			"last_seen": account.last_seen_at,
			"best_score": account.best_score,
			"runs": account.runs,
			"muted": account.is_muted(),
			"warnings": account.warnings,
			"online": server.online_named(account.id) != null,
		})
	return {"accounts": rows, "roles": Permissions.ROLES}


static func _log(server: PitServer, peer: ServerPeer, lines: int) -> Dictionary:
	if not peer.may(Permissions.SERVER_LOG):
		return {}
	var rows: Array = []
	for entry in server.logger.tail(clampi(lines, 1, ServerLog.RING_SIZE)):
		rows.append(ServerLog.format(entry))
	return {"log": rows}
