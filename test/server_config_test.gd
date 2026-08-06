extends GdUnitTestSuite
## The settings registry and the command registry — the two things every
## administration surface is generated from.
##
## They are tested together because they fail in the same way: the console, the
## remote console and the in-game panel all read them, so a defect here is a
## defect in three places at once and in none of them visibly.


# ── Settings ────────────────────────────────────────────────────────────────
func test_every_setting_has_a_key_a_description_and_a_valid_default() -> void:
	var settings := ServerSettings.new()
	assert_int(settings.defs.size()) \
		.override_failure_message("a server with almost no settings is suspicious") \
		.is_greater(50)
	for key in settings.defs:
		var def: SettingDef = settings.defs[key]
		assert_str(def.key).is_equal(key)
		assert_bool(key.contains("/")) \
			.override_failure_message("'%s' has no section" % key).is_true()
		# The default has to survive its own validation, or the file written on
		# first boot cannot be read back on the second.
		var parsed: Array = def.parse(str(def.default_value))
		assert_bool(parsed[0]) \
			.override_failure_message("the default of '%s' fails its own check: %s"
				% [key, parsed[2]]).is_true()


func test_a_value_out_of_range_is_refused_and_the_old_one_stays() -> void:
	var settings := ServerSettings.new()
	var before := settings.get_int("network/port")
	assert_str(settings.set_from_text("network/port", "99999")).is_not_empty()
	assert_int(settings.get_int("network/port")).is_equal(before)
	assert_str(settings.set_from_text("network/port", "25000")).is_empty()
	assert_int(settings.get_int("network/port")).is_equal(25000)


func test_a_value_outside_the_choices_is_refused() -> void:
	var settings := ServerSettings.new()
	assert_str(settings.set_from_text("auth/mode", "whatever")).is_not_empty()
	assert_str(settings.get_text("auth/mode")).is_equal("guest")
	assert_str(settings.set_from_text("auth/mode", "account")).is_empty()
	assert_str(settings.get_text("auth/mode")).is_equal("account")


## The same words are accepted wherever they are typed. A setting that takes
## "yes" on the console and refuses it in the file is a bug report waiting.
func test_booleans_take_the_words_people_actually_type() -> void:
	var settings := ServerSettings.new()
	for yes in ["true", "yes", "on", "1", "TRUE"]:
		assert_str(settings.set_from_text("moderation/chat", yes)).is_empty()
		assert_bool(settings.get_bool("moderation/chat")).is_true()
	for no in ["false", "no", "off", "0"]:
		assert_str(settings.set_from_text("moderation/chat", no)).is_empty()
		assert_bool(settings.get_bool("moderation/chat")).is_false()
	assert_str(settings.set_from_text("moderation/chat", "perhaps")).is_not_empty()


func test_an_unknown_setting_is_refused_rather_than_invented() -> void:
	var settings := ServerSettings.new()
	assert_str(settings.set_from_text("nonsense/key", "1")).is_not_empty()
	assert_bool(settings.has("nonsense/key")).is_false()


func test_a_secret_never_shows_its_value() -> void:
	var settings := ServerSettings.new()
	settings.set_from_text("rcon/password", "hunter2")
	var def: SettingDef = settings.defs["rcon/password"]
	assert_bool(def.secret).is_true()
	assert_str(def.display(settings.get_value("rcon/password"))) \
		.override_failure_message("a secret must not print itself").is_equal("(set)")


func test_list_settings_come_back_clean() -> void:
	var settings := ServerSettings.new()
	settings.set_from_text("auth/reserved_names", " Root, ,ADMIN ,, server ")
	var names := settings.get_list("auth/reserved_names")
	assert_array(Array(names)).contains_exactly(["root", "admin", "server"])


## Written on first boot and read back on the second. This is the round trip an
## operator's edits go through, and the descriptions have to survive it as
## comments without being mistaken for values.
func test_the_generated_file_reads_back_as_what_was_written() -> void:
	var dir := "user://server_config_test"
	DirAccess.make_dir_recursive_absolute(dir)
	var written := ServerSettings.new()
	written.set_from_text("server/name", "A Test Server")
	written.set_from_text("network/port", "24999")
	written.set_from_text("moderation/chat", "false")
	written.set_from_text("auth/mode", "account")
	assert_int(written.save_to(dir)).is_equal(OK)

	var read_back := ServerSettings.new()
	var problems := read_back.load_from(dir)
	assert_array(Array(problems)).is_empty()
	assert_str(read_back.get_text("server/name")).is_equal("A Test Server")
	assert_int(read_back.get_int("network/port")).is_equal(24999)
	assert_bool(read_back.get_bool("moderation/chat")).is_false()
	assert_str(read_back.get_text("auth/mode")).is_equal("account")
	DirAccess.remove_absolute(dir.path_join(ServerSettings.FILE_NAME))


