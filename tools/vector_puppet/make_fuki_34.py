#!/usr/bin/env python3
"""Собирает векторный файл кошки в виде 3/4 (fuki_34_v01.svg) по ТЗ для иллюстратора.

Образец — растровый рисунок (ref34.png, правая фигура с листа ракурсов). Видимые формы
обводятся по рисунку и переводятся в плавные кривые; спрятанные части (тело под плащом,
руки в рукавах, стопы в сапогах, основания ушей) достраиваются простыми фигурами.

Запуск:  python3 make_fuki_34.py  выход.svg
Нужны: numpy, opencv, scipy, scikit-image.
"""
import sys
import math
import numpy as np
from base import *          # растр-образец, маски цветов, операции с масками
import vecfit

OUT = sys.argv[1] if len(sys.argv) > 1 else "fuki_34_v01.svg"

# ------------------------------------------------------------------ палитра (9 цветов)
C_CREAM = "#fcf8ee"      # шерсть
C_BLACK = "#0c0c0c"      # глаза, нос, рот
C_FUR = "#9da3a1"        # штрихи шерсти
C_RED = "#df2e31"        # плащ и сапоги
C_SEAM = "#a0181a"       # швы и кромки
C_SHINE = "#fbe6e2"      # блик на сапоге
C_PIVOT = "#ff00ff"      # точки вращения
LINE = 8.0               # толщина самой тонкой детали на листе (правило ТЗ)
LW = LINE / S / 2.0      # её половина в точках образца

# ------------------------------------------------------------------ опорные точки (в точках образца)
GROUND = (CX, GY)
HEAD_PIV = (187.0, 258.0)
NECK_PIV = (187.0, 292.0)
WAIST = (191.0, 362.0)
SH_N, WR_N = (138.0, 302.0), (79.0, 425.0)          # ближняя рука: плечо, запястье
SH_F, WR_F = (236.0, 302.0), (297.0, 424.0)         # дальняя рука
EL_N = ((SH_N[0] + WR_N[0]) / 2, (SH_N[1] + WR_N[1]) / 2)
EL_F = ((SH_F[0] + WR_F[0]) / 2, (SH_F[1] + WR_F[1]) / 2)
FAR_DROP = 5.0                                       # дальняя нога на рисунке стоит выше: опускаем на общую землю
HIP_N, KNEE_N, ANK_N = (168.0, 414.0), (166.5, 524.0), (162.0, 659.0)
HIP_F, KNEE_F, ANK_F = (219.0, 414.0), (218.0, 524.0), (216.0, 659.0)
TOE_N, TOE_F = (186.0, 688.0), (242.0, 688.0)
ARM_R, FORE_R = 11.0, 10.0
THIGH_R, KNEE_R, ANKLE_R = 19.0, 18.0, 15.0
BOOT_R_N, BOOT_R_F = 19.5, 18.5

shapes_log = []     # для отчёта: (часть, число узлов)


