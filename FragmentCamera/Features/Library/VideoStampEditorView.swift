import AVFoundation
import Photos
import SwiftUI
import UIKit

struct VideoStampEditorRoute: Identifiable, Equatable {
    let assetLocalIdentifier: String
    var id: String { assetLocalIdentifier }
}

/// 1本のクリップの編集。共通設定の日付スタンプに「ちょっと足す」ための画面。
///
/// 表示は1つのかたまり（日付・時刻・場所・ひとこと）だけ。日付・時刻・場所は出す／出さないを
/// 切り替え、その下にひとことを書ける。かたまりはドラッグで移動、2本指で大きさを変える。
/// 共通設定がオフなら、空の状態からここで組み立てる。
///
/// 編集項目を足す時は、`VlogClipEdit` にプロパティを足し、ここに状態と操作、
/// 画面に1セクションを足す（既存のセクションには触らない）。
@MainActor
final class VideoStampEditorViewModel: ObservableObject {
    @Published var block = VlogStampBlock()
    @Published private(set) var clipDuration: TimeInterval = 1
    @Published private(set) var videoAspectRatio: CGFloat = 9.0 / 16.0
    @Published private(set) var previewTime: TimeInterval = 0
    @Published private(set) var isPreviewLoading = false
    @Published private(set) var isPreviewReady = false
    @Published private(set) var isPreviewPlaying = false
    @Published private(set) var previewLoadFailed = false
    @Published private(set) var isLoading = true
    @Published private(set) var isSaving = false
    @Published private(set) var isUnavailable = false
    /// 撮影場所の名前（撮影時に取得したもの）。nil の時は「場所」を出せない。
    @Published private(set) var capturedPlaceName: String?
    @Published var errorMessage: String?

    let assetLocalIdentifier: String
    let previewPlayer = AVPlayer()
    private let service: VideoStampEditingService
    private var baseContext: VideoPostProcessContext?
    private var sourceMetadata: VlogClipSourceMetadata?
    private var stampSettings: DateStampSettings?
    private var sourceTimeZoneIdentifier: String?
    /// 共通スタンプをこのクリップで既に隠しているか（保存時の重複処理を避ける）。
    private var hidesCommonStamp = false
    private var previewRequestID: PHImageRequestID?
    private var previewTimeObserver: Any?
    private var previewEndObserver: NSObjectProtocol?
    private var previewLoadGeneration = 0

    init(assetLocalIdentifier: String, service: VideoStampEditingService) {
        self.assetLocalIdentifier = assetLocalIdentifier
        self.service = service
    }

    // MARK: Derived

    var resolvedTextOverlays: [VlogResolvedTextOverlay] {
        guard let sourceMetadata else { return [] }
        return VlogTextOverlayResolver.resolve(
            edit: currentEdit,
            metadata: sourceMetadata,
            clipDuration: clipDuration
        )
    }

    var canShowPlace: Bool {
        !(capturedPlaceName?.isEmpty ?? true) || !block.placeName.isEmpty
    }

    /// 日付・時刻の実際の表示（ボタンに添える）。
    var dateText: String { sampleLine(showing: \.showsDate) }
    var timeText: String { sampleLine(showing: \.showsTime) }

    private var currentEdit: VlogClipEdit {
        VlogClipEdit(
            assetLocalIdentifier: assetLocalIdentifier,
            block: block,
            sourceTimeZoneIdentifier: sourceTimeZoneIdentifier,
            updatedAt: Date()
        )
    }

    private func sampleLine(showing keyPath: WritableKeyPath<VlogStampBlock, Bool>) -> String {
        guard let sourceMetadata else { return "" }
        var sample = VlogStampBlock(
            dateFormat: block.dateFormat,
            zeroPadded: block.zeroPadded,
            timeStyle: block.timeStyle
        )
        sample[keyPath: keyPath] = true
        let timeZone = sourceTimeZoneIdentifier.flatMap(TimeZone.init(identifier:))
            ?? sourceMetadata.timeZone
        return VlogTextOverlayResolver.lines(
            for: sample,
            capturedAt: sourceMetadata.capturedAt,
            timeZone: timeZone
        ).first ?? ""
    }

