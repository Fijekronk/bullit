"""Генерирует текстуру разметки льда assets/textures/rink_markings.png (2048x1024, RGBA).

Маппинг: каток 40 x 20 м -> 2048 x 1024 px (51.2 px/м).
Ось X изображения = ось X катка (длина), ось Y изображения = ось Z катка (ширина).
Рисуем с 2x суперсэмплингом и даунскейлом для сглаживания.

Запуск из корня проекта:  python tools/generate_rink_markings.py
"""
import os

from PIL import Image, ImageDraw

OUT_PATH = os.path.join("assets", "textures", "rink_markings.png")
WIDTH, HEIGHT = 2048, 1024
SUPERSAMPLE = 2
SCALE = WIDTH * SUPERSAMPLE / 40.0  # px на метр

RED = (214, 40, 57, 255)
BLUE = (36, 78, 168, 255)

GOAL_LINE_X = 17.0        # линии ворот: 3 м от торцевых бортов
GOAL_LINE_HALF_SPAN = 9.85  # до начала скругления бортов
CENTER_CIRCLE_R = 4.5
CREASE_R = 2.4
FACEOFF_DOT_R = 0.3
FACEOFF_X = 11.0
FACEOFF_Z = 4.0


def px(x_m: float, z_m: float) -> tuple[float, float]:
    return ((x_m + 20.0) * SCALE, (z_m + 10.0) * SCALE)


def rect(draw: ImageDraw.ImageDraw, x0, z0, x1, z1, color) -> None:
    p0, p1 = px(x0, z0), px(x1, z1)
    draw.rectangle((p0[0], p0[1], p1[0], p1[1]), fill=color)


def disc(draw: ImageDraw.ImageDraw, x, z, r_m, color) -> None:
    cx, cy = px(x, z)
    r = r_m * SCALE
    draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=color)


def circle_outline(draw: ImageDraw.ImageDraw, x, z, r_m, width_m, color) -> None:
    cx, cy = px(x, z)
    r = r_m * SCALE
    draw.ellipse((cx - r, cy - r, cx + r, cy + r), outline=color,
                 width=max(1, round(width_m * SCALE)))


def arc(draw: ImageDraw.ImageDraw, x, z, r_m, start_deg, end_deg, width_m, color) -> None:
    cx, cy = px(x, z)
    r = r_m * SCALE
    draw.arc((cx - r, cy - r, cx + r, cy + r), start_deg, end_deg, fill=color,
             width=max(1, round(width_m * SCALE)))


def main() -> None:
    img = Image.new("RGBA", (WIDTH * SUPERSAMPLE, HEIGHT * SUPERSAMPLE), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # Красная центральная линия поперёк (30 см).
    rect(d, -0.15, -10.0, 0.15, 10.0, RED)

    # Линии ворот (красные, 10 см), обрезаны до начала скруглений.
    for sx in (-1, 1):
        rect(d, sx * GOAL_LINE_X - 0.05, -GOAL_LINE_HALF_SPAN,
             sx * GOAL_LINE_X + 0.05, GOAL_LINE_HALF_SPAN, RED)

    # Центральный круг (синий контур 10 см) и центральная точка.
    circle_outline(d, 0.0, 0.0, CENTER_CIRCLE_R, 0.10, BLUE)
    disc(d, 0.0, 0.0, 0.15, BLUE)

    # 4 точки вбрасывания (красные, R 0.3), по 2 с каждой стороны.
    for sx in (-1, 1):
        for sz in (-1, 1):
            disc(d, sx * FACEOFF_X, sz * FACEOFF_Z, FACEOFF_DOT_R, RED)

    # Площадь ворот: красный полукруг R 2.4 от линии ворот в сторону центра.
    # PIL: угол 0 = +X, по часовой (ось Y изображения вниз).
    arc(d, -GOAL_LINE_X, 0.0, CREASE_R, -90, 90, 0.08, RED)   # левые ворота
    arc(d, GOAL_LINE_X, 0.0, CREASE_R, 90, 270, 0.08, RED)    # правые ворота

    img = img.resize((WIDTH, HEIGHT), Image.LANCZOS)
    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    img.save(OUT_PATH)
    print(f"saved {OUT_PATH} {img.size}")


if __name__ == "__main__":
    main()
