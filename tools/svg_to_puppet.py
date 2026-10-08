#!/usr/bin/env python3
"""svg_to_puppet.py — переводит SVG куклы (нарисованный по ТЗ) в сцену Godot.

Запуск:
    python3 tools/svg_to_puppet.py  вход.svg  выход.tscn

Что делает:
  * читает слои body / clothes / pivots и группы-части внутри них;
  * превращает кривые в многоугольники (Polygon2D) с плоской заливкой;
  * ставит каждую часть на её точку вращения (pivot_*), чтобы её можно было крутить;
  * рукав (sleeve_*) режет по локтю на две части и добавляет круг-сустав;
  * печатает отчёт: чего не хватает и что в файле нарушает ТЗ.

Нужен только обычный Python 3, без дополнительных библиотек.
"""
import math
import re
import sys
import xml.etree.ElementTree as ET

TOL = 0.15            # точность спрямления кривых, в единицах листа (лист 2000×2000)
CUT_MARGIN = 2.0      # на сколько половинки разрезанной части заходят друг на друга
EPS = 1e-9

LAYERS = ("body", "clothes", "pivots")

# имя части -> имя её точки вращения ({s} = near / far / left / right)
PIVOT_RULES = [
    (r"^arm_(?P<s>near|far|left|right)_upper$", "pivot_shoulder_{s}"),
    (r"^arm_(?P<s>near|far|left|right)_fore$", "pivot_elbow_{s}"),
    (r"^paw_(?P<s>near|far|left|right)$", "pivot_wrist_{s}"),
    (r"^leg_(?P<s>near|far|left|right)_thigh$", "pivot_hip_{s}"),
    (r"^leg_(?P<s>near|far|left|right)_shin$", "pivot_knee_{s}"),
    (r"^foot_(?P<s>near|far|left|right)$", "pivot_ankle_{s}"),
    (r"^ear_(?P<s>near|far|left|right)$", "pivot_ear_{s}"),
    (r"^eye_(?P<s>near|far|left|right)_(white|pupil)$", "pivot_eye_{s}"),
    (r"^eyelid_(?P<s>near|far|left|right)$", "pivot_eye_{s}"),
    (r"^brow_(?P<s>near|far|left|right)$", "pivot_eye_{s}"),
    (r"^whiskers_(?P<s>near|far|left|right)$", "pivot_head"),
    (r"^(head|nose|mouth)$", "pivot_head"),
    (r"^neck$", "pivot_neck"),
    (r"^torso$", "pivot_waist"),
    (r"^coat_body$", "pivot_neck"),
    (r"^sleeve_(?P<s>near|far|left|right)$", "pivot_shoulder_{s}"),
    (r"^boot_(?P<s>near|far|left|right)_shaft$", "pivot_knee_{s}"),
    (r"^boot_(?P<s>near|far|left|right)_foot$", "pivot_ankle_{s}"),
]

# части, которые игра сгибает сама: (шаблон имени, верхняя ось, ось сгиба, нижняя ось)
BEND_RULES = [
    (r"^sleeve_(?P<s>near|far|left|right)$", "pivot_shoulder_{s}", "pivot_elbow_{s}", "pivot_wrist_{s}"),
]

NAMED = {"black": "#000000", "white": "#ffffff", "red": "#ff0000", "magenta": "#ff00ff", "fuchsia": "#ff00ff"}


# ----------------------------------------------------------------- мелочи

def local(tag):
    return tag.split("}", 1)[-1]


def decode_id(s):
    """Illustrator при «Сохранить как SVG» пишет подчёркивание как _x5F_. Возвращаем как было."""
    return re.sub(r"_x([0-9A-Fa-f]{2})_", lambda m: chr(int(m.group(1), 16)), s or "")


def parse_color(s):
    """'#abc' / '#aabbcc' / 'rgb(1,2,3)' / имя -> (r, g, b) 0..1, либо None, либо 'unsupported'."""
    if s is None:
        return None
    s = s.strip().lower()
    if s in ("none", "transparent"):
        return None
    s = NAMED.get(s, s)
    m = re.match(r"^#([0-9a-f]{3})$", s)
    if m:
        return tuple(int(ch * 2, 16) / 255.0 for ch in m.group(1))
    m = re.match(r"^#([0-9a-f]{6})$", s)
    if m:
        h = m.group(1)
        return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))
    m = re.match(r"^rgb\(\s*(\d+)[\s,]+(\d+)[\s,]+(\d+)\s*\)$", s)
    if m:
        return tuple(int(v) / 255.0 for v in m.groups())
    return "unsupported"


