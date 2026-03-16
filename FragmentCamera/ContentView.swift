import Photos
import SwiftUI

struct ContentView: View {
    @AppStorage("hasSeenCaptureIntroCard") private var hasSeenCaptureIntroCard = false
    @ObservedObject var captureViewModel: CaptureFeatureViewModel
    @ObservedObject var libraryViewModel: LibraryFeatureViewModel
    @ObservedObject var settingsViewModel: SettingsViewModel
    let makePlaybackSingle: (PHAsset) -> PlaybackFeatureViewModel
    let makePlaybackDay: ([PHAsset]) -> PlaybackFeatureViewModel

    @State private var showIntroCard = false
    @State private var deferredPlaybackRoute: PlaybackRoute?
    @State private var playbackViewModel: PlaybackFeatureViewModel?

    var body: some View {
        ZStack {
            CameraView(cameraService: captureViewModel.cameraService)
                .ignoresSafeArea()
                .simultaneousGesture(tapToFocusGesture)
                .simultaneousGesture(pinchToZoomGesture)

            LinearGradient(
                colors: [.black.opacity(0.35), .clear, .black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            if captureViewModel.showGrid {
                CameraGridOverlay()
            }

            GeometryReader { geometry in
                if captureViewModel.showFocusIndicator, let point = captureViewModel.focusPoint {
                    FocusRingView(point: point, size: geometry.size)
                }
            }

            VStack(spacing: 0) {
                topBar
                Spacer()
                centerStatus
                Spacer()
                bottomDock
            }
            .padding(.top, 10)
            .padding(.bottom, 12)
            .padding(.horizontal, 12)

            if showIntroCard {
                introCard
            }
        }
        .background(Color.black.ignoresSafeArea())
        .task {
            captureViewModel.prepare()
            libraryViewModel.loadIfNeeded()
            if !hasSeenCaptureIntroCard {
                showIntroCard = true
            }
        }
        .onReceive(libraryViewModel.$playbackRoute) { route in
            guard let route else { return }
            if libraryViewModel.isPresentingLibrary {
                deferredPlaybackRoute = route
            } else {
                presentPlayback(for: route)
            }
        }
        .onChange(of: libraryViewModel.isPresentingLibrary) { _, isPresentingLibrary in
            guard !isPresentingLibrary, let deferredPlaybackRoute else { return }
            presentPlayback(for: deferredPlaybackRoute)
            self.deferredPlaybackRoute = nil
        }
        .sheet(isPresented: $libraryViewModel.isPresentingLibrary) {
            DaylogLibrarySheetView(viewModel: libraryViewModel)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $playbackViewModel, onDismiss: {
            deferredPlaybackRoute = nil
            libraryViewModel.clearPlaybackRoute()
            captureViewModel.resumeCaptureMode()
        }) { viewModel in
            PlaybackFeatureView(viewModel: viewModel)
        }
        .sheet(isPresented: $captureViewModel.showSettings) {
            SettingsFeatureView(viewModel: settingsViewModel)
        }
        .alert(
            captureViewModel.permissionTitle,
            isPresented: captureViewModel.isShowingPermissionAlert
        ) {
            Button("設定を開く") {
                captureViewModel.openSettingsApp()
            }
            Button("閉じる", role: .cancel) {}
        } message: {
            Text(captureViewModel.permissionMessage)
        }
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            CapsuleActionButton(
                systemName: captureViewModel.state.torchEnabled ? "bolt.fill" : "bolt.slash.fill",
                tint: captureViewModel.state.torchEnabled ? .yellow : AppTheme.onGlass,
                isEnabled: captureViewModel.state.isTorchAvailable,
                action: captureViewModel.toggleTorch
            )

            Spacer()

            Text("daylog")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.onGlass.opacity(0.92))
                .tracking(1.2)

            Spacer()

            HStack(spacing: 8) {
                CapsuleActionButton(
                    systemName: "square.grid.3x3",
                    tint: captureViewModel.showGrid ? AppTheme.accent : AppTheme.onGlass,
                    action: { captureViewModel.showGrid.toggle() }
                )
                CapsuleActionButton(
                    systemName: "gearshape.fill",
                    tint: AppTheme.onGlass,
                    action: { captureViewModel.showSettings = true }
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppTheme.stroke, lineWidth: 1)
        )
    }

    private var centerStatus: some View {
        VStack(spacing: 12) {
            if let status = captureViewModel.statusText {
                Text(status)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.onGlass)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
            }

            if captureViewModel.showPermissionCard {
                PermissionCard(
                    message: captureViewModel.permissionMessage,
                    onOpenSettings: captureViewModel.openSettingsApp
                )
            }
        }
    }

