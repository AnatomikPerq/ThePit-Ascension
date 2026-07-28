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

var _notification_timer: float = 0.0
var _combo_tween: Tween


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
	if player.has_double_jump:
		skills_text += "[WING] "
	if player.has_strike:
		skills_text += "[STRIKE] "
	if player.has_shockwave:
		skills_text += "[SHOCKWAVE] "
	if player.flying:
		skills_text += "[FLIGHT] "
	skills_label.text = skills_text
	flight_label.text = "FLIGHT MODE ACTIVE" if player.flying else ""

	var ascent := clampf(1.0 - player.global_position.y / max_depth, 0.0, 1.0)
	ascent_bar.value = ascent * 100.0

	strike_icon.visible = player.has_strike
	strike_icon.modulate.a = 0.35 if not player.strike_cd_timer.is_stopped() else 1.0
	shockwave_icon.visible = player.has_shockwave
	shockwave_icon.modulate.a = 0.35 if not player.shockwave_cd_timer.is_stopped() else 1.0

	if _notification_timer > 0.0:
		_notification_timer -= delta
		if _notification_timer <= 0.0:
			notif_label.text = ""

	fps_label.text = "FPS: %d" % Engine.get_frames_per_second()


func on_score_changed(score: int, combo: int) -> void:
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
