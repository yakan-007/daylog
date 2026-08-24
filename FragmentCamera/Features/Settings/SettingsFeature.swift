import SwiftUI

private enum DaylogLinks {
    static let privacyPolicy = URL(string: "https://github.com/yakan-007/daylog/blob/main/PRIVACY.md")!
    static let support = URL(string: "https://github.com/yakan-007/daylog/issues")!
}

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var stampEnabled: Bool {
        didSet { settingsStore.stampEnabled = stampEnabled }
    }
    @Published var dateStampFormat: String {
        didSet { settingsStore.stampFormat = dateStampFormat }
    }
    @Published var zeroPadded: Bool {
        didSet { settingsStore.stampZeroPadded = zeroPadded }
    }
    @Published var stampTimeStyleKey: String {
        didSet {
            settingsStore.stampTimeStyle = DateStampTimeStyle.normalized(
                stampTimeStyleKey
            )
        }
    }
    @Published var stampSize: String {
        didSet { settingsStore.stampSize = stampSize }
    }
    @Published var stampPositionKey: String {
        didSet {
            settingsStore.stampPosition = DateStampPosition.normalized(
                stampPositionKey
            )
        }
    }
    @Published private(set) var stampElements: Set<DateStampElement>
    @Published var stampFadesOut: Bool {
        didSet { settingsStore.stampFadesOut = stampFadesOut }
    }
    @Published var stampRenderingModeKey: String {
        didSet {
            settingsStore.stampRenderingMode = StampRenderingMode.normalized(
                stampRenderingModeKey
            )
        }
    }
    @Published var videoStorageModeKey: String {
        didSet {
            settingsStore.videoStorageMode = VideoStorageMode.normalized(videoStorageModeKey)
        }
    }
    @Published var locationCaptureEnabled: Bool {
        didSet {
            settingsStore.locationCaptureEnabled = locationCaptureEnabled
            guard !locationCaptureEnabled, stampElements.contains(.place) else { return }
            stampElements.remove(.place)
            if stampElements.isEmpty {
                stampElements.insert(.time)
            }
            settingsStore.stampElements = stampElements
        }
    }
    @Published var captureOrientationModeKey: String {
        didSet {
            settingsStore.captureOrientationMode = CaptureOrientationMode.normalized(
                captureOrientationModeKey
            )
        }
    }
    @Published private(set) var hasSeenCaptureIntroCard: Bool

    private let settingsStore: DaylogSettingsStore

    init(settingsStore: DaylogSettingsStore = DaylogSettingsStore()) {
        self.settingsStore = settingsStore
        stampEnabled = settingsStore.stampEnabled
        dateStampFormat = settingsStore.stampFormat
        zeroPadded = settingsStore.stampZeroPadded
        stampTimeStyleKey = settingsStore.stampTimeStyle.rawValue
        stampSize = settingsStore.stampSize
        stampPositionKey = settingsStore.stampPosition.rawValue
        stampElements = settingsStore.stampElements
        stampFadesOut = settingsStore.stampFadesOut
        stampRenderingModeKey = settingsStore.stampRenderingMode.rawValue
        videoStorageModeKey = settingsStore.videoStorageMode.rawValue
        locationCaptureEnabled = settingsStore.locationCaptureEnabled
        captureOrientationModeKey = settingsStore.captureOrientationMode.rawValue
        hasSeenCaptureIntroCard = settingsStore.hasSeenCaptureIntroCard
    }

    var previewLines: [String] {
        DateStampFormatter.lines(
            from: Date(),
            storedFormat: dateStampFormat,
            zeroPadded: zeroPadded,
            timeStyle: stampTimeStyle,
            elements: stampElements,
            placeName: stampElements.contains(.place) ? L10n.text("地名") : nil
        )
    }

    var previewFontSize: CGFloat {
        DateStampStyle.fontSize(
            for: CGSize(width: 360, height: 640),
            sizeKey: stampSize
        )
    }

    var stampPosition: DateStampPosition {
        DateStampPosition.normalized(stampPositionKey)
    }

    var stampTimeStyle: DateStampTimeStyle {
        DateStampTimeStyle.normalized(stampTimeStyleKey)
    }

    var videoStorageMode: VideoStorageMode {
        VideoStorageMode.normalized(videoStorageModeKey)
    }

    var stampRenderingMode: StampRenderingMode {
        StampRenderingMode.normalized(stampRenderingModeKey)
    }

    var captureOrientationMode: CaptureOrientationMode {
        CaptureOrientationMode.normalized(captureOrientationModeKey)
    }

    func toggleStampElement(_ element: DateStampElement) {
        var updated = stampElements
        if updated.contains(element) {
            guard updated.count > 1 else { return }
            updated.remove(element)
        } else {
            updated.insert(element)
            if element == .place, !locationCaptureEnabled {
                locationCaptureEnabled = true
            }
        }
        stampElements = updated
        settingsStore.stampElements = updated
    }

    func markCaptureIntroSeen() {
        guard !hasSeenCaptureIntroCard else { return }
        hasSeenCaptureIntroCard = true
        settingsStore.hasSeenCaptureIntroCard = true
    }

    var appVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return L10n.text("%@ %@ (%@)", AppIdentity.brandName, version, build)
    }

}

