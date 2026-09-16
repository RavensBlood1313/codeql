import "build.just"

# These formatters take files rather than directories, so `run_on_files.py` collects them
# and passes them positionally, which is what lets paths contain spaces. Both name every
# file they were given, so the lines saying nothing happened are dropped: for buildifier
# that is an empty warning tally, and a non-zero one is left alone, being the only notice
# of what it could not fix now that the exit code is 0 either way.
#
# The banner is a report rather than a command to paste: it names the formatter and what
# it is told to do, and leaves out the collecting, the patterns walked and the flags that
# only shape output. `just -n` prints what actually runs, `@` or no `@`. Pasting never
# worked anyway: the banner used to carry an unexpanded `"$@"`, which matches no file in
# another shell and so formatted nothing while exiting 0.
#
# `[no-cd]` keeps a relative argument meaning the caller's directory: the forwarder passes
# `--justfile`, so without it the default `.` would silently become the whole repository.

_ql_formatter := (if SEMMLE_CODE != "" { '"$SEMMLE_CODE/target/intree/codeql-nolang/codeql"' } else { "codeql" }) + " query format --in-place"

[no-cd]
[no-exit-message]
[positional-arguments]
@_format_ql +ARGS: (_maybe_build_dist "nolang")
    echo "$CMD_BEGIN-> "{{ quote(_ql_formatter) }}" -- $*$CMD_END" >&2
    {{ py }} "{{ source_dir() }}/run_on_files.py" --drop '^Formatting ' --drop '^No change for ' "*.ql,*.qll" {{ _ql_formatter }} -v -- "$@"

_py_formatter := if SEMMLE_CODE != "" { "uv run black" } else { "black" }

[no-cd]
[no-exit-message]
[positional-arguments]
@_format_py *ARGS=".":
    echo "$CMD_BEGIN-> "{{ quote(_py_formatter) }}" $*$CMD_END" >&2
    {{ _py_formatter }} "$@"

_cpp_formatter := (if SEMMLE_CODE != "" { "uv run clang-format" } else { "clang-format" }) + " -i"

[no-cd]
[no-exit-message]
[positional-arguments]
@_format_cpp *ARGS=".":
    echo "$CMD_BEGIN-> "{{ quote(_cpp_formatter) }}" -- $*$CMD_END" >&2
    {{ py }} "{{ source_dir() }}/run_on_files.py" "*.h,*.cpp" {{ _cpp_formatter }} -- "$@"

# The `buildifier` target formats a whole workspace and so cannot take a path, so its
# binary is driven directly. bazel is asked from this repository's root even when it sits
# inside another, and the files are bounded to it, so each repository formats its own with
# the version it pins. Building needs the enclosing workspace instead, hence `_bazel`.
_bazel_workspace := quote(parent_directory(parent_directory(source_dir())))

_bazel_formatter := (if SEMMLE_CODE != "" { '"$SEMMLE_CODE/tools/bazel"' } else { "bazel" }) + " run @buildifier_prebuilt//:buildifier"

# Kept out of the formatter, unlike the other three: bazel's own flags have to sit between
# the target and `--`, so no single string spans both sides of it.
_bazel_args := "-mode=fix -lint=fix"

# Keep both in step with the `buildifier` target. The names are what it recognises walking a
# workspace, a check it skips for paths handed to it, so anything extra here is rewritten
# regardless. Being wider is deliberate: what it recognises differs between versions, and
# each repository pins its own, so only a list covering every one of them can be shared. A
# directory of one file per candidate name, formatted with `-r`, says what a version takes.
# Exclusions match the path as walked and its absolute form, so one that has to hold
# however the path was reached is anchored absolutely.
_bazel_names := "BUILD,WORKSPACE,*.bazel,*.bzl,*.sky,*.star"

_bazel_excluded := ".git/*,*/.git/*,*misc/bazel/3rdparty/*_deps/*"

[no-cd]
[no-exit-message]
[positional-arguments]
@_format_bazel *ARGS=".":
    echo "$CMD_BEGIN-> "{{ quote(_bazel_formatter + " -- " + _bazel_args) }}" -- $*$CMD_END" >&2
    {{ py }} "{{ source_dir() }}/run_on_files.py" --absolute --chdir {{ _bazel_workspace }} --within {{ _bazel_workspace }} --drop ': applied fixes, 0 warnings left$' --exclude '{{ _bazel_excluded }}' "{{ _bazel_names }}" {{ _bazel_formatter }} --noshow_progress --ui_event_filters=,+error,+fail -- {{ _bazel_args }} -v -- "$@"
