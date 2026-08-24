# This Was My Day アーキテクチャ基準

- 文書版: 2.4
- 更新日: 2026-08-14
- 対象: `This Was My Day` iOSアプリ（内部ターゲット名: `FragmentCamera`）
- 前提: App Store公開前。旧実装・開発中データとの互換レイヤーは持たない

## 結論

全面的な新規プロジェクト化は行わず、動作実績のあるAVFoundation／PhotoKit処理を残して、その周囲を組み直した。現在はカメラロールUIを大きく変更しても、撮影・保存・再生へ表示都合が波及しにくい状態になっている。

今後の機能追加は、下記の境界を壊さずに各Feature内で行う。旧経路を並走させる互換レイヤーは作らない。

## 現在の構造

```text
FragmentCamera
├── App root
│   ├── FragmentCameraApp
│   ├── DaylogContainer
│   └── ContentView
├── Capture
│   ├── CaptureFeature / CapturePresentation
│   ├── CaptureScreenView / CaptureScreenComponents
│   ├── CameraService
│   ├── CaptureSessionController
│   ├── CaptureReadinessMonitor
│   ├── CaptureSaveCoordinator
│   └── CaptureLocationService
├── Library
│   ├── LibraryFeatureViewModel
│   ├── CameraRollView / CameraRollPresentation
│   ├── CameraRollDayCard / CameraRollDayDetailView
│   ├── CameraRollCalendarView / CameraRollCalendarPresentation
│   ├── CameraRollArchiveView / CameraRollComponents
│   ├── LibraryThumbnailLoader / LibraryThumbnailView
│   ├── DaylogLibraryServices
│   └── DaylogMetadataStore
├── Playback
│   ├── PlaybackFeature / PlaybackModels
│   ├── LibraryClipBrowserFeature
│   ├── ClipBrowserView / ClipBrowserPresentation
│   └── AssetPlaybackLoader
├── Media
│   ├── VideoPostProcessPipeline
│   ├── DateStampLayerFactory
│   ├── DayVideoExportFeature
│   ├── LibraryVideoExportService
│   ├── DayVideoCompositionBuilder
│   ├── DayVideoExportPolicy
│   ├── MediaExporter
│   └── VideoEncodingPolicy
└── Core
    ├── DaylogDomain / DaylogFailure
    ├── AppSettings
    ├── VideoStampContextService
    ├── TemporaryFileStore
    ├── VideoStampRecipeStore
    ├── AppIdentity / L10n
    └── DaylogFormatting
```

依存の基本方向は `View → ViewModel → Service` とする。SwiftUI ViewはPhotoKit、AVCaptureSession、UserDefaults、FileManagerを直接操作しない。

## 今回完了した整理

### UI境界

- 441行だったルート画面を、撮影View、部品、表示変換、Previewへ分離した。
- 1,100行を超えていたカメラロール部品を、日別カード、カレンダー、全動画、日別詳細、共通部品へ分割した。
- 月グリッド生成と月移動を `CameraRollCalendarPresenter`、サムネイルの読込開始・キャンセルを `LibraryThumbnailView` に集約した。
- カメラロールを表示専用の `CameraRollScreenState` で描画し、ViewからPhotoKitと日別集計を除去した。
- クリップブラウザを表示状態、ナビゲーションロジック、PhotoKit読込へ分離した。
- カメラロールと撮影画面に実データ不要のPreviewとPresentationテストを追加した。
- 撮影画面は常設説明カードを外し、純正カメラに近いアイコン・シャッター・秒数・ズーム中心へ変更した。
- 日別画面は暗いガラスUIから、紙面・グリッド・写真を主役にした手帳風UIへ変更した。
- 再生画面の操作説明文をアイコンとVoiceOverヒントへ移した。

### 状態管理

- `CameraService` の多数の `@Published` を `CameraEngineState` 一つへ統合した。
- 権限拒否、準備中、撮影可能、中断、カメラ利用不可を明示的な状態にした。
- `CaptureFeatureState` が画面固有の秒数、ライト、グリッド、フォーカス、ズーム、進捗だけを所有するようにした。
- 権限の実状態とアラートを閉じた状態を分離した。
- 撮影秒数の候補・既定値・正規化を `CaptureDurationPolicy` へ一本化した。

