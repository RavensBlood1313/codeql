import? '../../../semmle-code.just' # internal repo just file, if present
import 'semmle-code-stub.just'

# `set lists` is what lets recipes forward argument lists without encoding them as
# whitespace separated strings. It is still unstable as of just 1.58.
set unstable
set lists
set fallback
set allow-duplicate-recipes
set allow-duplicate-variables

export PATH_SEP := if os() == "windows" { ";" } else { ":" }
export JUST_EXECUTABLE := just_executable()

error := f'{{ style("error") }}error{{ NORMAL }}: '

# The separator line, sized to the terminal.
#
# `stty` rather than `tput`: it needs no terminfo, so it survives `TERM=dumb`, and reads
# the terminal from stdin, so it answers when stdout is piped. The arithmetic is in the
# shell because just has no integers.
#
# With no terminal the value is non-numeric and this falls back to a fixed 57 columns.
# That is a branch, not a platform test: just runs `sh` everywhere.
#
# `JUST_CMD_RULE` is the whole line and lands in a shell script, so a value set by hand
# has to be a comment itself.
#
# Exported and preferred over measuring: `shell()` runs on every parse, so a forwarded
# verb would otherwise re-measure in every child it spawns, and `if` is lazy in its
# branches. Inheritance needs a process, so a `mod` measures for itself; presetting
# `JUST_CMD_RULE` skips measuring entirely.
_rule := if env('JUST_CMD_RULE', '') != '' { env('JUST_CMD_RULE', '') } else { shell('''
    w=$(stty size 2>/dev/null | cut -d" " -f2)
    case "$w" in '' | *[!0-9]*) w=57 ;; esac
    printf "%*s" $w "" | tr " " '#'
''') }

export JUST_CMD_RULE := _rule

cmd_sep := "\n" + _rule + "\n"
export CMD_BEGIN := style("command") + cmd_sep
export CMD_END := cmd_sep + NORMAL
export JUST_ERROR := error

py := "python3"

default_db_checks := ['--check-databases', '--check-diff-informed', '--fail-on-trap-errors']

[no-exit-message]
@_require_semmle_code:
    {{ if SEMMLE_CODE == "" { f'''
        echo "{error} running this recipe requires doing so from an internal repository checkout" >&2
        exit 1
    ''' } else { "" } }}

[no-cd]
_run +ARGS:
    {{ cmd_sep }}{{ ARGS }}{{ cmd_sep }}

[no-cd]
_run_in DIR +ARGS:
    {{ cmd_sep }}cd "{{ DIR }}"; {{ ARGS }}{{ cmd_sep }}

[no-cd]
_run_in_semmle_code +ARGS: _require_semmle_code (_run_in "$SEMMLE_CODE" ARGS)

[no-cd]
[no-exit-message]
[positional-arguments]
@_just +ARGS:
    echo "-> just $@"
    "{{ JUST_EXECUTABLE }}" "$@"

[no-cd]
[positional-arguments]
@_if_not_on_ci_just +ARGS:
    if [ "${GITHUB_ACTIONS:-}" != "true" ]; then \
        echo "-> just $@"; \
        "$JUST_EXECUTABLE" "$@"; \
    fi

[no-cd]
[no-exit-message]
_if_in_semmle_code THEN ELSE *ARGS:
    {{ cmd_sep }}{{ if SEMMLE_CODE != "" { THEN } else { ELSE } }} {{ ARGS }}{{ cmd_sep }}
