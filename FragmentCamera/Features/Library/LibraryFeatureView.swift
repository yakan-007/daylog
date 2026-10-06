import SwiftUI

extension PresentationDetent {
    /// 撮影画面の上に半分だけ重ねる高さ。後ろのカメラが見える。
    static let libraryPeek = PresentationDetent.custom(LibraryPeekDetent.self)
}

/// 半分の高さ。基本は画面の47%だが、小さい iPhone や文字を大きくした時でも
/// 今日の分（日付・クリップ・時間軸・「通して見る」と共有）が最初から見える高さを確保する。
struct LibraryPeekDetent: CustomPresentationDetent {
    /// 標準の文字サイズで、見出しと今日の分が収まる高さ。
    private static let contentHeight: CGFloat = 392

    static func height(in context: Context) -> CGFloat? {
        let textScale: CGFloat
        if context.dynamicTypeSize.isAccessibilitySize {
            textScale = 1.45
        } else if context.dynamicTypeSize > .large {
            textScale = 1.15
        } else {
            textScale = 1
        }
        let preferred = max(context.maxDetentValue * 0.47, contentHeight * textScale)
        // カメラが少しは見えるよう、上限は8割にする（それ以上は中をスクロール）。
        return min(preferred, context.maxDetentValue * 0.8)
    }
}

struct VlogishLibrarySheetView: View {
    @ObservedObject var viewModel: LibraryFeatureViewModel
    var onExpand: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            cameraRollContent
        }
        .preferredColorScheme(.light)
        .task {
            viewModel.loadIfNeeded()
        }
        .sheet(item: $viewModel.exportShareItem, onDismiss: {
            viewModel.clearExportShareItem()
        }) { item in
            ShareSheet(activityItems: [item.url])
        }
        .sheet(item: $viewModel.stampEditorRoute) { route in
            VideoStampEditorView(
                viewModel: viewModel.makeStampEditorViewModel(route: route),
                onSaved: viewModel.handleStampEditSaved
            )
            // 動画を主役にした暗い編集画面。再生画面と同じ出し方にそろえる。
            .presentationDragIndicator(.hidden)
            .presentationCornerRadius(30)
        }
        .alert(
            viewModel.exportFailure?.title ?? VlogishFailure.exportFailed.title,
            isPresented: exportFailureBinding
        ) {
            Button("もう一度", action: viewModel.retryExport)
            Button("閉じる", role: .cancel) {}
        } message: {
            Text(
                viewModel.exportFailureDetail
                    ?? viewModel.exportFailure?.message
                    ?? VlogishFailure.exportFailed.message
            )
        }
        .alert(item: $viewModel.exportConfirmation) { confirmation in
            Alert(
                title: Text(confirmation.assessment.confirmationTitle),
                message: Text(confirmation.assessment.confirmationMessage),
                primaryButton: .default(Text("結合する")) {
                    viewModel.confirmExport(confirmation)
                },
                secondaryButton: .cancel(Text("やめる"), action: viewModel.cancelExportConfirmation)
            )
        }
        .alert(
            viewModel.libraryFailure?.title ?? VlogishFailure.libraryAssetUnavailable.title,
            isPresented: libraryFailureBinding
        ) {
            if viewModel.libraryFailure?.requiresSettings == true {
                Button("設定を開く", action: viewModel.openSystemSettings)
            }
            Button("再読み込み", action: viewModel.retryLibraryLoad)
            Button("閉じる", role: .cancel) {}
        } message: {
            Text(viewModel.libraryFailure?.message ?? VlogishFailure.libraryAssetUnavailable.message)
        }
        .alert(
            "一部の写真のみ表示中",
            isPresented: $viewModel.isLimitedLibraryNoticePresented
        ) {
            Button("写真を追加選択", action: viewModel.manageLimitedLibraryAccess)
            Button("設定を開く", action: viewModel.openSystemSettings)
            Button("閉じる", role: .cancel) {}
        } message: {
            Text("iOSで選択した写真だけを表示しています。アプリの動画が見つからない場合は、表示する写真を追加してください。")
        }
        .interactiveDismissDisabled(viewModel.hasActiveExport)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                viewModel.retryLibraryLoad()
            }
        }
    }

    private var cameraRollContent: some View {
        CameraRollView(
            state: viewModel.screenState,
            thumbnailProvider: viewModel.thumbnailProvider,
            onClipTap: viewModel.playClip,
            onEditStamp: viewModel.editStamp,
            onExportClip: viewModel.exportClip,
            onPlayDay: viewModel.playDay,
            onExportDay: viewModel.exportDay,
            onLoadDay: viewModel.loadDayIfNeeded,
            onCancelExport: viewModel.cancelExport,
            onLoadMore: viewModel.loadMoreIfNeeded,
            onRefresh: viewModel.refresh,
            onClose: closeLibrary,
            onExpand: onExpand,
            onShareExport: viewModel.shareCompletedExport,
            onDismissExport: viewModel.dismissCompletedExport
        )
    }

    private func closeLibrary() {
        if viewModel.hasActiveExport {
            viewModel.cancelExport()
        } else {
            dismiss()
        }
    }

    private var exportFailureBinding: Binding<Bool> {
        Binding(
            get: { viewModel.exportFailure != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.clearExportFailure()
                }
            }
        )
    }

    private var libraryFailureBinding: Binding<Bool> {
        Binding(
            get: { viewModel.libraryFailure != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.clearLibraryFailure()
                }
            }
        )
    }
}
