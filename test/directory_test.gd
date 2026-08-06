extends GdUnitTestSuite
## The server list: what a directory believes, what it refuses, and what it
## takes away.
##
## The three-process probe (tools/run_directory_probe.sh) proves the wire —
## a real directory, a real server announcing to it and a real client reading
## the result. This suite pins the DECISIONS, which the probe exercises one path
## of and cannot enumerate: every way a verification claim fails, and the fact
## that failing one loses the badge without losing the listing.
##
## The badge is the only thing here a stranger must not be able to lie about, so
## it is the only thing with this many cases against it.

const KEY_SECRET := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

var _keys: VerifyKeyStore
var _store: DirectoryStore
var _now: int = 1786000000


func before_test() -> void:
	_keys = VerifyKeyStore.new()
	_store = DirectoryStore.new()


## A well-formed announce, signed unless `secret` is empty.
func _announce(server_name: String, address: String, key_id: String = "",
		secret: String = "", nonce: String = "") -> Dictionary:
	var message := {
		"game": String(NetProtocol.GAME_ID),
		"protocol": NetProtocol.VERSION,
		"content": NetProtocol.content_hash(),
		"name": server_name,
		"address": address,
		"port": 24565,
		"players": 3,
		"max_players": 16,
		"auth": "guest",
		"verify_id": key_id,
		"stamp": _now,
		"nonce": nonce if nonce != "" else NetCrypto.new_token(16),
	}
	if secret != "":
		message["proof"] = DirectoryProtocol.sign_announce(message, secret)
	return message


func _issued(kind: String = DirectoryProtocol.BADGE_OFFICIAL) -> VerifyKey:
	var key := VerifyKey.issue(kind, "the developer", "Run by the developer.")
	key.secret = KEY_SECRET
	_keys.add(key)
	return key


# ── The signature ───────────────────────────────────────────────────────────
func test_a_signed_announce_earns_its_badge() -> void:
	var key := _issued()
	var checked := _keys.check(_announce("The PIT", "play.example.com",
		key.id, KEY_SECRET), _now)
	assert_object(checked[0]).is_not_null()
	assert_str(str(checked[1])).is_equal("")


## The whole point of the signature. A captured announce cannot be re-pointed at
## another machine, because the address is inside what was signed.
func test_moving_a_signed_announce_to_another_address_invalidates_it() -> void:
	var key := _issued()
	var message := _announce("The PIT", "play.example.com", key.id, KEY_SECRET)
	message["address"] = "impostor.example.com"
	var checked := _keys.check(message, _now)
	assert_object(checked[0]) \
		.override_failure_message("a signed announce was accepted for a different address") \
		.is_null()
	assert_str(str(checked[1])).contains("signature")


func test_renaming_a_signed_announce_invalidates_it() -> void:
	var key := _issued()
	var message := _announce("The PIT", "play.example.com", key.id, KEY_SECRET)
	message["name"] = "Something Else"
	assert_object(_keys.check(message, _now)[0]).is_null()


func test_the_secret_is_never_in_the_announce() -> void:
	var key := _issued()
	var message := _announce("The PIT", "play.example.com", key.id, KEY_SECRET)
	assert_str(JSON.stringify(message)) \
		.override_failure_message("the verification secret travelled with the announce") \
		.not_contains(KEY_SECRET)


func test_a_wrong_secret_proves_nothing() -> void:
	var key := _issued()
	var message := _announce("The PIT", "play.example.com", key.id,
		"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff")
	assert_object(_keys.check(message, _now)[0]).is_null()


func test_an_unsigned_claim_proves_nothing() -> void:
	var key := _issued()
	assert_object(_keys.check(_announce("The PIT", "play.example.com", key.id),
		_now)[0]).is_null()


func test_an_unknown_key_is_refused() -> void:
	var checked := _keys.check(_announce("The PIT", "play.example.com",
		"pitk_nosuchkey", KEY_SECRET), _now)
	assert_object(checked[0]).is_null()
	assert_str(str(checked[1])).contains("unknown")


# ── Freshness ───────────────────────────────────────────────────────────────
func test_a_stale_announce_is_refused() -> void:
	var key := _issued()
	var message := _announce("The PIT", "play.example.com", key.id, KEY_SECRET)
	var later := _now + DirectoryProtocol.MAX_CLOCK_SKEW_SECONDS + 60
	assert_object(_keys.check(message, later)[0]) \
		.override_failure_message("an announce from an hour ago was still accepted") \
		.is_null()


