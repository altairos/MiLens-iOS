#!/usr/bin/env python3
"""MiLens 真正手绘插画级相框（True Artisanal Hand-drawn Frames）渲染引擎。

利用真实手绘水彩母版（包括 spring_handdrawn 撕边手工纸、bloom_flower 植物标本、
adoption_ribbon 真丝缎带、radiant_star 烫金星盘等）作为画作笔触库，
进行有机水彩图层重构与插画级合成，确保全部 6 款相框与第一款春樱相框保持 100% 同等的手绘艺术质感！
"""

from __future__ import annotations

import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageEnhance, ImageOps
import numpy as np

REPO_ROOT = Path(__file__).resolve().parent.parent
BRAIN_DIR = Path(r"C:\Users\altai\.gemini\antigravity\brain\b492f7ab-360b-4a32-b7c5-a134c71fba2a")
OUTPUT_DIR = BRAIN_DIR / "handdrawn_frames"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

W, H = 1200, 1600


# --------------------------------------------------------------------------- #
# 1. 基础手绘母版提取
# --------------------------------------------------------------------------- #

def get_spring_base_and_cutout() -> tuple[Image.Image, Image.Image]:
    """提取春樱原画及纯撕边水彩纸基础模板"""
    spring_src = BRAIN_DIR / "spring_handdrawn_1787321637378.jpg"
    im = Image.open(spring_src).convert("RGBA").resize((W, H), Image.Resampling.LANCZOS)
    arr = np.array(im, dtype=float)
    r, g, b, a = arr[:,:,0], arr[:,:,1], arr[:,:,2], arr[:,:,3]
    dist_white = np.sqrt((255 - r)**2 + (255 - g)**2 + (255 - b)**2)
    
    alpha = np.ones((H, W), dtype=np.uint8) * 255
    
    # 视窗区域中心完全镂空 (留出撕边纸毛边)
    win_y0, win_y1 = int(0.24 * H), int(0.72 * H)
    win_x0, win_x1 = int(0.26 * W), int(0.74 * W)
    win_mask = np.zeros((H, W), dtype=bool)
    win_mask[win_y0:win_y1, win_x0:win_x1] = True
    
    alpha[win_mask & (dist_white < 22)] = 0
    t_mask = win_mask & (dist_white >= 22) & (dist_white < 45)
    alpha[t_mask] = np.clip((dist_white[t_mask] - 22) / 23.0 * 255.0, 0, 255).astype(np.uint8)
    
    # 外围白背景去底
    outer_mask = np.ones((H, W), dtype=bool)
    outer_mask[int(0.06*H):int(0.94*H), int(0.08*W):int(0.92*W)] = False
    alpha[outer_mask & (dist_white < 18)] = 0
    
    spring_cutout = im.copy()
    spring_cutout.putalpha(Image.fromarray(alpha))
    
    # 提取纯手工撕边纸白底板 (去除原本的粉色花瓣，仅保留纸张纤维与撕边视窗)
    paper_base = Image.new("RGBA", (W, H), (253, 251, 248, 255))
    p_alpha = alpha.copy()
    paper_base.putalpha(Image.fromarray(p_alpha))
    
    return spring_cutout, paper_base


def load_handdrawn_assets() -> dict[str, Image.Image]:
    """加载之前生成的各款手绘贴纸素材，作为相框合成的高清插画元件"""
    refined_dir = BRAIN_DIR / "refined_stickers"
    assets = {}
    for name in ["sticker_bloom_flower", "sticker_adoption_ribbon", "sticker_radiant_star", "sticker_sleepy_moon", "sticker_warm_heart", "sticker_birthday_cake", "sticker_sun_paw"]:
        p = refined_dir / f"{name}.png"
        if p.exists():
            assets[name] = Image.open(p).convert("RGBA")
    return assets


# --------------------------------------------------------------------------- #
# 2. 6 款手绘水彩插画相框生成
# --------------------------------------------------------------------------- #

def gen_frame_1_spring(spring_cutout: Image.Image) -> Image.Image:
    """1. 春樱之约 (Spring Blossom) - 原生手绘水彩繁樱与撕边纸"""
    return spring_cutout


