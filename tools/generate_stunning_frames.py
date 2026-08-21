#!/usr/bin/env python3
"""MiLens 【时令与纪念·时光档案馆】绝美艺术相框（Seasons & Keepsakes Edition）渲染引擎。

打造兼具极高艺术美感、情绪价值与精致细节的 6 款惊艳相框：
1. 春樱之约 · 繁花漫境 (frame_spring_blossom)
2. 夏夜萤火 · 星海微芒 (frame_summer_firefly)
3. 秋暮银杏 · 琥珀暖阳 (frame_autumn_ginkgo)
4. 冬雪初晴 · 晶璨雪松 (frame_winter_frost)
5. 诞辰星愿 · 岁岁常欢 (frame_birthday_starlight)
6. 记忆星河 · 彩虹彼岸 (frame_eternal_rainbow)

输出 1200x1600 超高清透明相框及搭配真实宠物照片的绝美实机效果图。
"""

from __future__ import annotations

import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import numpy as np

REPO_ROOT = Path(__file__).resolve().parent.parent
BRAIN_DIR = Path(r"C:\Users\altai\.gemini\antigravity\brain\b492f7ab-360b-4a32-b7c5-a134c71fba2a")
OUTPUT_DIR = BRAIN_DIR / "stunning_frames"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

W, H = 1200, 1600


# --------------------------------------------------------------------------- #
# 基础几何与光效渲染器
# --------------------------------------------------------------------------- #

def get_fonts():
    try:
        font_serif_lg = ImageFont.truetype("georgia.ttf", 32)
        font_serif_md = ImageFont.truetype("georgia.ttf", 22)
        font_script_lg = ImageFont.truetype("pala.ttf", 36)
        font_sans = ImageFont.truetype("msyh.ttc", 22)
    except Exception:
        font_serif_lg = font_serif_md = font_script_lg = font_sans = ImageFont.load_default()
    return font_serif_lg, font_serif_md, font_script_lg, font_sans


def draw_glow_star(draw: ImageDraw.ImageDraw, cx: float, cy: float, size: float, color: tuple, glow_color: tuple = None):
    """绘制发光星芒"""
    if glow_color:
        gr = size * 1.8
        draw.ellipse([cx - gr, cy - gr, cx + gr, cy + gr], fill=glow_color)
    for ang in [0, 45, 90, 135]:
        r = math.radians(ang)
        draw.line([(cx - size*math.cos(r), cy - size*math.sin(r)), (cx + size*math.cos(r), cy + size*math.sin(r))], fill=color, width=max(1, int(size*0.12)))


def draw_floating_petal(draw: ImageDraw.ImageDraw, cx: float, cy: float, rx: float, ry: float, angle_deg: float, fill_color: tuple, outline_color: tuple = None):
    """绘制飘落的樱花/花瓣"""
    temp = Image.new("RGBA", (int(rx*3), int(ry*3)), (0, 0, 0, 0))
    tdraw = ImageDraw.Draw(temp)
    tcx, tcy = rx*1.5, ry*1.5
    # 心形/水滴花瓣
    pts = [
        (tcx, tcy - ry),
        (tcx + rx*0.8, tcy - ry*0.3),
        (tcx + rx*0.9, tcy + ry*0.4),
        (tcx + rx*0.3, tcy + ry*0.85),
        (tcx, tcy + ry),
        (tcx - rx*0.3, tcy + ry*0.85),
        (tcx - rx*0.9, tcy + ry*0.4),
        (tcx - rx*0.8, tcy - ry*0.3),
    ]
    tdraw.polygon(pts, fill=fill_color, outline=outline_color, width=1)
    temp = temp.rotate(angle_deg, resample=Image.Resampling.BICUBIC)
    draw._image.paste(temp, (int(cx - rx*1.5), int(cy - ry*1.5)), temp)


