"""Перевод контура из точек в плавную кривую Безье с малым числом узлов (алгоритм Шнайдера).
Используется сборщиком make_fuki_34.py."""
import math
import numpy as np


def _bez(c, t):
    t = np.asarray(t)[:, None]
    return ((1 - t) ** 3) * c[0] + 3 * ((1 - t) ** 2) * t * c[1] + 3 * (1 - t) * (t ** 2) * c[2] + (t ** 3) * c[3]


def _bez_d1(c, t):
    t = np.asarray(t)[:, None]
    return 3 * ((1 - t) ** 2) * (c[1] - c[0]) + 6 * (1 - t) * t * (c[2] - c[1]) + 3 * (t ** 2) * (c[3] - c[2])


def _bez_d2(c, t):
    t = np.asarray(t)[:, None]
    return 6 * (1 - t) * (c[2] - 2 * c[1] + c[0]) + 6 * t * (c[3] - 2 * c[2] + c[1])


def _chord(pts):
    d = np.hypot(*(pts[1:] - pts[:-1]).T)
    u = np.concatenate([[0.0], np.cumsum(d)])
    return u / u[-1] if u[-1] > 0 else np.linspace(0, 1, len(pts))


def _gen(pts, u, t1, t2):
    p0, p3 = pts[0], pts[-1]
    b0 = (1 - u) ** 3
    b1 = 3 * u * (1 - u) ** 2
    b2 = 3 * u * u * (1 - u)
    b3 = u ** 3
    a1 = t1[None, :] * b1[:, None]
    a2 = t2[None, :] * b2[:, None]
    c00 = (a1 * a1).sum()
    c01 = (a1 * a2).sum()
    c11 = (a2 * a2).sum()
    tmp = pts - (p0[None, :] * (b0 + b1)[:, None] + p3[None, :] * (b2 + b3)[:, None])
    x0 = (a1 * tmp).sum()
    x1 = (a2 * tmp).sum()
    det = c00 * c11 - c01 * c01
    seg = np.hypot(*(p3 - p0))
    if abs(det) > 1e-12:
        al = (x0 * c11 - x1 * c01) / det
        ar = (c00 * x1 - c01 * x0) / det
    else:
        al = ar = 0.0
    eps = 1e-6 * seg
    if al < eps or ar < eps or al > 3 * seg or ar > 3 * seg:
        al = ar = seg / 3.0
    return np.array([p0, p0 + t1 * al, p3 + t2 * ar, p3])


def _err(pts, c, u):
    d = _bez(c, u) - pts
    e = (d * d).sum(1)
    i = int(np.argmax(e))
    return math.sqrt(e[i]), i


def _reparam(pts, c, u):
    d = _bez(c, u) - pts
    d1 = _bez_d1(c, u)
    d2 = _bez_d2(c, u)
    num = (d * d1).sum(1)
    den = (d1 * d1).sum(1) + (d * d2).sum(1)
    out = u.copy()
    ok = np.abs(den) > 1e-12
    out[ok] = u[ok] - num[ok] / den[ok]
    out = np.clip(out, 0, 1)
    out[0], out[-1] = 0.0, 1.0
    return np.maximum.accumulate(out)


def _unit(v):
    n = np.hypot(*v)
    return v / n if n > 1e-12 else np.array([1.0, 0.0])


def fit_open(pts, t1, t2, tol, depth=0):
    """Точки -> список кубических кривых (каждая 4 точки). t1, t2 — касательные на концах (внутрь отрезка)."""
    pts = np.asarray(pts, float)
    if len(pts) == 2:
        d = np.hypot(*(pts[1] - pts[0])) / 3.0
        return [np.array([pts[0], pts[0] + t1 * d, pts[1] + t2 * d, pts[1]])]
    u = _chord(pts)
    c = _gen(pts, u, t1, t2)
    e, i = _err(pts, c, u)
    if e <= tol:
        return [c]
    if e <= tol * 4:
        for _ in range(6):
            u = _reparam(pts, c, u)
            c = _gen(pts, u, t1, t2)
            e, i = _err(pts, c, u)
            if e <= tol:
                return [c]
    if depth > 12 or len(pts) < 4:
        return [c]
    i = min(max(i, 1), len(pts) - 2)
    k = max(1, min(3, i, len(pts) - 1 - i))
    tc = _unit(pts[i - k] - pts[i + k])
    return fit_open(pts[:i + 1], t1, tc, tol, depth + 1) + fit_open(pts[i:], -tc, t2, tol, depth + 1)


