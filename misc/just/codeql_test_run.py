#!/usr/bin/env python3
"""Run CodeQL tests with appropriate configuration.

Called from just recipes as:
    python3 codeql_test_run.py LANGUAGE [ARG...]

Arguments are already split by `just` (see `set lists`), so each one is taken verbatim.
`--extra-check=FLAG` offers FLAG as a check to run, and `--all-checks` (or its `+`
abbreviation) turns the offered ones on. Per-language justfiles supply the offers and
the caller supplies the switch, so the two are separate options rather than one.
"""

import dataclasses
import os
import re
import subprocess
import sys
from pathlib import Path

JUST = os.environ.get("JUST_EXECUTABLE", "just")
ERROR = os.environ.get("JUST_ERROR", "error: ")
CMD_BEGIN = os.environ.get("CMD_BEGIN", "")
CMD_END = os.environ.get("CMD_END", "")
SEMMLE_CODE = os.environ.get("SEMMLE_CODE")

EXTRA_CHECK_PREFIX = "--extra-check="
ENV_RE = re.compile(r"^[A-Z_][A-Z_0-9]*=.*$")


def invoke(invocation, *, cwd=None, log_prefix=""):
    prefix = f"{log_prefix} " if log_prefix else ""
    print(f"{CMD_BEGIN}{prefix}{' '.join(invocation)}{CMD_END}")
    try:
        subprocess.run(invocation, check=True, cwd=cwd)
    except subprocess.CalledProcessError as e:
        return e.returncode
    return 0


def error(message):
    print(f"{ERROR}{message}", file=sys.stderr)


@dataclasses.dataclass
class Arguments:
    """A command line sorted into the kinds that are handled differently.

    Sorted by hand rather than by `argparse`, which could own the three options named
    below but none of the rest: every flag not named here belongs to `codeql test run`
    and has to survive untouched, `+` is not a spelling `argparse` has, and `CPUS=4` and
    `ql/test` are both positionals told apart only by shape. Handing it the half it can
    take would leave this loop in place for the other half.
    """

    codeql: str = dataclasses.field(
        default_factory=lambda: "build" if SEMMLE_CODE else "host"
    )
    all: bool = False
    tests: list = dataclasses.field(default_factory=list)
    flags: list = dataclasses.field(default_factory=list)
    env: list = dataclasses.field(default_factory=list)
    extra_checks: list = dataclasses.field(default_factory=list)

    def parse(self, argv):
        """Sort arguments into tests, flags and environment assignments."""
        for arg in argv:
            if not arg:
                # an empty argument can come from a caller interpolating an unset
                # variable
                continue
            if arg.startswith(EXTRA_CHECK_PREFIX):
                self.extra_checks.append(arg[len(EXTRA_CHECK_PREFIX) :])
            elif arg.startswith("--codeql="):
                self.codeql = arg.split("=", 1)[1]
            elif arg in ("+", "--all-checks"):
                self.all = True
            elif arg.startswith("-"):
                self.flags.append(arg)
            elif ENV_RE.match(arg):
                self.env.append(arg)
            else:
                self.tests.append(arg)

    def env_value(self, name, default):
        """Resolve a setting from test arguments, then the environment, then a default."""
        for assignment in reversed(self.env):
            key, _, value = assignment.partition("=")
            if key == name and value:
                return value
        return os.environ.get(name) or default


def main():
    argv = sys.argv[1:]
    if not argv:
        error("Usage: codeql_test_run.py LANGUAGE [ARG...]")
        return 1

    language, *rest = argv

    args = Arguments()
    args.parse(rest)
    if args.all:
        args.parse(args.extra_checks)

    if not SEMMLE_CODE and args.codeql in ("build", "built"):
        error(
            "Using `--codeql=build` or `--codeql=built` requires working "
            "with the internal repository"
        )
        return 1

    if not args.tests:
        args.tests.append(".")

    # Resolve these only once all arguments are known, so that a `RAM_PER_THREAD=` test
    # argument can lower the default on memory-heavy suites.
    default_ram = 3000 if sys.platform == "linux" else 2048
    ram_per_thread = int(args.env_value("RAM_PER_THREAD", default_ram))
    cpus = int(args.env_value("CPUS", os.cpu_count() or 1))
    args.flags[:0] = [f"--ram={ram_per_thread * cpus}", f"-j{cpus}"]

    if args.codeql == "build":
        if invoke([JUST, language, "build"], cwd=SEMMLE_CODE) != 0:
            return 1

    if args.codeql != "host":
        # Disable the default implicit config file, but keep an explicit one.
        # Same behavior wrt --codeql as the integration test runner.
        os.environ.setdefault("CODEQL_CONFIG_FILE", ".")

    for env_var in args.env:
        key, _, value = env_var.partition("=")
        if not key:
            error(f"Invalid environment variable assignment: {env_var}")
            return 1
        os.environ[key] = value

    # Resolve codeql executable
    if args.codeql in ("built", "build"):
        codeql = Path(SEMMLE_CODE, "target", "intree", f"codeql-{language}", "codeql")
    elif args.codeql == "host":
        codeql = Path("codeql")
    else:
        codeql = Path(args.codeql)

    if codeql.is_dir():
        codeql = codeql / "codeql"

    # On Windows, prefer codeql.exe over the Unix shell wrapper
    if sys.platform == "win32" and codeql.suffix != ".exe":
        exe = codeql.with_suffix(".exe")
        if exe.exists():
            codeql = exe

    if args.codeql != "host" and not codeql.exists():
        error(f"CodeQL executable not found: {codeql}")
        return 1

    return invoke(
        [str(codeql), "test", "run", *args.flags, "--", *args.tests],
        log_prefix=" ".join(args.env),
    )


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(128 + 2)
