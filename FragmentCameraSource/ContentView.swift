import SwiftUI

struct ContentView: View {
    @StateObject private var cameraService = CameraService()
    struct CaptureUIState {
        var thumbnail: UIImage? = nil
        var recordingTime: TimeInterval = 0
    }
    @State private var ui = CaptureUIState()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            // 1. 背景のカメラビュー
            CameraView(cameraService: cameraService)
                .ignoresSafeArea()

            // --- UI要素をVStackで囲まず、個別にZStackの子として配置 ---

            // 2. 上部コントロール (画面上部に固定)
            HStack {
                // フラッシュボタン
                Button(action: {
                    // TODO: フラッシュ機能の実装
                }) {
                    Image(systemName: "bolt.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                }

                Spacer()

                // カメラ切り替えボタン
                Button(action: {
                    cameraService.switchCamera()
                }) {
                    Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                        .font(.title2)
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal)
            .padding(.top)
            .frame(maxHeight: .infinity, alignment: .top) // ZStack内で上部に配置

            // 3. 録画タイマー (画面上部中央に固定)
            if cameraService.isRecording {
                Text(formatTime(ui.recordingTime))
                    .foregroundColor(.white)
                    .font(.headline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(10)
                    .frame(maxHeight: .infinity, alignment: .top) // ZStack内で上部に配置
                    .padding(.top)
            }

            // 4. 下部コントロール (画面下部に固定)
            HStack(alignment: .center) {
                // サムネイル
                Button(action: {
                    // TODO: ギャラリー表示機能の実装
                }) {
                    if let thumbnail = ui.thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 60, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white, lineWidth: 2)
                            )
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.8))
                            .frame(width: 60, height: 60)
                            .overlay(
                                Image(systemName: "photo.on.rectangle")
                                    .foregroundColor(.white)
                                    .font(.title)
                            )
                    }
                }
                .frame(width: 80)

                Spacer()

                // 録画ボタン
                Button(action: {
                    if cameraService.isRecording {
                        cameraService.stopRecording()
                        // TODO: 録画停止時にサムネイルを更新する処理
                    } else {
                        ui.recordingTime = 0
                        cameraService.startRecording()
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(cameraService.isRecording ? .red : .white)
                            .frame(width: 70, height: 70)

                        Circle()
                            .stroke(Color.white, lineWidth: 4)
                            .frame(width: 80, height: 80)
                    }
                }

                Spacer()

                // 右側のスペーサー
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 80)
            }
            .padding(.horizontal)
            .padding(.bottom, 30)
            .frame(maxHeight: .infinity, alignment: .bottom) // ZStack内で下部に配置
        }
        .onAppear {
            cameraService.checkForPermissions()
        }
        .onReceive(timer) { _ in
            if cameraService.isRecording {
                ui.recordingTime += 1
            }
        }
        .edgesIgnoringSafeArea(.all) // ZStack全体でSafeAreaを無視するようにする
    }

    // 時間をフォーマットするヘルパー関数
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
