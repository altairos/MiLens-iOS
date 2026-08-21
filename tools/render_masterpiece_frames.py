#!/usr/bin/env python3
"""MiLens 大师级艺术构图相框（Masterpiece Artisanal Frames）渲染引擎。

彻底放弃规则九宫格与死板对称拼贴，采用非对称有机艺术构图（Asymmetrical Organic Composition），
充分调用真实手绘水彩原画（繁花、弯月安睡猫、真丝缎带、古典火漆印、八芒星盘、旁轴相机等），
为毛孩子打造 6 款真正典雅、精致、惊艳、极具情绪价值与时光收藏感的艺术插画相框：

1. 【春生 · 繁花秘境】(frame_spring_blossom) - 原生法式水彩繁花与撕边纸
2. 【夏梦 · 月夜星穹】(frame_summer_firefly) - 顶部弯月安睡猫、垂落星夜藤蔓与萤火虫光晕
3. 【秋忆 · 琥珀手账】(frame_autumn_ginkgo) - 右侧秋金植物蔓延与左下古典深红火漆印
4. 【冬祈 · 极光雪松】(frame_winter_frost) - 覆雪松枝红果与右上维多利亚八角北极星
5. 【诞辰 · 家盟之约】(frame_birthday_starlight) - 顶部真丝缎带蝴蝶结、蔷薇花环与底部烛光
6. 【永恒 · 彩虹星河】(frame_eternal_rainbow) - 柔彩水彩虹光、维多利亚烫金星盘与永恒花卉

输出 1200x1600 高清透明相框及搭配真实宠物照片的实机效果图。
"""

from __future__ import annotations

import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont, ImageEnhance
import numpy as np

REPO_ROOT = Path(__file__).resolve().parent.parent
BRAIN_DIR = Path(r"C:\Users\altai\.gemini\antigravity\brain\b492f7ab-360b-4a32-b7c5-a134c71fba2a")
OUTPUT_DIR = BRAIN_DIR / "masterpiece_frames"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

W, H = 1200, 1600


# --------------------------------------------------------------------------- #
# 资源加载与基础准备
# --------------------------------------------------------------------------- #

def get_fonts():
    try:
        font_serif_lg = ImageFont.truetype("georgia.ttf", 26)
        font_serif_md = ImageFont.truetype("georgia.ttf", 19)
        font_sans = ImageFont.truetype("msyh.ttc", 22)
    except Exception:
        font_serif_lg = font_serif_md = font_sans = ImageFont.load_default()
    return font_serif_lg, font_serif_md, font_sans


def load_cutout_stickers() -> dict[str, Image.Image]:
    """加载 12 款真实手绘精修贴纸作为艺术插画构图元件"""
    refined_dir = BRAIN_DIR / "refined_stickers"
    stickers = {}
    names = [
        "sticker_bloom_flower", "sticker_adoption_ribbon", "sticker_radiant_star",
        "sticker_sleepy_moon", "sticker_warm_heart", "sticker_birthday_cake",
        "sticker_sun_paw", "sticker_archive_seal", "sticker_retro_camera",
        "sticker_paw_mark", "sticker_food_bowl", "sticker_tandem_paws"
    ]
    for name in names:
        p = refined_dir / f"{name}.png"
        if p.exists():
            stickers[name] = Image.open(p).convert("RGBA")
    return stickers


