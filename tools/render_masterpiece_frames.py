#!/usr/bin/env python3
"""MiLens Masterpiece Artisan Photo Frame Generation Engine - High Precision Edition
Generates 3:4 photo frames with 100% transparent centers:
05: 欧洲古典烫金卷草 (Baroque Gilded Acanthus & Pearl Border)
06: 星穹经纬与微光 (Celestial Coordinates & Glimmer)
"""

import math
import os
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageEnhance, ImageChops
from scipy.ndimage import gaussian_filter, sobel

W, H = 1800, 2400
# Window dimensions: Exactly 3:4 proportion
WIN_W, WIN_H = 1170, 1560
WIN_X0 = (W - WIN_W) // 2  # 315
WIN_Y0 = (H - WIN_H) // 2  # 420
WIN_X1 = WIN_X0 + WIN_W    # 1485
WIN_Y1 = WIN_Y0 + WIN_H    # 1980

OUT_DIR = Path(r"C:\Users\altai\.gemini\antigravity\brain\dfa9995a-6fc6-4a8f-9eae-1438cca1b254")
OUT_DIR.mkdir(parents=True, exist_ok=True)
HERO_CAT_PATH = Path(r"e:\iOSprojects\MiLens\ui_draft\milens-hero-cat.png")


# =========================================================================== #
# Texture Shaders
# =========================================================================== #

def create_gold_texture(width, height, base_rgb=(218, 172, 60)):
    """Creates a tactile antique gold leaf texture with organic shimmer and specular flecks."""
    np.random.seed(42)
    x = np.linspace(0, 1, width)
    y = np.linspace(0, 1, height)
    xx, yy = np.meshgrid(x, y)
    
    sheen = 0.5 + 0.35 * np.sin(xx * 7.0 + yy * 4.5) + 0.15 * np.cos(xx * 14.0 - yy * 9.0)
    noise = np.random.normal(0, 1, (height, width))
    fine_noise = gaussian_filter(noise, sigma=0.65)
    broad_noise = gaussian_filter(noise, sigma=3.5)
    
    combined = sheen * 0.55 + fine_noise * 0.25 + broad_noise * 0.2
    combined = (combined - combined.min()) / (combined.max() - combined.min())
    
    r0, g0, b0 = base_rgb
    r = np.clip(r0 * 0.65 + combined * r0 * 0.70, 0, 255).astype(np.uint8)
    g = np.clip(g0 * 0.60 + combined * g0 * 0.75, 0, 255).astype(np.uint8)
    b = np.clip(b0 * 0.45 + combined * b0 * 0.85, 0, 255).astype(np.uint8)
    
    return Image.fromarray(np.stack([r, g, b], axis=-1), "RGB")


def create_pale_gold_texture(width, height):
    """Creates a luminous pale champagne gold texture for celestial themes."""
    return create_gold_texture(width, height, base_rgb=(238, 215, 138))


def create_ivory_paper(width, height):
    """Creates an ivory archival paper texture."""
    np.random.seed(101)
    noise = np.random.normal(0, 1, (height, width))
    fine = gaussian_filter(noise, sigma=0.55) * 2.5
    broad = gaussian_filter(noise, sigma=10.0) * 1.5
    
    r0, g0, b0 = (252, 249, 244)
    r = np.clip(r0 + fine + broad, 0, 255).astype(np.uint8)
    g = np.clip(g0 + fine + broad, 0, 255).astype(np.uint8)
    b = np.clip(b0 + fine + broad, 0, 255).astype(np.uint8)
    
    return Image.fromarray(np.stack([r, g, b], axis=-1), "RGB")


def create_midnight_navy_sky(width, height):
    """Creates a deep summer night indigo sky with soft watercolor cloudiness."""
    np.random.seed(2026)
    x = np.linspace(0, 1, width)
    y = np.linspace(0, 1, height)
    xx, yy = np.meshgrid(x, y)
    
    noise1 = gaussian_filter(np.random.normal(0, 1, (height, width)), sigma=40.0)
    noise2 = gaussian_filter(np.random.normal(0, 1, (height, width)), sigma=12.0)
    
    cx, cy = 0.5, 0.5
    dist = np.sqrt((xx - cx)**2 + (yy - cy)**2) * 1.414
    vignette = np.clip(dist * 0.35, 0, 1)
    
    val = (noise1 * 0.6 + noise2 * 0.4) * 0.25 + vignette * 0.35
    
    r = np.clip(10 + val * 12, 5, 36).astype(np.uint8)
    g = np.clip(22 + val * 20, 12, 55).astype(np.uint8)
    b = np.clip(50 + val * 38, 28, 95).astype(np.uint8)
    
    return Image.fromarray(np.stack([r, g, b], axis=-1), "RGB")


