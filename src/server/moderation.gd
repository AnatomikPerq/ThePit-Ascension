class_name Moderation
extends RefCounted
## Kick, ban, mute, warn, move — the verbs, in one place.
##
## They live here rather than in the commands that call them because there are
## three ways to reach every one of them (the console, the remote console, the
## admin panel in the game) and the rules must not be three implementations. The
## commands parse; this decides.
##
## Two rules run through all of it:
##
## - **You cannot act on somebody at or above your own rank.** Without it, two
##   admins can ban each other, and a moderator can remove the owner. The console
##   is above everyone, because an operator locked out of their own server by
##   somebody they promoted would have no way back in.
## - **Every action is written down**: who did it, to whom, and the reason they
##   gave. A moderation record that cannot answer those three questions turns
##   into an argument later.

var server: PitServer


func _init(owner: PitServer) -> void:
	server = owner


## Common check for every verb below. Returns "" or the refusal.
func may_act_on(caller: CommandCaller, target: ServerPeer) -> String:
	if target == null:
		return "nobody by that name is connected"
	if target.peer_id == caller.peer_id:
		return "that is you"
	if target.account != null and target.account.rank() >= caller.rank():
		return "%s outranks you (or matches you)" % target.name_text()
	return ""


func kick(caller: CommandCaller, target: ServerPeer, reason: String) -> String:
	var refusal := may_act_on(caller, target)
	if refusal != "":
		return refusal
	var text := reason if reason != "" else "no reason given"
	server.chat.system(target.room_id, "%s was removed by %s — %s"
		% [target.name_text(), caller.label, text])
	server.kick(target.peer_id, text)
	_record("kick", caller, target.name_text(), text, 0.0)
	return ""


## `minutes` of 0 is permanent. A ban applies to the account; whether it also
## follows the address is `moderation/ban_evasion_by_ip`, which is a trade an
## operator makes knowingly — see docs/SERVER.md.
func ban(caller: CommandCaller, target: ServerPeer, reason: String,
		minutes: float) -> String:
	var refusal := may_act_on(caller, target)
	if refusal != "":
		return refusal
	var text := reason if reason != "" else "no reason given"
	var subject := target.account.id if target.account != null else target.name_text()
	server.bans.add(subject, BanList.KIND_ACCOUNT, text, caller.label, minutes)
	if server.settings.get_bool("moderation/ban_evasion_by_ip") and target.address != "":
		server.bans.add(target.address, BanList.KIND_ADDRESS,
			"with %s" % subject, caller.label, minutes)
	server.bans.save()
	server.chat.system(target.room_id, "%s was banned — %s" % [target.name_text(), text])
	server.kick(target.peer_id, "banned: %s" % text)
	_record("ban", caller, target.name_text(), text, minutes)
	return ""


## Ban somebody who is not connected, by account name. The common case after the
## fact: a report comes in about somebody who has already left.
func ban_absent(caller: CommandCaller, account_name: String, reason: String,
		minutes: float) -> String:
	var account := server.accounts.find(account_name)
	if account == null:
		return "no account called '%s' — ban a connected player by name instead" \
			% account_name
	if account.rank() >= caller.rank():
		return "%s outranks you (or matches you)" % account.name
	var text := reason if reason != "" else "no reason given"
	server.bans.add(account.id, BanList.KIND_ACCOUNT, text, caller.label, minutes)
	if server.settings.get_bool("moderation/ban_evasion_by_ip") and account.last_address != "":
		server.bans.add(account.last_address, BanList.KIND_ADDRESS,
			"with %s" % account.id, caller.label, minutes)
	server.bans.save()
	_record("ban", caller, account.name, text, minutes)
	return ""


func unban(caller: CommandCaller, subject: String) -> String:
	var removed := server.bans.remove(Account.canonical(subject))
	# Addresses are not lower-cased, so try the raw form too.
	if server.bans.remove(subject):
		removed = true
	if not removed:
		return "'%s' is not banned" % subject
	server.bans.save()
	_record("unban", caller, subject, "", 0.0)
	return ""


func mute(caller: CommandCaller, target: ServerPeer, minutes: float,
		reason: String) -> String:
	var refusal := may_act_on(caller, target)
	if refusal != "":
		return refusal
	target.account.mute_for(minutes)
	if not target.account.guest:
		server.accounts.touch()
	var how := "until it is lifted" if minutes <= 0.0 else "for %g minutes" % minutes
	server.hub_notice(target.peer_id, "YOU HAVE BEEN MUTED %s" % how.to_upper())
	_record("mute", caller, target.name_text(), reason, minutes)
	return ""


func unmute(caller: CommandCaller, target: ServerPeer) -> String:
	if target == null:
		return "nobody by that name is connected"
	target.account.muted_until = 0
	if not target.account.guest:
		server.accounts.touch()
	server.hub_notice(target.peer_id, "YOU CAN SPEAK AGAIN")
	_record("unmute", caller, target.name_text(), "", 0.0)
	return ""


## A warning is a countdown, not a punishment: enough of them and the player is
## removed, and `moderation/warnings_before_kick` says how many. A guest's
## warnings live only as long as their connection, which is a real limitation and
## the reason to run a server in `account` mode if warnings are to mean anything.
func warn(caller: CommandCaller, target: ServerPeer, reason: String) -> String:
	var refusal := may_act_on(caller, target)
	if refusal != "":
		return refusal
	_apply_warning(target, reason, caller.label)
	return ""


func _apply_warning(target: ServerPeer, reason: String, by: String) -> void:
	target.session_warnings += 1
	if target.account != null and not target.account.guest:
		target.account.warnings += 1
		server.accounts.touch()
	var total := target.session_warnings \
			+ (target.account.warnings if target.account != null and not target.account.guest
				else 0)
	var limit := server.settings.get_int("moderation/warnings_before_kick")
	server.hub_notice(target.peer_id, "WARNING: %s" % reason.to_upper())
	server.logger.info("mod", "warned %s (%d) — %s by %s"
		% [target.name_text(), total, reason, by])
	if limit > 0 and total >= limit:
		server.kick(target.peer_id, "too many warnings")


## The path the chat filter uses: not a moderator's decision, so it takes no
## CommandCaller and cannot be refused on rank.
func auto_warn(target: ServerPeer, reason: String, by: String) -> void:
	_apply_warning(target, reason, by)


func move(caller: CommandCaller, target: ServerPeer, room_id: int) -> String:
	var refusal := may_act_on(caller, target)
	if refusal != "":
		return refusal
	if server.rooms.get_room(room_id) == null:
		return "no room #%d" % room_id
	server.rooms.leave(target.peer_id, "")
	# Moved by staff, so the password and a full room do not apply — the whole
	# point of the verb is to put somebody somewhere they were not going.
	var problem := server.rooms.join(target.peer_id, room_id, "",
		Game.default_character_id())
	if problem != "":
		return problem
	server.hub_notice(target.peer_id, "YOU WERE MOVED TO ROOM #%d" % room_id)
	_record("move", caller, target.name_text(), "to room %d" % room_id, 0.0)
	return ""


func _record(action: String, caller: CommandCaller, subject: String,
		reason: String, minutes: float) -> void:
	var duration := ""
	if minutes > 0.0:
		duration = " for %g minutes" % minutes
	elif action in ["ban", "mute"]:
		duration = " permanently"
	server.logger.info("mod", "%s %s%s by %s%s" % [
		action, subject, duration, caller.label,
		" — %s" % reason if reason != "" else ""])
