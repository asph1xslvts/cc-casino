#!/usr/bin/env python3
"""
convert_icons.py
Converts PNG icons -> OC-palette Lua format (icons.lua)

Technique: "half-pixel" rendering with OC Tier 2 custom palette
  - Each OC GPU character uses upper-half-block (U+2580) as the character
  - gpu.setForeground = top pixel color, gpu.setBackground = bottom pixel color
  - Result: 2 vertical pixels per character row -> double vertical resolution

Color quality: Floyd-Steinberg dithering against the 8-color OC palette
  - palette is stored in M.PALETTE and applied via gpu.setPaletteColor at runtime

Requires: Pillow  (pip install Pillow)
"""

from PIL import Image
import os

# OC Tier 2 custom palette (8 colors, set via gpu.setPaletteColor)
# Computed at runtime from actual PNG pixels using median-cut quantization.
# Slots 0 and 1 are forced (black bg + white text for UI readability).
# Slots 2-7 are the 6 most representative colors from all 6 icon textures.

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

# OC terminal characters are square, so half-block pixels are 2x taller than wide.
# To display Minecraft 1:1 textures without vertical stretching:
#   ICON_PIX_H must equal ICON_PIX_W  (square source)
#   ICON_CHAR_H = ICON_PIX_H // 2
ICON_CHAR_W = 14           # chars wide per icon
ICON_PIX_W  = ICON_CHAR_W  # = 14 source pixels wide
ICON_PIX_H  = ICON_CHAR_W  # = 14 source pixels tall (SQUARE -> correct aspect)
ICON_CHAR_H = ICON_PIX_H // 2  # = 7 chars tall

ICONS = [
    ('diamond',     'diamond.png'),
    ('emerald',     'emerald.png'),
    ('ender_pearl', 'ender_pearl.png'),
    ('gold_ingot',  'gold_ingot.png'),
    ('iron_ingot',  'iron_ingot.png'),
    ('nether_star', 'nether_star.png'),
]


def compute_palette():
    """Compute optimal 8-color palette from actual PNG files.
    Slot 0 = forced near-black (UI background).
    Slot 1 = forced near-white (UI text).
    Slots 2-7 = 6 best colors extracted from all icon pixels via median-cut.
    """
    pixels = []
    for _, fname in ICONS:
        path = os.path.join(SCRIPT_DIR, fname)
        if not os.path.exists(path):
            continue
        img = Image.open(path).convert('RGBA').resize((ICON_PIX_W, ICON_PIX_H), Image.LANCZOS)
        for y in range(ICON_PIX_H):
            for x in range(ICON_PIX_W):
                r, g, b, a = img.getpixel((x, y))
                if a >= 64:
                    pixels.append((r, g, b))

    n_free = 6
    forced = [(0x0A, 0x0A, 0x0A), (0xEE, 0xEE, 0xEE)]

    if len(pixels) >= n_free:
        combined = Image.new('RGB', (len(pixels), 1))
        combined.putdata(pixels)
        try:
            quant = combined.quantize(n_free, method=Image.Quantize.MEDIANCUT)
        except Exception:
            quant = combined.quantize(n_free)
        raw = quant.getpalette()[:n_free * 3]
        computed = [(raw[i*3], raw[i*3+1], raw[i*3+2]) for i in range(n_free)]
    else:
        computed = [(0x33, 0x66, 0xCC), (0xDD, 0xAA, 0x11), (0x33, 0xBB, 0x33),
                    (0xCC, 0x33, 0x33), (0x99, 0x44, 0xBB), (0x88, 0x88, 0x88)]

    return forced + computed


OC_PALETTE = compute_palette()


def nearest_idx(r, g, b):
    best, best_d = 0, float('inf')
    for i, (cr, cg, cb) in enumerate(OC_PALETTE):
        d = 0.299*(r-cr)**2 + 0.587*(g-cg)**2 + 0.114*(b-cb)**2
        if d < best_d:
            best_d, best = d, i
    return best


BG_IDX = nearest_idx(0x0A, 0x0A, 0x0A)