### メディアとファイル

- 標準／節約の解像度、30fps、HEVC優先、H.264フォールバックを `VideoEncodingPolicy` に集約した。
- 撮影後処理と日次結合に重複していた書き出し処理を `MediaExporter` 一つへ統合した。
- 出力形式選択、バックグラウンドタスク、一時ファイル掃除、音声消失確認が共通になった。
- 一時URLの生成と24時間後の孤立ファイル掃除を `TemporaryFileStore` に限定した。
- 位置情報取得、保存調整、カメラ準備判定を `CameraService` から分離した。
- AVCaptureSession、入出力、端末操作を `CaptureSessionController` へ分離し、CameraServiceを状態遷移と録画・保存調整へ縮小した。
- 標準撮影を1080p／30fps基準、HEVC優先とし、低照度ブースト、滑らかなAF・ズーム、タップ後の連続AF復帰を追加した。
- 日次結合は素材AVAssetを一括保持せず1本ずつCompositionへ移し、100本以上を24本単位で分割処理するようにした。
- 80本で事前注意、100本以上で分割処理の案内を撮影画面と日別画面に表示する。
- スタンプ描画を `DateStampLayerFactory` へ集約し、撮影時焼き込みと日次書き出しで同じフォント・余白・フェードを使う。
- 既定の撮影保存はスタンプを再圧縮せず、`VideoStampRecipeStore` のレシピをアプリ内再生で重ねる。設定で撮影時焼き込みも選択できる。
- 日次結合はレシピを各クリップの時間範囲へ一度だけ焼き込み、分割結合の最終段で二重適用しない。
- 現在のスタンプ設定、撮影時メタデータ、地名補完、レシピ更新を `VideoStampContextService` に集約し、再生・単体書き出し・日次書き出しで同じ決定結果を使う。
- 逆ジオコードを `PlaceNameResolver` に一本化し、連続撮影した同一地点の問い合わせ結果を共有する。
- 日次書き出し前の地名補完は最大4件の上限付き並列処理とし、元の動画順を保ったままレシピ更新を一括保存する。準備工程も件数付きで進捗表示する。
- 縦横素材の混在時は総再生時間が長い向きを出力キャンバスにし、最大幅・最大高の合成による正方形化を防ぐ。

### ライブラリと再生

- PhotoKitリポジトリの独自DispatchQueueと `@unchecked Sendable` を削除した。
- PHAsset、サムネイル、変更通知をMainActor境界に閉じ込めた。
- 旧個別プレイヤーと旧日次プレイヤーを削除し、`LibraryClipBrowserViewModel` に一本化した。
- 日次再生は同じブラウザの連続再生モードとして実装した。
- 近傍動画の先読みと日をまたぐ時刻近似を一つの経路にした。
- 日次再生と結合の順序を撮影時刻の古い順へ統一した。
- アプリ内スタンプはAVPlayerの映像領域へレイヤー表示し、縦横比による黒帯へは置かない。

### 設定・エラー・検証

- UserDefaultsキー、既定値、正規化、移行を `DaylogSettingsStore` に集約した。
- 保存・書き出しエラーを `DaylogFailure` に分類し、画面の案内を統一した。
- Unit Testターゲット、共有scheme、GitHub Actionsを追加した。
- アプリとUnit Testの `build-for-testing` が成功することを確認した。

### 公開前の保守性整理（2.4）

- 単体動画と一日動画の「設定読込 → レシピ取得 → 地名解決 → スタンプ生成 → 書き出し」を `LibraryVideoExportService` へ一本化した。
- スタンプ準備を先頭10%、メディア処理を残り90%とする進捗変換を `LibraryExportProgressMapper` に集約した。
- 一日書き出しと単体書き出しで別々に持っていた実行中ID・再試行IDを `LibraryExportTarget` 一つへ統合し、同時に両方が実行中になる不正状態を表現できなくした。
- 書き出しの開始・成功・失敗・キャンセル後の状態初期化を共通化し、失敗理由と再試行先が食い違わないようにした。
- 公開名、ホーム画面名、写真アルバム名を `AppIdentity` へ集約し、日本語・英語の文言は `L10n` と `.lproj` リソースへ分離した。

