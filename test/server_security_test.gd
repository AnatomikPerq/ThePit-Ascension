extends GdUnitTestSuite
## The parts of the server that decide whether somebody may do a thing.
##
## Every one of these is a rule the three-process probe exercises but cannot
## enumerate: the probe proves that a player is refused `stop`, this proves that
## the whole ladder of who-may-do-what is the shape it is meant to be. Password
## hashing is in here too, against a published vector rather than against itself.


# ── Password hashing ────────────────────────────────────────────────────────
## PBKDF2-HMAC-SHA256, P="password", S="salt", c=1000, dkLen=32. A published
## vector, so this checks the implementation and not merely that it is stable.
## If it ever fails, every account on every server is affected — which is why it
## is pinned rather than assumed.
func test_pbkdf2_matches_the_published_vector() -> void:
	var derived := NetCrypto.derive_key("password", "salt".to_utf8_buffer(), 1000)
	assert_str(derived.hex_encode()) \
		.override_failure_message("PBKDF2-HMAC-SHA256 does not match RFC's vector") \
		.is_equal("632c2812e46d4604102ba7618e9d6d7d2f8128f6266b4a03264d2a0460b7dcb3")


func test_a_different_password_derives_a_different_key() -> void:
	var salt := "salt".to_utf8_buffer()
	assert_bool(NetCrypto.equal(
		NetCrypto.derive_key("password", salt, 1000),
		NetCrypto.derive_key("Password", salt, 1000))).is_false()


func test_the_same_password_with_a_different_salt_derives_a_different_key() -> void:
	assert_bool(NetCrypto.equal(
		NetCrypto.derive_key("password", "salt-a".to_utf8_buffer(), 1000),
		NetCrypto.derive_key("password", "salt-b".to_utf8_buffer(), 1000))).is_false()


## Below the floor, the count is raised rather than honoured. A config that said
## `1` must not turn hashing into a single HMAC.
func test_the_iteration_floor_cannot_be_configured_away() -> void:
	var salt := NetCrypto.new_salt()
	assert_bool(NetCrypto.equal(
		NetCrypto.derive_key("password", salt, 1),
		NetCrypto.derive_key("password", salt, NetCrypto.MIN_ITERATIONS))).is_true()


## The password is never stored and never sent: the account keeps the derived
## key, and a login answers a per-connection nonce with an HMAC of it.
func test_a_login_proof_is_bound_to_its_nonce() -> void:
	var account := Account.make("somebody", "a good password", NetCrypto.MIN_ITERATIONS)
	var nonce := NetCrypto.new_nonce()
	var key := NetCrypto.derive_key("a good password", account.salt, account.iterations)
	assert_bool(account.proves(nonce, NetCrypto.proof(key, nonce))).is_true()
	# The same proof against a different nonce — a replay — is worthless.
	assert_bool(account.proves(NetCrypto.new_nonce(), NetCrypto.proof(key, nonce))).is_false()
	# And the wrong password never proves anything.
	var wrong := NetCrypto.derive_key("a bad password", account.salt, account.iterations)
	assert_bool(account.proves(nonce, NetCrypto.proof(wrong, nonce))).is_false()


## An unknown account still gets a challenge, built from the server's own secret,
## so that "no such name" and "wrong password" are indistinguishable. Without it
## the port answers the question "who plays here" to anybody who asks.
func test_the_decoy_salt_is_stable_and_name_specific() -> void:
	var secret := NetCrypto.random_bytes(32)
	var once := NetCrypto.decoy_salt(secret, "ghost")
	assert_int(once.size()).is_equal(NetCrypto.SALT_BYTES)
	assert_bool(NetCrypto.equal(once, NetCrypto.decoy_salt(secret, "ghost"))).is_true()
	assert_bool(NetCrypto.equal(once, NetCrypto.decoy_salt(secret, "ghoul"))).is_false()
	# And it differs per install, so one server's decoys say nothing about another's.
	assert_bool(NetCrypto.equal(once,
		NetCrypto.decoy_salt(NetCrypto.random_bytes(32), "ghost"))).is_false()


# ── Permissions ─────────────────────────────────────────────────────────────
func test_the_owner_holds_everything_and_a_player_does_not() -> void:
	for right in Permissions.catalogue():
		assert_bool(Permissions.allows(Permissions.of_role(Permissions.ROLE_OWNER), right)) \
			.override_failure_message("the owner should hold %s" % right).is_true()
	var player := Permissions.of_role(Permissions.ROLE_PLAYER)
	assert_bool(Permissions.allows(player, Permissions.SERVER_STOP)).is_false()
	assert_bool(Permissions.allows(player, Permissions.PLAYER_BAN)).is_false()
	assert_bool(Permissions.allows(player, Permissions.SERVER_SETTINGS_WRITE)).is_false()


func test_a_moderator_may_act_on_people_but_not_on_the_server() -> void:
	var mod := Permissions.of_role(Permissions.ROLE_MODERATOR)
	assert_bool(Permissions.allows(mod, Permissions.PLAYER_KICK)).is_true()
	assert_bool(Permissions.allows(mod, Permissions.PLAYER_BAN)).is_true()
	assert_bool(Permissions.allows(mod, Permissions.SERVER_SETTINGS_WRITE)).is_false()
	assert_bool(Permissions.allows(mod, Permissions.SERVER_STOP)).is_false()
	assert_bool(Permissions.allows(mod, Permissions.ACCOUNT_ROLE)).is_false()


