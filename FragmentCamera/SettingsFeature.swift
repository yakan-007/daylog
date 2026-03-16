import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    @AppStorage("isDateStampEnabled") var stampEnabled: Bool = true
    @AppStorage("dateStampFormat") var dateStampFormat: String = DateStampFormatter.compactDateTime
    @AppStorage("dateStampZeroPadded") var zeroPadded: Bool = false
    @AppStorage("dateStampSize") var stampSize: String = DateStampStyle.medium

    let formats = [DateStampFormatter.compactDateTime]

    init() {
        if !formats.contains(dateStampFormat) {
            dateStampFormat = DateStampFormatter.compactDateTime
        }
        stampSize = DateStampStyle.normalizedSizeKey(stampSize)
    }

    var previewText: String {
        DateStampFormatter.string(
            from: Date(),
            storedFormat: dateStampFormat,
            zeroPadded: zeroPadded
        )
    }

    var previewFontSize: CGFloat {
        DateStampStyle.fontSize(for: CGSize(width: 360, height: 640), sizeKey: stampSize)
    }

    func label(for format: String) -> String {
        switch format {
        case DateStampFormatter.compactDateTime:
            return "YYYY.MM.DD HH:mm"
        default:
            return format
        }
    }
}

struct SettingsFeatureView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("日付スタンプ")) {
                    Toggle("スタンプを表示", isOn: $viewModel.stampEnabled)
                    Toggle("0埋め", isOn: $viewModel.zeroPadded)
                    Picker("書式", selection: $viewModel.dateStampFormat) {
                        ForEach(viewModel.formats, id: \.self) { format in
                            Text(viewModel.label(for: format)).tag(format)
                        }
                    }
                    Picker("文字サイズ", selection: $viewModel.stampSize) {
                        Text("小").tag(DateStampStyle.small)
                        Text("中").tag(DateStampStyle.medium)
                        Text("大").tag(DateStampStyle.large)
                    }
                    .pickerStyle(.segmented)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("プレビュー")
                            .font(AppTheme.labelFont)
                            .foregroundStyle(.secondary)
                        ZStack(alignment: .topTrailing) {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(AppTheme.surfaceElevated)
                                .frame(height: 120)
                            Text(viewModel.previewText)
                                .font(.system(size: viewModel.previewFontSize, weight: .bold, design: .monospaced))
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
    }
}
