# App Store Submission Checklist

## Product Identity
- App Store Name: `Vlogish`
- Home Screen Name: `Vlogish`
- Core promise: multiple 1–5 second moments become one chronological day

## Metadata (English)
- Subtitle: `Your day, told in seconds.`
- Promotional Text:
  - `Capture 1–5 seconds at a time, then watch your day unfold in order. Add time and place now or change the stamp later.`
- Description bullets:
  - `Capture a moment in one tap (1–5 seconds)`
  - `Watch every moment from earliest to latest`
  - `Change the date, time, place, position, and fade later`
  - `Export one clip or your whole day with the current stamp`
  - `Portrait and landscape capture with native iPhone lenses`
  - `No account required; videos stay in your photo library`

## Metadata (Japanese)
- App Name: `Vlogish`
- Subtitle: `数秒ずつ、一日の流れを残す`
- Promotional Text:
  - `1〜5秒ずつ残した瞬間を、古い順に一日の流れとして再生。日付・時刻・場所は後から表示を変えられます。`
- Description bullets:
  - `最短ワンタップ撮影（1〜5秒）`
  - `一日の瞬間を古い順に連続再生`
  - `日付・時刻・場所・位置・フェードを後から変更`
  - `単体動画と一日動画を、現在のスタンプで書き出し`
  - `iPhoneのレンズを活かした縦向き / 横向き撮影`
  - `アカウント不要。動画は写真ライブラリへ保存`

## Privacy URLs
- Support URL: `https://github.com/yakan-007/daylog/issues`
- Privacy Policy URL: `https://github.com/yakan-007/daylog/blob/main/PRIVACY.md`

## Screenshots (English and Japanese)
- [ ] `Capture a moment. Keep living.` / `一瞬を撮って、日常へ戻る。`
- [ ] `Watch your day unfold.` / `一日の流れを、古い順に。`
- [ ] `Time and place, your way.` / `日付・時刻・場所を、好きな形で。`
- [ ] `Change the stamp later.` / `スタンプは後から変更。`
- [ ] `Share the whole day.` / `一日を一本にして共有。`

## Before Paying / Enrolling
- [ ] Confirm `Vlogish` in App Store Connect and perform a trademark check
- [ ] Decide whether to enroll as an individual (legal name is public) or an organization
- [ ] Complete all no-membership real-device checks below

## TestFlight Gate
- [ ] English and Japanese installs both show the correct UI and permission text
- [ ] Run a 7–14 day test with 5–10 people
- [ ] Confirm testers can record on at least 3 separate days without guidance
- [ ] Confirm daily playback and export succeed without developer assistance
- [ ] Collect the top three points of confusion before App Review submission

## Final QA Gate
- [ ] Camera/Mic permission deny -> recover flow works
- [ ] Photo permission deny -> save error guidance works
- [ ] Record -> save -> list reflect works on real device
- [ ] Failed save preserves the original; rescue, explicit deletion, and next-launch detection work
- [ ] Export shows a busy state, then opens the share sheet or a clear failure message
- [ ] Export progress increases from 0 to 100%; cancel stops the export and removes temporary files
- [ ] 80 clips show a warning; 100 and 150 clips complete via chunked export
- [ ] Portrait/landscape setting rotates the UI, preview, saved video, timestamp, and place name consistently
- [ ] All five stamp positions match the preview; center includes date; fade ON disappears after 2 seconds and OFF remains visible
- [ ] A newly captured clip can change or remove its stamp later without creating a duplicate asset; Photos can revert to the clean original
- [ ] A legacy baked-stamp clip explains that it cannot be re-edited and never overlays a second stamp
- [ ] Continuous day playback and merged export both start with the oldest clip and end with the newest
- [ ] Limited Photos access offers additional selection and Settings recovery
- [ ] 1080p/30fps, HEVC playback, low-light focus, and 1x/2x/5x zoom work on a real iPhone
- [ ] VoiceOver labels/hints are readable on key controls
- [ ] English layouts do not truncate at the largest Dynamic Type size
- [ ] Calendar month, weekday, time, and permission text follow the selected app language
- [ ] Japanese and English App Store screenshots match the submitted build
- [x] Support URL is publicly reachable (HTTP 200 on 2026-08-11)
- [ ] Push `PRIVACY.md`, then confirm the privacy policy URL no longer returns HTTP 404
