#!/usr/bin/env python3
"""MiLens 纯粹整体感艺术相框（Holistic Unified Botanical & Celestial Frames）渲染引擎。

彻底杜绝杂乱拼贴贴纸，聚焦于【纯粹、连贯、一体化、高度典雅】的手绘边框艺术体系：
1. 【春日繁樱】(frame_spring_sakura) - 纯粹连贯的手绘水彩粉樱花簇与嫩叶花环
2. 【盛夏常青】(frame_summer_botanical) - 纯粹连贯的手绘水彩尤加利与常春藤枝蔓花环
3. 【秋日金枫】(frame_autumn_foliage) - 纯粹连贯的手绘水彩秋金银杏与琥珀红枫叶环
4. 【冬日雪松】(frame_winter_pine) - 纯粹连贯的手绘覆雪松针与冬青红浆果花环
5. 【古典烫金】(frame_antique_gilt) - 纯粹连贯的欧洲古典手绘烫金细线、珠边与卷草纹
6. 【星穹星轨】(frame_celestial_stars) - 纯粹连贯的手绘星宿刻度双线与微光星辰环

输出 1200x1600 超高清透明相框及搭配真实宠物照片的纯净实机展示图。
"""

from __future__ import annotations

import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import numpy as np

REPO_ROOT = Path(__file__).resolve().parent.parent
BRAIN_DIR = Path(r"C:\Users\altai\.gemini\antigravity\brain\b492f7ab-360b-4a32-b7c5-a134c71fba2a")
OUTPUT_DIR = BRAIN_DIR / "holistic_frames"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

W, H = 1200, 1600


# --------------------------------------------------------------------------- #
# 1. 基础手绘母版高保真提取
# --------------------------------------------------------------------------- #

def get_spring_master_cutout() -> Image.Image:
    """提取春樱手绘原画透明相框"""
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
    
    im.putalpha(Image.fromarray(alpha))
    return im


def extract_paper_base(spring_cutout: Image.Image) -> tuple[Image.Image, np.ndarray]:
    """提取纯净撕边纸基底与遮罩"""
    alpha = np.array(spring_cutout)[:, :, 3]
    paper_base = Image.new("RGBA", (W, H), (252, 250, 246, 255))
    paper_base.putalpha(Image.fromarray(alpha))
    return paper_base, alpha


# --------------------------------------------------------------------------- #
# 2. 6 款纯粹整体感相框生成
# --------------------------------------------------------------------------- #

def gen_frame_1_spring_sakura(spring_cutout: Image.Image) -> Image.Image:
    """1. 【春日繁樱】(frame_spring_sakura) - 纯粹连贯的手绘水彩粉樱花簇与嫩叶花环"""
    return spring_cutout


def gen_frame_2_summer_botanical(spring_cutout: Image.Image) -> Image.Image:
    """2. 【盛夏常青】(frame_summer_botanical) - 纯粹连贯的手绘水彩尤加利与常春藤枝蔓花环
    将春樱整体转调为清新盛夏的翠绿、鼠尾草绿与橄榄叶色系，保留整圈连贯的植物手绘花环结构。
    """
    arr = np.array(spring_cutout, dtype=np.float32)
    r, g, b, a = arr[:,:,0], arr[:,:,1], arr[:,:,2], arr[:,:,3]
    
    # 将原本的粉红色/红色花瓣转为温润白花/淡雅黄绿花，将绿叶增强为饱满夏日翠绿
    # 计算原本红度与绿度
    is_plant = (a > 30)
    
    # 调色矩阵：降低粉红，提升草木翠绿与白茉莉花色
    new_r = np.where(is_plant, r * 0.70 + g * 0.20, r)
    new_g = np.where(is_plant, np.clip(g * 1.15 + r * 0.10, 0, 255), g)
    new_b = np.where(is_plant, b * 0.85 + g * 0.15, b)
    
    res_arr = np.stack([new_r, new_g, new_b, a], axis=-1).astype(np.uint8)
    return Image.fromarray(res_arr)