class Part:
    def __init__(self, name):
        self.name = name
        self.items = []          # строки SVG

    def add_mask(self, mask, color, tol=1.0, corner_deg=50.0, sigma=1.5, step=1.5, keep=1):
        cs = contours(mask, sigma)
        for pts in cs[:keep]:
            segs = vecfit.fit_closed(pts, tol=tol, step=step, corner_deg=corner_deg)
            self.items.append('<path d="%s" fill="%s"/>' % (vecfit.path_d(segs), color))
            shapes_log.append((self.name, len(segs)))
        return self

    def add_poly(self, pts_sheet, color, tol=0.6, corner_deg=50.0, step=1.0):
        segs = vecfit.fit_closed(np.asarray(pts_sheet, float), tol=tol, step=step, corner_deg=corner_deg, win=5)
        self.items.append('<path d="%s" fill="%s"/>' % (vecfit.path_d(segs), color))
        shapes_log.append((self.name, len(segs)))
        return self

    def add_capsule(self, a, b, color, width=LINE):
        """прямой штрих с круглыми концами; a, b — в точках образца"""
        ax, ay = to_sheet(a[0], a[1])
        bx, by = to_sheet(b[0], b[1])
        d = math.hypot(bx - ax, by - ay)
        r = width / 2.0
        if d < 0.5:
            self.items.append('<circle cx="%.2f" cy="%.2f" r="%.2f" fill="%s"/>' % (ax, ay, r, color))
            return self
        nx, ny = -(by - ay) / d * r, (bx - ax) / d * r
        self.items.append('<path d="M%.2f,%.2fL%.2f,%.2fA%.2f,%.2f 0 0 0 %.2f,%.2fL%.2f,%.2fA%.2f,%.2f 0 0 0 %.2f,%.2fZ" fill="%s"/>' % (
            ax + nx, ay + ny, bx + nx, by + ny, r, r, bx - nx, by - ny, ax - nx, ay - ny, r, r, ax + nx, ay + ny, color))
        shapes_log.append((self.name, 4))
        return self

    def add_stroke(self, pts, color, width=LINE, width_end=None, tol=0.5):
        """плавная линия через точки образца, разобранная в фигуру; толщина может сужаться к концу"""
        self.add_poly(stroke_outline(pts, width, width_end), color, tol=tol, corner_deg=70.0)
        return self

    def add_ellipse(self, c, rx, ry, color, deg=0.0):
        x, y = to_sheet(c[0], c[1])
        tr = ' transform="rotate(%.2f %.2f %.2f)"' % (deg, x, y) if abs(deg) > 0.01 else ""
        self.items.append('<ellipse cx="%.2f" cy="%.2f" rx="%.2f" ry="%.2f"%s fill="%s"/>' % (x, y, rx * S, ry * S, tr, color))
        shapes_log.append((self.name, 4))
        return self


def smooth_line(pts, n_per=10):
    """ломаная -> плавная кривая через те же точки (сплайн Катмулла — Рома)"""
    p = np.asarray(pts, float)
    if len(p) < 3:
        t = np.linspace(0, 1, n_per + 1)[:, None]
        return p[0] * (1 - t) + p[-1] * t
    ext = np.vstack([2 * p[0] - p[1], p, 2 * p[-1] - p[-2]])
    out = []
    for i in range(1, len(ext) - 2):
        p0, p1, p2, p3 = ext[i - 1], ext[i], ext[i + 1], ext[i + 2]
        for t in np.linspace(0, 1, n_per, endpoint=False):
            out.append(0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t ** 3))
    out.append(p[-1])
    return np.array(out)


def stroke_outline(pts, width, width_end=None):
    """контур линии заданной толщины с круглыми концами, в координатах листа"""
    c = smooth_line(pts)
    x, y = to_sheet(c[:, 0], c[:, 1])
    c = np.stack([x, y], 1)
    d = np.gradient(c, axis=0)
    d /= np.maximum(np.hypot(d[:, 0], d[:, 1])[:, None], 1e-9)
    nrm = np.stack([-d[:, 1], d[:, 0]], 1)
    w0 = width / 2.0
    w1 = w0 if width_end is None else width_end / 2.0
    w = np.linspace(w0, w1, len(c))[:, None]
    left = c + nrm * w
    right = c - nrm * w
    def cap(center, direction, r):
        a0 = math.atan2(direction[1], direction[0])
        return [center + r * np.array([math.cos(a0 + math.pi / 2 - math.pi * k / 8), math.sin(a0 + math.pi / 2 - math.pi * k / 8)]) for k in range(1, 8)]
    end_cap = cap(c[-1], d[-1], w1)
    start_cap = cap(c[0], -d[0], w0)
    return np.vstack([left, end_cap, right[::-1], start_cap])


def pca_segment(mask):
    """вытянутое пятно -> (начало, конец, длина, толщина) в точках образца"""
    ys, xs = np.where(mask)
    p = np.stack([XC[ys, xs], YC[ys, xs]], 1)
    c = p.mean(0)
    w, v = np.linalg.eigh(np.cov((p - c).T))
    axis = v[:, 1]
    t = (p - c) @ axis
    n = (p - c) @ v[:, 0]
    a, b = c + axis * t.min(), c + axis * t.max()
    return a, b, t.max() - t.min(), n.max() - n.min()