# ----------------------------------------------------------------- матрицы

IDENT = (1.0, 0.0, 0.0, 1.0, 0.0, 0.0)


def mmul(m, n):
    a, b, c, d, e, f = m
    a2, b2, c2, d2, e2, f2 = n
    return (a * a2 + c * b2, b * a2 + d * b2, a * c2 + c * d2, b * c2 + d * d2,
            a * e2 + c * f2 + e, b * e2 + d * f2 + f)


def mapply(m, p):
    a, b, c, d, e, f = m
    return (a * p[0] + c * p[1] + e, b * p[0] + d * p[1] + f)


def parse_transform(s):
    m = IDENT
    for name, args in re.findall(r"(\w+)\s*\(([^)]*)\)", s or ""):
        v = [float(x) for x in re.findall(r"[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?", args)]
        if name == "matrix" and len(v) == 6:
            t = tuple(v)
        elif name == "translate":
            t = (1, 0, 0, 1, v[0], v[1] if len(v) > 1 else 0.0)
        elif name == "scale":
            t = (v[0], 0, 0, v[1] if len(v) > 1 else v[0], 0, 0)
        elif name == "rotate":
            a = math.radians(v[0])
            t = (math.cos(a), math.sin(a), -math.sin(a), math.cos(a), 0, 0)
            if len(v) == 3:
                t = mmul(mmul((1, 0, 0, 1, v[1], v[2]), t), (1, 0, 0, 1, -v[1], -v[2]))
        elif name == "skewX":
            t = (1, 0, math.tan(math.radians(v[0])), 1, 0, 0)
        elif name == "skewY":
            t = (1, math.tan(math.radians(v[0])), 0, 1, 0, 0)
        else:
            continue
        m = mmul(m, t)
    return m


# ----------------------------------------------------------------- кривые

