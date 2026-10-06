#!/usr/bin/env python3
"""App Store 用スクリーンショットを作る。

使い方:
  1. 実機かシミュレーターで画面を撮り、raw/ja/01.png〜05.png（英語は raw/en/）に置く。
  2. python3 compose.py           → out/ja/01.png … out/en/05.png（1320×2868, 6.9インチ用）

文言は CAPTIONS を直す。必要なもの: Pillow（pip install pillow）。
画面が無い番号はグレーの仮画面で作る（レイアウト確認用）。
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).resolve().parent
SIZE = (1320, 2868)
GROUND = (245, 245, 242)
INK = (17, 17, 17)
SECONDARY = (110, 110, 106)
ACCENT = (255, 91, 20)

CAPTIONS = {
    "ja": [
        ("一瞬を撮って、", "日常へ戻る。"),
        ("一日を、", "一本の時間軸に。"),
        ("撮っていない時間も、", "一日のうち。"),
        ("日付に、", "ひとこと添えて。"),
        ("一日を一本にして、", "そのまま共有。"),
    ],
    "en": [
        ("Capture a moment.", "Keep living."),
        ("Your day,", "on one timeline."),
        ("Even the quiet hours", "are part of it."),
        ("Add a note", "to the date."),
        ("Share the whole day", "as one video."),
    ],
}

FONT_CANDIDATES = {
    "bold": [
        "/System/Library/Fonts/ヒラギノ角ゴシック W7.ttc",
        "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc",
    ],
    "mono": [
        "/System/Library/Fonts/SFNSMono.ttf",
        "/System/Library/Fonts/Menlo.ttc",
        "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
    ],
}


def font(kind: str, size: int) -> ImageFont.FreeTypeFont:
    for path in FONT_CANDIDATES[kind]:
        if Path(path).exists():
            index = 0
            if path.endswith("NotoSansCJK-Bold.ttc"):
                index = 0  # JP は ttc 内の Noto Sans CJK JP
            return ImageFont.truetype(path, size, index=index)
    return ImageFont.load_default()


def draw_mark(draw: ImageDraw.ImageDraw, x: int, y: int, width: int) -> None:
    """ロゴA（時間軸）の横長版。"""
    line_h = 6
    draw.rounded_rectangle([x, y - line_h // 2, x + width, y + line_h // 2], radius=3, fill=INK)
    for ratio in (0.18, 0.36, 0.56):
        tx = x + int(width * ratio)
        draw.rounded_rectangle([tx - 4, y - 26, tx + 4, y + 26], radius=4, fill=INK)
    r = 15
    cx = x + int(width * 0.78)
    draw.ellipse([cx - r, y - r, cx + r, y + r], fill=ACCENT)


def rounded(image: Image.Image, radius: int) -> Image.Image:
    mask = Image.new("L", image.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, image.width, image.height], radius=radius, fill=255)
    out = image.convert("RGBA")
    out.putalpha(mask)
    return out


def placeholder(size) -> Image.Image:
    im = Image.new("RGB", size, (220, 220, 214))
    d = ImageDraw.Draw(im)
    d.text((size[0] // 2, size[1] // 2), "SCREENSHOT", fill=(150, 150, 146), anchor="mm", font=font("mono", 64))
    return im


def compose(lang: str, index: int) -> Image.Image:
    canvas = Image.new("RGB", SIZE, GROUND)
    draw = ImageDraw.Draw(canvas)
    margin = 110

    draw_mark(draw, margin, 250, 300)

    title = font("bold", 104 if lang == "ja" else 96)
    line1, line2 = CAPTIONS[lang][index]
    draw.text((margin, 360), line1, fill=INK, font=title)
    draw.text((margin, 500), line2, fill=INK, font=title)

    raw_path = HERE / "raw" / lang / f"{index + 1:02d}.png"
    screen = Image.open(raw_path).convert("RGB") if raw_path.exists() else placeholder((1179, 2556))

    # 画面は下側に、角丸の枠で置く（下端は少し切れて、続きを感じさせる）。
    target_w = SIZE[0] - margin * 2
    scale = target_w / screen.width
    shown = screen.resize((target_w, int(screen.height * scale)), Image.LANCZOS)
    top = 760
    frame = Image.new("RGBA", (shown.width + 24, shown.height + 24), (0, 0, 0, 0))
    ImageDraw.Draw(frame).rounded_rectangle([0, 0, frame.width, frame.height], radius=96, fill=INK)
    frame.alpha_composite(rounded(shown, 84), (12, 12))
    canvas.paste(frame, (margin - 12, top), frame)

    footer = font("mono", 34)
    draw.text((SIZE[0] - margin, 300), "VLOGISH", fill=SECONDARY, font=footer, anchor="rs")
    return canvas


def main() -> None:
    for lang in CAPTIONS:
        out_dir = HERE / "out" / lang
        out_dir.mkdir(parents=True, exist_ok=True)
        for index in range(len(CAPTIONS[lang])):
            compose(lang, index).save(out_dir / f"{index + 1:02d}.png")
    print("written:", HERE / "out")


if __name__ == "__main__":
    main()