    private var bottomDock: some View {
        let isRecording = captureViewModel.cameraService.isRecording

        return VStack(spacing: isRecording ? 8 : 14) {
            HStack(spacing: 8) {
                ForEach([1.0, 2.0, 3.0, 4.0, 5.0], id: \.self) { duration in
                    Button {
                        captureViewModel.setDuration(duration)
                    } label: {
                        Text("\(Int(duration))s")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(captureViewModel.state.selectedDuration == duration ? AppTheme.onAccent : AppTheme.onGlass)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(captureViewModel.state.selectedDuration == duration ? AppTheme.accent : Color.white.opacity(0.08))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(SquishableButtonStyle())
                    .disabled(isRecording)
                }
            }
            .opacity(isRecording ? 0.28 : 1)
            .scaleEffect(isRecording ? 0.96 : 1, anchor: .bottom)

            HStack(alignment: .center) {
                compactDockButton(action: {
                    libraryViewModel.openLibrary()
                }) {
                    ZStack(alignment: .bottomTrailing) {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 54, height: 54)
                            .overlay {
                                if let latestThumbnail = libraryViewModel.latestThumbnail {
                                    Image(uiImage: latestThumbnail)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 54, height: 54)
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                } else {
                                    Image(systemName: "photo.stack")
                                        .font(.system(size: 22, weight: .bold))
                                        .foregroundStyle(AppTheme.onGlass)
                                }
                            }
                        Text(libraryViewModel.clipCountTodayLabel())
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(AppTheme.accent)
                            .clipShape(Capsule())
                            .offset(x: 8, y: 8)
                    }
                }
                .opacity(isRecording ? 0.18 : 1)
                .scaleEffect(isRecording ? 0.92 : 1)
                .allowsHitTesting(!isRecording)

                Spacer()

                Button(action: captureViewModel.handleShutterTap) {
                    ZStack {
                        Circle()
                            .strokeBorder(AppTheme.onGlass.opacity(0.92), lineWidth: 3)
                            .frame(width: 88, height: 88)

                        if case .recording(let progress, _) = captureViewModel.state.recording {
                            Circle()
                                .trim(from: 0, to: progress)
                                .stroke(AppTheme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                                .frame(width: 98, height: 98)
                                .rotationEffect(.degrees(-90))
                        }

                        RoundedRectangle(cornerRadius: isRecording ? 12 : 36, style: .continuous)
                            .fill(isRecording ? AppTheme.danger : AppTheme.onGlass)
                            .frame(width: isRecording ? 34 : 68, height: isRecording ? 34 : 68)
                    }
                }
                .buttonStyle(SquishableButtonStyle())
                .disabled(!captureViewModel.isReadyToRecord && !isRecording)

                Spacer()

                compactDockButton(action: captureViewModel.switchCamera) {
                    Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(AppTheme.onGlass)
                        .frame(width: 54, height: 54)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .opacity(isRecording ? 0.18 : 1)
                .scaleEffect(isRecording ? 0.92 : 1)
                .disabled(isRecording)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 18)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(AppTheme.stroke, lineWidth: 1)
        )
    }

    private var introCard: some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                Text("今日を1本だけ残す")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.onGlass)
                Text("起動したらすぐ撮る。撮ったら左下からその日のまとまりを見返す。daylog v1 はこの流れだけに絞っています。")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(AppTheme.onGlass.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
                Button("はじめる") {
                    hasSeenCaptureIntroCard = true
                    withAnimation(.easeOut(duration: 0.2)) {
                        showIntroCard = false
                    }
                }
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.onAccent)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(AppTheme.accent)
                .clipShape(Capsule())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(AppTheme.stroke, lineWidth: 1)
            )
            .padding(16)
        }
        .background(Color.black.opacity(0.24).ignoresSafeArea())
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var tapToFocusGesture: some Gesture {
        SpatialTapGesture().onEnded { event in
            captureViewModel.focus(at: event.location)
        }
    }

    private var pinchToZoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                captureViewModel.applyPinchChanged(value)
            }
            .onEnded { _ in
                captureViewModel.applyPinchEnded()
            }
    }

    private func compactDockButton<Label: View>(action: @escaping () -> Void, @ViewBuilder label: () -> Label) -> some View {
        Button(action: action, label: label)
            .buttonStyle(SquishableButtonStyle())
    }

    private func presentPlayback(for route: PlaybackRoute) {
        switch route {
        case .single(let item):
            playbackViewModel = makePlaybackSingle(item.asset)
        case .day(let items):
            let sortedAssets = items.assets.sorted(by: { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) })
            playbackViewModel = makePlaybackDay(sortedAssets)
        }
    }
}

private struct CapsuleActionButton: View {
    let systemName: String
    let tint: Color
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(isEnabled ? tint : Color.white.opacity(0.35))
                .frame(width: 42, height: 42)
                .background(Color.white.opacity(0.08))
                .clipShape(Capsule())
        }
        .buttonStyle(SquishableButtonStyle())
        .disabled(!isEnabled)
    }
}

private struct PermissionCard: View {
    let message: String
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("権限を確認してください")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.8))
            Button("設定を開く", action: onOpenSettings)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.onAccent)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(AppTheme.accent)
                .clipShape(Capsule())
        }
        .padding(16)
        .frame(maxWidth: 320, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(AppTheme.stroke, lineWidth: 1)
        )
    }
}
