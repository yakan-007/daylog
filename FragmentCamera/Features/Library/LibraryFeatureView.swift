import SwiftUI

extension PresentationDetent {
    /// 撮影画面の上に半分だけ重ねる高さ。後ろのカメラが見える。
    static let libraryPeek = PresentationDetent.fraction(0.47)
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