## A correct announce, captured and sent again. The timestamp alone would let
## this work for five minutes; the nonce is what closes that window.
func test_the_same_announce_twice_is_refused_the_second_time() -> void:
	var key := _issued()
	var message := _announce("The PIT", "play.example.com", key.id, KEY_SECRET, "n123456789012345678")
	assert_object(_keys.check(message, _now)[0]).is_not_null()
	var second := _keys.check(message, _now)
	assert_object(second[0]).is_null()
	assert_str(str(second[1])).contains("already been seen")


# ── Binding and revoking ────────────────────────────────────────────────────
func test_a_key_binds_to_the_first_address_it_is_used_from() -> void:
	var key := _issued()
	_keys.check(_announce("The PIT", "play.example.com", key.id, KEY_SECRET), _now, true)
	assert_str(key.bind_address).is_equal("play.example.com")
	# And now the same secret cannot badge anywhere else, which is what makes a
	# handed-on or leaked key stop being useful.
	var elsewhere := _keys.check(_announce("The PIT", "other.example.com",
		key.id, KEY_SECRET), _now, true)
	assert_object(elsewhere[0]).is_null()
	assert_str(str(elsewhere[1])).contains("bound to")


func test_binding_can_be_undone() -> void:
	var key := _issued()
	_keys.check(_announce("The PIT", "play.example.com", key.id, KEY_SECRET), _now, true)
	_keys.bind(key.id, "")
	assert_object(_keys.check(_announce("The PIT", "other.example.com",
		key.id, KEY_SECRET), _now)[0]).is_not_null()


func test_a_revoked_key_is_refused() -> void:
	var key := _issued()
	_keys.revoke(key.id, "sold the server")
	assert_object(_keys.check(_announce("The PIT", "play.example.com",
		key.id, KEY_SECRET), _now)[0]).is_null()


## Revoking must not have to wait for the server to announce again — it might
## never do so, having got what it wanted.
func test_revoking_strips_the_badge_from_a_server_already_listed() -> void:
	var key := _issued()
	var checked := _keys.check(_announce("The PIT", "play.example.com",
		key.id, KEY_SECRET), _now)
	var entry := _store.accept(_announce("The PIT", "play.example.com"),
		"1.2.3.4", checked[0], _now)
	assert_bool(entry.verified()).is_true()
	_keys.revoke(key.id, "no longer trusted")
	assert_int(_store.refresh_badges(_keys)).is_equal(1)
	assert_bool(_store.find("play.example.com", 24565).verified()).is_false()


# ── The listing itself ──────────────────────────────────────────────────────
## Losing a badge must never mean losing the row. A key that stopped working is
## the operator's problem; the players on that server did nothing.
func test_a_failed_claim_still_leaves_the_server_listed() -> void:
	var key := _issued()
	var message := _announce("The PIT", "play.example.com", key.id, "deadbeef")
	var checked := _keys.check(message, _now)
	var entry := _store.accept(message, "1.2.3.4", checked[0], _now)
	assert_bool(entry.verified()).is_false()
	assert_int(_store.listing(_now, 150).size()).is_equal(1)


func test_a_server_that_stops_announcing_stops_being_listed() -> void:
	_store.accept(_announce("The PIT", "play.example.com"), "1.2.3.4", null, _now)
	assert_int(_store.listing(_now + 10, 150).size()).is_equal(1)
	assert_int(_store.listing(_now + 400, 150).size()).is_equal(0)
	# Still remembered, though: it comes straight back when it announces again,
	# keeping the "listed since" it had.
	assert_int(_store.count()).is_equal(1)
	assert_int(_store.forget_stale(_now + 400, 300)).is_equal(1)
	assert_int(_store.count()).is_equal(0)


func test_re_announcing_keeps_first_seen_and_moves_last_seen() -> void:
	var first := _store.accept(_announce("The PIT", "play.example.com"),
		"1.2.3.4", null, _now)
	var again := _store.accept(_announce("The PIT", "play.example.com"),
		"1.2.3.4", null, _now + 60)
	assert_int(again.first_seen).is_equal(first.first_seen)
	assert_int(again.last_seen).is_equal(_now + 60)
	assert_int(_store.count()).is_equal(1)


## A server behind NAT does not know its own public address. The directory does.
func test_a_server_that_names_no_address_gets_the_one_it_came_from() -> void:
	var message := _announce("The PIT", "")
	var entry := _store.accept(message, "203.0.113.9", null, _now)
	assert_str(entry.address).is_equal("203.0.113.9")


func test_verified_servers_sort_first() -> void:
	var key := _issued()
	_store.accept(_announce("Busy", "busy.example.com"), "1.1.1.1", null, _now)
	var checked := _keys.check(_announce("Quiet", "quiet.example.com",
		key.id, KEY_SECRET), _now)
	var quiet := _announce("Quiet", "quiet.example.com")
	quiet["players"] = 0
	_store.accept(quiet, "2.2.2.2", checked[0], _now)
	var listing := _store.listing(_now, 150)
	assert_str(str((listing[0] as Dictionary).get("name"))).is_equal("Quiet")


