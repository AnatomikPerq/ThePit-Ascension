extends GdUnitTestSuite
## The check that stops a dedicated server being left running across a game
## update.
##
## A server is a process that stays up for weeks. When the game changes and the
## server does not, the client rebuilds a *different* pit from the same seed and
## falls through geometry the server does not have — and nothing anywhere says
## why. So the two sides state their build in the first packet either sends, and
## a mismatch is refused with a sentence naming which side is stale.
##
## `tools/run_tests.sh` regenerates the fingerprint on every run and says out
## loud when it moved. This suite pins the parts of that machinery that a change
## could quietly break.


func test_the_build_has_a_content_fingerprint() -> void:
	assert_str(NetProtocol.content_hash()) \
		.override_failure_message(
			"no content fingerprint — run: godot --headless --path . -s "
			+ "tools/build_protocol_stamp.gd") \
		.is_not_empty()
	assert_int(NetProtocol.content_hash().length()) \
		.override_failure_message("a SHA-256 hex digest is 64 characters").is_equal(64)


func test_the_stamp_records_what_it_was_made_from() -> void:
	var stamp: ProtocolStamp = load(NetProtocol.STAMP_PATH)
	assert_object(stamp).is_not_null()
	assert_int(stamp.file_count) \
		.override_failure_message("the fingerprint covers suspiciously few files") \
		.is_greater(40)
	assert_array(Array(stamp.sources)).is_not_empty()


func test_two_builds_that_agree_are_allowed_to_play() -> void:
	assert_str(NetProtocol.incompatibility(NetProtocol.VERSION,
		NetProtocol.content_hash(), NetProtocol.GAME_ID, true)).is_empty()
	assert_str(NetProtocol.incompatibility(NetProtocol.VERSION,
		NetProtocol.content_hash(), NetProtocol.GAME_ID, false)).is_empty()


## The message has to name which side is behind. "The server is older" is
## something a player can act on; "version mismatch" is not.
func test_an_older_server_is_named_as_the_older_one() -> void:
	var told := NetProtocol.incompatibility(NetProtocol.VERSION - 1,
		NetProtocol.content_hash(), NetProtocol.GAME_ID, true)
	assert_str(told).contains("PROTOCOL MISMATCH")
	assert_str(told).contains("SERVER IS OLDER")


func test_an_older_client_is_named_as_the_older_one() -> void:
	var told := NetProtocol.incompatibility(NetProtocol.VERSION - 1,
		NetProtocol.content_hash(), NetProtocol.GAME_ID, false)
	assert_str(told).contains("CLIENT IS OLDER")


## The whole point: same protocol, different content, and the refusal says to
## rebuild the server rather than leaving anybody to guess.
func test_different_content_is_refused_and_says_to_rebuild_the_server() -> void:
	var told := NetProtocol.incompatibility(NetProtocol.VERSION,
		"0000000000000000000000000000000000000000000000000000000000000000",
		NetProtocol.GAME_ID, true)
	assert_str(told).contains("CONTENT MISMATCH")
	assert_str(told).contains("SERVER MUST BE REBUILT")


func test_another_game_on_the_same_port_is_refused() -> void:
	assert_str(NetProtocol.incompatibility(NetProtocol.VERSION,
		NetProtocol.content_hash(), &"something.else", true)).is_not_empty()


# ── Encoding ────────────────────────────────────────────────────────────────
func test_a_handshake_message_survives_a_round_trip() -> void:
	var sent := {
		"t": NetProtocol.MSG_IDENT,
		"proto": NetProtocol.VERSION,
		"name": "somebody",
		"nonce": NetCrypto.new_nonce(),
	}
	var got := NetProtocol.decode(NetProtocol.encode(sent))
	assert_str(str(got.get("t", ""))).is_equal(String(NetProtocol.MSG_IDENT))
	assert_int(int(got.get("proto", 0))).is_equal(NetProtocol.VERSION)
	assert_bool(NetCrypto.equal(got.get("nonce"), sent["nonce"])).is_true()


## Everything a stranger can send before authenticating goes through `decode`.
## It answers "not one of ours" rather than throwing — and it does so from the
## HEADER, without letting the engine's decoder near the bytes, because that
## decoder pushes an error for malformed input and an unauthenticated stranger
## must not be able to fill an operator's log by sending noise at the port.
func test_rubbish_decodes_to_nothing_rather_than_failing() -> void:
	assert_bool(NetProtocol.decode(PackedByteArray()).is_empty()).is_true()
	assert_bool(NetProtocol.decode(PackedByteArray([1, 2, 3])).is_empty()).is_true()
	# Four bytes of noise: a leading type field that is not a dictionary.
	assert_bool(NetProtocol.decode(PackedByteArray([9, 9, 9, 9])).is_empty()).is_true()
	# Well-formed, but not a dictionary at all.
	assert_bool(NetProtocol.decode(var_to_bytes("hello")).is_empty()).is_true()
	assert_bool(NetProtocol.decode(var_to_bytes(42)).is_empty()).is_true()
	# A dictionary with no type field is not a message.
	assert_bool(NetProtocol.decode(NetProtocol.encode({"x": 1})).is_empty()).is_true()


func test_an_oversized_payload_is_refused_before_it_is_decoded() -> void:
	var huge := PackedByteArray()
	huge.resize(NetProtocol.MAX_AUTH_BYTES + 1)
	assert_bool(NetProtocol.decode(huge).is_empty()).is_true()


## Both ends must use the same ENet compression or no connection ever forms — no
## error, no log line, just a client stuck on "contacting…". It lives in the
## protocol for that reason, and this pins that it is not a per-machine choice.
func test_the_transport_is_a_protocol_constant() -> void:
	assert_int(NetProtocol.COMPRESSION).is_equal(ENetConnection.COMPRESS_RANGE_CODER)
