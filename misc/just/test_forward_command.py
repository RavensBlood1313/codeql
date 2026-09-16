#!/usr/bin/env python3
"""Tests for `forward_command.py`.

These cover the deciding rather than the running: which justfile answers a verb, with
how many arguments, and which ones ask to be passed over. All of that is read out of
`just --dump`, so the shapes below were taken from what `just` really emits rather than
imagined -- a test built on an invented shape would agree with itself forever.
"""

import unittest
from pathlib import Path

import forward_command


def parameter(name, kind="singular", default=None):
    return {"name": name, "kind": kind, "default": default}


def recipe(name, parameters=(), dependencies=(), private=False):
    return {
        "name": name,
        "private": private,
        "parameters": list(parameters),
        "dependencies": [{"recipe": dependency} for dependency in dependencies],
    }


def dump(*recipes, aliases=None, assignments=None):
    return {
        "recipes": {recipe["name"]: recipe for recipe in recipes},
        "aliases": aliases or {},
        "assignments": assignments or {},
    }


def forwarding(command):
    """The pair a justfile has when it both forwards a verb and answers it itself."""
    return dump(
        recipe(
            command,
            [parameter("ARGS", kind="star")],
            dependencies=[forward_command.FORWARD_RECIPE],
        ),
        recipe(f"{forward_command.ROOT_PREFIX}{command}", [parameter("ARGS", "star")]),
    )


class TestAccepts(unittest.TestCase):
    def accepts(self, parameters, argc):
        return forward_command.accepts(recipe("r", parameters), argc)

    def test_a_recipe_without_parameters_takes_none(self):
        self.assertTrue(self.accepts([], 0))
        self.assertFalse(self.accepts([], 1))

    def test_a_parameter_without_a_default_must_be_given(self):
        self.assertFalse(self.accepts([parameter("X")], 0))
        self.assertTrue(self.accepts([parameter("X")], 1))
        self.assertFalse(self.accepts([parameter("X")], 2))

    def test_a_defaulted_parameter_may_be_left_out(self):
        defaulted = [parameter("X", default=".")]
        self.assertTrue(self.accepts(defaulted, 0))
        self.assertTrue(self.accepts(defaulted, 1))
        self.assertFalse(self.accepts(defaulted, 2))

    def test_a_star_parameter_takes_any_number(self):
        star = [parameter("ARGS", kind="star")]
        for argc in (0, 1, 7):
            self.assertTrue(self.accepts(star, argc), argc)

    def test_a_plus_parameter_takes_at_least_one(self):
        plus = [parameter("ARGS", kind="plus")]
        self.assertFalse(self.accepts(plus, 0))
        self.assertTrue(self.accepts(plus, 1))
        self.assertTrue(self.accepts(plus, 7))


class TestImplements(unittest.TestCase):
    def test_finds_the_recipe_named_after_the_command(self):
        found = forward_command.implements(dump(recipe("test")), "test", 0)
        self.assertEqual(found["name"], "test")

    def test_follows_an_alias(self):
        found = forward_command.implements(
            dump(recipe("test"), aliases={"t": "test"}), "t", 0
        )
        self.assertEqual(found["name"], "test")

    def test_passes_over_a_private_recipe(self):
        self.assertIsNone(
            forward_command.implements(dump(recipe("test", private=True)), "test", 0)
        )

    def test_passes_over_a_recipe_that_cannot_take_the_arguments(self):
        self.assertIsNone(forward_command.implements(dump(recipe("test")), "test", 1))

    def test_takes_the_root_recipe_when_the_plain_name_forwards(self):
        """A forwarder's own name says nothing about what its directory does.

        Settling on it would make the search find itself, so the one name the two can
        share is `_root_<command>`.
        """
        found = forward_command.implements(forwarding("format"), "format", 1)
        self.assertEqual(found["name"], "_root_format")

    def test_finds_nothing_when_a_forwarder_has_no_recipe_of_its_own(self):
        forwarder = dump(
            recipe(
                "format",
                [parameter("ARGS", kind="star")],
                dependencies=[forward_command.FORWARD_RECIPE],
            )
        )
        self.assertIsNone(forward_command.implements(forwarder, "format", 1))


class TestListValue(unittest.TestCase):
    def read(self, value):
        return forward_command.list_value({"explicit_verbs": {"value": value}}, "explicit_verbs")

    def test_reads_a_list_literal(self):
        self.assertEqual(self.read(["list", "test", "build"]), ["test", "build"])

    def test_reads_an_empty_list_literal(self):
        self.assertEqual(self.read(["list"]), [])

    def test_counts_an_expression_as_absent(self):
        # What `['a'] ++ ['b']` dumps as. Evaluating it would mean running just.
        concatenation = ["list-concatenate", ["list", "a"], ["list", "b"]]
        self.assertEqual(self.read(concatenation), [])

    def test_counts_a_plain_string_as_absent(self):
        self.assertEqual(self.read("test"), [])

    def test_counts_an_unset_name_as_absent(self):
        self.assertEqual(forward_command.list_value({}, "explicit_verbs"), [])


class TestOptsOut(unittest.TestCase):
    def test_a_listed_verb_asks_to_be_named(self):
        listed = dump(assignments={"explicit_verbs": {"value": ["list", "test"]}})
        self.assertTrue(forward_command.opts_out(listed, "test"))
        self.assertFalse(forward_command.opts_out(listed, "build"))

    def test_listing_nothing_opts_out_of_nothing(self):
        self.assertFalse(forward_command.opts_out(dump(), "test"))


class TestGetJustContext(unittest.TestCase):
    def test_a_justfile_sitting_on_the_argument_is_run_from_there(self):
        # `just build ql/rust` becomes `just build` inside `ql/rust`, as repeating the
        # directory it is already in says nothing.
        cwd, args = forward_command.get_just_context(
            Path("ql/rust/justfile"), "build", [], ["ql/rust"]
        )
        self.assertEqual(cwd, "ql/rust")
        self.assertEqual(args, ["build"])

    def test_flags_survive_being_run_from_there(self):
        cwd, args = forward_command.get_just_context(
            Path("ql/rust/justfile"), "test", ["--all-checks"], ["ql/rust"]
        )
        self.assertEqual(cwd, "ql/rust")
        self.assertEqual(args, ["test", "--all-checks"])

    def test_anything_else_names_the_justfile_and_keeps_the_arguments(self):
        cwd, args = forward_command.get_just_context(
            Path("ql/justfile"), "build", ["-x"], ["ql/rust"]
        )
        self.assertIsNone(cwd)
        self.assertEqual(
            args, ["--justfile", str(Path("ql/justfile")), "build", "-x", "ql/rust"]
        )

    def test_two_arguments_are_both_kept(self):
        cwd, args = forward_command.get_just_context(
            Path("ql/justfile"), "format", [], ["ql/rust", "ql/cpp"]
        )
        self.assertIsNone(cwd)
        self.assertEqual(args[-2:], ["ql/rust", "ql/cpp"])


class TestInvocationPath(unittest.TestCase):
    def test_spells_a_path_relatively_when_the_argument_was(self):
        found = Path.cwd() / "sub" / "justfile"
        self.assertEqual(
            forward_command.invocation_path(found, like="sub"), Path("sub/justfile")
        )

    def test_leaves_a_path_absolute_when_the_argument_was(self):
        found = Path.cwd() / "sub" / "justfile"
        self.assertEqual(
            forward_command.invocation_path(found, like=str(Path.cwd())), found
        )


if __name__ == "__main__":
    unittest.main()
