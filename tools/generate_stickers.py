#!/usr/bin/env python3
"""MiLens 贴纸生成脚本。

基于 Quiet Archive 美术风格规范，生成首批 12 款高清透明 PNG 贴纸（1024x1024，sRGB，RGBA），
并生成对应的 manifest（sticker.json）存入 assets_src/stickers/ 目录供 frame_import.py 导入。
"""

from __future__ import annotations

import json
import math
from pathlib import Path
from PIL import Image, ImageDraw

REPO_ROOT = Path(__file__).resolve().parent.parent
OUTPUT_BASE = REPO_ROOT / "assets_src" / "stickers"

# 色彩定义（Quiet Archive 调性）
BRAND_CORAL = (253, 134, 99, 255)       # #FD8663
ACTION_PRIMARY = (188, 71, 39, 255)     # #BC4727 深铜红
ACCENT_SOFT = (252, 232, 223, 255)      # #FCE8DF
EDITORIAL_INK = (31, 27, 24, 255)       # #1F1B18
WARM_GOLD = (220, 140, 75, 255)         # 暖铜金
SOFT_WHITE = (250, 248, 245, 255)       # 纸白
SAGE_GREEN = (108, 148, 120, 255)       # 鼠尾草绿


def create_canvas(scale=2, size=1024) -> tuple[Image.Image, ImageDraw.ImageDraw, int]:
    """创建超采样画布（默认 2x 即 2048x2048），返回 (img, draw, actual_size)"""
    dim = size * scale
    img = Image.new("RGBA", (dim, dim), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    return img, draw, dim


def finalize_image(img: Image.Image, target_size=1024) -> Image.Image:
    """降采样抗锯齿到 target_size，并返回平滑图像"""
    return img.resize((target_size, target_size), Image.Resampling.LANCZOS)


# --------------------------------------------------------------------------- #
# 几何绘制辅助函数
# --------------------------------------------------------------------------- #

def draw_star(draw: ImageDraw.ImageDraw, cx: float, cy: float, r_out: float, r_in: float, points: int, fill, outline=None, width=1):
    """绘制 N 芒星"""
    coords = []
    angle_step = math.pi / points
    for i in range(2 * points):
        r = r_out if i % 2 == 0 else r_in
        angle = i * angle_step - math.pi / 2
        x = cx + r * math.cos(angle)
        y = cy + r * math.sin(angle)
        coords.append((x, y))
    draw.polygon(coords, fill=fill, outline=outline, width=width)


def draw_paw_print(draw: ImageDraw.ImageDraw, cx: float, cy: float, size: float, color: tuple, angle=0.0):
    """在指定位置绘制单枚爪印（主肉垫 + 4 颗指垫），支持旋转"""
    pad_w = int(size * 1.5)
    pad_h = int(size * 1.5)
    temp = Image.new("RGBA", (pad_w, pad_h), (0, 0, 0, 0))
    tdraw = ImageDraw.Draw(temp)
    
    tcx, tcy = pad_w / 2, pad_h / 2
    
    # 主肉垫（略带心形/倒梯形圆角的大肉垫）
    mw = size * 0.55
    mh = size * 0.45
    tdraw.ellipse([tcx - mw*0.65, tcy - mh*0.2, tcx + mw*0.65, tcy + mh*0.9], fill=color)
    tdraw.ellipse([tcx - mw*0.6, tcy - mh*0.6, tcx - mw*0.05, tcy + mh*0.2], fill=color)
    tdraw.ellipse([tcx + mw*0.05, tcy - mh*0.6, tcx + mw*0.6, tcy + mh*0.2], fill=color)
    tdraw.ellipse([tcx - mw*0.35, tcy - mh*0.4, tcx + mw*0.35, tcy + mh*0.5], fill=color)

    # 4 颗趾垫（呈弧形分布）
    toe_r_x = size * 0.16
    toe_r_y = size * 0.22
    toe_dist = size * 0.58
    toe_angles = [-55, -20, 20, 55]  # 度
    
    for i, a_deg in enumerate(toe_angles):
        a_rad = math.radians(a_deg - 90)
        tx = tcx + toe_dist * math.cos(a_rad)
        ty = tcy + toe_dist * math.sin(a_rad)
        scale_f = 0.88 if i in (0, 3) else 1.0
        rx = toe_r_x * scale_f
        ry = toe_r_y * scale_f
        tdraw.ellipse([tx - rx, ty - ry, tx + rx, ty + ry], fill=color)

    if angle != 0:
        temp = temp.rotate(angle, resample=Image.Resampling.BICUBIC, center=(tcx, tcy))

    # 绘制到主画布
    draw._image.paste(temp, (int(cx - pad_w/2), int(cy - pad_h/2)), temp)


# --------------------------------------------------------------------------- #
# 12 款贴纸具体绘制实现
# --------------------------------------------------------------------------- #

def gen_sun_paw() -> Image.Image:
    """1. sticker_sun_paw: 暖阳爪印 (推荐组，免费)"""
    img, draw, S = create_canvas()
    cx, cy = S / 2, S / 2
    
    rays = 16
    r_inner = S * 0.30
    r_outer_long = S * 0.44
    r_outer_short = S * 0.37
    
    for i in range(rays):
        angle = i * (2 * math.pi / rays)
        is_long = (i % 2 == 0)
        r_out = r_outer_long if is_long else r_outer_short
        color = ACTION_PRIMARY if is_long else BRAND_CORAL
        w = int(S * 0.016 if is_long else S * 0.010)
        
        x1 = cx + r_inner * math.cos(angle)
        y1 = cy + r_inner * math.sin(angle)
        x2 = cx + r_out * math.cos(angle)
        y2 = cy + r_out * math.sin(angle)
        draw.line([(x1, y1), (x2, y2)], fill=color, width=w)
        
        if is_long:
            dot_r = S * 0.014
            dot_x = cx + (r_out + S*0.02) * math.cos(angle)
            dot_y = cy + (r_out + S*0.02) * math.sin(angle)
            draw.ellipse([dot_x - dot_r, dot_y - dot_r, dot_x + dot_r, dot_y + dot_r], fill=ACTION_PRIMARY)

    draw.ellipse([cx - S*0.29, cy - S*0.29, cx + S*0.29, cy + S*0.29], 
                 outline=ACCENT_SOFT, width=int(S*0.015))
    draw_paw_print(draw, cx, cy + S*0.01, size=S*0.36, color=ACTION_PRIMARY)
    
    return finalize_image(img)


def gen_paw_mark() -> Image.Image:
    """2. sticker_paw_mark: 档案足印 (爪印组，免费)"""
    img, draw, S = create_canvas()
    cx, cy = S / 2, S / 2
    
    draw.ellipse([cx - S*0.42, cy - S*0.42, cx + S*0.42, cy + S*0.42], outline=ACTION_PRIMARY, width=int(S*0.022))
    draw.ellipse([cx - S*0.37, cy - S*0.37, cx + S*0.37, cy + S*0.37], outline=BRAND_CORAL, width=int(S*0.008))
    
    for a_deg in [0, 90, 180, 270]:
        a = math.radians(a_deg)
        x1 = cx + S*0.37 * math.cos(a)
        y1 = cy + S*0.37 * math.sin(a)
        x2 = cx + S*0.42 * math.cos(a)
        y2 = cy + S*0.42 * math.sin(a)
        draw.line([(x1, y1), (x2, y2)], fill=ACTION_PRIMARY, width=int(S*0.012))

    for a_deg in [45, 135, 225, 315]:
        a = math.radians(a_deg)
        px = cx + S*0.395 * math.cos(a)
        py = cy + S*0.395 * math.sin(a)
        draw_star(draw, px, py, r_out=S*0.016, r_in=S*0.007, points=4, fill=ACTION_PRIMARY)

    draw_paw_print(draw, cx, cy, size=S*0.42, color=ACTION_PRIMARY)

    return finalize_image(img)


def gen_tandem_paws() -> Image.Image:
    """3. sticker_tandem_paws: 步步相伴 (爪印组，免费)"""
    img, draw, S = create_canvas()
    cx, cy = S / 2, S / 2
    
    draw_paw_print(draw, cx - S*0.16, cy + S*0.12, size=S*0.38, color=ACTION_PRIMARY, angle=-18)
    draw_paw_print(draw, cx + S*0.18, cy - S*0.14, size=S*0.30, color=BRAND_CORAL, angle=20)
    
    draw_star(draw, cx + S*0.36, cy + S*0.25, r_out=S*0.030, r_in=S*0.012, points=4, fill=ACTION_PRIMARY)
    draw_star(draw, cx - S*0.32, cy - S*0.22, r_out=S*0.024, r_in=S*0.010, points=4, fill=BRAND_CORAL)
    draw_star(draw, cx + S*0.02, cy - S*0.35, r_out=S*0.018, r_in=S*0.008, points=4, fill=WARM_GOLD)

    return finalize_image(img)


def gen_warm_heart() -> Image.Image:
    """4. sticker_warm_heart: 温存心痕 (日常组，免费)"""
    img, draw, S = create_canvas()
    cx, cy = S / 2, S / 2
    
    def get_heart_points(center_x, center_y, scale):
        pts = []
        for t_step in range(120):
            t = t_step * (2 * math.pi / 120)
            x = 16 * (math.sin(t) ** 3)
            y = -(13 * math.cos(t) - 5 * math.cos(2*t) - 2 * math.cos(3*t) - math.cos(4*t))
            pts.append((center_x + x * scale, center_y + y * scale + scale * 2))
        return pts

    outer_pts = get_heart_points(cx, cy - S*0.02, scale=S*0.023)
    draw.polygon(outer_pts, outline=ACTION_PRIMARY, width=int(S*0.024))
    
    inner_pts = get_heart_points(cx, cy - S*0.02, scale=S*0.019)
    draw.polygon(inner_pts, fill=ACCENT_SOFT, outline=BRAND_CORAL, width=int(S*0.008))
    
    draw_paw_print(draw, cx, cy + S*0.01, size=S*0.22, color=ACTION_PRIMARY)
    draw_star(draw, cx + S*0.32, cy - S*0.28, r_out=S*0.04, r_in=S*0.016, points=4, fill=BRAND_CORAL)

    return finalize_image(img)


def gen_bloom_flower() -> Image.Image:
    """5. sticker_bloom_flower: 春日花期 (日常组，免费)"""
    img, draw, S = create_canvas()
    cx, cy = S / 2, S / 2
    
    leaf_color = SAGE_GREEN
    draw.chord([cx - S*0.44, cy - S*0.08, cx - S*0.18, cy + S*0.18], start=120, end=300, fill=leaf_color, outline=EDITORIAL_INK, width=int(S*0.008))
    draw.chord([cx + S*0.18, cy - S*0.18, cx + S*0.44, cy + S*0.08], start=300, end=120, fill=leaf_color, outline=EDITORIAL_INK, width=int(S*0.008))
    
    petals = 5
    petal_r = S * 0.17
    dist = S * 0.18
    for i in range(petals):
        angle = i * (2 * math.pi / petals) - math.pi / 2
        px = cx + dist * math.cos(angle)
        py = cy + dist * math.sin(angle)
        draw.ellipse([px - petal_r, py - petal_r, px + petal_r, py + petal_r], 
                     fill=ACCENT_SOFT, outline=ACTION_PRIMARY, width=int(S*0.018))
        draw.line([(cx + S*0.06*math.cos(angle), cy + S*0.06*math.sin(angle)), (px, py)], fill=BRAND_CORAL, width=int(S*0.008))

    core_r = S * 0.13
    draw.ellipse([cx - core_r, cy - core_r, cx + core_r, cy + core_r], fill=ACTION_PRIMARY)
    draw.ellipse([cx - core_r*0.5, cy - core_r*0.5, cx + core_r*0.5, cy + core_r*0.5], fill=WARM_GOLD)

    return finalize_image(img)


def gen_retro_camera() -> Image.Image:
    """6. sticker_retro_camera: 定格镜头 (日常组，免费)"""
    img, draw, S = create_canvas()
    cx, cy = S / 2, S / 2 + S * 0.04
    
    body_w = S * 0.72
    body_h = S * 0.48
    bx0, by0 = cx - body_w/2, cy - body_h/2
    bx1, by1 = cx + body_w/2, cy + body_h/2
    
    draw.rounded_rectangle([bx0, by0, bx1, by1], radius=int(S*0.06), fill=ACCENT_SOFT, outline=EDITORIAL_INK, width=int(S*0.02))
    
    draw.rectangle([bx0 + S*0.10, by0 - S*0.05, bx0 + S*0.22, by0], fill=WARM_GOLD, outline=EDITORIAL_INK, width=int(S*0.016))
    draw.rectangle([bx1 - S*0.24, by0 - S*0.07, bx1 - S*0.14, by0], fill=ACTION_PRIMARY, outline=EDITORIAL_INK, width=int(S*0.016))
    draw.rounded_rectangle([bx1 - S*0.22, by0 + S*0.06, bx1 - S*0.08, by0 + S*0.15], radius=int(S*0.02), fill=BRAND_CORAL, outline=EDITORIAL_INK, width=int(S*0.012))

    draw.rectangle([bx0 + S*0.01, cy - S*0.08, bx1 - S*0.01, cy + S*0.16], fill=ACTION_PRIMARY)

    lens_r1 = S * 0.19
    lens_r2 = S * 0.14
    lens_r3 = S * 0.08
    draw.ellipse([cx - lens_r1, cy - lens_r1, cx + lens_r1, cy + lens_r1], fill=SOFT_WHITE, outline=EDITORIAL_INK, width=int(S*0.02))
    draw.ellipse([cx - lens_r2, cy - lens_r2, cx + lens_r2, cy + lens_r2], fill=EDITORIAL_INK)
    draw.ellipse([cx - lens_r3, cy - lens_r3, cx + lens_r3, cy + lens_r3], fill=BRAND_CORAL)
    draw.ellipse([cx + S*0.03, cy - S*0.07, cx + S*0.07, cy - S*0.03], fill=SOFT_WHITE)

    draw_star(draw, cx - S*0.28, cy - S*0.34, r_out=S*0.05, r_in=S*0.02, points=4, fill=ACTION_PRIMARY)
    draw_star(draw, cx + S*0.30, cy - S*0.30, r_out=S*0.036, r_in=S*0.014, points=4, fill=BRAND_CORAL)

    return finalize_image(img)


def gen_food_bowl() -> Image.Image:
    """7. sticker_food_bowl: 满满食光 (日常组，免费)"""
    img, draw, S = create_canvas()
    cx, cy = S / 2, S / 2 + S * 0.06
    
    steam_y = cy - S*0.28
    for ox in [-S*0.16, 0, S*0.16]:
        draw.arc([cx + ox - S*0.08, steam_y - S*0.12, cx + ox + S*0.08, steam_y + S*0.08], start=220, end=340, fill=BRAND_CORAL, width=int(S*0.014))
        draw.arc([cx + ox - S*0.08, steam_y - S*0.20, cx + ox + S*0.08, steam_y], start=40, end=160, fill=ACTION_PRIMARY, width=int(S*0.014))

    bw, bh = S * 0.70, S * 0.36
    bowl_poly = [
        (cx - bw*0.40, cy - bh*0.2),
        (cx + bw*0.40, cy - bh*0.2),
        (cx + bw*0.48, cy + bh*0.6),
        (cx - bw*0.48, cy + bh*0.6),
    ]
    draw.polygon(bowl_poly, fill=ACCENT_SOFT, outline=ACTION_PRIMARY, width=int(S*0.02))
    draw.rounded_rectangle([cx - bw*0.42, cy + bh*0.56, cx + bw*0.42, cy + bh*0.68], radius=int(S*0.03), fill=ACTION_PRIMARY)

    draw.ellipse([cx - bw*0.42, cy - bh*0.35, cx + bw*0.42, cy - bh*0.05], fill=WARM_GOLD, outline=ACTION_PRIMARY, width=int(S*0.018))
    draw.ellipse([cx - bw*0.36, cy - bh*0.30, cx + bw*0.36, cy - bh*0.10], fill=ACTION_PRIMARY)

    fx, fy = cx, cy + bh*0.22
    draw.ellipse([fx - S*0.10, fy - S*0.05, fx + S*0.06, fy + S*0.05], fill=BRAND_CORAL)
    draw.polygon([(fx + S*0.04, fy), (fx + S*0.12, fy - S*0.06), (fx + S*0.12, fy + S*0.06)], fill=BRAND_CORAL)
    draw.ellipse([fx - S*0.07, fy - S*0.025, fx - S*0.04, fy + S*0.005], fill=SOFT_WHITE)

    return finalize_image(img)


def gen_sleepy_moon() -> Image.Image:
    """8. sticker_sleepy_moon: 甜梦月影 (日常组，免费)"""
    img, draw, S = create_canvas()
    cx, cy = S / 2, S / 2
    
    moon_img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    mdraw = ImageDraw.Draw(moon_img)
    
    mr_out = S * 0.38
    mdraw.ellipse([cx - mr_out, cy - mr_out, cx + mr_out, cy + mr_out], fill=WARM_GOLD)
    
    mr_in = S * 0.34
    in_cx, in_cy = cx + S*0.15, cy - S*0.06
    mdraw.ellipse([in_cx - mr_in, in_cy - mr_in, in_cx + mr_in, in_cy + mr_in], fill=(0, 0, 0, 0))
    
    img.paste(moon_img, (0, 0), moon_img)

    draw.arc([cx - mr_out, cy - mr_out, cx + mr_out, cy + mr_out], start=70, end=270, fill=ACTION_PRIMARY, width=int(S*0.02))

    draw.arc([cx - S*0.15, cy - S*0.08, cx - S*0.03, cy + S*0.04], start=20, end=160, fill=ACTION_PRIMARY, width=int(S*0.016))
    draw_paw_print(draw, cx - S*0.14, cy + S*0.12, size=S*0.22, color=ACTION_PRIMARY, angle=25)

    draw_star(draw, cx + S*0.16, cy - S*0.35, r_out=S*0.045, r_in=S*0.018, points=4, fill=BRAND_CORAL)
    draw_star(draw, cx + S*0.30, cy + S*0.10, r_out=S*0.032, r_in=S*0.012, points=4, fill=ACTION_PRIMARY)
    draw_star(draw, cx + S*0.12, cy + S*0.32, r_out=S*0.024, r_in=S*0.010, points=4, fill=WARM_GOLD)

    return finalize_image(img)


def gen_radiant_star() -> Image.Image:
    """9. sticker_radiant_star: 守护微光 (纪念组，Pro 专属)"""
    img, draw, S = create_canvas()
    cx, cy = S / 2, S / 2
    
    draw.ellipse([cx - S*0.32, cy - S*0.32, cx + S*0.32, cy + S*0.32], outline=ACCENT_SOFT, width=int(S*0.012))
    draw.ellipse([cx - S*0.20, cy - S*0.20, cx + S*0.20, cy + S*0.20], outline=BRAND_CORAL, width=int(S*0.008))

    draw_star(draw, cx, cy, r_out=S*0.34, r_in=S*0.08, points=4, fill=BRAND_CORAL)
    
    r_main = S * 0.46
    r_base = S * 0.09
    
    for i, a_deg in enumerate([0, 90, 180, 270]):
        a = math.radians(a_deg - 90)
        a_left = a - math.pi/4
        a_right = a + math.pi/4
        
        tip_x = cx + r_main * math.cos(a)
        tip_y = cy + r_main * math.sin(a)
        left_x = cx + r_base * math.cos(a_left)
        left_y = cy + r_base * math.sin(a_left)
        right_x = cx + r_base * math.cos(a_right)
        right_y = cy + r_base * math.sin(a_right)
        
        draw.polygon([(cx, cy), (left_x, left_y), (tip_x, tip_y)], fill=ACTION_PRIMARY)
        draw.polygon([(cx, cy), (tip_x, tip_y), (right_x, right_y)], fill=WARM_GOLD)

    draw.ellipse([cx - S*0.05, cy - S*0.05, cx + S*0.05, cy + S*0.05], fill=SOFT_WHITE, outline=ACTION_PRIMARY, width=int(S*0.008))
    draw.ellipse([cx - S*0.02, cy - S*0.02, cx + S*0.02, cy + S*0.02], fill=ACTION_PRIMARY)

    for a_deg in [45, 135, 225, 315]:
        a = math.radians(a_deg)
        px = cx + S*0.38 * math.cos(a)
        py = cy + S*0.38 * math.sin(a)
        draw_star(draw, px, py, r_out=S*0.025, r_in=S*0.010, points=4, fill=ACTION_PRIMARY)

    return finalize_image(img)


def gen_archive_seal() -> Image.Image:
    """10. sticker_archive_seal: 珍藏火漆印 (纪念组，Pro 专属)"""
    img, draw, S = create_canvas()
    cx, cy = S / 2, S / 2
    
    num_blobs = 18
    seal_pts = []
    for i in range(num_blobs):
        a = i * (2 * math.pi / num_blobs)
        r_var = S * 0.42 + (math.sin(i * 3.5) * S * 0.025)
        seal_pts.append((cx + r_var * math.cos(a), cy + r_var * math.sin(a)))
    
    draw.polygon(seal_pts, fill=ACTION_PRIMARY)
    
    draw.ellipse([cx - S*0.36, cy - S*0.36, cx + S*0.36, cy + S*0.36], outline=WARM_GOLD, width=int(S*0.014))
    draw.ellipse([cx - S*0.32, cy - S*0.32, cx + S*0.32, cy + S*0.32], outline=WARM_GOLD, width=int(S*0.008))
    
    beads = 24
    for i in range(beads):
        a = i * (2 * math.pi / beads)
        bx = cx + S*0.34 * math.cos(a)
        by = cy + S*0.34 * math.sin(a)
        draw.ellipse([bx - S*0.007, by - S*0.007, bx + S*0.007, by + S*0.007], fill=SOFT_WHITE)

    draw_paw_print(draw, cx, cy - S*0.02, size=S*0.34, color=WARM_GOLD)
    
    draw.line([(cx - S*0.22, cy + S*0.22), (cx + S*0.22, cy + S*0.22)], fill=WARM_GOLD, width=int(S*0.010))
    draw_star(draw, cx, cy + S*0.22, r_out=S*0.024, r_in=S*0.010, points=4, fill=SOFT_WHITE)
    draw_star(draw, cx - S*0.14, cy + S*0.22, r_out=S*0.014, r_in=S*0.006, points=4, fill=SOFT_WHITE)
    draw_star(draw, cx + S*0.14, cy + S*0.22, r_out=S*0.014, r_in=S*0.006, points=4, fill=SOFT_WHITE)

    return finalize_image(img)


def gen_adoption_ribbon() -> Image.Image:
    """11. sticker_adoption_ribbon: 家人丝带 (纪念组，Pro 专属)"""
    img, draw, S = create_canvas()
    cx, cy = S / 2, S / 2 - S * 0.04
    
    left_tail = [
        (cx - S*0.06, cy + S*0.05),
        (cx - S*0.26, cy + S*0.44),
        (cx - S*0.18, cy + S*0.38),
        (cx - S*0.10, cy + S*0.44),
        (cx - S*0.02, cy + S*0.08),
    ]
    draw.polygon(left_tail, fill=ACTION_PRIMARY, outline=EDITORIAL_INK, width=int(S*0.012))
    
    right_tail = [
        (cx + S*0.02, cy + S*0.08),
        (cx + S*0.10, cy + S*0.44),
        (cx + S*0.18, cy + S*0.38),
        (cx + S*0.26, cy + S*0.44),
        (cx + S*0.06, cy + S*0.05),
    ]
    draw.polygon(right_tail, fill=ACTION_PRIMARY, outline=EDITORIAL_INK, width=int(S*0.012))

    draw.ellipse([cx - S*0.38, cy - S*0.22, cx, cy + S*0.08], fill=BRAND_CORAL, outline=ACTION_PRIMARY, width=int(S*0.018))
    draw.ellipse([cx - S*0.28, cy - S*0.14, cx - S*0.08, cy + S*0.02], fill=ACCENT_SOFT)
    draw.ellipse([cx, cy - S*0.22, cx + S*0.38, cy + S*0.08], fill=BRAND_CORAL, outline=ACTION_PRIMARY, width=int(S*0.018))
    draw.ellipse([cx + S*0.08, cy - S*0.14, cx + S*0.28, cy + S*0.02], fill=ACCENT_SOFT)

    knot_r = S * 0.10
    draw.ellipse([cx - knot_r, cy - knot_r, cx + knot_r, cy + knot_r], fill=WARM_GOLD, outline=ACTION_PRIMARY, width=int(S*0.016))
    draw_paw_print(draw, cx, cy, size=S*0.14, color=ACTION_PRIMARY)

    draw_star(draw, cx + S*0.32, cy - S*0.26, r_out=S*0.038, r_in=S*0.015, points=4, fill=WARM_GOLD)

    return finalize_image(img)


def gen_birthday_cake() -> Image.Image:
    """12. sticker_birthday_cake: 诞辰烛光 (纪念组，Pro 专属)"""
    img, draw, S = create_canvas()
    cx, cy = S / 2, S / 2 + S * 0.08
    
    candle_w = S * 0.05
    candle_h = S * 0.22
    candle_x0, candle_y0 = cx - candle_w/2, cy - S*0.42
    candle_x1, candle_y1 = cx + candle_w/2, cy - S*0.20
    
    draw.rectangle([candle_x0, candle_y0, candle_x1, candle_y1], fill=SOFT_WHITE, outline=ACTION_PRIMARY, width=int(S*0.010))
    for s_idx in range(4):
        sy = candle_y0 + s_idx * (candle_h / 4)
        draw.line([(candle_x0, sy), (candle_x1, sy + S*0.02)], fill=ACTION_PRIMARY, width=int(S*0.008))

    draw.line([(cx, candle_y0), (cx, candle_y0 - S*0.03)], fill=EDITORIAL_INK, width=int(S*0.008))
    draw.ellipse([cx - S*0.06, candle_y0 - S*0.14, cx + S*0.06, candle_y0 - S*0.02], fill=BRAND_CORAL)
    draw.ellipse([cx - S*0.035, candle_y0 - S*0.12, cx + S*0.035, candle_y0 - S*0.03], fill=WARM_GOLD)
    draw_star(draw, cx, candle_y0 - S*0.08, r_out=S*0.06, r_in=S*0.02, points=4, fill=SOFT_WHITE)

    cake_w = S * 0.60
    cake_h = S * 0.26
    
    draw.ellipse([cx - cake_w*0.56, cy + cake_h*0.40, cx + cake_w*0.56, cy + cake_h*0.75], fill=WARM_GOLD, outline=ACTION_PRIMARY, width=int(S*0.016))
    draw.rectangle([cx - cake_w/2, cy - cake_h*0.2, cx + cake_w/2, cy + cake_h*0.5], fill=ACCENT_SOFT, outline=ACTION_PRIMARY, width=int(S*0.018))
    draw.ellipse([cx - cake_w/2, cy - cake_h*0.4, cx + cake_w/2, cy], fill=SOFT_WHITE, outline=ACTION_PRIMARY, width=int(S*0.018))
    
    scallops = 7
    sc_w = cake_w / scallops
    for i in range(scallops):
        sx0 = cx - cake_w/2 + i * sc_w
        sx1 = sx0 + sc_w
        draw.chord([sx0, cy - cake_h*0.08, sx1, cy + cake_h*0.08], start=0, end=180, fill=ACTION_PRIMARY)

    draw_paw_print(draw, cx, cy + cake_h*0.25, size=S*0.18, color=ACTION_PRIMARY)

    return finalize_image(img)


# --------------------------------------------------------------------------- #
# 素材元数据定义与导出组织
# --------------------------------------------------------------------------- #

STICKERS_SPEC = [
    {
        "id": "sticker_sun_paw",
        "name": "decoration.sticker.sunPaw",
        "category": "sticker",
        "fit_mode": "stretch",
        "is_premium": False,
        "group": "recommended",
        "sort_order": 10,
        "generator": gen_sun_paw,
    },
    {
        "id": "sticker_paw_mark",
        "name": "decoration.sticker.pawMark",
        "category": "sticker",
        "fit_mode": "stretch",
        "is_premium": False,
        "group": "paw",
        "sort_order": 20,
        "generator": gen_paw_mark,
    },
    {
        "id": "sticker_tandem_paws",
        "name": "decoration.sticker.tandemPaws",
        "category": "sticker",
        "fit_mode": "stretch",
        "is_premium": False,
        "group": "paw",
        "sort_order": 21,
        "generator": gen_tandem_paws,
    },
    {
        "id": "sticker_warm_heart",
        "name": "decoration.sticker.warmHeart",
        "category": "sticker",
        "fit_mode": "stretch",
        "is_premium": False,
        "group": "daily",
        "sort_order": 30,
        "generator": gen_warm_heart,
    },
    {
        "id": "sticker_bloom_flower",
        "name": "decoration.sticker.bloomFlower",
        "category": "sticker",
        "fit_mode": "stretch",
        "is_premium": False,
        "group": "daily",
        "sort_order": 31,
        "generator": gen_bloom_flower,
    },
    {
        "id": "sticker_retro_camera",
        "name": "decoration.sticker.retroCamera",
        "category": "sticker",
        "fit_mode": "stretch",
        "is_premium": False,
        "group": "daily",
        "sort_order": 32,
        "generator": gen_retro_camera,
    },
    {
        "id": "sticker_food_bowl",
        "name": "decoration.sticker.foodBowl",
        "category": "sticker",
        "fit_mode": "stretch",
        "is_premium": False,
        "group": "daily",
        "sort_order": 33,
        "generator": gen_food_bowl,
    },
    {
        "id": "sticker_sleepy_moon",
        "name": "decoration.sticker.sleepyMoon",
        "category": "sticker",
        "fit_mode": "stretch",
        "is_premium": False,
        "group": "daily",
        "sort_order": 34,
        "generator": gen_sleepy_moon,
    },
    {
        "id": "sticker_radiant_star",
        "name": "decoration.sticker.radiantStar",
        "category": "sticker",
        "fit_mode": "stretch",
        "is_premium": True,
        "group": "memorial",
        "sort_order": 40,
        "generator": gen_radiant_star,
    },
    {
        "id": "sticker_archive_seal",
        "name": "decoration.sticker.archiveSeal",
        "category": "sticker",
        "fit_mode": "stretch",
        "is_premium": True,
        "group": "memorial",
        "sort_order": 41,
        "generator": gen_archive_seal,
    },
    {
        "id": "sticker_adoption_ribbon",
        "name": "decoration.sticker.adoptionRibbon",
        "category": "sticker",
        "fit_mode": "stretch",
        "is_premium": True,
        "group": "memorial",
        "sort_order": 42,
        "generator": gen_adoption_ribbon,
    },
    {
        "id": "sticker_birthday_cake",
        "name": "decoration.sticker.birthdayCake",
        "category": "sticker",
        "fit_mode": "stretch",
        "is_premium": True,
        "group": "memorial",
        "sort_order": 43,
        "generator": gen_birthday_cake,
    },
]


def main():
    print(f"开始生成 MiLens 12 款 Quiet Archive 风格贴纸素材...")
    OUTPUT_BASE.mkdir(parents=True, exist_ok=True)
    
    for spec in STICKERS_SPEC:
        item_id = spec["id"]
        dir_path = OUTPUT_BASE / item_id
        dir_path.mkdir(parents=True, exist_ok=True)
        
        # 1. 生成 PNG 图像
        png_path = dir_path / f"{item_id}.png"
        print(f"  [生成] {item_id} -> {png_path.name}")
        img = spec["generator"]()
        img.save(png_path, "PNG", optimize=True)
        
        # 2. 生成 sticker.json manifest
        manifest = {
            "id": spec["id"],
            "name": spec["name"],
            "category": spec["category"],
            "fit_mode": spec["fit_mode"],
            "is_premium": spec["is_premium"],
            "group": spec["group"],
            "sort_order": spec["sort_order"],
            "native_aspect_ratio": 1.0,
        }
        manifest_path = dir_path / "sticker.json"
        with manifest_path.open("w", encoding="utf-8") as f:
            json.dump(manifest, f, indent=2, ensure_ascii=False)
            f.write("\n")

    print(f"\n全部 12 款贴纸素材生成完毕！目标路径: {OUTPUT_BASE}")


if __name__ == "__main__":
    main()