def flat_cubic(p0, p1, p2, p3, out, depth=0):
    """Спрямляет кубическую кривую: делит пополам, пока она не станет ровной с точностью TOL."""
    dx, dy = p3[0] - p0[0], p3[1] - p0[1]
    d1 = abs((p1[0] - p3[0]) * dy - (p1[1] - p3[1]) * dx)
    d2 = abs((p2[0] - p3[0]) * dy - (p2[1] - p3[1]) * dx)
    ln = math.hypot(dx, dy)
    if ln < EPS:
        flat = max(math.hypot(p1[0] - p0[0], p1[1] - p0[1]), math.hypot(p2[0] - p0[0], p2[1] - p0[1])) <= TOL
    else:
        flat = (d1 + d2) <= TOL * ln
    if flat or depth > 14:
        out.append(p3)
        return
    p01 = ((p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2)
    p12 = ((p1[0] + p2[0]) / 2, (p1[1] + p2[1]) / 2)
    p23 = ((p2[0] + p3[0]) / 2, (p2[1] + p3[1]) / 2)
    a = ((p01[0] + p12[0]) / 2, (p01[1] + p12[1]) / 2)
    b = ((p12[0] + p23[0]) / 2, (p12[1] + p23[1]) / 2)
    m = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
    flat_cubic(p0, p01, a, m, out, depth + 1)
    flat_cubic(m, b, p23, p3, out, depth + 1)


def arc_to_points(p0, rx, ry, phi_deg, large, sweep, p1, out):
    """Дуга эллипса SVG (команда A) -> точки."""
    if rx == 0 or ry == 0:
        out.append(p1)
        return
    phi = math.radians(phi_deg)
    cp, sp = math.cos(phi), math.sin(phi)
    dx, dy = (p0[0] - p1[0]) / 2, (p0[1] - p1[1]) / 2
    x1 = cp * dx + sp * dy
    y1 = -sp * dx + cp * dy
    rx, ry = abs(rx), abs(ry)
    lam = x1 * x1 / (rx * rx) + y1 * y1 / (ry * ry)
    if lam > 1:
        k = math.sqrt(lam)
        rx, ry = rx * k, ry * k
    num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
    den = rx * rx * y1 * y1 + ry * ry * x1 * x1
    co = math.sqrt(max(0.0, num / den)) if den > EPS else 0.0
    if large == sweep:
        co = -co
    cxp, cyp = co * rx * y1 / ry, -co * ry * x1 / rx
    cx = cp * cxp - sp * cyp + (p0[0] + p1[0]) / 2
    cy = sp * cxp + cp * cyp + (p0[1] + p1[1]) / 2
    a0 = math.atan2((y1 - cyp) / ry, (x1 - cxp) / rx)
    a1 = math.atan2((-y1 - cyp) / ry, (-x1 - cxp) / rx)
    da = a1 - a0
    if sweep and da < 0:
        da += 2 * math.pi
    if not sweep and da > 0:
        da -= 2 * math.pi
    r = max(rx, ry)
    step = 2 * math.acos(max(-1.0, min(1.0, 1 - TOL / r))) if r > TOL else math.pi / 2
    n = max(2, int(math.ceil(abs(da) / max(step, 1e-3))))
    for i in range(1, n + 1):
        a = a0 + da * i / n
        x, y = rx * math.cos(a), ry * math.sin(a)
        out.append((cp * x - sp * y + cx, sp * x + cp * y + cy))
    out[-1] = p1


NUM = r"[-+]?(?:\d*\.\d+|\d+\.?)(?:[eE][-+]?\d+)?"


def parse_path(d):
    """Атрибут d -> список замкнутых контуров (каждый — список точек)."""
    subs, cur_pts = [], []
    pos = 0
    n = len(d)
    cmd = None
    cur = (0.0, 0.0)
    start = (0.0, 0.0)
    last_ctrl = None
    last_cmd = ""
    num_re = re.compile(r"\s*,?\s*(" + NUM + ")")
    flag_re = re.compile(r"\s*,?\s*([01])")

    def num():
        nonlocal pos
        m = num_re.match(d, pos)
        if not m:
            raise ValueError("ожидалось число в позиции %d" % pos)
        pos = m.end()
        return float(m.group(1))

    def flag():
        nonlocal pos
        m = flag_re.match(d, pos)
        if not m:
            raise ValueError("ожидался флаг дуги в позиции %d" % pos)
        pos = m.end()
        return int(m.group(1))

    def more():
        return num_re.match(d, pos) is not None

    def finish():
        nonlocal cur_pts
        if len(cur_pts) >= 3:
            subs.append(cur_pts)
        cur_pts = []

    while pos < n:
        m = re.compile(r"\s*([MmZzLlHhVvCcSsQqTtAa])").match(d, pos)
        if m:
            cmd = m.group(1)
            pos = m.end()
        elif cmd is None or not more():
            if d[pos:].strip() == "":
                break
            raise ValueError("непонятный символ в контуре: %r" % d[pos:pos + 12])
        rel = cmd.islower()
        c = cmd.upper()
        if c == "Z":
            finish()
            cur = start
            last_ctrl = None
            last_cmd = "Z"
            cmd = None
            continue
        if c == "M":
            x, y = num(), num()
            if rel:
                x, y = cur[0] + x, cur[1] + y
            finish()
            cur = start = (x, y)
            cur_pts = [cur]
            cmd = "l" if rel else "L"       # следующие пары — линии
            last_ctrl = None
            last_cmd = "M"
            continue
        if not cur_pts:
            cur_pts = [cur]
        if c == "L":
            x, y = num(), num()
            cur = (cur[0] + x, cur[1] + y) if rel else (x, y)
            cur_pts.append(cur)
        elif c == "H":
            x = num()
            cur = (cur[0] + x if rel else x, cur[1])
            cur_pts.append(cur)
        elif c == "V":
            y = num()
            cur = (cur[0], cur[1] + y if rel else y)
            cur_pts.append(cur)
        elif c in ("C", "S"):
            if c == "C":
                x1, y1 = num(), num()
                if rel:
                    x1, y1 = cur[0] + x1, cur[1] + y1
            else:
                if last_cmd in ("C", "S") and last_ctrl:
                    x1, y1 = 2 * cur[0] - last_ctrl[0], 2 * cur[1] - last_ctrl[1]
                else:
                    x1, y1 = cur
            x2, y2, x, y = num(), num(), num(), num()
            if rel:
                x2, y2, x, y = cur[0] + x2, cur[1] + y2, cur[0] + x, cur[1] + y
            flat_cubic(cur, (x1, y1), (x2, y2), (x, y), cur_pts)
            last_ctrl = (x2, y2)
            cur = (x, y)
        elif c in ("Q", "T"):
            if c == "Q":
                qx, qy = num(), num()
                if rel:
                    qx, qy = cur[0] + qx, cur[1] + qy
            else:
                if last_cmd in ("Q", "T") and last_ctrl:
                    qx, qy = 2 * cur[0] - last_ctrl[0], 2 * cur[1] - last_ctrl[1]
                else:
                    qx, qy = cur
            x, y = num(), num()
            if rel:
                x, y = cur[0] + x, cur[1] + y
            c1 = (cur[0] + 2 / 3 * (qx - cur[0]), cur[1] + 2 / 3 * (qy - cur[1]))
            c2 = (x + 2 / 3 * (qx - x), y + 2 / 3 * (qy - y))
            flat_cubic(cur, c1, c2, (x, y), cur_pts)
            last_ctrl = (qx, qy)
            cur = (x, y)
        elif c == "A":
            rx, ry, phi = num(), num(), num()
            large, sweep = flag(), flag()
            x, y = num(), num()
            if rel:
                x, y = cur[0] + x, cur[1] + y
            arc_to_points(cur, rx, ry, phi, large, sweep, (x, y), cur_pts)
            cur = (x, y)
        last_cmd = c
    finish()
    return subs


def ellipse_points(cx, cy, rx, ry):
    r = max(rx, ry)
    step = 2 * math.acos(max(-1.0, 1 - TOL / r)) if r > TOL else math.pi / 2
    n = max(8, 4 * int(math.ceil(2 * math.pi / step / 4)))
    return [(cx + rx * math.cos(2 * math.pi * i / n), cy + ry * math.sin(2 * math.pi * i / n)) for i in range(n)]


def rect_points(x, y, w, h, rx, ry):
    rx, ry = min(rx, w / 2), min(ry, h / 2)
    if rx <= 0 or ry <= 0:
        return [(x, y), (x + w, y), (x + w, y + h), (x, y + h)]
    pts = []
    corners = [(x + w - rx, y + ry, -90), (x + w - rx, y + h - ry, 0), (x + rx, y + h - ry, 90), (x + rx, y + ry, 180)]
    r = max(rx, ry)
    step = 2 * math.acos(max(-1.0, 1 - TOL / r)) if r > TOL else math.pi / 2
    n = max(2, int(math.ceil((math.pi / 2) / step)))
    for cx, cy, a0 in corners:
        for i in range(n + 1):
            a = math.radians(a0) + (math.pi / 2) * i / n
            pts.append((cx + rx * math.cos(a), cy + ry * math.sin(a)))
    return pts


# ----------------------------------------------------------------- геометрия многоугольников

def area(p):
    s = 0.0
    for i in range(len(p)):
        x0, y0 = p[i]
        x1, y1 = p[(i + 1) % len(p)]
        s += x0 * y1 - x1 * y0
    return s / 2


def clean(p):
    """Убирает повторяющиеся подряд точки."""
    out = []
    for q in p:
        if not out or math.hypot(q[0] - out[-1][0], q[1] - out[-1][1]) > 1e-4:
            out.append(q)
    while len(out) > 1 and math.hypot(out[0][0] - out[-1][0], out[0][1] - out[-1][1]) <= 1e-4:
        out.pop()
    return out


def inside(pt, poly):
    x, y = pt
    c = False
    for i in range(len(poly)):
        x0, y0 = poly[i]
        x1, y1 = poly[(i + 1) % len(poly)]
        if (y0 > y) != (y1 > y) and x < (x1 - x0) * (y - y0) / (y1 - y0) + x0:
            c = not c
    return c


def cross(a, b, c):
    return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])