def render_embossed_gold(mask_arr, gold_tex_arr, light_deg=45.0, depth=4.0, spec_power=26.0):
    """Renders realistic 3D bevel & embossed antique gold with specular highlights."""
    mask_f = mask_arr.astype(float) / 255.0
    height_map = gaussian_filter(mask_f, sigma=1.1) * depth
    
    gx = sobel(height_map, axis=1)
    gy = sobel(height_map, axis=0)
    gz = np.ones_like(gx) * 2.0
    
    norm = np.sqrt(gx*gx + gy*gy + gz*gz) + 1e-6
    nx, ny, nz = -gx / norm, -gy / norm, gz / norm
    
    rad = math.radians(light_deg)
    lx = math.cos(rad) * 0.707
    ly = math.sin(rad) * 0.707
    lz = 0.707
    
    diffuse = np.clip(nx * lx + ny * ly + nz * lz, 0, 1)
    
    vx, vy, vz = 0, 0, 1.0
    hx, hy, hz = lx + vx, ly + vy, lz + vz
    hnorm = math.sqrt(hx*hx + hy*hy + hz*hz)
    hx, hy, hz = hx/hnorm, hy/hnorm, hz/hnorm
    spec = np.power(np.clip(nx * hx + ny * hy + nz * hz, 0, 1), spec_power)
    
    gold_f = gold_tex_arr.astype(float)
    shaded_r = gold_f[:,:,0] * (0.35 + 0.65 * diffuse) + spec * 240.0
    shaded_g = gold_f[:,:,1] * (0.35 + 0.65 * diffuse) + spec * 220.0
    shaded_b = gold_f[:,:,2] * (0.35 + 0.65 * diffuse) + spec * 160.0
    
    out_r = np.clip(shaded_r, 0, 255).astype(np.uint8)
    out_g = np.clip(shaded_g, 0, 255).astype(np.uint8)
    out_b = np.clip(shaded_b, 0, 255).astype(np.uint8)
    out_a = mask_arr
    
    return Image.fromarray(np.stack([out_r, out_g, out_b, out_a], axis=-1), "RGBA")


# =========================================================================== #
# Classical Baroque Engraving Drawing Primitives
# =========================================================================== #

def draw_pearl_string(draw, x0, y0, x1, y1, radius=6, spacing=15):
    """Draws a continuous string of pearl beads along a rectangle perimeter."""
    w = x1 - x0
    h = y1 - y0
    nx = int(round(w / spacing))
    ny = int(round(h / spacing))
    
    for i in range(nx + 1):
        x = x0 + i * (w / nx)
        draw.ellipse([x - radius, y0 - radius, x + radius, y0 + radius], fill=255)
        draw.ellipse([x - radius, y1 - radius, x + radius, y1 + radius], fill=255)
        
    for j in range(ny + 1):
        y = y0 + j * (h / ny)
        draw.ellipse([x0 - radius, y - radius, x0 + radius, y + radius], fill=255)
        draw.ellipse([x1 - radius, y - radius, x1 + radius, y + radius], fill=255)


def draw_eight_pointed_star(draw, cx, cy, r_outer, r_inner, r_mid=None):
    """Draws a classical eight-pointed faceted starburst."""
    if r_mid is None:
        r_mid = r_outer * 0.58
        
    pts = []
    for i in range(16):
        angle = i * (math.pi / 8.0) - math.pi / 2.0
        if i % 4 == 0:
            r = r_outer
        elif i % 2 == 0:
            r = r_mid
        else:
            r = r_inner
        pts.append((cx + r * math.cos(angle), cy + r * math.sin(angle)))
    draw.polygon(pts, fill=255)
    draw.ellipse([cx - r_inner*0.75, cy - r_inner*0.75, cx + r_inner*0.75, cy + r_inner*0.75], fill=255)


