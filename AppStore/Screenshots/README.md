# App Store スクリーンショット

`compose.py` が、撮った画面にロゴ（時間軸）と見出しを付けて、App Store 用（1320×2868, 6.9インチ）の画像にする。

## 撮る画面（縦・日本語と英語それぞれ）

| 番号 | 画面 | 見出し（日本語 / 英語） |
| --- | --- | --- |
| 01 | 撮影画面（構えている状態） | 一瞬を撮って、日常へ戻る。 / Capture a moment. Keep living. |
| 02 | カメラロールのフィード（今日に数本ある状態） | 一日を、一本の時間軸に。 / Your day, on one timeline. |
| 03 | 1日の詳細（「空白」と「いま」が見える状態） | 撮っていない時間も、一日のうち。 / Even the quiet hours are part of it. |
| 04 | 編集画面（日付・時刻の下にひとこと） | 日付に、ひとこと添えて。 / Add a note to the date. |
| 05 | 1本に結合して共有する画面 | 一日を一本にして、そのまま共有。 / Share the whole day as one video. |

撮った画像は `raw/ja/01.png` 〜 `raw/ja/05.png`、英語は `raw/en/` に置く。

## 作り方

```
cd AppStore/Screenshots
python3 -m pip install pillow   # 初回だけ
python3 compose.py
```

`out/ja/` と `out/en/` にできた画像を App Store Connect に入れる。
画面が無い番号はグレーの仮画面になる（レイアウト確認用）。見出しは `compose.py` の `CAPTIONS` で直す。

## アイコン

App Store のアイコンはビルドのアプリアイコン（`Assets.xcassets/AppIcon`）がそのまま使われるので、別に用意しなくてよい。
