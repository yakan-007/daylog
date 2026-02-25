import SwiftUI

struct SettingsView: View {
    @AppStorage("isDateStampEnabled") private var isDateStampEnabled: Bool = true
    @AppStorage("dateStampFormat") private var dateStampFormat: String = DateStampFormatter.compactDateTime
    @AppStorage("dateStampZeroPadded") private var dateStampZeroPadded: Bool = false
    @AppStorage("dateStampSize") private var dateStampSize: String = DateStampStyle.medium

    private let formats = [DateStampFormatter.compactDateTime]

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("日付スタンプ")) {
                    Toggle("スタンプを表示", isOn: $isDateStampEnabled)
                        .accessibilityHint("撮影した動画の冒頭に日付時刻を表示します")
                    Toggle("0埋め", isOn: $dateStampZeroPadded)
                        .accessibilityHint("月日と時刻の桁をそろえて表示します")
                    Picker("書式", selection: $dateStampFormat) {
                        ForEach(formats, id: \.self) { fmt in
                            Text(label(for: fmt)).tag(fmt)
                        }
                    }
                    .accessibilityHint("現在は固定フォーマットで表示します")
                    Picker("文字サイズ", selection: $dateStampSize) {
                        Text("小").tag(DateStampStyle.small)
                        Text("中").tag(DateStampStyle.medium)
                        Text("大").tag(DateStampStyle.large)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityHint("動画に表示する日付の文字サイズを切り替えます")

                    VStack(alignment: .leading, spacing: 8) {
                        Text("プレビュー")
                            .font(AppTheme.labelFont)
                            .foregroundStyle(.secondary)
                        ZStack(alignment: .topTrailing) {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(AppTheme.surfaceElevated)
                                .frame(height: 120)
                            Text(previewText)
                                .font(
                                    .system(
                                        size: previewFontSize,
                                        weight: .bold,
                                        design: .monospaced
                                    )
                                )
                                .foregroundColor(.white)
                                .padding(.top, 10)
                                .padding(.trailing, 12)
                        }
                        Text("書式は「YYYY.MM.DD HH:mm」固定です。0埋めのみ切替できます。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(
                LinearGradient(
                    colors: [Color.black.opacity(0.02), Color.black.opacity(0.08)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .navigationTitle("設定")
        }
        .onAppear {
            // Migrate older/invalid values to the new default preset.
            if !formats.contains(dateStampFormat) {
                dateStampFormat = DateStampFormatter.compactDateTime
            }
            dateStampSize = DateStampStyle.normalizedSizeKey(dateStampSize)
        }
        .onChange(of: dateStampZeroPadded) { _, _ in
            if !formats.contains(dateStampFormat) {
                dateStampFormat = DateStampFormatter.compactDateTime
            }
        }
    }

    private func label(for format: String) -> String {
        switch format {
        case DateStampFormatter.compactDateTime:
            return "YYYY.MM.DD HH:mm"
        default:
            return format
        }
    }

    private var previewText: String {
        DateStampFormatter.string(
            from: Date(),
            storedFormat: dateStampFormat,
            zeroPadded: dateStampZeroPadded
        )
    }

    private var previewFontSize: CGFloat {
        let renderSize = CGSize(width: 360, height: 640)
        return DateStampStyle.fontSize(for: renderSize, sizeKey: dateStampSize)
    }
}