def bezier_curve(p0, p1, p2, p3, num_pts=50):
    """Calculates cubic Bezier curve points."""
    pts = []
    for t in np.linspace(0, 1, num_pts):
        u = 1 - t
        x = u**3 * p0[0] + 3*u**2*t * p1[0] + 3*u*t**2 * p2[0] + t**3 * p3[0]
        y = u**3 * p0[1] + 3*u**2*t * p1[1] + 3*u*t**2 * p2[1] + t**3 * p3[1]
        pts.append((x, y))
    return pts


def draw_engraved_acanthus_leaf(draw, base_pt, tip_pt, ctrl1, ctrl2, width_mid=30, num_hatch=8):
    """Draws an authentic, openwork classical engraved acanthus leaf with contour and internal hatching."""
    bx, by = base_pt
    tx, ty = tip_pt
    
    # Left and right outer contour curves
    c1_l = (ctrl1[0] - width_mid * 0.8, ctrl1[1] + width_mid * 0.8)
    c2_l = (ctrl2[0] - width_mid * 0.5, ctrl2[1] + width_mid * 0.5)
    pts_l = bezier_curve(base_pt, c1_l, c2_l, tip_pt, 40)
    
    c1_r = (ctrl1[0] + width_mid * 0.8, ctrl1[1] - width_mid * 0.8)
    c2_r = (ctrl2[0] + width_mid * 0.5, ctrl2[1] - width_mid * 0.5)
    pts_r = bezier_curve(base_pt, c1_r, c2_r, tip_pt, 40)
    
    # Draw double contour lines
    for i in range(len(pts_l) - 1):
        draw.line([pts_l[i], pts_l[i+1]], fill=255, width=3)
        draw.line([pts_r[i], pts_r[i+1]], fill=255, width=3)
        
    # Central spine vein
    spine = bezier_curve(base_pt, ctrl1, ctrl2, tip_pt, 40)
    for i in range(len(spine) - 1):
        draw.line([spine[i], spine[i+1]], fill=255, width=2)
        
    # Delicate internal cross-hatching veins (雕刻羽状线)
    for k in range(1, num_hatch):
        idx = int(k * len(pts_l) / num_hatch)
        pl = pts_l[idx]
        pr = pts_r[idx]
        ps = spine[idx]
        draw.line([ps, pl], fill=255, width=2)
        draw.line([ps, pr], fill=255, width=2)
        # Small leaf serration lobe
        draw.ellipse([pl[0] - 5, pl[1] - 5, pl[0] + 5, pl[1] + 5], fill=255)
        draw.ellipse([pr[0] - 5, pr[1] - 5, pr[0] + 5, pr[1] + 5], fill=255)
        
    # Curled button tip
    draw.ellipse([tx - 8, ty - 8, tx + 8, ty + 8], fill=255)


def draw_fine_engraved_corner_scroll(size=560):
    """Draws an exquisite, fine-line engraved classical baroque corner acanthus scroll."""
    im = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(im)
    
    # 1. Main sweeping diagonal S-volute
    draw_engraved_acanthus_leaf(draw, (70, 70), (380, 380), (100, 280), (280, 100), width_mid=35, num_hatch=10)
    
    # 2. Horizontal branch along top moulding
    draw_engraved_acanthus_leaf(draw, (70, 70), (450, 110), (180, 40), (320, 130), width_mid=28, num_hatch=8)
    
    # 3. Vertical branch along left moulding
    draw_engraved_acanthus_leaf(draw, (70, 70), (110, 450), (40, 180), (130, 320), width_mid=28, num_hatch=8)
    
    # 4. Secondary inner spiral volutes (细密巴洛克旋涡卷草)
    for t in np.linspace(0, 3.5 * math.pi, 200):
        r = 12 + (t ** 1.6) * 12
        x = 210 + r * math.cos(t - 0.4)
        y = 210 + r * math.sin(t - 0.4)
        draw.ellipse([x - 2, y - 2, x + 2, y + 2], fill=255)
        
    # 5. Corner rosette medallion (四角中心浮雕圆盘)
    for r in [8, 16, 26, 38, 50]:
        draw.ellipse([90 - r, 90 - r, 90 + r, 90 + r], outline=255, width=2)
    draw.ellipse([90 - 10, 90 - 10, 90 + 10, 90 + 10], fill=255)

    # 6. Pearl drops and floral buds
    for bx, by in [(310, 190), (190, 310), (410, 240), (240, 410), (470, 160), (160, 470)]:
        draw.ellipse([bx - 6, by - 6, bx + 6, by + 6], fill=255)
        draw.ellipse([bx + 8 - 4, by - 4, bx + 8 + 4, by + 4], fill=255)

    return im