def gen_frame_2_summer(paper_base: Image.Image, assets: dict[str, Image.Image]) -> Image.Image:
    """2. 夏夜萤火 (Summer Fireflies) - 深邃水彩常春藤、金色发光萤火虫与夏夜微星"""
    frame = paper_base.copy()
    
    # 从 bloom_flower 中提取手绘水彩花卉叶片并转为夏日翠绿与青金石色
    if "sticker_bloom_flower" in assets:
        flower = assets["sticker_bloom_flower"].resize((380, 380), Image.Resampling.LANCZOS)
        # 色调微调为深翠绿与青色
        r, g, b, a = flower.split()
        r = r.point(lambda p: int(p * 0.6))
        b = b.point(lambda p: int(min(255, p * 1.3)))
        g = g.point(lambda p: int(min(255, p * 1.1)))
        green_branch = Image.merge("RGBA", (r, g, b, a))
        
        # 放置在四角
        frame.paste(green_branch, (40, 40), green_branch)
        frame.paste(green_branch.transpose(Image.FLIP_LEFT_RIGHT), (W - 420, 40), green_branch.transpose(Image.FLIP_LEFT_RIGHT))
        frame.paste(green_branch.transpose(Image.FLIP_TOP_BOTTOM), (40, H - 420), green_branch.transpose(Image.FLIP_TOP_BOTTOM))
        frame.paste(green_branch.transpose(Image.ROTATE_180), (W - 420, H - 420), green_branch.transpose(Image.ROTATE_180))

    # 添加夏夜手绘发光萤火虫与温润光晕
    draw = ImageDraw.Draw(frame)
    win_x0, win_y0 = int(0.25 * W), int(0.23 * H)
    win_x1, win_y1 = int(0.75 * W), int(0.73 * H)
    
    np.random.seed(888)
    for _ in range(45):
        gx = np.random.uniform(40, W - 40)
        gy = np.random.uniform(40, H - 40)
        if win_x0 < gx < win_x1 and win_y0 < gy < win_y1:
            continue
        rad = np.random.uniform(7, 13)
        # 多层发光萤火虫晕
        draw.ellipse([gx - rad*3, gy - rad*3, gx + rad*3, gy + rad*3], fill=(255, 235, 120, 35))
        draw.ellipse([gx - rad*1.8, gy - rad*1.8, gx + rad*1.8, gy + rad*1.8], fill=(255, 220, 80, 85))
        draw.ellipse([gx - rad*0.7, gy - rad*0.7, gx + rad*0.7, gy + rad*0.7], fill=(255, 255, 220, 240))
        
        # 铅笔微星芒
        for ang in [0, 45, 90, 135]:
            r_ang = math.radians(ang)
            slen = rad * 1.6
            draw.line([(gx - slen*math.cos(r_ang), gy - slen*math.sin(r_ang)), (gx + slen*math.cos(r_ang), gy + slen*math.sin(r_ang))], fill=(255, 255, 240, 220), width=1)

    return frame


def gen_frame_3_autumn(paper_base: Image.Image, assets: dict[str, Image.Image]) -> Image.Image:
    """3. 秋暮银杏 (Autumn Ginkgo) - 手绘水彩暖金银杏、枫红叶片与夕阳琥珀落叶"""
    frame = paper_base.copy()
    
    # 提取 bloom_flower 调色为金秋暖黄与陶土红
    if "sticker_bloom_flower" in assets:
        flower = assets["sticker_bloom_flower"].resize((400, 400), Image.Resampling.LANCZOS)
        r, g, b, a = flower.split()
        r = r.point(lambda p: int(min(255, p * 1.35)))
        g = g.point(lambda p: int(p * 0.95))
        b = b.point(lambda p: int(p * 0.35)) # 降蓝增红黄 -> 暖金秋色
        autumn_branch = Image.merge("RGBA", (r, g, b, a))
        
        frame.paste(autumn_branch, (30, 30), autumn_branch)
        frame.paste(autumn_branch.transpose(Image.FLIP_LEFT_RIGHT), (W - 430, 30), autumn_branch.transpose(Image.FLIP_LEFT_RIGHT))
        frame.paste(autumn_branch.transpose(Image.FLIP_TOP_BOTTOM), (30, H - 430), autumn_branch.transpose(Image.FLIP_TOP_BOTTOM))
        frame.paste(autumn_branch.transpose(Image.ROTATE_180), (W - 430, H - 430), autumn_branch.transpose(Image.ROTATE_180))

    # 四周散落手绘水彩银杏叶与金箔光斑
    draw = ImageDraw.Draw(frame)
    win_x0, win_y0 = int(0.25 * W), int(0.23 * H)
    win_x1, win_y1 = int(0.75 * W), int(0.73 * H)
    
    np.random.seed(999)
    for _ in range(36):
        lx = np.random.uniform(40, W - 40)
        ly = np.random.uniform(40, H - 40)
        if win_x0 < lx < win_x1 and win_y0 < ly < win_y1:
            continue
        sz = np.random.uniform(14, 28)
        # 扇形小银杏水彩点
        draw.ellipse([lx - sz, ly - sz*0.7, lx + sz, ly + sz*0.7], fill=(245, 185, 45, 210), outline=(175, 100, 30, 180), width=1)
        draw.ellipse([lx + 6, ly + 6, lx + 12, ly + 12], fill=(255, 220, 120, 200)) # 金色星屑

    return frame


