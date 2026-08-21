#!/usr/bin/env python3
"""MiLens 手绘水彩插画级相框（Hand-drawn Artisanal Watercolor Frames）渲染引擎。

与贴纸保持完全一致的 Quiet Archive 手绘水彩与植物线描风格：
1. 春樱之约 · 繁花漫境 (frame_spring_blossom) - 真实手绘水彩繁樱与手工毛边纸
2. 夏夜萤火 · 星海微芒 (frame_summer_firefly) - 深邃夏夜水彩藤蔓与发光萤火虫光晕
3. 秋暮银杏 · 琥珀暖阳 (frame_autumn_ginkgo) - 手绘水彩银杏扇叶与暖金落叶
4. 冬雪初晴 · 晶璨雪松 (frame_winter_frost) - 手绘水彩覆雪松针与鲜艳冬青红果
5. 诞辰星愿 · 岁岁常欢 (frame_birthday_starlight) - 手绘真丝缎带、金色星芒吊饰与柔彩气球
6. 记忆星河 · 彩虹彼岸 (frame_eternal_rainbow) - 柔和水彩七彩虹晕、星河星屑与守护金色爪印

输出 1200x1600 高清透明相框及搭配真实宠物照片的绝美画廊展示图。
"""

from __future__ import annotations

import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import numpy as np

REPO_ROOT = Path(__file__).resolve().parent.parent
BRAIN_DIR = Path(r"C:\Users\altai\.gemini\antigravity\brain\b492f7ab-360b-4a32-b7c5-a134c71fba2a")
OUTPUT_DIR = BRAIN_DIR / "handdrawn_frames"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

W, H = 1200, 1600


# --------------------------------------------------------------------------- #
# 水彩与手绘渲染辅助
# --------------------------------------------------------------------------- #

def get_fonts():
    try:
        font_serif_lg = ImageFont.truetype("georgia.ttf", 30)
        font_serif_md = ImageFont.truetype("georgia.ttf", 20)
        font_sans = ImageFont.truetype("msyh.ttc", 22)
    except Exception:
        font_serif_lg = font_serif_md = font_sans = ImageFont.load_default()
    return font_serif_lg, font_serif_md, font_sans


def create_watercolor_paper_texture(w: int, h: int) -> Image.Image:
    """生成真实的冷压水彩纸纹理 (Cold-press Watercolor Paper Grain)"""
    arr = np.random.normal(248, 4.0, (h, w)).astype(np.float32)
    # 漫射模糊
    img = Image.fromarray(np.clip(arr, 235, 255).astype(np.uint8))
    img = img.filter(ImageFilter.GaussianBlur(1.2))
    return img.convert("RGBA")


def cutout_spring_master() -> Image.Image:
    """从手绘春樱母版提取高保真透明相框"""
    spring_src = BRAIN_DIR / "spring_handdrawn_1787321637378.jpg"
    if not spring_src.exists():
        return Image.new("RGBA", (W, H), (0, 0, 0, 0))
        
    im = Image.open(spring_src).convert("RGBA").resize((W, H), Image.Resampling.LANCZOS)
    arr = np.array(im, dtype=float)
    r, g, b, a = arr[:,:,0], arr[:,:,1], arr[:,:,2], arr[:,:,3]
    
    # 计算距离白色的距离
    dist_white = np.sqrt((255 - r)**2 + (255 - g)**2 + (255 - b)**2)
    
    alpha = np.ones((H, W), dtype=np.uint8) * 255
    
    # 内视窗中心区域 (撕边水彩纸内侧)
    win_y0, win_y1 = int(0.24 * H), int(0.72 * H)
    win_x0, win_x1 = int(0.26 * W), int(0.74 * W)
    
    win_mask = np.zeros((H, W), dtype=bool)
    win_mask[win_y0:win_y1, win_x0:win_x1] = True
    
    # 纯白色完全抠空
    alpha[win_mask & (dist_white < 22)] = 0
    # 过渡区微平滑
    t_mask = win_mask & (dist_white >= 22) & (dist_white < 45)
    alpha[t_mask] = np.clip((dist_white[t_mask] - 22) / 23.0 * 255.0, 0, 255).astype(np.uint8)
    
    # 四周外边缘去除多余白色背景
    outer_mask = np.ones((H, W), dtype=bool)
    outer_mask[int(0.06*H):int(0.94*H), int(0.08*W):int(0.92*W)] = False
    alpha[outer_mask & (dist_white < 18)] = 0
    
    im.putalpha(Image.fromarray(alpha))
    return im


