class_name VerifyKey
extends RefCounted
## One verification key: the thing the developer hands a host so that their
## server wears a badge in the browser.
##
## A key is an `id` and a `secret`. The id travels in every announce; the secret
## never travels at all — it signs the announce (see DirectoryProtocol.canonical)
## and the directory checks the signature against its own copy. So a key cannot
## be lifted off the wire, and an announce cannot be replayed onto a different
## machine, because the address is inside what was signed.
##
## The secret is shown exactly once, when the key is issued. It is stored here
## because HMAC needs it on both sides — which is the honest trade for "the
## secret never travels", and it is why `keys.json` lives on the directory's own
## box and nowhere else. Losing it means reissuing keys, not losing accounts.

## Bumped only if the stored shape changes.
const FORMAT: int = 1

var id: String = ""
var secret: String = ""
## Which badge this key confers. One of DirectoryProtocol.BADGES.
var badge: String = DirectoryProtocol.BADGE_VERIFIED
## Who it was given to. For the developer's own records; never sent to a client.
var label: String = ""
## What the badge's tooltip says. Empty falls back to the badge's own wording,
## so a key issued in a hurry still explains itself.
var note: String = ""
## When set, the key only works for a server announcing this exact address. A
## leaked key then cannot move somebody else's badge onto another machine, which
## is the failure this is here for.
var bind_address: String = ""

var issued_at: int = 0
var last_used: int = 0
var uses: int = 0
var revoked: bool = false
var revoked_reason: String = ""


## A fresh key. The id is public and prefixed so that one found in a config file
## is recognisable for what it is; the secret is 32 random bytes.
static func issue(kind: String, who: String, hover: String = "",
		bind: String = "") -> VerifyKey:
	var key := VerifyKey.new()
	key.id = "pitk_%s" % NetCrypto.random_bytes(6).hex_encode()
	key.secret = NetCrypto.random_bytes(32).hex_encode()
	key.badge = kind if DirectoryProtocol.is_badge(kind) \
			else DirectoryProtocol.BADGE_VERIFIED
	key.label = who
	key.note = hover
	key.bind_address = bind.strip_edges().to_lower()
	key.issued_at = int(Time.get_unix_time_from_system())
	return key


func usable() -> bool:
	return not revoked and id != "" and secret != ""


## Whether this key may speak for that address. An unbound key may speak for any.
func may_claim(address: String) -> bool:
	if bind_address == "":
		return true
	return address.strip_edges().to_lower() == bind_address


func hover_text() -> String:
	return DirectoryProtocol.badge_note(badge, note)


func describe() -> String:
	var parts := PackedStringArray([DirectoryProtocol.badge_label(badge)])
	if label != "":
		parts.append(label)
	if bind_address != "":
		parts.append("bound to %s" % bind_address)
	if revoked:
		parts.append("REVOKED%s" % ("" if revoked_reason == "" else ": " + revoked_reason))
	parts.append("%d use%s" % [uses, "" if uses == 1 else "s"])
	return "  ·  ".join(parts)


func to_dict() -> Dictionary:
	return {
		"id": id, "secret": secret, "badge": badge, "label": label,
		"note": note, "bind_address": bind_address,
		"issued_at": issued_at, "last_used": last_used, "uses": uses,
		"revoked": revoked, "revoked_reason": revoked_reason,
	}


static func from_dict(row: Dictionary) -> VerifyKey:
	var key := VerifyKey.new()
	key.id = str(row.get("id", ""))
	key.secret = str(row.get("secret", ""))
	key.badge = str(row.get("badge", DirectoryProtocol.BADGE_VERIFIED))
	key.label = str(row.get("label", ""))
	key.note = str(row.get("note", ""))
	key.bind_address = str(row.get("bind_address", ""))
	key.issued_at = int(row.get("issued_at", 0))
	key.last_used = int(row.get("last_used", 0))
	key.uses = int(row.get("uses", 0))
	key.revoked = bool(row.get("revoked", false))
	key.revoked_reason = str(row.get("revoked_reason", ""))
	return key