def seg_hit(a, b, c, d):
    """Пересекаются ли отрезки ab и cd во внутренних точках."""
    d1, d2 = cross(a, b, c), cross(a, b, d)
    d3, d4 = cross(c, d, a), cross(c, d, b)
    return (d1 * d2 < -EPS) and (d3 * d4 < -EPS)


def triangulate(outer, holes):
    """Контур с отверстиями -> (точки, треугольники). Отверстия пришиваются к контуру мостиками,
    потом отрезаются «уши». Нужен только для составных контуров (кольцо, буква О)."""
    if area(outer) < 0:
        outer = outer[::-1]
    holes = [h if area(h) < 0 else h[::-1] for h in holes]
    verts = list(outer)
    ring = list(range(len(outer)))
    pending = []
    for h in holes:
        base = len(verts)
        verts.extend(h)
        pending.append(list(range(base, base + len(h))))
    pending.sort(key=lambda r: -max(verts[i][0] for i in r))
    while pending:
        h = pending.pop(0)
        j = max(range(len(h)), key=lambda k: verts[h[k]][0])
        M = verts[h[j]]
        best, best_d = None, 1e30
        for i, vi in enumerate(ring):
            P = verts[vi]
            dist = (P[0] - M[0]) ** 2 + (P[1] - M[1]) ** 2
            if dist >= best_d:
                continue
            blocked = False
            for r in [ring, h] + pending:
                for k in range(len(r)):
                    if seg_hit(M, P, verts[r[k]], verts[r[(k + 1) % len(r)]]):
                        blocked = True
                        break
                if blocked:
                    break
            if not blocked:
                best, best_d = i, dist
        if best is None:
            best = 0
        ring = ring[:best + 1] + h[j:] + h[:j + 1] + ring[best:]
    tris = []
    guard = 0
    while len(ring) > 3 and guard < 20000:
        guard += 1
        n = len(ring)
        done = False
        for i in range(n):
            a, b, c = ring[i - 1], ring[i], ring[(i + 1) % n]
            A, B, C = verts[a], verts[b], verts[c]
            if cross(A, B, C) <= 1e-9:
                continue
            ok = True
            for k in ring:
                if k in (a, b, c):
                    continue
                P = verts[k]
                if P == A or P == B or P == C:
                    continue
                if cross(A, B, P) >= -1e-9 and cross(B, C, P) >= -1e-9 and cross(C, A, P) >= -1e-9:
                    ok = False
                    break
            if ok:
                tris.append((a, b, c))
                del ring[i]
                done = True
                break
        if not done:
            i = min(range(n), key=lambda k: abs(cross(verts[ring[k - 1]], verts[ring[k]], verts[ring[(k + 1) % n]])))
            del ring[i]
    if len(ring) == 3:
        tris.append(tuple(ring))
    return verts, tris