def draw_ginkgo_leaf(draw: ImageDraw.ImageDraw, cx: float, cy: float, size: float, angle_deg: float, fill_color: tuple, vein_color: tuple):
    """绘制扇形银杏叶片"""
    temp = Image.new("RGBA", (int(size*2.5), int(size*2.5)), (0, 0, 0, 0))
    tdraw = ImageDraw.Draw(temp)
    tcx, tcy = size*1.25, size*1.25
    
    # 银杏叶扇形轮廓
    leaf_pts = [(tcx, tcy + size*0.7)] # 叶柄根部
    num_pts = 16
    for i in range(num_pts + 1):
        t = i / float(num_pts)
        ang = math.radians(200 + t * 140)
        # 中央微凹
        r = size * (0.95 - 0.25 * math.sin(t * math.pi))
        px = tcx + r * math.cos(ang)
        py = tcy + r * math.sin(ang)
        leaf_pts.append((px, py))
        
    tdraw.polygon(leaf_pts, fill=fill_color, outline=vein_color, width=1)
    # 叶柄
    tdraw.line([(tcx, tcy + size*0.7), (tcx + size*0.1, tcy + size*1.1)], fill=vein_color, width=2)
    # 辐射叶脉
    for i in range(1, num_pts, 3):
        t = i / float(num_pts)
        ang = math.radians(200 + t * 140)
        r = size * 0.85
        tdraw.line([(tcx, tcy + size*0.7), (tcx + r * math.cos(ang), tcy + r * math.sin(ang))], fill=vein_color, width=1)

    temp = temp.rotate(angle_deg, resample=Image.Resampling.BICUBIC)
    draw._image.paste(temp, (int(cx - size*1.25), int(cy - size*1.25)), temp)


# --------------------------------------------------------------------------- #
# 6 款绝美相框渲染函数
# --------------------------------------------------------------------------- #

def gen_spring_blossom() -> Image.Image:
    """1. 春樱之约 · 繁花漫境 (frame_spring_blossom)"""
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)
    
    win_x0, win_y0 = 90, 100
    win_x1, win_y1 = W - 90, H - 100
    
    # 1. 柔美温润的春日双重细线 (暖珊瑚 + 浅香槟金)
    draw.rectangle([win_x0, win_y0, win_x1, win_y1], outline=(253, 160, 150, 200), width=2)
    draw.rectangle([win_x0 - 10, win_y0 - 10, win_x1 + 10, win_y1 + 10], outline=(235, 195, 130, 160), width=1)
    
    # 2. 四角与边缘蔓延的浪漫樱花枝桠与花簇
    # 左上与右上樱花簇
    for corner_x, corner_y, flip_x, flip_y in [(win_x0 - 10, win_y0 - 10, 1, 1), (win_x1 + 10, win_y0 - 10, -1, 1), (win_x0 - 10, win_y1 + 10, 1, -1), (win_x1 + 10, win_y1 + 10, -1, -1)]:
        # 枝干
        branch_pts = [(corner_x, corner_y), (corner_x + 60*flip_x, corner_y + 30*flip_y), (corner_x + 140*flip_x, corner_y + 45*flip_y), (corner_x + 220*flip_x, corner_y + 20*flip_y)]
        for i in range(len(branch_pts)-1):
            draw.line([branch_pts[i], branch_pts[i+1]], fill=(145, 100, 75, 220), width=3)
            
        # 盛开的粉樱花簇
        for ox, oy, s in [(40, 25, 28), (90, 40, 36), (150, 42, 32), (200, 20, 26), (60, 70, 24), (120, 80, 22)]:
            fx = corner_x + ox * flip_x
            fy = corner_y + oy * flip_y
            # 5 瓣樱花
            for petal_i in range(5):
                p_ang = petal_i * 72
                draw_floating_petal(draw, fx, fy, s*0.6, s*0.8, p_ang, fill_color=(255, 220, 225, 230), outline_color=(245, 170, 180, 220))
            # 花蕊
            draw.ellipse([fx - 4, fy - 4, fx + 4, fy + 4], fill=(235, 150, 120, 255))
            draw_glow_star(draw, fx, fy, 8, (255, 255, 220, 255))

    # 3. 漫天轻舞的飘落花瓣与微光光斑
    np.random.seed(42)
    for _ in range(35):
        px = np.random.uniform(30, W - 30)
        py = np.random.uniform(30, H - 30)
        # 避开中心纯透明区
        if win_x0 + 100 < px < win_x1 - 100 and win_y0 + 100 < py < win_y1 - 100:
            continue
        rot = np.random.uniform(0, 360)
        sz = np.random.uniform(10, 18)
        alpha_p = int(np.random.uniform(140, 220))
        draw_floating_petal(draw, px, py, sz*0.7, sz, rot, fill_color=(255, 225, 230, alpha_p), outline_color=(250, 185, 195, alpha_p))
        if np.random.rand() > 0.5:
            draw_glow_star(draw, px + 8, py + 8, np.random.uniform(6, 12), (255, 250, 200, 200), (255, 230, 180, 60))

    return im