def find_ticks(region, exclude, lum_thr, min_len=5.0, spacing=7.0, limit=99):
    """штрихи шерсти: тёмные тонкие пятна внутри region. Возвращает отрезки, прорежённые до spacing."""
    lum = (R + G + B) / 3.0
    m = region & (lum < lum_thr) & ~exclude
    lab, n = ndi.label(m)
    found = []
    for sl_i, sl in enumerate(ndi.find_objects(lab)):
        if sl is None:
            continue
        sub = lab[sl] == (sl_i + 1)
        if sub.sum() < 20 * UP:
            continue
        full = np.zeros_like(m)
        full[sl] = sub
        a, b, ln, th = pca_segment(full)
        if ln < min_len or ln < 2.2 * th:
            continue
        found.append((ln, a, b))
    found.sort(key=lambda t: -t[0])
    kept = []
    for ln, a, b in found:
        mid = (a + b) / 2
        if all(np.hypot(*(mid - (ka + kb) / 2)) >= spacing for _, ka, kb in kept):
            kept.append((ln, a, b))
        if len(kept) >= limit:
            break
    return kept


def trim(a, b, cut):
    """укоротить отрезок с обоих концов на cut (чтобы круглые концы штриха не удлиняли его)"""
    a = np.asarray(a, float); b = np.asarray(b, float)
    d = b - a
    ln = np.hypot(*d)
    if ln <= 2 * cut + 0.5:
        m = (a + b) / 2
        return m, m
    d /= ln
    return a + d * cut, b - d * cut


# ================================================================== ГОЛОВА
REDW = (R - G > 60) & (R > 110)
head = (DBG > 55) & ~REDW & (YC < 300)                       # всё, что не фон и не плащ
head = largest(opening(head, 2.5))                           # усы тоньше 5 точек — отпадают
head = ndi.binary_fill_holes(closing(head, 6.0))
head = opening(head, 5.0)                                    # пушистый край щёк сглаживается
# уши отрезаются прямыми линиями; под каждым ухом у головы остаётся пологий купол
EAR_CUT_N = ((77.5, 128.0), (160.0, 107.0))
EAR_CUT_F = ((219.0, 103.0), (286.0, 150.0))


def bulge(a, b, h):
    """сегмент круга над отрезком a-b высотой h (в сторону уха)"""
    a = np.array(a, float); b = np.array(b, float)
    mid = (a + b) / 2
    d = b - a
    ln = np.hypot(*d)
    n = np.array([-d[1], d[0]]) / ln                         # на экране смотрит вниз, от уха
    rr = (ln * ln / 4 + h * h) / (2 * h)
    return disc(mid + n * (rr - h), rr) & ~half(a, b)


ear_near_m = head & ~half(*EAR_CUT_N) & (XC < 166)
ear_far_m = head & ~half(*EAR_CUT_F) & (XC > 213)
skull = (head & ~ear_near_m & ~ear_far_m) | bulge(EAR_CUT_N[0], EAR_CUT_N[1], 10.0) | bulge(EAR_CUT_F[0], EAR_CUT_F[1], 10.0)
skull = opening(closing(skull, 12.0), 8.0)


def ear_full(e):
    """ухо целиком: видимая часть + основание, уходящее под голову на 30 единиц листа"""
    base = dilate(e, 30.0 / S) & skull
    return closing(e | base, 4.0)


ear_near_full = ear_full(ear_near_m)
ear_far_full = ear_full(ear_far_m)


def ear_pivot(e):
    seam = dilate(e, 2.0) & skull
    return (float(XC[seam].mean()), float(YC[seam].mean()))


EAR_N, EAR_F = ear_pivot(ear_near_m), ear_pivot(ear_far_m)

# глаза: тёмное кольцо, белок внутри, зрачок
eye_dark = DARK & (YC > 150) & (YC < 228) & (XC > 100) & (XC < 290)
eye_n_ring = largest(eye_dark & (XC < 200))
eye_f_ring = largest(eye_dark & (XC > 225))
RING = 3.6          # толщина ободка глаза: 8 единиц листа


