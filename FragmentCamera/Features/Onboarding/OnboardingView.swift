import AVFoundation
import Photos
import SwiftUI

/// はじめての案内。ようこそ → 許可のお願い → スタンプを選ぶ、の3枚。
///
/// 許可は理由を見せてから、カメラ・マイク・写真をまとめて確認する（撮影直後に写真の確認が割り込まないように）。
/// 位置情報は「場所」を選んだ人にだけ、撮影の時に確認する。
struct OnboardingView: View {
    @ObservedObject var settingsViewModel: SettingsViewModel
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step: Step = .welcome
    @State private var isRequestingPermissions = false

    private enum Step: Int, CaseIterable {
        case welcome
        case permissions
        case stamp
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header
                switch step {
                case .welcome:
                    welcome.transition(.opacity)
                case .permissions:
                    permissions.transition(.opacity)
                case .stamp:
                    stamp.transition(.opacity)
                }
            }
            .padding(.horizontal, 28)
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: step)
    }

    private var header: some View {
        HStack {
            Text(verbatim: AppIdentity.brandName.uppercased())
                .rollMono(13, .semibold, maxScale: 1.3)
                .tracking(1.8)
                .opacity(0.85)
            Spacer()
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.rawValue) { item in
                    Capsule()
                        .fill(item == step ? Color.white : Color.white.opacity(0.3))
                        .frame(width: item == step ? 16 : 6, height: 6)
                }
            }
            .accessibilityHidden(true)
        }
        .padding(.top, 24)
    }

    private func primaryButton(_ title: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .rollText(16, .bold)
                .foregroundStyle(RollTheme.ink)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(Color.white.opacity(0.94), in: Capsule())
        }
        .buttonStyle(SquishableButtonStyle())
        .padding(.bottom, 24)
        .accessibilityIdentifier(identifier)
    }

    // MARK: Welcome

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 24)
            OnboardingTimeline()
                .padding(.bottom, 40)
            Text(L10n.text("一瞬ずつ、\n一日を残す。"))
                .rollText(30, .bold)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            Text(L10n.text("1日に何度か、数秒だけ撮る。\n撮った時刻が線に並んで、夜には1本の動画になる。"))
                .rollText(14)
                .lineSpacing(6)
                .opacity(0.75)
                .padding(.top, 14)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 24)
            primaryButton(L10n.text("はじめる"), identifier: "onboarding.next") {
                step = .permissions
            }
        }
    }

    // MARK: Permissions

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 24)
            Text(L10n.text("使う前に、\n3つだけ許可してください"))
                .rollText(24, .bold)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 20)
            permissionRow(symbol: "camera", title: L10n.text("カメラ"), body: L10n.text("数秒の動画を撮るために使います。"))
            permissionRow(symbol: "mic", title: L10n.text("マイク"), body: L10n.text("その場の音も一緒に残します。"))
            permissionRow(symbol: "photo.on.rectangle", title: L10n.text("写真"), body: L10n.text("撮った動画を保存して、記録として並べるために使います。"))
            Text(L10n.text("動画はあなたの iPhone の写真ライブラリにだけ保存されます。アカウント登録もありません。"))
                .rollText(11)
                .lineSpacing(4)
                .opacity(0.55)
                .padding(.top, 20)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 24)
            primaryButton(L10n.text("続ける"), identifier: "onboarding.permissions.continue") {
                requestPermissions()
            }
            .disabled(isRequestingPermissions)
        }
    }

    private func permissionRow(symbol: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.1), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).rollText(15, .bold)
                Text(body)
                    .rollText(12)
                    .opacity(0.7)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }

    /// カメラ → マイク → 写真の順に確認する。断られても先へ進む（撮影画面で改めて案内する）。
    private func requestPermissions() {
        guard !isRequestingPermissions else { return }
        isRequestingPermissions = true
        Task { @MainActor in
            if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .video)
            }
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .audio)
            }
            if PHPhotoLibrary.authorizationStatus(for: .readWrite) == .notDetermined {
                _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            }
            isRequestingPermissions = false
            step = .stamp
        }
    }

    // MARK: Stamp

    private var stamp: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L10n.text("スタンプを選ぶ"))
                .rollText(24, .bold)
                .padding(.top, 36)
            Text(L10n.text("撮った動画に入る文字です。あとで設定から変えられます。"))
                .rollText(13)
                .opacity(0.7)
                .padding(.top, 6)
                .fixedSize(horizontal: false, vertical: true)

            stampPreview
                .padding(.top, 20)

            HStack(alignment: .center, spacing: 16) {
                HStack(spacing: 0) {
                    ForEach(DateStampElement.allCases, id: \.rawValue) { element in
                        stampChip(element)
                    }
                    noneChip
                }
                positionGrid
            }
            .padding(.top, 18)

            Text(settingsViewModel.stampEnabled && settingsViewModel.stampElements.contains(.place)
                 ? L10n.text("場所を出すため、撮影のときに位置情報の許可を確認します。")
                 : L10n.text("場所を入れると、撮った場所の地名も残ります。"))
                .rollText(11)
                .opacity(0.55)
                .padding(.top, 10)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 16)
            primaryButton(L10n.text("これで始める"), identifier: "capture.intro.start") {
                onFinish()
            }
        }
    }

    private var stampPreview: some View {
        let block = VlogStampLayerSeeder.block(
            settings: settingsViewModel.previewStampSettings,
            placeName: L10n.text("地名")
        )
        let overlays = VlogTextOverlayResolver.resolve(
            edit: VlogClipEdit(assetLocalIdentifier: "onboarding.preview", block: block),
            metadata: VlogClipSourceMetadata(
                capturedAt: Date(),
                capturedPlaceName: nil,
                timeZoneIdentifier: TimeZone.current.identifier
            ),
            clipDuration: 3
        )
        return ZStack {
            LinearGradient(
                colors: [Color(hex: 0x5E7180), Color(hex: 0x2C3038)],
                startPoint: .top,
                endPoint: .bottom
            )
            VlogTextOverlayCanvas(
                overlays: settingsViewModel.stampEnabled ? overlays : [],
                playbackTime: 0,
                videoAspectRatio: 9.0 / 16.0
            )
            .allowsHitTesting(false)
        }
        .aspectRatio(9.0 / 16.0, contentMode: .fit)
        .frame(maxHeight: 290)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(settingsViewModel.stampEnabled ? (overlays.first?.text ?? "") : L10n.text("タイムスタンプなし"))
    }

    private func stampChip(_ element: DateStampElement) -> some View {
        let isOn = settingsViewModel.stampEnabled && settingsViewModel.stampElements.contains(element)
        return chip(label: element.title, isOn: isOn, identifier: "onboarding.stamp.\(element.rawValue)") {
            switch element {
            case .date:
                Text(verbatim: CameraRollStampFormat.date.string(from: Date()))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
            case .time:
                Text(verbatim: CameraRollStampFormat.hourMinute.string(from: Date()))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
            case .place:
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 15, weight: .medium))
            }
        } action: {
            settingsViewModel.toggleStampElementForSetup(element)
        }
    }

    private var noneChip: some View {
        chip(label: L10n.text("なし"), isOn: !settingsViewModel.stampEnabled, identifier: "onboarding.stamp.none") {
            Image(systemName: "minus")
                .font(.system(size: 15, weight: .medium))
        } action: {
            settingsViewModel.stampEnabled = false
        }
    }

    private func chip<Glyph: View>(
        label: String,
        isOn: Bool,
        identifier: String,
        @ViewBuilder glyph: () -> Glyph,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                glyph()
                    .foregroundStyle(isOn ? RollTheme.ink : .white)
                    .frame(width: 46, height: 46)
                    .background {
                        if isOn {
                            Circle().fill(Color.white.opacity(0.94))
                        } else {
                            Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
                        }
                    }
                Text(label)
                    .rollText(11, maxScale: 1.3)
                    .opacity(0.9)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(SquishableButtonStyle())
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier(identifier)
        .sensoryFeedback(.selection, trigger: isOn)
    }

    private var positionGrid: some View {
        let columns = Array(repeating: GridItem(.fixed(22), spacing: 4), count: 3)
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(DateStampPosition.allCases, id: \.rawValue) { position in
                let isSelected = settingsViewModel.stampPosition == position
                Button {
                    settingsViewModel.stampPositionKey = position.rawValue
                } label: {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(isSelected ? Color.white.opacity(0.94) : Color.white.opacity(0.14))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle().inset(by: -3))
                }
                .buttonStyle(SquishableButtonStyle())
                .accessibilityLabel(position.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .frame(width: 74)
        .disabled(!settingsViewModel.stampEnabled)
        .opacity(settingsViewModel.stampEnabled ? 1 : 0.35)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.text("表示位置"))
    }
}