struct SettingsFeatureView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("撮影方向", selection: $viewModel.captureOrientationModeKey) {
                        ForEach(CaptureOrientationMode.allCases, id: \.rawValue) { mode in
                            Label(
                                mode.title,
                                systemImage: mode == .portrait
                                    ? "rectangle.portrait"
                                    : "rectangle"
                            )
                            .tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("settings.capture.orientation")
                    .accessibilityHint("縦向きまたは横向きの撮影画面を選びます")
                } header: {
                    Text("撮影方向")
                } footer: {
                    Text(
                        viewModel.captureOrientationMode == .portrait
                            ? L10n.text("撮影画面と保存動画を縦向きに固定します。")
                            : L10n.text("撮影画面と保存動画を横向きに固定します。")
                    )
                }

                Section {
                    Picker("保存容量", selection: $viewModel.videoStorageModeKey) {
                        ForEach(VideoStorageMode.allCases, id: \.rawValue) { mode in
                            Text(mode.title).tag(mode.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("settings.storage.mode")
                    .accessibilityHint("節約を選ぶと、次に撮影する動画を小さく保存します")
                } header: {
                    Text("保存容量")
                } footer: {
                    Text(
                        viewModel.videoStorageMode == .compact
                            ? L10n.text("次の撮影から720p・30fpsへ変換して容量を抑えます。保存に少し時間がかかります。")
                            : L10n.text("次の撮影から1080p・30fpsの画質を維持して保存します。")
                    )
                }

                Section {
                    Toggle("タイムスタンプを表示", isOn: $viewModel.stampEnabled)
                        .accessibilityIdentifier("settings.stamp.enabled")
                    if viewModel.stampEnabled {
                        Picker("反映するタイミング", selection: $viewModel.stampRenderingModeKey) {
                            ForEach(StampRenderingMode.allCases, id: \.rawValue) { mode in
                                Text(mode.title).tag(mode.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("settings.stamp.renderingMode")

                        Picker("表示位置", selection: $viewModel.stampPositionKey) {
                            ForEach(DateStampPosition.allCases, id: \.rawValue) { position in
                                Text(position.title).tag(position.rawValue)
                            }
                        }
                        .accessibilityIdentifier("settings.stamp.position")

                        ForEach(DateStampElement.allCases, id: \.rawValue) { element in
                            Button {
                                viewModel.toggleStampElement(element)
                            } label: {
                                HStack {
                                    Label(element.title, systemImage: element.systemImage)
                                    Spacer()
                                    Image(systemName: viewModel.stampElements.contains(element)
                                          ? "checkmark"
                                          : "minus")
                                        .foregroundStyle(viewModel.stampElements.contains(element)
                                                         ? DaylogModernTheme.accent
                                                         : DaylogModernTheme.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("settings.stamp.element.\(element.rawValue)")
                            .accessibilityValue(viewModel.stampElements.contains(element) ? L10n.text("選択中") : L10n.text("未選択"))
                        }

                        if viewModel.stampElements.contains(.date) {
                            Toggle("日付を0埋め", isOn: $viewModel.zeroPadded)
                                .accessibilityIdentifier("settings.stamp.zeroPadded")
                        }
                        if viewModel.stampElements.contains(.time) {
                            Picker("時刻表記", selection: $viewModel.stampTimeStyleKey) {
                                ForEach(DateStampTimeStyle.allCases, id: \.rawValue) { style in
                                    Text(L10n.text("%@（%@）", style.title, style.example))
                                        .tag(style.rawValue)
                                }
                            }
                            .accessibilityIdentifier("settings.stamp.timeStyle")
                        }
                        Toggle("2秒後にフェードアウト", isOn: $viewModel.stampFadesOut)
                            .accessibilityIdentifier("settings.stamp.fade")
                        Picker("文字サイズ", selection: $viewModel.stampSize) {
                            Text("小").tag(DateStampStyle.small)
                            Text("中").tag(DateStampStyle.medium)
                            Text("大").tag(DateStampStyle.large)
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("settings.stamp.size")

                        ZStack {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color.black.opacity(0.84))
                                .frame(height: 168)
                            previewStamp
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: previewAlignment)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                        }
                        .frame(height: 168)
                    }
                } header: {
                    Text("タイムスタンプ")
                } footer: {
                    if viewModel.stampEnabled {
                        Text(L10n.text("%@ 場所を選んだ場合だけ、撮影中に位置情報を使用します。", viewModel.stampRenderingMode.explanation))
                    } else {
                        Text("アプリ内の再生と書き出しでタイムスタンプを表示しません。")
                    }
                }

                Section {
                    Toggle("位置情報を記録", isOn: $viewModel.locationCaptureEnabled)
                        .accessibilityIdentifier("settings.location.enabled")
                        .accessibilityHint("オンの場合のみ、撮影中に現在地を動画へ記録します")
                } header: {
                    Text("プライバシー")
                } footer: {
                    Text("オンの場合だけ撮影中に現在地を取得し、動画へ記録します。")
                }

                Section {
                    Link(destination: DaylogLinks.privacyPolicy) {
                        Label("プライバシーポリシー", systemImage: "hand.raised")
                    }
                    .accessibilityHint("ブラウザでプライバシーポリシーを開きます")

                    Link(destination: DaylogLinks.support) {
                        Label("サポート・不具合報告", systemImage: "questionmark.bubble")
                    }
                    .accessibilityHint("ブラウザでサポートページを開きます")

                    Text(viewModel.appVersionText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("This Was My Day について")
                }
            }
            .font(.system(size: 15))
            .tint(DaylogModernTheme.accent)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .background(DaylogModernBackground())
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DaylogModernTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完了") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DaylogModernTheme.accent)
                    .accessibilityLabel("完了")
                    .accessibilityIdentifier("settings.done")
                }
            }
        }
        .preferredColorScheme(.light)
    }

    private var previewFont: Font {
        .system(size: viewModel.previewFontSize, weight: .semibold)
    }

    private var previewStamp: some View {
        Text(viewModel.previewLines.joined(separator: "\n"))
            .font(previewFont)
            .multilineTextAlignment(previewTextAlignment)
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
            .accessibilityIdentifier("settings.stamp.preview.text")
    }

    private var previewAlignment: Alignment {
        switch viewModel.stampPosition {
        case .topLeading: return .topLeading
        case .topTrailing: return .topTrailing
        case .bottomLeading: return .bottomLeading
        case .bottomTrailing: return .bottomTrailing
        case .center: return .center
        }
    }

    private var previewTextAlignment: TextAlignment {
        switch viewModel.stampPosition {
        case .topLeading, .bottomLeading: return .leading
        case .topTrailing, .bottomTrailing: return .trailing
        case .center: return .center
        }
    }
}
