#!/usr/bin/env python3
"""Превью векторной куклы: рисует SVG так, как его читает игра (через tools/svg_to_puppet.py).

Запуск:  python3 preview.py  файл.svg  папка
В папку кладутся два PNG из ТЗ: собранная кошка на прозрачном фоне (2000 px по высоте)
и тот же кадр с точками вращения.
Нужны: numpy, opencv."""
import os
import sys
import cv2
import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import svg_to_puppet as sp


def render(svg, scale=1.0, clothes=True, pivots=False, variants=(), ss=2):
    """Возвращает картинку BGRA размером 2000*scale. Сменные детали (имя с «__») скрыты, если не названы в variants."""
    rd = sp.Reader().read(svg)
    n = int(2000 * scale * ss)
    img = np.zeros((n, n, 4), np.uint8)
    for name, layer, shapes in rd.parts:
        if layer.startswith("clothes") and not clothes:
            continue
        if "__" in name and name not in variants:
            continue
        for s in shapes:
            polys = [(np.array(c) * scale * ss).astype(np.int32) for c in [s.outer] + list(s.holes)]
            col = tuple(int(round(c * 255)) for c in s.color[::-1]) + (255,)
            cv2.fillPoly(img, polys, col)
    if pivots:
        for nm, p in rd.pivots.items():
            c = (int(p[0] * scale * ss), int(p[1] * scale * ss))
            cv2.circle(img, c, int(9 * scale * ss), (0, 0, 0, 255), -1)
            cv2.circle(img, c, int(6 * scale * ss), (255, 0, 255, 255), -1)
    return cv2.resize(img, (int(2000 * scale), int(2000 * scale)), interpolation=cv2.INTER_AREA)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(2)
    svg, out_dir = sys.argv[1], sys.argv[2]
    stem = os.path.splitext(os.path.basename(svg))[0]
    cv2.imwrite(os.path.join(out_dir, stem + "_preview.png"), render(svg))
    cv2.imwrite(os.path.join(out_dir, stem + "_pivots.png"), render(svg, pivots=True))
    print("Готово: %s_preview.png и %s_pivots.png" % (stem, stem))
