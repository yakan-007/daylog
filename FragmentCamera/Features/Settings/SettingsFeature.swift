import SwiftUI

private enum VlogishLinks {
    static let privacyPolicy = URL(string: "https://github.com/yakan-007/daylog/blob/main/PRIVACY.md")!
    static let support = URL(string: "https://github.com/yakan-007/daylog/issues")!
}

/// 設定。世界中で使われる前提で、項目は「誰にでも意味が分かるもの」だけに絞る。
///
/// - 日付の並びは地域に合わせて自動（変えることもできる）。数字は常に0でそろえる。
/// - 時刻は iPhone の12時間／24時間の設定に従う（アプリでは持たない）。
/// - 位置は編集画面と同じ9か所。
@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var stampEnabled: Bool {
        didSet { settingsStore.stampEnabled = stampEnabled }
    }
    /// nil なら地域に合わせる。
    @Published var dateOrderOverride: DateStampDateOrder? {
        didSet { settingsStore.stampDateOrderOverride = dateOrderOverride }
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
    @Published var exportEndMarkEnabled: Bool {
        didSet { settingsStore.exportEndMarkEnabled = exportEndMarkEnabled }
    }
    @Published private(set) var hasSeenCaptureIntroCard: Bool
    @Published private(set) var hasSeenCaptureCoach: Bool

    private let settingsStore: VlogishSettingsStore

    init(settingsStore: VlogishSettingsStore = VlogishSettingsStore()) {
        self.settingsStore = settingsStore
        stampEnabled = settingsStore.stampEnabled
        dateOrderOverride = settingsStore.stampDateOrderOverride
        stampSize = settingsStore.stampSize
        stampPositionKey = settingsStore.stampPosition.rawValue
        stampElements = settingsStore.stampElements
        stampFadesOut = settingsStore.stampFadesOut
        stampRenderingModeKey = settingsStore.stampRenderingMode.rawValue
        videoStorageModeKey = settingsStore.videoStorageMode.rawValue
        locationCaptureEnabled = settingsStore.locationCaptureEnabled
        exportEndMarkEnabled = settingsStore.exportEndMarkEnabled
        hasSeenCaptureIntroCard = settingsStore.hasSeenCaptureIntroCard
        hasSeenCaptureCoach = settingsStore.hasSeenCaptureCoach
    }

    /// 編集画面と同じ描き方でプレビューするための、現在の設定のスタンプ。
    var previewStampSettings: DateStampSettings {
        DateStampSettings(
            isEnabled: stampEnabled,
            format: dateOrder.rawValue,
            isZeroPadded: true,
            timeStyle: DateStampTimeStyle.system(),
            sizeKey: stampSize,
            position: stampPosition,
            elements: stampElements,
            fadesOut: stampFadesOut
        )
    }

    var dateOrder: DateStampDateOrder {
        dateOrderOverride ?? DateStampDateOrder.regional()
    }

    var stampPosition: DateStampPosition {
        DateStampPosition.normalized(stampPositionKey)
    }

    var videoStorageMode: VideoStorageMode {
        VideoStorageMode.normalized(videoStorageModeKey)
    }

    var stampRenderingMode: StampRenderingMode {
        StampRenderingMode.normalized(stampRenderingModeKey)
    }

    /// 写真アプリや共有先でも日付を見せる（＝撮影直後に焼き込む）。
    var burnsStampIntoVideo: Bool {
        get { stampRenderingMode == .burnOnCapture }
        set {
            stampRenderingModeKey = (newValue ? StampRenderingMode.burnOnCapture : .playbackOverlay).rawValue
        }
    }

    func selectDateOrder(_ order: DateStampDateOrder) {
        // 地域の並びと同じものを選んだら「自動」に戻す（旅先で地域を変えても追従するように）。
        dateOrderOverride = order == DateStampDateOrder.regional() ? nil : order
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

    /// はじめての案内のスタンプ選び。オフの時に押したら、その1つだけでオンにする。
    /// 最後の1つを外したら、スタンプ自体をオフにする（「なし」と同じ）。
    func toggleStampElementForSetup(_ element: DateStampElement) {
        guard stampEnabled else {
            stampEnabled = true
            stampElements = [element]
            settingsStore.stampElements = stampElements
            if element == .place, !locationCaptureEnabled {
                locationCaptureEnabled = true
            }
            return
        }
        if stampElements == [element] {
            stampEnabled = false
            return
        }
        toggleStampElement(element)
    }

    func markCaptureCoachSeen() {
        guard !hasSeenCaptureCoach else { return }
        hasSeenCaptureCoach = true
        settingsStore.hasSeenCaptureCoach = true
    }

    func markCaptureIntroSeen() {
        guard !hasSeenCaptureIntroCard else { return }
        hasSeenCaptureIntroCard = true
        settingsStore.hasSeenCaptureIntroCard = true
    }

    var appVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(AppIdentity.brandName.uppercased()) \(version) (\(build))"
    }
}