func test_only_verified_can_be_asked_for() -> void:
	var key := _issued()
	_store.accept(_announce("Plain", "plain.example.com"), "1.1.1.1", null, _now)
	var checked := _keys.check(_announce("Badged", "badged.example.com",
		key.id, KEY_SECRET), _now)
	_store.accept(_announce("Badged", "badged.example.com"), "2.2.2.2", checked[0], _now)
	assert_int(_store.listing(_now, 150, true).size()).is_equal(1)


# ── What an announce may claim ──────────────────────────────────────────────
## The badge is the directory's to give. A server that puts one in its own
## announce gets nothing for it — this is the case that would otherwise make the
## whole scheme decorative.
func test_a_server_cannot_badge_itself() -> void:
	var message := _announce("Impostor", "impostor.example.com")
	message["badge"] = DirectoryProtocol.BADGE_OFFICIAL
	message["badge_note"] = "Totally official, honest."
	var entry := _store.accept(message, "1.2.3.4", null, _now)
	assert_bool(entry.verified()).is_false()
	assert_str(entry.badge).is_equal("")


## And neither can a machine on your own network, where there is no directory in
## the path at all to decide.
func test_a_lan_reply_cannot_badge_itself() -> void:
	var entry := DirectoryEntry.from_listing({
		"name": "Impostor", "address": "192.168.1.9", "port": 24565,
		"badge": DirectoryProtocol.BADGE_OFFICIAL,
	}, DirectoryEntry.Source.LAN)
	assert_bool(entry.verified()).is_false()


func test_an_over_long_name_is_shortened_rather_than_refused() -> void:
	var message := _announce("x".repeat(400), "long.example.com")
	message["description"] = "y".repeat(4000)
	var entry := _store.accept(message, "1.2.3.4", null, _now)
	assert_int(entry.name.length()).is_equal(DirectoryProtocol.MAX_NAME)
	assert_int(entry.description.length()).is_equal(DirectoryProtocol.MAX_DESCRIPTION)


## A newline in a name breaks every list that prints it, and there is no
## legitimate one.
func test_control_characters_are_stripped_from_what_a_server_claims() -> void:
	var entry := _store.accept(_announce("Two\nLines\tHere", "cr.example.com"),
		"1.2.3.4", null, _now)
	assert_str(entry.name).is_equal("TwoLinesHere")


func test_too_many_tags_are_cut_and_de_duplicated() -> void:
	var message := _announce("Tagged", "tags.example.com")
	message["tags"] = ["EU", "eu", "coop", "race", "a", "b", "c", "d", "e", "f", "g"]
	var entry := _store.accept(message, "1.2.3.4", null, _now)
	assert_int(entry.tags.size()).is_less_equal(DirectoryProtocol.MAX_TAGS)
	assert_int(Array(entry.tags).count("eu")).is_equal(1)


# ── What the browser does with a listing ────────────────────────────────────
## A server on another build is shown and NOT offered, which is the difference
## between a sentence in the browser and a connection that fails ten seconds
## later with a sentence nobody reads.
func test_a_server_on_another_build_is_not_joinable() -> void:
	var mine := DirectoryEntry.from_listing({"address": "a", "port": 1,
		"protocol": NetProtocol.VERSION, "content": NetProtocol.content_hash()})
	var theirs := DirectoryEntry.from_listing({"address": "b", "port": 1,
		"protocol": NetProtocol.VERSION, "content": "something else entirely"})
	assert_bool(mine.joinable()).is_true()
	assert_bool(theirs.joinable()).is_false()


func test_a_listing_survives_a_round_trip() -> void:
	var key := _issued(DirectoryProtocol.BADGE_PARTNER)
	var checked := _keys.check(_announce("The PIT", "play.example.com",
		key.id, KEY_SECRET), _now)
	var entry := _store.accept(_announce("The PIT", "play.example.com"),
		"1.2.3.4", checked[0], _now)
	var read_back := DirectoryEntry.from_listing(entry.to_listing())
	assert_str(read_back.name).is_equal(entry.name)
	assert_str(read_back.badge).is_equal(DirectoryProtocol.BADGE_PARTNER)
	assert_str(read_back.badge_note).is_equal("Run by the developer.")
	assert_int(read_back.port).is_equal(entry.port)


func test_a_badge_with_no_note_falls_back_to_its_own_wording() -> void:
	var key := VerifyKey.issue(DirectoryProtocol.BADGE_VERIFIED, "somebody")
	assert_str(key.hover_text()) \
		.is_equal(DirectoryProtocol.BADGE_NOTES[DirectoryProtocol.BADGE_VERIFIED])