def gen_summer_firefly() -> Image.Image:
    """2. 夏夜萤火 · 星海微芒 (frame_summer_firefly)"""
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)
    
    win_x0, win_y0 = 80, 90
    win_x1, win_y1 = W - 80, H - 90
    
    # 1. 深邃静谧的夏夜微光边框 (深青金石蓝 + 金色星轨)
    draw.rectangle([win_x0, win_y0, win_x1, win_y1], outline=(100, 150, 200, 150), width=1)
    draw.rectangle([win_x0 - 8, win_y0 - 8, win_x1 + 8, win_y1 + 8], outline=(220, 180, 90, 180), width=1)
    
    # 2. 边缘优雅缠绕的常春藤与夏夜枝蔓
    for corner_x, corner_y, fx, fy in [(win_x0, win_y0, 1, 1), (win_x1, win_y0, -1, 1), (win_x0, win_y1, 1, -1), (win_x1, win_y1, -1, -1)]:
        for i in range(12):
            t = i / 12.0
            vx = corner_x + (t * 260 + 20 * math.sin(t * 8)) * fx
            vy = corner_y + (t * 20 + 25 * math.sin(t * 6)) * fy
            # 嫩绿小叶
            draw_floating_petal(draw, vx, vy, 10, 18, t * 120 * fx, fill_color=(85, 140, 105, 220), outline_color=(120, 180, 140, 240))
            
    # 3. 散落四周的数十颗梦幻发光萤火虫与温润光芒
    np.random.seed(101)
    for _ in range(45):
        gx = np.random.uniform(20, W - 20)
        gy = np.random.uniform(20, H - 20)
        if win_x0 + 80 < gx < win_x1 - 80 and win_y0 + 80 < gy < win_y1 - 80:
            continue
        g_size = np.random.uniform(4, 8)
        # 暖金发光圆晕 (多层光晕)
        draw.ellipse([gx - g_size*3, gy - g_size*3, gx + g_size*3, gy + g_size*3], fill=(255, 235, 120, 40))
        draw.ellipse([gx - g_size*1.8, gy - g_size*1.8, gx + g_size*1.8, gy + g_size*1.8], fill=(255, 220, 80, 90))
        draw.ellipse([gx - g_size*0.8, gy - g_size*0.8, gx + g_size*0.8, gy + g_size*0.8], fill=(255, 255, 220, 240))
        # 微星芒
        if np.random.rand() > 0.4:
            draw_glow_star(draw, gx, gy, np.random.uniform(8, 14), (255, 255, 240, 230))

    # 4. 底部微型手绘星轨刻度
    draw.text((W // 2 - 130, H - 65), "SUMMER NIGHT MEMORY • ✦", fill=(210, 175, 95, 220), font=get_fonts()[1])
    return im


def gen_autumn_ginkgo() -> Image.Image:
    """3. 秋暮银杏 · 琥珀暖阳 (frame_autumn_ginkgo)"""
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)
    
    win_x0, win_y0 = 85, 95
    win_x1, win_y1 = W - 85, H - 95
    
    # 1. 温暖金棕色双重线框 (深陶土红 + 琥珀金)
    draw.rectangle([win_x0, win_y0, win_x1, win_y1], outline=(188, 71, 39, 210), width=2)
    draw.rectangle([win_x0 - 8, win_y0 - 8, win_x1 + 8, win_y1 + 8], outline=(225, 155, 45, 180), width=1)
    
    # 2. 四角与四边飘落的金色银杏叶与红枫叶
    # 四角密集的银杏叶堆叠
    for corner_x, corner_y, fx, fy in [(win_x0 - 15, win_y0 - 15, 1, 1), (win_x1 + 15, win_y0 - 15, -1, 1), (win_x0 - 15, win_y1 + 15, 1, -1), (win_x1 + 15, win_y1 + 15, -1, -1)]:
        for ox, oy, sz, rot, col in [
            (30, 20, 52, -20, (245, 185, 40, 240)),
            (80, 35, 46, 35, (235, 155, 30, 230)),
            (140, 25, 42, -10, (225, 130, 35, 230)),
            (35, 80, 48, 70, (240, 175, 45, 230)),
            (90, 95, 38, -45, (205, 75, 40, 220)), # 红枫点缀
            (160, 85, 44, 15, (250, 195, 55, 240)),
            (210, 30, 36, -30, (230, 160, 40, 220)),
        ]:
            draw_ginkgo_leaf(draw, corner_x + ox*fx, corner_y + oy*fy, sz, rot*fx, fill_color=col, vein_color=(160, 95, 25, 200))
            
    # 3. 散落四周的落叶与金色微尘
    np.random.seed(202)
    for _ in range(30):
        lx = np.random.uniform(25, W - 25)
        ly = np.random.uniform(25, H - 25)
        if win_x0 + 90 < lx < win_x1 - 90 and win_y0 + 90 < ly < win_y1 - 90:
            continue
        lsz = np.random.uniform(24, 38)
        lrot = np.random.uniform(0, 360)
        draw_ginkgo_leaf(draw, lx, ly, lsz, lrot, fill_color=(245, 180, 45, 200), vein_color=(175, 100, 30, 180))
        draw_glow_star(draw, lx + 12, ly + 12, np.random.uniform(6, 10), (255, 220, 120, 220))

    return im


def gen_winter_frost() -> Image.Image:
    """4. 冬雪初晴 · 晶璨雪松 (frame_winter_frost) - Pro 专属"""
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)
    
    win_x0, win_y0 = 85, 95
    win_x1, win_y1 = W - 85, H - 95
    
    # 1. 冰蓝银白晶莹双重线框
    draw.rectangle([win_x0, win_y0, win_x1, win_y1], outline=(175, 210, 235, 220), width=2)
    draw.rectangle([win_x0 - 8, win_y0 - 8, win_x1 + 8, win_y1 + 8], outline=(230, 242, 255, 180), width=1)
    
    # 2. 四角覆雪松针与鲜红冬青浆果
    for corner_x, corner_y, fx, fy in [(win_x0 - 10, win_y0 - 10, 1, 1), (win_x1 + 10, win_y0 - 10, -1, 1), (win_x0 - 10, win_y1 + 10, 1, -1), (win_x1 + 10, win_y1 + 10, -1, -1)]:
        # 深绿松枝
        for i in range(8):
            t = i / 8.0
            bx = corner_x + (t * 220 + 15*math.sin(t*6)) * fx
            by = corner_y + (t * 30 + 20*math.cos(t*4)) * fy
            # 松针
            draw.line([(bx, by), (bx + 25*fx, by + 15*fy)], fill=(65, 100, 75, 240), width=2)
            draw.line([(bx, by), (bx + 18*fx, by - 18*fy)], fill=(65, 100, 75, 240), width=2)
            # 松针上的白雪积霜
            draw.line([(bx, by - 2), (bx + 20*fx, by + 12*fy)], fill=(245, 250, 255, 250), width=2)

        # 鲜艳红冬青果串
        for ox, oy in [(50, 30), (95, 45), (145, 35)]:
            cx, cy = corner_x + ox*fx, corner_y + oy*fy
            draw.ellipse([cx - 9, cy - 9, cx + 5, cy + 5], fill=(215, 45, 40, 255))
            draw.ellipse([cx + 3, cy - 7, cx + 15, cy + 5], fill=(215, 45, 40, 255))
            draw.ellipse([cx - 4, cy + 3, cx + 8, cy + 15], fill=(215, 45, 40, 255))
            draw.ellipse([cx - 2, cy - 4, cx, cy - 2], fill=(255, 220, 220, 255)) # 高光

    # 3. 散落四周的精美晶莹雪花 (6 芒冰晶)
    def draw_snowflake(sx, sy, r, alpha_s):
        for ang in [0, 60, 120]:
            rad = math.radians(ang)
            draw.line([(sx - r*math.cos(rad), sy - r*math.sin(rad)), (sx + r*math.cos(rad), sy + r*math.sin(rad))], fill=(240, 248, 255, alpha_s), width=2)
            # 分叉小冰晶
            for dist in [r*0.5, r*0.85]:
                for side in [-1, 1]:
                    bx = sx + dist * math.cos(rad)
                    by = sy + dist * math.sin(rad)
                    draw.line([(bx, by), (bx + r*0.3*math.cos(rad + side*0.6), by + r*0.3*math.sin(rad + side*0.6))], fill=(240, 248, 255, alpha_s), width=1)

    np.random.seed(303)
    for _ in range(28):
        fx = np.random.uniform(25, W - 25)
        fy = np.random.uniform(25, H - 25)
        if win_x0 + 80 < fx < win_x1 - 80 and win_y0 + 80 < fy < win_y1 - 80:
            continue
        draw_snowflake(fx, fy, np.random.uniform(12, 24), int(np.random.uniform(180, 250)))
        draw_glow_star(draw, fx, fy, np.random.uniform(8, 14), (255, 255, 255, 240), (200, 230, 255, 60))

    return im


