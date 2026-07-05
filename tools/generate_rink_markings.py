"""Офлайн-генератор текстуры разметки льда (PNG с прозрачностью).

ВАЖНО: в рантайме разметка рисуется процедурной flat-геометрией в rink.gd
(масштабируется под любой размер катка без перезапуска Python). Этот скрипт —
офлайн-инструмент/референс: принимает габариты и рисует пропорционально
(круги/точки — по правилам, не растяжением).

Запуск:  python tools/generate_rink_markings.py --length 56 --width 26
"""
import argparse
import os

from PIL import Image, ImageDraw

OUT_PATH = os.path.join("assets", "textures", "rink_markings.png")
SUPERSAMPLE = 2
PX_PER_M = 36.0  # разрешение текстуры на метр (до суперсэмплинга)

RED = (214, 40, 57, 255)
BLUE = (36, 78, 168, 255)

GOAL_LINE_FROM_END = 4.0  # линии ворот в 4 м от торцевых бортов
CENTER_CIRCLE_R = 4.5
CREASE_R = 2.4
FACEOFF_DOT_R = 0.3


def make_px(length: float, width: float):
    scale = PX_PER_M * SUPERSAMPLE

    def px(x_m: float, z_m: float) -> tuple[float, float]:
        return ((x_m + length / 2.0) * scale, (z_m + width / 2.0) * scale)

    return px, scale


def rect(draw, px, x0, z0, x1, z1, color) -> None:
    p0, p1 = px(x0, z0), px(x1, z1)
    draw.rectangle((p0[0], p0[1], p1[0], p1[1]), fill=color)


def disc(draw, px, scale, x, z, r_m, color) -> None:
    cx, cy = px(x, z)
    r = r_m * scale
    draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=color)


def circle_outline(draw, px, scale, x, z, r_m, width_m, color) -> None:
    cx, cy = px(x, z)
    r = r_m * scale
    draw.ellipse((cx - r, cy - r, cx + r, cy + r), outline=color,
                 width=max(1, round(width_m * scale)))


def arc(draw, px, scale, x, z, r_m, start_deg, end_deg, width_m, color) -> None:
    cx, cy = px(x, z)
    r = r_m * scale
    draw.arc((cx - r, cy - r, cx + r, cy + r), start_deg, end_deg, fill=color,
             width=max(1, round(width_m * scale)))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--length", type=float, default=56.0)
    parser.add_argument("--width", type=float, default=26.0)
    args = parser.parse_args()
    length, width = args.length, args.width

    px, scale = make_px(length, width)
    w_px = round(length * PX_PER_M)
    h_px = round(width * PX_PER_M)
    img = Image.new("RGBA", (w_px * SUPERSAMPLE, h_px * SUPERSAMPLE), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    goal_x = length / 2.0 - GOAL_LINE_FROM_END
    half_w = width / 2.0
    faceoff_x = goal_x - 6.0
    faceoff_z = half_w * 0.4

    # Красная центральная линия поперёк (30 см).
    rect(d, px, -0.15, -half_w, 0.15, half_w, RED)

    # Линии ворот (красные, 10 см).
    for sx in (-1, 1):
        rect(d, px, sx * goal_x - 0.05, -(half_w - 0.5),
             sx * goal_x + 0.05, half_w - 0.5, RED)

    # Центральный круг (синий контур 10 см) и центральная точка.
    circle_outline(d, px, scale, 0.0, 0.0, CENTER_CIRCLE_R, 0.10, BLUE)
    disc(d, px, scale, 0.0, 0.0, 0.15, BLUE)

    # 4 точки вбрасывания (красные, R 0.3), по 2 с каждой стороны.
    for sx in (-1, 1):
        for sz in (-1, 1):
            disc(d, px, scale, sx * faceoff_x, sz * faceoff_z, FACEOFF_DOT_R, RED)

    # Площадь ворот: красный полукруг R 2.4 от линии ворот в сторону центра.
    arc(d, px, scale, -goal_x, 0.0, CREASE_R, -90, 90, 0.08, RED)
    arc(d, px, scale, goal_x, 0.0, CREASE_R, 90, 270, 0.08, RED)

    img = img.resize((w_px, h_px), Image.LANCZOS)
    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    img.save(OUT_PATH)
    print(f"saved {OUT_PATH} {img.size} for rink {length}x{width}")


if __name__ == "__main__":
    main()
