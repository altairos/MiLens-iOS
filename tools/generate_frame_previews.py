#!/usr/bin/env python3
"""MiLens 6 款精选相框设计与渲染脚本。

基于 Quiet Archive 美术风格规范，生成 6 款高清晰度透明相框母版，
并生成带有照片叠加效果的 Mockup 预览和总览全景图，供用户在画廊中检视。
"""

from __future__ import annotations

import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import numpy as np

REPO_ROOT = Path(__file__).resolve().parent.parent
BRAIN_DIR = Path(r"C:\Users\altai\.gemini\antigravity\brain\b492f7ab-360b-4a32-b7c5-a134c71fba2a")
OUTPUT_DIR = BRAIN_DIR / "frame_previews"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

# 色彩定义
TERRACOTTA = (188, 71, 39, 255)       # #BC4727 深陶土红
WARM_GOLD = (220, 140, 75, 255)        # 暖铜金
DARK_INK = (31, 27, 24, 255)          # 档案墨黑
IVORY_PAPER = (250, 248, 245, 255)     # 纸白
WARM_CREAM = (244, 240, 232, 255)      # 暖米色
BORDER_LINE = (229, 223, 216, 255)
FILM_BLACK = (22, 20, 18, 255)        # 胶片黑
FILM_YELLOW = (235, 185, 80, 255)     # 胶卷黄
HOLLY_RED = (200, 50, 45, 255)
PINE_GREEN = (78, 115, 88, 255)

W, H = 1200, 1600  # 标准 3:4 相框母版尺寸


def get_fonts():
    try:
        font_serif_lg = ImageFont.truetype("georgia.ttf", 28)
        font_serif_md = ImageFont.truetype("georgia.ttf", 20)
        font_mono = ImageFont.truetype("consola.ttf", 18)
        font_mono_lg = ImageFont.truetype("consola.ttf", 24)
        font_sans = ImageFont.truetype("msyh.ttc", 22)
    except Exception:
        font_serif_lg = font_serif_md = font_mono = font_mono_lg = font_sans = ImageFont.load_default()
    return font_serif_lg, font_serif_md, font_mono, font_mono_lg, font_sans


