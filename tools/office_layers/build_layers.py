#!/usr/bin/env python3
"""Режет картинку офиса на слои для параллакса: far (город за окном), mid (стены и шкафы),
near (мебель вместе с кошкой за столом и её стулом). Запуск: python3 build_layers.py src.png out_dir"""
import sys
import numpy as np
import cv2
from scipy import ndimage
from scipy.sparse import lil_matrix, csr_matrix
from scipy.sparse.linalg import spsolve

SRC, OUT = sys.argv[1], sys.argv[2]
img = cv2.cvtColor(cv2.imread(SRC, cv2.IMREAD_UNCHANGED)[:, :, :3], cv2.COLOR_BGR2RGB).astype(np.float64)
H, W = img.shape[:2]
R, G, B = img[:, :, 0], img[:, :, 1], img[:, :, 2]
yy, xx = np.mgrid[0:H, 0:W]
FLOOR = 1020                      # с этой строки начинается пол (тёмная полоса)


def rect(x0, y0, x1, y1):
    m = np.zeros((H, W), bool)
    m[y0:y1, x0:x1] = True
    return m


# ------------------------------------------------------------------ окна
# (левый край, правый край, центр дуги по y) — границы стекла с точностью до полпикселя
WINDOWS = [(1193.4, 1455.6), (1540.0, 1802.3), (1886.6, 2148.6)]
GLASS_BOTTOM = 1010.5             # ниже стекла идёт плинтус (стена)
ARCH_Y = 333.0
SS = 4                            # сглаживание края: считаем маску в 4 раза крупнее


def glass_coverage():
    cov = np.zeros((H, W))
    ys = (np.arange(H * SS) + 0.5) / SS
    xs = (np.arange(W * SS) + 0.5) / SS
    X, Y = np.meshgrid(xs, ys)
    big = np.zeros((H * SS, W * SS), bool)
    for x0, x1 in WINDOWS:
        cx, r = (x0 + x1) / 2, (x1 - x0) / 2
        inside = (X >= x0) & (X <= x1) & (Y <= GLASS_BOTTOM) & ((Y >= ARCH_Y) | ((X - cx) ** 2 + (Y - ARCH_Y) ** 2 <= r * r))
        big |= inside
    return big.reshape(H, SS, W, SS).mean(axis=(1, 3))


cov = glass_coverage()
SHELF = rect(1028, 763, 1513, FLOOR)            # стеллаж: закрывает низ первого окна
CABINET = rect(1462, 812, 1621, FLOOR)          # тумба с ящиками: закрывает левый низ второго окна
cov[SHELF | CABINET] = 0.0
glass = cov > 0.5

# переплёт окна: тёмные тонкие линии поверх стекла (места измерены по картинке)
lum = 0.299 * R + 0.587 * G + 0.114 * B
mull = np.zeros((H, W), bool)
for y0, y1 in ((342, 348), (524, 531), (707, 713)):
    mull[y0:y1] = True
for x0, x1 in ((1322, 1328), (1666, 1672)):      # вертикали первого и второго окна
    mull[:, x0:x1] = True
mull &= cov > 0.01

# ------------------------------------------------------------------ мебель (ближний слой)
near = np.zeros((H, W), bool)
for r_ in [
    (44, 725, 185, 882),      # компьютер слева
    (183, 817, 256, 877),     # стопка бумаг
    (284, 726, 432, 876),     # монитор, вид сзади
    (414, 845, 456, 877),     # кружки
    (499, 924, 604, FLOOR),   # тёмный ящик и стопка под столом
    (529, 817, 633, 877),     # стопка бумаг
    (13, 874, 724, 926),      # столешница
    (745, 977, 848, FLOOR),   # стопка на полу
    (1619, 724, 1760, 882),   # компьютер справа
    (1756, 817, 1832, 877),   # стопка бумаг
    (1859, 726, W, 876),      # монитор справа, вид сзади
    (1554, 872, W, 908),      # столешница справа
    (1727, 931, 1830, FLOOR), # стопка под столом
    (1842, 906, W, FLOOR),    # тёмный ящик под столом
    (1803, 906, 1829, 934),   # ножка стола за стопкой
    (1513, 977, 1615, FLOOR), # стопка на полу перед тумбой
]:
    near |= rect(*r_)
# под левым столом: всё, что не яркая синяя стена, — мебель
under_l = rect(13, 924, 724, FLOOR)
wall_like = (R <= 30) & (B >= 100)
near |= under_l & ~wall_like
# под правым столом: чёрные ножки
under_r = rect(1554, 906, 1830, FLOOR)
neutral = (img.max(2) - img.min(2) <= 12) & (img.max(2) <= 70)
near |= under_r & ndimage.binary_dilation(neutral, iterations=1) & (R < 90)
near &= ~(rect(440, 845, 458, 877) & (R > 150) & (B < 200))    # розовая кофта кошки рядом с кружкой — не мебель
near &= yy < FLOOR