def eye_parts(ring):
    outer = ndi.binary_fill_holes(closing(ring, 1.0))
    white = erode(outer, RING)
    pupil = largest(opening(ring & erode(outer, RING + 0.6), 5.0))
    pupil = dilate(pupil, 0.4)
    c = (float(XC[outer].mean()), float(YC[outer].mean()))
    return outer, white, pupil, c


eye_n_outer, eye_n_white, eye_n_pupil, EYE_N = eye_parts(eye_n_ring)
eye_f_outer, eye_f_white, eye_f_pupil, EYE_F = eye_parts(eye_f_ring)

# нос: перевёрнутый треугольник; рот — «ножки» под ним
nose_all = largest(DARK & (XC > 200) & (XC < 230) & (YC > 214) & (YC < 244))
nose_m = dilate(opening(nose_all & (YC < 227.0), 1.6), 0.3)

# усы: по три с каждой стороны, от щеки наружу
WHISKERS_F = [[(266.0, 231.5), (284.0, 229.5), (305.0, 226.0), (325.5, 225.0)],
              [(268.0, 236.0), (288.0, 237.5), (308.0, 240.5), (327.5, 243.5)],
              [(262.0, 241.0), (284.0, 249.0), (306.0, 260.0), (328.5, 273.5)]]
WHISKERS_N = [[(128.0, 233.5), (104.0, 230.0), (78.0, 227.5), (52.0, 228.0)],
              [(128.0, 238.5), (104.0, 240.5), (78.0, 243.0), (53.0, 246.5)],
              [(134.0, 243.0), (106.0, 252.0), (78.0, 263.5), (52.0, 276.5)]]
whisker_zone = blank()
for w in WHISKERS_F + WHISKERS_N:
    for q0, q1 in zip(w[:-1], w[1:]):
        whisker_zone |= capsule(q0, q1, 4.5)

# штрихи шерсти на голове (не на лице и не поперёк усов)
face_ex = dilate(eye_n_outer | eye_f_outer | nose_all, 3.0) | whisker_zone
head_ticks = find_ticks(erode(head, 1.5) & half(*EAR_CUT_N) & half(*EAR_CUT_F), face_ex, 205.0, min_len=7.0, spacing=7.5)

# ================================================================== ТЕЛО ПОД ОДЕЖДОЙ
neck_m = capsule((187.0, 246.0), (187.0, 302.0), 13.0)
torso_m = capsule((187.0, 314.0), (192.0, 398.0), 40.0, 31.0) | capsule((152.0, 305.0), (222.0, 305.0), 14.0) | capsule((176.0, 410.0), (211.0, 410.0), 23.0)
torso_m = closing(torso_m, 16.0)

arm_n_upper = capsule(SH_N, EL_N, ARM_R)
arm_n_fore = capsule(EL_N, WR_N, ARM_R, FORE_R)
arm_f_upper = capsule(SH_F, EL_F, ARM_R)
arm_f_fore = capsule(EL_F, WR_F, ARM_R, FORE_R)

paw_n_vis = largest(CREAM & (XC > 36) & (XC < 96) & (YC > 418) & (YC < 482))
paw_f_vis = largest(CREAM & (XC > 280) & (XC < 332) & (YC > 415) & (YC < 478))


def paw_full(vis, wrist):
    """кисть: видимая часть + запястье, уходящее в рукав"""
    c = (float(XC[vis].mean()), float(YC[vis].mean()))
    m = closing(vis, 3.0) | capsule(wrist, c, FORE_R, FORE_R + 4.0)
    return ndi.binary_fill_holes(closing(m, 6.0)), c


paw_n_m, PAW_N_C = paw_full(paw_n_vis, WR_N)
paw_f_m, PAW_F_C = paw_full(paw_f_vis, WR_F)
paw_n_ticks = find_ticks(erode(ndi.binary_fill_holes(closing(paw_n_vis, 3.0)), 2.5), blank(), 222.0, min_len=5.0, spacing=6.0, limit=3)
paw_f_ticks = find_ticks(erode(ndi.binary_fill_holes(closing(paw_f_vis, 3.0)), 2.5), blank(), 222.0, min_len=5.0, spacing=6.0, limit=3)

