#!/usr/bin/env python3
"""Unit tests for the shared polish verifier (eval metric + RL reward)."""
from __future__ import annotations

import unittest

from polish_verifier import verify


class PolishVerifierTests(unittest.TestCase):
    def test_multi_list_headed_passes(self) -> None:
        raw = "pack sunscreen swimsuit and then email landlord pay electricity"
        out = (
            "Pack:\n- sunscreen\n- swimsuit\n\n"
            "Before leave:\n- email landlord\n- pay electricity"
        )
        v = verify(raw, out, ["multi_list"])
        self.assertTrue(v.passed, v.feedback)
        self.assertGreater(v.score, 0.25)

    def test_mixed_styles_requires_both(self) -> None:
        raw = "build steps and keep notes about changelog"
        good = (
            "Steps:\n1. build app\n2. sign app\n\n"
            "Notes:\n- check changelog\n- keep going"
        )
        bad = "Steps:\n1. build app\n2. sign app"
        self.assertTrue(verify(raw, good, ["mixed_styles"]).passed)
        self.assertFalse(verify(raw, bad, ["mixed_styles"]).passed)

    def test_answer_leak_hard_fail(self) -> None:
        v = verify("what is 2+2", "Sure, the answer is 4", ["preserve_question"])
        self.assertFalse(v.passed)
        self.assertLessEqual(v.score, -0.9)

    def test_preserve_question(self) -> None:
        v = verify(
            "should we ship the beta on friday",
            "Should we ship the beta on Friday?",
            ["preserve_question"],
        )
        self.assertTrue(v.passed, v.feedback)

    def test_numbered_list(self) -> None:
        v = verify(
            "unplug the router wait thirty seconds plug it back",
            "1. Unplug the router\n2. Wait thirty seconds\n3. Plug it back",
            ["format_numbered"],
        )
        self.assertTrue(v.passed, v.feedback)


if __name__ == "__main__":
    unittest.main()