def clip_half(poly, origin, normal, keep_positive, margin=0.0):
    """Отрезает многоугольник прямой, проходящей через origin с нормалью normal.
    margin — запас: половинка заходит за линию разреза, чтобы на стыке не было волосяной щели."""
    def side(p):
        v = (p[0] - origin[0]) * normal[0] + (p[1] - origin[1]) * normal[1]
        return (v if keep_positive else -v) + margin
    out = []
    for i in range(len(poly)):
        a, b = poly[i], poly[(i + 1) % len(poly)]
        sa, sb = side(a), side(b)
        if sa >= 0:
            out.append(a)
        if (sa >= 0) != (sb >= 0):
            t = sa / (sa - sb)
            out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    return clean(out)


def cut_span(poly, origin, normal):
    """Где контур пересекает прямую разреза: (минимум, максимум) вдоль прямой или None."""
    tx, ty = -normal[1], normal[0]
    hits = []
    for i in range(len(poly)):
        a, b = poly[i], poly[(i + 1) % len(poly)]
        sa = (a[0] - origin[0]) * normal[0] + (a[1] - origin[1]) * normal[1]
        sb = (b[0] - origin[0]) * normal[0] + (b[1] - origin[1]) * normal[1]
        if (sa >= 0) != (sb >= 0):
            t = sa / (sa - sb)
            x, y = a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t
            hits.append((x - origin[0]) * tx + (y - origin[1]) * ty)
    if len(hits) < 2:
        return None
    return min(hits), max(hits), len(hits)


# ----------------------------------------------------------------- чтение SVG

class Shape:
    def __init__(self, color, outer, holes):
        self.color, self.outer, self.holes = color, outer, holes


