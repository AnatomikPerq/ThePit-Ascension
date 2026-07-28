"""End-to-end: boot the real application and drive a run through it.

Scope, stated up front, because this suite is easy to over-trust:

PlayGodot's node, property and method-call API works against this project.
Its *input injection* does not — neither `press_key` nor `press_action` reaches
the game, headless or with a real WSLg window. That matches the warning GdUnit4
prints too ("Godot InputEvents are not transported by the engine in headless
mode"). So these tests drive the game through the same public API the input
layer calls, rather than through synthetic keystrokes.

Keyboard paths are covered instead by `tools/state_probe.gd`, which runs on the
stock Godot 4.7 that actually builds the game and feeds real InputEventKey
objects through `Input.parse_input_event()`. What is verified there is the
InputMap wiring; what is verified here is that the whole application holds
together across a scene change.
"""

import asyncio

import pytest

MENU = "/root/MainMenu"
WORLD = "/root/World"


async def _start_run(game):
    """Menu -> world, through the same call the START button is wired to."""
    await game.wait_for_node(MENU, timeout=30.0)
    await game.call(MENU, "_start_game")
    await game.wait_for_node(WORLD, timeout=30.0)
    # Let _ready finish generating the level and spawning the player.
    await asyncio.sleep(0.5)


@pytest.mark.asyncio
async def test_boots_to_the_main_menu(game):
    await game.wait_for_node(MENU, timeout=30.0)
    assert await game.node_exists(MENU)


@pytest.mark.asyncio
async def test_autoloads_are_present(game):
    await game.wait_for_node(MENU, timeout=30.0)
    for autoload in ("/root/Fx", "/root/Audio", "/root/Game"):
        assert await game.node_exists(autoload), f"{autoload} is missing"


@pytest.mark.asyncio
async def test_menu_starts_a_run(game):
    await _start_run(game)
    assert await game.node_exists(WORLD)
    assert await game.node_exists(WORLD + "/Player")


@pytest.mark.asyncio
async def test_player_spawns_deep_in_the_pit(game):
    await _start_run(game)
    pos = await game.get_property(WORLD + "/Player", "global_position")
    max_depth = await game.get_property(WORLD, "max_depth")
    # Spawn is max_depth - 300; 0 is the surface, so a large y means deep.
    assert pos["y"] > max_depth - 600


@pytest.mark.asyncio
async def test_the_world_builds_its_containers(game):
    await _start_run(game)
    for container in ("Platforms", "Enemies", "Trampolines"):
        assert await game.node_exists(f"{WORLD}/{container}"), container


@pytest.mark.asyncio
async def test_pause_and_resume(game):
    await _start_run(game)
    assert not await game.is_paused()

    await game.call(WORLD, "cancel_pressed")
    await asyncio.sleep(0.2)
    assert await game.is_paused()

    await game.call(WORLD, "cancel_pressed")
    await asyncio.sleep(0.2)
    assert not await game.is_paused()


@pytest.mark.asyncio
async def test_restart_works_while_paused(game):
    """The owner's headline bug. The pause overlay advertises 'R - restart' and R
    used to do nothing, because the handler lived on a node that stops processing
    when the tree pauses. Here the reload is exercised from the paused state
    through the whole running application."""
    await _start_run(game)
    await game.call(WORLD, "cancel_pressed")
    await asyncio.sleep(0.2)
    assert await game.is_paused()

    await game.call(WORLD, "restart")
    await game.wait_for_node(WORLD, timeout=30.0)
    await asyncio.sleep(0.5)
    assert not await game.is_paused(), "restart left the tree paused"
    assert await game.node_exists(WORLD + "/Player")


@pytest.mark.asyncio
async def test_music_can_be_toggled(game):
    await game.wait_for_node(MENU, timeout=30.0)
    before = await game.get_property("/root/Audio", "music_enabled")
    await game.call("/root/Audio", "toggle_music")
    await asyncio.sleep(0.2)
    assert await game.get_property("/root/Audio", "music_enabled") != before


@pytest.mark.asyncio
async def test_no_global_time_scale_is_ever_applied(game):
    """The kill hitstop used to drive Engine.time_scale. It is gone and must stay
    gone: a peer whose clock is scaled desynchronises from everyone else."""
    await _start_run(game)
    assert await game.get_time_scale() == pytest.approx(1.0)