# ------------------------------------------------------------------ кошка за столом
cat_box = rect(436, 768, 524, 875)
sil = cat_box & (R > 125) & ~near
sil = ndimage.binary_fill_holes(ndimage.binary_closing(sil, iterations=2))
lab, n = ndimage.label(sil)
if n:
    sizes = ndimage.sum(sil, lab, range(1, n + 1))
    sil = lab == (1 + int(np.argmax(sizes)))
# вместе с кошкой берём усы (они тоньше и длиннее силуэта) и спинку стула за ней.
# Выше стула — только сама голова с узкой каймой: свечение вокруг неё остаётся на стене.
cat_zone = (ndimage.binary_dilation(sil, iterations=4) & rect(424, 768, 536, 875)) | rect(430, 806, 560, 875)
cat_zone &= ~near
# розовая строка там, где кофта касается столешницы, запеклась в мебель — возвращаем цвет стола
src_img = img.copy()                               # исходник без правок — по нему вырезается кошка
edge = rect(440, 874, 520, 877) & (R > G + 6)
for y_, x_ in zip(*np.where(edge)):
    img[y_, x_] = img[y_, 660]
near &= ~rect(452, 872, 520, 874)                  # выше столешницы здесь кошка, а не стол (кружка кончается на x=451)
cat_zone |= rect(450, 872, 512, 876)
R, G, B = img[:, :, 0], img[:, :, 1], img[:, :, 2]

# ------------------------------------------------------------------ средний слой: стены и шкафы
mid = img.copy()
unknown = ndimage.binary_dilation(near | cat_zone, iterations=2) & (yy < FLOOR)


def harmonic_fill(image, hole, source):
    """Заполняет hole плавным продолжением цвета из source (как натянутая плёнка)."""
    idx = -np.ones((H, W), int)
    ys, xs = np.where(hole)
    idx[ys, xs] = np.arange(len(ys))
    n_ = len(ys)
    rows, cols, vals = [], [], []
    rhs = np.zeros((n_, 3))
    diag = np.zeros(n_)
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        ny, nx = ys + dy, xs + dx
        ok = (ny >= 0) & (ny < H) & (nx >= 0) & (nx < W)
        nyc, nxc = np.clip(ny, 0, H - 1), np.clip(nx, 0, W - 1)
        is_hole = ok & hole[nyc, nxc]
        is_src = ok & source[nyc, nxc] & ~is_hole
        diag += is_hole + is_src
        k = np.where(is_hole)[0]
        rows += k.tolist()
        cols += idx[nyc[k], nxc[k]].tolist()
        vals += [-1.0] * len(k)
        k = np.where(is_src)[0]
        rhs[k] += image[nyc[k], nxc[k]]
    diag[diag == 0] = 1.0
    rows += list(range(n_))
    cols += list(range(n_))
    vals += diag.tolist()
    A = csr_matrix((vals, (rows, cols)), shape=(n_, n_))
    out = image.copy()
    for c in range(3):
        out[ys, xs, c] = spsolve(A, rhs[:, c])
    bad = hole & ~np.isfinite(out).all(axis=2)
    if bad.any():                                  # кусок без соседей-образцов: берём ближайший известный цвет
        out[bad] = 0
        _, (iy, ix) = ndimage.distance_transform_edt(hole | ~source, return_indices=True)
        out[bad] = image[iy[bad], ix[bad]]
    return out


# 1. слева: стена с плавным градиентом
left = unknown & (xx < 1000) & (yy < FLOOR - 1)
src_ok = ~unknown & (yy > 86) & (yy < FLOOR - 1) & (xx < 1010)
mid = harmonic_fill(mid, left, src_ok)
# строка у самого пола — переход стены в пол
k = unknown & (yy == FLOOR - 1) & (xx < 1000)
mid[k] = 0.42 * mid[np.where(k)[0] - 1, np.where(k)[1]] + 0.58 * np.array([2, 16, 17])

# 2. тумба: цвет плоский, с горизонтальными линиями ящиков — тянем строки слева
cab_hole = unknown & CABINET
for y, x in zip(*np.where(cab_hole)):
    xs_ = x
    while cab_hole[y, xs_] and xs_ > 1464:
        xs_ -= 1
    mid[y, x] = mid[y, xs_ - 1] if not cab_hole[y, xs_] else mid[y, 1470]