thigh_n = capsule(HIP_N, KNEE_N, THIGH_R, KNEE_R)
shin_n = capsule(KNEE_N, ANK_N, KNEE_R, ANKLE_R)
thigh_f = capsule(HIP_F, KNEE_F, THIGH_R, KNEE_R)
shin_f = capsule(KNEE_F, ANK_F, KNEE_R, ANKLE_R)
leg_n_vis = largest(CREAM & (XC > 144) & (XC < 192) & (YC > 524) & (YC < 594))
leg_f_vis = largest(CREAM & (XC > 195) & (XC < 242) & (YC > 521) & (YC < 592))
knee_zone = disc(KNEE_N, KNEE_R + 2.0) | disc(KNEE_F, KNEE_R + 2.0)
leg_zone = (YC < 585.0) & (YC > 528.0)
leg_n_ticks = find_ticks(erode(ndi.binary_fill_holes(closing(leg_n_vis, 3.0)), 2.0) & leg_zone, knee_zone, 215.0, min_len=6.0, spacing=7.0, limit=6)
leg_f_ticks = find_ticks(erode(ndi.binary_fill_holes(closing(leg_f_vis, 3.0)), 2.0) & leg_zone, knee_zone, 215.0, min_len=6.0, spacing=7.0, limit=6)

# ================================================================== САПОГИ
red_low = RED & (YC > 580)
red_low = ndi.binary_fill_holes(closing(red_low | (DARK & (YC > 580) & (R > 90) & (G < 70)), 1.5))
boots = largest(red_low, 2)
boots.sort(key=lambda m: XC[m].mean())
boot_n, boot_f = boots[0], boots[1]
boot_f = np.roll(boot_f, int(round(FAR_DROP * UP)), axis=0)           # дальний сапог — на общую землю
boot_f = boot_f | (disc((210.5, 682.5), 10.5) & (YC < GY - 0.3)) | poly([(199.5, 660.0), (212.0, 660.0), (214.0, 692.6), (203.0, 692.6), (200.0, 682.0)])   # пятка, спрятанная за ближним носком
boot_n = opening(closing(boot_n, 3.0), 3.0)
boot_f = opening(closing(boot_f, 3.0), 3.0)


def boot_split(boot, ankle, r):
    shaft = (boot & (YC <= ankle[1])) | (disc(ankle, r) & dilate(boot, 0.5))
    foot = (boot & (YC >= ankle[1])) | (disc(ankle, r) & dilate(boot, 0.5))
    return closing(shaft, 2.0), closing(foot, 2.0)


boot_n_shaft, boot_n_foot = boot_split(boot_n, ANK_N, BOOT_R_N)
boot_f_shaft, boot_f_foot = boot_split(boot_f, ANK_F, BOOT_R_F)
foot_n = erode(boot_n_foot, 4.0) | (disc(ANK_N, ANKLE_R) & erode(boot_n, 2.0))
foot_f = erode(boot_f_foot, 4.0) | (disc(ANK_F, ANKLE_R) & erode(boot_f, 2.0))
foot_n = closing(largest(foot_n), 3.0)
foot_f = closing(largest(foot_f), 3.0)

# ================================================================== ПЛАЩ
red_top = RED & (YC > 255) & (YC < 535)
coat_all = ndi.binary_fill_holes(closing(largest(red_top), 2.0))
# правый край плаща (за ним — дальний рукав) и линия внутреннего края ближнего рукава
EDGE_R = [(227.0, 262.0), (229.5, 272.0), (235.5, 284.0), (241.0, 296.0), (251.0, 320.0), (260.0, 344.0), (268.5, 368.0),
          (276.0, 392.0), (283.0, 416.0), (288.5, 440.0), (293.5, 464.0), (299.5, 488.0), (303.5, 505.0), (305.0, 540.0)]
EDGE_L = [(136.5, 262.0), (75.0, 530.0)]                 # левый край плаща, спрятанный под ближним рукавом
LINE_A = [(160.0, 266.0), (157.0, 274.0), (153.0, 296.0), (147.5, 320.0), (141.0, 344.0), (135.0, 356.0), (126.5, 380.0),
          (117.5, 404.0), (107.5, 428.0), (100.5, 446.0)]  # внутренний край ближнего рукава
