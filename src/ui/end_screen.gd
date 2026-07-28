class_name EndScreen
extends ColorRect
## End-of-run screen. One scene serves both outcomes: World.tscn instances it
## twice with the title, colors and background overridden per instance.


func show_with(stats: String) -> void:
	$Stats.text = stats
	visible = true