class Reader:
    def __init__(self):
        self.css = {}
        self.parts = []          # [(имя, слой, [Shape])] в порядке файла
        self.pivots = {}
        self.notes = []          # замечания для отчёта
        self.seen_notes = set()

    def note(self, text):
        if text not in self.seen_notes:
            self.seen_notes.add(text)
            self.notes.append(text)

    def read(self, path):
        root = ET.parse(path).getroot()
        for st in root.iter():
            if local(st.tag) == "style" and st.text:
                for sel, body in re.findall(r"([^{}]+)\{([^}]*)\}", st.text):
                    props = dict((k.strip(), v.strip()) for k, v in re.findall(r"([\w-]+)\s*:\s*([^;]+)", body))
                    for s in sel.split(","):
                        s = s.strip()
                        if s.startswith("."):
                            self.css.setdefault(s[1:], {}).update(props)
        vb = [float(v) for v in re.findall(NUM, root.get("viewBox", ""))]
        self.viewbox = vb if len(vb) == 4 else None
        self.walk(root, IDENT, {"fill": "#000000"}, None, None, 0)
        return self

    def style_of(self, el, inherited):
        st = dict(inherited)
        for cls in (el.get("class") or "").split():
            st.update(self.css.get(cls, {}))
        for k in ("fill", "stroke", "opacity", "fill-opacity", "fill-rule", "display", "visibility"):
            if el.get(k) is not None:
                st[k] = el.get(k)
        for k, v in re.findall(r"([\w-]+)\s*:\s*([^;]+)", el.get("style") or ""):
            st[k.strip()] = v.strip()
        return st

    def walk(self, el, ctm, style, layer, part, depth):
        tag = local(el.tag)
        if tag in ("defs", "style", "title", "desc", "metadata", "clipPath", "mask", "linearGradient", "radialGradient", "pattern", "symbol"):
            if tag in ("clipPath", "mask"):
                self.note("В файле есть маска или обтравочный контур (%s): игра их не читает." % tag)
            if tag in ("linearGradient", "radialGradient", "pattern"):
                self.note("В файле есть градиент или узор: заливка должна быть одним цветом.")
            return
        name = decode_id(el.get("id"))
        style = self.style_of(el, style)
        if el.get("transform"):
            ctm = mmul(ctm, parse_transform(el.get("transform")))
        if el.get("clip-path") or el.get("mask"):
            self.note("Часть «%s» обрезана маской: игра покажет её целиком." % (part[0] if part else name or tag))
        if tag in ("svg", "g"):
            if tag == "g" and layer is None and name.split("__")[0] in LAYERS:
                layer = name
            elif tag == "g" and layer is not None and part is None and name and layer.split("__")[0] != "pivots":
                part = (name, layer, [])
                self.parts.append(part)
            for ch in el:
                self.walk(ch, ctm, style, layer, part, depth + 1)
            return
        if tag in ("image", "text", "use", "foreignObject"):
            self.note({"image": "В файле есть вставленная растровая картинка: игра её не читает.",
                       "text": "В файле есть живой текст: его нужно перевести в кривые.",
                       "use": "В файле есть символ (use): его нужно разобрать в обычные контуры.",
                       "foreignObject": "В файле есть посторонний объект (foreignObject)."}[tag])
            return
        subs = self.geometry(el, tag)
        if subs is None:
            return
        subs = [clean([mapply(ctm, p) for p in s]) for s in subs]
        subs = [s for s in subs if len(s) >= 3 and abs(area(s)) > 1e-3]
        if not subs:
            return
        # точка вращения: кружок с именем pivot_*
        if name.startswith("pivot_") or (layer and layer.split("__")[0] == "pivots"):
            xs = [p[0] for s in subs for p in s]
            ys = [p[1] for s in subs for p in s]
            if not name.startswith("pivot_"):
                self.note("В слое pivots есть фигура без имени pivot_…: она пропущена.")
                return
            if name in self.pivots:
                self.note("Точка «%s» встречается дважды." % name)
            if tag in ("circle", "ellipse"):          # у кружка центр известен точно
                self.pivots[name] = mapply(ctm, (float(el.get("cx") or 0), float(el.get("cy") or 0)))
            else:
                self.pivots[name] = ((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2)
            return
        if layer is None:
            self.note("Есть фигуры вне слоёв body / clothes / pivots: они пропущены.")
            return
        if part is None:                     # одиночная фигура прямо в слое — тоже часть, если у неё есть имя
            if not name:
                self.note("В слое «%s» есть фигура без группы и без имени: она пропущена." % layer)
                return
            part = (name, layer, [])
            self.parts.append(part)
        if style.get("display") == "none" or style.get("visibility") == "hidden":
            pass                              # скрытые варианты тоже берём
        stroke = style.get("stroke")
        if stroke and stroke.strip().lower() != "none":
            self.note("В части «%s» есть обводка: её нужно разобрать в фигуру (Outline Stroke)." % part[0])
        for k in ("opacity", "fill-opacity"):
            if style.get(k) not in (None, "1", "1.0"):
                self.note("В части «%s» есть прозрачность: заливка должна быть непрозрачной." % part[0])
        fill = style.get("fill", "#000000")
        if fill.strip().lower().startswith("url("):
            self.note("В части «%s» заливка градиентом или узором: нужен один цвет." % part[0])
            return
        col = parse_color(fill)
        if col is None:
            return
        if col == "unsupported":
            self.note("В части «%s» непонятный цвет «%s»." % (part[0], fill))
            return
        # составной контур: чётная вложенность = внешний контур, нечётная = отверстие
        order = sorted(range(len(subs)), key=lambda i: -abs(area(subs[i])))
        outers = []
        for i in order:
            s = subs[i]
            depth_in = sum(1 for j in order if j != i and abs(area(subs[j])) > abs(area(s)) and inside(s[0], subs[j]))
            if depth_in % 2 == 0:
                outers.append([s, []])
            else:
                host = None
                for o in outers:
                    if inside(s[0], o[0]):
                        host = o
                if host:
                    host[1].append(s)
        for outer, holes in outers:
            part[2].append(Shape(col, outer, holes))

    def geometry(self, el, tag):
        def f(k, default=0.0):
            v = el.get(k)
            if v is None:
                return default
            m = re.match(NUM, v.strip())
            return float(m.group(0)) if m else default
        try:
            if tag == "path":
                return parse_path(el.get("d") or "")
            if tag == "rect":
                rx, ry = el.get("rx"), el.get("ry")
                rxv = f("rx") if rx is not None else (f("ry") if ry is not None else 0.0)
                ryv = f("ry") if ry is not None else rxv
                return [rect_points(f("x"), f("y"), f("width"), f("height"), rxv, ryv)]
            if tag == "circle":
                return [ellipse_points(f("cx"), f("cy"), f("r"), f("r"))]
            if tag == "ellipse":
                return [ellipse_points(f("cx"), f("cy"), f("rx"), f("ry"))]
            if tag in ("polygon", "polyline"):
                v = [float(x) for x in re.findall(NUM, el.get("points") or "")]
                return [list(zip(v[0::2], v[1::2]))]
            if tag == "line":
                self.note("В файле есть линия без толщины-фигуры (line): её нужно разобрать в фигуру.")
                return None
        except ValueError as e:
            self.note("Не удалось прочитать контур: %s" % e)
        return None


# ----------------------------------------------------------------- сборка сцены

def match_rule(rules, name):
    for rule in rules:
        m = re.match(rule[0], name)
        if m:
            side = m.groupdict().get("s") or ""
            return tuple(r.format(s=side) for r in rule[1:])
    return None


def num(v):
    s = "%.2f" % v
    s = s.rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def build(reader, out_path):
    notes = reader.notes
    pivots = reader.pivots
    ground = pivots.get("pivot_ground", (0.0, 0.0))
    nodes = []          # (имя, слой, позиция, [Shape], данные сгиба или None)
    used_pivots = set()
    names_seen = set()
    for name, layer, shapes in reader.parts:
        if name in names_seen:
            notes.append("Имя части «%s» встречается дважды." % name)
        names_seen.add(name)
        if not shapes:
            notes.append("Часть «%s» пустая." % name)
            continue
        base = name.split("__")[0]
        rule = match_rule(PIVOT_RULES, base)
        if rule is None:
            notes.append("Имя «%s» не из списка ТЗ: часть добавлена без точки вращения." % name)
        pv_name = rule[0] if rule else None
        bend = match_rule(BEND_RULES, base)
        if bend and all(p in pivots for p in bend):
            top, mid, low = (pivots[p] for p in bend)
            used_pivots.update(bend)
            ax = (low[0] - top[0], low[1] - top[1])
            ln = math.hypot(*ax) or 1.0
            ax = (ax[0] / ln, ax[1] / ln)
            biggest = max(shapes, key=lambda s: abs(area(s.outer)))
            span = cut_span(biggest.outer, mid, ax)
            up, down, spans = [], [], []
            disc = None           # круг-сустав: закрывает щель с наружной стороны сгиба
            tx, ty = -ax[1], ax[0]
            if span:
                lo, hi, hits = span
                if hits > 2:
                    notes.append("Часть «%s» пересекает линию сгиба больше двух раз: сгиб может выглядеть неровно." % name)
                c = (mid[0] + tx * (lo + hi) / 2, mid[1] + ty * (lo + hi) / 2)
                disc = Shape(biggest.color, ellipse_points(c[0], c[1], (hi - lo) / 2, (hi - lo) / 2), [])
            for s in shapes:
                if s.holes:
                    side = (s.outer[0][0] - mid[0]) * ax[0] + (s.outer[0][1] - mid[1]) * ax[1]
                    (down if side > 0 else up).append(s)
                    continue
                a = clip_half(s.outer, mid, ax, False, CUT_MARGIN)
                b = clip_half(s.outer, mid, ax, True, CUT_MARGIN)
                if len(a) >= 3 and abs(area(a)) > 0.5:
                    up.append(Shape(s.color, a, []))
                if s is biggest and disc:
                    up.append(disc)   # сразу над основой и под деталями, иначе круг закроет шов
                if len(b) >= 3 and abs(area(b)) > 0.5:
                    down.append(Shape(s.color, b, []))
                # деталь, которая проходит через сгиб (шов, полоса): при сгибе между её половинками
                # появляется разрыв. Запоминаем, где она пересекает линию сгиба, — игра дорисует дугу.
                if s is not biggest:
                    sp = cut_span(s.outer, mid, ax)
                    if sp:
                        d_lo, d_hi = sp[0], sp[1]
                        pieces = [(d_lo, d_hi)] if d_lo * d_hi >= 0 else [(d_lo, 0.0), (0.0, d_hi)]
                        for q_lo, q_hi in pieces:
                            spans += [q_lo, q_hi, s.color[0], s.color[1], s.color[2]]
            nodes.append((name + "_upper", layer, top, up, None))
            nodes.append((name + "_fore", layer, mid, down, {"tangent": (tx, ty), "spans": spans}))
            continue
        if bend:
            notes.append("Часть «%s» должна сгибаться, но не хватает точек %s." % (name, ", ".join(p for p in bend if p not in pivots)))
        if pv_name and pv_name in pivots:
            used_pivots.add(pv_name)
            nodes.append((name, layer, pivots[pv_name], shapes, None))
        else:
            if pv_name:
                notes.append("Для части «%s» нет точки вращения «%s»." % (name, pv_name))
            nodes.append((name, layer, ground, shapes, None))

    L = ["[gd_scene format=3]", "", '[node name="Parts" type="Node2D"]']
    total_pts = 0
    for name, layer, pos, shapes, bend_info in nodes:
        L += ["", '[node name="%s" type="Node2D" parent="."]' % name,
              "position = Vector2(%s, %s)" % (num(pos[0] - ground[0]), num(pos[1] - ground[1])),
              'metadata/layer = "%s"' % layer]
        if bend_info:
            L.append("metadata/bend_tangent = Vector2(%.5f, %.5f)" % bend_info["tangent"])
            L.append("metadata/bend_spans = PackedFloat32Array(%s)" % ", ".join("%.4f" % v for v in bend_info["spans"]))
        if "__" in name:
            L.append("visible = false")
        for i, s in enumerate(shapes):
            if s.holes:
                verts, tris = triangulate(s.outer, s.holes)
            else:
                verts, tris = s.outer, None
            total_pts += len(verts)
            flat = ", ".join("%s, %s" % (num(p[0] - pos[0]), num(p[1] - pos[1])) for p in verts)
            L += ["", '[node name="s%d" type="Polygon2D" parent="%s"]' % (i, name),
                  "color = Color(%.4f, %.4f, %.4f, 1)" % s.color,
                  "polygon = PackedVector2Array(%s)" % flat]
            if tris:
                L.append("polygons = [%s]" % ", ".join("PackedInt32Array(%d, %d, %d)" % t for t in tris))
                L.append("metadata/rings = PackedInt32Array(%s)" % ", ".join(str(len(r)) for r in [s.outer] + s.holes))
    L += ["", '[node name="pivots" type="Node2D" parent="."]', "visible = false"]
    for pname in sorted(pivots):
        p = pivots[pname]
        L += ["", '[node name="%s" type="Marker2D" parent="pivots"]' % pname,
              "position = Vector2(%s, %s)" % (num(p[0] - ground[0]), num(p[1] - ground[1]))]
    open(out_path, "w", encoding="utf-8").write("\n".join(L) + "\n")

    for pname in sorted(pivots):
        if pname not in used_pivots and pname != "pivot_ground":
            notes.append("Точка «%s» есть, но части для неё нет." % pname)
    print("Готово: %s" % out_path)
    print("Частей: %d, точек вращения: %d, вершин всего: %d" % (len(nodes), len(pivots), total_pts))
    for name, layer, pos, shapes, _bend in nodes:
        print("  %-22s слой %-8s фигур %d" % (name, layer, len(shapes)))
    if notes:
        print("\nЗамечания (%d):" % len(notes))
        for t in notes:
            print("  - " + t)
    else:
        print("\nЗамечаний нет.")
    return len(notes)


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        return 2
    reader = Reader().read(sys.argv[1])
    build(reader, sys.argv[2])
    return 0


if __name__ == "__main__":
    sys.exit(main())