def draw_fine_engraved_crest(width=640, height=200):
    """Draws a classical baroque anthemion center crest for top and bottom."""
    im = Image.new("L", (width, height), 0)
    draw = ImageDraw.Draw(im)
    cx, cy = width // 2, height - 30
    
    # Central fan of 9 engraved acanthus petals
    for angle_deg in [-60, -45, -30, -15, 0, 15, 30, 45, 60]:
        rad = math.radians(angle_deg - 90)
        length = 165 - abs(angle_deg) * 1.3
        tx = cx + length * math.cos(rad)
        ty = cy + length * math.sin(rad)
        
        # Double petal contour
        w = 16 - abs(angle_deg) * 0.12
        p1 = (cx + w * math.cos(rad + math.pi/2), cy + w * math.sin(rad + math.pi/2))
        p2 = (tx, ty)
        p3 = (cx + w * math.cos(rad - math.pi/2), cy + w * math.sin(rad - math.pi/2))
        draw.line([p1, p2], fill=255, width=2)
        draw.line([p2, p3], fill=255, width=2)
        draw.line([(cx, cy), (tx, ty)], fill=255, width=2)
        draw.ellipse([tx - 6, ty - 6, tx + 6, ty + 6], fill=255)
        
    # Symmetrical outward volute scrolls
    for sign in [-1, 1]:
        pts = bezier_curve((cx, cy), (cx + sign * 130, cy + 25), (cx + sign * 250, cy - 70), (cx + sign * 290, cy - 15), 50)
        for i in range(len(pts) - 1):
            draw.line([pts[i], pts[i+1]], fill=255, width=3)
        ex, ey = pts[-1]
        for r in [6, 14, 22]:
            draw.ellipse([ex - r, ey - r, ex + r, ey + r], outline=255, width=2)
        draw.ellipse([ex - 6, ey - 6, ex + 6, ey + 6], fill=255)
        
    # Central base rosette
    for r in [8, 18, 28, 40]:
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], outline=255, width=2)
    draw.ellipse([cx - 10, cy - 10, cx + 10, cy + 10], fill=255)
    
    return im


