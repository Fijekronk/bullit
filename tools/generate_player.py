"""Офлайн-генератор low-poly хоккеиста на основе готового тела.

Запуск (headless):
    blender --background --python tools/generate_player.py

Blender (Steam): C:\\Program Files (x86)\\Steam\\steamapps\\common\\Blender\\blender.exe

Пайплайн:
  1. Берём готовое тело assets/models/player/male_lowpoly.blend (риг + меш, A-поза,
     лицом в -Y, рост ~1.955 м). Тело из примитивов НЕ строим.
  2. Поднимаем руки в T-позу (поворот арм-вершин вокруг плеча по вершинным группам),
     разворачиваем лицом в +Y (в Godot -> -Z), масштабируем в рост 1.8 м, ставим
     ноги на Z=0, снимаем скелет (БЕЗ скелета в выходе).
  3. Тело режем на палитровые зоны по вершинным группам: skin (голова/шея/кисти/
     предплечья) и base_dark (поддёвочный слой под экипировкой).
  4. Экипировку строим ПОВЕРХ тела отдельными мешами по слотам SKINS_CONVENTION.md:
     slot_skates / slot_socks / slot_pants / slot_jersey / slot_gloves / slot_helmet.
     Размеры привязаны к замерам тела (плечи/бёдра/колени/стопы), блочные и шире
     реальных — «квадратный» хоккейный силуэт. Зеркальная симметрия. Клюшка не генерится.
  5. Палитра assets/textures/player_palette.png (64x64, 8x8) + assets/palette_layout.md.
     UV каждой грани — в центр своей ячейки (плоский цвет, без запекания).
  6. Выход: assets/models/player/player.glb (+ упакованная текстура) и player.blend.
  7. Превью в tools/preview/: front / side / 3-4 view + игровая дистанция (~10 м, ~40 гр).

ВСЕ пропорции экипировки — именованные параметры в блоке PARAMS (метры).
Модель В ИГРУ НЕ ПОДКЛЮЧАЕТСЯ — сначала оценка силуэта по превью.
"""

import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector, Matrix

# --------------------------------------------------------------------------- #
#  ПУТИ
# --------------------------------------------------------------------------- #
THIS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(THIS)

BODY_BLEND = os.path.join(ROOT, "assets", "models", "player", "male_lowpoly.blend")
PALETTE_PNG = os.path.join(ROOT, "assets", "textures", "player_palette.png")
PALETTE_MD = os.path.join(ROOT, "assets", "palette_layout.md")
GLB_PATH = os.path.join(ROOT, "assets", "models", "player", "player.glb")
BLEND_PATH = os.path.join(ROOT, "assets", "models", "player", "player.blend")
PREVIEW_DIR = os.path.join(THIS, "preview")

for d in (os.path.dirname(PALETTE_PNG), os.path.dirname(GLB_PATH), PREVIEW_DIR):
    os.makedirs(d, exist_ok=True)

BODY_OBJ_NAME = "M_lowpoly"

# --------------------------------------------------------------------------- #
#  PARAMS — целевой рост и паддинги экипировки (метры). Позиции берутся из
#  замеров тела; PAD_* задают «толщину»/навал экипировки поверх тела.
#  Blender после подготовки: Z=вверх, +Y=перёд(лицо), X=вбок; ноги на Z=0.
# --------------------------------------------------------------------------- #
HEIGHT = 1.80

# Коньки
SKATE_PAD_W = 0.02       # навал ботинка вбок от стопы
SKATE_BLADE_H = 0.03     # высота лезвия
SKATE_HOLDER_H = 0.04    # держатель между лезвием и ботинком
SKATE_LIFT = SKATE_BLADE_H + SKATE_HOLDER_H  # тело приподнято на эту высоту
SKATE_BLADE_LEN_PAD = 0.04   # лезвие длиннее стопы
SKATE_BOOT_PADZ = 0.01

# Гетры (голень+колено) — облегают ногу
SOCK_PAD = 0.018         # навал вокруг ноги

# Штаны (шорты) — чуть объёмнее бёдер, без «юбки»
PANTS_PAD_W = 0.03       # ширина бёдер сверх таза
PANTS_PAD_F = 0.03

# Свитер: торс + плечи + рукава — облегают тело
JERSEY_PAD_W = 0.028     # навал по бокам торса
JERSEY_PAD_F = 0.028     # навал по глубине
SHOULDER_EXTRA = 0.03    # плечи чуть шире торса
SHOULDER_H = 0.11        # высота наплечного блока
SLEEVE_PAD = 0.018       # толщина рукава вокруг руки
COLLAR_W = 0.08

# Краги — чуть крупнее кисти
GLOVE_PAD = 0.03         # навал перчатки вокруг кисти
GLOVE_OUT = 0.02         # выступ краги наружу за кончики пальцев

