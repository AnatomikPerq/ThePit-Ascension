class_name DirectoryProtocol
extends Object
## The contract between a server that wants to be listed, a directory that lists
## it, and a client that reads the list.
##
## Deliberately NOT part of `NetProtocol`. That one is the game: two builds have
## to agree on it exactly or the pit desyncs, which is why it is fingerprinted
## and why a mismatch refuses the connection. This one is metadata about servers
## — nothing here decides where a platform is, so a directory one version behind
## a server should degrade to "shows less", never to "refuses everything". Every
## reader below treats a missing field as absent rather than as an error, and
## `VERSION` is carried so a future change can be recognised rather than guessed.
##
## It is HTTP because of what has to speak it: `HTTPRequest` in the client, curl
## on an operator's laptop, and nginx in front of the whole thing terminating
## TLS. A bespoke TCP format would have bought nothing and cost all three.

## Bumped when the shape of an announce or a listing changes. Sent both ways.
const VERSION: int = 1

## Everything is under a version prefix so that a directory can serve two at once
## during a transition, rather than the client having to guess which it is
## talking to.
const PATH_SERVERS := "/v1/servers"
const PATH_ANNOUNCE := "/v1/announce"
const PATH_HEALTH := "/v1/health"

## An announce older than this is refused, so a captured one cannot be replayed
## for the rest of time. Generous because a server's clock is not ours: it only
## has to be closer than "somebody kept the packet".
const MAX_CLOCK_SKEW_SECONDS: int = 300

## Ceiling on an announce body. A listing entry is a few hundred bytes; anything
## approaching this is somebody testing what happens.
const MAX_ANNOUNCE_BYTES: int = 8192

## Field lengths the directory clamps rather than refuses, because a server with
## a name one character too long should appear with a shortened name, not
## disappear with no explanation anybody will ever see.
const MAX_NAME := 40
const MAX_DESCRIPTION := 160
const MAX_TAGS := 8
const MAX_TAG := 16
const MAX_REGION := 24

# ── Verification ────────────────────────────────────────────────────────────
## The badge a listed server may carry. The kind is the wire value; the label is
## what a player reads; the note is what the hover says when whoever issued the
## key did not write their own.
##
## Three rather than one because they mean genuinely different things, and a
## single "verified" tick would have to mean the weakest of them. `official` is
## the developer's own machine; `partner` is somebody else's that the developer
## vouches for; `verified` says only that the operator is who they say they are.
const BADGE_NONE := ""
const BADGE_OFFICIAL := "official"
const BADGE_PARTNER := "partner"
const BADGE_VERIFIED := "verified"

const BADGES: Array[String] = [BADGE_OFFICIAL, BADGE_PARTNER, BADGE_VERIFIED]

const BADGE_LABELS := {
	BADGE_OFFICIAL: "OFFICIAL",
	BADGE_PARTNER: "PARTNER",
	BADGE_VERIFIED: "VERIFIED",
}

const BADGE_NOTES := {
	BADGE_OFFICIAL:
		"An official server, run by the developer of the game.",
	BADGE_PARTNER:
		"A community server the developer vouches for.",
	BADGE_VERIFIED:
		"The person running this server has been identified by the developer.",
}


static func is_badge(kind: String) -> bool:
	return BADGES.has(kind)


static func badge_label(kind: String) -> String:
	return str(BADGE_LABELS.get(kind, ""))


static func badge_note(kind: String, note: String = "") -> String:
	if note.strip_edges() != "":
		return note.strip_edges()
	return str(BADGE_NOTES.get(kind, ""))


# ── The proof ───────────────────────────────────────────────────────────────
## What a verified announce is signed over.
##
## The secret behind a verification key never travels: the server signs this
## string with it and sends the signature, and the directory recomputes the same
## string from what arrived and checks it. Two things follow, and both are the
## point:
##
##   - a key cannot be lifted out of a captured announce, because it is not in
##     one;
##   - the signature covers the NAME, ADDRESS and PORT as well as the key, so a
##     captured announce cannot be replayed to put somebody else's badge on a
##     different machine. Changing any of them invalidates it.
##
## The stamp and the nonce are what stop the *same* announce being replayed
## forever: the directory refuses one older than MAX_CLOCK_SKEW_SECONDS and
## remembers the nonces it has seen inside that window.
static func canonical(message: Dictionary) -> String:
	return "|".join(PackedStringArray([
		"pit-directory",
		str(VERSION),
		str(message.get("game", "")),
		str(message.get("content", "")),
		str(message.get("name", "")),
		str(message.get("address", "")),
		str(int(message.get("port", 0))),
		str(message.get("verify_id", "")),
		str(int(message.get("stamp", 0))),
		str(message.get("nonce", "")),
	]))


## Sign an announce. Called on the server being listed.
static func sign_announce(message: Dictionary, secret: String) -> String:
	var mac := NetCrypto.hmac_sha256(
		secret.to_utf8_buffer(), canonical(message).to_utf8_buffer())
	return mac.hex_encode()


## Check a signature. Called on the directory. Constant-time, because the
## comparison is the whole check and a timing leak on it is a way to guess a
## signature byte by byte.
static func verify_announce(message: Dictionary, secret: String) -> bool:
	var given := str(message.get("proof", ""))
	if given.length() != NetCrypto.DIGEST_BYTES * 2:
		return false
	return NetCrypto.equal(given.hex_decode(), sign_announce(message, secret).hex_decode())


# ── Finding servers on a local network ──────────────────────────────────────
## A client shouts this on the local network and every server that hears it
## answers with one packet describing itself. Request/response rather than
## servers broadcasting on a timer: an idle server should be silent, and a
## client that is not looking at the browser should not be listening.
const LAN_PROBE := "PIT-DISCOVER-1"
## Prefix on every answer, so that whatever else is on this port is ignored
## rather than parsed.
const LAN_REPLY := "PIT-SERVER-1 "
const LAN_PORT: int = 24568
## The client probes a few consecutive ports, because only one process per
## machine can hold one — two servers on one box would otherwise leave the
## second invisible on its own network.
const LAN_PORT_SPAN: int = 3
## Anything larger is not one of ours.
const LAN_MAX_BYTES: int = 2048


## True for a packet that is one of our answers.
static func is_lan_reply(text: String) -> bool:
	return text.begins_with(LAN_REPLY)


static func lan_payload(text: String) -> Dictionary:
	var json: Variant = JSON.parse_string(text.substr(LAN_REPLY.length()))
	return json if typeof(json) == TYPE_DICTIONARY else {}