def create_sample_photo() -> Image.Image:
    """生成一张用于相框效果展示的温馨样张底图（暖阳下安睡小猫）"""
    sample = Image.new("RGBA", (W, H), (240, 230, 220, 255))
    sdraw = ImageDraw.Draw(sample)
    
    # 柔和渐变背景
    for y in range(H):
        ratio = y / H
        r = int(248 * (1 - ratio*0.2) + 215 * ratio*0.2)
        g = int(235 * (1 - ratio*0.2) + 195 * ratio*0.2)
        b = int(220 * (1 - ratio*0.2) + 175 * ratio*0.2)
        sdraw.line([(0, y), (W, y)], fill=(r, g, b, 255))

    # 尝试加载小猫插画或绘制温馨剪影
    cat_src = BRAIN_DIR / "sleepy_moon_sticker_1787316716106.jpg"
    if cat_src.exists():
        cat_img = Image.open(cat_src).resize((700, 700), Image.Resampling.LANCZOS)
        sample.paste(cat_img, ((W - 700)//2, (H - 700)//2 - 40))
    
    return sample


# --------------------------------------------------------------------------- #
# 6 款相框的具体渲染实现
# --------------------------------------------------------------------------- #

def gen_frame_linen_register() -> Image.Image:
    """1. 亚麻登记框 (frame_linen_register)"""
    linen_src = BRAIN_DIR / "frame_linen_reg_1787319664269.jpg"
    if linen_src.exists():
        im = Image.open(linen_src).convert("RGBA").resize((W, H), Image.Resampling.LANCZOS)
        arr = np.array(im, dtype=float)
        r, g, b, a = arr[:,:,0], arr[:,:,1], arr[:,:,2], arr[:,:,3]
        dist_white = np.sqrt((255-r)**2 + (255-g)**2 + (255-b)**2)
        
        alpha = np.ones((H, W), dtype=np.uint8) * 255
        
        # 内视窗完全镂空
        win_mask = np.zeros((H, W), dtype=bool)
        win_y0, win_y1 = int(0.205 * H), int(0.765 * H)
        win_x0, win_x1 = int(0.245 * W), int(0.755 * W)
        win_mask[win_y0:win_y1, win_x0:win_x1] = True
        
        # 外边缘轻微透明
        outer_mask = np.ones((H, W), dtype=bool)
        card_y0, card_y1 = int(0.095 * H), int(0.875 * H)
        card_x0, card_x1 = int(0.100 * W), int(0.900 * W)
        outer_mask[card_y0:card_y1, card_x0:card_x1] = False
        
        alpha[win_mask & (dist_white < 35)] = 0
        alpha[outer_mask & (dist_white < 25)] = 0
        
        im.putalpha(Image.fromarray(alpha))
        return im
    
    # 纯算法降级绘制
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    return im


def gen_frame_polaroid_white() -> Image.Image:
    """2. 拍立得经典白框 (frame_polaroid_white)"""
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)
    
    # 外卡片尺寸（留出四周轻微呼吸边距）
    pad_out_x, pad_out_y = 60, 60
    card_x0, card_y0 = pad_out_x, pad_out_y
    card_x1, card_y1 = W - pad_out_x, H - pad_out_y
    
    # 1. 拍立得相纸底色（象牙白带有极微纸纤维微噪点）
    draw.rounded_rectangle([card_x0, card_y0, card_x1, card_y1], radius=16, fill=WARM_CREAM, outline=BORDER_LINE, width=2)
    
    # 2. 内视窗坐标（经典拍立得上/左/右窄边 100px，下宽边 280px）
    win_x0 = card_x0 + 80
    win_y0 = card_y0 + 80
    win_x1 = card_x1 - 80
    win_y1 = card_y1 - 260
    
    # 3. 视窗内边缘凹槽微阴影 (Bevel Inner Shadow)
    draw.rounded_rectangle([win_x0 - 4, win_y0 - 4, win_x1 + 4, win_y1 + 4], radius=6, outline=(210, 205, 195, 255), width=3)
    draw.rounded_rectangle([win_x0 - 1, win_y0 - 1, win_x1 + 1, win_y1 + 1], radius=4, outline=(170, 160, 150, 255), width=2)
    
    # 4. 底部手写/极细印字区域
    _, font_serif_md, font_mono, _, _ = get_fonts()
    bottom_cy = (win_y1 + card_y1) // 2
    draw.text((win_x0 + 20, bottom_cy - 14), "MiLens • Instant Archive", fill=(130, 120, 110, 255), font=font_serif_md)
    draw.text((win_x1 - 180, bottom_cy - 10), "ISO 400 / 2026", fill=(170, 160, 150, 255), font=font_mono)
    
    # 5. 挖空内视窗 (Alpha = 0)
    arr = np.array(im)
    arr[win_y0:win_y1, win_x0:win_x1, 3] = 0
    return Image.fromarray(arr)


def gen_frame_vintage_film() -> Image.Image:
    """3. 复古黑胶卷底片 (frame_vintage_film)"""
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)
    
    # 胶片外框
    draw.rectangle([0, 0, W, H], fill=FILM_BLACK)
    
    # 左右两侧各 140px 为齿孔区，中间为透光视窗
    border_w = 140
    win_x0 = border_w
    win_y0 = 60
    win_x1 = W - border_w
    win_y1 = H - 60
    
    _, _, font_mono, font_mono_lg, _ = get_fonts()
    
    # 绘制左侧与右侧 35mm 方形圆角齿孔与编号
    num_sprockets = 14
    sp_h = 56
    sp_w = 42
    sp_gap = (H - 80) / num_sprockets
    
    for i in range(num_sprockets):
        sy = int(40 + i * sp_gap)
        
        # 左齿孔
        draw.rounded_rectangle([36, sy, 36 + sp_w, sy + sp_h], radius=8, fill=(0, 0, 0, 0), outline=(50, 45, 40, 255), width=2)
        # 右齿孔
        draw.rounded_rectangle([W - 36 - sp_w, sy, W - 36, sy + sp_h], radius=8, fill=(0, 0, 0, 0), outline=(50, 45, 40, 255), width=2)
        
        # 胶卷边缘黄色打印批号
        if i % 2 == 0:
            frame_no = 20 + i
            draw.text((92, sy + 14), f"▶ {frame_no}A", fill=FILM_YELLOW, font=font_mono)
            draw.text((W - 130, sy + 14), "MILENS 400", fill=FILM_YELLOW, font=font_mono)

    # 视窗四周边框金铜色细线
    draw.rectangle([win_x0 - 2, win_y0 - 2, win_x1 + 2, win_y1 + 2], outline=(140, 90, 50, 255), width=2)
    
    # 挖空中央视窗
    arr = np.array(im)
    arr[win_y0:win_y1, win_x0:win_x1, 3] = 0
    return Image.fromarray(arr)