    // MARK: Load

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
            block = editable.clipEdit.block
            capturedPlaceName = editable.placeName
            stampSettings = editable.stampSettings
            sourceTimeZoneIdentifier = editable.clipEdit.sourceTimeZoneIdentifier
                ?? editable.context.timeZoneIdentifier
            hidesCommonStamp = editable.visibilityOverride.hidesStamp
            loadPreview()
        } catch {
            errorMessage = error.localizedDescription
            isUnavailable = true
        }
    }

    // MARK: Block

    func setShowsDate(_ isOn: Bool) { block.showsDate = isOn }
    func setShowsTime(_ isOn: Bool) { block.showsTime = isOn }

    func setShowsPlace(_ isOn: Bool) {
        if isOn, block.placeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            block.placeName = capturedPlaceName ?? ""
        }
        block.showsPlace = isOn && canShowPlace
    }

    func setPlaceName(_ name: String) {
        block.placeName = String(name.prefix(VlogStampBlock.maxCaptionLength))
    }

    func setCaption(_ text: String) {
        block.caption = String(text.prefix(VlogStampBlock.maxCaptionLength))
    }

    func setStyle(_ style: VlogTextStylePreset) { block.style = style }

    func setCaptionPlacement(_ placement: VlogCaptionPlacement) { block.captionPlacement = placement }

    func setFadesOut(_ isOn: Bool) { block.fadesOut = isOn }

    /// 日付・時刻・場所のどれかが出ているか（ひとことの上下を選ぶ意味がある時）。
    var showsStampLines: Bool {
        block.showsDate || block.showsTime || block.hasPlace
    }

    func setAnchor(_ anchor: VlogNormalizedPoint) { block.anchor = anchor.normalized }

    /// 9か所のどこかに置く。手で動かした位置は上書きされる。
    func setPosition(_ position: VlogBlockPosition) { block.anchor = position.anchor }

    /// 今の位置が9か所のどれか（手で動かした後は nil）。
    var currentPosition: VlogBlockPosition? { VlogBlockPosition.matching(block.anchor) }

    func setScale(_ scale: Double) {
        let range = VlogStampBlock.scaleRange
        block.scale = min(max(scale, range.lowerBound), range.upperBound)
    }

    /// 共通設定の状態に戻す（ひとことは残す）。
    func resetToCommonSettings() {
        guard let stampSettings else { return }
        let caption = block.caption
        var seeded = VlogStampLayerSeeder.block(settings: stampSettings, placeName: capturedPlaceName)
        seeded.caption = caption
        block = seeded
    }

    /// 画面上の位置がかたまりの上か。
    func isOnBlock(_ location: CGPoint, containerSize: CGSize) -> Bool {
        guard let frame = blockFrame(containerSize: containerSize) else { return false }
        return frame.insetBy(dx: -16, dy: -16).contains(location)
    }

    /// 指定した位置に置いた時に、実際に見える中心（端では余白の内側へ寄る）を返す。
    /// 保存する位置を見た目と一致させ、端に寄せた後でもすぐ動かせるようにする。
    func visibleAnchor(proposed: VlogNormalizedPoint, containerSize: CGSize) -> VlogNormalizedPoint {
        let normalized = proposed.normalized
        let contentFrame = DateStampStyle.aspectFitFrame(
            contentAspectRatio: videoAspectRatio,
            in: containerSize
        )
        guard contentFrame.width > 0, contentFrame.height > 0,
              let resolved = resolvedTextOverlays.first else { return normalized }
        let metrics = VlogTextMetrics.measure(overlay: resolved, contentFrame: contentFrame)
        let center = VlogTextLayout.center(
            anchor: normalized,
            contentFrame: contentFrame,
            boxSize: metrics.boxSize
        )
        return VlogNormalizedPoint(
            x: Double((center.x - contentFrame.minX) / contentFrame.width),
            y: Double((center.y - contentFrame.minY) / contentFrame.height)
        ).normalized
    }

    private func blockFrame(containerSize: CGSize) -> CGRect? {
        guard let resolved = resolvedTextOverlays.first else { return nil }
        let contentFrame = DateStampStyle.aspectFitFrame(
            contentAspectRatio: videoAspectRatio,
            in: containerSize
        )
        let metrics = VlogTextMetrics.measure(overlay: resolved, contentFrame: contentFrame)
        let center = VlogTextLayout.center(
            anchor: resolved.anchor,
            contentFrame: contentFrame,
            boxSize: metrics.boxSize
        )
        return CGRect(
            x: center.x - metrics.boxSize.width / 2,
            y: center.y - metrics.boxSize.height / 2,
            width: metrics.boxSize.width,
            height: metrics.boxSize.height
        )
    }

    // MARK: Preview playback

    func togglePreviewPlayback() {
        guard isPreviewReady else {
            if previewLoadFailed { loadPreview() }
            return
        }
        if isPreviewPlaying {
            previewPlayer.pause()
            isPreviewPlaying = false
        } else {
            if previewTime >= clipDuration - 0.05 { seekPreview(to: 0) }
            previewPlayer.play()
            isPreviewPlaying = true
        }
    }

    func seekPreview(to seconds: TimeInterval) {
        let target = min(max(seconds, 0), clipDuration)
        previewTime = target
        previewPlayer.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    func retryPreview() { loadPreview() }

    func stopPreview() {
        previewLoadGeneration += 1
        service.cancelPreviewRequest(previewRequestID)
        previewRequestID = nil
        previewPlayer.pause()
        previewPlayer.replaceCurrentItem(with: nil)
        isPreviewPlaying = false
        isPreviewReady = false
        isPreviewLoading = false
        if let previewTimeObserver {
            previewPlayer.removeTimeObserver(previewTimeObserver)
            self.previewTimeObserver = nil
        }
        if let previewEndObserver {
            NotificationCenter.default.removeObserver(previewEndObserver)
            self.previewEndObserver = nil
        }
    }

    private func loadPreview() {
        previewLoadGeneration += 1
        let generation = previewLoadGeneration
        service.cancelPreviewRequest(previewRequestID)
        previewRequestID = nil
        previewPlayer.pause()
        previewPlayer.replaceCurrentItem(with: nil)
        isPreviewPlaying = false
        isPreviewReady = false
        isPreviewLoading = true
        previewLoadFailed = false

        do {
            let requestID = try service.requestPreviewPlayerItem(
                assetLocalIdentifier: assetLocalIdentifier
            ) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self, self.previewLoadGeneration == generation else { return }
                    self.previewRequestID = nil
                    self.isPreviewLoading = false
                    switch result {
                    case .success(let item):
                        self.preparePreview(item)
                    case .failure:
                        self.previewLoadFailed = true
                    }
                }
            }
            previewRequestID = requestID == PHInvalidImageRequestID ? nil : requestID
        } catch {
            isPreviewLoading = false
            previewLoadFailed = true
        }
    }

    private func preparePreview(_ item: AVPlayerItem) {
        previewPlayer.replaceCurrentItem(with: item)
        previewPlayer.actionAtItemEnd = .pause
        isPreviewReady = true
        installPreviewObservers(for: item)
        seekPreview(to: 0)
    }

    private func installPreviewObservers(for item: AVPlayerItem) {
        if let previewTimeObserver {
            previewPlayer.removeTimeObserver(previewTimeObserver)
        }
        if let previewEndObserver {
            NotificationCenter.default.removeObserver(previewEndObserver)
        }
        previewTimeObserver = previewPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.05, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.previewTime = min(
                    max(time.seconds.isFinite ? time.seconds : 0, 0),
                    self.clipDuration
                )
            }
        }
        previewEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isPreviewPlaying = false
            }
        }
    }

    // MARK: Save

    func save() async -> Bool {
        guard baseContext != nil, !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            try await service.saveClipEdit(currentEdit, clipDuration: clipDuration)
            // 保存したクリップでは、日付もこの編集内容で描く。共通スタンプは二重にならないよう隠す。
            if !hidesCommonStamp {
                try await service.apply(
                    assetLocalIdentifier: assetLocalIdentifier,
                    visibilityOverride: VideoStampVisibilityOverride(hidesStamp: true, hiddenElements: [])
                )
                hidesCommonStamp = true
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

// MARK: - View

/// 動画を主役にした編集画面。動画を画面いっぱいに出し、文字のかたまりは動画の上で直接さわる。
///
/// - 下のボタン：日付・時刻・場所は出す／出さない、ひとことは入力、見た目はスタイルのパネル。
/// - かたまりをタップで入力、ドラッグで移動、2本指で大きさ。
/// - 入力中は動画を暗くし、キーボードの上で見たまま打つ。
struct VideoStampEditorView: View {
    @StateObject private var viewModel: VideoStampEditorViewModel
    let onSaved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedField: Field?
    @State private var dragOrigin: VlogNormalizedPoint?
    @State private var pinchOrigin: Double?
    @State private var isTyping = false
    @State private var isStylePanelOpen = false
    @State private var showsHint = true

    private enum Field: Hashable {
        case caption
        case place
    }

    init(viewModel: VideoStampEditorViewModel, onSaved: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onSaved = onSaved
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if viewModel.isLoading {
                ProgressView()
                    .tint(.white)
                    .accessibilityIdentifier("stampEditor.loading")
            } else if viewModel.isUnavailable {
                unavailableView
            } else {
                canvas
                chrome
                if isTyping {
                    typingOverlay
                        .transition(.opacity)
                }
            }

            if viewModel.isSaving {
                ProgressView(L10n.text("保存しています"))
                    .tint(.white)
                    .foregroundStyle(.white)
                    .padding(20)
                    .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
            }
        }
        .animation(motion, value: isTyping)
        .animation(motion, value: isStylePanelOpen)
        .preferredColorScheme(.dark)
        .presentationBackground(.black)
        .task { await viewModel.load() }
        .task {
            // 操作の案内は最初の数秒だけ出す。
            try? await Task.sleep(for: .seconds(4))
            withAnimation(.easeOut(duration: 0.3)) { showsHint = false }
        }
        .onDisappear { viewModel.stopPreview() }
        .onChange(of: focusedField) { _, field in
            // キーボードを閉じたら入力を終える（下へのスワイプやキーボードの閉じるボタン）。
            if field == nil, isTyping {
                isTyping = false
            }
        }
        .alert(L10n.text("編集内容を保存できません"), isPresented: errorBinding) {
            Button(L10n.text("閉じる"), role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? L10n.text("不明なエラーです。"))
        }
    }

    private var motion: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.2)
    }

    // MARK: Canvas

    /// 動画と文字のかたまり。キーボードが出ても大きさを変えない（かたまりの位置がずれないように）。
    private var canvas: some View {
        GeometryReader { proxy in
            ZStack {
                VideoEditorPlayerSurface(player: viewModel.previewPlayer)
                    .allowsHitTesting(false)

                VlogTextOverlayCanvas(
                    overlays: isTyping ? [] : viewModel.resolvedTextOverlays,
                    playbackTime: viewModel.previewTime,
                    videoAspectRatio: viewModel.videoAspectRatio
                )
                .allowsHitTesting(false)

                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { location in
                        handleCanvasTap(at: location, containerSize: proxy.size)
                    }
                    .gesture(dragGesture(containerSize: proxy.size).simultaneously(with: pinchGesture))
                    .accessibilityHidden(true)
            }
        }
        .ignoresSafeArea()
        .overlay {
            Color.black
                .opacity(isTyping ? 0.45 : 0)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .accessibilityIdentifier("stampEditor.preview")
    }

    private func handleCanvasTap(at location: CGPoint, containerSize: CGSize) {
        if isStylePanelOpen {
            isStylePanelOpen = false
            return
        }
        if viewModel.isOnBlock(location, containerSize: containerSize) {
            startTyping(.caption)
        }
    }

    /// かたまりの上から始めたドラッグで動かす。位置は「実際に見えている位置」を基準にする。
    private func dragGesture(containerSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard !isTyping else { return }
                if dragOrigin == nil {
                    guard viewModel.isOnBlock(value.startLocation, containerSize: containerSize) else { return }
                    dragOrigin = viewModel.visibleAnchor(
                        proposed: viewModel.block.anchor,
                        containerSize: containerSize
                    )
                    showsHint = false
                }
                guard let origin = dragOrigin else { return }
                let frame = DateStampStyle.aspectFitFrame(
                    contentAspectRatio: viewModel.videoAspectRatio,
                    in: containerSize
                )
                guard frame.width > 0, frame.height > 0 else { return }
                viewModel.setAnchor(viewModel.visibleAnchor(
                    proposed: VlogNormalizedPoint(
                        x: origin.x + Double(value.translation.width / frame.width),
                        y: origin.y + Double(value.translation.height / frame.height)
                    ),
                    containerSize: containerSize
                ))
            }
            .onEnded { _ in dragOrigin = nil }
    }

    private var pinchGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                guard !isTyping else { return }
                let origin = pinchOrigin ?? viewModel.block.scale
                if pinchOrigin == nil { pinchOrigin = origin }
                viewModel.setScale(origin * Double(value.magnification))
                showsHint = false
            }
            .onEnded { _ in pinchOrigin = nil }
    }

    // MARK: Chrome

    private var chrome: some View {
        VStack(spacing: 0) {
            topBar
            if showsHint && !isTyping && !isStylePanelOpen {
                Text(L10n.text("文字をタップで入力 · ドラッグで移動 · 2本指で大きさ"))
                    .rollText(11, maxScale: 1.3)
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.4), radius: 3)
                    .padding(.top, 8)
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
            Spacer(minLength: 0)
            if !isTyping {
                bottomPanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(alignment: .top) {
            LinearGradient(colors: [.black.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 140)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .background(alignment: .bottom) {
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                .frame(height: 260)
                .ignoresSafeArea()
                .opacity(isTyping ? 0 : 1)
                .allowsHitTesting(false)
        }
    }

    private var topBar: some View {
        HStack {
            Button(L10n.text("キャンセル")) { dismiss() }
                .rollText(15)
                .foregroundStyle(.white)
                .frame(minHeight: 44)
                .accessibilityIdentifier("stampEditor.cancel")

            Spacer()

            if isTyping {
                capsuleButton(L10n.text("完了"), identifier: "stampEditor.done") {
                    stopTyping()
                }
            } else {
                capsuleButton(L10n.text("保存"), identifier: "stampEditor.save") {
                    save()
                }
                .disabled(viewModel.isLoading || viewModel.isSaving)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func capsuleButton(_ title: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .rollText(15, .bold)
                .foregroundStyle(RollTheme.ink)
                .padding(.horizontal, 18)
                .frame(minHeight: 36)
                .background(Color.white.opacity(0.92), in: Capsule())
        }
        .buttonStyle(SquishableButtonStyle())
        .accessibilityIdentifier(identifier)
    }

    private var bottomPanel: some View {
        VStack(spacing: 14) {
            if isStylePanelOpen {
                stylePanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            previewControls
            toolRow
        }
        .padding(.bottom, 12)
    }

    // MARK: Preview controls

    @ViewBuilder
    private var previewControls: some View {
        if viewModel.isPreviewLoading {
            ProgressView().tint(.white).frame(height: 28)
        } else if viewModel.previewLoadFailed {
            Button(action: viewModel.retryPreview) {
                Label(L10n.text("再試行"), systemImage: "arrow.clockwise")
                    .rollText(13, .semibold)
                    .foregroundStyle(RollTheme.ink)
                    .padding(.horizontal, 16)
                    .frame(minHeight: 36)
                    .background(Color.white, in: Capsule())
            }
            .buttonStyle(SquishableButtonStyle())
        } else {
            HStack(spacing: 12) {
                Button(action: viewModel.togglePreviewPlayback) {
                    Image(systemName: viewModel.isPreviewPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(viewModel.isPreviewPlaying ? L10n.text("一時停止") : L10n.text("再生"))

                EditorScrubber(
                    time: viewModel.previewTime,
                    duration: viewModel.clipDuration,
                    onSeek: viewModel.seekPreview(to:)
                )
                .frame(height: 28)

                Text(verbatim: String(format: "%.1f / %.1f", viewModel.previewTime, viewModel.clipDuration))
                    .rollMono(10, maxScale: 1.2)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: Tools

    private var toolRow: some View {
        HStack(alignment: .top, spacing: 0) {
            toolButton(
                label: L10n.text("日付"),
                glyph: .text(viewModel.dateText.isEmpty ? "DATE" : shortGlyph(viewModel.dateText)),
                isOn: viewModel.block.showsDate,
                identifier: "stampEditor.toggle.date"
            ) { viewModel.setShowsDate(!viewModel.block.showsDate) }

            toolButton(
                label: L10n.text("時刻"),
                glyph: .text(viewModel.timeText.isEmpty ? "TIME" : shortGlyph(viewModel.timeText)),
                isOn: viewModel.block.showsTime,
                identifier: "stampEditor.toggle.time"
            ) { viewModel.setShowsTime(!viewModel.block.showsTime) }

            toolButton(
                label: L10n.text("場所"),
                glyph: .symbol("mappin.and.ellipse"),
                isOn: viewModel.block.showsPlace,
                isEnabled: viewModel.canShowPlace,
                identifier: "stampEditor.toggle.place"
            ) { viewModel.setShowsPlace(!viewModel.block.showsPlace) }

            toolButton(
                label: L10n.text("ひとこと"),
                glyph: .text("Aa"),
                isOn: viewModel.block.hasCaption,
                identifier: "stampEditor.caption"
            ) { startTyping(.caption) }

            toolButton(
                label: L10n.text("見た目"),
                glyph: .symbol("circle.lefthalf.filled"),
                isOn: isStylePanelOpen,
                identifier: "stampEditor.style"
            ) { isStylePanelOpen.toggle() }
        }
        .padding(.horizontal, 8)
    }

    private enum ToolGlyph {
        case text(String)
        case symbol(String)
    }

    /// 丸に収まる短い表示にする。日付は年を省き（"2026.10.06" / "10.06.2026" → "10.06"）、
    /// 時刻は午前・午後を省く（"6:39 PM" → "6:39"）。
    private func shortGlyph(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.contains(":") {
            return trimmed.components(separatedBy: " ").first ?? trimmed
        }
        let parts: [String] = trimmed
            .components(separatedBy: ".")
            .filter { $0.count != 4 }
        return parts.count >= 2 ? parts.joined(separator: ".") : trimmed
    }

    private func toolButton(
        label: String,
        glyph: ToolGlyph,
        isOn: Bool,
        isEnabled: Bool = true,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Group {
                    switch glyph {
                    case .text(let text):
                        Text(verbatim: text)
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .padding(.horizontal, 4)
                    case .symbol(let name):
                        Image(systemName: name)
                            .font(.system(size: 16, weight: .medium))
                    }
                }
                .foregroundStyle(isOn ? RollTheme.ink : .white)
                .frame(width: 46, height: 46)
                .background {
                    if isOn {
                        Circle().fill(Color.white.opacity(0.92))
                    } else {
                        Circle()
                            .fill(Color.black.opacity(0.4))
                            .overlay { Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1) }
                    }
                }

                Text(label)
                    .rollText(11, maxScale: 1.3)
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(SquishableButtonStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? L10n.text("表示中") : L10n.text("非表示"))
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    // MARK: Style panel

    private var stylePanel: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                ForEach(VlogTextStylePreset.allCases, id: \.self) { style in
                    styleTile(style, isSelected: viewModel.block.style == style)
                }
            }

            HStack(alignment: .center, spacing: 14) {
                EditorPositionGrid(
                    selection: viewModel.currentPosition,
                    onSelect: viewModel.setPosition
                )

                Toggle(isOn: Binding(get: { viewModel.block.fadesOut }, set: viewModel.setFadesOut)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.text("2秒後にフェードアウト"))
                            .rollText(13, .medium)
                        Text(L10n.text("ひとことも一緒に消えます。2.5秒以下の動画では最後まで表示します。"))
                            .rollText(10)
                            .opacity(0.65)
                    }
                    .foregroundStyle(.white)
                }
                .tint(.white)
                .accessibilityIdentifier("stampEditor.fade")
            }

            Button(action: viewModel.resetToCommonSettings) {
                Text(L10n.text("全体設定に戻す"))
                    .rollText(12)
                    .foregroundStyle(.white.opacity(0.75))
                    .underline()
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("stampEditor.reset")
        }
        .padding(12)
        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 16)
    }

    private func styleTile(_ style: VlogTextStylePreset, isSelected: Bool) -> some View {
        let spec = style.spec
        return Button {
            viewModel.setStyle(style)
        } label: {
            Text("Aa")
                .font(Font(VlogTextFont.uiFont(spec: spec, size: 17) as CTFont))
                .foregroundStyle(Color(spec.foreground))
                .shadow(
                    color: spec.outline.map { Color($0).opacity(spec.outlineOpacity) } ?? .clear,
                    radius: spec.outline == nil ? 0 : 1.5
                )
                .padding(.horizontal, 17 * CGFloat(spec.horizontalPaddingRatio))
                .padding(.vertical, 17 * CGFloat(spec.verticalPaddingRatio))
                .background {
                    if let background = spec.background {
                        RoundedRectangle(cornerRadius: 17 * CGFloat(spec.cornerRadiusRatio), style: .continuous)
                            .fill(Color(background))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isSelected ? Color.white : .clear, lineWidth: 2)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(SquishableButtonStyle())
        .accessibilityLabel(style.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: Typing

    /// 入力中の重ね表示。キーボードの上の空いた所に、かたまりを見たまま出して直接打つ。
    private var typingOverlay: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 72)

            VStack(spacing: 4) {
                if viewModel.block.captionPlacement == .above {
                    captionField
                }
                if viewModel.block.showsDate, !viewModel.dateText.isEmpty {
                    stampLine(viewModel.dateText)
                }
                if viewModel.block.showsTime, !viewModel.timeText.isEmpty {
                    stampLine(viewModel.timeText)
                }
                if viewModel.block.showsPlace {
                    TextField(L10n.text("場所の名前"), text: Binding(
                        get: { viewModel.block.placeName },
                        set: viewModel.setPlaceName
                    ))
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .focused($focusedField, equals: .place)
                    .submitLabel(.done)
                    .onSubmit { stopTyping() }
                    .accessibilityIdentifier("stampEditor.placeField")
                }
                if viewModel.block.captionPlacement == .below {
                    captionField
                }
            }
            .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
            .padding(.horizontal, 24)

            Spacer(minLength: 24)

            if viewModel.showsStampLines {
                HStack(spacing: 8) {
                    ForEach(VlogCaptionPlacement.allCases, id: \.self) { placement in
                        placementChip(placement)
                    }
                }
                .padding(.bottom, 12)
                .accessibilityIdentifier("stampEditor.captionPlacement")
            }
        }
    }

    private var captionField: some View {
        TextField(
            L10n.text("ひとこと（例：東京に到着！！）"),
            text: Binding(get: { viewModel.block.caption }, set: viewModel.setCaption),
            axis: .vertical
        )
        .lineLimit(1...3)
        .font(.system(size: 22, weight: .bold))
        .multilineTextAlignment(.center)
        .foregroundStyle(.white)
        .tint(.white)
        .focused($focusedField, equals: .caption)
        .accessibilityIdentifier("stampEditor.textField")
    }

    private func stampLine(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 20, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white)
            .onTapGesture { focusedField = .caption }
    }

    private func placementChip(_ placement: VlogCaptionPlacement) -> some View {
        let isSelected = viewModel.block.captionPlacement == placement
        return Button {
            viewModel.setCaptionPlacement(placement)
        } label: {
            Text(placement.title)
                .rollText(13, isSelected ? .bold : .regular)
                .foregroundStyle(isSelected ? RollTheme.ink : .white)
                .padding(.horizontal, 14)
                .frame(minHeight: 32)
                .background(isSelected ? Color.white.opacity(0.92) : Color.white.opacity(0.12), in: Capsule())
        }
        .buttonStyle(SquishableButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func startTyping(_ field: Field) {
        isStylePanelOpen = false
        showsHint = false
        if viewModel.isPreviewPlaying { viewModel.togglePreviewPlayback() }
        isTyping = true
        // 表示が切り替わってからフォーカスする（重ね表示のTextFieldが出来てから）。
        Task { @MainActor in
            await Task.yield()
            focusedField = field
        }
    }

    private func stopTyping() {
        focusedField = nil
        isTyping = false
    }

    private func save() {
        stopTyping()
        Task {
            if await viewModel.save() {
                onSaved()
                dismiss()
            }
        }
    }

    // MARK: States

    private var unavailableView: some View {
        VStack(spacing: 16) {
            ContentUnavailableView(
                L10n.text("この動画は編集できません"),
                systemImage: "exclamationmark.triangle",
                description: Text(viewModel.errorMessage ?? L10n.text("原本がありません。"))
            )
            Button(L10n.text("閉じる")) { dismiss() }
                .foregroundStyle(.white)
                .accessibilityIdentifier("stampEditor.cancel")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { viewModel.errorMessage != nil && !viewModel.isLoading && !viewModel.isUnavailable },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )
    }
}

/// かたまりの位置を9か所から選ぶ。手で動かした後はどれも選ばれていない状態になる。
private struct EditorPositionGrid: View {
    let selection: VlogBlockPosition?
    let onSelect: (VlogBlockPosition) -> Void

    private let columns = Array(repeating: GridItem(.fixed(26), spacing: 4), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.text("位置"))
                .rollText(11)
                .foregroundStyle(.white.opacity(0.75))
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(VlogBlockPosition.allCases, id: \.self) { position in
                    let isSelected = selection == position
                    Button {
                        onSelect(position)
                    } label: {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(isSelected ? Color.white.opacity(0.92) : Color.white.opacity(0.14))
                            .frame(width: 26, height: 26)
                            .overlay {
                                Circle()
                                    .fill(isSelected ? RollTheme.ink : Color.white.opacity(0.6))
                                    .frame(width: 5, height: 5)
                            }
                            // 小さいマスでも押しやすいよう、当たり判定は少し広げる。
                            .contentShape(Rectangle().inset(by: -2))
                    }
                    .buttonStyle(SquishableButtonStyle())
                    .accessibilityLabel(position.accessibilityTitle)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityIdentifier("stampEditor.position.\(position.rawValue)")
                }
            }
            .frame(width: 86)
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// 再生位置の細いバー。タップやドラッグで位置を変える。
private struct EditorScrubber: View {
    let time: TimeInterval
    let duration: TimeInterval
    let onSeek: (TimeInterval) -> Void

    var body: some View {
        GeometryReader { proxy in
            let fraction = duration > 0 ? min(max(time / duration, 0), 1) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.3)).frame(height: 3)
                Capsule().fill(Color.white).frame(width: proxy.size.width * fraction, height: 3)
                Circle()
                    .fill(Color.white)
                    .frame(width: 10, height: 10)
                    .offset(x: proxy.size.width * fraction - 5)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard proxy.size.width > 0 else { return }
                        let ratio = min(max(value.location.x / proxy.size.width, 0), 1)
                        onSeek(duration * Double(ratio))
                    }
            )
        }
        .accessibilityElement()
        .accessibilityLabel(L10n.text("再生位置"))
        .accessibilityValue(String(format: "%.1f", time))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onSeek(min(time + 0.5, duration))
            case .decrement: onSeek(max(time - 0.5, 0))
            @unknown default: break
            }
        }
    }
}

enum VlogEditorGeometry {
    static func normalizedPoint(
        location: CGPoint,
        containerSize: CGSize,
        videoAspectRatio: CGFloat
    ) -> VlogNormalizedPoint {
        let frame = DateStampStyle.aspectFitFrame(
            contentAspectRatio: videoAspectRatio,
            in: containerSize
        )
        guard frame.width > 0, frame.height > 0 else { return .center }
        return VlogNormalizedPoint(
            x: Double((location.x - frame.minX) / frame.width),
            y: Double((location.y - frame.minY) / frame.height)
        ).normalized
    }
}

private struct VideoEditorPlayerSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> VideoEditorPlayerView {
        let view = VideoEditorPlayerView()
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: VideoEditorPlayerView, context: Context) {
        if uiView.playerLayer.player !== player { uiView.playerLayer.player = player }
    }
}

private final class VideoEditorPlayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

