# App Store Submission Checklist

最終更新: 2026-10-07（redesign/vlogish-ui の内容に合わせて書き直し）

## 公開までの流れ

1. [ ] Apple Developer Program に登録（年 99 USD。個人登録だと App Store に本名が出る）
2. [ ] App Store Connect でアプリを作成し、名前 `Vlogish` を確保（Bundle ID: `com.leo.vlogish`, SKU は任意）
3. [ ] `redesign/vlogish-ui` を push → `main` へマージ（プライバシーポリシーの URL がこれで生きる。下の「URL」参照）
4. [ ] Xcode › Product › Archive → TestFlight へアップロード
5. [ ] TestFlight で 5〜10 人に 1〜2 週間使ってもらう（下の「TestFlight」）
6. [ ] App Store Connect にメタデータ・スクショ・各種回答を入れる（下の各節）
7. [ ] 審査に提出（目安 1〜2 日）

## Product Identity

- App Store Name: `Vlogish`（全言語共通）
- Home Screen Name: `Vlogish`
- Category: Photo & Video（`public.app-category.photography`）
- Core promise: 1〜5秒の瞬間を重ねて、一日を一本の時間軸にする
- 価格: 無料・アプリ内課金なし

## 配信する国と地域

- [ ] **中国本土は外す**（配信には ICP 備案が必要で、個人では通らない）
- それ以外は全世界で可。言語ページは en / ja / ko / zh-Hans / zh-Hant
- 簡体字はシンガポール・マレーシアなど、繁体字は台湾・香港向け

## URL

- Support URL: `https://github.com/yakan-007/daylog/issues`（公開リポジトリなので 200 を確認済み 2026-10-07）
- Privacy Policy URL: `https://github.com/yakan-007/daylog/blob/main/PRIVACY.md`
  - [ ] **2026-10-07 時点で 404**。`main` に `PRIVACY.md` が無いため。ブランチを `main` へマージすれば開く
  - 注意: リポジトリは公開設定なので、ソースコードも誰でも見られる。非公開にしたい場合は、プライバシーポリシーとサポートを別の公開ページ（Vercel など）へ移し、`SettingsFeature.swift` の `VlogishLinks` も変える

## App Store Connect で聞かれること

- **App のプライバシー**: 「データを収集していない」
  - 動画・音声・位置情報は端末と写真ライブラリの中だけ。開発者のサーバーへは送らない
  - 地名は Apple のジオコーディングに問い合わせるだけで、開発者側には残らない
  - 広告・トラッキング・解析 SDK なし
- **年齢レーティング**: 質問はすべて「なし」→ 4+ の想定（アプリ内での投稿・閲覧機能なし。共有は iOS の共有シートだけ）
- **輸出コンプライアンス（暗号化）**: `Info.plist` に `ITSAppUsesNonExemptEncryption = NO` を設定済み。アップロードごとの質問は出ない
- **EU のデジタルサービス法（事業者か）**: 無料・収益なしなら「事業者ではない」を選べる。事業者を選ぶと住所・電話番号が EU のストアに表示される
- **コンテンツの権利**: 第三者のコンテンツは含まない
- **審査メモ**（App Review Information に書く）:
  - ログイン不要。カメラ・マイク・写真の許可を出せばすぐ撮影できる
  - 位置情報は設定でオンにした時だけ使う（初期はオフ）
  - 書き出した動画の最後 1.5 秒に小さな VLOGISH の文字が入る（設定でオフにできる）

## スクリーンショット（6.9 インチ・1320×2868・各言語 5 枚）

`AppStore/Screenshots/compose.py` で 5 言語ぶん作れる（手順は同フォルダの README）。

| 番号 | 画面 | ja | en |
| --- | --- | --- | --- |
| 01 | 撮影画面 | 一瞬を撮って、日常へ戻る。 | Capture a moment. Keep living. |
| 02 | 記録シート（今日に数本） | 一日を、一本の時間軸に。 | Your day, on one timeline. |
| 03 | 1日の詳細（空白と「いま」） | 撮っていない時間も、一日のうち。 | Even the quiet hours are part of it. |
| 04 | クリップ編集（スタンプ＋ひとこと） | 日付に、ひとこと添えて。 | Add a note to the date. |
| 05 | 1本にした完成カード | 一日を一本にして、そのまま共有。 | Share the whole day as one video. |