# 3. простенок между вторым и третьим окном: тянем цвет стены сверху вниз
pier = unknown & (cov < 0.01) & (xx >= 1795) & ~CABINET
src_ok = ~unknown & (cov < 0.01) & (xx >= 1795) & (yy > 86) & (yy < FLOOR - 1)
mid = harmonic_fill(mid, pier, src_ok)
# 4. стена справа от тумбы до окна, спрятанная за ножкой стола (если есть)
rest = unknown & (cov < 0.01) & ~left & ~cab_hole & ~pier & (yy < FLOOR)
if rest.any():
    src_ok = ~unknown & (cov < 0.01) & (yy > 86) & (yy < FLOOR - 1)
    mid = harmonic_fill(mid, rest, src_ok)

# 5. вертикаль переплёта за компьютером: продолжаем её вниз
hidden_mull = mull & unknown
for y, x in zip(*np.where(hidden_mull)):
    y0 = y
    while y0 > 300 and (unknown[y0, x] or not mull[y0, x]):
        y0 -= 1
    mid[y, x] = img[y0, x]

# прозрачность: стекло прозрачное, переплёт остаётся
alpha_mid = 1.0 - cov
alpha_mid[mull] = 1.0
# у края стекла цвет исходника смешан с городом — берём чистый цвет стены рядом
band = (cov > 0.0) & (cov < 1.0) & ~mull
ring = band
m8 = (ring | (cov > 0)).astype(np.uint8) * 255
m8[mull] = 0
wall_only = cv2.inpaint(cv2.cvtColor(mid.clip(0, 255).astype(np.uint8), cv2.COLOR_RGB2BGR), m8, 4, cv2.INPAINT_TELEA)
wall_only = cv2.cvtColor(wall_only, cv2.COLOR_BGR2RGB).astype(np.float64)
mid[ring & ~mull] = wall_only[ring & ~mull]

# ------------------------------------------------------------------ дальний слой: город за окном
far = img.copy()
visible = (cov > 0.999) & ~ndimage.binary_dilation(mull, iterations=1) & ~unknown
# 1. у краёв стекла, предметов и переплёта цвет смешан с соседом. Отступаем на 2 пикселя внутрь
#    и закрашиваем кромку и линии переплёта ближайшим чистым цветом.
core = ndimage.binary_erosion(visible, iterations=2)
dist, (iy, ix) = ndimage.distance_transform_edt(~core, return_indices=True)
patch = ~core & (dist <= 8.5) & (cov > 0.5)
far[patch] = img[iy[patch], ix[patch]]
far_k = core | patch

# 2. стекло, спрятанное за мебелью и шкафами: продолжаем полосы домов сверху с их шагом
col = lum[540:705, 1700] - ndimage.uniform_filter1d(lum[540:705, 1700], 40)
ac = [float((col[:-p] * col[p:]).mean()) for p in range(8, 40)]
P = 8 + int(np.argmax(ac))
print("шаг полос на домах:", P)
glass_full = glass_coverage() > 0.5              # стекло целиком, включая спрятанное
hidden = glass_full & ~far_k
for x in range(W):
    ys = np.where(hidden[:, x])[0]
    if len(ys) == 0:
        continue
    kn = far_k[:, x]
    for y in ys:
        y0 = y
        while y0 > 0 and not kn[y0]:
            y0 -= 1
        if y0 == 0:
            continue
        d = y - y0
        ysrc = y0 - ((P - d % P) % P)
        ysrc = ysrc if kn[max(ysrc, 0)] else y0
        far[y, x] = far[ysrc, x]
# за правым компьютером: слева виден синий дом, справа — полосатый. Продолжаем каждый по строке,
# тогда полосы за компьютером совпадают с видимыми рядом.
EDGE_X = 1646                                     # граница между синим и полосатым домом
for y in range(722, 818):
    for x in np.where(hidden[y, 1621:1760])[0] + 1621:
        far[y, x] = far[y, 1612] if x < EDGE_X else far[y, 1775]
