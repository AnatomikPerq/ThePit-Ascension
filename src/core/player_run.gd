class_name PlayerRun
extends RefCounted
## One player's state for one run: score, kills, combo chain. Game holds one
## of these per peer, keyed by peer id — solo play is simply a single entry.
## Everything here is authoritative simulation state; in a networked session
## the host owns it and clients mirror it.

var peer_id: int = 1
var score: int = 0
var kills: int = 0
var combo: int = 0
var max_combo: int = 0
## Seconds left before the combo chain expires.
var combo_time: float = 0.0