def draw_fine_engraved_side_vine(length=800):
    """Draws an elegant, fine-line running acanthus vine for left/right rails."""
    im = Image.new("L", (120, length), 0)
    draw = ImageDraw.Draw(im)
    cx = 60
    
    # Sinusoidal stem line
    pts = []
    for y in range(0, length, 4):
        x = cx + math.sin(y * 0.03) * 16
        pts.append((x, y))
    for i in range(len(pts) - 1):
        draw.line([pts[i], pts[i+1]], fill=255, width=3)
        
    # Alternating engraved leaves and berries
    for y in range(35, length - 35, 60):
        sign = 1 if (y // 60) % 2 == 0 else -1
        vx = cx + math.sin(y * 0.03) * 16
        
        # Engraved leaf contour
        p_base = (vx, y)
        p_tip = (vx + sign * 38, y - 10)
        p_c1 = (vx + sign * 15, y - 22)
        p_c2 = (vx + sign * 28, y + 12)
        draw.line([p_base, p_c1], fill=255, width=2)
        draw.line([p_c1, p_tip], fill=255, width=2)
        draw.line([p_tip, p_c2], fill=255, width=2)
        draw.line([p_c2, p_base], fill=255, width=2)
        draw.line([p_base, p_tip], fill=255, width=2)
        draw.ellipse([p_tip[0] - 4, p_tip[1] - 4, p_tip[0] + 4, p_tip[1] + 4], fill=255)
        
        # Pearl berry on opposite side
        bx, by = vx - sign * 20, y + 5
        draw.ellipse([bx - 5, by - 5, bx + 5, by + 5], fill=255)

    return im


# =========================================================================== #
# FRAME 05: 欧洲古典烫金卷草 (Baroque Gilded Acanthus & Pearl Border)
# =========================================================================== #

def generate_frame_05_baroque():
    print("Generating Frame 05: 欧洲古典烫金卷草...")
    paper = create_ivory_paper(W, H)
    gold_tex = create_gold_texture(W, H)
    
    mask_im = Image.new("L", (W, H), 0)
    draw = ImageDraw.Draw(mask_im)
    
    # 1. Outer Baroque Double/Triple Moulding
    draw.rectangle([85, 115, W - 85, H - 115], outline=255, width=5)
    draw.rectangle([105, 135, W - 105, H - 135], outline=255, width=2)
    draw.rectangle([122, 152, W - 122, H - 152], outline=255, width=4)
    
    # Outer pearl beading string
    draw_pearl_string(draw, 142, 172, W - 142, H - 172, radius=4, spacing=14)
    draw.rectangle([160, 190, W - 160, H - 190], outline=255, width=2)
    
    # 2. Inner photo window border
    draw.rectangle([WIN_X0 - 52, WIN_Y0 - 52, WIN_X1 + 52, WIN_Y1 + 52], outline=255, width=2)
    draw.rectangle([WIN_X0 - 38, WIN_Y0 - 38, WIN_X1 + 38, WIN_Y1 + 38], outline=255, width=4)
    
    # Inner pearl bead string framing the photo window
    draw_pearl_string(draw, WIN_X0 - 20, WIN_Y0 - 20, WIN_X1 + 20, WIN_Y1 + 20, radius=5, spacing=15)
    
    # Crisp inner gilt frame boundary
    draw.rectangle([WIN_X0 - 4, WIN_Y0 - 4, WIN_X1 + 4, WIN_Y1 + 4], outline=255, width=3)
    
    # 3. Fine Engraved Baroque Acanthus Corner Foliage (Four corners)
    corner_foliage = draw_fine_engraved_corner_scroll(size=560)
    
    # Top-Left
    tl = corner_foliage
    mask_im.paste(ImageChops.lighter(mask_im.crop((85, 115, 85 + 560, 115 + 560)), tl), (85, 115))
    
    # Top-Right
    tr = corner_foliage.transpose(Image.FLIP_LEFT_RIGHT)
    mask_im.paste(ImageChops.lighter(mask_im.crop((W - 85 - 560, 115, W - 85, 115 + 560)), tr), (W - 85 - 560, 115))
    
    # Bottom-Left
    bl = corner_foliage.transpose(Image.FLIP_TOP_BOTTOM)
    mask_im.paste(ImageChops.lighter(mask_im.crop((85, H - 115 - 560, 85 + 560, H - 115)), bl), (85, H - 115 - 560))
    
    # Bottom-Right
    br = corner_foliage.transpose(Image.FLIP_LEFT_RIGHT).transpose(Image.FLIP_TOP_BOTTOM)
    mask_im.paste(ImageChops.lighter(mask_im.crop((W - 85 - 560, H - 115 - 560, W - 85, H - 115)), br), (W - 85 - 560, H - 115 - 560))
    
    # 4. Top and Bottom Symmetrical Baroque Anthemion Crests
    crest = draw_fine_engraved_crest(width=640, height=200)
    crest_x = (W - 640) // 2
    
    # Top Crest
    mask_im.paste(ImageChops.lighter(mask_im.crop((crest_x, 105, crest_x + 640, 305)), crest), (crest_x, 105))
    
    # Bottom Crest (flipped)
    crest_bottom = crest.transpose(Image.FLIP_TOP_BOTTOM)
    mask_im.paste(ImageChops.lighter(mask_im.crop((crest_x, H - 305, crest_x + 640, H - 105)), crest_bottom), (crest_x, H - 305))

    # 5. Side Running Acanthus Vines (Left and Right Rails)
    side_vine = draw_fine_engraved_side_vine(length=800)
    sv_y = (H - 800) // 2
    # Left vine
    mask_im.paste(ImageChops.lighter(mask_im.crop((175, sv_y, 175 + 120, sv_y + 800)), side_vine), (175, sv_y))
    # Right vine (flipped)
    mask_im.paste(ImageChops.lighter(mask_im.crop((W - 175 - 120, sv_y, W - 175, sv_y + 800)), side_vine.transpose(Image.FLIP_LEFT_RIGHT)), (W - 175 - 120, sv_y))

    # 6. Render 3D Embossed Gold Layer
    gold_layer = render_embossed_gold(np.array(mask_im), np.array(gold_tex), light_deg=45.0, depth=3.8, spec_power=26.0)
    
    # 7. Warm Paper Composite with soft warm gold shadow
    frame_final = paper.convert("RGBA")
    
    shadow_mask = mask_im.filter(ImageFilter.GaussianBlur(radius=5))
    shadow_arr = np.array(shadow_mask).astype(float) / 255.0
    
    shadow_layer = Image.new("RGBA", (W, H), (70, 45, 15, 0))
    shadow_alpha = (shadow_arr * 115).astype(np.uint8)
    shadow_layer.putalpha(Image.fromarray(shadow_alpha))
    
    frame_final = Image.alpha_composite(frame_final, shadow_layer)
    frame_final = Image.alpha_composite(frame_final, gold_layer)
    
    # 8. MAKE CENTER PHOTO WINDOW 100% TRANSPARENT
    arr = np.array(frame_final)
    arr[WIN_Y0:WIN_Y1, WIN_X0:WIN_X1, 3] = 0
    frame_05 = Image.fromarray(arr, "RGBA")
    
    out_png = OUT_DIR / "frame_05_baroque_gold_3x4.png"
    frame_05.save(out_png, "PNG")
    print(f"Saved: {out_png}")
    return frame_05


# =========================================================================== #
# FRAME 06: 星穹经纬与微光 (Celestial Coordinates & Glimmer)
# =========================================================================== #

def generate_frame_06_celestial():
    print("Generating Frame 06: 星穹经纬与微光...")
    sky = create_midnight_navy_sky(W, H)
    gold_tex = create_pale_gold_texture(W, H)
    
    mask_im = Image.new("L", (W, H), 0)
    draw = ImageDraw.Draw(mask_im)
    
    # 1. Coordinate double-lines with tick marks (经纬刻度双线)
    cx0, cy0, cx1, cy1 = 80, 110, W - 80, H - 110
    cx0_in, cy0_in, cx1_in, cy1_in = 115, 145, W - 115, H - 145
    
    draw.rectangle([cx0, cy0, cx1, cy1], outline=255, width=2)
    draw.rectangle([cx0_in, cy0_in, cx1_in, cy1_in], outline=255, width=2)
    
    # Degree calibration ticks (刻度齿)
    tick_step = 16
    for x in range(cx0, cx1, tick_step):
        is_major = ((x - cx0) % (tick_step * 5)) == 0
        tick_h = 16 if is_major else 8
        draw.line([(x, cy0), (x, cy0 + tick_h)], fill=255, width=2 if is_major else 1)
        draw.line([(x, cy1), (x, cy1 - tick_h)], fill=255, width=2 if is_major else 1)
        
    for y in range(cy0, cy1, tick_step):
        is_major = ((y - cy0) % (tick_step * 5)) == 0
        tick_w = 16 if is_major else 8
        draw.line([(cx0, y), (cx0 + tick_w, y)], fill=255, width=2 if is_major else 1)
        draw.line([(cx1, y), (cx1 - tick_w, y)], fill=255, width=2 if is_major else 1)

    # 2. Celestial Star Trails & Astrolabe Orbits (天体星轨与星盘圆弧)
    dial_r = 210
    for cx_c, cy_c, a0, a1 in [(cx0, cy0, 0, 90), (cx1, cy0, 90, 180), (cx0, cy1, 270, 360), (cx1, cy1, 180, 270)]:
        draw.arc([cx_c - dial_r, cy_c - dial_r, cx_c + dial_r, cy_c + dial_r], a0, a1, fill=255, width=2)
        draw.arc([cx_c - dial_r + 25, cy_c - dial_r + 25, cx_c + dial_r - 25, cy_c + dial_r - 25], a0, a1, fill=255, width=1)
        draw.arc([cx_c - dial_r + 50, cy_c - dial_r + 50, cx_c + dial_r - 50, cy_c + dial_r - 50], a0, a1, fill=255, width=1)
        for a_deg in range(a0, a1, 10):
            rad = math.radians(a_deg)
            x_in = cx_c + (dial_r - 25) * math.cos(rad)
            y_in = cy_c + (dial_r - 25) * math.sin(rad)
            x_out = cx_c + dial_r * math.cos(rad)
            y_out = cy_c + dial_r * math.sin(rad)
            draw.line([(x_in, y_in), (x_out, y_out)], fill=255, width=1)

    # Sweeping elliptical celestial planetary orbits traversing the frame margins
    draw.arc([80, 40, W + 550, H - 120], 120, 290, fill=255, width=2)
    draw.arc([-550, 140, W - 80, H + 180], 300, 110, fill=255, width=2)
    draw.arc([140, -320, W - 140, H + 320], 15, 165, fill=255, width=1)

    # Constellation lines (faint stippled star links)
    constellations = [
        [(200, 400), (240, 480), (300, 520), (280, 600)],
        [(W - 200, 400), (W - 250, 490), (W - 280, 580)],
        [(200, H - 400), (250, H - 480), (310, H - 520)],
        [(W - 200, H - 400), (W - 260, H - 470), (W - 300, H - 540)]
    ]
    for c_pts in constellations:
        for i in range(len(c_pts) - 1):
            draw.line([c_pts[i], c_pts[i+1]], fill=180, width=1)
        for pt in c_pts:
            draw.ellipse([pt[0] - 3, pt[1] - 3, pt[0] + 3, pt[1] + 3], fill=255)

    # 3. Inner window framing lines
    draw.rectangle([WIN_X0 - 45, WIN_Y0 - 45, WIN_X1 + 45, WIN_Y1 + 45], outline=255, width=2)
    draw.rectangle([WIN_X0 - 28, WIN_Y0 - 28, WIN_X1 + 28, WIN_Y1 + 28], outline=255, width=1)
    draw.rectangle([WIN_X0 - 4, WIN_Y0 - 4, WIN_X1 + 4, WIN_Y1 + 4], outline=255, width=3)
    
    # Inner corner stars & brackets
    for bx, by in [(WIN_X0 - 28, WIN_Y0 - 28), (WIN_X1 + 28, WIN_Y0 - 28), (WIN_X0 - 28, WIN_Y1 + 28), (WIN_X1 + 28, WIN_Y1 + 28)]:
        draw_eight_pointed_star(draw, bx, by, r_outer=20, r_inner=6, r_mid=11)

    # 4. Eight-pointed starbursts (点点手绘微光八角星)
    star_positions_major = [
        (215, 245, 56, 16, 32),
        (W - 215, 245, 56, 16, 32),
        (215, H - 245, 56, 16, 32),
        (W - 215, H - 245, 56, 16, 32),
        (W // 2, 205, 72, 18, 42),    # Top center Polaris
        (W // 2, H - 205, 52, 14, 30)  # Bottom center
    ]
    for sx, sy, ro, ri, rm in star_positions_major:
        draw_eight_pointed_star(draw, sx, sy, ro, ri, rm)
        draw.ellipse([sx - ro * 1.25, sy - ro * 1.25, sx + ro * 1.25, sy + ro * 1.25], outline=255, width=1)
        draw.ellipse([sx - ro * 1.5, sy - ro * 1.5, sx + ro * 1.5, sy + ro * 1.5], outline=255, width=1)

    medium_stars = [
        (205, H // 2 - 300, 30, 9, 18),
        (205, H // 2 + 300, 30, 9, 18),
        (W - 205, H // 2 - 300, 30, 9, 18),
        (W - 205, H // 2 + 300, 30, 9, 18),
        (W // 2 - 340, 245, 26, 8, 15),
        (W // 2 + 340, 245, 26, 8, 15),
        (W // 2 - 340, H - 245, 26, 8, 15),
        (W // 2 + 340, H - 245, 26, 8, 15),
    ]
    for sx, sy, ro, ri, rm in medium_stars:
        draw_eight_pointed_star(draw, sx, sy, ro, ri, rm)

    # 5. Micro diamond stars & stardust dots
    np.random.seed(888)
    for _ in range(130):
        while True:
            rx = np.random.randint(120, W - 120)
            ry = np.random.randint(150, H - 150)
            if not (WIN_X0 - 25 <= rx <= WIN_X1 + 25 and WIN_Y0 - 25 <= ry <= WIN_Y1 + 25):
                break
        rad = np.random.choice([2, 3, 4, 6, 8])
        if rad >= 6:
            draw.polygon([(rx, ry - rad*2), (rx + rad, ry), (rx, ry + rad*2), (rx - rad, ry)], fill=255)
            draw.polygon([(rx - rad*2, ry), (rx, ry + rad), (rx + rad*2, ry), (rx, ry - rad)], fill=255)
            draw.ellipse([rx - 2, ry - 2, rx + 2, ry + 2], fill=255)
        else:
            draw.ellipse([rx - rad, ry - rad, rx + rad, ry + rad], fill=255)

    # Render 3D pale gold embossed lines
    gold_layer = render_embossed_gold(np.array(mask_im), np.array(gold_tex), light_deg=45.0, depth=3.2, spec_power=26.0)

    # Luminous warm glow layer for stars
    glow_mask = mask_im.filter(ImageFilter.GaussianBlur(radius=9))
    glow_arr = np.array(glow_mask).astype(float) / 255.0
    glow_im = Image.new("RGBA", (W, H), (255, 238, 175, 0))
    glow_im.putalpha(Image.fromarray((glow_arr * 140).astype(np.uint8)))

    # Composite onto midnight navy sky
    frame_final = sky.convert("RGBA")
    frame_final = Image.alpha_composite(frame_final, glow_im)
    frame_final = Image.alpha_composite(frame_final, gold_layer)

    # 6. MAKE CENTER PHOTO WINDOW 100% TRANSPARENT
    arr = np.array(frame_final)
    arr[WIN_Y0:WIN_Y1, WIN_X0:WIN_X1, 3] = 0
    frame_06 = Image.fromarray(arr, "RGBA")

    out_png = OUT_DIR / "frame_06_celestial_star_3x4.png"
    frame_06.save(out_png, "PNG")
    print(f"Saved: {out_png}")
    return frame_06


# =========================================================================== #
# Mockup Presentation with MiLens Official Hero Pet
# =========================================================================== #

def generate_preview_mockups(frame_05, frame_06):
    print("Generating presentation mockups with official hero pet...")
    
    if HERO_CAT_PATH.exists():
        pet_img = Image.open(HERO_CAT_PATH).convert("RGB")
    else:
        pet_img = Image.new("RGB", (WIN_W, WIN_H), (230, 200, 170))
        
    pet_fitted = pet_img.resize((WIN_W, WIN_H), Image.Resampling.LANCZOS)
    
    # 1. Mockup 05
    mockup_05 = Image.new("RGBA", (W, H), (255, 255, 255, 255))
    mockup_05.paste(pet_fitted, (WIN_X0, WIN_Y0))
    mockup_05 = Image.alpha_composite(mockup_05, frame_05)
    mockup_05_path = OUT_DIR / "mockup_05_baroque_gold.jpg"
    mockup_05.convert("RGB").save(mockup_05_path, "JPEG", quality=96)
    
    # 2. Mockup 06
    mockup_06 = Image.new("RGBA", (W, H), (255, 255, 255, 255))
    mockup_06.paste(pet_fitted, (WIN_X0, WIN_Y0))
    mockup_06 = Image.alpha_composite(mockup_06, frame_06)
    mockup_06_path = OUT_DIR / "mockup_06_celestial_star.jpg"
    mockup_06.convert("RGB").save(mockup_06_path, "JPEG", quality=96)
    
    # 3. High-res Side-by-side Overview Presentation
    overview_w = 2100
    overview_h = 1500
    overview = Image.new("RGB", (overview_w, overview_h), (247, 245, 241))
    
    thumb_w, thumb_h = 900, int(900 * 4 / 3)  # 900 x 1200
    t05 = mockup_05.resize((thumb_w, thumb_h), Image.Resampling.LANCZOS)
    t06 = mockup_06.resize((thumb_w, thumb_h), Image.Resampling.LANCZOS)
    
    spacing = (overview_w - thumb_w * 2) // 3
    y_pos = (overview_h - thumb_h) // 2
    
    def paste_with_shadow(bg, img, x, y):
        shadow = Image.new("RGBA", (img.width + 40, img.height + 40), (0, 0, 0, 0))
        sdraw = ImageDraw.Draw(shadow)
        sdraw.rectangle([20, 20, img.width + 20, img.height + 20], fill=(0, 0, 0, 70))
        shadow = shadow.filter(ImageFilter.GaussianBlur(15))
        bg.paste(shadow, (x - 20, y - 10), shadow)
        bg.paste(img, (x, y))

    paste_with_shadow(overview, t05, spacing, y_pos)
    paste_with_shadow(overview, t06, spacing * 2 + thumb_w, y_pos)
    
    overview_path = OUT_DIR / "frames_proposal_overview.jpg"
    overview.save(overview_path, "JPEG", quality=96)
    print(f"Saved high-res presentation mockups to {OUT_DIR}")


if __name__ == "__main__":
    f05 = generate_frame_05_baroque()
    f06 = generate_frame_06_celestial()
    generate_preview_mockups(f05, f06)
    print("Execution complete.")