# Шлем
HELMET_PAD = 0.028       # оболочка больше головы
HELMET_LIFT = 0.015
HELMET_BOTTOM_FRAC = 0.55  # доля радиуса вниз, докуда опускается оболочка
HELMET_BROW_FRAC = 0.12    # спереди срез до брови (открыть лицо)
VISOR_H = 0.07
VISOR_DEPTH = 0.05
VISOR_W_FRAC = 0.95        # ширина визора от ширины головы

# --------------------------------------------------------------------------- #
#  ПАЛИТРА (8x8). (col, row_top, rgb). row сверху-вниз (как в редакторе PNG).
# --------------------------------------------------------------------------- #
GRID = 8
ZONES = {
    "jersey_main":   (0, 0, (0.11, 0.15, 0.34)),   # свитер тёмно-синий
    "jersey_insert": (1, 0, (0.90, 0.91, 0.94)),   # белые вставки
    "jersey_trim":   (2, 0, (0.62, 0.15, 0.18)),   # акцент (резерв)
    "socks":         (3, 0, (0.15, 0.28, 0.62)),   # гетры синие
    "pants":         (4, 0, (0.12, 0.14, 0.20)),   # штаны тёмные
    "gloves":        (5, 0, (0.08, 0.08, 0.10)),   # краги чёрные
    "helmet":        (6, 0, (0.06, 0.06, 0.08)),   # шлем чёрный
    "visor":         (7, 0, (0.04, 0.05, 0.08)),   # визор тёмный
    "skate_black":   (0, 1, (0.09, 0.09, 0.11)),   # коньки чёрные
    "skate_white":   (1, 1, (0.84, 0.85, 0.88)),   # белая деталь/лезвие
    "skin":          (2, 1, (0.86, 0.66, 0.53)),   # кожа (лицо, шея, кисти)
    "neck_dark":     (3, 1, (0.10, 0.11, 0.16)),   # ворот/подшлемник
    "base_dark":     (4, 1, (0.09, 0.10, 0.15)),   # поддёвочный слой тела
}
UNUSED_GRAY = (0.5, 0.5, 0.5)


def cell_uv(zone):
    col, row_top, _ = ZONES[zone]
    row_bottom = (GRID - 1) - row_top
    return ((col + 0.5) / GRID, (row_bottom + 0.5) / GRID)


# --------------------------------------------------------------------------- #
#  ПАЛИТРА PNG + layout.md
# --------------------------------------------------------------------------- #
def build_palette():
    res = 64
    cp = res // GRID
    px = [0.0] * (res * res * 4)
    for i in range(res * res):
        px[i * 4:i * 4 + 4] = [UNUSED_GRAY[0], UNUSED_GRAY[1], UNUSED_GRAY[2], 1.0]

    def fill(col, row_top, rgb):
        row_b = (GRID - 1) - row_top
        for yy in range(row_b * cp, (row_b + 1) * cp):
            for xx in range(col * cp, (col + 1) * cp):
                idx = (yy * res + xx) * 4
                px[idx:idx + 4] = [rgb[0], rgb[1], rgb[2], 1.0]

    for _, (col, row_top, rgb) in ZONES.items():
        fill(col, row_top, rgb)

    img = bpy.data.images.new("player_palette", width=res, height=res, alpha=True)
    img.pixels = px
    img.filepath_raw = PALETTE_PNG
    img.file_format = "PNG"
    img.save()
    return img


def write_palette_layout():
    labels = {
        "jersey_main": "Свитер — основной (тёмно-синий)",
        "jersey_insert": "Свитер — вставки (белые)",
        "jersey_trim": "Акцент/полоса (резерв)",
        "socks": "Гетры (синие)",
        "pants": "Штаны (тёмные)",
        "gloves": "Краги (чёрные)",
        "helmet": "Шлем (чёрный)",
        "visor": "Визор (тёмный)",
        "skate_black": "Коньки — ботинок (чёрный)",
        "skate_white": "Коньки — деталь/лезвие (белая)",
        "skin": "Кожа — лицо, шея, кисти, предплечья",
        "neck_dark": "Ворот/подшлемник (тёмный)",
        "base_dark": "Тело — поддёвочный слой под экипировкой",
    }
    L = []
    L.append("# palette_layout.md — раскладка палитрового атласа игрока")
    L.append("")
    L.append("Файл: `assets/textures/player_palette.png` — 64x64, сетка 8x8 ячеек")
    L.append("(ячейка 8x8 px). Перекраска = замена цвета ячейки. UV каждой грани —")
    L.append("в ЦЕНТРЕ своей ячейки, детали не запекаются (правило 2 SKINS_CONVENTION.md).")
    L.append("")
    L.append("Координаты: `col` слева-направо (0..7), `row` СВЕРХУ-вниз (0..7).")
    L.append("")
    L.append("| Зона | col | row | ключ | RGB 0-255 |")
    L.append("|------|-----|-----|------|-----------|")
    for zone, (col, row, rgb) in ZONES.items():
        r, g, b = (int(round(c * 255)) for c in rgb)
        L.append(f"| {labels.get(zone, zone)} | {col} | {row} | `{zone}` | {r},{g},{b} |")
    L.append("")
    L.append("Остальные ячейки — нейтральный серый (резерв).")
    L.append("")
    L.append("## Меши и зоны")
    L.append("")
    L.append("- `M_lowpoly` (базовое тело) — `skin` (голова/шея/кисти/предплечья) + "
             "`base_dark` (торс/ноги/стопы под экипировкой)")
    L.append("- `slot_helmet` — `helmet` + `visor`")
    L.append("- `slot_jersey` — `jersey_main` (торс/плечи/рукава) + `jersey_insert` "
             "(ворот/манжеты/полоса плеч)")
    L.append("- `slot_pants` — `pants`")
    L.append("- `slot_socks` — `socks`")
    L.append("- `slot_gloves` — `gloves`")
    L.append("- `slot_skates` — `skate_black` (ботинок) + `skate_white` (лезвие)")
    L.append("")
    with open(PALETTE_MD, "w", encoding="utf-8") as f:
        f.write("\n".join(L))


