class_name WorldSound
extends AudioStreamPlayer2D
## One sound that happened somewhere, rather than in your head.
##
## An AudioStreamPlayer2D is quieter the further the listener is, and in 2D the
## listener is the active Camera2D — which, in a session, is each machine's own
## camera following its own avatar. That is what makes distance work in
## multiplayer without a single byte crossing the wire: the *event* replicates,
## and every machine works out for itself how loud it was from where it stands.
##
## The falloff curve, panning and default range are authored on WorldSound.tscn;
## Audio.play_at fills in the stream, level, pitch and position from the
## SoundDef. Runs while the tree is paused, like the rest of the audio, so a
## sound that started before a pause still finishes and still frees itself.

func _ready() -> void:
	finished.connect(queue_free)
