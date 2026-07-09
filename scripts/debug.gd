extends CanvasLayer
## Отладочный оверлей: FPS и счётчик голов.

@onready var fps_label: Label = $FpsLabel
@onready var score_label: Label = $ScoreLabel


func _process(_delta: float) -> void:
	fps_label.text = "FPS: %d" % Engine.get_frames_per_second()


func set_score(left: int, right: int) -> void:
	score_label.text = "LEFT %d : %d RIGHT" % [left, right]