- [ ] ja / en / ko / zh-Hans / zh-Hant の生画面を `raw/<言語>/` に置いて `python3 compose.py`
- [ ] スクショは提出するビルドの画面と一致していること

---

## Metadata

文字数の上限: 名前・サブタイトル 30、プロモーション 170、キーワード 100（カンマ区切り・空白なし）、説明 4000。

### English

- Subtitle: `Your day, told in seconds.`
- Promotional Text: `Capture 1–5 seconds at a time, then watch your day unfold in order. Stamp the date, time, place, or a short note—and change it anytime.`
- Keywords: `vlog,video diary,daily vlog,journal,clips,timeline,memories,date stamp,1 second,everyday,camera`
- Description:

```
Vlogish turns tiny moments into one day.

Tap once to record 1–5 seconds, then get back to your day. Every clip lands on a single timeline, from morning to night—quiet hours included.

• One-tap capture, 1–5 seconds
• Your day on one timeline, with "now" marked
• Play the whole day from oldest to newest
• Stamp the date, time, place, or a short note—in any of 9 positions, and change it later
• Export a clip or the whole day as one video and share it
• Remove clips you don't need: take them out of Vlogish, or delete them from Photos
• Space Saver mode keeps new clips smaller

No account. Your videos stay in your photo library and are never sent to our servers.
```

### 日本語

- Subtitle: `数秒ずつ、一日の流れを残す`
- Promotional Text: `1〜5秒ずつ残した瞬間を、古い順に一日の流れとして再生。日付・時刻・場所・ひとことのスタンプは、あとからいつでも変えられます。`
- Keywords: `Vlog,ブイログ,動画日記,日記,日常,タイムライン,思い出,日付,スタンプ,一秒,ショート動画,カメラ`
- Description:

```
Vlogishは、数秒の瞬間を重ねて、一日を一本にするアプリです。

ワンタップで1〜5秒だけ撮って、すぐ日常へ戻る。撮った動画は、朝から夜までの一本の時間軸に並びます。撮っていない時間も、一日のうちです。

・ワンタップで1〜5秒の撮影
・一日を一本の時間軸で。「いま」の位置もひと目でわかる
・一日の動画を古い順に連続再生
・日付・時刻・場所・ひとことのスタンプ。9か所に置けて、あとから変更できる
・1本ずつでも、一日まるごと1本にしても書き出して共有
・いらない動画は「Vlogishから外す」か「写真からも削除」
・節約モードで、次の撮影から容量を抑えて保存

アカウントは不要。動画は写真ライブラリに保存され、開発者のサーバーへ送られることはありません。
```

### 한국어

- Subtitle: `몇 초씩, 하루의 흐름을 남기다`
- Promotional Text: `1~5초씩 남긴 순간을 오래된 순서대로 하루의 흐름으로 재생해요. 날짜·시간·장소·한마디 스탬프는 나중에 언제든 바꿀 수 있어요.`
- Keywords: `브이로그,영상일기,일기,하루,일상,타임라인,추억,날짜,스탬프,1초,짧은영상,카메라`
- Description:

```
Vlogish는 몇 초의 순간을 모아 하루를 한 편으로 만드는 앱이에요.

한 번 탭해서 1~5초만 찍고, 바로 일상으로 돌아가요. 찍은 영상은 아침부터 밤까지 하나의 타임라인에 놓여요. 찍지 않은 시간도 하루의 일부예요.

• 한 번 탭으로 1~5초 촬영
• 하루를 하나의 타임라인으로, '지금'의 위치도 한눈에
• 하루의 영상을 오래된 순서대로 연속 재생
• 날짜·시간·장소·한마디 스탬프. 9곳에 놓을 수 있고 나중에 바꿀 수 있어요
• 한 편씩, 또는 하루 전체를 한 편으로 내보내서 공유
• 필요 없는 영상은 'Vlogish에서 빼기' 또는 '사진에서도 삭제'
• 절약 모드로 다음 촬영부터 용량을 줄여서 저장

계정이 필요 없어요. 영상은 사진 보관함에 저장되고, 개발자의 서버로 전송되지 않아요.
```

### 简体中文

- Subtitle: `几秒一段，记下一天的流动`
- Promotional Text: `每次留下 1–5 秒，按时间顺序播放成一天的流动。日期、时间、地点和一句话的时间戳，之后随时可以修改。`
- Keywords: `Vlog,视频日记,日记,日常,时间轴,回忆,日期,时间戳,一秒,短视频,相机`
- Description:

