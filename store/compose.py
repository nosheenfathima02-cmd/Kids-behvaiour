"""Builds the store images from the raw screenshots (store/screenshots.js).

python3 store/compose.py <raw play dir> <raw ios dir>
Writes store/screenshots/{play,ios}/ and store/graphics/.
"""
import pathlib
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = pathlib.Path(__file__).parent
GREEN = (13, 107, 91)
GOLD = (240, 182, 40)
WHITE = (255, 255, 255)
BOLD = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
REGULAR = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'

CAPTIONS = {
    '1-kid-home': ('Salah times, stars and', 'a reminder every day'),
    '2-kid-jobs': ('Tasks lock when', 'their time is over'),
    '3-kid-rewards': ('Homework, tests and', "Qur'an competitions"),
    '4-mom-today': ('Parents see every', 'tick, live'),
    '5-mom-school': ('Add school work in', 'a few taps'),
    '6-link-device': ("Link your child's", 'device with a QR code'),
}
SIZES = {'play': (1080, 1920), 'ios': (1290, 2796)}


def rounded(img, radius):
    mask = Image.new('L', img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, img.width - 1, img.height - 1], radius, fill=255)
    out = img.convert('RGBA')
    out.putalpha(mask)
    return out


def frame(raw_path, size, caption):
    w, h = size
    canvas = Image.new('RGB', size, GREEN)
    d = ImageDraw.Draw(canvas)
    font = ImageFont.truetype(BOLD, int(w * 0.068))
    top = int(h * 0.05)
    for i, line in enumerate(caption):
        tw = d.textlength(line, font=font)
        d.text(((w - tw) / 2, top + i * font.size * 1.25), line, font=font, fill=WHITE if i else GOLD)
    caption_h = top + len(caption) * font.size * 1.25 + h * 0.035
    shot = Image.open(raw_path)
    scale = min((w * 0.84) / shot.width, (h - caption_h - h * 0.04) / shot.height)
    shot = shot.resize((int(shot.width * scale), int(shot.height * scale)), Image.LANCZOS)
    shot = rounded(shot, int(w * 0.045))
    x = (w - shot.width) // 2
    y = int(caption_h)
    shadow = Image.new('RGBA', size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [x, y + 12, x + shot.width, y + shot.height + 12], int(w * 0.045), fill=(0, 0, 0, 90))
    canvas = Image.alpha_composite(canvas.convert('RGBA'), shadow.filter(ImageFilter.GaussianBlur(18)))
    canvas.alpha_composite(shot, (x, y))
    return canvas.convert('RGB')


def feature_graphic(icon_path, out):
    w, h = 1024, 500
    g = Image.new('RGB', (w, h), GREEN)
    icon = Image.open(icon_path).convert('RGB').resize((300, 300), Image.LANCZOS)
    g.paste(rounded(icon, 60), (70, 100), rounded(icon, 60))
    d = ImageDraw.Draw(g)
    d.text((420, 140), 'Super Mom', font=ImageFont.truetype(BOLD, 74), fill=WHITE)
    small = ImageFont.truetype(REGULAR, 34)
    d.text((424, 250), 'Salah, homework and good', font=small, fill=GOLD)
    d.text((424, 296), 'habits for Muslim kids', font=small, fill=GOLD)
    g.save(out)


def main():
    raw = {'play': pathlib.Path(sys.argv[1]), 'ios': pathlib.Path(sys.argv[2])}
    for target, size in SIZES.items():
        out_dir = ROOT / 'screenshots' / target
        out_dir.mkdir(parents=True, exist_ok=True)
        for name, caption in CAPTIONS.items():
            frame(raw[target] / f'{name}.png', size, caption).save(out_dir / f'{name}.png')
    graphics = ROOT / 'graphics'
    graphics.mkdir(exist_ok=True)
    icon = ROOT.parent / 'app' / 'assets' / 'icon' / 'icon.png'
    Image.open(icon).resize((512, 512), Image.LANCZOS).save(graphics / 'icon-512.png')
    feature_graphic(icon, graphics / 'feature-graphic.png')
    print('done')


if __name__ == '__main__':
    main()
