import SwiftUI

private struct RecoveryShareItem: Identifiable {
    let url: URL

    var id: String { url.path }
}

struct ContentView: View {
    @ObservedObject var captureViewModel: CaptureFeatureViewModel
    @ObservedObject var libraryViewModel: LibraryFeatureViewModel
    @ObservedObject var settingsViewModel: SettingsViewModel
    let makeLibraryClipBrowser: (LibraryClipPlaybackContext) -> LibraryClipBrowserViewModel

    @State private var showsIntro = false
    @State private var showsSettings = false
    @State private var presentedPlaybackRoute: PlaybackRoute?
    @State private var isPreparingPlayback = false
    @State private var recoveryShareItem: RecoveryShareItem?
    /// 記録シートの高さ。開くときは毎回「半分」から。
    @State private var librarySheetDetent: PresentationDetent = .libraryPeek
    /// 記録シートを全画面にしたとき、少し待ってからカメラを止める（行き来でセッションを何度も止めないため）。
    @State private var pendingCaptureSuspend: Task<Void, Never>?
    /// 撮影画面での一言（はじめての撮影の前後に1回ずつ）。
    @State private var captureCoach: CaptureCoachMark?
    @State private var showsFirstClipCoachAfterSave = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        CaptureScreenView(
            state: captureViewModel.screenState,
            latestThumbnail: libraryViewModel.latestThumbnail,
            todayTimeline: libraryViewModel.todayTimeline,
            coachMark: captureCoach,
            actions: captureActions
        ) {
            CameraPreviewView(cameraService: captureViewModel.cameraService)
        }
        .preferredColorScheme(.dark)
        .overlay {
            // はじめての案内。撮影画面の上に重ね、終わるまでカメラは動かさない。
            if showsIntro {
                OnboardingView(settingsViewModel: settingsViewModel, onFinish: dismissIntro)
                    .transition(.opacity)
            }
        }
        .onChange(of: captureViewModel.screenState.isRecording) { _, isRecording in
            updateCaptureCoach(isRecording: isRecording)
        }
        .overlay {
            if isPlaybackTransitionActive {
                Color.black
                    .ignoresSafeArea()
                    .allowsHitTesting(true)
                    .transition(.opacity)
            }
        }
        .task {
            prepareFeatures()
        }
        .onReceive(libraryViewModel.$playbackRoute, perform: handlePlaybackRoute)
        .onChange(of: libraryViewModel.isPresentingLibrary) { _, isPresented in
            handleLibraryPresentationChanged(isPresented)
            synchronizeCaptureMode()
        }
        .onChange(of: librarySheetDetent) { _, _ in
            synchronizeCaptureMode()
        }
        .onChange(of: showsSettings) { _, _ in
            synchronizeCaptureMode()
        }
        .onChange(of: showsIntro) { _, _ in
            synchronizeCaptureMode()
        }
        .onChange(of: recoveryShareItem?.id) { _, _ in
            synchronizeCaptureMode()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                applyCaptureOrientation()
                captureViewModel.refreshPermissionsIfNeeded()
            }
            synchronizeCaptureMode()
        }
        .sheet(isPresented: $libraryViewModel.isPresentingLibrary) {
            VlogishLibrarySheetView(
                viewModel: libraryViewModel,
                onExpand: { librarySheetDetent = .large }
            )
                // 再生は記録シートの上に重ねる。閉じると、開いていた画面・高さ・スクロール位置のまま記録に戻る。
                .sheet(item: $presentedPlaybackRoute, onDismiss: handlePlaybackDismissed) { route in
                    PlaybackFeatureView(
                        route: route,
                        makeLibraryClipBrowser: makeLibraryClipBrowser
                    )
                    .preferredColorScheme(.dark)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
                    .presentationCornerRadius(30)
                }
                .presentationDetents([.libraryPeek, .large], selection: $librarySheetDetent)
                .presentationContentInteraction(.resizes)
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(30)
        }
        .sheet(isPresented: $showsSettings) {
            SettingsFeatureView(viewModel: settingsViewModel)
        }
        .sheet(item: $recoveryShareItem, onDismiss: synchronizeCaptureMode) { item in
            ShareSheet(activityItems: [item.url])
        }
        .alert(
            captureViewModel.permissionTitle,
            isPresented: permissionAlertBinding
        ) {
            Button("設定を開く", action: captureViewModel.openSettingsApp)
            Button("閉じる", role: .cancel) {}
        } message: {
            Text(captureViewModel.permissionMessage)
        }
        .alert(
            captureViewModel.saveErrorTitle,
            isPresented: saveFailureBinding
        ) {
            if captureViewModel.saveErrorRequiresSettings {
                Button("設定を開く", action: captureViewModel.openSettingsApp)
            }
            if captureViewModel.hasRecoverableCapture {
                Button("動画を救出", action: presentRecoverableCapture)
                Button(
                    "原本を削除",
                    role: .destructive,
                    action: captureViewModel.discardRecoverableCapture
                )
                Button("あとで", role: .cancel) {}
            } else {
                Button("撮り直す", role: .cancel) {}
            }
        } message: {
            Text(captureViewModel.saveErrorMessage)
        }
    }

    private var captureActions: CaptureScreenActions {
        CaptureScreenActions(
            onToggleTorch: captureViewModel.toggleTorch,
            onToggleGrid: captureViewModel.toggleGrid,
            onOpenSystemSettings: captureViewModel.openSettingsApp,
            onOpenSettings: { showsSettings = true },
            onSelectDuration: captureViewModel.setDuration,
            onOpenLibrary: libraryViewModel.openLibrary,
            onShutter: captureViewModel.handleShutterTap,
            onSwitchCamera: captureViewModel.switchCamera,
            onFocus: captureViewModel.focus,
            onLockFocusAndExposure: captureViewModel.lockFocusAndExposure,
            onExposureChanged: captureViewModel.applyExposureChanged,
            onExposureEnded: captureViewModel.applyExposureEnded,
            onZoomChanged: captureViewModel.applyPinchChanged,
            onZoomEnded: captureViewModel.applyPinchEnded,
            onSelectZoom: captureViewModel.selectZoomFactor
        )
    }

    private var isPlaybackTransitionActive: Bool {
        isPreparingPlayback
            || presentedPlaybackRoute != nil
            || libraryViewModel.playbackRoute != nil
    }

    private var permissionAlertBinding: Binding<Bool> {
        Binding(
            get: { captureViewModel.isPermissionAlertPresented },
            set: { isPresented in
                if !isPresented {
                    captureViewModel.dismissPermissionAlert()
                }
            }
        )
    }

    private var saveFailureBinding: Binding<Bool> {
        Binding(
            get: { captureViewModel.isSaveFailurePresented },
            set: { isPresented in
                if !isPresented {
                    captureViewModel.dismissSaveFailure()
                }
            }
        )
    }

    private func prepareFeatures() {
        applyCaptureOrientation()
        libraryViewModel.loadIfNeeded()
        showsIntro = !settingsViewModel.hasSeenCaptureIntroCard
        if !showsIntro {
            captureViewModel.prepare()
            if !settingsViewModel.hasSeenCaptureCoach {
                captureCoach = .shutter
            }
        }
    }

    private func dismissIntro() {
        settingsViewModel.markCaptureIntroSeen()
        captureViewModel.prepare()
        withAnimation(.easeOut(duration: 0.25)) {
            showsIntro = false
        }
        if !settingsViewModel.hasSeenCaptureCoach {
            captureCoach = .shutter
        }
    }

    /// 撮り始めたらシャッターの案内を消し、撮り終えたら「今日の1本目」を数秒だけ出す。
    private func updateCaptureCoach(isRecording: Bool) {
        if isRecording {
            guard captureCoach == .shutter else { return }
            captureCoach = nil
            showsFirstClipCoachAfterSave = true
            settingsViewModel.markCaptureCoachSeen()
            return
        }
        guard showsFirstClipCoachAfterSave else { return }
        showsFirstClipCoachAfterSave = false
        captureCoach = .firstClip
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            if captureCoach == .firstClip {
                captureCoach = nil
            }
        }
    }

    /// 再生はいつも記録シートから始まる。シートが閉じていたら（閉じる途中など）再生しない。
    private func handlePlaybackRoute(_ route: PlaybackRoute?) {
        guard let route else { return }
        guard libraryViewModel.isPresentingLibrary else {
            libraryViewModel.clearPlaybackRoute()
            return
        }
        presentPlayback(for: route)
    }

    private func handleLibraryPresentationChanged(_ isPresented: Bool) {
        // 記録を開いたら、1本目の後の案内はもう要らない。
        if isPresented, captureCoach == .firstClip {
            captureCoach = nil
        }
        if !isPresented {
            // 次に開くときは、また半分の高さから。
            librarySheetDetent = .libraryPeek
        }
    }

    private func handlePlaybackDismissed() {
        libraryViewModel.clearPlaybackRoute()
        presentedPlaybackRoute = nil
        synchronizeCaptureMode()
    }

    private func presentPlayback(for route: PlaybackRoute) {
        guard presentedPlaybackRoute == nil, !isPreparingPlayback else {
            // 二重タップなど。進行中の再生を優先し、後から来た要求は捨てる。
            if presentedPlaybackRoute?.id != route.id {
                libraryViewModel.clearPlaybackRoute()
            }
            return
        }

        isPreparingPlayback = true
        Task {
            // 音声の切り替えのため、先にカメラを止めてから再生を出す。
            await captureViewModel.enterPlaybackMode()
            await MainActor.run {
                isPreparingPlayback = false
                guard libraryViewModel.isPresentingLibrary else {
                    // 準備中に記録シートが閉じられた。再生はせず撮影へ戻す。
                    libraryViewModel.clearPlaybackRoute()
                    synchronizeCaptureMode()
                    return
                }
                presentedPlaybackRoute = route
            }
        }
    }

    private func synchronizeCaptureMode() {
        pendingCaptureSuspend?.cancel()
        pendingCaptureSuspend = nil

        let canRun = scenePhase == .active
            && !showsIntro
            && !showsSettings
            && presentedPlaybackRoute == nil
            && libraryViewModel.playbackRoute == nil
            && !isPreparingPlayback
            && recoveryShareItem == nil
        // 記録シートが半分のときは、後ろのカメラを動かしたままにする（すぐ撮れるように）。
        let isLibraryCoveringCamera = libraryViewModel.isPresentingLibrary
            && librarySheetDetent != .libraryPeek

        if canRun && !isLibraryCoveringCamera {
            captureViewModel.prepare()
            captureViewModel.resumeCaptureMode()
        } else if canRun {
            // 全画面にしただけなら、すぐ半分に戻すこともあるので少し待ってから止める。
            pendingCaptureSuspend = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled else { return }
                await captureViewModel.suspendCaptureMode()
            }
        } else {
            Task {
                await captureViewModel.suspendCaptureMode()
            }
        }
    }

    private func presentRecoverableCapture() {
        guard let url = captureViewModel.recoverableCaptureURL else { return }
        recoveryShareItem = RecoveryShareItem(url: url)
    }

    /// 撮影は縦固定。復帰時などにプレビューの回転だけ合わせ直す。
    private func applyCaptureOrientation() {
        captureViewModel.refreshPreviewOrientation()
    }
}
