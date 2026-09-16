import "build.just"

_ql_formatter := if SEMMLE_CODE != "" { '"$SEMMLE_CODE/target/intree/codeql-nolang/codeql"' } else { "codeql" }

_py_formatter := if SEMMLE_CODE != "" { "uv run black" } else { "black" }

_cpp_formatter := if SEMMLE_CODE != "" { "uv run clang-format" } else { "clang-format" }

# The `buildifier` target formats a whole workspace and so cannot take a path, so its
# binary is driven directly. bazel is asked from this repository's root even when it sits
# inside another, and the files are bounded to it, so each repository formats its own with
# the version it pins. Building needs the enclosing workspace instead, hence `_bazel`.
_bazel_workspace := quote(parent_directory(parent_directory(source_dir())))

_bazel_formatter := (if SEMMLE_CODE != "" { '"$SEMMLE_CODE/tools/bazel"' } else { "bazel" }) + " run --noshow_progress --ui_event_filters=,+error,+fail @buildifier_prebuilt//:buildifier --"

# Keep in step with the `buildifier` target's own exclusions, or `just format` rewrites
# what pre-commit and CI deliberately leave alone. Patterns match the path as walked, so
# one naming a directory has to cover both how it is reached and how it is walked.
_bazel_names := "BUILD,WORKSPACE,*.bazel,*.bzl,*.sky"

_bazel_excluded := ".git/*,*/.git/*,*misc/bazel/3rdparty/*_deps/*"

# buildifier only names what it rewrote if it also accounts for every file it did not.
_bazel_accounting := ': applied fixes, [0-9]+ warnings left$'

# These formatters take files rather than directories, so `run_on_files.py` collects them
# and passes them positionally, which is what lets paths contain spaces. `codeql query
# format` likewise only reports what it rewrote if it also names everything it did not, so
# those lines are dropped and nothing else is.
#
# `[no-cd]` keeps a relative argument meaning the caller's directory: the forwarder passes
# `--justfile`, so without it the default `.` would silently become the whole repository.

[no-cd]
[no-exit-message]
[positional-arguments]
_format_ql +ARGS: (_maybe_build_dist "nolang")
    {{ cmd_sep }}{{ py }} "{{ source_dir() }}/run_on_files.py" --drop '^Formatting ' --drop '^No change for ' "*.ql,*.qll" {{ _ql_formatter }} query format --in-place -v -- "$@"{{ cmd_sep }}

[no-cd]
[no-exit-message]
[positional-arguments]
_format_py *ARGS=".":
    {{ cmd_sep }}{{ _py_formatter }} "$@"{{ cmd_sep }}

[no-cd]
[no-exit-message]
[positional-arguments]
_format_cpp *ARGS=".":
    {{ cmd_sep }}{{ py }} "{{ source_dir() }}/run_on_files.py" "*.h,*.cpp" {{ _cpp_formatter }} -i -- "$@"{{ cmd_sep }}

[no-cd]
[no-exit-message]
[positional-arguments]
_format_bazel *ARGS=".":
    {{ cmd_sep }}{{ py }} "{{ source_dir() }}/run_on_files.py" --absolute --chdir {{ _bazel_workspace }} --within {{ _bazel_workspace }} --drop '{{ _bazel_accounting }}' --exclude '{{ _bazel_excluded }}' "{{ _bazel_names }}" {{ _bazel_formatter }} -mode=fix -lint=fix -v -- "$@"{{ cmd_sep }}