# --------------------------------------------------------------------------- #
#  БИЛДЕР ЭКИПИРОВКИ (примитивы + пофейсовая палитровая ячейка)
# --------------------------------------------------------------------------- #
_CORN = [(-1, -1, -1), (1, -1, -1), (1, 1, -1), (-1, 1, -1),
         (-1, -1, 1), (1, -1, 1), (1, 1, 1), (-1, 1, 1)]
_FACES = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4),
          (3, 7, 6, 2), (1, 2, 6, 5), (0, 4, 7, 3)]


class MeshBuilder:
    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.fz = {}

    def _box(self, cx, cy, cz, sx, sy, sz, zone):
        hx, hy, hz = sx / 2, sy / 2, sz / 2
        vs = [self.bm.verts.new((cx + dx * hx, cy + dy * hy, cz + dz * hz))
              for (dx, dy, dz) in _CORN]
        for f in _FACES:
            self.fz[self.bm.faces.new([vs[i] for i in f])] = zone

    def box(self, center, size, zone, mirror=False):
        self._box(center[0], center[1], center[2], size[0], size[1], size[2], zone)
        if mirror:
            self._box(-center[0], center[1], center[2], size[0], size[1], size[2], zone)

    def taper_box(self, cx, cy, cz, sy, sx_bot, sx_top, height, zone, mirror=False):
        hy = sy / 2
        zt = cz + height

        def emit(cx_):
            hb, ht = sx_bot / 2, sx_top / 2
            pts = [(cx_ - hb, cy - hy, cz), (cx_ + hb, cy - hy, cz),
                   (cx_ + hb, cy + hy, cz), (cx_ - hb, cy + hy, cz),
                   (cx_ - ht, cy - hy, zt), (cx_ + ht, cy - hy, zt),
                   (cx_ + ht, cy + hy, zt), (cx_ - ht, cy + hy, zt)]
            vs = [self.bm.verts.new(p) for p in pts]
            for f in _FACES:
                self.fz[self.bm.faces.new([vs[i] for i in f])] = zone

        emit(cx)
        if mirror:
            emit(-cx)

    def ico(self, center, radius, zone, squash=(1, 1, 1), subdiv=2, cut_fn=None):
        res = bmesh.ops.create_icosphere(self.bm, subdivisions=subdiv, radius=radius)
        verts = res["verts"]
        cx, cy, cz = center
        for v in verts:
            v.co.x = v.co.x * squash[0] + cx
            v.co.y = v.co.y * squash[1] + cy
            v.co.z = v.co.z * squash[2] + cz
        for f in [f for f in self.bm.faces if f not in self.fz]:
            self.fz[f] = zone
        if cut_fn:
            kill = [v for v in verts if cut_fn(v.co.x, v.co.y, v.co.z)]
            if kill:
                bmesh.ops.delete(self.bm, geom=kill, context="VERTS")

    def finish(self, material):
        bm = self.bm
        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        uvl = bm.loops.layers.uv.new("UVMap")
        for face in bm.faces:
            zone = self.fz.get(face)
            if zone is None:
                continue
            uv = cell_uv(zone)
            for loop in face.loops:
                loop[uvl].uv = uv
        mesh = bpy.data.meshes.new(self.name)
        bm.to_mesh(mesh)
        bm.free()
        obj = bpy.data.objects.new(self.name, mesh)
        obj.data.materials.append(material)
        bpy.context.scene.collection.objects.link(obj)
        return obj


# --------------------------------------------------------------------------- #
#  ПОДГОТОВКА ТЕЛА
# --------------------------------------------------------------------------- #
def group_indices(obj, names):
    return {obj.vertex_groups[n].index for n in names if n in obj.vertex_groups}


def verts_in_groups(obj, idxs, thresh=0.5):
    out = []
    for v in obj.data.vertices:
        w = sum(g.weight for g in v.groups if g.group in idxs)
        if w > thresh:
            out.append(v)
    return out


