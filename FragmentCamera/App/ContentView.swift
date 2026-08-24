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
    @State private var deferredPlaybackRoute: PlaybackRoute?
    @State private var isPreparingPlayback = false
    @State private var recoveryShareItem: RecoveryShareItem?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        CaptureScreenView(
            state: captureViewModel.screenState,
            latestThumbnail: libraryViewModel.latestThumbnail,
            todayClipCount: libraryViewModel.clipCountToday,
            showsIntro: showsIntro,
            actions: captureActions
        ) {
            CameraPreviewView(cameraService: captureViewModel.cameraService)
        }
        .preferredColorScheme(.dark)
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
        .onChange(of: showsSettings) { _, _ in
            synchronizeCaptureMode()
        }
        .onChange(of: settingsViewModel.captureOrientationModeKey) { _, _ in
            applyCaptureOrientation()
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
            DaylogLibrarySheetView(viewModel: libraryViewModel)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(30)
        }
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
            onSelectZoom: captureViewModel.selectZoomFactor,
            onDismissIntro: dismissIntro
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
        }
    }

    private func dismissIntro() {
        settingsViewModel.markCaptureIntroSeen()
        captureViewModel.prepare()
        withAnimation(.easeOut(duration: 0.2)) {
            showsIntro = false
        }
    }

    private func handlePlaybackRoute(_ route: PlaybackRoute?) {
        guard let route else { return }
        if libraryViewModel.isPresentingLibrary {
            deferredPlaybackRoute = route
            libraryViewModel.isPresentingLibrary = false
            return
        }
        presentPlayback(for: route)
    }

    private func handleLibraryPresentationChanged(_ isPresented: Bool) {
        guard !isPresented, let route = deferredPlaybackRoute else { return }
        deferredPlaybackRoute = nil
        Task { @MainActor in
            await Task.yield()
            presentPlayback(for: route)
        }
    }

    private func handlePlaybackDismissed() {
        libraryViewModel.clearPlaybackRoute()
        presentedPlaybackRoute = nil
        deferredPlaybackRoute = nil
        synchronizeCaptureMode()
    }

    private func presentPlayback(for route: PlaybackRoute) {
        guard presentedPlaybackRoute == nil else { return }
        guard !isPreparingPlayback else { return }

        isPreparingPlayback = true
        Task {
            await captureViewModel.enterPlaybackMode()
            await MainActor.run {
                presentedPlaybackRoute = route
                isPreparingPlayback = false
            }
        }
    }

    private func synchronizeCaptureMode() {
        let shouldRun = scenePhase == .active
            && !showsIntro
            && !libraryViewModel.isPresentingLibrary
            && !showsSettings
            && presentedPlaybackRoute == nil
            && libraryViewModel.playbackRoute == nil
            && !isPreparingPlayback
            && recoveryShareItem == nil
        if shouldRun {
            captureViewModel.prepare()
            captureViewModel.resumeCaptureMode()
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

    private func applyCaptureOrientation() {
        DaylogOrientationController.apply(settingsViewModel.captureOrientationMode)
        captureViewModel.refreshPreviewOrientation()
    }
}
