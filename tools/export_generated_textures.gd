extends SceneTree
## One-shot migration tool: bakes every texture that the game used to draw at
## runtime with Image.set_pixel into a real PNG asset.
##
## The generation code below is copied VERBATIM from the scripts it replaces so
## the exported PNGs are pixel-identical to what the game rendered before:
##   bat        <- scripts/bat.gd        _make_bat_texture()
##   spitter    <- scripts/spitter.gd    _make_spitter_texture()
##   projectile <- scripts/projectile.gd _make_blob_texture()
##   shockwave  <- scripts/shockwave.gd  _make_ring_texture(128)
##   hearts     <- scripts/world.gd      _build_heart_textures()
##
## Run once:
##   godot --headless --path . -s tools/export_generated_textures.gd
##
## After the PNGs exist this tool is dead weight — it is kept only so the
## provenance of those assets is reproducible.

const OUT_DIR := "res://assets/sprites/"


func _initialize() -> void:
	var written: Array[String] = []
	written.append(_save(_make_bat_texture(), "bat.png"))
	written.append(_save(_make_spitter_texture(), "spitter.png"))
	written.append(_save(_make_blob_texture(), "projectile_blob.png"))
	written.append(_save(_make_ring_texture(128), "shockwave_ring.png"))

	var heart_pattern: Array[String] = [
		".XX.XX.",
		"XXXXXXX",
		"XXXXXXX",
		".XXXXX.",
		"..XXX..",
		"...X...",
	]
	written.append(_save(_texture_from_pattern(heart_pattern, Color(0.92, 0.22, 0.3)), "heart_full.png"))
	written.append(_save(_texture_from_pattern(heart_pattern, Color(0.24, 0.07, 0.10)), "heart_empty.png"))

	for path in written:
		print("wrote ", path)
	quit(0)


func _save(img: Image, filename: String) -> String:
	var path := OUT_DIR + filename
	var err := img.save_png(path)
	if err != OK:
		push_error("failed to save %s (error %d)" % [path, err])
	return path


# ── Copied verbatim from scripts/bat.gd ─────────────────────────────────────
func _make_bat_texture() -> Image:
	# 32×32 dark bat: round body, two triangular wings, red eyes.
	var size := 32
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var center := Vector2(16, 16)
	var body_color := Color(0.12, 0.05, 0.18, 1.0)
	var wing_color := Color(0.05, 0.02, 0.10, 1.0)
	var eye_color := Color(1.0, 0.25, 0.25, 1.0)
	for y in range(size):
		for x in range(size):
			var p := Vector2(x, y)
			var d := p.distance_to(center)
			if d <= 6.0:
				img.set_pixel(x, y, body_color)
			elif d <= 9.0 and p.y < 12.0:
				# Ears
				img.set_pixel(x, y, body_color)
			# Wings: stretched triangles either side of the body.
			elif p.y >= 12.0 and p.y <= 22.0:
				if x < 16:
					var span: float = (15.0 - float(x)) / 15.0
					if span > 0.0 and abs(p.y - 17.0) < (span * 9.0) and span > 0.25:
						img.set_pixel(x, y, wing_color)
				else:
					var span2: float = (float(x) - 16.0) / 15.0
					if span2 > 0.0 and abs(p.y - 17.0) < (span2 * 9.0) and span2 > 0.25:
						img.set_pixel(x, y, wing_color)
			# Eyes
			if (p - Vector2(13.0, 14.0)).length() <= 1.3 or (p - Vector2(19.0, 14.0)).length() <= 1.3:
				img.set_pixel(x, y, eye_color)
	return img


# ── Copied verbatim from scripts/spitter.gd ─────────────────────────────────
func _make_spitter_texture() -> Image:
	# 32×32 bulbous plant-spitter: green base, gaping mouth, fang.
	var size := 32
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var center := Vector2(16, 22)
	var body_color := Color(0.20, 0.45, 0.16, 1.0)
	var dark_color := Color(0.10, 0.30, 0.10, 1.0)
	var mouth_color := Color(0.10, 0.05, 0.05, 1.0)
	var fang_color := Color(0.9, 0.9, 0.8, 1.0)
	for y in range(size):
		for x in range(size):
			var p := Vector2(x, y)
			var d := p.distance_to(center)
			# Bulb body
			if d <= 11.0:
				img.set_pixel(x, y, body_color)
			elif d <= 13.0:
				img.set_pixel(x, y, dark_color)
			# Mouth: dark oval near the top center
			var mouth_d := p.distance_to(Vector2(16, 14))
			if mouth_d <= 5.0:
				img.set_pixel(x, y, mouth_color)
			# Fangs
			if (p - Vector2(13.0, 17.0)).length() <= 1.4 or (p - Vector2(19.0, 17.0)).length() <= 1.4:
				img.set_pixel(x, y, fang_color)
			# Stem base shading
			if p.y >= 28 and abs(p.x - 16) < 4:
				img.set_pixel(x, y, dark_color)
	return img


# ── Copied verbatim from scripts/projectile.gd ──────────────────────────────
func _make_blob_texture() -> Image:
	var size := 16
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var center := Vector2(8, 8)
	for y in range(size):
		for x in range(size):
			var d := Vector2(x, y).distance_to(center)
			if d <= 6.0:
				var edge := smoothstep(4.0, 6.0, d)
				img.set_pixel(x, y, Color(0.45, 0.95, 0.3, 1.0 - edge * 0.4))
	return img


# ── Copied verbatim from scripts/shockwave.gd ───────────────────────────────
func _make_ring_texture(size: int) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var center := Vector2(size / 2.0, size / 2.0)
	var outer := size / 2.0
	var thickness := 12.0
	for y in range(size):
		for x in range(size):
			var d: float = Vector2(x, y).distance_to(center)
			if d <= outer and d >= outer - thickness:
				var edge: float = smoothstep(outer - thickness, outer, d)
				img.set_pixel(x, y, Color(0.6, 0.9, 1.0, edge))
	return img


# ── Copied verbatim from scripts/world.gd ───────────────────────────────────
func _texture_from_pattern(pattern: Array[String], color: Color) -> Image:
	var h := pattern.size()
	var w := pattern[0].length()
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in h:
		for x in w:
			if pattern[y][x] == "X":
				img.set_pixel(x, y, color)
	return img
