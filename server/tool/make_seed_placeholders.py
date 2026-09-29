"""Writes the placeholder screenshots of the seed listings.

The seed listings' models come from the private test-assets checkout, so the
repository ships neutral placeholders instead of renders of them. With
test-assets and Blender at hand, tool/render_seed_screenshots.py renders the
real ones locally.

    python tool/make_seed_placeholders.py        (needs Pillow)

Writes server/seed/screenshots/<slug>.jpg (1280x720).
"""
import os

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, '..', 'seed', 'screenshots')
FONT = os.path.join(HERE, '..', '..', '..', 'lumina', 'lumina_ui', 'assets', 'fonts', 'JetBrainsMono-Bold.ttf')

LISTINGS = {
    'barrel': ('Barrel', (46, 74, 98)),
    'access-cards': ('Access Cards', (58, 52, 96)),
    'ac-units': ('AC Units', (40, 84, 84)),
    'banana-bunch': ('Banana Bunch', (92, 82, 36)),
    'chair': ('Chair', (86, 56, 42)),
    'jerry-can': ('Jerry Can', (84, 44, 44)),
}


def font(size):
    try:
        return ImageFont.truetype(FONT, size)
    except OSError:
        return ImageFont.load_default()


def placeholder(title, colour):
    w, h = 1280, 720
    img = Image.new('RGB', (w, h))
    px = img.load()
    for y in range(h):
        t = y / (h - 1)
        row = tuple(int(c * (1.0 - 0.55 * t) + 12 * t) for c in colour)
        for x in range(w):
            px[x, y] = row
    draw = ImageDraw.Draw(img)
    big, small = font(72), font(26)
    tw = draw.textlength(title, font=big)
    draw.text(((w - tw) / 2, h / 2 - 70), title, font=big, fill=(236, 240, 244))
    note = 'Lumina Marketplace sample listing'
    nw = draw.textlength(note, font=small)
    draw.text(((w - nw) / 2, h / 2 + 30), note, font=small, fill=(190, 198, 206))
    return img


def main():
    os.makedirs(OUT, exist_ok=True)
    for slug, (title, colour) in LISTINGS.items():
        path = os.path.join(OUT, f'{slug}.jpg')
        placeholder(title, colour).save(path, 'JPEG', quality=88)
        print(path)


if __name__ == '__main__':
    main()