def get_deckled_paper_base() -> tuple[Image.Image, Image.Image]:
    """提取春樱原画与带有撕边纤维的纯水彩纸视窗基底"""
    spring_src = BRAIN_DIR / "spring_handdrawn_1787321637378.jpg"
    im = Image.open(spring_src).convert("RGBA").resize((W, H), Image.Resampling.LANCZOS)
    arr = np.array(im, dtype=float)
    r, g, b, a = arr[:,:,0], arr[:,:,1], arr[:,:,2], arr[:,:,3]
    dist_white = np.sqrt((255 - r)**2 + (255 - g)**2 + (255 - b)**2)
    
    alpha = np.ones((H, W), dtype=np.uint8) * 255
    win_y0, win_y1 = int(0.24 * H), int(0.72 * H)
    win_x0, win_x1 = int(0.26 * W), int(0.74 * W)
    win_mask = np.zeros((H, W), dtype=bool)
    win_mask[win_y0:win_y1, win_x0:win_x1] = True
    
    alpha[win_mask & (dist_white < 22)] = 0
    t_mask = win_mask & (dist_white >= 22) & (dist_white < 45)
    alpha[t_mask] = np.clip((dist_white[t_mask] - 22) / 23.0 * 255.0, 0, 255).astype(np.uint8)
    
    outer_mask = np.ones((H, W), dtype=bool)
    outer_mask[int(0.06*H):int(0.94*H), int(0.08*W):int(0.92*W)] = False
    alpha[outer_mask & (dist_white < 18)] = 0
    
    spring_cutout = im.copy()
    spring_cutout.putalpha(Image.fromarray(alpha))
    
    # 纯纸样基底
    paper_base = Image.new("RGBA", (W, H), (252, 250, 246, 255))
    paper_base.putalpha(Image.fromarray(alpha))
    
    return spring_cutout, paper_base


# --------------------------------------------------------------------------- #
# 6 款非对称艺术大师级相框渲染
# --------------------------------------------------------------------------- #

def frame_1_spring_blossom(spring_cutout: Image.Image) -> Image.Image:
    """1. 【春生 · 繁花秘境】(frame_spring_blossom)"""
    # 保持原生法式手绘水彩画的完整艺术美感
    return spring_cutout