CUFF_N = [(100.5, 446.0), (51.0, 416.0)]
CUFF_F = [(313.5, 416.0), (288.5, 441.0)]
CUFF_F_HID = (276.5, 453.0)                              # спрятанный за плащом угол манжеты дальнего рукава

coat_body_m = coat_all & poly([EDGE_L[0]] + EDGE_R + [(60.0, 540.0), EDGE_L[1]])
coat_body_m = largest(opening(coat_body_m, 1.5))

sleeve_n_m = coat_all & poly(LINE_A + [(40.0, 409.3), (40.0, 250.0), (160.0, 250.0)])
sleeve_n_m = largest(opening(sleeve_n_m, 1.0)) | (disc(SH_N, 14.0) & coat_all)
sleeve_n_m = closing(sleeve_n_m, 2.0)

sleeve_f_vis = coat_all & poly([(229.5, 262.0)] + EDGE_R[1:10] + [CUFF_F[1], (CUFF_F[0][0] + 12.0, CUFF_F[0][1] - 12.0), (330.0, 250.0)])
sleeve_f_m = largest(opening(sleeve_f_vis, 1.0)) | poly([(222.0, 272.0), (236.0, 276.0), CUFF_F[1], CUFF_F_HID, (212.0, 296.0)]) | disc(SH_F, 14.0)
sleeve_f_m = closing(sleeve_f_m, 2.0)


def col_y(mask, x):
    """нижняя граница маски в столбце x (в точках образца)"""
    col = mask[:, int(round((x + 0.5) * UP - 0.5))]
    ys = np.where(col)[0]
    return (ys.max() + 0.5) / UP - 0.5


hem_line = [(x, col_y(coat_body_m, x) - 2.6) for x in np.arange(92.0, 296.1, 17.0)]
SEAM_B = [(157.0, 275.0), (153.0, 296.0), (147.5, 320.0), (141.0, 344.0), (137.5, 368.0), (132.5, 392.0), (127.0, 416.0),
          (122.5, 440.0), (117.5, 464.0), (112.5, 488.0), (108.5, 512.0)]
SEAM_C = [(202.5, 277.0), (206.0, 296.0), (210.5, 320.0), (214.5, 344.0), (217.5, 368.0), (220.5, 392.0), (222.5, 416.0),
          (224.5, 440.0), (226.5, 464.0), (228.0, 488.0), (229.5, 512.0)]
SEAM_R = [(p[0] - 2.2, p[1]) for p in EDGE_R[2:13]]
COLLAR = [(159.0, 273.5), (172.0, 275.5), (187.0, 276.5), (203.0, 276.5), (216.0, 275.0), (227.0, 272.5)]

# ================================================================== СБОРКА ЧАСТЕЙ
body, clothes = [], []


def part(layer, name):
    p = Part(name)
    layer.append(p)
    return p


def add_ticks(p, ticks, color=C_FUR):
    for ln, a, b in ticks:
        a2, b2 = trim(a, b, LW)
        p.add_capsule(a2, b2, color)