struct SettingsFeatureView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    stampSection
                    storageSection
                    exportSection
                    privacySection
                    aboutSection
                }
                .padding(.horizontal, RollTheme.pagePadding)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .background(RollTheme.ground.ignoresSafeArea())
            .foregroundStyle(RollTheme.ink)
            .tint(RollTheme.ink)
            .navigationTitle(L10n.text("設定"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(RollTheme.ground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: {
                        Text(L10n.text("完了"))
                            .rollText(14, .bold)
                            .foregroundStyle(RollTheme.ground)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 32)
                            .background(RollTheme.ink, in: Capsule())
                    }
                    .buttonStyle(SquishableButtonStyle())
                    .accessibilityLabel(L10n.text("完了"))
                    .accessibilityIdentifier("settings.done")
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: viewModel.stampEnabled)
        }
        .preferredColorScheme(.light)
    }

    // MARK: Stamp

    private var stampSection: some View {
        VStack(alignment: .leading, spacing: 18) {
            Toggle(isOn: $viewModel.stampEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    sectionHeader("STAMP")
                    Text(L10n.text("撮った動画にスタンプを入れる"))
                        .rollText(15, .bold)
                }
            }
            .accessibilityIdentifier("settings.stamp.enabled")

            stampPreview

            if viewModel.stampEnabled {
                elementButtons
                HStack(alignment: .top, spacing: 18) {
                    positionGrid
                    sizePicker
                }
                detailRows
            } else {
                Text(L10n.text("オフでも、1本ずつの編集で日付やひとことを足せます。"))
                    .rollText(12)
                    .foregroundStyle(RollTheme.secondary)
            }
        }
    }

    /// 日付スタンプの見本。編集画面・再生と同じ描き方（VlogTextOverlayCanvas）で、縦動画の枠に置く。
    private var stampPreview: some View {
        let block = VlogStampLayerSeeder.block(
            settings: viewModel.previewStampSettings,
            placeName: L10n.text("地名")
        )
        let edit = VlogClipEdit(assetLocalIdentifier: "settings.preview", block: block)
        let overlays = VlogTextOverlayResolver.resolve(
            edit: edit,
            metadata: VlogClipSourceMetadata(
                capturedAt: Date(),
                capturedPlaceName: nil,
                timeZoneIdentifier: TimeZone.current.identifier
            ),
            clipDuration: 3
        )
        return ZStack(alignment: .topTrailing) {
            LinearGradient(
                colors: [Color(hex: 0x5E7180), Color(hex: 0x2C3038)],
                startPoint: .top,
                endPoint: .bottom
            )
            VlogTextOverlayCanvas(
                overlays: viewModel.stampEnabled ? overlays : [],
                playbackTime: 0,
                videoAspectRatio: 9.0 / 16.0
            )
            .allowsHitTesting(false)

            Text(verbatim: "PREVIEW")
                .rollMono(9, .semibold, maxScale: 1.2)
                .tracking(1)
                .foregroundStyle(.white.opacity(0.7))
                .padding(10)
        }
        .aspectRatio(9.0 / 16.0, contentMode: .fit)
        .frame(maxHeight: 300)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .opacity(viewModel.stampEnabled ? 1 : 0.5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(viewModel.stampEnabled ? (overlays.first?.text ?? L10n.text("タイムスタンプなし")) : L10n.text("タイムスタンプなし"))
        .accessibilityIdentifier("settings.stamp.preview.text")
    }

    /// 日付・時刻・場所。編集画面と同じ丸ボタン（明るい地なので、オンは黒）。
    private var elementButtons: some View {
        HStack(spacing: 0) {
            ForEach(DateStampElement.allCases, id: \.rawValue) { element in
                let isOn = viewModel.stampElements.contains(element)
                Button {
                    viewModel.toggleStampElement(element)
                } label: {
                    VStack(spacing: 6) {
                        Group {
                            switch element {
                            case .date:
                                Text(verbatim: CameraRollStampFormat.date.string(from: Date()))
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            case .time:
                                Text(verbatim: CameraRollStampFormat.hourMinute.string(from: Date()))
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            case .place:
                                Image(systemName: "mappin.and.ellipse")
                                    .font(.system(size: 16, weight: .medium))
                            }
                        }
                        .foregroundStyle(isOn ? RollTheme.ground : RollTheme.ink)
                        .frame(width: 48, height: 48)
                        .background {
                            if isOn {
                                Circle().fill(RollTheme.ink)
                            } else {
                                Circle().strokeBorder(RollTheme.hairline.opacity(1), lineWidth: 1)
                            }
                        }
                        Text(element.title)
                            .rollText(11)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(SquishableButtonStyle())
                .accessibilityLabel(element.title)
                .accessibilityValue(isOn ? L10n.text("選択中") : L10n.text("未選択"))
                .accessibilityAddTraits(isOn ? .isSelected : [])
                .accessibilityIdentifier("settings.stamp.element.\(element.rawValue)")
            }
        }
        .sensoryFeedback(.selection, trigger: viewModel.stampElements)
    }

    private var positionGrid: some View {
        let columns = Array(repeating: GridItem(.fixed(26), spacing: 4), count: 3)
        return VStack(alignment: .leading, spacing: 6) {
            Text(L10n.text("位置"))
                .rollText(11)
                .foregroundStyle(RollTheme.secondary)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(DateStampPosition.allCases, id: \.rawValue) { position in
                    let isSelected = viewModel.stampPosition == position
                    Button {
                        viewModel.stampPositionKey = position.rawValue
                    } label: {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(isSelected ? RollTheme.ink : RollTheme.fill)
                            .frame(width: 26, height: 26)
                            .overlay {
                                Circle()
                                    .fill(isSelected ? RollTheme.ground : RollTheme.dashed)
                                    .frame(width: 5, height: 5)
                            }
                            .contentShape(Rectangle().inset(by: -2))
                    }
                    .buttonStyle(SquishableButtonStyle())
                    .accessibilityLabel(position.title)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .frame(width: 86)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.text("%@、%@", L10n.text("表示位置"), viewModel.stampPosition.title))
        .accessibilityIdentifier("settings.stamp.position")
        .sensoryFeedback(.selection, trigger: viewModel.stampPositionKey)
    }

    private var sizePicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.text("大きさ"))
                .rollText(11)
                .foregroundStyle(RollTheme.secondary)
            SettingsSegmented(
                options: [
                    (DateStampStyle.small, L10n.text("小")),
                    (DateStampStyle.medium, L10n.text("中")),
                    (DateStampStyle.large, L10n.text("大"))
                ],
                selection: $viewModel.stampSize
            )
            .accessibilityIdentifier("settings.stamp.size")
        }
    }

    private var detailRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            divider

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(L10n.text("日付の順番"))
                        .rollText(14)
                    Spacer()
                    Text(viewModel.dateOrderOverride == nil ? L10n.text("地域に合わせて自動") : L10n.text("手動で選択中"))
                        .rollText(11)
                        .foregroundStyle(RollTheme.secondary)
                }
                SettingsSegmented(
                    options: DateStampDateOrder.allCases.map { ($0, $0.title) },
                    selection: Binding(
                        get: { viewModel.dateOrder },
                        set: viewModel.selectDateOrder
                    )
                )
                .accessibilityIdentifier("settings.stamp.dateOrder")
            }
            .padding(.vertical, 12)
            rowDivider

            Toggle(isOn: $viewModel.stampFadesOut) {
                Text(L10n.text("2秒後にフェードアウト"))
                    .rollText(14)
            }
            .frame(minHeight: 50)
            .accessibilityIdentifier("settings.stamp.fade")
            rowDivider

            Toggle(isOn: Binding(
                get: { viewModel.burnsStampIntoVideo },
                set: { viewModel.burnsStampIntoVideo = $0 }
            )) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.text("写真アプリや共有先でもスタンプを表示"))
                        .rollText(14)
                    Text(viewModel.burnsStampIntoVideo
                         ? L10n.text("撮った直後の動画にスタンプを入れて保存します。写真アプリに残るスタンプは、後から変えられません。")
                         : L10n.text("オフなら元の動画はそのまま。スタンプはアプリの中と書き出しのときに入り、後から変えられます。"))
                        .rollText(11)
                        .foregroundStyle(RollTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 10)
            .accessibilityIdentifier("settings.stamp.renderingMode")
            rowDivider

            Text(L10n.text("時刻は iPhone の設定（12時間／24時間）に合わせて表示します。"))
                .rollText(11)
                .foregroundStyle(RollTheme.secondary)
                .padding(.top, 10)
        }
    }

    // MARK: Storage

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("STORAGE")
            SettingsSegmented(
                options: VideoStorageMode.allCases.map { ($0.rawValue, $0.title) },
                selection: $viewModel.videoStorageModeKey
            )
            .accessibilityIdentifier("settings.storage.mode")
            .accessibilityHint(L10n.text("節約を選ぶと、次に撮影する動画を小さく保存します"))
            Text(
                viewModel.videoStorageMode == .compact
                    ? L10n.text("次の撮影から720p・30fpsへ変換して容量を抑えます。保存に少し時間がかかります。")
                    : L10n.text("次の撮影から1080p・30fpsの画質を維持して保存します。")
            )
            .rollText(11)
            .foregroundStyle(RollTheme.secondary)
        }
    }

    // MARK: Export

    private var exportSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("EXPORT")
                .padding(.bottom, 4)
            Toggle(isOn: $viewModel.exportEndMarkEnabled) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.text("書き出しにロゴを入れる"))
                        .rollText(14)
                    Text(L10n.text("最後の1.5秒だけ、隅に小さく入ります。写真に残る元の動画には入りません。"))
                        .rollText(11)
                        .foregroundStyle(RollTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 10)
            .accessibilityIdentifier("settings.export.endMark")
            rowDivider
        }
    }

    // MARK: Privacy

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("PRIVACY")
                .padding(.bottom, 4)
            Toggle(isOn: $viewModel.locationCaptureEnabled) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(L10n.text("撮影場所を記録"))
                        .rollText(14)
                    Text(L10n.text("記録の地名と、日付の「場所」に使います。地名を調べる時だけ Apple の地図サービスに問い合わせ、ほかには送りません。"))
                        .rollText(11)
                        .foregroundStyle(RollTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 10)
            .accessibilityIdentifier("settings.location.enabled")
            rowDivider
        }
    }

    // MARK: About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("ABOUT")
                .padding(.bottom, 4)
            linkRow(L10n.text("プライバシーポリシー"), url: VlogishLinks.privacyPolicy)
                .accessibilityHint(L10n.text("ブラウザでプライバシーポリシーを開きます"))
            linkRow(L10n.text("サポート・不具合報告"), url: VlogishLinks.support)
                .accessibilityHint(L10n.text("ブラウザでサポートページを開きます"))
            Text(verbatim: viewModel.appVersionText)
                .rollMono(11)
                .foregroundStyle(RollTheme.secondary)
                .padding(.top, 18)
        }
    }

    private func linkRow(_ title: String, url: URL) -> some View {
        Link(destination: url) {
            HStack {
                Text(title)
                    .rollText(14)
                    .foregroundStyle(RollTheme.ink)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(RollTheme.secondary)
            }
            .frame(minHeight: 50)
            .overlay(alignment: .bottom) { rowDivider }
            .contentShape(Rectangle())
        }
    }

    // MARK: Parts

    /// 記録画面の "EARLIER" と同じ、言語によらない小さな見出し。
    private func sectionHeader(_ text: String) -> some View {
        Text(verbatim: text)
            .rollMono(10, .semibold)
            .tracking(1.2)
            .foregroundStyle(RollTheme.secondary)
            .accessibilityAddTraits(.isHeader)
    }

    private var divider: some View {
        Rectangle().fill(RollTheme.hairline).frame(height: 1)
    }

    private var rowDivider: some View {
        Rectangle().fill(RollTheme.rowLine).frame(height: 1)
    }
}

/// 設定用のセグメント。選んだものは白く浮かせる（地は薄いグレー）。
private struct SettingsSegmented<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let isSelected = option.0 == selection
                Button {
                    selection = option.0
                } label: {
                    Text(option.1)
                        .rollText(13, isSelected ? .bold : .regular)
                        .foregroundStyle(isSelected ? RollTheme.ink : RollTheme.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(Color.white)
                                    .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.1)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(3)
        .background(RollTheme.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .sensoryFeedback(.selection, trigger: selection)
    }
}
