extends MeshInstance3D
## След юза на льду. В режиме SKID под игроком рисуются две параллельные полосы
## по проекции лезвия. Не выцветают — очищаются при респауне шайбы или кнопкой
## в панели. Реализация: накопительный ImmediateMesh (квады только при SKID) —
## дёшево (рисование лишь когда игрок скользит), бюджет < 0.3 мс/кадр.
## (Render-target из ТЗ заменён на mesh-полосы: проще, детерминированно,
##  та же роль «поверхности следов»; при желании масштабируется до RT позже.)

const HALF_GAP := 0.16   # полурасстояние между полосами (проекция лезвия)
const WIDTH := 0.05
const MAX_QUADS := 2000

var enabled := true

var _player: Player
var _mesh: ImmediateMesh
var _strokes: Array = []      # массив полос: [{left:[Vector3...], right:[...]}]
var _skidding_prev := false
var _dirty := false


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_player = get_parent()
	_mesh = ImmediateMesh.new()
	mesh = _mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.80, 0.86, 0.95, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _physics_process(_delta: float) -> void:
	var skid := enabled and _player.is_skidding
	if skid:
		var forward := -_player.global_transform.basis.z
		forward.y = 0.0
		var side := forward.normalized().rotated(Vector3.UP, -PI / 2.0)
		var base := _player.global_position + Vector3(0, 0.025, 0)
		if not _skidding_prev:
			_strokes.append({"left": PackedVector3Array(), "right": PackedVector3Array()})
		var stroke = _strokes[-1]
		stroke.left.append(base + side * HALF_GAP)
		stroke.right.append(base - side * HALF_GAP)
		_trim()
		_dirty = true
	_skidding_prev = skid
	if _dirty:
		_rebuild()
		_dirty = false


func clear_trail() -> void:
	_strokes.clear()
	_skidding_prev = false
	_mesh.clear_surfaces()


func set_enabled(value: bool) -> void:
	enabled = value
	if not value:
		clear_trail()


func _trim() -> void:
	# Ограничить суммарное число точек (бюджет).
	var total := 0
	for s in _strokes:
		total += s.left.size()
	while total > MAX_QUADS and _strokes.size() > 1:
		total -= _strokes[0].left.size()
		_strokes.pop_front()


func _rebuild() -> void:
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in _strokes:
		_ribbon(s.left)
		_ribbon(s.right)
	_mesh.surface_end()


func _ribbon(points: PackedVector3Array) -> void:
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var d := b - a
		d.y = 0.0
		if d.length() < 0.001:
			continue
		var perp := Vector3(-d.z, 0.0, d.x).normalized() * (WIDTH / 2.0)
		_quad(a - perp, a + perp, b + perp, b - perp)


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for v in [a, b, c, a, c, d]:
		_mesh.surface_add_vertex(v)
