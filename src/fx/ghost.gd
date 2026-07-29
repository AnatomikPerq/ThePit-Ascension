extends Node2D
## One dash afterimage. The fade and the self-free live in the scene's
## AnimationPlayer; the script only copies what the source sprite shows.
## Call after add_child so the global transform lands where the source is.


func setup(texture: Texture2D, flipped: bool, source_transform: Transform2D, tint: Color) -> void:
	var sprite: Sprite2D = $Sprite2D
	sprite.texture = texture
	sprite.flip_h = flipped
	modulate = tint
	# Freeze the source's full transform (position, facing, scale).
	global_transform = source_transform