def gen_handdrawn_summer_firefly() -> Image.Image:
    """2. 夏夜萤火 · 手绘水彩版"""
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)
    
    win_x0, win_y0 = 100, 110
    win_x1, win_y1 = W - 100, H - 110
    
    # 手绘质感夏夜双线与毛边
    draw.rectangle([win_x0, win_y0, win_x1, win_y1], outline=(95, 135, 175, 180), width=2)
    draw.rectangle([win_x0 - 10, win_y0 - 10, win_x1 + 10, win_y1 + 10], outline=(215, 175, 85, 140), width=1)
    
    # 从贴纸中提取手绘水彩枝叶并环绕相框四边
    leaf_color_base = (75, 125, 95)
    
    for corner_x, corner_y, fx, fy in [(win_x0, win_y0, 1, 1), (win_x1, win_y0, -1, 1), (win_x0, win_y1, 1, -1), (win_x1, win_y1, -1, -1)]:
        # 水彩枝条
        for i in range(16):
            t = i / 16.0
            bx = corner_x + (t * 260 + 18*math.sin(t*7)) * fx
            by = corner_y + (t * 25 + 20*math.sin(t*5)) * fy
            
            # 手绘水彩深浅叶片
            leaf_w, leaf_h = 14, 22
            col_var = int(np.random.uniform(-15, 15))
            c_rgb = (leaf_color_base[0] + col_var, leaf_color_base[1] + col_var, leaf_color_base[2] + col_var, 220)
            
            # 绘制自然有机水彩叶片
            ang = t * 140 * fx
            # 叶片椭圆
            draw.ellipse([bx - leaf_w, by - leaf_h, bx + leaf_w, by + leaf_h], fill=c_rgb, outline=(45, 85, 60, 200), width=1)
            draw.line([(bx, by - leaf_h + 3), (bx, by + leaf_h - 3)], fill=(120, 175, 130, 230), width=1) # 叶脉

    # 手绘发光萤火虫 (多层柔和高斯光晕)
    np.random.seed(123)
    for _ in range(48):
        gx = np.random.uniform(30, W - 30)
        gy = np.random.uniform(30, H - 30)
        if win_x0 + 80 < gx < win_x1 - 80 and win_y0 + 80 < gy < win_y1 - 80:
            continue
        rad = np.random.uniform(6, 12)
        # 暖黄外晕
        draw.ellipse([gx - rad*3.5, gy - rad*3.5, gx + rad*3.5, gy + rad*3.5], fill=(255, 235, 120, 35))
        draw.ellipse([gx - rad*2, gy - rad*2, gx + rad*2, gy + rad*2], fill=(255, 220, 80, 85))
        # 亮核
        draw.ellipse([gx - rad*0.8, gy - rad*0.8, gx + rad*0.8, gy + rad*0.8], fill=(255, 255, 210, 240))
        # 铅笔微星
        for ang in [0, 45, 90, 135]:
            r_ang = math.radians(ang)
            slen = rad * 1.5
            draw.line([(gx - slen*math.cos(r_ang), gy - slen*math.sin(r_ang)), (gx + slen*math.cos(r_ang), gy + slen*math.sin(r_ang))], fill=(255, 255, 240, 220), width=1)

    # 底部手绘植物小印记
    draw.text((W // 2 - 145, H - 70), "SUMMER NIGHT MEMORY • ✦", fill=(210, 175, 95, 230), font=get_fonts()[1])
    return im


def gen_handdrawn_autumn_ginkgo() -> Image.Image:
    """3. 秋暮银杏 · 手绘水彩版"""
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)
    
    win_x0, win_y0 = 95, 105
    win_x1, win_y1 = W - 95, H - 105
    
    # 手绘秋季暖陶土红与金色双线
    draw.rectangle([win_x0, win_y0, win_x1, win_y1], outline=(188, 71, 39, 210), width=2)
    draw.rectangle([win_x0 - 10, win_y0 - 10, win_x1 + 10, win_y1 + 10], outline=(225, 155, 45, 180), width=1)
    
    # 绘制层次丰富的手绘水彩银杏叶与红枫
    def draw_watercolor_ginkgo(cx, cy, sz, rot, col_base, vein_col):
        temp = Image.new("RGBA", (int(sz*3), int(sz*3)), (0, 0, 0, 0))
        tdraw = ImageDraw.Draw(temp)
        tcx, tcy = sz*1.5, sz*1.5
        
        # 扇形轮廓与自然波浪边
        pts = [(tcx, tcy + sz*0.8)]
        for i in range(18):
            t = i / 17.0
            ang = math.radians(195 + t * 150)
            r = sz * (1.0 - 0.22*math.sin(t*math.pi)) + np.random.uniform(-1.5, 1.5)
            pts.append((tcx + r*math.cos(ang), tcy + r*math.sin(ang)))
            
        tdraw.polygon(pts, fill=col_base, outline=vein_col, width=1)
        # 手绘叶柄
        tdraw.line([(tcx, tcy + sz*0.8), (tcx + sz*0.15, tcy + sz*1.2)], fill=vein_col, width=2)
        # 放射水彩叶脉
        for i in range(1, 17, 2):
            t = i / 17.0
            ang = math.radians(195 + t * 150)
            r = sz * 0.9
            tdraw.line([(tcx, tcy + sz*0.8), (tcx + r*math.cos(ang), tcy + r*math.sin(ang))], fill=vein_col, width=1)
            
        temp = temp.rotate(rot, resample=Image.Resampling.BICUBIC)
        im.paste(temp, (int(cx - sz*1.5), int(cy - sz*1.5)), temp)

    # 四角堆叠的手绘水彩银杏与枫叶
    leaf_palettes = [
        ((250, 195, 45, 235), (170, 105, 30, 210)),
        ((240, 165, 35, 230), (160, 90, 25, 210)),
        ((225, 130, 30, 225), (150, 75, 20, 200)),
        ((205, 75, 40, 220), (135, 40, 20, 200)), # 枫红
        ((255, 210, 60, 240), (180, 120, 35, 220)),
    ]
    
    for corner_x, corner_y, fx, fy in [(win_x0, win_y0, 1, 1), (win_x1, win_y0, -1, 1), (win_x0, win_y1, 1, -1), (win_x1, win_y1, -1, -1)]:
        for idx, (ox, oy, sz, rot) in enumerate([
            (25, 20, 56, -25), (85, 35, 48, 30), (145, 25, 44, -15),
            (30, 85, 52, 65), (95, 100, 42, -40), (165, 90, 46, 20), (220, 30, 38, -30)
        ]):
            c_base, c_vein = leaf_palettes[idx % len(leaf_palettes)]
            draw_watercolor_ginkgo(corner_x + ox*fx, corner_y + oy*fy, sz, rot*fx, c_base, c_vein)

    # 散落的水彩金叶与微光星屑
    np.random.seed(234)
    for _ in range(32):
        lx = np.random.uniform(30, W - 30)
        ly = np.random.uniform(30, H - 30)
        if win_x0 + 90 < lx < win_x1 - 90 and win_y0 + 90 < ly < win_y1 - 90:
            continue
        lsz = np.random.uniform(26, 40)
        lrot = np.random.uniform(0, 360)
        c_base, c_vein = leaf_palettes[np.random.randint(len(leaf_palettes))]
        draw_watercolor_ginkgo(lx, ly, lsz, lrot, c_base, c_vein)
        # 金色微尘
        draw.ellipse([lx + 10, ly + 10, lx + 16, ly + 16], fill=(255, 220, 120, 200))

    return im


def gen_handdrawn_winter_frost() -> Image.Image:
    """4. 冬雪初晴 · 手绘水彩版"""
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)
    
    win_x0, win_y0 = 95, 105
    win_x1, win_y1 = W - 95, H - 105
    
    draw.rectangle([win_x0, win_y0, win_x1, win_y1], outline=(175, 210, 235, 210), width=2)
    draw.rectangle([win_x0 - 10, win_y0 - 10, win_x1 + 10, win_y1 + 10], outline=(230, 245, 255, 180), width=1)
    
    # 手绘覆雪松针枝桠与鲜艳冬青浆果
    for corner_x, corner_y, fx, fy in [(win_x0, win_y0, 1, 1), (win_x1, win_y0, -1, 1), (win_x0, win_y1, 1, -1), (win_x1, win_y1, -1, -1)]:
        # 水彩深绿松枝
        for i in range(12):
            t = i / 12.0
            bx = corner_x + (t * 240 + 16*math.sin(t*6)) * fx
            by = corner_y + (t * 32 + 22*math.cos(t*4)) * fy
            
            # 松针簇
            draw.line([(bx, by), (bx + 26*fx, by + 16*fy)], fill=(55, 95, 70, 240), width=2)
            draw.line([(bx, by), (bx + 20*fx, by - 20*fy)], fill=(65, 105, 80, 240), width=2)
            # 松针上的厚实手绘白雪积霜
            draw.line([(bx, by - 2), (bx + 22*fx, by + 12*fy)], fill=(248, 252, 255, 255), width=3)

        # 晶莹水彩红冬青果
        for ox, oy in [(55, 32), (105, 48), (155, 38), (75, 70)]:
            cx, cy = corner_x + ox*fx, corner_y + oy*fy
            draw.ellipse([cx - 10, cy - 10, cx + 6, cy + 6], fill=(215, 45, 40, 255), outline=(150, 25, 20, 220))
            draw.ellipse([cx + 3, cy - 8, cx + 16, cy + 6], fill=(215, 45, 40, 255), outline=(150, 25, 20, 220))
            draw.ellipse([cx - 4, cy + 4, cx + 9, cy + 16], fill=(215, 45, 40, 255), outline=(150, 25, 20, 220))
            # 白色反光水彩高光
            draw.ellipse([cx - 3, cy - 5, cx, cy - 2], fill=(255, 230, 230, 255))
            draw.ellipse([cx + 7, cy - 4, cx + 10, cy - 1], fill=(255, 230, 230, 255))

    # 手绘冰晶雪花 (细腻 6 芒雪花)
    def draw_watercolor_snowflake(sx, sy, r, alpha_s):
        for ang in [0, 60, 120]:
            rad = math.radians(ang)
            draw.line([(sx - r*math.cos(rad), sy - r*math.sin(rad)), (sx + r*math.cos(rad), sy + r*math.sin(rad))], fill=(240, 248, 255, alpha_s), width=2)
            for dist in [r*0.5, r*0.85]:
                for side in [-1, 1]:
                    bx = sx + dist * math.cos(rad)
                    by = sy + dist * math.sin(rad)
                    draw.line([(bx, by), (bx + r*0.35*math.cos(rad + side*0.6), by + r*0.35*math.sin(rad + side*0.6))], fill=(240, 248, 255, alpha_s), width=1)

    np.random.seed(345)
    for _ in range(30):
        fx = np.random.uniform(30, W - 30)
        fy = np.random.uniform(30, H - 30)
        if win_x0 + 80 < fx < win_x1 - 80 and win_y0 + 80 < fy < win_y1 - 80:
            continue
        draw_watercolor_snowflake(fx, fy, np.random.uniform(14, 26), int(np.random.uniform(180, 255)))

    return im