```
Vlogish 把几秒钟的瞬间串起来，让一天变成一段视频。

轻点一下，只拍 1–5 秒，然后回到日常。拍下的视频会排在从早到晚的一条时间轴上。没拍的时间，也是一天的一部分。

• 轻点一下，拍摄 1–5 秒
• 一天就是一条时间轴，"现在"的位置一目了然
• 按从早到晚的顺序连续播放一天的视频
• 日期、时间、地点和一句话的时间戳，可放在 9 个位置，之后还能修改
• 单段导出，或把一整天合成一段视频分享
• 不需要的视频，可以"从 Vlogish 中移除"或"从'照片'中删除"
• 节省空间模式，让之后拍摄的视频更小

无需账户。视频保存在你的照片图库中，不会发送到开发者的服务器。
```

### 繁體中文

- Subtitle: `幾秒一段，記下一天的流動`
- Promotional Text: `每次留下 1–5 秒，依時間順序播放成一天的流動。日期、時間、地點與一句話的時間戳記，之後隨時都能修改。`
- Keywords: `Vlog,影片日記,日記,日常,時間軸,回憶,日期,時間戳記,一秒,短影片,相機`
- Description:

```
Vlogish 把幾秒鐘的瞬間串起來，讓一天變成一段影片。

輕點一下，只拍 1–5 秒，然後回到日常。拍下的影片會排在從早到晚的一條時間軸上。沒拍的時間，也是一天的一部分。

• 輕點一下，拍攝 1–5 秒
• 一天就是一條時間軸，「現在」的位置一目瞭然
• 依從早到晚的順序連續播放一天的影片
• 日期、時間、地點與一句話的時間戳記，可放在 9 個位置，之後也能修改
• 單段輸出，或把一整天合成一段影片分享
• 不需要的影片，可以「從 Vlogish 中移除」或「從『照片』中刪除」
• 節省空間模式，讓之後拍攝的影片更小

不需要帳號。影片儲存在你的照片圖庫中，不會傳送到開發者的伺服器。
```

---

## TestFlight

- [ ] 5 言語のどれで入れても、画面と許可の文言がその言語で出る
- [ ] 5〜10 人で 7〜14 日。説明なしで 3 日以上撮れるか
- [ ] 一日の再生と書き出しが、開発者の手助けなしでできるか
- [ ] 迷ったところの上位 3 つを集めてから審査に出す

## Final QA（実機）

撮影と保存
- [ ] カメラ・マイクの許可を拒否 → 設定へ戻る導線が出る
- [ ] 写真の許可を拒否 → 保存エラーの案内が出る
- [ ] 撮影 → 保存 → 記録シートに反映される
- [ ] 保存に失敗しても元の動画が残り、次回起動で救済できる
- [ ] 着信・別アプリへの切り替えで中断 → 戻ると撮影できる
- [ ] 節約モード: ログの `save.postprocess.size` で標準より小さいことを確認

スタンプと編集
- [ ] 9 か所の配置がプレビュー・再生・書き出しで一致する
- [ ] フェードオンは 2 秒で消え、オフは残る
- [ ] 撮った後にスタンプを変えても、動画が二重にならない

一覧と削除
- [ ] 「Vlogishから外す」→ 写真アプリには残る
- [ ] 「写真からも削除」→ iOS の確認 →「最近削除した項目」へ
- [ ] その日の最後の 1 本を消すと、開いた元の画面へ戻る
- [ ] 写真へのアクセスが「選択した写真のみ」でも、追加選択と設定への導線が出る

書き出し
- [ ] 進行 0→100%、キャンセルで止まり一時ファイルが消える
- [ ] 60 本で確認、80 本以上は分割処理、200 本を超えると「上限超え」で止まる
- [ ] 容量が足りない時は、始める前に案内が出る
- [ ] 最後の 1.5 秒に VLOGISH が出る。スタンプや「ひとこと」と重ならない角に逃げる。設定でオフにできる
- [ ] 再生と書き出しは古い順に始まり、新しい順で終わる

表示と言語
- [ ] VoiceOver で主要なボタンが読める
- [ ] 最大の文字サイズで英語・韓国語が切れない
- [ ] カレンダーの月・曜日・時刻・日付の順番が、アプリの言語と地域に合う
- [ ] Reduce Motion でも操作できる