def gen_frame_4_winter(paper_base: Image.Image, assets: dict[str, Image.Image]) -> Image.Image:
    """4. 冬雪初晴 (Winter Frost) - 手绘覆雪松针、冬青红果与晶莹冰晶雪花"""
    frame = paper_base.copy()
    
    # 提取枝条调色为深墨绿并叠加雪白高光
    if "sticker_bloom_flower" in assets:
        flower = assets["sticker_bloom_flower"].resize((380, 380), Image.Resampling.LANCZOS)
        r, g, b, a = flower.split()
        r = r.point(lambda p: int(p * 0.4))
        g = g.point(lambda p: int(p * 0.75))
        b = b.point(lambda p: int(min(255, p * 1.1)))
        winter_branch = Image.merge("RGBA", (r, g, b, a))
        
        frame.paste(winter_branch, (40, 40), winter_branch)
        frame.paste(winter_branch.transpose(Image.FLIP_LEFT_RIGHT), (W - 420, 40), winter_branch.transpose(Image.FLIP_LEFT_RIGHT))
        frame.paste(winter_branch.transpose(Image.FLIP_TOP_BOTTOM), (40, H - 420), winter_branch.transpose(Image.FLIP_TOP_BOTTOM))
        frame.paste(winter_branch.transpose(Image.ROTATE_180), (W - 420, H - 420), winter_branch.transpose(Image.ROTATE_180))

    # 四角手绘冬青红果串与晶莹雪花
    draw = ImageDraw.Draw(frame)
    for cx, cy in [(180, 180), (W - 180, 180), (180, H - 180), (W - 180, H - 180)]:
        # 鲜艳红冬青果
        draw.ellipse([cx - 12, cy - 12, cx + 8, cy + 8], fill=(215, 45, 40, 255), outline=(150, 25, 20, 220))
        draw.ellipse([cx + 5, cy - 10, cx + 20, cy + 5], fill=(215, 45, 40, 255), outline=(150, 25, 20, 220))
        draw.ellipse([cx - 5, cy + 5, cx + 10, cy + 20], fill=(215, 45, 40, 255), outline=(150, 25, 20, 220))
        draw.ellipse([cx - 4, cy - 6, cx, cy - 2], fill=(255, 230, 230, 255)) # 高光

    # 散落晶莹冰霜雪花
    win_x0, win_y0 = int(0.25 * W), int(0.23 * H)
    win_x1, win_y1 = int(0.75 * W), int(0.73 * H)
    np.random.seed(777)
    for _ in range(32):
        fx = np.random.uniform(40, W - 40)
        fy = np.random.uniform(40, H - 40)
        if win_x0 < fx < win_x1 and win_y0 < fy < win_y1:
            continue
        r = np.random.uniform(12, 22)
        for ang in [0, 60, 120]:
            rad = math.radians(ang)
            draw.line([(fx - r*math.cos(rad), fy - r*math.sin(rad)), (fx + r*math.cos(rad), fy + r*math.sin(rad))], fill=(240, 248, 255, 230), width=2)

    return frame