def gen_handdrawn_birthday_starlight() -> Image.Image:
    """5. 诞辰星愿 · 手绘水彩版"""
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)
    
    win_x0, win_y0 = 90, 115
    win_x1, win_y1 = W - 90, H - 115
    
    draw.rectangle([win_x0, win_y0, win_x1, win_y1], outline=(225, 175, 75, 230), width=2)
    draw.rectangle([win_x0 - 10, win_y0 - 10, win_x1 + 10, win_y1 + 10], outline=(245, 215, 135, 180), width=1)
    
    # 顶部手绘金色悬垂吊星
    for i in range(11):
        x = win_x0 + i * ((win_x1 - win_x0) // 10)
        hang_len = 38 + 28 * math.sin(i * 0.7)
        draw.line([(x, win_y0 - 10), (x, win_y0 + hang_len)], fill=(225, 180, 90, 210), width=1)
        # 手绘金色发光星
        star_r = 16 if i % 2 == 0 else 10
        # 外发光
        draw.ellipse([x - star_r*1.8, win_y0 + hang_len - star_r*1.8, x + star_r*1.8, win_y0 + hang_len + star_r*1.8], fill=(255, 230, 120, 60))
        # 金色八角星
        for ang in [0, 45, 90, 135]:
            rad = math.radians(ang)
            draw.line([(x - star_r*math.cos(rad), win_y0 + hang_len - star_r*math.sin(rad)), (x + star_r*math.cos(rad), win_y0 + hang_len + star_r*math.sin(rad))], fill=(255, 250, 200, 255), width=2)

    # 四角手绘柔桃与香槟色轻盈水彩气球与缎带
    for corner_x, corner_y, fx, fy in [(win_x0, win_y0, 1, 1), (win_x1, win_y0, -1, 1), (win_x0, win_y1, 1, -1), (win_x1, win_y1, -1, -1)]:
        for ox, oy, rad, col in [
            (28, 28, 28, (255, 195, 185, 220)),
            (60, 50, 24, (255, 230, 140, 220)),
            (38, 78, 26, (235, 200, 245, 210)),
        ]:
            bx, by = corner_x + ox*fx, corner_y + oy*fy
            draw.ellipse([bx - rad, by - rad*1.25, bx + rad, by + rad*1.25], fill=col, outline=(255, 255, 255, 220), width=1)
            # 水彩高光弧
            draw.arc([bx - rad*0.7, by - rad*1.0, bx + rad*0.3, by - rad*0.2], start=200, end=300, fill=(255, 255, 255, 220), width=2)

    # 底部金色花体祝福
    font_serif_lg, font_serif_md, font_sans = get_fonts()
    draw.text((W // 2 - 210, H - 85), "✦  A LIFETIME OF PURE LOVE  ✦", fill=(220, 165, 65, 240), font=font_serif_md)

    return im


def gen_handdrawn_eternal_rainbow() -> Image.Image:
    """6. 记忆星河 · 手绘水彩版"""
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)
    
    win_x0, win_y0 = 90, 100
    win_x1, win_y1 = W - 90, H - 100
    
    # 柔和水彩彩虹六色渐变框
    rainbow_colors = [
        (255, 175, 175, 190),
        (255, 210, 155, 190),
        (255, 245, 165, 190),
        (185, 235, 195, 190),
        (175, 220, 250, 190),
        (210, 190, 245, 190),
    ]
    
    for i, col in enumerate(rainbow_colors):
        offset = i * 3
        draw.rectangle([win_x0 - offset, win_y0 - offset, win_x1 + offset, win_y1 + offset], outline=col, width=2)
        
    # 顶部手绘柔光彩虹拱弧
    for r_idx, r_col in enumerate(rainbow_colors):
        draw.arc([win_x0 - 50, win_y0 - 90 - r_idx*4, win_x1 + 50, win_y0 + 130 - r_idx*4], start=195, end=345, fill=r_col, width=3)

    # 四角金色守护肉垫徽章与发光小星
    for corner_x, corner_y, fx, fy in [(win_x0, win_y0, 1, 1), (win_x1, win_y0, -1, 1), (win_x0, win_y1, 1, -1), (win_x1, win_y1, -1, -1)]:
        draw.ellipse([corner_x - 16, corner_y - 16, corner_x + 16, corner_y + 16], fill=(255, 235, 160, 230), outline=(220, 175, 80, 255), width=2)
        # 小肉垫
        draw.ellipse([corner_x - 7, corner_y - 3, corner_x + 7, corner_y + 8], fill=(188, 71, 39, 240))
        for t_ang in [-45, -15, 15, 45]:
            t_rad = math.radians(t_ang - 90)
            tx = corner_x + 9 * math.cos(t_rad)
            ty = corner_y + 9 * math.sin(t_rad)
            draw.ellipse([tx - 2.5, ty - 2.5, tx + 2.5, ty + 2.5], fill=(188, 71, 39, 240))

    # 散落浩瀚星河星屑
    np.random.seed(567)
    for _ in range(55):
        sx = np.random.uniform(25, W - 25)
        sy = np.random.uniform(25, H - 25)
        if win_x0 + 70 < sx < win_x1 - 70 and win_y0 + 70 < sy < win_y1 - 70:
            continue
        sz = np.random.uniform(6, 14)
        c_pick = rainbow_colors[np.random.randint(len(rainbow_colors))]
        # 外晕
        draw.ellipse([sx - sz, sy - sz, sx + sz, sy + sz], fill=(*c_pick[:3], 60))
        # 亮核
        draw.ellipse([sx - 2, sy - 2, sx + 2, sy + 2], fill=(255, 255, 255, 240))

    # 底部守护铭文
    draw.text((W // 2 - 190, H - 75), "✦  FOREVER LOVED & REMEMBERED  ✦", fill=(215, 185, 235, 240), font=get_fonts()[1])
    return im


# --------------------------------------------------------------------------- #
# 主控生成流程
# --------------------------------------------------------------------------- #

HANDDRAWN_FRAMES = [
    ("frame_spring_blossom", "春樱之约 · 繁花漫境 (Spring Blossom)", "recommended", False, cutout_spring_master),
    ("frame_summer_firefly", "夏夜萤火 · 星海微芒 (Summer Fireflies)", "film", False, gen_handdrawn_summer_firefly),
    ("frame_autumn_ginkgo", "秋暮银杏 · 琥珀暖阳 (Autumn Ginkgo)", "film", False, gen_handdrawn_autumn_ginkgo),
    ("frame_winter_frost", "冬雪初晴 · 晶璨雪松 (Winter Frost)", "holiday", True, gen_handdrawn_winter_frost),
    ("frame_birthday_starlight", "诞辰星愿 · 岁岁常欢 (Birthday Starlight)", "paper", True, gen_handdrawn_birthday_starlight),
    ("frame_eternal_rainbow", "记忆星河 · 彩虹彼岸 (Eternal Rainbow)", "paper", True, gen_handdrawn_eternal_rainbow),
]


def main():
    print("开始生成 MiLens 手绘水彩插画级相框（与贴纸完全一致的手绘风格）...")
    
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
    for fid, name, group, is_pro, generator in HANDDRAWN_FRAMES:
        frame_png = generator()
        
        # 保存透明相框原图
        frame_out = OUTPUT_DIR / f"{fid}.png"
        frame_png.save(frame_out, "PNG", optimize=True)
        print(f"  [手绘水彩相框原图] {frame_out.name}")
        
        # 合成叠加照片的 Mockup
        mockup = sample_photo.copy()
        mockup.paste(frame_png, (0, 0), frame_png)
        mockup_out = OUTPUT_DIR / f"{fid}_mockup.png"
        mockup.save(mockup_out, "PNG", optimize=True)
        print(f"  [实机手绘套框效果] {mockup_out.name}")

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

    draw.text((pad_x, 40), "MiLens · 手绘水彩插画级相框设计全览 (Quiet Archive 手绘质感)", fill=(31, 27, 24, 255), font=font_title)
    draw.text((pad_x, 95), "与贴纸保持完全一致的手工水彩晕染、植物标本细线描、撕边纸样与微颗粒星屑，充满生命温度与画作感", fill=(107, 98, 91, 255), font=font_sub)

    for idx, (fid, name, group, is_pro, _) in enumerate(HANDDRAWN_FRAMES):
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

    overview_out = OUTPUT_DIR / "handdrawn_frames_overview.png"
    overview.save(overview_out, "PNG", optimize=True)
    print(f"\n手绘水彩相框总览图生成完毕！路径: {overview_out}")


if __name__ == "__main__":
    main()
