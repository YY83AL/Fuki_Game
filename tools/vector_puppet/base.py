"""Общая основа сборщика: растр-образец, маски цветов, операции с масками, перевод в координаты листа."""
import os
import cv2, numpy as np
from scipy import ndimage as ndi
from skimage import measure

UP = 4                      # во сколько раз увеличен образец для работы с масками
CX, GY = 196.0, 693.0       # точка земли между стопами на вырезанном образце
S = 1500.0 / 656.0          # масштаб: рост 656 точек образца -> 1500 на листе

HERE = os.path.dirname(os.path.abspath(__file__))
crop = cv2.cvtColor(cv2.imread(os.path.join(HERE, 'ref34.png')), cv2.COLOR_BGR2RGB)   # образец: вид 3/4 с листа ракурсов
big = cv2.resize(crop, None, fx=UP, fy=UP, interpolation=cv2.INTER_CUBIC).astype(np.float32)
H, W = big.shape[:2]
R, G, B = big[..., 0], big[..., 1], big[..., 2]
YY, XX = np.mgrid[0:H, 0:W]
XC = (XX + 0.5) / UP - 0.5          # координаты образца для каждой точки увеличенной картинки
YC = (YY + 0.5) / UP - 0.5

BG = np.array([131, 160, 168.0])
DBG = np.abs(big - BG).sum(2)
RED = (R > 150) & (G < 110) & (B < 110)
CREAM = (R > 195) & (G > 195) & (B > 185)
DARK = (big.max(2) < 120) & (DBG > 60)


def erode(m, r):
    return ndi.distance_transform_edt(m) > r * UP


def dilate(m, r):
    return ndi.distance_transform_edt(~m) <= r * UP


def opening(m, r):
    return dilate(erode(m, r), r)


def closing(m, r):
    return erode(dilate(m, r), r)


def largest(m, k=1):
    lab, n = ndi.label(m)
    if n == 0:
        return [m] * k if k > 1 else m
    sizes = ndi.sum(m, lab, range(1, n + 1))
    order = np.argsort(-sizes)
    res = [lab == (order[i] + 1) for i in range(min(k, n))]
    return res if k > 1 else res[0]


def blank():
    return np.zeros((H, W), bool)


def u(p):
    """точка образца -> точка увеличенной картинки (для рисования cv2)"""
    return (int(round((p[0] + 0.5) * UP - 0.5)), int(round((p[1] + 0.5) * UP - 0.5)))


def disc(c, r):
    return (XC - c[0]) ** 2 + (YC - c[1]) ** 2 <= r * r


def ellipse(c, rx, ry, deg=0.0):
    a = np.radians(deg)
    dx, dy = XC - c[0], YC - c[1]
    x = dx * np.cos(a) + dy * np.sin(a)
    y = -dx * np.sin(a) + dy * np.cos(a)
    return (x / rx) ** 2 + (y / ry) ** 2 <= 1.0


def capsule(p0, p1, r0, r1=None):
    """вытянутая фигура с круглыми концами; радиус может меняться от r0 к r1"""
    r1 = r0 if r1 is None else r1
    p0 = np.array(p0, float); p1 = np.array(p1, float)
    d = p1 - p0
    L2 = (d * d).sum()
    t = np.clip(((XC - p0[0]) * d[0] + (YC - p0[1]) * d[1]) / L2, 0, 1)
    px = p0[0] + t * d[0]; py = p0[1] + t * d[1]
    rr = r0 + (r1 - r0) * t
    return (XC - px) ** 2 + (YC - py) ** 2 <= rr * rr


def poly(points):
    m = np.zeros((H, W), np.uint8)
    cv2.fillPoly(m, [np.array([u(p) for p in points], np.int32)], 1)
    return m.astype(bool)


def half(p0, p1):
    """полуплоскость слева от направления p0 -> p1 (на экране, где y вниз, это «по правую руку»)"""
    return (p1[0] - p0[0]) * (YC - p0[1]) - (p1[1] - p0[1]) * (XC - p0[0]) >= 0


def to_sheet(xc, yc):
    return 1000.0 + (xc - CX) * S, 1800.0 + (yc - GY) * S


def sheet_pt(p):
    x, y = to_sheet(p[0], p[1])
    return (round(x, 2), round(y, 2))


def contours(mask, sigma=1.5):
    """маска -> контуры в координатах листа, от большого к малому"""
    f = ndi.gaussian_filter(mask.astype(np.float32), sigma * UP / 4.0)
    out = []
    for c in measure.find_contours(f, 0.5):
        if len(c) < 12:
            continue
        xc = (c[:, 1] + 0.5) / UP - 0.5
        yc = (c[:, 0] + 0.5) / UP - 0.5
        x, y = to_sheet(xc, yc)
        pts = np.stack([x, y], 1)
        a = 0.5 * np.abs(np.dot(pts[:, 0], np.roll(pts[:, 1], 1)) - np.dot(pts[:, 1], np.roll(pts[:, 0], 1)))
        out.append((a, pts))
    out.sort(key=lambda t: -t[0])
    return [p for a, p in out]