def bounds(verts):
    xs = [v.co.x for v in verts]
    ys = [v.co.y for v in verts]
    zs = [v.co.z for v in verts]
    return {
        "cx": sum(xs) / len(xs), "cy": sum(ys) / len(ys), "cz": sum(zs) / len(zs),
        "minx": min(xs), "maxx": max(xs), "miny": min(ys), "maxy": max(ys),
        "minz": min(zs), "maxz": max(zs),
    }


ARM_GROUP_PREFIX = ("upperarm", "lowerarm", "hand", "thumb", "index",
                    "middle", "ring", "pinky")


def raise_arm_to_tpose(obj):
    """Поднимает руки в горизонталь, вращая арм-вершины вокруг плечевого сустава.
    Работает в исходном пространстве (тело лицом в -Y, hand на +/-X)."""
    arm_idxs = {vg.index for vg in obj.vertex_groups
                if vg.name.startswith(ARM_GROUP_PREFIX)}
    # разбиваем на левую (x>0) и правую (x<0) руку по знаку X кисти
    for sign in (+1, -1):
        # вершины этой руки
        arm_verts = []
        for v in obj.data.vertices:
            w = sum(g.weight for g in v.groups if g.group in arm_idxs)
            if w > 0.5 and (v.co.x * sign) > 0.02:
                arm_verts.append(v)
        if not arm_verts:
            continue
        # плечевой сустав: медиально-верхняя точка плеча
        up_idx = group_indices(obj, [f"upperarm_{'L' if sign > 0 else 'R'}"])
        up_verts = verts_in_groups(obj, up_idx)
        if not up_verts:
            continue
        # сустав = самая медиальная (мин |x|) и высокая точка плеча
        pivot_x = min(v.co.x for v in up_verts) if sign > 0 else max(v.co.x for v in up_verts)
        pivot_z = max(v.co.z for v in up_verts)
        pivot_y = sum(v.co.y for v in up_verts) / len(up_verts)
        pivot = Vector((pivot_x, pivot_y, pivot_z))
        # кисть
        hand_idx = group_indices(obj, [f"hand_{'L' if sign > 0 else 'R'}"])
        hv = verts_in_groups(obj, hand_idx)
        hand = Vector((sum(v.co.x for v in hv) / len(hv),
                       sum(v.co.y for v in hv) / len(hv),
                       sum(v.co.z for v in hv) / len(hv)))
        d = hand - pivot
        # текущий угол вектора в плоскости XZ ниже горизонтали
        drop = math.atan2(-d.z, abs(d.x))   # >0, рука ниже плеча
        # пробуем оба знака поворота вокруг Y, выбираем поднимающий кисть
        best = None
        for ang in (drop, -drop):
            R = Matrix.Rotation(ang, 3, "Y")
            new_hand = R @ (hand - pivot) + pivot
            if best is None or new_hand.z > best[1]:
                best = (ang, new_hand.z)
        ang = best[0]
        R = Matrix.Rotation(ang, 3, "Y")
        for v in arm_verts:
            v.co = R @ (v.co - pivot) + pivot

        # 2-й поворот: выпрямить кисть (убрать завал запястья) в горизонталь
        hand_idxs = {vg.index for vg in obj.vertex_groups
                     if vg.name.startswith(("hand", "thumb", "index", "middle",
                                            "ring", "pinky"))}
        hverts = [v for v in obj.data.vertices
                  if sum(g.weight for g in v.groups if g.group in hand_idxs) > 0.5
                  and v.co.x * sign > 0.02]
        if hverts:
            # запястье = медиальный край кисти (ближе к телу)
            wx = min(v.co.x for v in hverts) if sign > 0 else max(v.co.x for v in hverts)
            near = sorted(hverts, key=lambda v: abs(v.co.x - wx))[:max(3, len(hverts) // 4)]
            wrist = Vector((wx, sum(v.co.y for v in near) / len(near),
                            sum(v.co.z for v in near) / len(near)))
            hc = Vector((sum(v.co.x for v in hverts) / len(hverts),
                         sum(v.co.y for v in hverts) / len(hverts),
                         sum(v.co.z for v in hverts) / len(hverts)))
            dd = hc - wrist
            drop2 = math.atan2(-dd.z, abs(dd.x))
            best2 = None
            for a in (drop2, -drop2):
                Rr = Matrix.Rotation(a, 3, "Y")
                nh = Rr @ (hc - wrist) + wrist
                if best2 is None or nh.z > best2[1]:
                    best2 = (a, nh.z)
            Rr = Matrix.Rotation(best2[0], 3, "Y")
            for v in hverts:
                v.co = Rr @ (v.co - wrist) + wrist


def apply_transform(obj):
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    obj.select_set(False)


def prepare_body():
    with bpy.data.libraries.load(BODY_BLEND, link=False) as (src, dst):
        dst.objects = [BODY_OBJ_NAME]
    body = None
    for o in dst.objects:
        if o and o.name.startswith(BODY_OBJ_NAME):
            body = o
            break
    bpy.context.scene.collection.objects.link(body)
    # снять модификаторы (арматур) — работаем чистой геометрией, БЕЗ скелета
    body.modifiers.clear()
    body.parent = None
    body.matrix_world = Matrix.Identity(4)

    # 0) запечь shape keys в базовую геометрию и удалить их: иначе активный
    #    shape-key перекрывает правки vertices.co (меш рендерится в исходной позе)
    if body.data.shape_keys:
        deps = bpy.context.evaluated_depsgraph_get()
        ev = body.evaluated_get(deps)
        tmp = ev.to_mesh()
        coords = [v.co.copy() for v in tmp.vertices]
        ev.to_mesh_clear()
        body.shape_key_clear()
        for v, c in zip(body.data.vertices, coords):
            v.co = c
        body.data.update()

    # 1) руки в T-позу (в исходном пространстве)
    raise_arm_to_tpose(body)
    body.data.update()

    # 2) развернуть лицом в +Y (было -Y)
    body.rotation_euler = (0, 0, math.pi)
    apply_transform(body)

    # 3) масштаб: тело занимает (HEIGHT - SKATE_LIFT), сверху коньки добавят lift
    bb = bounds(body.data.vertices)
    h = bb["maxz"] - bb["minz"]
    s = (HEIGHT - SKATE_LIFT) / h
    body.scale = (s, s, s)
    apply_transform(body)

    # 4) центрировать X/Y в 0, стопы на Z=SKATE_LIFT (под ними лезвие+держатель)
    bb = bounds(body.data.vertices)
    body.location.x -= (bb["minx"] + bb["maxx"]) / 2
    body.location.y -= (bb["miny"] + bb["maxy"]) / 2
    body.location.z -= bb["minz"] - SKATE_LIFT
    apply_transform(body)
    return body


def zone_body_uvs(body):
    """Режем тело на палитровые зоны по вершинным группам."""
    skin_prefix = ("head", "neck", "hand", "thumb", "index", "middle", "ring",
                   "pinky", "lowerarm")
    # per-vertex zone по доминирующей группе
    idx_name = {vg.index: vg.name for vg in body.vertex_groups}
    vert_zone = {}
    for v in body.data.vertices:
        best_w, best_name = 0.0, None
        for g in v.groups:
            if g.weight > best_w:
                best_w, best_name = g.weight, idx_name.get(g.group, "")
        z = "skin" if (best_name or "").startswith(skin_prefix) else "base_dark"
        vert_zone[v.index] = z

    me = body.data
    uvl = me.uv_layers.get("UVMap") or me.uv_layers.new(name="UVMap")
    uvdata = uvl.data
    for poly in me.polygons:
        # зона грани = большинство её вершин
        votes = {}
        for vi in poly.vertices:
            z = vert_zone[vi]
            votes[z] = votes.get(z, 0) + 1
        zone = max(votes, key=votes.get)
        uv = cell_uv(zone)
        for li in range(poly.loop_start, poly.loop_start + poly.loop_total):
            uvdata[li].uv = uv


def measure(body):
    """Замеры bbox частей тела (финальное пространство). Парные части (руки/ноги)
    меряются по ПРАВОЙ стороне (x>0); экипировка строится справа и зеркалится."""
    def gb(pred, sign=None):
        idxs = {vg.index for vg in body.vertex_groups if pred(vg.name)}
        vs = []
        for v in body.data.vertices:
            w = sum(g.weight for g in v.groups if g.group in idxs)
            if w > 0.5 and (sign is None or v.co.x * sign > 0):
                vs.append(v)
        return bounds(vs) if vs else None

    def sw(*p):
        return lambda n: n.startswith(p)

    return {
        "all": bounds(list(body.data.vertices)),
        "head": gb(sw("head")),
        "neck": gb(sw("neck")),
        "chest": gb(sw("spine", "clavicle")),
        "pelvis": gb(sw("pelvis")),
        "thighR": gb(sw("thigh"), +1),
        "calfR": gb(sw("calf"), +1),
        "footR": gb(sw("foot", "toes"), +1),
        "armR": gb(sw("upperarm", "lowerarm"), +1),
        "handR": gb(sw("hand", "thumb", "index", "middle", "ring", "pinky"), +1),
    }


def bb_center_size(b, pad_x=0.0, pad_y=0.0, pad_z=0.0):
    cx = (b["minx"] + b["maxx"]) / 2
    cy = (b["miny"] + b["maxy"]) / 2
    cz = (b["minz"] + b["maxz"]) / 2
    sx = (b["maxx"] - b["minx"]) + 2 * pad_x
    sy = (b["maxy"] - b["miny"]) + 2 * pad_y
    sz = (b["maxz"] - b["minz"]) + 2 * pad_z
    return (cx, cy, cz), (sx, sy, sz)


def leg_split_z(m):
    """Согласованные высоты стыков штаны/гетры/коньки (без щелей, с нахлёстом)."""
    hip_top = m["pelvis"]["maxz"] + 0.03
    knee = m["calfR"]["maxz"]
    ankle_top = m["footR"]["maxz"]
    pants_bottom = knee + 0.07          # штаны заканчиваются чуть выше колена
    socks_top = pants_bottom + 0.07     # гетры заходят под штаны (нахлёст)
    socks_bottom = ankle_top - 0.02     # гетры заходят в конёк
    return {
        "hip_top": hip_top, "pants_bottom": pants_bottom,
        "socks_top": socks_top, "socks_bottom": socks_bottom,
        "ankle_top": ankle_top,
    }


# --------------------------------------------------------------------------- #
#  ЭКИПИРОВКА (по замерам m)
# --------------------------------------------------------------------------- #
def build_skates(mat, m):
    b = MeshBuilder("slot_skates")
    f = m["footR"]
    cx = (f["minx"] + f["maxx"]) / 2
    cy = (f["miny"] + f["maxy"]) / 2
    boot_w = (f["maxx"] - f["minx"]) + 2 * SKATE_PAD_W
    boot_len = (f["maxy"] - f["miny"]) + 0.05
    # ботинок обнимает стопу от льда-подошвы (SKATE_LIFT) до подъёма
    boot_bottom = SKATE_LIFT
    boot_top = f["maxz"] + SKATE_BOOT_PADZ
    b.box((cx, cy, (boot_bottom + boot_top) / 2),
          (boot_w, boot_len, boot_top - boot_bottom), "skate_black", mirror=True)
    # язык (белая деталь спереди-сверху)
    b.box((cx, f["maxy"] - boot_len * 0.15, boot_top - 0.02),
          (boot_w * 0.7, boot_len * 0.3, 0.05), "skate_white", mirror=True)
    # держатель
    b.box((cx, cy, SKATE_BLADE_H + SKATE_HOLDER_H / 2),
          (0.03, boot_len * 0.7, SKATE_HOLDER_H), "skate_black", mirror=True)
    # лезвие (сталь)
    b.box((cx, cy, SKATE_BLADE_H / 2),
          (0.02, boot_len + SKATE_BLADE_LEN_PAD, SKATE_BLADE_H),
          "skate_white", mirror=True)
    return b.finish(mat)


def build_socks(mat, m):
    b = MeshBuilder("slot_socks")
    z = leg_split_z(m)
    c = m["calfR"]
    cx = (c["minx"] + c["maxx"]) / 2
    cy = (c["miny"] + c["maxy"]) / 2
    sx = (c["maxx"] - c["minx"]) + 2 * SOCK_PAD
    sy = (c["maxy"] - c["miny"]) + 2 * SOCK_PAD
    z0, z1 = z["socks_bottom"], z["socks_top"]
    b.box((cx, cy, (z0 + z1) / 2), (sx, sy, z1 - z0), "socks", mirror=True)
    return b.finish(mat)


def build_pants(mat, m):
    b = MeshBuilder("slot_pants")
    z = leg_split_z(m)
    p = m["pelvis"]
    th = m["thighR"]
    z1 = z["hip_top"]
    z0 = z["pants_bottom"]
    half_w = th["maxx"] + PANTS_PAD_W          # внешний край бедра + навал
    cy = (p["miny"] + p["maxy"]) / 2
    depth = (p["maxy"] - p["miny"]) + 2 * PANTS_PAD_F
    b.box((0.0, cy, (z0 + z1) / 2), (half_w * 2, depth, z1 - z0), "pants")
    return b.finish(mat)


def build_jersey(mat, m):
    b = MeshBuilder("slot_jersey")
    z = leg_split_z(m)
    chest = m["chest"]
    arm = m["armR"]
    hand = m["handR"]
    z_top = chest["maxz"]
    z_bot = z["hip_top"] - 0.02                # свитер заходит на штаны (нахлёст)
    half_w = (chest["maxx"] - chest["minx"]) / 2 + JERSEY_PAD_W
    depth = (chest["maxy"] - chest["miny"]) + 2 * JERSEY_PAD_F
    cy = (chest["maxy"] + chest["miny"]) / 2
    # торс
    b.box((0.0, cy, (z_bot + z_top) / 2), (half_w * 2, depth, z_top - z_bot),
          "jersey_main")
    # плечи (широкие наплечники)
    sh_half = half_w + SHOULDER_EXTRA
    b.box((0.0, cy, z_top - SHOULDER_H / 2),
          (sh_half * 2, depth + 0.02, SHOULDER_H), "jersey_main")
    # белая полоса плеч
    b.box((0.0, cy, z_top - 0.03),
          (sh_half * 1.5, (depth + 0.02) * 0.82, 0.03), "jersey_insert")
    # ворот-филлер (тёмный): заполняет проём вокруг шеи от плеч до подбородка,
    # чтобы сверху не зияла дыра открытого тела
    n = m["neck"]
    head = m["head"]
    if n:
        nw = n["maxx"] - n["minx"]
        nd = n["maxy"] - n["miny"]
        ncy = (n["maxy"] + n["miny"]) / 2
        neck_top = (head["minz"] + 0.03) if head else (z_top + 0.12)
        b.box((0.0, ncy, (z_top - 0.03 + neck_top) / 2),
              (nw + 0.06, nd + 0.06, neck_top - (z_top - 0.03)), "neck_dark")
    else:
        nw = 0.12
    # белый ворот-обод поверх плечевого блока
    b.box((0.0, cy, z_top + 0.015), (nw + COLLAR_W, depth * 0.85, 0.05),
          "jersey_insert")
    # рукав: обнимает bbox руки, от плеча до начала кисти (нахлёст с крагой)
    (ac, asz) = bb_center_size(arm, 0, SLEEVE_PAD, SLEEVE_PAD)
    x_in = sh_half - 0.02
    x_out = hand["minx"] + 0.03
    b.box(((x_in + x_out) / 2, ac[1], ac[2]),
          (x_out - x_in, asz[1], asz[2]), "jersey_main", mirror=True)
    # манжета (белая) у запястья
    b.box((x_out - 0.02, ac[1], ac[2]),
          (0.05, asz[1] * 1.03, asz[2] * 1.03), "jersey_insert", mirror=True)
    return b.finish(mat)


def build_gloves(mat, m):
    b = MeshBuilder("slot_gloves")
    (c, s) = bb_center_size(m["handR"], GLOVE_PAD, GLOVE_PAD, GLOVE_PAD)
    # удлиняем краги наружу (за кончики пальцев), центр смещаем на половину прибавки
    cx = c[0] + GLOVE_OUT / 2
    b.box((cx, c[1], c[2]), (s[0] + GLOVE_OUT, s[1], s[2]), "gloves", mirror=True)
    return b.finish(mat)


def build_helmet(mat, m):
    b = MeshBuilder("slot_helmet")
    h = m["head"]
    cx = (h["maxx"] + h["minx"]) / 2
    cy = (h["maxy"] + h["miny"]) / 2
    cz = (h["maxz"] + h["minz"]) / 2 + 0.02
    rx = (h["maxx"] - h["minx"]) / 2
    ry = (h["maxy"] - h["miny"]) / 2
    rz = (h["maxz"] - h["minz"]) / 2
    r = max(rx, rz) + HELMET_PAD
    center = (cx, cy, cz + HELMET_LIFT)
    bottom_z = cz - rz * HELMET_BOTTOM_FRAC
    brow_z = cz + rz * HELMET_BROW_FRAC
    front_y = cy  # лицо на +Y => срезаем перед (y>cy) снизу

    def cut(x, y, z):
        if z < bottom_z:
            return True
        if y > front_y + 0.005 and z < brow_z:
            return True
        return False

    b.ico(center, r, "helmet",
          squash=(1.02, (ry + HELMET_PAD) / r * 1.02, 1.0), subdiv=2, cut_fn=cut)
    # визор спереди на уровне глаз
    visor_y = h["maxy"] + VISOR_DEPTH * 0.4
    visor_z = cz + rz * 0.1
    b.box((cx, visor_y, visor_z),
          (rx * 2 * VISOR_W_FRAC, VISOR_DEPTH, VISOR_H), "visor")
    return b.finish(mat)


# --------------------------------------------------------------------------- #
#  МАТЕРИАЛ
# --------------------------------------------------------------------------- #
def build_material(palette_img):
    mat = bpy.data.materials.new("player_palette_mat")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Roughness"].default_value = 0.65
    bsdf.inputs["Metallic"].default_value = 0.0
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = palette_img
    tex.interpolation = "Closest"
    tex.extension = "EXTEND"
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    return mat


# --------------------------------------------------------------------------- #
#  СЦЕНА / СВЕТ / КАМЕРЫ / РЕНДЕР
# --------------------------------------------------------------------------- #
def clean_scene_extras(keep):
    for o in list(bpy.data.objects):
        if o not in keep:
            bpy.data.objects.remove(o, do_unlink=True)


def setup_lighting_and_ground():
    scene = bpy.context.scene
    world = bpy.data.worlds.new("preview_world")
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs["Color"].default_value = (0.55, 0.57, 0.60, 1.0)
        bg.inputs["Strength"].default_value = 0.7
    scene.world = world

    sun_data = bpy.data.lights.new("Sun", "SUN")
    sun_data.energy = 3.2
    sun_data.angle = math.radians(3.0)
    sun = bpy.data.objects.new("Sun", sun_data)
    sun.rotation_euler = (math.radians(52), math.radians(14), math.radians(-38))
    scene.collection.objects.link(sun)

    area_data = bpy.data.lights.new("Fill", "AREA")
    area_data.energy = 220.0
    area_data.size = 4.0
    area = bpy.data.objects.new("Fill", area_data)
    area.location = (2.5, 4.0, 2.2)
    d = Vector((0, 0, 1.0)) - area.location
    area.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    scene.collection.objects.link(area)

    mesh = bpy.data.meshes.new("ground")
    bmg = bmesh.new()
    bmesh.ops.create_grid(bmg, x_segments=1, y_segments=1, size=6.0)
    bmg.to_mesh(mesh)
    bmg.free()
    ground = bpy.data.objects.new("ground", mesh)
    ground.location = (0, 0, -0.002)
    gmat = bpy.data.materials.new("ground_mat")
    gmat.use_nodes = True
    gb = gmat.node_tree.nodes.get("Principled BSDF")
    if gb:
        gb.inputs["Base Color"].default_value = (0.72, 0.75, 0.80, 1.0)
        gb.inputs["Roughness"].default_value = 0.9
    ground.data.materials.append(gmat)
    scene.collection.objects.link(ground)
    return ground


def make_camera(name, location, target, ortho_scale=None, lens=None):
    cd = bpy.data.cameras.new(name)
    if ortho_scale is not None:
        cd.type = "ORTHO"
        cd.ortho_scale = ortho_scale
    else:
        cd.type = "PERSP"
        cd.lens = lens or 50.0
    cam = bpy.data.objects.new(name, cd)
    cam.location = location
    d = Vector(target) - Vector(location)
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.collection.objects.link(cam)
    return cam


def setup_render_engine():
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 48
    try:
        scene.cycles.use_denoising = True
    except Exception:
        pass
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False


def render_to(cam, res_x, res_y, filepath):
    scene = bpy.context.scene
    scene.camera = cam
    scene.render.resolution_x = res_x
    scene.render.resolution_y = res_y
    scene.render.resolution_percentage = 100
    scene.render.filepath = filepath
    bpy.ops.render.render(write_still=True)


# --------------------------------------------------------------------------- #
#  MAIN
# --------------------------------------------------------------------------- #
def main():
    # чистый старт
    bpy.ops.wm.read_homefile(use_empty=True)

    palette_img = build_palette()
    write_palette_layout()
    mat = build_material(palette_img)

    body = prepare_body()
    m = measure(body)
    zone_body_uvs(body)
    body.vertex_groups.clear()   # БЕЗ скелета — веса не нужны
    body.data.materials.clear()
    body.data.materials.append(mat)

    equip = [
        build_skates(mat, m),
        build_socks(mat, m),
        build_pants(mat, m),
        build_jersey(mat, m),
        build_gloves(mat, m),
        build_helmet(mat, m),
    ]
    all_objs = [body] + equip

    total = 0
    for o in all_objs:
        for p in o.data.polygons:
            total += max(0, len(p.vertices) - 2)
    print(f"[player] меши: {[o.name for o in all_objs]}")
    print(f"[player] треугольников суммарно: {total} (бюджет <= 5000)")
    if total > 5000:
        print("[player] ВНИМАНИЕ: превышен бюджет!", file=sys.stderr)

    # экспорт GLB
    bpy.ops.object.select_all(action="DESELECT")
    for o in all_objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.export_scene.gltf(filepath=GLB_PATH, export_format="GLB",
                              use_selection=True, export_apply=True,
                              export_yup=True)
    print(f"[player] GLB: {GLB_PATH}")

    # превью-сцена
    setup_lighting_and_ground()
    setup_render_engine()
    cams = {
        "front": make_camera("cam_front", (0, 4.6, 0.95), (0, 0, 0.95), ortho_scale=2.05),
        "side": make_camera("cam_side", (4.6, 0, 0.95), (0, 0, 0.95), ortho_scale=2.05),
        "three_quarter": make_camera("cam_3q", (3.2, 3.2, 1.9), (0, 0, 0.9), ortho_scale=2.4),
    }
    dist, elev, azim = 10.0, math.radians(40.0), math.radians(28.0)
    horiz = dist * math.cos(elev)
    cams["game"] = make_camera(
        "cam_game",
        (horiz * math.sin(azim), horiz * math.cos(azim), 0.9 + dist * math.sin(elev)),
        (0, 0, 0.9), lens=85.0)

    renders = {"front": (860, 1100), "side": (760, 1100),
               "three_quarter": (1000, 1000), "game": (1280, 800)}
    for key, (rx, ry) in renders.items():
        out = os.path.join(PREVIEW_DIR, f"player_{key}.png")
        render_to(cams[key], rx, ry, out)
        print(f"[player] превью: {out}")

    bpy.ops.wm.save_as_mainfile(filepath=BLEND_PATH)
    print(f"[player] BLEND: {BLEND_PATH}")
    print("[player] Готово. В ИГРУ НЕ ПОДКЛЮЧЕНО — оцени превью.")


if __name__ == "__main__":
    main()
