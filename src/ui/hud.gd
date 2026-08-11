class_name RunHud
extends Control
## In-run HUD. The layout is authored in HUD.tscn; this script only feeds it
## data. World calls update() every frame and the event hooks on change.

const HEART_FULL_TEX: Texture2D = preload("res://assets/sprites/heart_full.png")
const HEART_EMPTY_TEX: Texture2D = preload("res://assets/sprites/heart_empty.png")

@onready var hp_bar: HBoxContainer = $HPBar
@onready var score_label: Label = $ScoreLabel
@onready var combo_label: Label = $ComboLabel
@onready var depth_label: Label = $DepthLabel
@onready var skills_label: Label = $SkillsLabel
@onready var flight_label: Label = $FlightLabel
@onready var notif_label: Label = $NotificationLabel
@onready var fps_label: Label = $FPSLabel
@onready var ascent_bar: ProgressBar = $AscentBar
@onready var strike_icon: Panel = $AbilityIcons/StrikeIcon
@onready var shockwave_icon: Panel = $AbilityIcons/ShockwaveIcon
## The railgun's charge meter. Shown only for an avatar carrying something that
## HAS charges — the HUD asks the weapon, never the character.
@onready var rail_gauge: RailGauge = $AbilityIcons/RailGauge
@onready var spectator_bar: Label = $SpectatorBar

var _notification_timer: float = 0.0
var _combo_tween: Tween
## The widgets that are about an avatar. A spectator has none, so rather than
## every one of them learning about spectating they are simply switched off
## together.
@onready var _avatar_widgets: Array[Control] = [
	hp_bar, score_label, depth_label, skills_label, ascent_bar,
	$SurfaceLabel, $AbilityIcons,
]


## (Re)build the heart row. Called on spawn and when max HP grows.
func build_hp_bar(max_health: int, health: int) -> void:
	for child in hp_bar.get_children():
		hp_bar.remove_child(child)
		child.queue_free()
	for i in range(max_health):
		var heart := TextureRect.new()
		heart.custom_minimum_size = Vector2(42, 36)
		heart.stretch_mode = TextureRect.STRETCH_SCALE
		heart.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		heart.texture = HEART_FULL_TEX if i < health else HEART_EMPTY_TEX
		hp_bar.add_child(heart)


func update_hp(health: int) -> void:
	var hearts := hp_bar.get_children()
	for i in range(hearts.size()):
		hearts[i].texture = HEART_FULL_TEX if i < health else HEART_EMPTY_TEX


func show_notification(text: String) -> void:
	notif_label.text = text
	_notification_timer = 3.0


## Per-frame refresh, driven by World while the run plays.
func update(player: CharacterBody2D, max_depth: float, delta: float) -> void:
	depth_label.text = "DEPTH: %d" % int(player.global_position.y)

	var skills_text := "Skills: "
	if player.max_jumps > 1:
		skills_text += "[JUMP x%d] " % player.max_jumps
	if player.has_attack:
		skills_text += "[STRIKE] "
	if player.has_shockwave:
		skills_text += "[SHOCKWAVE] "
	if player.flying:
		skills_text += "[FLIGHT] "
	skills_label.text = skills_text
	flight_label.text = "FLIGHT MODE ACTIVE" if player.flying else ""

	var ascent := clampf(1.0 - player.global_position.y / max_depth, 0.0, 1.0)
	ascent_bar.value = ascent * 100.0

	strike_icon.visible = player.has_attack
	strike_icon.modulate.a = 0.35 if not player.strike_cd_timer.is_stopped() else 1.0
	shockwave_icon.visible = player.has_shockwave
	shockwave_icon.modulate.a = 0.35 if not player.shockwave_cd_timer.is_stopped() else 1.0
	_update_weapon(player.weapon)

	if _notification_timer > 0.0:
		_notification_timer -= delta
		if _notification_timer <= 0.0:
			notif_label.text = ""

	fps_label.text = "FPS: %d" % Engine.get_frames_per_second()


## A carried weapon, if it is the kind that holds charges.
##
## The question asked is "does this thing have a fill and is it armed", never
## "is this Uzi" — a second charged weapon later lights the same meter up with no
## change here. `carried.armed()` is what keeps the gun off the bar until the
## upgrade that grants it has actually been taken.
func _update_weapon(carried: Node) -> void:
	var charged := carried != null and carried.has_method(&"fill") \
		and bool(carried.call(&"armed"))
	rail_gauge.visible = charged
	if not charged:
		rail_gauge.forget()
		return
	# `meter()`, not `fill()`: what can be fired right now plus what is being
	# earned, rather than what the gun holds. See Railgun.meter(). `capacity()` is
	# what a full gun holds — the scale the marks along the top divide up.
	rail_gauge.show_charge(float(carried.call(&"meter")), int(carried.get(&"charges")),
		int(carried.call(&"capacity")))


# ── Spectating ──────────────────────────────────────────────────────────────
## Everything about an avatar goes away; one line along the bottom says what the
## keys do. Called by World when this machine stops having a body to follow.
func enter_spectator() -> void:
	for widget in _avatar_widgets:
		widget.visible = false
	combo_label.visible = false
	spectator_bar.visible = true


func exit_spectator() -> void:
	for widget in _avatar_widgets:
		widget.visible = true
	spectator_bar.visible = false


func update_spectator(text: String) -> void:
	spectator_bar.text = text


## Connected to the world's RunLedger, which reports every peer in the room;
## the HUD only ever shows the local player's run.
func on_score_changed(peer_id: int, score: int, combo: int) -> void:
	if peer_id != Game.local_peer_id:
		return
	score_label.text = "SCORE %06d" % score
	if combo >= 2:
		combo_label.visible = true
		combo_label.text = "COMBO x%d" % combo
		var heat := clampf((combo - 2) / 8.0, 0.0, 1.0)
		combo_label.add_theme_color_override(
			"font_color", Color(1.0, lerpf(1.0, 0.45, heat), lerpf(1.0, 0.1, heat)))
		if _combo_tween and _combo_tween.is_valid():
			_combo_tween.kill()
		combo_label.scale = Vector2(1.35, 1.35)
		_combo_tween = create_tween()
		_combo_tween.tween_property(combo_label, "scale", Vector2.ONE, 0.2)\
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		combo_label.visible = false