for y in range(818, 893):                         # ниже видимых кусков нет — повторяем полосы с их шагом
    k = -(-(y - 817) // P)
    xs_h = np.where(hidden[y, 1621:1803])[0] + 1621
    far[y, xs_h] = far[y - k * P, xs_h]
# ниже столешницы под правым столом город виден кусками — продолжаем эти куски по строке
low = hidden & (yy >= 893) & (xx >= 1621) & (xx <= 1802)
for y in np.where(low.any(axis=1))[0]:
    xs_k = np.where(far_k[y] & (np.arange(W) >= 1621) & (np.arange(W) <= 1802))[0]
    if len(xs_k) == 0:
        continue
    for x in np.where(low[y])[0]:
        far[y, x] = far[y, xs_k[np.argmin(np.abs(xs_k - x))]]
far_k |= hidden

# 3. за стенами: в каждой строке тянем цвет от ближайшего края окна
inner = far_k
for y in range(H):
    xs_k = np.where(inner[y])[0]
    if len(xs_k) == 0:
        continue
    pos = np.searchsorted(xs_k, np.arange(W))
    lo = xs_k[np.clip(pos - 1, 0, len(xs_k) - 1)]
    hi = xs_k[np.clip(pos, 0, len(xs_k) - 1)]
    nearest = np.where(np.abs(np.arange(W) - lo) <= np.abs(hi - np.arange(W)), lo, hi)
    fill = ~far_k[y]
    far[y, fill] = far[y, nearest[fill]]
rows_ok = np.where(inner.any(axis=1))[0]
far[:rows_ok[0]] = far[rows_ok[0]]
far[rows_ok[-1] + 1:] = far[rows_ok[-1]]

# ------------------------------------------------------------------ кошка и её стул: часть ближнего слоя
under = mid.copy()
desk_part = cat_zone & near                        # там, где кошка заходит на край столешницы
under[desk_part] = img[desk_part]
diff = np.abs(src_img - under).max(axis=2)
a_cat = np.clip((diff - 5.0) / 26.0, 0, 1) * cat_zone
a_cat[sil] = np.maximum(a_cat[sil], np.clip((diff[sil] - 2.0) / 10.0, 0, 1))
a_cat[ndimage.binary_erosion(sil, iterations=2)] = 1.0
a_cat[a_cat < 0.02] = 0.0
ac_ = a_cat[:, :, None]
cat_rgb = ((src_img - (1 - ac_) * under) / np.maximum(ac_, 0.05)).clip(0, 255)

# ------------------------------------------------------------------ ближний слой
# мебель, а в просветах между ней — кошка со стулом (там, где кофта касается стола, кошка поверх)
na = near[:, :, None] * 1.0
out_a = ac_ + na * (1 - ac_)
near_rgb = np.where(out_a > 0, (cat_rgb * ac_ + img * na * (1 - ac_)) / np.maximum(out_a, 1e-6), img)
near_rgba = np.dstack([near_rgb, out_a[:, :, 0] * 255.0])
near_rgba[FLOOR:, :, :3] = img[FLOOR:]
near_rgba[FLOOR:, :, 3] = 255.0                  # пол целиком в ближнем слое


def save(name, arr):
    arr = arr.clip(0, 255).astype(np.uint8)
    code = cv2.COLOR_RGBA2BGRA if arr.shape[2] == 4 else cv2.COLOR_RGB2BGR
    cv2.imwrite(f"{OUT}/{name}", cv2.cvtColor(arr, code))


TOP, BOTTOM = 100, 1060                           # видимая часть картинки по высоте
save("far.png", far[TOP:BOTTOM])
save("mid.png", np.dstack([mid, alpha_mid * 255.0])[TOP:BOTTOM])
save("near.png", near_rgba[TOP:BOTTOM])

# ------------------------------------------------------------------ проверки
np.save(f"{OUT}/_masks.npy", np.stack([near, cat_zone, glass, mull]).astype(np.uint8))
full_far, full_mid, full_near = far, np.dstack([mid, alpha_mid]), near_rgba


def compose(shift_far=0, shift_near=0):
    out = np.roll(full_far, shift_far, axis=1).copy()
    a = full_mid[:, :, 3:4]
    out = out * (1 - a) + full_mid[:, :, :3] * a
    nr = np.roll(full_near, shift_near, axis=1)
    a = nr[:, :, 3:4] / 255.0
    return out * (1 - a) + nr[:, :, :3] * a


c0 = compose()
err = np.abs(c0 - src_img).max(axis=2)
print("сборка без сдвига против исходника: макс. разница %.1f, пикселей с разницей > 8: %d" % (err.max(), int((err > 8).sum())))
save("_check_same.png", c0)
save("_check_shift.png", compose(shift_far=90, shift_near=-32))
save("_check_shift_back.png", compose(shift_far=-90, shift_near=32))
save("_check_mid_on_pink.png", np.array([255, 0, 255.0]) * (1 - alpha_mid[:, :, None]) + mid * alpha_mid[:, :, None])
save("_check_near_on_pink.png", np.array([255, 0, 255.0]) * (1 - out_a) + near_rgb * out_a)
save("_check_err.png", np.dstack([err * 8] * 3))
