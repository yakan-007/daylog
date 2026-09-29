import SwiftUI

struct VideoStampEditorRoute: Identifiable, Equatable {
    let assetLocalIdentifier: String
    var id: String { assetLocalIdentifier }
}

@MainActor
final class VideoStampEditorViewModel: ObservableObject {
    @Published var stampEnabled = true
    @Published var textOverlays: [VlogTextOverlay] = []
    @Published var selectedOverlayID: UUID?
    @Published private(set) var commonStampEnabled = true
    @Published private(set) var commonElements: Set<DateStampElement> = [.date, .time]
    @Published private(set) var hiddenElements: Set<DateStampElement> = []
    @Published private(set) var canUsePlace = false
    @Published private(set) var clipDuration: TimeInterval = 1
    @Published private(set) var videoAspectRatio: CGFloat = 9.0 / 16.0
    @Published private(set) var isLoading = true
    @Published private(set) var isSaving = false
    @Published private(set) var isUnavailable = false
    @Published var errorMessage: String?

    let assetLocalIdentifier: String
    private let service: VideoStampEditingService
    private var baseContext: VideoPostProcessContext?
    private var sourceMetadata: VlogClipSourceMetadata?

    init(assetLocalIdentifier: String, service: VideoStampEditingService) {
        self.assetLocalIdentifier = assetLocalIdentifier
        self.service = service
    }

    var visibleElements: Set<DateStampElement> {
        commonElements.subtracting(hiddenElements)
    }

    var hasIndividualOverride: Bool {
        !stampEnabled || !hiddenElements.isEmpty
    }

    var previewLines: [String] {
        guard commonStampEnabled, stampEnabled, let baseContext else { return [] }
        return DateStampFormatter.lines(
            from: baseContext.stampDate,
            storedFormat: baseContext.format,
            zeroPadded: baseContext.zeroPadded,
            timeStyle: baseContext.timeStyle,
            elements: visibleElements,
            placeName: visibleElements.contains(.place) ? (baseContext.placeName ?? L10n.text("地名")) : nil,
            timeZone: baseContext.stampTimeZone
        )
    }

    var resolvedTextOverlays: [VlogResolvedTextOverlay] {
        guard let sourceMetadata else { return [] }
        return VlogTextOverlayResolver.resolve(
            edit: currentEdit,
            metadata: sourceMetadata,
            clipDuration: clipDuration
        )
    }

    var selectedOverlay: VlogTextOverlay? {
        guard let selectedOverlayID else { return nil }
        return textOverlays.first { $0.id == selectedOverlayID }
    }

    var previewTime: TimeInterval {
        selectedOverlay?.timeRange.start ?? 0
    }

    private var currentEdit: VlogClipEdit {
        VlogClipEdit(
            assetLocalIdentifier: assetLocalIdentifier,
            textOverlays: textOverlays,
            updatedAt: Date()
        )
    }

    func isVisible(_ element: DateStampElement) -> Bool {
        commonElements.contains(element) && !hiddenElements.contains(element)
    }

    func isAvailable(_ element: DateStampElement) -> Bool {
        commonStampEnabled && commonElements.contains(element)
            && (element != .place || canUsePlace)
    }