def gen_birthday_starlight() -> Image.Image:
    """5. 诞辰星愿 · 岁岁常欢 (frame_birthday_starlight) - Pro 专属"""
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)
    
    win_x0, win_y0 = 85, 110
    win_x1, win_y1 = W - 85, H - 110
    
    # 1. 华丽香槟金双重星轨边框
    draw.rectangle([win_x0, win_y0, win_x1, win_y1], outline=(225, 175, 75, 230), width=2)
    draw.rectangle([win_x0 - 8, win_y0 - 8, win_x1 + 8, win_y1 + 8], outline=(245, 215, 135, 180), width=1)
    
    # 2. 顶部庆祝星芒华盖与悬垂的小星辰吊饰
    for i in range(11):
        x = win_x0 + i * ((win_x1 - win_x0) // 10)
        hang_len = 35 + 25 * math.sin(i * 0.7)
        # 垂线
        draw.line([(x, win_y0 - 8), (x, win_y0 + hang_len)], fill=(225, 180, 90, 200), width=1)
        # 吊坠发光星
        draw_glow_star(draw, x, win_y0 + hang_len, 14 if i % 2 == 0 else 9, (255, 245, 180, 255), (255, 210, 80, 90))

    # 3. 四角香槟色与柔桃色梦幻庆祝气球与丝带波浪
    for corner_x, corner_y, fx, fy in [(win_x0, win_y0, 1, 1), (win_x1, win_y0, -1, 1), (win_x0, win_y1, 1, -1), (win_x1, win_y1, -1, -1)]:
        # 飘带弧线
        for ox, oy, rad, col in [
            (25, 25, 26, (255, 190, 180, 210)),
            (55, 45, 22, (255, 225, 130, 210)),
            (35, 70, 24, (230, 195, 240, 200)),
        ]:
            bx, by = corner_x + ox*fx, corner_y + oy*fy
            draw.ellipse([bx - rad, by - rad*1.2, bx + rad, by + rad*1.2], fill=col, outline=(255, 255, 255, 200), width=1)
            # 气球高光
            draw.ellipse([bx - rad*0.5, by - rad*0.9, bx - rad*0.2, by - rad*0.5], fill=(255, 255, 255, 180))

    # 4. 底部典雅花体金色题字
    font_serif_lg, font_serif_md, _, _ = get_fonts()
    draw.text((W // 2 - 210, H - 82), "✦  A LIFETIME OF PURE LOVE  ✦", fill=(220, 165, 65, 240), font=font_serif_md)

    # 5. 飘散的金色礼花与光斑
    np.random.seed(404)
    for _ in range(40):
        px = np.random.uniform(20, W - 20)
        py = np.random.uniform(20, H - 20)
        if win_x0 + 70 < px < win_x1 - 70 and win_y0 + 70 < py < win_y1 - 70:
            continue
        draw_glow_star(draw, px, py, np.random.uniform(6, 12), (255, 235, 140, 230), (255, 200, 80, 50))

    return im


def gen_eternal_rainbow() -> Image.Image:
    """6. 记忆星河 · 彩虹彼岸 (frame_eternal_rainbow) - Pro 专属"""
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)
    
    win_x0, win_y0 = 85, 95
    win_x1, win_y1 = W - 85, H - 95
    
    # 1. 梦幻温润的七彩微光边框 (虹光渐变线条)
    rainbow_colors = [
        (255, 170, 170, 200), # 柔红
        (255, 205, 150, 200), # 暖橙
        (255, 245, 160, 200), # 柔黄
        (180, 235, 190, 200), # 浅绿
        (170, 220, 250, 200), # 浅蓝
        (205, 185, 245, 200), # 柔紫
    ]
    
    for i, col in enumerate(rainbow_colors):
        offset = i * 2.5
        draw.rectangle([win_x0 - offset, win_y0 - offset, win_x1 + offset, win_y1 + offset], outline=col, width=2)
        
    # 2. 四角与顶部的梦幻彩虹桥弧光与天使微羽
    # 顶部轻柔彩虹弧光
    for r_idx, r_col in enumerate(rainbow_colors):
        draw.arc([win_x0 - 40, win_y0 - 80 - r_idx*3, win_x1 + 40, win_y0 + 120 - r_idx*3], start=200, end=340, fill=r_col, width=3)

    # 四角微光小羽毛与金色星痕
    for corner_x, corner_y, fx, fy in [(win_x0, win_y0, 1, 1), (win_x1, win_y0, -1, 1), (win_x0, win_y1, 1, -1), (win_x1, win_y1, -1, -1)]:
        # 金色守护爪印徽记
        draw.ellipse([corner_x - 14, corner_y - 14, corner_x + 14, corner_y + 14], fill=(255, 235, 160, 220), outline=(220, 175, 80, 255), width=1)
        draw_glow_star(draw, corner_x, corner_y, 16, (255, 255, 255, 255), (255, 220, 100, 100))

    # 3. 浩瀚星河星屑与温暖光斑
    np.random.seed(505)
    for _ in range(50):
        sx = np.random.uniform(20, W - 20)
        sy = np.random.uniform(20, H - 20)
        if win_x0 + 70 < sx < win_x1 - 70 and win_y0 + 70 < sy < win_y1 - 70:
            continue
        sz = np.random.uniform(5, 14)
        c_pick = rainbow_colors[np.random.randint(len(rainbow_colors))]
        draw_glow_star(draw, sx, sy, sz, (255, 255, 255, 240), (*c_pick[:3], 70))

    # 4. 底部守护铭文
    draw.text((W // 2 - 190, H - 72), "✦  FOREVER LOVED & REMEMBERED  ✦", fill=(215, 185, 235, 230), font=get_fonts()[1])

    return im


# --------------------------------------------------------------------------- #
# 主控流程
# --------------------------------------------------------------------------- #

STUNNING_FRAMES = [
    ("frame_spring_blossom", "春樱之约 · 繁花漫境 (Spring Blossom)", "recommended", False, gen_spring_blossom),
    ("frame_summer_firefly", "夏夜萤火 · 星海微芒 (Summer Fireflies)", "film", False, gen_summer_firefly),
    ("frame_autumn_ginkgo", "秋暮银杏 · 琥珀暖阳 (Autumn Ginkgo)", "film", False, gen_autumn_ginkgo),
    ("frame_winter_frost", "冬雪初晴 · 晶璨雪松 (Winter Frost)", "holiday", True, gen_winter_frost),
    ("frame_birthday_starlight", "诞辰星愿 · 岁岁常欢 (Birthday Starlight)", "paper", True, gen_birthday_starlight),
    ("frame_eternal_rainbow", "记忆星河 · 彩虹彼岸 (Eternal Rainbow)", "paper", True, gen_eternal_rainbow),
]


def main():
    print("开始生成 MiLens 【时令与纪念·时光档案馆】绝美艺术相框...")
    
    # 创建高质量测试底图 (温馨安睡小猫咪)
    sample_photo = Image.new("RGBA", (W, H), (242, 236, 226, 255))
    sdraw = ImageDraw.Draw(sample_photo)
    for y in range(H):
        t = y / H
        sdraw.line([(0, y), (W, y)], fill=(int(248 - 25*t), int(238 - 30*t), int(224 - 35*t), 255))
    
    cat_src = BRAIN_DIR / "sleepy_moon_sticker_1787316716106.jpg"
    if cat_src.exists():
        cat_img = Image.open(cat_src).resize((780, 780), Image.Resampling.LANCZOS)
        sample_photo.paste(cat_img, ((W - 780)//2, (H - 780)//2 - 10))

    # 1. 渲染每款透明相框与套框实机效果
    for fid, name, group, is_pro, generator in STUNNING_FRAMES:
        frame_png = generator()
        
        # 保存透明相框原图
        frame_out = OUTPUT_DIR / f"{fid}.png"
        frame_png.save(frame_out, "PNG", optimize=True)
        print(f"  [绝美艺术相框] {frame_out.name}")
        
        # 合成叠加照片的 Mockup
        mockup = sample_photo.copy()
        mockup.paste(frame_png, (0, 0), frame_png)
        mockup_out = OUTPUT_DIR / f"{fid}_mockup.png"
        mockup.save(mockup_out, "PNG", optimize=True)
        print(f"  [实机梦幻套框效果] {mockup_out.name}")

    # 2. 生成全景画廊总览大图
    cols, rows = 3, 2
    cell_w, cell_h = 520, 720
    pad_x, pad_y = 60, 100
    total_w = pad_x * 2 + cols * cell_w
    total_h = pad_y + 120 + rows * cell_h + 40

    overview = Image.new("RGBA", (total_w, total_h), (250, 248, 245, 255))
    draw = ImageDraw.Draw(overview)

    try:
        font_title = ImageFont.truetype("msyh.ttc", 44)
        font_sub = ImageFont.truetype("msyh.ttc", 22)
        font_item = ImageFont.truetype("msyh.ttc", 25)
        font_badge = ImageFont.truetype("msyh.ttc", 16)
    except Exception:
        font_title = font_sub = font_item = font_badge = ImageFont.load_default()

    draw.text((pad_x, 40), "MiLens ·【时令与纪念·时光档案馆】艺术相框全览", fill=(31, 27, 24, 255), font=font_title)
    draw.text((pad_x, 95), "融汇四季时令（春樱、夏萤、秋杏、冬雪）与永恒纪念（诞辰星愿、彩虹彼岸），赋予毛孩子照片无尽的诗意与纪念价值", fill=(107, 98, 91, 255), font=font_sub)

    for idx, (fid, name, group, is_pro, _) in enumerate(STUNNING_FRAMES):
        r = idx // cols
        c = idx % cols
        
        x0 = pad_x + c * cell_w + 16
        y0 = pad_y + 80 + r * cell_h + 16
        x1 = x0 + cell_w - 32
        y1 = y0 + cell_h - 32
        
        draw.rounded_rectangle([x0, y0, x1, y1], radius=16, fill=(255, 255, 255, 255), outline=(229, 223, 216, 255), width=1)
        
        mockup_p = OUTPUT_DIR / f"{fid}_mockup.png"
        mockup_img = Image.open(mockup_p)
        thumb_w, thumb_h = 360, 480
        mockup_thumb = mockup_img.resize((thumb_w, thumb_h), Image.Resampling.LANCZOS)
        
        img_x = x0 + (cell_w - 32 - thumb_w) // 2
        img_y = y0 + 24
        overview.paste(mockup_thumb, (img_x, img_y), mockup_thumb)
        
        zh_title = name.split(" (")[0]
        en_title = name.split(" (")[1].replace(")", "") if "(" in name else ""
        
        draw.text((x0 + 24, y0 + 524), zh_title, fill=(31, 27, 24, 255), font=font_item)
        draw.text((x0 + 24, y0 + 560), f"主题: {group}  |  {en_title}", fill=(107, 98, 91, 255), font=font_sub)
        
        if is_pro:
            draw.rounded_rectangle([x1 - 70, y0 + 16, x1 - 16, y0 + 44], radius=6, fill=(188, 71, 39, 255))
            draw.text((x1 - 58, y0 + 20), "PRO", fill=(255, 255, 255, 255), font=font_badge)
        else:
            draw.rounded_rectangle([x1 - 70, y0 + 16, x1 - 16, y0 + 44], radius=6, fill=(242, 239, 234, 255))
            draw.text((x1 - 58, y0 + 20), "FREE", fill=(107, 98, 91, 255), font=font_badge)

    overview_out = OUTPUT_DIR / "stunning_frames_overview.png"
    overview.save(overview_out, "PNG", optimize=True)
    print(f"\n绝美艺术相框总览图生成完毕！路径: {overview_out}")


if __name__ == "__main__":
    main()
