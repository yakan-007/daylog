#!/usr/bin/env python3
"""App Store 用スクリーンショットを作る。

使い方:
  1. 実機かシミュレーターで画面を撮り、raw/<言語>/01.png〜05.png に置く
     （言語: ja, en, ko, zh-Hans, zh-Hant。アプリをその言語にして撮る）。
  2. python3 compose.py           → out/<言語>/01.png … 05.png（1320×2868, 6.9インチ用）

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
    "ko": [
        ("순간을 찍고,", "일상으로 돌아가요."),
        ("하루를,", "하나의 타임라인에."),
        ("찍지 않은 시간도,", "하루의 일부."),
        ("날짜에,", "한마디를 더해요."),
        ("하루를 한 편으로,", "그대로 공유."),
    ],
    "zh-Hans": [
        ("拍下一瞬，", "回到日常。"),
        ("把一天，", "放进一条时间轴。"),
        ("没拍的时间，", "也是一天的一部分。"),
        ("在日期旁，", "写一句话。"),
        ("把一天合成一段，", "直接分享。"),
    ],
    "zh-Hant": [
        ("拍下一瞬，", "回到日常。"),
        ("把一天，", "放進一條時間軸。"),
        ("沒拍的時間，", "也是一天的一部分。"),
        ("在日期旁，", "寫一句話。"),
        ("把一天合成一段，", "直接分享。"),
    ],
}

# 見出しの太字。言語ごとに、その文字を持っているフォントを上から探す。
# Noto Sans CJK の ttc は 0:JP 1:KR 2:SC 3:TC の順に入っている。
TITLE_FONTS = {
    "ja": [
        ("/System/Library/Fonts/ヒラギノ角ゴシック W7.ttc", 0),
        ("/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc", 0),
    ],
    "en": [
        ("/System/Library/Fonts/ヒラギノ角ゴシック W7.ttc", 0),
        ("/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc", 0),
    ],
    "ko": [
        ("/System/Library/Fonts/AppleSDGothicNeo.ttc", None),
        ("/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc", 1),
    ],
    "zh-Hans": [
        ("/System/Library/Fonts/PingFang.ttc", None),
        ("/System/Library/Fonts/Hiragino Sans GB.ttc", None),
        ("/System/Library/Fonts/STHeiti Medium.ttc", 0),
        ("/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc", 2),
    ],
    "zh-Hant": [
        ("/System/Library/Fonts/PingFang.ttc", None),
        ("/System/Library/Fonts/STHeiti Medium.ttc", 0),
        ("/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc", 3),
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


def bold_face(path: str, size: int) -> ImageFont.FreeTypeFont:
    """ttc の中から太字の書体を探す（見つからなければ先頭）。"""
    for index in range(16):
        try:
            face = ImageFont.truetype(path, size, index=index)
        except OSError:
            break
        style = face.getname()[1].lower()
        if any(word in style for word in ("bold", "semibold", "w6", "w7")):
            return face
    return ImageFont.truetype(path, size, index=0)


def title_font(lang: str, size: int) -> ImageFont.FreeTypeFont:
    # index が None のものは、ttc の中から太字を探す。
    for path, index in TITLE_FONTS.get(lang, TITLE_FONTS["ja"]):
        if not Path(path).exists():
            continue
        if index is None:
            return bold_face(path, size)
        try:
            return ImageFont.truetype(path, size, index=index)
        except OSError:
            return ImageFont.truetype(path, size, index=0)
    print(f"warning: {lang} の見出しフォントが見つからない。文字が化けるかもしれない")
    return font("bold", size)


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

    title = title_font(lang, 96 if lang == "en" else 104)
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