    func load() async {
        guard baseContext == nil else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let editable = try await service.load(assetLocalIdentifier: assetLocalIdentifier)
            baseContext = editable.context
            sourceMetadata = editable.sourceMetadata
            clipDuration = max(editable.clipDuration, 0.1)
            videoAspectRatio = CGFloat(editable.videoAspectRatio)
            textOverlays = editable.clipEdit.textOverlays
            selectedOverlayID = textOverlays.first?.id
            stampEnabled = !editable.visibilityOverride.hidesStamp
            commonStampEnabled = editable.commonStampEnabled
            commonElements = editable.commonElements
            hiddenElements = editable.visibilityOverride.hiddenElements
            canUsePlace = editable.canUsePlace
        } catch {
            errorMessage = error.localizedDescription
            isUnavailable = true
        }
    }

    func addCustomText() { addOverlay(.custom(L10n.text("タイトル")), anchor: .center) }
    func addDate() { addOverlay(.capturedDate(format: .abbreviated), anchor: .bottomLeading) }
    func addTime() { addOverlay(.capturedTime(format: .system), anchor: .bottomLeading) }
    func addPlace() { addOverlay(.place(customName: nil), anchor: .bottomLeading) }

    private func addOverlay(_ source: VlogTextSource, anchor: VlogNormalizedPoint) {
        let overlay = VlogTextOverlay(source: source, anchor: anchor)
        textOverlays.append(overlay)
        selectedOverlayID = overlay.id
    }

    func select(_ id: UUID) { selectedOverlayID = id }

    func remove(_ id: UUID) {
        textOverlays.removeAll { $0.id == id }
        if selectedOverlayID == id { selectedOverlayID = textOverlays.first?.id }
    }

    func updateOverlay(_ id: UUID, _ update: (inout VlogTextOverlay) -> Void) {
        guard let index = textOverlays.firstIndex(where: { $0.id == id }) else { return }
        update(&textOverlays[index])
    }

    func toggle(_ element: DateStampElement) {
        guard commonElements.contains(element) else {
            errorMessage = L10n.text("この項目は共通設定で非表示になっています。")
            return
        }
        if element == .place, !canUsePlace {
            errorMessage = L10n.text("この動画には撮影場所が記録されていません。")
            return
        }
        if hiddenElements.contains(element) { hiddenElements.remove(element) }
        else { hiddenElements.insert(element) }
    }

    func resetToCommonSettings() {
        stampEnabled = true
        hiddenElements = []
    }

    func save() async -> Bool {
        guard baseContext != nil, !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            try await service.saveClipEdit(currentEdit, clipDuration: clipDuration)
            try await service.apply(
                assetLocalIdentifier: assetLocalIdentifier,
                visibilityOverride: VideoStampVisibilityOverride(
                    hidesStamp: !stampEnabled,
                    hiddenElements: hiddenElements
                ).normalized
            )
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

struct VideoStampEditorView: View {
    @StateObject private var viewModel: VideoStampEditorViewModel
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss

    init(viewModel: VideoStampEditorViewModel, onSaved: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onSaved = onSaved
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("動画を読み込んでいます")
                        .accessibilityIdentifier("stampEditor.loading")
                } else if viewModel.isUnavailable {
                    unavailableView
                } else {
                    editor
                }
            }
            .navigationTitle("動画を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DaylogModernTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        Task {
                            if await viewModel.save() {
                                onSaved()
                                dismiss()
                            }
                        }
                    }
                    .disabled(viewModel.isLoading || viewModel.isSaving)
                }
            }
        }
        .tint(DaylogModernTheme.accent)
        .background(DaylogModernBackground())
        .preferredColorScheme(.light)
        .task { await viewModel.load() }
        .alert("編集内容を保存できません", isPresented: errorBinding) {
            Button("閉じる", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? L10n.text("不明なエラーです。"))
        }
    }

    private var editor: some View {
        Form {
            Section {
                preview
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section("追加") {
                HStack(spacing: 0) {
                    addButton("文字", systemImage: "textformat", action: viewModel.addCustomText)
                    addButton("日付", systemImage: "calendar", action: viewModel.addDate)
                    addButton("時刻", systemImage: "clock", action: viewModel.addTime)
                    addButton("場所", systemImage: "location", action: viewModel.addPlace)
                }
            }

            if viewModel.textOverlays.isEmpty {
                Section {
                    Text("文字・日付・時刻・場所を重ねられます。元の動画は変更しません。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("レイヤー") {
                    ForEach(viewModel.textOverlays) { overlay in overlayRow(overlay) }
                }
            }

            if let overlay = viewModel.selectedOverlay { overlayInspector(overlay) }

            Section {
                DisclosureGroup("撮影情報の共通表示") {
                    Toggle("この動画に表示", isOn: $viewModel.stampEnabled)
                        .disabled(!viewModel.commonStampEnabled)
                    ForEach(DateStampElement.allCases, id: \.rawValue) { element in
                        Button { viewModel.toggle(element) } label: {
                            HStack {
                                Label(element.title, systemImage: element.systemImage)
                                Spacer()
                                Image(systemName: viewModel.isVisible(element) ? "checkmark" : "minus")
                                    .foregroundStyle(viewModel.isVisible(element) ? .primary : .tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!viewModel.stampEnabled || !viewModel.isAvailable(element))
                    }
                    Button("共通設定に戻す", action: viewModel.resetToCommonSettings)
                        .disabled(!viewModel.hasIndividualOverride)
                }
            } footer: {
                Text("従来の撮影日時表示です。新しい文字レイヤーとは別に管理されます。")
            }
        }
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .background(DaylogModernBackground())
        .disabled(viewModel.isSaving)
        .overlay {
            if viewModel.isSaving {
                ProgressView("編集内容を保存しています")
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.9))
            if !viewModel.previewLines.isEmpty {
                Text(viewModel.previewLines.joined(separator: "\n"))
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(16)
            }
            VlogTextOverlayCanvas(
                overlays: viewModel.resolvedTextOverlays,
                playbackTime: viewModel.previewTime,
                videoAspectRatio: viewModel.videoAspectRatio
            )
            .allowsHitTesting(false)
        }
        .frame(height: 210)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityIdentifier("stampEditor.preview")
    }

    private func addButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: systemImage).font(.system(size: 18, weight: .medium))
                Text(title).font(.caption)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.plain)
    }

    private func overlayRow(_ overlay: VlogTextOverlay) -> some View {
        Button { viewModel.select(overlay.id) } label: {
            HStack(spacing: 12) {
                Image(systemName: sourceIcon(overlay.source)).frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(sourceTitle(overlay.source))
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(rangeText(overlay.timeRange))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if viewModel.selectedOverlayID == overlay.id {
                    Image(systemName: "checkmark").foregroundStyle(.primary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions {
            Button(role: .destructive) { viewModel.remove(overlay.id) } label: {
                Label("削除", systemImage: "trash")
            }
        }
    }

    private func overlayInspector(_ overlay: VlogTextOverlay) -> some View {
        Section("選択中のレイヤー") {
            sourceEditor(overlay)
            Picker("位置", selection: anchorBinding(for: overlay)) {
                Text("左上").tag(VlogOverlayAnchorPreset.topLeading)
                Text("中央").tag(VlogOverlayAnchorPreset.center)
                Text("左下").tag(VlogOverlayAnchorPreset.bottomLeading)
                Text("右下").tag(VlogOverlayAnchorPreset.bottomTrailing)
            }
            labeledSlider(
                title: "大きさ",
                valueText: String(format: "%.0f%%", overlay.style.relativeSize * 100),
                value: sizeBinding(for: overlay),
                range: 0.5...2,
                step: 0.1
            )
            labeledSlider(
                title: "表示開始",
                valueText: timeText(overlay.timeRange.start),
                value: startBinding(for: overlay),
                range: 0...max(viewModel.clipDuration - 0.1, 0.1),
                step: 0.1
            )
            labeledSlider(
                title: "表示終了",
                valueText: timeText(overlay.timeRange.end ?? viewModel.clipDuration),
                value: endBinding(for: overlay),
                range: 0.1...viewModel.clipDuration,
                step: 0.1
            )
        }
    }

    private func labeledSlider(
        title: String,
        valueText: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step)
        }
    }

    @ViewBuilder
    private func sourceEditor(_ overlay: VlogTextOverlay) -> some View {
        switch overlay.source {
        case .custom(let text):
            TextField("文字を入力", text: customTextBinding(for: overlay, fallback: text))
        case .place(let customName):
            TextField("撮影場所を使う", text: placeBinding(for: overlay, fallback: customName ?? ""))
        case .capturedDate(let format):
            Picker("日付の表示", selection: dateFormatBinding(for: overlay, fallback: format)) {
                Text("短く").tag(VlogDateFormat.numeric)
                Text("標準").tag(VlogDateFormat.abbreviated)
                Text("詳しく").tag(VlogDateFormat.full)
            }
        case .capturedTime(let format):
            Picker("時刻の表示", selection: timeFormatBinding(for: overlay, fallback: format)) {
                Text("端末設定").tag(VlogTimeFormat.system)
                Text("12時間").tag(VlogTimeFormat.twelveHour)
                Text("24時間").tag(VlogTimeFormat.twentyFourHour)
            }
        }
    }

    private func customTextBinding(for overlay: VlogTextOverlay, fallback: String) -> Binding<String> {
        Binding(get: {
            guard let current = viewModel.textOverlays.first(where: { $0.id == overlay.id }),
                  case .custom(let text) = current.source else { return fallback }
            return text
        }, set: { value in viewModel.updateOverlay(overlay.id) { $0.source = .custom(value) } })
    }

    private func placeBinding(for overlay: VlogTextOverlay, fallback: String) -> Binding<String> {
        Binding(get: {
            guard let current = viewModel.textOverlays.first(where: { $0.id == overlay.id }),
                  case .place(let value) = current.source else { return fallback }
            return value ?? ""
        }, set: { value in
            viewModel.updateOverlay(overlay.id) { $0.source = .place(customName: value.isEmpty ? nil : value) }
        })
    }

    private func dateFormatBinding(for overlay: VlogTextOverlay, fallback: VlogDateFormat) -> Binding<VlogDateFormat> {
        Binding(get: {
            guard let current = viewModel.textOverlays.first(where: { $0.id == overlay.id }),
                  case .capturedDate(let value) = current.source else { return fallback }
            return value
        }, set: { value in viewModel.updateOverlay(overlay.id) { $0.source = .capturedDate(format: value) } })
    }

    private func timeFormatBinding(for overlay: VlogTextOverlay, fallback: VlogTimeFormat) -> Binding<VlogTimeFormat> {
        Binding(get: {
            guard let current = viewModel.textOverlays.first(where: { $0.id == overlay.id }),
                  case .capturedTime(let value) = current.source else { return fallback }
            return value
        }, set: { value in viewModel.updateOverlay(overlay.id) { $0.source = .capturedTime(format: value) } })
    }

    private func anchorBinding(for overlay: VlogTextOverlay) -> Binding<VlogOverlayAnchorPreset> {
        Binding(get: {
            VlogOverlayAnchorPreset(point: viewModel.textOverlays.first(where: { $0.id == overlay.id })?.anchor ?? overlay.anchor)
        }, set: { value in viewModel.updateOverlay(overlay.id) { $0.anchor = value.point } })
    }

    private func sizeBinding(for overlay: VlogTextOverlay) -> Binding<Double> {
        Binding(
            get: { viewModel.textOverlays.first(where: { $0.id == overlay.id })?.style.relativeSize ?? 1 },
            set: { value in viewModel.updateOverlay(overlay.id) { $0.style.relativeSize = value } }
        )
    }

    private func startBinding(for overlay: VlogTextOverlay) -> Binding<Double> {
        Binding(get: {
            viewModel.textOverlays.first(where: { $0.id == overlay.id })?.timeRange.start ?? 0
        }, set: { value in
            viewModel.updateOverlay(overlay.id) {
                let end = $0.timeRange.end ?? viewModel.clipDuration
                $0.timeRange.start = min(value, max(end - 0.1, 0))
            }
        })
    }

    private func endBinding(for overlay: VlogTextOverlay) -> Binding<Double> {
        Binding(get: {
            viewModel.textOverlays.first(where: { $0.id == overlay.id })?.timeRange.end ?? viewModel.clipDuration
        }, set: { value in
            viewModel.updateOverlay(overlay.id) { $0.timeRange.end = max(value, $0.timeRange.start + 0.1) }
        })
    }

    private func sourceTitle(_ source: VlogTextSource) -> String {
        switch source {
        case .custom(let text): return text.isEmpty ? L10n.text("文字") : text
        case .capturedDate: return L10n.text("撮影日")
        case .capturedTime: return L10n.text("撮影時刻")
        case .place(let customName): return customName ?? L10n.text("撮影場所")
        }
    }

    private func sourceIcon(_ source: VlogTextSource) -> String {
        switch source {
        case .custom: return "textformat"
        case .capturedDate: return "calendar"
        case .capturedTime: return "clock"
        case .place: return "location"
        }
    }

    private func rangeText(_ range: VlogOverlayTimeRange) -> String {
        "\(timeText(range.start)) – \(timeText(range.end ?? viewModel.clipDuration))"
    }

    private func timeText(_ seconds: TimeInterval) -> String { String(format: "%.1f秒", seconds) }

    private var unavailableView: some View {
        ContentUnavailableView(
            "この動画は編集できません",
            systemImage: "exclamationmark.triangle",
            description: Text(viewModel.errorMessage ?? L10n.text("原本がありません。"))
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: {
            viewModel.errorMessage != nil && !viewModel.isLoading && !viewModel.isUnavailable
        }, set: { if !$0 { viewModel.errorMessage = nil } })
    }
}

private enum VlogOverlayAnchorPreset: String, Hashable {
    case topLeading
    case center
    case bottomLeading
    case bottomTrailing

    init(point: VlogNormalizedPoint) {
        if point.y < 0.3 { self = .topLeading }
        else if point.x > 0.7 { self = .bottomTrailing }
        else if point.y < 0.7 { self = .center }
        else { self = .bottomLeading }
    }

    var point: VlogNormalizedPoint {
        switch self {
        case .topLeading: return .topLeading
        case .center: return .center
        case .bottomLeading: return .bottomLeading
        case .bottomTrailing: return .bottomTrailing
        }
    }
}