def convert_image(filepath):
    img = Image.open(filepath).convert('RGBA')
    img = img.resize((ICON_PIX_W, ICON_PIX_H), Image.LANCZOS)
    px = []
    for y in range(ICON_PIX_H):
        row = []
        for x in range(ICON_PIX_W):
            row.append(list(img.getpixel((x, y))))
        px.append(row)

    indices = [[BG_IDX] * ICON_PIX_W for _ in range(ICON_PIX_H)]
    for y in range(ICON_PIX_H):
        for x in range(ICON_PIX_W):
            r, g, b, a = px[y][x]
            if a < 64:
                indices[y][x] = BG_IDX
                continue
            idx = nearest_idx(r, g, b)
            indices[y][x] = idx
            cr, cg, cb = OC_PALETTE[idx]
            er, eg, eb = r - cr, g - cg, b - cb
            def push(dx, dy, weight):
                nx, ny = x + dx, y + dy
                if 0 <= nx < ICON_PIX_W and 0 <= ny < ICON_PIX_H:
                    p = px[ny][nx]
                    if p[3] >= 64:
                        p[0] = max(0, min(255, p[0] + int(er * weight)))
                        p[1] = max(0, min(255, p[1] + int(eg * weight)))
                        p[2] = max(0, min(255, p[2] + int(eb * weight)))
            push( 1,  0, 7/16)
            push(-1,  1, 3/16)
            push( 0,  1, 5/16)
            push( 1,  1, 1/16)

    rows = []
    for cy in range(ICON_CHAR_H):
        top_row = indices[cy * 2]
        bot_row = indices[cy * 2 + 1]
        fg_bytes = bytes([top_row[cx] + 1 for cx in range(ICON_CHAR_W)])
        bg_bytes = bytes([bot_row[cx] + 1 for cx in range(ICON_CHAR_W)])
        rows.append((fg_bytes, bg_bytes))
    return rows

def bytes_to_lua(b):
    return '"' + ''.join(f'\\{v}' for v in b) + '"'

def main():
    script_dir  = os.path.dirname(os.path.abspath(__file__))
    output_path = os.path.join(script_dir, 'icons.lua')

    print(f'Computed palette ({len(OC_PALETTE)} colors from PNG data):')
    for i, (r, g, b) in enumerate(OC_PALETTE):
        tag = '(bg)' if i == 0 else '(text)' if i == 1 else ''
        print(f'  [{i}] #{r:02X}{g:02X}{b:02X}  {tag}')

    palette_lua = ', '.join(f'0x{r:02X}{g:02X}{b:02X}' for r, g, b in OC_PALETTE)
    lines = [
        '-- icons.lua',
        '-- Auto-generated by convert_icons.py  --  DO NOT EDIT BY HAND',
        '-- OC Tier 2 half-pixel icons with custom 8-color palette.',
        '-- M.PALETTE[1..8] = OC RGB colors; set via gpu.setPaletteColor(i-1, color)',
        '-- Each icon row: { fg_bytes, bg_bytes }',
        '--   fg_bytes:byte(col) = PALETTE index (1..8) for TOP pixel',
        '--   bg_bytes:byte(col) = PALETTE index (1..8) for BOTTOM pixel',
        '',
        'local M = {}',
        f'M.CHAR_WIDTH  = {ICON_CHAR_W}',
        f'M.CHAR_HEIGHT = {ICON_CHAR_H}',
        f'M.PALETTE = {{{palette_lua}}}',
        '',
    ]
    converted = 0
    for name, filename in ICONS:
        filepath = os.path.join(script_dir, filename)
        if not os.path.exists(filepath):
            print(f'  [skip] {filename} not found')
            continue
        print(f'  Converting {filename} ...', end=' ')
        rows = convert_image(filepath)
        lines.append(f'M.{name} = {{')
        for (fg_b, bg_b) in rows:
            lines.append(f'  {{{bytes_to_lua(fg_b)}, {bytes_to_lua(bg_b)}}},')
        lines.append('}')
        lines.append('')
        converted += 1
        print('OK')
    lines.append('return M')
    lines.append('')
    content = '\n'.join(lines)
    with open(output_path, 'wb') as f:
        f.write(content.encode('ascii').replace(b'\r\n', b'\n'))
    print(f'Wrote {output_path}  ({converted} icons, {len(OC_PALETTE)} palette colors)')

if __name__ == '__main__':
    main()