def resample(pts, step, closed=True):
    pts = np.asarray(pts, float)
    if closed and np.hypot(*(pts[0] - pts[-1])) > 1e-9:
        pts = np.vstack([pts, pts[0]])
    d = np.hypot(*(pts[1:] - pts[:-1]).T)
    s = np.concatenate([[0.0], np.cumsum(d)])
    n = max(8, int(round(s[-1] / step)))
    t = np.linspace(0, s[-1], n + 1)
    out = np.stack([np.interp(t, s, pts[:, 0]), np.interp(t, s, pts[:, 1])], 1)
    return out[:-1] if closed else out


def find_corners(p, win, corner_deg):
    """Номера точек замкнутого контура, где он резко ломается."""
    n = len(p)
    a = p[(np.arange(n) - win) % n]
    b = p[(np.arange(n) + win) % n]
    v1 = p - a
    v2 = b - p
    ang = np.abs(np.arctan2(v1[:, 0] * v2[:, 1] - v1[:, 1] * v2[:, 0], (v1 * v2).sum(1)))
    thr = math.radians(corner_deg)
    idx = []
    for i in range(n):
        if ang[i] < thr:
            continue
        nb = [(i + k) % n for k in range(-win, win + 1)]
        if ang[i] >= ang[nb].max() - 1e-12:
            if idx and (i - idx[-1]) <= win:
                if ang[i] > ang[idx[-1]]:
                    idx[-1] = i
            else:
                idx.append(i)
    if len(idx) > 1 and (idx[0] + n - idx[-1]) <= win:
        if ang[idx[0]] >= ang[idx[-1]]:
            idx.pop()
        else:
            idx.pop(0)
    return idx


def fit_closed(pts, tol=1.2, step=1.5, corner_deg=50.0, win=6):
    """Замкнутый контур -> список кубических кривых. Углы сохраняются, остальное сглаживается."""
    p = resample(pts, step, True)
    n = len(p)
    corners = find_corners(p, win, corner_deg)
    smooth = False
    if not corners:
        smooth = True
        corners = sorted(set([int(np.argmin(p[:, 0])), int(np.argmax(p[:, 0]))]))
        if len(corners) < 2:
            corners = [0, n // 2]
    segs = []
    m = len(corners)
    for k in range(m):
        i0 = corners[k]
        i1 = corners[(k + 1) % m]
        idx = [(i0 + j) % n for j in range(((i1 - i0) % n or n) + 1)]
        seg = p[idx]
        kk = max(1, min(win // 2 + 1, len(seg) - 1))
        if smooth:
            t1 = _unit(p[(i0 + kk) % n] - p[(i0 - kk) % n])
            t2 = _unit(p[(i1 - kk) % n] - p[(i1 + kk) % n])
        else:
            t1 = _unit(seg[kk] - seg[0])
            t2 = _unit(seg[-1 - kk] - seg[-1])
        segs += fit_open(seg, t1, t2, tol)
    return segs


def path_d(segs):
    f = lambda v: ("%.2f" % v).rstrip("0").rstrip(".") if "." in ("%.2f" % v) else "%.2f" % v
    d = "M%s,%s" % (f(segs[0][0][0]), f(segs[0][0][1]))
    for c in segs:
        d += "C" + " ".join("%s,%s" % (f(q[0]), f(q[1])) for q in c[1:])
    return d + "Z"


def flatten(segs, n=12):
    out = []
    t = np.linspace(0, 1, n + 1)[:-1]
    for c in segs:
        out.append(_bez(c, t))
    return np.vstack(out)
