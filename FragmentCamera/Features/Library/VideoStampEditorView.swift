import SwiftUI

struct VideoStampEditorRoute: Identifiable, Equatable {
    let assetLocalIdentifier: String
    var id: String { assetLocalIdentifier }
}

@MainActor
final class VideoStampEditorViewModel: ObservableObject {
    @Published var stampEnabled = true
    @Published private(set) var commonStampEnabled = true
    @Published private(set) var commonElements: Set<DateStampElement> = [.date, .time]
    @Published private(set) var hiddenElements: Set<DateStampElement> = []
    @Published private(set) var canUsePlace = false
    @Published private(set) var requiresVideoRegeneration = false
    @Published private(set) var isLoading = true
    @Published private(set) var isSaving = false
    @Published private(set) var isUnavailable = false
    @Published var errorMessage: String?

    let assetLocalIdentifier: String
    private let service: VideoStampEditingService
    private var baseContext: VideoPostProcessContext?

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

    var position: DateStampPosition {
        baseContext?.position ?? .center
    }

    func isVisible(_ element: DateStampElement) -> Bool {
        commonElements.contains(element) && !hiddenElements.contains(element)
    }

    func isAvailable(_ element: DateStampElement) -> Bool {
        commonStampEnabled
            && commonElements.contains(element)
            && (element != .place || canUsePlace)
    }

    func load() async {
        guard baseContext == nil else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let editable = try await service.load(assetLocalIdentifier: assetLocalIdentifier)
            baseContext = editable.context
            stampEnabled = !editable.visibilityOverride.hidesStamp
            commonStampEnabled = editable.commonStampEnabled
            commonElements = editable.commonElements
            hiddenElements = editable.visibilityOverride.hiddenElements
            canUsePlace = editable.canUsePlace
            requiresVideoRegeneration = editable.requiresVideoRegeneration
        } catch {
            errorMessage = error.localizedDescription
            isUnavailable = true
        }
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
        if hiddenElements.contains(element) {
            hiddenElements.remove(element)
        } else {
            hiddenElements.insert(element)
        }
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
                    ProgressView("原本を読み込んでいます")
                        .accessibilityIdentifier("stampEditor.loading")
                } else if viewModel.isUnavailable {
                    unavailableView
                } else {
                    form
                }
            }
            .navigationTitle("この動画のスタンプ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DaylogModernTheme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                        .accessibilityIdentifier("stampEditor.cancel")
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
                    .accessibilityIdentifier("stampEditor.save")
                }
            }
        }
        .tint(DaylogModernTheme.accent)
        .background(DaylogModernBackground())
        .preferredColorScheme(.light)
        .task { await viewModel.load() }
        .alert("スタンプを変更できません", isPresented: errorBinding) {
            Button("閉じる", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? L10n.text("不明なエラーです。"))
        }
    }

    private var form: some View {
        Form {
            Section {
                Toggle("この動画にスタンプを表示", isOn: $viewModel.stampEnabled)
                    .disabled(!viewModel.commonStampEnabled)
                    .accessibilityIdentifier("stampEditor.enabled")
                ForEach(DateStampElement.allCases, id: \.rawValue) { element in
                    Button { viewModel.toggle(element) } label: {
                        HStack {
                            Label(element.title, systemImage: element.systemImage)
                            Spacer()
                            if !viewModel.commonElements.contains(element) {
                                Text("共通設定で非表示")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Image(systemName: viewModel.isVisible(element)
                                  ? "checkmark"
                                  : "minus")
                                .foregroundStyle(viewModel.isVisible(element)
                                                 ? DaylogModernTheme.accent
                                                 : DaylogModernTheme.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!viewModel.stampEnabled || !viewModel.isAvailable(element))
                    .accessibilityIdentifier("stampEditor.element.\(element.rawValue)")
                }
                Button("共通設定に戻す") {
                    viewModel.resetToCommonSettings()
                }
                .disabled(!viewModel.hasIndividualOverride)
                .accessibilityIdentifier("stampEditor.reset")
            } header: {
                Text("この動画だけの表示")
            } footer: {
                Text(viewModel.commonStampEnabled
                     ? L10n.text("位置・文字サイズ・時刻表記・フェードは、設定画面の共通設定を使います。ここでは、この動画だけ隠す内容を選べます。")
                     : L10n.text("共通設定でタイムスタンプが非表示です。表示内容を変更するには、先に設定画面でタイムスタンプを有効にしてください。"))
            }

            Section("共通設定でのプレビュー") {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.black.opacity(0.84))
                        .frame(height: 180)
                    Text(viewModel.previewLines.isEmpty
                         ? L10n.text("この動画では表示しません")
                         : viewModel.previewLines.joined(separator: "\n"))
                        .font(.system(size: 20, weight: .semibold))
                        .multilineTextAlignment(textAlignment)
                        .foregroundStyle(viewModel.previewLines.isEmpty
                                         ? Color.secondary
                                         : Color.white)
                        .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
                        .padding(12)
                }
                .frame(height: 180)
            }

            Section {
                Text(viewModel.requiresVideoRegeneration
                     ? L10n.text("この動画は撮影時焼き込みのため、保存時に写真ライブラリの編集内容を再生成します。原本は保持されます。")
                     : L10n.text("変更はアプリ内の表示設定として保存します。動画本体は再生成しません。"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 15))
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden)
        .background(DaylogModernBackground())
        .disabled(viewModel.isSaving)
        .overlay {
            if viewModel.isSaving {
                ProgressView(viewModel.requiresVideoRegeneration
                             ? L10n.text("動画を再生成しています")
                             : L10n.text("表示設定を保存しています"))
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private var unavailableView: some View {
        ContentUnavailableView(
            "この動画は編集できません",
            systemImage: "exclamationmark.triangle",
            description: Text(viewModel.errorMessage ?? L10n.text("原本がありません。"))
        )
    }

    private var alignment: Alignment {
        switch viewModel.position {
        case .topLeading: return .topLeading
        case .topTrailing: return .topTrailing
        case .bottomLeading: return .bottomLeading
        case .bottomTrailing: return .bottomTrailing
        case .center: return .center
        }
    }

    private var textAlignment: TextAlignment {
        switch viewModel.position {
        case .topLeading, .bottomLeading: return .leading
        case .topTrailing, .bottomTrailing: return .trailing
        case .center: return .center
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: {
                viewModel.errorMessage != nil
                    && !viewModel.isLoading
                    && !viewModel.isUnavailable
            },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }
}
