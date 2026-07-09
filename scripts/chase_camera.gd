extends Camera3D
## Орбитальная камера: мышь = камера ВСЕГДА (в стойке, в финтах, в бросках —
## никаких заморозок и режимов захвата). Мышь вращает только yaw; pitch
## статичный. Позиция плавно следует за целью. Два пресета: полевой и ВРАТАРЬ
## (goalie_mode — свой отступ/высота/наклон/FOV/плавность/чувствительность).

var params: SkatingParams
var target: Node3D  # полевой ИЛИ вратарь (свап)
var goalie_mode := false  # true = пресет камеры вратаря (gcam_*)

var yaw := 0.0
var pitch := 42.0
var _follow := Vector3.ZERO
var _initialized := false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and params:
		var sens: float = params.gcam_sensitivity if goalie_mode else params.mouse_sensitivity
		yaw -= deg_to_rad(event.relative.x * sens)


func _physics_process(delta: float) -> void:
	if target == null or params == null:
		return
	# Пресет: вратарь (gcam_*) или полевой (camera_*).
	var dist: float = params.gcam_distance if goalie_mode else params.camera_distance
	var height: float = params.gcam_height if goalie_mode else params.camera_height
	pitch = params.gcam_pitch if goalie_mode else params.camera_pitch
	var smooth: float = params.gcam_smoothing if goalie_mode else params.camera_smoothing
	var f: float = params.gcam_fov if goalie_mode else params.camera_fov

	var look := target.global_position + Vector3(0.0, height, 0.0)
	if not _initialized:
		_initialized = true
		_follow = look
	else:
		_follow = _follow.lerp(look, 1.0 - exp(-smooth * delta))

	var p := deg_to_rad(pitch)
	var offset := Vector3(sin(yaw) * cos(p), sin(p), cos(yaw) * cos(p)) * dist
	global_position = _follow + offset
	look_at(_follow, Vector3.UP)
	fov = f