# ---- слой body, снизу вверх (порядок из ТЗ)
part(body, "arm_far_upper").add_mask(arm_f_upper, C_CREAM)
part(body, "arm_far_fore").add_mask(arm_f_fore, C_CREAM)
p = part(body, "paw_far").add_mask(paw_f_m, C_CREAM, tol=0.8)
add_ticks(p, paw_f_ticks)
part(body, "leg_far_thigh").add_mask(thigh_f, C_CREAM)
p = part(body, "leg_far_shin").add_mask(shin_f, C_CREAM)
add_ticks(p, leg_f_ticks)
part(body, "foot_far").add_mask(foot_f, C_CREAM)
part(body, "ear_far").add_mask(ear_far_full, C_CREAM, tol=0.9)
part(body, "torso").add_mask(torso_m, C_CREAM)
part(body, "neck").add_mask(neck_m, C_CREAM)
part(body, "leg_near_thigh").add_mask(thigh_n, C_CREAM)
p = part(body, "leg_near_shin").add_mask(shin_n, C_CREAM)
add_ticks(p, leg_n_ticks)
part(body, "foot_near").add_mask(foot_n, C_CREAM)
p = part(body, "head").add_mask(skull, C_CREAM, tol=1.4, corner_deg=70.0, sigma=3.0)
add_ticks(p, head_ticks)
part(body, "ear_near").add_mask(ear_near_full, C_CREAM, tol=0.9)
part(body, "eye_far_white").add_mask(eye_f_outer, C_BLACK, tol=0.6).add_mask(eye_f_white, C_CREAM, tol=0.6)
part(body, "eye_far_pupil").add_mask(eye_f_pupil, C_BLACK, tol=0.6)
part(body, "eye_near_white").add_mask(eye_n_outer, C_BLACK, tol=0.6).add_mask(eye_n_white, C_CREAM, tol=0.6)
part(body, "eye_near_pupil").add_mask(eye_n_pupil, C_BLACK, tol=0.6)


def eyelids(side, outer, c):
    """веки: прищур и закрытый глаз. Цвет головы, снизу тёмная линия ресниц."""
    ys = YC[outer]
    top, bot = float(ys.min()), float(ys.max())
    xs = XC[outer]
    x0, x1 = float(xs.min()), float(xs.max())
    cover = dilate(outer, 1.2)
    for state, level in (("half", top + (bot - top) * 0.50), ("closed", top + (bot - top) * 0.80)):
        lid = cover & (YC <= level) if state == "half" else cover
        p = part(body, "eyelid_%s__%s" % (side, state)).add_mask(lid, C_CREAM, tol=0.6)
        sag = 5.0 if state == "closed" else 3.0
        w = (x1 - x0) / 2.0
        line = []
        for k in np.linspace(-1.0, 1.0, 7):
            x = c[0] + k * (w - 2.0)
            # линия ресниц идёт по хорде глаза и чуть провисает к середине
            y = level + sag * (1 - k * k) - (0.0 if state == "half" else 4.0)
            line.append((x, y))
        p.add_stroke(line, C_BLACK, width=LINE + 2.0)


eyelids("far", eye_f_outer, EYE_F)
eyelids("near", eye_n_outer, EYE_N)
part(body, "nose").add_mask(nose_m, C_BLACK, tol=0.5)
p = part(body, "mouth")
p.add_stroke([(216.6, 224.0), (216.4, 229.0), (215.4, 233.2), (211.5, 237.2), (205.2, 240.0)], C_BLACK)
p.add_stroke([(216.4, 229.5), (217.8, 233.6), (220.6, 237.0), (224.2, 239.4)], C_BLACK)
p = part(body, "whiskers_far")
for w in WHISKERS_F:
    p.add_stroke(w, C_CREAM)
p = part(body, "whiskers_near")
for w in WHISKERS_N:
    p.add_stroke(w, C_CREAM)
part(body, "arm_near_upper").add_mask(arm_n_upper, C_CREAM)
part(body, "arm_near_fore").add_mask(arm_n_fore, C_CREAM)
p = part(body, "paw_near").add_mask(paw_n_m, C_CREAM, tol=0.8)
add_ticks(p, paw_n_ticks)