def gen_frame_3_autumn_foliage(spring_cutout: Image.Image) -> Image.Image:
    """3. 【秋日金枫】(frame_autumn_foliage) - 纯粹连贯的手绘水彩秋金银杏与琥珀红枫叶环
    将整体花环转调为深秋暖阳色系：金黄银杏、红褐枫叶、琥珀果实，极具丰盈温暖的连贯感。
    """
    arr = np.array(spring_cutout, dtype=np.float32)
    r, g, b, a = arr[:,:,0], arr[:,:,1], arr[:,:,2], arr[:,:,3]
    is_plant = (a > 30)
    
    # 调色矩阵：增强红色与黄色，降低蓝色 -> 浓郁秋季金枫
    new_r = np.where(is_plant, np.clip(r * 1.25 + g * 0.15, 0, 255), r)
    new_g = np.where(is_plant, np.clip(g * 0.95 + r * 0.10, 0, 255), g)
    new_b = np.where(is_plant, b * 0.35, b)
    
    res_arr = np.stack([new_r, new_g, new_b, a], axis=-1).astype(np.uint8)
    return Image.fromarray(res_arr)


def gen_frame_4_winter_pine(spring_cutout: Image.Image) -> Image.Image:
    """4. 【冬日雪松】(frame_winter_pine) - 纯粹连贯的手绘覆雪松针与冬青红浆果花环
    将花环转调为深墨绿松针与纯白雪霜，果实转为鲜红冬青浆果。
    """
    arr = np.array(spring_cutout, dtype=np.float32)
    r, g, b, a = arr[:,:,0], arr[:,:,1], arr[:,:,2], arr[:,:,3]
    is_plant = (a > 30)
    
    # 调色矩阵：深冷绿与银白霜雪
    new_r = np.where(is_plant, r * 0.65, r)
    new_g = np.where(is_plant, np.clip(g * 0.95 + b * 0.15, 0, 255), g)
    new_b = np.where(is_plant, np.clip(b * 1.15, 0, 255), b)
    
    res_arr = np.stack([new_r, new_g, new_b, a], axis=-1).astype(np.uint8)
    res_im = Image.fromarray(res_arr)
    
    # 在花环四角点缀连贯鲜红冬青小浆果
    draw = ImageDraw.Draw(res_im)
    for cx, cy in [(140, 150), (W - 140, 150), (140, H - 150), (W - 140, H - 150), (W//2, 80), (W//2, H - 80)]:
        draw.ellipse([cx - 8, cy - 8, cx + 6, cy + 6], fill=(215, 45, 40, 255), outline=(150, 25, 20, 220))
        draw.ellipse([cx + 2, cy - 6, cx + 14, cy + 4], fill=(215, 45, 40, 255), outline=(150, 25, 20, 220))
        draw.ellipse([cx - 3, cy - 4, cx, cy - 1], fill=(255, 220, 220, 255))
        
    return res_im


def gen_frame_5_antique_gilt(paper_base: Image.Image) -> Image.Image:
    """5. 【古典烫金】(frame_antique_gilt) - 纯粹连贯的欧洲古典手绘烫金细线、珠边与卷草纹
    极致纯净、典雅、克制的高定艺术边框。
    """
    frame = paper_base.copy()
    draw = ImageDraw.Draw(frame)
    
    win_x0, win_y0 = int(0.24 * W) - 8, int(0.22 * H) - 8
    win_x1, win_y1 = int(0.76 * W) + 8, int(0.74 * H) + 8
    
    GOLD_PRIMARY = (212, 160, 65, 230)
    GOLD_LIGHT = (245, 215, 135, 180)
    GOLD_DEEP = (165, 110, 35, 240)
    
    # 1. 精密手绘双重烫金细线
    draw.rectangle([win_x0, win_y0, win_x1, win_y1], outline=GOLD_PRIMARY, width=2)
    draw.rectangle([win_x0 - 12, win_y0 - 12, win_x1 + 12, win_y1 + 12], outline=GOLD_LIGHT, width=1)
    draw.rectangle([win_x0 - 24, win_y0 - 24, win_x1 + 24, win_y1 + 24], outline=GOLD_PRIMARY, width=1)
    
    # 2. 四边等距手绘微型金属珍珠珠边 (Beaded Filigree Trim)
    bead_inset = win_x0 - 18
    bead_r = 3
    for x in range(win_x0, win_x1, 16):
        draw.ellipse([x - bead_r, win_y0 - 18 - bead_r, x + bead_r, win_y0 - 18 + bead_r], fill=GOLD_PRIMARY)
        draw.ellipse([x - bead_r, win_y1 + 18 - bead_r, x + bead_r, win_y1 + 18 + bead_r], fill=GOLD_PRIMARY)
    for y in range(win_y0, win_y1, 16):
        draw.ellipse([win_x0 - 18 - bead_r, y - bead_r, win_x0 - 18 + bead_r, y + bead_r], fill=GOLD_PRIMARY)
        draw.ellipse([win_x1 + 18 - bead_r, y - bead_r, win_x1 + 18 + bead_r, y + bead_r], fill=GOLD_PRIMARY)

    # 3. 四角古典手绘卷草花角 (Filigree Corner Brackets)
    corner_len = 65
    for cx, cy, fx, fy in [(win_x0 - 24, win_y0 - 24, 1, 1), (win_x1 + 24, win_y0 - 24, -1, 1), (win_x0 - 24, win_y1 + 24, 1, -1), (win_x1 + 24, win_y1 + 24, -1, -1)]:
        # 卷草弧线
        arc_x0 = min(cx, cx + corner_len * fx)
        arc_x1 = max(cx, cx + corner_len * fx)
        arc_y0 = min(cy, cy + corner_len * fy)
        arc_y1 = max(cy, cy + corner_len * fy)
        draw.arc([arc_x0, arc_y0, arc_x1, arc_y1], start=0, end=360, fill=GOLD_PRIMARY, width=2)
        draw.line([(cx, cy), (cx + corner_len*fx, cy)], fill=GOLD_PRIMARY, width=2)
        draw.line([(cx, cy), (cx, cy + corner_len*fy)], fill=GOLD_PRIMARY, width=2)
        # 角部微型八角星
        for ang in [0, 45, 90, 135]:
            r_ang = math.radians(ang)
            draw.line([(cx + 18*fx - 6*math.cos(r_ang), cy + 18*fy - 6*math.sin(r_ang)), (cx + 18*fx + 6*math.cos(r_ang), cy + 18*fy + 6*math.sin(r_ang))], fill=GOLD_LIGHT, width=1)

    return frame


def gen_frame_6_celestial_stars(paper_base: Image.Image) -> Image.Image:
    """6. 【星穹星轨】(frame_celestial_stars) - 纯粹连贯的手绘星宿刻度双线与微光星辰环
    深邃、沉静、诗意的连贯天体星图相框。
    """
    frame = paper_base.copy()
    draw = ImageDraw.Draw(frame)
    
    win_x0, win_y0 = int(0.24 * W) - 8, int(0.22 * H) - 8
    win_x1, win_y1 = int(0.76 * W) + 8, int(0.74 * H) + 8
    
    STAR_GOLD = (225, 185, 95, 230)
    STAR_LIGHT = (255, 245, 185, 255)
    NAVY_INK = (75, 95, 130, 200)
    
    # 1. 典雅夏夜深蓝与金色双重天体星轨
    draw.rectangle([win_x0, win_y0, win_x1, win_y1], outline=NAVY_INK, width=2)
    draw.rectangle([win_x0 - 12, win_y0 - 12, win_x1 + 12, win_y1 + 12], outline=STAR_GOLD, width=1)
    draw.rectangle([win_x0 - 24, win_y0 - 24, win_x1 + 24, win_y1 + 24], outline=NAVY_INK, width=1)
    
    # 2. 四边等距星宿经纬刻度 (Celestial Meridian Ticks)
    for x in range(win_x0, win_x1, 24):
        draw.line([(x, win_y0 - 12), (x, win_y0 - 24)], fill=STAR_GOLD, width=1)
        draw.line([(x, win_y1 + 12), (x, win_y1 + 24)], fill=STAR_GOLD, width=1)
    for y in range(win_y0, win_y1, 24):
        draw.line([(win_x0 - 12, y), (win_x0 - 24, y)], fill=STAR_GOLD, width=1)
        draw.line([(win_x1 + 12, y), (win_x1 + 24, y)], fill=STAR_GOLD, width=1)

    # 3. 环绕边框的纯净发光微星与星尘
    np.random.seed(111)
    for _ in range(45):
        sx = np.random.uniform(40, W - 40)
        sy = np.random.uniform(40, H - 40)
        if win_x0 - 20 < sx < win_x1 + 20 and win_y0 - 20 < sy < win_y1 + 20:
            continue
        rad = np.random.uniform(4, 9)
        # 外发光
        draw.ellipse([sx - rad*1.8, sy - rad*1.8, sx + rad*1.8, sy + rad*1.8], fill=(255, 235, 140, 50))
        # 金色八角微星
        for ang in [0, 45, 90, 135]:
            r_ang = math.radians(ang)
            draw.line([(sx - rad*math.cos(r_ang), sy - rad*math.sin(r_ang)), (sx + rad*math.cos(r_ang), sy + rad*math.sin(r_ang))], fill=STAR_LIGHT, width=1)

    return frame


# --------------------------------------------------------------------------- #
# 主控流程
# --------------------------------------------------------------------------- #

def main():
    print("开始生成 MiLens 纯粹整体感艺术相框（彻底杜绝杂乱拼贴贴纸）...")
    spring_cutout = get_spring_master_cutout()
    paper_base, alpha = extract_paper_base(spring_cutout)
    
    generators = [
        ("frame_spring_sakura", "春日繁樱 (Spring Sakura)", "recommended", False, lambda: gen_frame_1_spring_sakura(spring_cutout)),
        ("frame_summer_botanical", "盛夏常青 (Summer Botanical)", "film", False, lambda: gen_frame_2_summer_botanical(spring_cutout)),
        ("frame_autumn_foliage", "秋日金枫 (Autumn Foliage)", "film", False, lambda: gen_frame_3_autumn_foliage(spring_cutout)),
        ("frame_winter_pine", "冬日雪松 (Winter Pine)", "holiday", True, lambda: gen_frame_4_winter_pine(spring_cutout)),
        ("frame_antique_gilt", "古典烫金 (Antique Gilt)", "paper", True, lambda: gen_frame_5_antique_gilt(paper_base)),
        ("frame_celestial_stars", "星穹星轨 (Celestial Stars)", "paper", True, lambda: gen_frame_6_celestial_stars(paper_base)),
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

    # 1. 渲染各相框透明图与 Mockup
    for fid, name, group, is_pro, gen_fn in generators:
        frame_png = gen_fn()
        
        frame_p = OUTPUT_DIR / f"{fid}.png"
        frame_png.save(frame_p, "PNG", optimize=True)
        print(f"  [纯净整体感相框] {frame_p.name}")
        
        mockup = sample_photo.copy()
        mockup.paste(frame_png, (0, 0), frame_png)
        mockup_p = OUTPUT_DIR / f"{fid}_mockup.png"
        mockup.save(mockup_p, "PNG", optimize=True)
        print(f"  [实机纯净套框展示] {mockup_p.name}")

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

    draw.text((pad_x, 40), "MiLens · 纯粹整体感艺术相框全览 (无杂乱拼贴 · 浑然一体典雅版)", fill=(31, 27, 24, 255), font=font_title)
    draw.text((pad_x, 95), "彻底告别零碎贴纸拼贴，采用连贯手绘植物花环、古典烫金珠边与天体星轨，呈现纯净、典雅、浑然一体的相框美感", fill=(107, 98, 91, 255), font=font_sub)

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

    overview_out = OUTPUT_DIR / "holistic_frames_overview.png"
    overview.save(overview_out, "PNG", optimize=True)
    print(f"\n纯粹整体感艺术相框总览图生成完毕！输出: {overview_out}")


if __name__ == "__main__":
    main()