# ── Commands ────────────────────────────────────────────────────────────────
## Arguments with spaces go in quotes, and nothing else is a shell. A moderator
## typing a reason is the whole requirement.
func test_the_command_line_splitter_honours_quotes_and_nothing_else() -> void:
	assert_array(Array(ServerConsole.split('ban someone "being unpleasant in room 2"'))) \
		.contains_exactly(["ban", "someone", "being unpleasant in room 2"])
	assert_array(Array(ServerConsole.split("  kick   somebody  "))) \
		.contains_exactly(["kick", "somebody"])
	assert_array(Array(ServerConsole.split(""))).is_empty()
	# An empty quoted argument is an argument, not nothing: `room set 1 password ""`
	# is how a room's password is removed.
	assert_array(Array(ServerConsole.split('room set 1 password ""'))) \
		.contains_exactly(["room", "set", "1", "password", ""])


func test_an_unknown_command_fails_and_suggests_something() -> void:
	var reg := _registry()
	var caller := reg.execute(CommandCaller.for_console(), "stauts")
	assert_bool(caller.failed).is_true()
	assert_str(caller.output()).contains("unknown command")


## Exists, then permitted, then well-formed — in that order. Telling somebody the
## correct syntax for a thing they may not do leaks what is being protected.
func test_permission_is_checked_before_the_arguments_are() -> void:
	var reg := _registry()
	var caller := reg.execute(_as_player(), "danger")
	assert_bool(caller.failed).is_true()
	assert_str(caller.output()) \
		.override_failure_message("a refusal must not double as a syntax lesson") \
		.contains("may not")
	assert_str(caller.output()).not_contains("usage:")


func test_a_permitted_command_with_the_wrong_arguments_gets_its_usage() -> void:
	var caller := _registry().execute(CommandCaller.for_console(), "danger")
	assert_bool(caller.failed).is_true()
	assert_str(caller.output()).contains("usage:")


## `room close 3` must find `room close`, not `room`. That is what lets the two
## carry different rights while reading as one family.
func test_a_two_word_command_wins_over_its_first_word() -> void:
	var reg := _registry()
	var caller := reg.execute(CommandCaller.for_console(), "thing do 7")
	assert_str(caller.output()).is_equal("did 7")


func test_help_lists_only_what_the_asker_may_run() -> void:
	var reg := _registry()
	var owner := reg.help_text(CommandCaller.for_console())
	assert_str(owner).contains("danger")
	var player := reg.help_text(_as_player())
	assert_str(player) \
		.override_failure_message("help must not advertise what it would refuse") \
		.not_contains("danger")


func test_the_console_outranks_everybody() -> void:
	var caller := CommandCaller.for_console()
	assert_bool(caller.may(Permissions.SERVER_STOP)).is_true()
	assert_int(caller.rank()).is_greater(Permissions.rank(Permissions.ROLE_OWNER) - 1)


# ── Helpers ─────────────────────────────────────────────────────────────────
func _registry() -> CommandRegistry:
	var reg := CommandRegistry.new()
	reg.add(ServerCommand.make("danger", "danger <what>", "needs a right",
		Permissions.SERVER_STOP,
		func(caller: CommandCaller, args: PackedStringArray) -> void:
			caller.say("boom %s" % args[0])
	).with_args(1, 1))
	reg.add(ServerCommand.make("thing", "thing", "the one-word one",
		Permissions.SERVER_STATUS,
		func(caller: CommandCaller, _args: PackedStringArray) -> void:
			caller.say("the plain thing")))
	reg.add(ServerCommand.make("thing do", "thing do <n>", "the two-word one",
		Permissions.SERVER_STATUS,
		func(caller: CommandCaller, args: PackedStringArray) -> void:
			caller.say("did %s" % args[0])
	).with_args(1, 1))
	return reg


func _as_player() -> CommandCaller:
	return CommandCaller.for_player(Account.guest_for("somebody"), 7)