# ---- слой clothes
p = part(clothes, "sleeve_far").add_mask(sleeve_f_m, C_RED)
p.add_stroke([(CUFF_F[0][0] - 1.2, CUFF_F[0][1] - 1.6), (CUFF_F[1][0] - 1.2, CUFF_F[1][1] - 1.6), (CUFF_F_HID[0] - 0.5, CUFF_F_HID[1] - 2.0)], C_SEAM)
p = part(clothes, "boot_far_shaft").add_mask(boot_f_shaft, C_RED, tol=1.2, sigma=2.5)
p = part(clothes, "boot_far_foot").add_mask(boot_f_foot, C_RED, tol=1.2, sigma=2.5)
p.add_ellipse((243.5, 673.5 + FAR_DROP), 5.4, 2.2, C_SHINE, deg=-4.0)
p = part(clothes, "boot_near_shaft").add_mask(boot_n_shaft, C_RED, tol=1.2, sigma=2.5)
p = part(clothes, "boot_near_foot").add_mask(boot_n_foot, C_RED, tol=1.2, sigma=2.5)
p.add_ellipse((184.0, 678.0), 5.6, 2.2, C_SHINE, deg=4.0)
p = part(clothes, "coat_body").add_mask(coat_body_m, C_RED, tol=1.0)
p.add_stroke(COLLAR, C_SEAM)
p.add_stroke(SEAM_B, C_SEAM)
p.add_stroke(SEAM_C, C_SEAM)
p.add_stroke(SEAM_R, C_SEAM)
p.add_stroke(hem_line, C_SEAM)
p = part(clothes, "sleeve_near").add_mask(sleeve_n_m, C_RED, tol=1.0)
p.add_stroke([(q[0] - 1.6, q[1]) for q in LINE_A[1:]], C_SEAM)
p.add_stroke([(CUFF_N[0][0] - 1.2, CUFF_N[0][1] - 2.4), (CUFF_N[1][0] + 3.0, CUFF_N[1][1] - 0.6)], C_SEAM)

# ---- слой pivots: 22 точки
pivots = [
    ("pivot_ground", GROUND), ("pivot_waist", WAIST), ("pivot_neck", NECK_PIV), ("pivot_head", HEAD_PIV),
    ("pivot_shoulder_near", SH_N), ("pivot_shoulder_far", SH_F), ("pivot_elbow_near", EL_N), ("pivot_elbow_far", EL_F),
    ("pivot_wrist_near", WR_N), ("pivot_wrist_far", WR_F), ("pivot_hip_near", HIP_N), ("pivot_hip_far", HIP_F),
    ("pivot_knee_near", KNEE_N), ("pivot_knee_far", KNEE_F), ("pivot_ankle_near", ANK_N), ("pivot_ankle_far", ANK_F),
    ("pivot_toe_near", TOE_N), ("pivot_toe_far", TOE_F), ("pivot_ear_near", EAR_N), ("pivot_ear_far", EAR_F),
    ("pivot_eye_near", EYE_N), ("pivot_eye_far", EYE_F),
]

L = ['<?xml version="1.0" encoding="UTF-8"?>',
     '<svg id="fuki_34" xmlns="http://www.w3.org/2000/svg" version="1.1" width="2000" height="2000" viewBox="0 0 2000 2000">']
for layer_name, layer in (("body", body), ("clothes", clothes)):
    L.append('  <g id="%s">' % layer_name)
    for p in layer:
        # сменные детали (веки) записаны в файл, но скрыты: в браузере кошка видна с открытыми глазами
        hidden = ' display="none"' if "__" in p.name else ""
        L.append('    <g id="%s"%s>' % (p.name, hidden))
        for it in p.items:
            L.append("      " + it)
        L.append("    </g>")
    L.append("  </g>")
L.append('  <g id="pivots">')
for name, pt in pivots:
    x, y = to_sheet(pt[0], pt[1])
    L.append('    <circle id="%s" cx="%.2f" cy="%.2f" r="5" fill="%s"/>' % (name, x, y, C_PIVOT))
L.append("  </g>")
L.append("</svg>")
open(OUT, "w", encoding="utf-8").write("\n".join(L) + "\n")

total = sum(n for _, n in shapes_log)
print("Записано: %s" % OUT)
print("Частей: %d (body %d, clothes %d), фигур: %d, узлов всего: %d, точек вращения: %d" % (
    len(body) + len(clothes), len(body), len(clothes), len(shapes_log), total, len(pivots)))
big_shapes = sorted(shapes_log, key=lambda t: -t[1])[:8]
print("Самые сложные фигуры (узлов):", ", ".join("%s %d" % t for t in big_shapes))
print("Штрихов шерсти: голова %d, ноги %d + %d, кисти %d + %d" % (len(head_ticks), len(leg_n_ticks), len(leg_f_ticks), len(paw_n_ticks), len(paw_f_ticks)))