## A wildcard covers what is under it and nothing beside it. Getting this wrong
## in the permissive direction is a hole; `player.*` must not match `playerfoo`.
func test_wildcards_cover_a_branch_and_not_a_prefix() -> void:
	var held := PackedStringArray(["player.*"])
	assert_bool(Permissions.allows(held, "player.kick")).is_true()
	assert_bool(Permissions.allows(held, "player.ban.permanent")).is_true()
	assert_bool(Permissions.allows(held, "player")).is_false()
	assert_bool(Permissions.allows(held, "playerlist.read")).is_false()
	assert_bool(Permissions.allows(held, "server.stop")).is_false()


## Rights are named rather than ranked, so one can be handed out on its own —
## and taken back even from a role that carries it.
func test_a_grant_adds_and_a_denial_overrides_the_role() -> void:
	var granted := Permissions.effective(Permissions.ROLE_PLAYER,
		PackedStringArray([Permissions.PLAYER_KICK]), PackedStringArray())
	assert_bool(Permissions.allows(granted, Permissions.PLAYER_KICK)).is_true()
	assert_bool(Permissions.allows(granted, Permissions.PLAYER_BAN)).is_false()

	var denied := Permissions.effective(Permissions.ROLE_MODERATOR,
		PackedStringArray(), PackedStringArray([Permissions.PLAYER_BAN]))
	assert_bool(Permissions.allows(denied, Permissions.PLAYER_KICK)).is_true()
	assert_bool(Permissions.allows(denied, Permissions.PLAYER_BAN)) \
		.override_failure_message("a denial must beat the role that grants it").is_false()


func test_roles_are_ordered_weakest_first() -> void:
	assert_int(Permissions.rank(Permissions.ROLE_PLAYER)) \
		.is_less(Permissions.rank(Permissions.ROLE_MODERATOR))
	assert_int(Permissions.rank(Permissions.ROLE_MODERATOR)) \
		.is_less(Permissions.rank(Permissions.ROLE_ADMIN))
	assert_int(Permissions.rank(Permissions.ROLE_ADMIN)) \
		.is_less(Permissions.rank(Permissions.ROLE_OWNER))
	assert_int(Permissions.rank("nonsense")).is_equal(0)


## Every right a role carries has to be a right that exists. This is what catches
## a constant renamed in one place and not the other.
func test_no_role_carries_a_right_that_is_not_in_the_catalogue() -> void:
	var known := Permissions.catalogue()
	for role in Permissions.ROLES:
		for right in Permissions.of_role(role):
			if right == Permissions.ALL or right.ends_with(".*"):
				continue
			assert_bool(known.has(right)) \
				.override_failure_message("%s carries '%s', which is not a right"
					% [role, right]).is_true()


# ── Bans ────────────────────────────────────────────────────────────────────
func test_a_timed_ban_expires_and_a_permanent_one_does_not() -> void:
	var bans := BanList.new()
	bans.add("someone", BanList.KIND_ACCOUNT, "being unpleasant", "console", 0.0)
	assert_bool(bans.check("someone", "").is_empty()).is_false()

	# Expiry is a unix timestamp, so an already-elapsed ban is one written with a
	# duration in the past. Nothing here waits on a clock.
	bans.entries["someone"]["until"] = int(Time.get_unix_time_from_system()) - 1
	assert_bool(bans.check("someone", "").is_empty()) \
		.override_failure_message("a ban that has run out must not be in force").is_true()
	assert_int(bans.count()).is_equal(0)


func test_an_account_ban_and_an_address_ban_are_separate_things() -> void:
	var bans := BanList.new()
	bans.add("10.0.0.9", BanList.KIND_ADDRESS, "evading", "console", 0.0)
	assert_bool(bans.check("someone", "10.0.0.9").is_empty()).is_false()
	assert_bool(bans.check("someone", "10.0.0.8").is_empty()).is_true()
	assert_bool(bans.remove("10.0.0.9")).is_true()
	assert_bool(bans.check("someone", "10.0.0.9").is_empty()).is_true()


## The account's own ban is reported in preference to an address one, so the
## message a player sees names their ban and not somebody else's.
func test_an_account_ban_is_reported_over_an_overlapping_address_ban() -> void:
	var bans := BanList.new()
	bans.add("10.0.0.9", BanList.KIND_ADDRESS, "the address", "console", 0.0)
	bans.add("someone", BanList.KIND_ACCOUNT, "the person", "console", 0.0)
	assert_str(str(bans.check("someone", "10.0.0.9").get("reason", ""))) \
		.is_equal("the person")


# ── Rate limiting ───────────────────────────────────────────────────────────
## A bucket, not a window. A window resets, and a resetting window lets somebody
## spend a whole allowance in its last millisecond and again in the next one's
## first.
func test_a_bucket_allows_its_burst_and_then_refuses() -> void:
	var limiter := RateLimiter.make(1.0, 5.0)
	for i in 5:
		assert_bool(limiter.allow("peer")) \
			.override_failure_message("refused request %d of a burst of 5" % (i + 1)).is_true()
	assert_bool(limiter.allow("peer")) \
		.override_failure_message("the sixth of a burst of five was allowed").is_false()


func test_buckets_are_per_key_and_can_be_forgotten() -> void:
	var limiter := RateLimiter.make(1.0, 1.0)
	assert_bool(limiter.allow("a")).is_true()
	assert_bool(limiter.allow("a")).is_false()
	assert_bool(limiter.allow("b")) \
		.override_failure_message("one peer's flood must not limit another's").is_true()
	limiter.forget("a")
	assert_int(limiter.tracked()).is_equal(1)
