#!/usr/bin/env python3
"""
convert_icons.py
Converts PNG icons -> ComputerCraft Lua blit format (icons.lua)

Technique: "half-pixel" rendering
  - Each CC terminal character cell is split top/bottom using char(143) = upper-half block (▀)
  - term.blit(chars, fg, bg): fg = top pixel color, bg = bottom pixel color
  - Result: 2 vertical pixels per character row -> double vertical resolution

Color quality: Floyd-Steinberg dithering on the CC 16-color palette
  -> much better than nearest-neighbor alone for pixel-art sprites

Requires: Pillow  (pip install Pillow)
"""

from PIL import Image
import os

# ─────────────────────────────────────────────────────────────
# CC:Tweaked 16-color palette  (blit hex digit -> sRGB)
# '0'=white … 'f'=black   (same order as CC colors.* constants)
# ─────────────────────────────────────────────────────────────
CC_PALETTE = [
    ('0', (240, 240, 240)),   # white
    ('1', (242, 178,  51)),   # orange
    ('2', (229, 127, 216)),   # magenta
    ('3', (153, 178, 242)),   # lightBlue
    ('4', (222, 222, 108)),   # yellow
    ('5', (127, 204,  25)),   # lime
    ('6', (242, 178, 204)),   # pink
    ('7', ( 76,  76,  76)),   # gray
    ('8', (153, 153, 153)),   # lightGray
    ('9', ( 76, 153, 178)),   # cyan
    ('a', (178, 102, 229)),   # purple
    ('b', ( 51, 102, 204)),   # blue
    ('c', (127, 102,  76)),   # brown
    ('d', ( 87, 166,  78)),   # green
    ('e', (204,  76,  76)),   # red
    ('f', ( 17,  17,  17)),   # black
]
CC_PALETTE_DICT = dict(CC_PALETTE)

# ─────────────────────────────────────────────────────────────
# Icon display dimensions
# ─────────────────────────────────────────────────────────────
ICON_CHAR_W = 5   # characters wide in the CC terminal
ICON_CHAR_H = 4   # characters tall  (half-pixel: 2 pixel rows per char row)
ICON_PIX_W  = ICON_CHAR_W
ICON_PIX_H  = ICON_CHAR_H * 2   # = 8 pixel rows

# CC upper-half-block character (decimal 143, 0x8F)
# When used with blit(): fg color fills top half, bg color fills bottom half
UPPER_HALF = 143

# Icons to convert (Lua key -> filename)
ICONS = [
    ('diamond',     'diamond.png'),
    ('emerald',     'emerald.png'),
    ('ender_pearl', 'ender_pearl.png'),
    ('gold_ingot',  'gold_ingot.png'),
    ('iron_ingot',  'iron_ingot.png'),
    ('nether_star', 'nether_star.png'),
]

# ─────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────
def nearest_cc(r, g, b):
    """Return the blit hex digit of the closest CC palette color (perceptual)."""
    best, best_d = 'f', float('inf')
    for ch, (cr, cg, cb) in CC_PALETTE:
        # Luma-weighted squared distance (perceptual)
        d = (0.299*(r-cr))**2 + (0.587*(g-cg))**2 + (0.114*(b-cb))**2
        if d < best_d:
            best_d, best = d, ch
    return best


def convert_image(filepath):
    """
    Load a PNG, resize, dither, and return list of (lua_chars, fg_str, bg_str).
    One tuple per character row.  fg_str and bg_str are 9-char hex digit strings.
    Transparent pixels map to 'f' (black).
    """
    img = Image.open(filepath).convert('RGBA')
    img = img.resize((ICON_PIX_W, ICON_PIX_H), Image.LANCZOS)

    # Build a flat list of [r, g, b, a] so we can do in-place error diffusion
    px = []
    for y in range(ICON_PIX_H):
        row = []
        for x in range(ICON_PIX_W):
            row.append(list(img.getpixel((x, y))))
        px.append(row)

    # Floyd-Steinberg dithering over the CC palette
    cc = [['f'] * ICON_PIX_W for _ in range(ICON_PIX_H)]

    for y in range(ICON_PIX_H):
        for x in range(ICON_PIX_W):
            r, g, b, a = px[y][x]
            if a < 64:
                cc[y][x] = 'f'   # transparent -> black background
                continue

            ch = nearest_cc(r, g, b)
            cc[y][x] = ch
            nr, ng, nb = CC_PALETTE_DICT[ch]

            er, eg, eb = r - nr, g - ng, b - nb

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

    # Combine pairs of pixel rows -> character rows (half-pixel)
    rows = []
    for cy in range(ICON_CHAR_H):
        top_row = cc[cy * 2]
        bot_row = cc[cy * 2 + 1]

        chars_lua = '"'   # will contain Lua string literal contents
        fg_str    = ''
        bg_str    = ''

        for cx in range(ICON_CHAR_W):
            tc = top_row[cx]
            bc = bot_row[cx]

            if tc == bc:
                # Both halves same color: use a plain space (no char needed)
                chars_lua += ' '
                fg_str    += tc
                bg_str    += tc
            else:
                # Upper-half block: fg = top pixel, bg = bottom pixel
                chars_lua += f'\\{UPPER_HALF}'
                fg_str    += tc
                bg_str    += bc

        chars_lua += '"'
        rows.append((chars_lua, fg_str, bg_str))

    return rows


# ─────────────────────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────────────────────
def main():
    script_dir  = os.path.dirname(os.path.abspath(__file__))
    output_path = os.path.join(script_dir, 'icons.lua')

    lines = [
        '-- icons.lua',
        '-- Auto-generated by convert_icons.py  --  DO NOT EDIT BY HAND',
        '--',
        '-- Half-pixel blit icons for ComputerCraft casino.',
        '-- Each icon[i] = { chars_string, fg_hex_string, bg_hex_string }',
        '-- Use with:  mon.blit(row[1], row[2], row[3])',
        '-- Upper-half-block char (\\143): fg=top pixel, bg=bottom pixel.',
        '',
        'local M = {}',
        f'M.CHAR_WIDTH  = {ICON_CHAR_W}',
        f'M.CHAR_HEIGHT = {ICON_CHAR_H}',
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
        for (lua_chars, fg, bg) in rows:
            lines.append(f'  {{ {lua_chars}, "{fg}", "{bg}" }},')
        lines.append('}')
        lines.append('')
        converted += 1
        print('OK')

    lines.append('return M')
    lines.append('')

    # Write as pure ASCII (all non-ASCII are represented as \NNN escapes)
    with open(output_path, 'w', encoding='ascii') as f:
        f.write('\n'.join(lines))

    print(f'\nDone!  {converted} icons -> {output_path}')
    print('Copy  icons.lua  and  casino.lua  to your CC computer.')


if __name__ == '__main__':
    print('ComputerCraft Icon Converter  (half-pixel + Floyd-Steinberg dither)')
    print('=' * 60)
    main()