/// ようこそ画面の時間軸。撮った時刻の線が1本ずつ現れ、最後に「いま」の点が残る。
private struct OnboardingTimeline: View {
    private let hours: [Double] = [7.7, 12.25, 12.8, 15.05, 18.65, 20.95]
    private let now: Double = 21.2

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visibleCount = 0

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(verbatim: "\(CameraRollStampFormat.date.string(from: Date())) \(CameraRollStampFormat.weekday.string(from: Date()).uppercased())")
                Spacer()
                Text(verbatim: CameraRollStampFormat.clips(visibleCount))
                    .contentTransition(.numericText())
            }
            .rollMono(11, maxScale: 1.3)
            .opacity(0.8)

            Canvas { context, size in
                let midY = size.height / 2
                let nowX = size.width * now / 24
                var past = Path()
                past.move(to: CGPoint(x: 0, y: midY))
                past.addLine(to: CGPoint(x: nowX, y: midY))
                context.stroke(past, with: .color(.white), lineWidth: 1)
                var future = Path()
                future.move(to: CGPoint(x: nowX, y: midY))
                future.addLine(to: CGPoint(x: size.width, y: midY))
                context.stroke(future, with: .color(.white.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                for hour in hours.prefix(visibleCount) {
                    let x = size.width * hour / 24
                    context.fill(Path(CGRect(x: x - 1, y: 0, width: 2, height: size.height)), with: .color(.white))
                }
                let dot = CGRect(x: nowX - 5.5, y: midY - 5.5, width: 11, height: 11)
                context.fill(Path(ellipseIn: dot), with: .color(RollTheme.accent))
            }
            .frame(height: 22)

            HStack {
                ForEach(["0", "6", "12", "18", "24"], id: \.self) { label in
                    Text(verbatim: label)
                    if label != "24" { Spacer() }
                }
            }
            .rollMono(9, maxScale: 1.2)
            .opacity(0.55)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.text("撮った時刻が一日の線に並ぶ様子"))
        .task {
            guard !reduceMotion else {
                visibleCount = hours.count
                return
            }
            try? await Task.sleep(for: .milliseconds(300))
            for index in 1...hours.count {
                withAnimation(.easeOut(duration: 0.25)) { visibleCount = index }
                try? await Task.sleep(for: .milliseconds(260))
            }
        }
    }
}
