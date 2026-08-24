extends GutTest

const GithubTokenStore = preload("res://src/licensing/github_token_store.gd")

var _test_paths: Array[String] = []


func after_each():
	for path in _test_paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_test_paths.clear()


func test_default_path_is_under_user_data_dir():
	assert_true(GithubTokenStore.default_path().begins_with("user://"))


func test_read_token_returns_empty_string_when_no_file_exists():
	assert_eq(GithubTokenStore.read_token("user://definitely_missing_token.txt"), "")


func test_write_token_then_read_token_round_trips():
	var path := "user://test_github_token_store_a.txt"
	_test_paths.append(path)
	GithubTokenStore.write_token(path, "gho_abc123")
	assert_eq(GithubTokenStore.read_token(path), "gho_abc123")


func test_write_token_trims_surrounding_whitespace():
	var path := "user://test_github_token_store_b.txt"
	_test_paths.append(path)
	GithubTokenStore.write_token(path, "  gho_abc123\n")
	assert_eq(GithubTokenStore.read_token(path), "gho_abc123")


func test_write_token_overwrites_a_previous_token():
	var path := "user://test_github_token_store_c.txt"
	_test_paths.append(path)
	GithubTokenStore.write_token(path, "old_token")
	GithubTokenStore.write_token(path, "new_token")
	assert_eq(GithubTokenStore.read_token(path), "new_token")


## A cached token that GitHub itself rejects (revoked, expired, the
## player revoked app access) must not keep being retried silently
## forever -- clear_token() removes it so the next check falls back to
## a fresh interactive device flow instead of quietly failing every time.
func test_clear_token_removes_the_cached_token():
	var path := "user://test_github_token_store_d.txt"
	_test_paths.append(path)
	GithubTokenStore.write_token(path, "gho_abc123")
	GithubTokenStore.clear_token(path)
	assert_eq(GithubTokenStore.read_token(path), "")


func test_clear_token_on_an_already_missing_file_does_not_error():
	var path := "user://definitely_missing_token_to_clear.txt"
	GithubTokenStore.clear_token(path)
	assert_eq(GithubTokenStore.read_token(path), "")
