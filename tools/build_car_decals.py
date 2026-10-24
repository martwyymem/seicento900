"""Generate the racing decal atlas for the Seicento cars (godot/models/car_decals.png, read by race_car_visual.gd).
Door number plates (1-16), windscreen sunstrips, bonnet rally plates and sponsor stacks.
Every sponsor is made up: no real brands. Run from the repo root: python3 tools/build_car_decals.py
"""
import os
from PIL import Image, ImageDraw, ImageFont


def fit_font(draw, text, path, size, max_w):
    """The largest font size up to `size` whose text fits in max_w pixels."""
    while size > 8:
        f = ImageFont.truetype(path, size)
        b = draw.textbbox((0, 0), text, font=f)
        if b[2] - b[0] <= max_w:
            return f
        size -= 2
    return ImageFont.truetype(path, size)

def make_atlas(out_path):
    W, H = 2048, 2048
    atlas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(atlas)

    font_path_bold = "godot/fonts/Archivo.ttf"
    font_path_cond = "godot/fonts/Oswald.ttf"
    
    # Fonts
    f_num = ImageFont.truetype(font_path_bold, 116)
    f_hdr = ImageFont.truetype(font_path_cond, 24)
    f_sub = ImageFont.truetype(font_path_cond, 18)
    f_sunstrip = ImageFont.truetype(font_path_bold, 62)
    f_sunstrip_sub = ImageFont.truetype(font_path_cond, 28)
    f_plate_hdr = ImageFont.truetype(font_path_cond, 42)
    f_plate_num = ImageFont.truetype(font_path_bold, 140)
    f_spon_lg = ImageFont.truetype(font_path_bold, 44)
    f_spon_sm = ImageFont.truetype(font_path_cond, 26)

    # 1. Door number plates (16 squares, grid 4x4 in 0..1024, 0..1024)
    headers = [
        ("SEICENTO 900 CUP", (190, 20, 30), (255, 255, 255)),
        ("OLIO VELOCE", (25, 25, 30), (255, 210, 0)),
        ("GOMME TORINO", (18, 55, 130), (255, 255, 255)),
        ("TROFEO SEICENTO", (20, 100, 50), (255, 255, 255)),
    ]

    for k in range(16):
        num = k + 1
        col = k % 4
        row = k // 4
        x0 = col * 256 + 12
        y0 = row * 256 + 12
        x1 = x0 + 232
        y1 = y0 + 232

        hdr_text, hdr_bg, hdr_fg = headers[k % len(headers)]

        # Plate body: white with dark border
        draw.rounded_rectangle([x0, y0, x1, y1], radius=16, fill=(248, 248, 246, 255), outline=(20, 22, 25, 255), width=5)
        # Inner fine line
        draw.rounded_rectangle([x0 + 4, y0 + 4, x1 - 4, y1 - 4], radius=12, outline=(180, 185, 190, 180), width=2)

        # Header bar
        draw.rounded_rectangle([x0 + 4, y0 + 4, x1 - 4, y0 + 52], radius=10, fill=hdr_bg)
        # Header text
        bbox = draw.textbbox((0, 0), hdr_text, font=f_hdr)
        tw = bbox[2] - bbox[0]
        draw.text((x0 + (232 - tw) // 2, y0 + 14), hdr_text, font=f_hdr, fill=hdr_fg)

        # Racing Number
        num_str = str(num)
        nbox = draw.textbbox((0, 0), num_str, font=f_num)
        nw = nbox[2] - nbox[0]
        nh = nbox[3] - nbox[1]
        draw.text((x0 + (232 - nw) // 2, y0 + 56 + (130 - nh) // 2), num_str, font=f_num, fill=(18, 20, 24, 255))

        # Bottom bar (sponsors & flag stripe)
        draw.line([x0 + 8, y1 - 32, x1 - 8, y1 - 32], fill=(200, 204, 210, 255), width=2)
        # Tricolore or Polish flag pip
        if k % 2 == 0:
            # Italian flag pip
            draw.rectangle([x0 + 16, y1 - 24, x0 + 32, y1 - 10], fill=(0, 146, 70, 255))
            draw.rectangle([x0 + 32, y1 - 24, x0 + 48, y1 - 10], fill=(255, 255, 255, 255))
            draw.rectangle([x0 + 48, y1 - 24, x0 + 64, y1 - 10], fill=(206, 43, 55, 255))
        else:
            # Polish flag pip
            draw.rectangle([x0 + 16, y1 - 24, x0 + 64, y1 - 17], fill=(255, 255, 255, 255))
            draw.rectangle([x0 + 16, y1 - 17, x0 + 64, y1 - 10], fill=(220, 30, 45, 255))
            
        spon = ["LAMPO", "VELOCE", "TORINO", "PISTA"][k % 4]
        sbox = draw.textbbox((0, 0), spon, font=f_sub)
        draw.text((x1 - 16 - (sbox[2] - sbox[0]), y1 - 26), spon, font=f_sub, fill=(60, 65, 70, 255))

    # 2. Windscreen Sunstrips (4 variations, 2048 x 128 each at y = 1024..1536)
    sunstrips = [
        # (title, subtitle, bg_col, fg_col, accent_col)
        ("•  SEICENTO 900 CUP  •", "CAMPIONATO TROFEO", (16, 24, 48, 255), (255, 255, 255), (210, 35, 45)),
        ("OLIO VELOCE  •  CORSE", "LUBRIFICANTI DA GARA", (18, 18, 20, 255), (255, 215, 0), (255, 215, 0)),
        ("GOMME TORINO  •  COMPETIZIONE", "PNEUMATICI RADIALI", (14, 45, 115, 255), (255, 255, 255), (230, 40, 30)),
        ("CANDELE LAMPO  •  RALLY", "SISTEMI DI ACCENSIONE", (28, 30, 32, 255), (255, 130, 20), (255, 130, 20)),
    ]

    for idx, (title, sub, bg, fg, acc) in enumerate(sunstrips):
        sy0 = 1024 + idx * 128
        sy1 = sy0 + 128
        # Background visor
        draw.rectangle([0, sy0, W, sy1], fill=bg)
        # Gradient / side flashes
        draw.polygon([(0, sy0), (160, sy0), (120, sy1), (0, sy1)], fill=acc)
        draw.polygon([(W - 160, sy0), (W, sy0), (W, sy1), (W - 120, sy1)], fill=acc)
        draw.line([0, sy1 - 4, W, sy1 - 4], fill=acc, width=4)

        # Title
        tbox = draw.textbbox((0, 0), title, font=f_sunstrip)
        tw = tbox[2] - tbox[0]
        draw.text(((W - tw) // 2, sy0 + 16), title, font=f_sunstrip, fill=fg)

        # Subtitle
        sbox = draw.textbbox((0, 0), sub, font=f_sunstrip_sub)
        sw = sbox[2] - sbox[0]
        draw.text(((W - sw) // 2, sy0 + 84), sub, font=f_sunstrip_sub, fill=(200, 205, 215, 240))

    # 3. Bonnet Rally / Competition Plates (x = 1024..2048, y = 0..1024)
    # 4 plates of 512x512
    plate_specs = [
        # (title, subtitle, num, bg, fg, shape)
        ("RAJD BÓR", "BRZESZCZE", "1", (210, 30, 40), (255, 255, 255)),
        ("TROFEO", "SEICENTO", "7", (20, 24, 28), (255, 210, 0)),
        ("POLISH TOUR", "MISTRZOSTWA", "12", (245, 245, 248), (20, 25, 30)),
        ("RALLY SPRINT", "STAGE", "99", (15, 60, 135), (255, 255, 255)),
    ]

    for pi, (ptitle, psub, pnum, pbg, pfg) in enumerate(plate_specs):
        col = pi % 2
        row = pi // 2
        px0 = 1024 + col * 512 + 24
        py0 = row * 512 + 24
        px1 = px0 + 464
        py1 = py0 + 464

        # Plate backplate
        draw.rounded_rectangle([px0, py0, px1, py1], radius=32, fill=(255, 255, 255, 255), outline=(20, 20, 20, 255), width=8)
        # Header arch / banner
        draw.rounded_rectangle([px0 + 8, py0 + 8, px1 - 8, py0 + 130], radius=24, fill=pbg)
        
        tbox = draw.textbbox((0, 0), ptitle, font=f_plate_hdr)
        tw = tbox[2] - tbox[0]
        draw.text((px0 + (464 - tw) // 2, py0 + 26), ptitle, font=f_plate_hdr, fill=pfg)

        sbox = draw.textbbox((0, 0), psub, font=f_sub)
        sw = sbox[2] - sbox[0]
        draw.text((px0 + (464 - sw) // 2, py0 + 84), psub, font=f_sub, fill=pfg)

        # Main bold number
        nbox = draw.textbbox((0, 0), pnum, font=f_plate_num)
        nw = nbox[2] - nbox[0]
        draw.text((px0 + (464 - nw) // 2, py0 + 170), pnum, font=f_plate_num, fill=(20, 22, 26, 255))

        # Bottom sponsors
        draw.line([px0 + 20, py1 - 70, px1 - 20, py1 - 70], fill=(210, 215, 220, 255), width=4)
        sp_line = "OLIO VELOCE  •  GOMME TORINO"
        spbox = draw.textbbox((0, 0), sp_line, font=f_sub)
        spw = spbox[2] - spbox[0]
        draw.text((px0 + (464 - spw) // 2, py1 - 50), sp_line, font=f_sub, fill=(70, 75, 80, 255))

    # 4. Technical Sponsor Stacks (y = 1536..2048, 4 panels each 1024x256)
    stacks = [
        [("OLIO VELOCE", (255, 210, 0), (20, 20, 22)), ("GOMME TORINO", (255, 255, 255), (15, 50, 120)), ("CANDELE LAMPO", (255, 255, 255), (220, 90, 15))],
        [("CAFFÈ PISTA", (245, 230, 200), (65, 38, 25)), ("BANCA AUTODROMO", (255, 255, 255), (10, 105, 55)), ("RADIO CIRCUITO", (20, 20, 20), (255, 215, 0))],
        [("OPONY BESKID", (255, 255, 255), (200, 25, 35)), ("ISKRA ZAPŁON", (255, 255, 255), (20, 50, 110)), ("KUBEŁ SPORT", (255, 255, 255), (25, 25, 28))],
        [("HAMULCE ŚLĄSK", (255, 255, 255), (195, 20, 25)), ("FELGI WISŁA", (20, 20, 20), (240, 240, 245)), ("AMOR TYCHY", (255, 220, 0), (15, 60, 140))],
    ]

    for si, sponsors in enumerate(stacks):
        col = si % 2
        row = si // 2
        sx0 = col * 1024 + 16
        sy0 = 1536 + row * 256 + 16
        
        for sj, (sname, stxt_col, sbg_col) in enumerate(sponsors):
            bx0 = sx0 + sj * 328
            by0 = sy0 + 36
            bx1 = bx0 + 310
            by1 = by0 + 130
            # Rounded sponsor badge
            draw.rounded_rectangle([bx0, by0, bx1, by1], radius=14, fill=sbg_col, outline=(255, 255, 255, 180), width=3)
            # Text
            f_fit = fit_font(draw, sname, font_path_bold, 44, 284)
            tbox = draw.textbbox((0, 0), sname, font=f_fit)
            tw = tbox[2] - tbox[0]
            th = tbox[3] - tbox[1]
            draw.text((bx0 + (310 - tw) // 2 - tbox[0], by0 + (130 - th) // 2 - tbox[1]), sname, font=f_fit, fill=stxt_col)

    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    atlas.save(out_path, "PNG")
    print(f"Saved decal atlas to {out_path} ({W}x{H})")

if __name__ == "__main__":
    make_atlas("godot/models/car_decals.png")