def gen_frame_editorial_paper() -> Image.Image:
    """4. 典雅期刊纸样 (frame_editorial_paper) - Pro"""
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)
    
    card_x0, card_y0 = 40, 40
    card_x1, card_y1 = W - 40, H - 40
    
    # 1. 象牙白手工纸底
    draw.rectangle([card_x0, card_y0, card_x1, card_y1], fill=IVORY_PAPER, outline=BORDER_LINE, width=1)
    
    # 2. 视窗四周双重深陶土红与暖金细线
    win_x0, win_y0 = 120, 140
    win_x1, win_y1 = W - 120, H - 160
    
    # 外细线（陶土红）
    draw.rectangle([win_x0 - 16, win_y0 - 16, win_x1 + 16, win_y1 + 16], outline=TERRACOTTA, width=3)
    # 内极细线（暖金）
    draw.rectangle([win_x0 - 6, win_y0 - 6, win_x1 + 6, win_y1 + 6], outline=WARM_GOLD, width=1)
    
    # 3. 四角古典 L 型角规与十字校准标
    bracket_len = 50
    corners = [
        (win_x0 - 32, win_y0 - 32, 1, 1),
        (win_x1 + 32, win_y0 - 32, -1, 1),
        (win_x0 - 32, win_y1 + 32, 1, -1),
        (win_x1 + 32, win_y1 + 32, -1, -1),
    ]
    for cx, cy, dx, dy in corners:
        draw.line([(cx, cy), (cx + dx * bracket_len, cy)], fill=DARK_INK, width=2)
        draw.line([(cx, cy), (cx, cy + dy * bracket_len)], fill=DARK_INK, width=2)
        # 微型十字
        draw.line([(cx - 8, cy), (cx + 8, cy)], fill=TERRACOTTA, width=1)
        draw.line([(cx, cy - 8), (cx, cy + 8)], fill=TERRACOTTA, width=1)

    # 4. 底部典雅画廊题注
    font_serif_lg, font_serif_md, _, _, _ = get_fonts()
    title_text = "MILENS PHOTOGRAPHIC ARCHIVE"
    sub_text = "FINE ART COLLECTION • PLATE NO. 04"
    draw.text((W // 2 - 240, H - 110), title_text, fill=DARK_INK, font=font_serif_lg)
    draw.text((W // 2 - 180, H - 75), sub_text, fill=TERRACOTTA, font=font_serif_md)
    
    # 挖空中央视窗
    arr = np.array(im)
    arr[win_y0:win_y1, win_x0:win_x1, 3] = 0
    return Image.fromarray(arr)


def gen_frame_ribbon_bound() -> Image.Image:
    """5. 丝带装订相角 (frame_ribbon_bound) - Pro"""
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)
    
    card_x0, card_y0 = 50, 50
    card_x1, card_y1 = W - 50, H - 50
    draw.rounded_rectangle([card_x0, card_y0, card_x1, card_y1], radius=20, fill=WARM_CREAM, outline=BORDER_LINE, width=2)
    
    win_x0, win_y0 = 110, 110
    win_x1, win_y1 = W - 110, H - 110
    
    # 手工缝线虚线
    dash_len = 12
    gap_len = 8
    # 顶部和底部缝线
    for x in range(win_x0 - 20, win_x1 + 20, dash_len + gap_len):
        draw.line([(x, win_y0 - 20), (min(x + dash_len, win_x1 + 20), win_y0 - 20)], fill=(180, 170, 160, 255), width=2)
        draw.line([(x, win_y1 + 20), (min(x + dash_len, win_x1 + 20), win_y1 + 20)], fill=(180, 170, 160, 255), width=2)
    for y in range(win_y0 - 20, win_y1 + 20, dash_len + gap_len):
        draw.line([(win_x0 - 20, y), (win_x0 - 20, min(y + dash_len, win_y1 + 20))], fill=(180, 170, 160, 255), width=2)
        draw.line([(win_x1 + 20, y), (win_x1 + 20, min(y + dash_len, win_y1 + 20))], fill=(180, 170, 160, 255), width=2)

    # 4 个真丝缎带三角角插 (Photo Corners)
    corner_size = 90
    
    # 左上
    draw.polygon([(win_x0 - 10, win_y0 + corner_size), (win_x0 + corner_size, win_y0 - 10), (win_x0 - 10, win_y0 - 10)], fill=TERRACOTTA)
    draw.polygon([(win_x0 - 5, win_y0 + corner_size - 15), (win_x0 + corner_size - 15, win_y0 - 5), (win_x0 - 5, win_y0 - 5)], fill=WARM_GOLD)
    # 右上
    draw.polygon([(win_x1 + 10, win_y0 + corner_size), (win_x1 - corner_size, win_y0 - 10), (win_x1 + 10, win_y0 - 10)], fill=TERRACOTTA)
    draw.polygon([(win_x1 + 5, win_y0 + corner_size - 15), (win_x1 - corner_size + 15, win_y0 - 5), (win_x1 + 5, win_y0 - 5)], fill=WARM_GOLD)
    # 左下
    draw.polygon([(win_x0 - 10, win_y1 - corner_size), (win_x0 + corner_size, win_y1 + 10), (win_x0 - 10, win_y1 + 10)], fill=TERRACOTTA)
    draw.polygon([(win_x0 - 5, win_y1 - corner_size + 15), (win_x0 + corner_size - 15, win_y1 + 5), (win_x0 - 5, win_y1 + 5)], fill=WARM_GOLD)
    # 右下
    draw.polygon([(win_x1 + 10, win_y1 - corner_size), (win_x1 - corner_size, win_y1 + 10), (win_x1 + 10, win_y1 + 10)], fill=TERRACOTTA)
    draw.polygon([(win_x1 + 5, win_y1 - corner_size + 15), (win_x1 - corner_size + 15, win_y1 + 5), (win_x1 + 5, win_y1 + 5)], fill=WARM_GOLD)

    # 挖空中央视窗
    arr = np.array(im)
    arr[win_y0:win_y1, win_x0:win_x1, 3] = 0
    return Image.fromarray(arr)


def gen_frame_holiday_warmth() -> Image.Image:
    """6. 暖冬节日 (frame_holiday_warmth) - Pro"""
    im = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(im)
    
    card_x0, card_y0 = 40, 40
    card_x1, card_y1 = W - 40, H - 40
    draw.rounded_rectangle([card_x0, card_y0, card_x1, card_y1], radius=16, fill=IVORY_PAPER, outline=BORDER_LINE, width=1)
    
    win_x0, win_y0 = 100, 100
    win_x1, win_y1 = W - 100, H - 100
    
    # 绘制内框微金细线
    draw.rectangle([win_x0, win_y0, win_x1, win_y1], outline=(210, 180, 140, 255), width=2)
    
    # 四周环绕手绘松针、冬青红浆果与金色微星
    def draw_pine_branch(bx, by, angle_deg, length=60):
        rad = math.radians(angle_deg)
        ex = bx + length * math.cos(rad)
        ey = by + length * math.sin(rad)
        draw.line([(bx, by), (ex, ey)], fill=PINE_GREEN, width=3)
        # 松针分叉
        for i in range(4):
            t = (i + 1) / 5.0
            px = bx + t * (ex - bx)
            py = by + t * (ey - by)
            # 左右针
            draw.line([(px, py), (px + 18*math.cos(rad + 0.6), py + 18*math.sin(rad + 0.6))], fill=PINE_GREEN, width=2)
            draw.line([(px, py), (px + 18*math.cos(rad - 0.6), py + 18*math.sin(rad - 0.6))], fill=PINE_GREEN, width=2)

    def draw_holly_berries(cx, cy):
        draw.ellipse([cx - 8, cy - 8, cx + 4, cy + 4], fill=HOLLY_RED)
        draw.ellipse([cx + 2, cy - 6, cx + 14, cy + 6], fill=HOLLY_RED)
        draw.ellipse([cx - 4, cy + 2, cx + 8, cy + 14], fill=HOLLY_RED)
        draw.ellipse([cx - 2, cy - 4, cx, cy - 2], fill=(255, 200, 200, 255))  # 高光点

    # 四角植物花环与星辰
    # 顶部松枝串
    for x in range(win_x0 + 40, win_x1 - 40, 90):
        draw_pine_branch(x, win_y0 - 15, 0 if (x // 90) % 2 == 0 else 180, length=45)
        if (x // 90) % 2 == 1:
            draw_holly_berries(x, win_y0 - 22)
            
    # 底部松枝串
    for x in range(win_x0 + 40, win_x1 - 40, 90):
        draw_pine_branch(x, win_y1 + 15, 0 if (x // 90) % 2 == 0 else 180, length=45)
        if (x // 90) % 2 == 0:
            draw_holly_berries(x, win_y1 + 22)

    # 左右两侧松枝串
    for y in range(win_y0 + 60, win_y1 - 60, 110):
        draw_pine_branch(win_x0 - 15, y, 90 if (y // 110) % 2 == 0 else 270, length=45)
        draw_pine_branch(win_x1 + 15, y, 90 if (y // 110) % 2 == 0 else 270, length=45)
        if (y // 110) % 2 == 1:
            draw_holly_berries(win_x0 - 20, y)
            draw_holly_berries(win_x1 + 20, y)

    # 四角八芒金星
    def draw_mini_star(sx, sy):
        for ang in [0, 45, 90, 135]:
            r = math.radians(ang)
            draw.line([(sx - 14*math.cos(r), sy - 14*math.sin(r)), (sx + 14*math.cos(r), sy + 14*math.sin(r))], fill=WARM_GOLD, width=2)

    draw_mini_star(win_x0 - 40, win_y0 - 40)
    draw_mini_star(win_x1 + 40, win_y0 - 40)
    draw_mini_star(win_x0 - 40, win_y1 + 40)
    draw_mini_star(win_x1 + 40, win_y1 + 40)

    # 挖空中央视窗
    arr = np.array(im)
    arr[win_y0:win_y1, win_x0:win_x1, 3] = 0
    return Image.fromarray(arr)


# --------------------------------------------------------------------------- #
# 主控生成流程
# --------------------------------------------------------------------------- #

FRAMES_SPEC = [
    ("frame_linen_register", "亚麻登记框 (Linen Register)", "recommended", False, gen_frame_linen_register),
    ("frame_polaroid_white", "拍立得白框 (Polaroid White)", "film", False, gen_frame_polaroid_white),
    ("frame_vintage_film", "复古胶卷底片 (Vintage Film)", "film", False, gen_frame_vintage_film),
    ("frame_editorial_paper", "典雅期刊纸样 (Editorial Paper)", "paper", True, gen_frame_editorial_paper),
    ("frame_ribbon_bound", "丝带装订相角 (Ribbon Bound)", "paper", True, gen_frame_ribbon_bound),
    ("frame_holiday_warmth", "暖冬节日 (Holiday Warmth)", "holiday", True, gen_frame_holiday_warmth),
]


def main():
    print("开始生成 MiLens 6 款精选相框设计稿与 Mockup 预览...")
    sample_photo = create_sample_photo()
    
    # 1. 生成并保存各相框透明图与 Mockup
    for fid, name, group, is_pro, generator in FRAMES_SPEC:
        frame_png = generator()
        
        # 保存纯相框透明 PNG
        frame_path = OUTPUT_DIR / f"{fid}.png"
        frame_png.save(frame_path, "PNG", optimize=True)
        print(f"  [相框透明原图] {frame_path.name}")
        
        # 合成叠加照片的 Mockup
        mockup = sample_photo.copy()
        mockup.paste(frame_png, (0, 0), frame_png)
        mockup_path = OUTPUT_DIR / f"{fid}_mockup.png"
        mockup.save(mockup_path, "PNG", optimize=True)
        print(f"  [照片套框效果] {mockup_path.name}")

    # 2. 生成一张高清晰度的 6 款相框总览大图 (Frames Overview Sheet)
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
        font_item = ImageFont.truetype("msyh.ttc", 26)
        font_badge = ImageFont.truetype("msyh.ttc", 16)
    except Exception:
        font_title = font_sub = font_item = font_badge = ImageFont.load_default()

    draw.text((pad_x, 40), "MiLens · 首批相框素材设计全览 (Quiet Archive 调性)", fill=DARK_INK, font=font_title)
    draw.text((pad_x, 95), "涵盖推荐、胶片、纸样、节日四大分组；包含纯透明边框与实际照片套框效果", fill=(107, 98, 91, 255), font=font_sub)

    for idx, (fid, name, group, is_pro, _) in enumerate(FRAMES_SPEC):
        r = idx // cols
        c = idx % cols
        
        x0 = pad_x + c * cell_w + 16
        y0 = pad_y + 80 + r * cell_h + 16
        x1 = x0 + cell_w - 32
        y1 = y0 + cell_h - 32
        
        draw.rounded_rectangle([x0, y0, x1, y1], radius=16, fill=(255, 255, 255, 255), outline=BORDER_LINE, width=1)
        
        mockup_p = OUTPUT_DIR / f"{fid}_mockup.png"
        mockup_img = Image.open(mockup_p)
        thumb_w, thumb_h = 360, 480
        mockup_thumb = mockup_img.resize((thumb_w, thumb_h), Image.Resampling.LANCZOS)
        
        img_x = x0 + (cell_w - 32 - thumb_w) // 2
        img_y = y0 + 24
        overview.paste(mockup_thumb, (img_x, img_y), mockup_thumb)
        
        zh_title = name.split(" (")[0]
        en_title = name.split(" (")[1].replace(")", "") if "(" in name else ""
        
        draw.text((x0 + 28, y0 + 524), zh_title, fill=DARK_INK, font=font_item)
        draw.text((x0 + 28, y0 + 560), f"分组: {group}  |  {en_title}", fill=(107, 98, 91, 255), font=font_sub)
        
        if is_pro:
            draw.rounded_rectangle([x1 - 70, y0 + 16, x1 - 16, y0 + 44], radius=6, fill=TERRACOTTA)
            draw.text((x1 - 58, y0 + 20), "PRO", fill=(255, 255, 255, 255), font=font_badge)
        else:
            draw.rounded_rectangle([x1 - 70, y0 + 16, x1 - 16, y0 + 44], radius=6, fill=(242, 239, 234, 255))
            draw.text((x1 - 58, y0 + 20), "FREE", fill=(107, 98, 91, 255), font=font_badge)

    overview_path = OUTPUT_DIR / "frames_overview.png"
    overview.save(overview_path, "PNG", optimize=True)
    print(f"\n全部 6 款相框设计稿与总览图生成完毕！输出目录: {OUTPUT_DIR}")


if __name__ == "__main__":
    main()
