import "build.just"

_ql_formatter := if SEMMLE_CODE != "" { '"$SEMMLE_CODE/target/intree/codeql-nolang/codeql"' } else { "codeql" }

_ql_args := "query format --in-place"

_py_formatter := if SEMMLE_CODE != "" { "uv run black" } else { "black" }

_cpp_formatter := if SEMMLE_CODE != "" { "uv run clang-format" } else { "clang-format" }

_cpp_args := "-i"

# The `buildifier` target formats a whole workspace and so cannot take a path, so its
# binary is driven directly. bazel is asked from this repository's root even when it sits
# inside another, and the files are bounded to it, so each repository formats its own with
# the version it pins. Building needs the enclosing workspace instead, hence `_bazel`.
_bazel_workspace := quote(parent_directory(parent_directory(source_dir())))

_bazel_formatter := (if SEMMLE_CODE != "" { '"$SEMMLE_CODE/tools/bazel"' } else { "bazel" }) + " run @buildifier_prebuilt//:buildifier"

_bazel_args := "-mode=fix -lint=fix"

# Held apart from the invocation because only output is at stake, which is what the banner
# leaves out. bazel takes these after the target as readily as before it.
_bazel_quiet := "--noshow_progress --ui_event_filters=,+error,+fail"

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
# The banner is a report rather than a command to paste: it names the formatter and what
# it is told to do, and leaves out the collecting, the patterns walked and the flags that
# only shape output. `just -n` prints what actually runs, `@` or no `@`. Pasting never
# worked anyway: the banner used to carry an unexpanded `"$@"`, which matches no file in
# another shell and so formatted nothing while exiting 0.
#
# `[no-cd]` keeps a relative argument meaning the caller's directory: the forwarder passes
# `--justfile`, so without it the default `.` would silently become the whole repository.

[no-cd]
[no-exit-message]
[positional-arguments]
@_format_ql +ARGS: (_maybe_build_dist "nolang")
    echo "$CMD_BEGIN-> {{ _ql_formatter }} {{ _ql_args }} -- $*$CMD_END" >&2
    {{ py }} "{{ source_dir() }}/run_on_files.py" --drop '^Formatting ' --drop '^No change for ' "*.ql,*.qll" {{ _ql_formatter }} {{ _ql_args }} -v -- "$@"

[no-cd]
[no-exit-message]
[positional-arguments]
@_format_py *ARGS=".":
    echo "$CMD_BEGIN-> {{ _py_formatter }} $*$CMD_END" >&2
    {{ _py_formatter }} "$@"

[no-cd]
[no-exit-message]
[positional-arguments]
@_format_cpp *ARGS=".":
    echo "$CMD_BEGIN-> {{ _cpp_formatter }} {{ _cpp_args }} -- $*$CMD_END" >&2
    {{ py }} "{{ source_dir() }}/run_on_files.py" "*.h,*.cpp" {{ _cpp_formatter }} {{ _cpp_args }} -- "$@"

[no-cd]
[no-exit-message]
[positional-arguments]
@_format_bazel *ARGS=".":
    echo "$CMD_BEGIN-> {{ _bazel_formatter }} -- {{ _bazel_args }} -- $*$CMD_END" >&2
    {{ py }} "{{ source_dir() }}/run_on_files.py" --absolute --chdir {{ _bazel_workspace }} --within {{ _bazel_workspace }} --drop '{{ _bazel_accounting }}' --exclude '{{ _bazel_excluded }}' "{{ _bazel_names }}" {{ _bazel_formatter }} {{ _bazel_quiet }} -- {{ _bazel_args }} -v -- "$@"
