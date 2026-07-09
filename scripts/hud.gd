extends Control
## Минимальный HUD: прицел в центре (камера = прицел), кольцо силы броска при
## зарядке щелчка + полоска паса, точка состояния шайбы (есть/нет контроля),
## полоска кулдауна рывка (мигает при готовности). Читает main/player/blade.

const COL_LINE := Color(1, 1, 1, 0.7)
const COL_SLAP := Color(1.0, 0.75, 0.2)
const COL_PASS := Color(0.4, 0.8, 1.0)
const COL_CTRL := Color(0.25, 0.9, 0.4)
const COL_FREE := Color(0.8, 0.8, 0.85, 0.6)

var main: Node
var _t := 0.0


func setup(m: Node) -> void:
	main = m


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	if main == null:
		return
	var c := size * 0.5
	# Прицел.
	draw_line(c - Vector2(9, 0), c + Vector2(9, 0), COL_LINE, 2.0)
	draw_line(c - Vector2(0, 9), c + Vector2(0, 9), COL_LINE, 2.0)

	# Кольцо силы щелчка.
	var charge: float = main.charge
	if charge > 0.01:
		draw_arc(c, 26.0, -PI / 2.0, -PI / 2.0 + TAU * charge, 32, COL_SLAP, 3.0)
		# Деление «кистевой/щелчок» — метка в начале кольца.
		draw_arc(c, 26.0, -PI / 2.0 - 0.05, -PI / 2.0 + 0.05, 4, Color(1, 1, 1, 0.5), 3.0)

	# Полоска силы паса.
	var pass_c: float = main.pass_charge
	if pass_c > 0.01:
		var w := 44.0
		draw_rect(Rect2(c.x - w / 2.0, c.y + 20.0, w, 5.0), Color(0, 0, 0, 0.4))
		draw_rect(Rect2(c.x - w / 2.0, c.y + 20.0, w * pass_c, 5.0), COL_PASS)

	# Точка состояния шайбы (контроль/свободна) над прицелом.
	var controlled: bool = main.blade.puck_state == 1
	draw_circle(c + Vector2(0, -34), 5.0, COL_CTRL if controlled else COL_FREE)

	# Кулдаун ОТБОРА (E) — кольцо под прицелом: заполняется по мере готовности,
	# зелёное когда готов. Спам виден (кольцо не полное).
	var pf: float = main.blade.poke_ready
	var pr := 16.0
	draw_arc(c + Vector2(0, 30), pr, 0.0, TAU, 40, Color(0, 0, 0, 0.35), 2.0)
	var pcol := Color(0.3, 0.9, 0.45, 0.9) if pf >= 1.0 else Color(0.95, 0.55, 0.2, 0.9)
	if pf > 0.001:
		draw_arc(c + Vector2(0, 30), pr, -PI / 2.0, -PI / 2.0 + TAU * pf, 40, pcol, 3.0)

	# --- Два РАЗДЕЛЬНЫХ индикатора снизу: спринт (бар) и рывок (молния+мини-бар).
	if not main.skating_params.hud_stamina:
		return
	var f: float = main.player.dash_ready_fraction()  # стамина 0..1
	var ready: bool = main.player.dash_ready()
	var by := size.y - 46.0
	var font := get_theme_default_font()  # всегда валиден (в отличие от ThemeDB)
	var fs := 12

	# СПРИНТ: горизонтальный бар слева от центра.
	var sw := 150.0
	var sx := c.x - sw - 24.0
	if font:
		draw_string(font, Vector2(sx, by - 6.0), "СПРИНТ (Shift)", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.7))
	draw_rect(Rect2(sx, by, sw, 10.0), Color(0, 0, 0, 0.5))
	var sfill := Color(0.45, 0.75, 1.0, 0.95)
	if main.player.is_sprinting:
		sfill = Color(0.95, 0.85, 0.3, 1.0)  # активный спринт — жёлтый
	if f < 0.3:
		sfill = Color(0.95, 0.25, 0.2, 1.0)  # низкий запас — красный
	draw_rect(Rect2(sx, by, sw * f, 10.0), sfill)

	# РЫВОК: отдельный элемент справа от центра — иконка молнии + мини-бар.
	var dx := c.x + 24.0
	var col_ready := Color(1.0, 0.95, 0.3, 0.7 + 0.3 * sin(_t * 8.0))
	var col_off := Color(0.6, 0.6, 0.65, 0.55)
	var lc := col_ready if ready else col_off
	if font:
		draw_string(font, Vector2(dx, by - 6.0), "РЫВОК (2×Shift)", HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
				Color(1, 0.95, 0.5, 0.9) if ready else Color(1, 1, 1, 0.45))
	# Молния.
	var lx := dx + 6.0
	var ly := by + 5.0
	var bolt := PackedVector2Array([
		Vector2(lx + 4, ly - 8), Vector2(lx - 4, ly + 3), Vector2(lx, ly + 3),
		Vector2(lx - 3, ly + 12), Vector2(lx + 7, ly), Vector2(lx + 1, ly),
	])
	draw_colored_polygon(bolt, lc)
	# Мини-бар готовности рывка (заполняется вместе с баком, ярко при полном).
	var mbw := 110.0
	var mbx := dx + 24.0
	draw_rect(Rect2(mbx, by, mbw, 10.0), Color(0, 0, 0, 0.5))
	draw_rect(Rect2(mbx, by, mbw * f, 10.0),
			col_ready if ready else Color(0.55, 0.55, 0.6, 0.75))
