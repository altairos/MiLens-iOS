#!/usr/bin/env python3
"""MiLens 逼真物理画框（Realistic Physical Gallery Frames）渲染引擎。

基于现实中美学画廊画框（实木胡桃木、拉丝黄铜、法式金箔浮雕、极简黑铝、橡木亚麻卡纸、暖冬松木），
利用光照法线渲染立体阶梯型材、45度斜切拼接缝、45度斜切卡纸与照片投射阴影。
输出 1200x1600 超高精度透明画框，并生成带有真实照片叠加效果的画廊展示图。
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

W, H = 1200, 1600  # 3:4 画框标准尺寸


# --------------------------------------------------------------------------- #
# 光照与材质辅助函数
# --------------------------------------------------------------------------- #

def create_miter_mask(width: int, height: int, border: int) -> np.ndarray:
    """生成 4 个象限的 45度角拼接区域掩码 (0: Top, 1: Bottom, 2: Left, 3: Right)"""
    y, x = np.mgrid[0:height, 0:width]
    # 对角线比较
    diag1 = y * width - x * height       # Top-Left to Bottom-Right
    diag2 = (height - 1 - y) * width - x * height # Bottom-Left to Top-Right
    
    top_mask = (y < border) & (diag1 < 0) & (diag2 > 0)
    bottom_mask = (y >= height - border) & (diag1 > 0) & (diag2 < 0)
    left_mask = (x < border) & (diag1 >= 0) & (diag2 >= 0)
    right_mask = (x >= width - border) & (diag1 <= 0) & (diag2 <= 0)
    
    return top_mask, bottom_mask, left_mask, right_mask


def render_molding_relief(
    width: int,
    height: int,
    outer_w: int,
    profile_heights: list[float], # 0.0 ~ 1.0 的高度剖面
    base_color: tuple[int, int, int],
    metallic: bool = False,
    grain_texture: np.ndarray | None = None
) -> Image.Image:
    """根据型材高度曲线和光源方向 (左上 135度) 渲染逼真的 3D 物理外框"""
    img = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    arr = np.zeros((height, width, 4), dtype=np.float32)
    
    y, x = np.mgrid[0:height, 0:width]
    
    # 到 4 个外边缘的距离
    d_top = y
    d_bottom = height - 1 - y
    d_left = x
    d_right = width - 1 - x
    d_outer = np.minimum(np.minimum(d_top, d_bottom), np.minimum(d_left, d_right))
    
    # 仅在外框区域渲染
    in_frame = (d_outer < outer_w)
    
    # 归一化距离 0.0 (最外) ~ 1.0 (最内)
    norm_d = np.clip(d_outer / float(outer_w), 0.0, 1.0)
    
    # 插值计算型材高度
    num_p = len(profile_heights)
    indices = norm_d * (num_p - 1)
    idx_low = np.floor(indices).astype(int)
    idx_high = np.ceil(indices).astype(int)
    t = indices - idx_low
    
    p_arr = np.array(profile_heights, dtype=np.float32)
    h_map = p_arr[idx_low] * (1.0 - t) + p_arr[idx_high] * t
    
    # 计算梯度 (法线)
    # 光源在左上方 (-0.6, -0.6, 0.8)
    top_m, bot_m, left_m, right_m = create_miter_mask(width, height, outer_w)
    
    # 根据朝向计算光照阴影
    light = np.zeros((height, width), dtype=np.float32)
    
    # 顶部向光 (明亮)
    slope_top = np.gradient(h_map, axis=0)
    light[top_m] = 0.95 - slope_top[top_m] * 3.5
    
    # 底部背光 (较暗)
    slope_bot = -np.gradient(h_map, axis=0)
    light[bot_m] = 0.65 - slope_bot[bot_m] * 3.5
    
    # 左侧向光 (最亮)
    slope_left = np.gradient(h_map, axis=1)
    light[left_m] = 1.05 - slope_left[left_m] * 4.0
    
    # 右侧背光 (较暗)
    slope_right = -np.gradient(h_map, axis=1)
    light[right_m] = 0.60 - slope_right[right_m] * 4.0
    
    if metallic:
        # 金属光泽具有强高光反射
        light = np.power(np.clip(light, 0.1, 2.0), 1.35)
    else:
        light = np.clip(light, 0.35, 1.35)
        
    for c in range(3):
        col = base_color[c] * light
        if grain_texture is not None:
            col = col * (0.88 + 0.24 * grain_texture)
        arr[:, :, c] = np.clip(col, 0, 255)
        
    arr[:, :, 3] = np.where(in_frame, 255, 0)
    
    # 45度拼接缝 (Miter joints)
    res_img = Image.fromarray(arr.astype(np.uint8))
    draw = ImageDraw.Draw(res_img)
    seam_col = (int(base_color[0]*0.4), int(base_color[1]*0.4), int(base_color[2]*0.4), 255)
    highlight_col = (int(min(255, base_color[0]*1.4)), int(min(255, base_color[1]*1.4)), int(min(255, base_color[2]*1.4)), 180)
    
    # 四角拼接缝
    draw.line([(0, 0), (outer_w, outer_w)], fill=seam_col, width=2)
    draw.line([(1, 0), (outer_w + 1, outer_w)], fill=highlight_col, width=1)
    
    draw.line([(width, 0), (width - outer_w, outer_w)], fill=seam_col, width=2)
    draw.line([(width - 1, 0), (width - outer_w - 1, outer_w)], fill=highlight_col, width=1)
    
    draw.line([(0, height), (outer_w, height - outer_w)], fill=seam_col, width=2)
    draw.line([(width, height), (width - outer_w, height - outer_w)], fill=seam_col, width=2)
    
    return res_img


def add_matboard_and_shadows(
    frame_img: Image.Image,
    outer_w: int,
    mat_w: int,
    mat_color: tuple[int, int, int] = (248, 245, 238),
    mat_texture_grain: float = 0.05
) -> Image.Image:
    """在画框内侧添加 45度斜切卡纸 (Matboard) 和向内部照片投射的逼真环境阴影"""
    W, H = frame_img.size
    total_w = outer_w + mat_w
    win_x0, win_y0 = total_w, total_w
    win_x1, win_y1 = W - total_w, H - total_w
    
    mat_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(mat_layer)
    
    # 1. 绘制卡纸平面 (在 outer_w 到 total_w 之间)
    mat_x0, mat_y0 = outer_w, outer_w
    mat_x1, mat_y1 = W - outer_w, H - outer_w
    draw.rectangle([mat_x0, mat_y0, mat_x1, mat_y1], fill=(*mat_color, 255))
    
    # 卡纸微棉麻纸质颗粒感
    if mat_texture_grain > 0:
        mat_arr = np.array(mat_layer, dtype=np.float32)
        noise = np.random.normal(1.0, mat_texture_grain, (H, W, 1))
        mat_arr[:, :, :3] = np.clip(mat_arr[:, :, :3] * noise, 0, 255)
        mat_layer = Image.fromarray(mat_arr.astype(np.uint8))
        draw = ImageDraw.Draw(mat_layer)
        
    # 外框对卡纸的投射内阴影 (Outer frame cast shadow onto mat)
    draw.line([(mat_x0, mat_y0), (mat_x1, mat_y0)], fill=(0, 0, 0, 60), width=4)
    draw.line([(mat_x0, mat_y0), (mat_x0, mat_y1)], fill=(0, 0, 0, 60), width=4)
    draw.line([(mat_x0, mat_y0 + 4), (mat_x1, mat_y0 + 4)], fill=(0, 0, 0, 30), width=3)
    draw.line([(mat_x0 + 4, mat_y0), (mat_x0 + 4, mat_y1)], fill=(0, 0, 0, 30), width=3)

    # 2. 45度斜切内口 (Beveled Cut Edge)
    # 左上斜切面受光呈纯白高光，右下斜切面背光呈浅灰阴影
    draw.line([(win_x0 - 4, win_y0 - 4), (win_x1 + 4, win_y0 - 4)], fill=(255, 255, 255, 255), width=3)
    draw.line([(win_x0 - 4, win_y0 - 4), (win_x0 - 4, win_y1 + 4)], fill=(255, 255, 255, 255), width=3)
    
    draw.line([(win_x0 - 4, win_y1 + 4), (win_x1 + 4, win_y1 + 4)], fill=(190, 185, 175, 255), width=3)
    draw.line([(win_x1 + 4, win_y0 - 4), (win_x1 + 4, win_y1 + 4)], fill=(190, 185, 175, 255), width=3)
    
    # 3. 镂空中央视窗
    mat_arr = np.array(mat_layer)
    mat_arr[win_y0:win_y1, win_x0:win_x1, 3] = 0
    mat_clean = Image.fromarray(mat_arr)
    
    # 4. 合成外框与卡纸
    combined = Image.alpha_composite(mat_clean, frame_img)
    
    # 5. 照片投射落差内阴影 (Deep Inner Drop Shadow on artwork)
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    sdraw = ImageDraw.Draw(shadow)
    
    # 顶部与左侧向内部照片投射自然渐变软阴影
    shadow_depth = 28
    sdraw.rectangle([win_x0, win_y0, win_x1, win_y0 + shadow_depth], fill=(0, 0, 0, 100))
    sdraw.rectangle([win_x0, win_y0, win_x0 + shadow_depth, win_y1], fill=(0, 0, 0, 100))
    shadow = shadow.filter(ImageFilter.GaussianBlur(10))
    
    # 限制阴影仅出现在照片区域 (防止溢出卡纸)
    s_arr = np.array(shadow)
    mask_outside = np.ones((H, W), dtype=bool)
    mask_outside[win_y0:win_y1, win_x0:win_x1] = False
    s_arr[mask_outside, 3] = 0
    shadow_clean = Image.fromarray(s_arr)
    
    # 最终叠合
    final_frame = Image.alpha_composite(shadow_clean, combined)
    return final_frame


# --------------------------------------------------------------------------- #
# 6 款物理画框具体设计与生成
# --------------------------------------------------------------------------- #

def gen_antique_brass_frame() -> Image.Image:
    """1. 典雅拉丝黄铜画框 (frame_antique_brass) - 推荐组 · 免费"""
    outer_w = 90
    mat_w = 110
    
    # 多层阶梯凸弧黄铜型材 (Cove & Bead Brass Profile)
    profile = [0.0, 0.45, 0.85, 1.0, 0.92, 0.70, 0.40, 0.65, 0.85, 0.50, 0.15, 0.0]
    
    # 细腻拉丝金属纹理
    y, x = np.mgrid[0:H, 0:W]
    brass_grain = np.sin(x * 0.4 + y * 0.1) * 0.05 + np.random.normal(0, 0.04, (H, W))
    
    # 美术馆古董黄铜色 #C89648
    base_color = (205, 155, 78)
    frame_molding = render_molding_relief(W, H, outer_w, profile, base_color, metallic=True, grain_texture=brass_grain)
    
    # 装饰珍珠珠边 (Beaded Trim at inner edge)
    fdraw = ImageDraw.Draw(frame_molding)
    bead_inset = outer_w - 12
    bead_r = 4
    # 四边小圆珠装饰
    for bx in range(outer_w + 10, W - outer_w - 10, 16):
        fdraw.ellipse([bx - bead_r, bead_inset - bead_r, bx + bead_r, bead_inset + bead_r], fill=(240, 200, 120, 255))
        fdraw.ellipse([bx - bead_r, H - bead_inset - bead_r, bx + bead_r, H - bead_inset + bead_r], fill=(160, 110, 45, 255))
    for by in range(outer_w + 10, H - outer_w - 10, 16):
        fdraw.ellipse([bead_inset - bead_r, by - bead_r, bead_inset + bead_r, by + bead_r], fill=(240, 200, 120, 255))
        fdraw.ellipse([W - bead_inset - bead_r, by - bead_r, W - bead_inset + bead_r, by + bead_r], fill=(160, 110, 45, 255))
        
    return add_matboard_and_shadows(frame_molding, outer_w, mat_w, mat_color=(250, 247, 240), mat_texture_grain=0.03)


def gen_vintage_walnut_frame() -> Image.Image:
    """2. 复古深色胡桃实木画框 (frame_vintage_walnut) - 胶片/经典组 · 免费"""
    outer_w = 110
    mat_w = 90
    
    # 优雅斜切实木造型 (Slanted Chamfer Wood Profile)
    profile = [0.1, 0.4, 0.7, 0.95, 0.85, 0.65, 0.45, 0.3, 0.2, 0.0]
    
    # 木材生长年轮与管孔纹理 (Procedural Walnut Wood Grain)
    y, x = np.mgrid[0:H, 0:W]
    wood_grain = np.sin((x + y*0.15) * 0.04) * 0.2 + np.sin((y - x*0.1) * 0.08) * 0.15 + np.random.normal(0, 0.08, (H, W))
    
    # 深沉胡桃木色 #4A2E1B
    base_color = (74, 46, 27)
    frame_molding = render_molding_relief(W, H, outer_w, profile, base_color, metallic=False, grain_texture=wood_grain)
    
    # 内圈极细金箔线 (Gilt Lip)
    fdraw = ImageDraw.Draw(frame_molding)
    lip_pos = outer_w - 6
    fdraw.rectangle([lip_pos, lip_pos, W - lip_pos, H - lip_pos], outline=(195, 145, 65, 220), width=3)
    
    return add_matboard_and_shadows(frame_molding, outer_w, mat_w, mat_color=(246, 242, 234), mat_texture_grain=0.04)


def gen_minimalist_gallery_frame() -> Image.Image:
    """3. 现代极简哑光黑铝画框 (frame_minimalist_gallery) - 胶片/现代组 · 免费"""
    outer_w = 48   # 现代超窄边框
    mat_w = 152    # 超宽画廊留白卡纸，突出照片主体
    
    # 极简直角型材 (Minimal Flat Edge)
    profile = [0.0, 0.9, 0.95, 0.95, 0.95, 0.9, 0.0]
    
    # 哑光黑色 #1C1A18
    base_color = (32, 30, 28)
    frame_molding = render_molding_relief(W, H, outer_w, profile, base_color, metallic=False)
    
    return add_matboard_and_shadows(frame_molding, outer_w, mat_w, mat_color=(252, 250, 246), mat_texture_grain=0.02)


def gen_baroque_gilded_frame() -> Image.Image:
    """4. 法式金箔巴洛克雕花画框 (frame_baroque_gilded) - 典藏组 · Pro 专属"""
    outer_w = 130
    mat_w = 80
    
    # 奢华深起伏巴洛克型材 (High Relief Baroque Profile)
    profile = [0.0, 0.3, 0.7, 1.0, 0.8, 0.5, 0.85, 1.1, 0.7, 0.3, 0.6, 0.2, 0.0]
    
    # 做旧金箔斑驳反光 (Aged Gilded Leaf Texture)
    y, x = np.mgrid[0:H, 0:W]
    gold_flake = np.sin(x * 0.15) * np.cos(y * 0.15) * 0.15 + np.random.normal(0, 0.12, (H, W))
    
    # 宫廷复古金箔色 #D4AF37
    base_color = (212, 175, 55)
    frame_molding = render_molding_relief(W, H, outer_w, profile, base_color, metallic=True, grain_texture=gold_flake)
    
    # 四角巴洛克毛茛叶雕花饰纹 (Carved Corner Foliage Ornaments)
    fdraw = ImageDraw.Draw(frame_molding)
    ornament_size = 90
    
    def draw_baroque_corner(cx, cy, flip_x, flip_y):
        # 优雅藤蔓涡卷多边形
        pts = [
            (cx, cy),
            (cx + 40*flip_x, cy + 15*flip_y),
            (cx + 70*flip_x, cy + 30*flip_y),
            (cx + 85*flip_x, cy + 60*flip_y),
            (cx + 65*flip_x, cy + 75*flip_y),
            (cx + 35*flip_x, cy + 55*flip_y),
            (cx + 15*flip_x, cy + 40*flip_y),
        ]
        fdraw.polygon(pts, fill=(245, 215, 110, 255), outline=(150, 105, 30, 255))
        # 叶脉雕刻
        fdraw.line([(cx, cy), (cx + 65*flip_x, cy + 55*flip_y)], fill=(130, 85, 20, 255), width=2)
        # 凸起圆宝珠
        fdraw.ellipse([cx + 40*flip_x - 8, cy + 40*flip_y - 8, cx + 40*flip_x + 8, cy + 40*flip_y + 8], fill=(255, 235, 150, 255))

    draw_baroque_corner(20, 20, 1, 1)
    draw_baroque_corner(W - 20, 20, -1, 1)
    draw_baroque_corner(20, H - 20, 1, -1)
    draw_baroque_corner(W - 20, H - 20, -1, -1)

    return add_matboard_and_shadows(frame_molding, outer_w, mat_w, mat_color=(245, 240, 230), mat_texture_grain=0.04)


def gen_warm_oak_linen_frame() -> Image.Image:
    """5. 原木橡木粗亚麻布衬画框 (frame_warm_oak_linen) - 典藏组 · Pro 专属"""
    outer_w = 95
    mat_w = 115
    
    # 质朴圆润原木型材 (Soft Rounded Oak Profile)
    profile = [0.1, 0.5, 0.85, 1.0, 0.95, 0.85, 0.7, 0.5, 0.3, 0.0]
    
    # 白橡木浅色木纹 (Light Oak Wood Grain)
    y, x = np.mgrid[0:H, 0:W]
    oak_grain = np.sin((y*0.8 + x*0.2) * 0.05) * 0.2 + np.random.normal(0, 0.05, (H, W))
    
    # 温润原木色 #B88B58
    base_color = (184, 139, 88)
    frame_molding = render_molding_relief(W, H, outer_w, profile, base_color, metallic=False, grain_texture=oak_grain)
    
    # 粗织亚麻布衬卡纸 (Rich Textured Linen Mat)
    return add_matboard_and_shadows(frame_molding, outer_w, mat_w, mat_color=(236, 228, 214), mat_texture_grain=0.09)


def gen_holiday_pine_frame() -> Image.Image:
    """6. 暖冬手作松木画框 (frame_holiday_pine) - 节日组 · Pro 专属"""
    outer_w = 100
    mat_w = 100
    
    # 复古松木造型 (Rustic Pine Profile)
    profile = [0.15, 0.6, 0.9, 0.95, 0.75, 0.5, 0.35, 0.2, 0.0]
    
    # 温暖深松木色 #6E3F24
    base_color = (110, 63, 36)
    frame_molding = render_molding_relief(W, H, outer_w, profile, base_color, metallic=False)
    
    # 绘制画框四角的微型黄铜角件与松枝红果点缀
    fdraw = ImageDraw.Draw(frame_molding)
    bracket_size = 50
    corners = [(10, 10, 1, 1), (W - 10, 10, -1, 1), (10, H - 10, 1, -1), (W - 10, H - 10, -1, -1)]
    
    for cx, cy, fx, fy in corners:
        # 黄铜角包片
        fdraw.polygon([(cx, cy), (cx + bracket_size*fx, cy), (cx + bracket_size*fx, cy + 16*fy), (cx + 16*fx, cy + 16*fy), (cx + 16*fx, cy + bracket_size*fy), (cx, cy + bracket_size*fy)], fill=(210, 165, 75, 255))
        # 铆钉圆点
        fdraw.ellipse([cx + 8*fx - 3, cy + 8*fy - 3, cx + 8*fx + 3, cy + 8*fy + 3], fill=(120, 80, 30, 255))
        fdraw.ellipse([cx + 36*fx - 3, cy + 8*fy - 3, cx + 36*fx + 3, cy + 8*fy + 3], fill=(120, 80, 30, 255))
        fdraw.ellipse([cx + 8*fx - 3, cy + 36*fy - 3, cx + 8*fx + 3, cy + 36*fy + 3], fill=(120, 80, 30, 255))

    return add_matboard_and_shadows(frame_molding, outer_w, mat_w, mat_color=(248, 245, 238), mat_texture_grain=0.03)


# --------------------------------------------------------------------------- #
# 主控流程
# --------------------------------------------------------------------------- #

FRAMES_CONFIG = [
    ("frame_antique_brass", "典雅拉丝黄铜画框 (Antique Brass)", "recommended", False, gen_antique_brass_frame),
    ("frame_vintage_walnut", "复古深胡桃木画框 (Vintage Walnut)", "film", False, gen_vintage_walnut_frame),
    ("frame_minimalist_gallery", "现代极简黑铝画框 (Minimalist Charcoal)", "film", False, gen_minimalist_gallery_frame),
    ("frame_baroque_gilded", "法式金箔巴洛克雕花框 (Baroque Gilded)", "paper", True, gen_baroque_gilded_frame),
    ("frame_warm_oak_linen", "原木橡木亚麻布衬框 (Warm Oak & Linen)", "paper", True, gen_warm_oak_linen_frame),
    ("frame_holiday_pine", "暖冬手作松木画框 (Rustic Pine)", "holiday", True, gen_holiday_pine_frame),
]


def main():
    print("开始生成 MiLens 现实画廊物理画框（Realistic Gallery Frames）...")
    
    # 创建高质量测试照片 (安睡小生灵)
    sample_photo = Image.new("RGBA", (W, H), (242, 236, 226, 255))
    sdraw = ImageDraw.Draw(sample_photo)
    for y in range(H):
        t = y / H
        sdraw.line([(0, y), (W, y)], fill=(int(248 - 30*t), int(238 - 35*t), int(224 - 40*t), 255))
    
    cat_src = BRAIN_DIR / "sleepy_moon_sticker_1787316716106.jpg"
    if cat_src.exists():
        cat_img = Image.open(cat_src).resize((760, 760), Image.Resampling.LANCZOS)
        sample_photo.paste(cat_img, ((W - 760)//2, (H - 760)//2 - 20))

    # 1. 逐一渲染透明画框与实机套框效果图
    for fid, name, group, is_pro, generator in FRAMES_CONFIG:
        frame_png = generator()
        
        # 保存透明相框原图
        frame_out = OUTPUT_DIR / f"{fid}.png"
        frame_png.save(frame_out, "PNG", optimize=True)
        print(f"  [物理画框透明原图] {frame_out.name}")
        
        # 合成叠加照片的 Mockup
        mockup = sample_photo.copy()
        mockup.paste(frame_png, (0, 0), frame_png)
        mockup_out = OUTPUT_DIR / f"{fid}_mockup.png"
        mockup.save(mockup_out, "PNG", optimize=True)
        print(f"  [实机套框光影展示] {mockup_out.name}")

    # 2. 生成全景画廊总览大图 (Realistic Frames Overview Sheet)
    cols, rows = 3, 2
    cell_w, cell_h = 520, 720
    pad_x, pad_y = 60, 100
    total_w = pad_x * 2 + cols * cell_w
    total_h = pad_y + 120 + rows * cell_h + 40

    overview = Image.new("RGBA", (total_w, total_h), (250, 248, 245, 255)) # SurfaceCanvas
    draw = ImageDraw.Draw(overview)

    try:
        font_title = ImageFont.truetype("msyh.ttc", 44)
        font_sub = ImageFont.truetype("msyh.ttc", 22)
        font_item = ImageFont.truetype("msyh.ttc", 26)
        font_badge = ImageFont.truetype("msyh.ttc", 16)
    except Exception:
        font_title = font_sub = font_item = font_badge = ImageFont.load_default()

    draw.text((pad_x, 40), "MiLens · 现实画廊物理画框设计全览 (Realistic Physical Frames)", fill=(31, 27, 24, 255), font=font_title)
    draw.text((pad_x, 95), "3D 阶梯型材、45° 斜角拼接缝、斜切卡纸衬底与照片落差环境阴影，还原真实艺术画廊质感", fill=(107, 98, 91, 255), font=font_sub)

    for idx, (fid, name, group, is_pro, _) in enumerate(FRAMES_CONFIG):
        r = idx // cols
        c = idx % cols
        
        x0 = pad_x + c * cell_w + 16
        y0 = pad_y + 80 + r * cell_h + 16
        x1 = x0 + cell_w - 32
        y1 = y0 + cell_h - 32
        
        # 画卡片底
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
        
        draw.text((x0 + 28, y0 + 524), zh_title, fill=(31, 27, 24, 255), font=font_item)
        draw.text((x0 + 28, y0 + 560), f"分组: {group}  |  {en_title}", fill=(107, 98, 91, 255), font=font_sub)
        
        if is_pro:
            draw.rounded_rectangle([x1 - 70, y0 + 16, x1 - 16, y0 + 44], radius=6, fill=(188, 71, 39, 255))
            draw.text((x1 - 58, y0 + 20), "PRO", fill=(255, 255, 255, 255), font=font_badge)
        else:
            draw.rounded_rectangle([x1 - 70, y0 + 16, x1 - 16, y0 + 44], radius=6, fill=(242, 239, 234, 255))
            draw.text((x1 - 58, y0 + 20), "FREE", fill=(107, 98, 91, 255), font=font_badge)

    overview_out = OUTPUT_DIR / "realistic_frames_overview.png"
    overview.save(overview_out, "PNG", optimize=True)
    print(f"\n物理画框总览图生成完毕！路径: {overview_out}")


if __name__ == "__main__":
    main()