## 削除した旧構造

- `PlayerView.swift`
- `DayPlayerView.swift`
- `AppDelegate.swift`
- 複数の再生ルート
- CameraServiceの個別公開フラグ群
- PhotoKitリポジトリの手動同期キュー
- `@unchecked Sendable`
- 処理を横流しするだけのCaptureUseCase
- 処理を横流しするだけの動画後処理Service
- 撮影保存用と日次結合用に重複していたAVAssetExportSession処理
- 使用されていない権限状態、録画状態、カメラ位置の中間モデル

## カメラロールUIを組み直すルール

1. Viewが受け取るのは `CameraRollScreenState` とIDベースのactionだけにする。
2. 日付、件数、再生時間の表示変換は `CameraRollPresenter` に置く。
3. PHAssetをViewへ渡さず、サムネイルは `LibraryThumbnailProviding` を使う。
4. セルの表示開始で読込み、非表示化でキャンセルする。
5. 再生・結合・ページングはViewModelのIDベースAPIから呼ぶ。
6. 新しいレイアウト状態は純粋な値型にし、実機PhotoKitなしでPreviewとUnit Testを作れるようにする。

この契約内であれば、縦リスト、日別カード、タイムライン、モザイク、カレンダー風レイアウトのいずれにも置換できる。

## 変更してはいけないプロダクト契約

- 1〜5秒撮影、早期停止、残り時間表示
- 前後カメラ、ライト、グリッド、フォーカス、ズーム
- 日付スタンプ、標準／節約、音声、任意の位置情報
- 写真ライブラリ内 `This Was My Day` アルバムを正本とする
- 日別一覧、個別再生、日次連続再生、結合共有
- 保存失敗を無言で終えず、次の行動を表示する
- iPhone・設定による縦／横の手動切替

## 残っている作業

コード構造の刷新は完了した。利用開始前に必要なのは主に実機品質確認である。

- 実機でカメラ／マイク許可、拒否、設定復帰を確認する。
- 1〜5秒と早期停止で、保存本数・音声・動画長を確認する。
- 前後カメラ、回転、ミラー、割り込み復帰を確認する。
- スタンプON/OFF、標準／節約、位置情報ON/OFFの組合せを確認する。
- 同一素材で節約モードの容量削減率と画質を比較する。
- 前後カメラで1080p／30fps、HEVC、低照度、AF復帰、1×／2×／5×ズームを確認する。
- 80本、100本、150本の日を用意し、注意表示、分割結合、音声、並び順を確認する。
- iCloud上だけにある動画の再生・結合失敗表示を確認する。
- 再生時スタンプのレシピはApplication Support内にあり、アプリ削除後の復元は未対応。動画本体は写真ライブラリに残るため、初期レシピの動画メタデータ格納またはプライベート同期を将来判断する。
- 個別クリップ書き出しは日次書き出しと同じ非破壊スタンプ経路へ統合済み。全スタンプ位置と場所あり／なしを実機で確認する。
- 再生時／撮影時スタンプ、縦／横動画、場所あり／なし、2秒以下／超のフェードを実機で組合せ確認する。
- Swift 6完全並行性チェックでは、AVFoundation／PhotoKitのDelegate・callback境界に移行警告が残る。現在のSwift 5ビルドには影響しないが、Swift 6化は別途actor境界を設計してから行う。

## 検証方法

```sh
xcodebuild -project FragmentCamera.xcodeproj \
  -scheme FragmentCamera \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /private/tmp/daylog-derived \
  build-for-testing CODE_SIGNING_ALLOWED=NO
```

Unit Testは利用可能なSimulatorで実行し、実機向けビルドも署名なしで確認する。

## 完了条件

- `git diff --check` が通る。
- `@unchecked Sendable` はロックで保護したAVFoundation／PhotoKit橋渡しオブジェクトに限定し、画面からのUserDefaults直参照と重複Exporterが存在しない。
- アプリとテストターゲットのコンパイルが成功する。
- 上記の実機シナリオを利用開始前に一巡する。
- 新しいカメラロールUIがPresentationテストとPreviewを伴って追加できる。
