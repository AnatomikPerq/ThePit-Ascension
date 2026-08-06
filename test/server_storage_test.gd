extends GdUnitTestSuite
## The small JSON files the operator's side keeps, and the write that must never
## leave one half-written.
##
## Every failure here is silent in production and expensive: a truncated
## accounts.json is every account on the server, and a bans.json that failed to
## parse is indistinguishable from an empty one — which is the same thing as
## quietly unbanning everybody. Both of those were real: the account file was
## written carefully and the ban file was not, which is what happens when the
## same twenty lines exist twice.

const DIR := "user://test_storage"

var _path: String = ""


func before_test() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	_path = ProjectSettings.globalize_path(DIR).path_join("thing.json")


func after_test() -> void:
	var base := ProjectSettings.globalize_path(DIR)
	var dir := DirAccess.open(base)
	if dir == null:
		return
	for file in dir.get_files():
		DirAccess.remove_absolute(base.path_join(file))


# ── Writing ─────────────────────────────────────────────────────────────────
func test_a_write_leaves_the_file_and_no_temporary() -> void:
	assert_int(JsonFile.write_atomically(_path, '{"a":1}', 3)).is_equal(OK)
	assert_bool(FileAccess.file_exists(_path)).is_true()
	assert_bool(FileAccess.file_exists("%s.tmp" % _path)) \
		.override_failure_message("the temporary file was left behind — the rename "
			+ "did not resolve the path it was given") \
		.is_false()
	assert_str(FileAccess.get_file_as_string(_path)).is_equal('{"a":1}')


func test_the_previous_version_is_kept_as_a_backup() -> void:
	JsonFile.write_atomically(_path, '{"generation":1}', 3)
	JsonFile.write_atomically(_path, '{"generation":2}', 3)
	assert_str(FileAccess.get_file_as_string(_path)).contains('"generation":2')
	assert_str(FileAccess.get_file_as_string("%s.1.bak" % _path)) \
		.override_failure_message("the version being replaced was not kept") \
		.contains('"generation":1')


func test_backups_can_be_turned_off() -> void:
	JsonFile.write_atomically(_path, "{}", 0)
	JsonFile.write_atomically(_path, "{}", 0)
	assert_bool(FileAccess.file_exists("%s.1.bak" % _path)).is_false()


func test_older_backups_shuffle_up_and_the_oldest_goes() -> void:
	for generation in range(1, 5):
		JsonFile.write_atomically(_path, '{"generation":%d}' % generation, 2)
	assert_str(FileAccess.get_file_as_string("%s.1.bak" % _path)).contains('"generation":3')
	assert_str(FileAccess.get_file_as_string("%s.2.bak" % _path)).contains('"generation":2')
	assert_bool(FileAccess.file_exists("%s.3.bak" % _path)) \
		.override_failure_message("backups grew past the number asked for").is_false()


# ── Reading ─────────────────────────────────────────────────────────────────
## A fresh install, and a file somebody emptied. Neither is a problem, and
## reporting one would make every first boot look broken.
func test_a_missing_or_empty_file_is_not_a_problem() -> void:
	var problem: Array = []
	assert_dict(JsonFile.read_dictionary(_path, problem)).is_empty()
	assert_array(problem).is_empty()
	FileAccess.open(_path, FileAccess.WRITE).close()
	assert_dict(JsonFile.read_dictionary(_path, problem)).is_empty()
	assert_array(problem).is_empty()


## A file with content that will not parse is very much a problem, and the
## caller has to be told rather than handed an empty store.
func test_an_unreadable_file_is_reported_and_left_alone() -> void:
	var file := FileAccess.open(_path, FileAccess.WRITE)
	file.store_string("{ this was cut off half way")
	file.close()
	var problem: Array = []
	assert_dict(JsonFile.read_dictionary(_path, problem)).is_empty()
	assert_array(problem).is_not_empty()
	assert_bool(FileAccess.file_exists(_path)) \
		.override_failure_message("an unreadable file must never be overwritten "
			+ "on the way past — it is the only copy of whatever was in it") \
		.is_true()


# ── The ban list, which had the careless copy ───────────────────────────────
func test_bans_survive_a_round_trip() -> void:
	var bans := BanList.new()
	bans.load_from(ProjectSettings.globalize_path(DIR))
	bans.add("somebody", "account", "being unpleasant", "moderator", 0.0)
	bans.save()

	var read_back := BanList.new()
	assert_str(read_back.load_from(ProjectSettings.globalize_path(DIR))).is_equal("")
	assert_dict(read_back.check("somebody", "")).is_not_empty()
	assert_dict(read_back.check("somebody else", "")).is_empty()


## The failure this replaces: a bans.json that would not parse loaded as an empty
## list, and every ban on the server was silently gone.
func test_an_unreadable_ban_file_is_reported() -> void:
	var base := ProjectSettings.globalize_path(DIR)
	var file := FileAccess.open(base.path_join("bans.json"), FileAccess.WRITE)
	file.store_string("[not even an object]")
	file.close()
	var bans := BanList.new()
	assert_str(bans.load_from(base)) \
		.override_failure_message("a corrupt ban list loaded as an empty one, which "
			+ "is the same thing as unbanning everybody") \
		.is_not_equal("")


func test_a_ban_write_never_leaves_a_temporary_behind() -> void:
	var base := ProjectSettings.globalize_path(DIR)
	var bans := BanList.new()
	bans.load_from(base)
	bans.add("somebody", "account", "", "console", 0.0)
	bans.save()
	assert_bool(FileAccess.file_exists(base.path_join("bans.json"))).is_true()
	assert_bool(FileAccess.file_exists(base.path_join("bans.json.tmp"))).is_false()