def frame_2_summer_nocturne(paper_base: Image.Image, stks: dict[str, Image.Image]) -> Image.Image:
    """2. 【夏梦 · 月夜星穹】(frame_summer_firefly)
    构图：顶部中央是一弯精雕细琢的金黄弯月与安睡猫咪(sleepy_moon)，两侧垂下水彩夏夜深青藤蔓，
    右下角点缀复古旁轴机械相机(retro_camera)，四周漂浮发光萤火虫与星尘。
    """
    frame = paper_base.copy()
    
    # 1. 顶部弯月与安睡猫咪
    if "sticker_sleepy_moon" in stks:
        moon = stks["sticker_sleepy_moon"].resize((340, 340), Image.Resampling.LANCZOS)
        frame.paste(moon, ((W - 340)//2, 20), moon)

    # 2. 左右两侧垂下的深青水彩藤蔓
    if "sticker_bloom_flower" in stks:
        flower = stks["sticker_bloom_flower"].resize((360, 360), Image.Resampling.LANCZOS)
        r, g, b, a = flower.split()
        r = r.point(lambda p: int(p * 0.55))
        g = g.point(lambda p: int(min(255, p * 1.15)))
        b = b.point(lambda p: int(min(255, p * 1.35)))
        night_vines = Image.merge("RGBA", (r, g, b, a))
        
        # 左侧与右侧自然垂落
        frame.paste(night_vines.rotate(-25, expand=True, resample=Image.Resampling.BICUBIC), (20, 180), night_vines.rotate(-25, expand=True, resample=Image.Resampling.BICUBIC))
        frame.paste(night_vines.transpose(Image.FLIP_LEFT_RIGHT).rotate(25, expand=True, resample=Image.Resampling.BICUBIC), (W - 380, 180), night_vines.transpose(Image.FLIP_LEFT_RIGHT).rotate(25, expand=True, resample=Image.Resampling.BICUBIC))

    # 3. 右下角复古旁轴相机与微光小星
    if "sticker_retro_camera" in stks:
        cam = stks["sticker_retro_camera"].resize((230, 230), Image.Resampling.LANCZOS)
        frame.paste(cam, (W - 270, H - 270), cam)

    # 4. 左下角手绘水彩小足印相伴
    if "sticker_tandem_paws" in stks:
        paws = stks["sticker_tandem_paws"].resize((180, 180), Image.Resampling.LANCZOS)
        frame.paste(paws, (40, H - 230), paws)

    # 5. 飘散在画面周围的梦幻发光萤火虫
    draw = ImageDraw.Draw(frame)
    win_x0, win_y0 = int(0.25 * W), int(0.23 * H)
    win_x1, win_y1 = int(0.75 * W), int(0.73 * H)
    
    np.random.seed(333)
    for _ in range(40):
        gx = np.random.uniform(40, W - 40)
        gy = np.random.uniform(40, H - 40)
        if win_x0 < gx < win_x1 and win_y0 < gy < win_y1:
            continue
        rad = np.random.uniform(6, 12)
        draw.ellipse([gx - rad*3, gy - rad*3, gx + rad*3, gy + rad*3], fill=(255, 235, 120, 35))
        draw.ellipse([gx - rad*1.6, gy - rad*1.6, gx + rad*1.6, gy + rad*1.6], fill=(255, 220, 80, 85))
        draw.ellipse([gx - rad*0.6, gy - rad*0.6, gx + rad*0.6, gy + rad*0.6], fill=(255, 255, 220, 240))

    return frame


def frame_3_autumn_keepsake(paper_base: Image.Image, stks: dict[str, Image.Image]) -> Image.Image:
    """3. 【秋忆 · 琥珀手账】(frame_autumn_ginkgo)
    构图：右侧是丰盛温暖的秋金水彩繁花与枫叶自右上倾泻至右下，左下角压印一枚温润厚重的深红火漆印(archive_seal)，
    散落手绘金箔落叶与手账细线。
    """
    frame = paper_base.copy()
    
    # 1. 右侧水彩植物蔓延（调色为暖金琥珀与秋枫红）
    if "sticker_bloom_flower" in stks:
        flower = stks["sticker_bloom_flower"].resize((420, 420), Image.Resampling.LANCZOS)
        r, g, b, a = flower.split()
        r = r.point(lambda p: int(min(255, p * 1.35)))
        g = g.point(lambda p: int(p * 0.95))
        b = b.point(lambda p: int(p * 0.35))
        autumn_flower = Image.merge("RGBA", (r, g, b, a))
        
        # 放置在右上角与右侧腰部
        frame.paste(autumn_flower.rotate(-15, expand=True, resample=Image.Resampling.BICUBIC), (W - 440, 20), autumn_flower.rotate(-15, expand=True, resample=Image.Resampling.BICUBIC))
        frame.paste(autumn_flower.rotate(40, expand=True, resample=Image.Resampling.BICUBIC), (W - 410, H - 480), autumn_flower.rotate(40, expand=True, resample=Image.Resampling.BICUBIC))

    # 2. 左下角古典深红火漆印章 (Archive Seal)
    if "sticker_archive_seal" in stks:
        seal = stks["sticker_archive_seal"].resize((270, 270), Image.Resampling.LANCZOS)
        frame.paste(seal, (35, H - 290), seal)

    # 3. 左上角暖阳爪印光芒 (Sun Paw)
    if "sticker_sun_paw" in stks:
        sun = stks["sticker_sun_paw"].resize((220, 220), Image.Resampling.LANCZOS)
        frame.paste(sun, (35, 35), sun)

    # 4. 散落四周的金色落叶与秋阳细尘
    draw = ImageDraw.Draw(frame)
    win_x0, win_y0 = int(0.25 * W), int(0.23 * H)
    win_x1, win_y1 = int(0.75 * W), int(0.73 * H)
    
    np.random.seed(444)
    for _ in range(35):
        lx = np.random.uniform(40, W - 40)
        ly = np.random.uniform(40, H - 40)
        if win_x0 < lx < win_x1 and win_y0 < ly < win_y1:
            continue
        sz = np.random.uniform(10, 22)
        draw.ellipse([lx - sz, ly - sz*0.6, lx + sz, ly + sz*0.6], fill=(245, 180, 45, 220), outline=(175, 95, 25, 180), width=1)
        draw.ellipse([lx + 5, ly + 5, lx + 10, ly + 10], fill=(255, 220, 120, 200))

    _, font_serif_md, _ = get_fonts()
    draw.text((W // 2 - 160, H - 75), "AUTUMN MEMORY • VOL. 03", fill=(175, 105, 45, 240), font=font_serif_md)
    return frame


def frame_4_winter_solstice(paper_base: Image.Image, stks: dict[str, Image.Image]) -> Image.Image:
    """4. 【冬祈 · 极光雪松】(frame_winter_frost)
    构图：左上角覆雪松枝与冬青红浆果，右上角悬挂维多利亚烫金八角北极星(radiant_star)，
    底部两角点缀手绘雪花与温暖足印。
    """
    frame = paper_base.copy()
    
    # 1. 右上角维多利亚八角金属浮雕北极星 (Radiant Star)
    if "sticker_radiant_star" in stks:
        star = stks["sticker_radiant_star"].resize((280, 280), Image.Resampling.LANCZOS)
        frame.paste(star, (W - 310, 25), star)

    # 2. 左上角与左侧深绿覆雪松枝（从 bloom_flower 调色并叠加白雪）
    if "sticker_bloom_flower" in stks:
        flower = stks["sticker_bloom_flower"].resize((400, 400), Image.Resampling.LANCZOS)
        r, g, b, a = flower.split()
        r = r.point(lambda p: int(p * 0.35))
        g = g.point(lambda p: int(p * 0.75))
        b = b.point(lambda p: int(min(255, p * 1.15)))
        winter_branch = Image.merge("RGBA", (r, g, b, a))
        
        frame.paste(winter_branch.rotate(20, expand=True, resample=Image.Resampling.BICUBIC), (20, 20), winter_branch.rotate(20, expand=True, resample=Image.Resampling.BICUBIC))
        frame.paste(winter_branch.transpose(Image.FLIP_TOP_BOTTOM).rotate(-35, expand=True, resample=Image.Resampling.BICUBIC), (20, H - 420), winter_branch.transpose(Image.FLIP_TOP_BOTTOM).rotate(-35, expand=True, resample=Image.Resampling.BICUBIC))

    # 3. 鲜艳红冬青果串与水彩白雪
    draw = ImageDraw.Draw(frame)
    for cx, cy in [(140, 150), (190, 110), (120, H - 180), (W - 140, H - 160)]:
        draw.ellipse([cx - 14, cy - 14, cx + 8, cy + 8], fill=(215, 45, 40, 255), outline=(150, 25, 20, 220))
        draw.ellipse([cx + 4, cy - 12, cx + 22, cy + 4], fill=(215, 45, 40, 255), outline=(150, 25, 20, 220))
        draw.ellipse([cx - 6, cy + 4, cx + 10, cy + 22], fill=(215, 45, 40, 255), outline=(150, 25, 20, 220))
        draw.ellipse([cx - 5, cy - 7, cx - 1, cy - 3], fill=(255, 230, 230, 255))
        draw.ellipse([cx + 8, cy - 5, cx + 12, cy - 1], fill=(255, 230, 230, 255))

    # 4. 散落的精美手绘六芒雪花与微光
    win_x0, win_y0 = int(0.25 * W), int(0.23 * H)
    win_x1, win_y1 = int(0.75 * W), int(0.73 * H)
    np.random.seed(555)
    for _ in range(30):
        fx = np.random.uniform(40, W - 40)
        fy = np.random.uniform(40, H - 40)
        if win_x0 < fx < win_x1 and win_y0 < fy < win_y1:
            continue
        r = np.random.uniform(10, 20)
        for ang in [0, 60, 120]:
            rad = math.radians(ang)
            draw.line([(fx - r*math.cos(rad), fy - r*math.sin(rad)), (fx + r*math.cos(rad), fy + r*math.sin(rad))], fill=(240, 248, 255, 230), width=2)

    return frame


def frame_5_birthday_crest(paper_base: Image.Image, stks: dict[str, Image.Image]) -> Image.Image:
    """5. 【诞辰 · 家盟之约】(frame_birthday_starlight)
    构图：顶部正中央是优雅大气的法式双层真丝缎带蝴蝶结(adoption_ribbon)，
    底部正中央是手绘精致诞辰蛋糕与温暖烛光(birthday_cake)，两侧点缀水彩花环与金色微星。
    """
    frame = paper_base.copy()
    
    # 1. 顶部真丝缎带蝴蝶结 (Adoption Ribbon)
    if "sticker_adoption_ribbon" in stks:
        ribbon = stks["sticker_adoption_ribbon"].resize((380, 380), Image.Resampling.LANCZOS)
        frame.paste(ribbon, ((W - 380)//2, 10), ribbon)

    # 2. 底部复古手绘诞辰蛋糕 (Birthday Cake)
    if "sticker_birthday_cake" in stks:
        cake = stks["sticker_birthday_cake"].resize((300, 300), Image.Resampling.LANCZOS)
        frame.paste(cake, ((W - 300)//2, H - 300), cake)

    # 3. 左右两侧柔粉水彩花枝环抱 (Rose Wreath)
    if "sticker_bloom_flower" in stks:
        flower = stks["sticker_bloom_flower"].resize((320, 320), Image.Resampling.LANCZOS)
        frame.paste(flower.rotate(-30, expand=True, resample=Image.Resampling.BICUBIC), (20, H // 2 - 200), flower.rotate(-30, expand=True, resample=Image.Resampling.BICUBIC))
        frame.paste(flower.transpose(Image.FLIP_LEFT_RIGHT).rotate(30, expand=True, resample=Image.Resampling.BICUBIC), (W - 340, H // 2 - 200), flower.transpose(Image.FLIP_LEFT_RIGHT).rotate(30, expand=True, resample=Image.Resampling.BICUBIC))

    # 4. 散落金色礼花星芒与微光光斑
    draw = ImageDraw.Draw(frame)
    win_x0, win_y0 = int(0.25 * W), int(0.23 * H)
    win_x1, win_y1 = int(0.75 * W), int(0.73 * H)
    np.random.seed(666)
    for _ in range(35):
        px = np.random.uniform(40, W - 40)
        py = np.random.uniform(40, H - 40)
        if win_x0 < px < win_x1 and win_y0 < py < win_y1:
            continue
        rad = np.random.uniform(5, 10)
        draw.ellipse([px - rad, py - rad, px + rad, py + rad], fill=(255, 225, 130, 180))
        draw.ellipse([px - 2, py - 2, px + 2, py + 2], fill=(255, 255, 255, 240))

    return frame


def frame_6_eternal_rainbow(paper_base: Image.Image, stks: dict[str, Image.Image]) -> Image.Image:
    """6. 【永恒 · 彩虹星河】(frame_eternal_rainbow)
    构图：顶部跨越着柔美通透的七彩水彩渐变光晕与星河，左下角闪耀着维多利亚金色守护星盘(radiant_star)，
    右上角是一朵永恒绽放的柔白植物繁花(bloom_flower)，星屑流转，温柔深情。
    """
    frame = paper_base.copy()
    
    # 1. 顶部手绘温润七彩水彩渐变拱弧
    draw = ImageDraw.Draw(frame)
    win_x0, win_y0 = int(0.25 * W), int(0.23 * H)
    win_x1, win_y1 = int(0.75 * W), int(0.73 * H)
    
    rainbow_colors = [
        (255, 175, 175, 180),
        (255, 210, 155, 180),
        (255, 245, 165, 180),
        (185, 235, 195, 180),
        (175, 220, 250, 180),
        (210, 190, 245, 180),
    ]
    for r_idx, r_col in enumerate(rainbow_colors):
        draw.arc([win_x0 - 60, win_y0 - 100 - r_idx*5, win_x1 + 60, win_y0 + 140 - r_idx*5], start=195, end=345, fill=r_col, width=4)

    # 2. 左下角维多利亚八角金属浮雕星盘 (Radiant Star)
    if "sticker_radiant_star" in stks:
        star = stks["sticker_radiant_star"].resize((260, 260), Image.Resampling.LANCZOS)
        frame.paste(star, (35, H - 280), star)

    # 3. 右上角永恒繁花 (Bloom Flower)
    if "sticker_bloom_flower" in stks:
        flower = stks["sticker_bloom_flower"].resize((340, 340), Image.Resampling.LANCZOS)
        frame.paste(flower.rotate(-20, expand=True, resample=Image.Resampling.BICUBIC), (W - 360, 25), flower.rotate(-20, expand=True, resample=Image.Resampling.BICUBIC))

    # 4. 右下角手绘水彩温暖心痕 (Warm Heart)
    if "sticker_warm_heart" in stks:
        heart = stks["sticker_warm_heart"].resize((200, 200), Image.Resampling.LANCZOS)
        frame.paste(heart, (W - 240, H - 240), heart)

    # 5. 浩瀚星河星屑
    np.random.seed(777)
    for _ in range(50):
        sx = np.random.uniform(40, W - 40)
        sy = np.random.uniform(40, H - 40)
        if win_x0 < sx < win_x1 and win_y0 < sy < win_y1:
            continue
        sz = np.random.uniform(4, 12)
        c_pick = rainbow_colors[np.random.randint(len(rainbow_colors))]
        draw.ellipse([sx - sz, sy - sz, sx + sz, sy + sz], fill=(*c_pick[:3], 90))
        draw.ellipse([sx - 1.5, sy - 1.5, sx + 1.5, sy + 1.5], fill=(255, 255, 255, 240))

    _, font_serif_md, _ = get_fonts()
    draw.text((W // 2 - 190, H - 75), "✦  FOREVER LOVED & REMEMBERED  ✦", fill=(195, 160, 215, 240), font=font_serif_md)
    return frame


# --------------------------------------------------------------------------- #
# 主控执行流程
# --------------------------------------------------------------------------- #

def main():
    print("开始生成 MiLens 大师级艺术构图相框（非对称有机插画设计）...")
    spring_cutout, paper_base = get_deckled_paper_base()
    stks = load_cutout_stickers()
    
    generators = [
        ("frame_spring_blossom", "春生 · 繁花秘境 (Spring Blossom)", "recommended", False, lambda: frame_1_spring_blossom(spring_cutout)),
        ("frame_summer_firefly", "夏梦 · 月夜星穹 (Summer Nocturne)", "film", False, lambda: frame_2_summer_nocturne(paper_base, stks)),
        ("frame_autumn_ginkgo", "秋忆 · 琥珀手账 (Autumn Keepsake)", "film", False, lambda: frame_3_autumn_keepsake(paper_base, stks)),
        ("frame_winter_frost", "冬祈 · 极光雪松 (Winter Solstice)", "holiday", True, lambda: frame_4_winter_solstice(paper_base, stks)),
        ("frame_birthday_starlight", "诞辰 · 家盟之约 (Gotcha Day Crest)", "paper", True, lambda: frame_5_birthday_crest(paper_base, stks)),
        ("frame_eternal_rainbow", "永恒 · 彩虹星河 (Eternal Rainbow)", "paper", True, lambda: frame_6_eternal_rainbow(paper_base, stks)),
    ]

    # 创建高质量测试底图
    sample_photo = Image.new("RGBA", (W, H), (242, 236, 226, 255))
    sdraw = ImageDraw.Draw(sample_photo)
    for y in range(H):
        t = y / H
        sdraw.line([(0, y), (W, y)], fill=(int(248 - 25*t), int(238 - 30*t), int(224 - 35*t), 255))
    
    cat_src = BRAIN_DIR / "sleepy_moon_sticker_1787316716106.jpg"
    if cat_src.exists():
        cat_img = Image.open(cat_src).resize((760, 760), Image.Resampling.LANCZOS)
        sample_photo.paste(cat_img, ((W - 760)//2, (H - 760)//2 - 10))

    # 1. 渲染相框透明图与 Mockup
    for fid, name, group, is_pro, gen_fn in generators:
        frame_png = gen_fn()
        
        frame_p = OUTPUT_DIR / f"{fid}.png"
        frame_png.save(frame_p, "PNG", optimize=True)
        print(f"  [大师级艺术相框原图] {frame_p.name}")
        
        mockup = sample_photo.copy()
        mockup.paste(frame_png, (0, 0), frame_png)
        mockup_p = OUTPUT_DIR / f"{fid}_mockup.png"
        mockup.save(mockup_p, "PNG", optimize=True)
        print(f"  [实机套框艺术展示] {mockup_p.name}")

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

    draw.text((pad_x, 40), "MiLens · 大师级艺术插画相框全览 (非对称手绘构图 · 绝美典藏版)", fill=(31, 27, 24, 255), font=font_title)
    draw.text((pad_x, 95), "打破死板九宫格限制，融合手绘繁花、月夜安睡猫、古典火漆印、法式真丝缎带与烫金星盘，赋予每张照片独一无二的绘本级艺术美感", fill=(107, 98, 91, 255), font=font_sub)

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

    overview_out = OUTPUT_DIR / "masterpiece_frames_overview.png"
    overview.save(overview_out, "PNG", optimize=True)
    print(f"\n大师级艺术相框总览图生成完毕！输出: {overview_out}")


if __name__ == "__main__":
    main()
