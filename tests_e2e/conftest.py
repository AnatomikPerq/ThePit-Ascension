"""Shared fixtures for the PlayGodot end-to-end suite.

These tests drive the real game from the real main scene, over Godot's native
RemoteDebugger protocol. That is coverage the in-engine GdUnit suites cannot
reach: menu-to-world transitions, input travelling through the actual InputMap,
and the state of the whole tree rather than a scene instantiated in isolation.

Requirements are unusual and deliberately isolated from the normal workflow —
see README.md in this directory. Everything else in the project is tested with
the stock Godot 4.7 that builds the game.
"""

import os
from pathlib import Path

import pytest
import pytest_asyncio
from playgodot import Godot

PROJECT = Path(os.environ.get("E2E_PROJECT", Path(__file__).resolve().parents[1]))
GODOT_PATH = os.environ.get("GODOT_PATH", "")

# Generous: the first launch imports the project.
LAUNCH_TIMEOUT = float(os.environ.get("E2E_TIMEOUT", "60"))


@pytest_asyncio.fixture
async def game():
    """A running instance of the game, torn down after each test."""
    if not GODOT_PATH:
        pytest.skip("GODOT_PATH is not set; see tests_e2e/README.md")
    async with Godot.launch(
        str(PROJECT),
        headless=True,
        timeout=LAUNCH_TIMEOUT,
        godot_path=GODOT_PATH,
    ) as instance:
        yield instance