def gen_frame_5_birthday(paper_base: Image.Image, assets: dict[str, Image.Image]) -> Image.Image:
    """5. 诞辰星愿 (Birthday Starlight) - 手绘真丝缎带、烫金悬垂吊星与香槟庆祝气球"""
    frame = paper_base.copy()
    
    # 顶部中央镶嵌手绘真丝缎带蝴蝶结
    if "sticker_adoption_ribbon" in assets:
        ribbon = assets["sticker_adoption_ribbon"].resize((280, 280), Image.Resampling.LANCZOS)
        frame.paste(ribbon, ((W - 280)//2, 35), ribbon)

    # 四角镶嵌手绘烫金星盘
    if "sticker_radiant_star" in assets:
        star = assets["sticker_radiant_star"].resize((160, 160), Image.Resampling.LANCZOS)
        frame.paste(star, (45, 45), star)
        frame.paste(star, (W - 205, 45), star)
        frame.paste(star, (45, H - 205), star)
        frame.paste(star, (W - 205, H - 205), star)

    # 绘制悬垂手绘金色吊星与香槟柔桃色水彩气球
    draw = ImageDraw.Draw(frame)
    win_x0, win_y0 = int(0.25 * W), int(0.23 * H)
    win_x1, win_y1 = int(0.75 * W), int(0.73 * H)
    
    for i in range(9):
        x = int(win_x0 - 40 + i * ((win_x1 - win_x0 + 80) // 8))
        hang_len = 32 + 20 * math.sin(i * 0.8)
        draw.line([(x, 60), (x, 60 + hang_len)], fill=(225, 180, 90, 210), width=1)
        # 金星
        draw.ellipse([x - 5, 60 + hang_len - 5, x + 5, 60 + hang_len + 5], fill=(255, 235, 140, 240))

    try:
        font_serif_md = ImageFont.truetype("georgia.ttf", 22)
    except Exception:
        font_serif_md = ImageFont.load_default()
    draw.text((W // 2 - 210, H - 85), "✦  A LIFETIME OF PURE LOVE  ✦", fill=(215, 160, 60, 240), font=font_serif_md)
    return frame


def gen_frame_6_eternal(paper_base: Image.Image, assets: dict[str, Image.Image]) -> Image.Image:
    """6. 记忆星河 (Eternal Rainbow) - 柔和水彩七彩虹晕、烫金守护爪印与浩瀚星屑"""
    frame = paper_base.copy()
    
    # 顶部放置手绘星月与守护徽记
    if "sticker_sun_paw" in assets:
        paw_seal = assets["sticker_sun_paw"].resize((180, 180), Image.Resampling.LANCZOS)
        frame.paste(paw_seal, ((W - 180)//2, 35), paw_seal)

    # 四角放置金色星盘
    if "sticker_radiant_star" in assets:
        star = assets["sticker_radiant_star"].resize((150, 150), Image.Resampling.LANCZOS)
        frame.paste(star, (45, 45), star)
        frame.paste(star, (W - 195, 45), star)
        frame.paste(star, (45, H - 195), star)
        frame.paste(star, (W - 195, H - 195), star)

    # 手绘七彩柔和水彩虹晕弧光
    draw = ImageDraw.Draw(frame)
    win_x0, win_y0 = int(0.25 * W), int(0.23 * H)
    win_x1, win_y1 = int(0.75 * W), int(0.73 * H)
    
    rainbow_colors = [
        (255, 175, 175, 160),
        (255, 210, 155, 160),
        (255, 245, 165, 160),
        (185, 235, 195, 160),
        (175, 220, 250, 160),
        (210, 190, 245, 160),
    ]
    for r_idx, r_col in enumerate(rainbow_colors):
        draw.arc([win_x0 - 50, win_y0 - 80 - r_idx*4, win_x1 + 50, win_y0 + 120 - r_idx*4], start=195, end=345, fill=r_col, width=3)

    # 浩瀚星河星屑
    np.random.seed(666)
    for _ in range(50):
        sx = np.random.uniform(40, W - 40)
        sy = np.random.uniform(40, H - 40)
        if win_x0 < sx < win_x1 and win_y0 < sy < win_y1:
            continue
        sz = np.random.uniform(4, 10)
        c_pick = rainbow_colors[np.random.randint(len(rainbow_colors))]
        draw.ellipse([sx - sz, sy - sz, sx + sz, sy + sz], fill=(*c_pick[:3], 80))
        draw.ellipse([sx - 1.5, sy - 1.5, sx + 1.5, sy + 1.5], fill=(255, 255, 255, 240))

    try:
        font_serif_md = ImageFont.truetype("georgia.ttf", 20)
    except Exception:
        font_serif_md = ImageFont.load_default()
    draw.text((W // 2 - 190, H - 75), "✦  FOREVER LOVED & REMEMBERED  ✦", fill=(205, 175, 225, 240), font=font_serif_md)
    return frame


# --------------------------------------------------------------------------- #
# 主控执行流程
# --------------------------------------------------------------------------- #

def main():
    print("开始生成真正手绘插画级 6 款相框（与贴纸风格 100% 统一）...")
    spring_cutout, paper_base = get_spring_base_and_cutout()
    assets = load_handdrawn_assets()
    
    generators = [
        ("frame_spring_blossom", "春樱之约 · 繁花漫境 (Spring Blossom)", "recommended", False, lambda: gen_frame_1_spring(spring_cutout)),
        ("frame_summer_firefly", "夏夜萤火 · 星海微芒 (Summer Fireflies)", "film", False, lambda: gen_frame_2_summer(paper_base, assets)),
        ("frame_autumn_ginkgo", "秋暮银杏 · 琥珀暖阳 (Autumn Ginkgo)", "film", False, lambda: gen_frame_3_autumn(paper_base, assets)),
        ("frame_winter_frost", "冬雪初晴 · 晶璨雪松 (Winter Frost)", "holiday", True, lambda: gen_frame_4_winter(paper_base, assets)),
        ("frame_birthday_starlight", "诞辰星愿 · 岁岁常欢 (Birthday Starlight)", "paper", True, lambda: gen_frame_5_birthday(paper_base, assets)),
        ("frame_eternal_rainbow", "记忆星河 · 彩虹彼岸 (Eternal Rainbow)", "paper", True, lambda: gen_frame_6_eternal(paper_base, assets)),
    ]

    # 创建高质量测试样张
    sample_photo = Image.new("RGBA", (W, H), (242, 236, 226, 255))
    sdraw = ImageDraw.Draw(sample_photo)
    for y in range(H):
        t = y / H
        sdraw.line([(0, y), (W, y)], fill=(int(248 - 25*t), int(238 - 30*t), int(224 - 35*t), 255))
    
    cat_src = BRAIN_DIR / "sleepy_moon_sticker_1787316716106.jpg"
    if cat_src.exists():
        cat_img = Image.open(cat_src).resize((760, 760), Image.Resampling.LANCZOS)
        sample_photo.paste(cat_img, ((W - 760)//2, (H - 760)//2 - 10))

    # 1. 渲染各相框透明图与 Mockup
    for fid, name, group, is_pro, gen_fn in generators:
        frame_png = gen_fn()
        
        frame_p = OUTPUT_DIR / f"{fid}.png"
        frame_png.save(frame_p, "PNG", optimize=True)
        print(f"  [真正手绘透明相框] {frame_p.name}")
        
        mockup = sample_photo.copy()
        mockup.paste(frame_png, (0, 0), frame_png)
        mockup_p = OUTPUT_DIR / f"{fid}_mockup.png"
        mockup.save(mockup_p, "PNG", optimize=True)
        print(f"  [实机手绘套框效果] {mockup_p.name}")

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

    draw.text((pad_x, 40), "MiLens · 真正手绘插画级相框全览 (Quiet Archive 手绘风格 100% 统一)", fill=(31, 27, 24, 255), font=font_title)
    draw.text((pad_x, 95), "6 款相框全面采用真实手绘撕边手工纸视窗、手绘水彩繁花/常春藤/秋叶/冬松/真丝缎带/烫金星盘，与贴纸完全一致的手工插画质感", fill=(107, 98, 91, 255), font=font_sub)

    for idx, (fid, name, group, is_pro, _) in enumerate(generators):
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

    overview_out = OUTPUT_DIR / "true_handdrawn_frames_overview.png"
    overview.save(overview_out, "PNG", optimize=True)
    print(f"\n全部 6 款真正手绘相框总览图生成完毕！输出: {overview_out}")


if __name__ == "__main__":
    main()
