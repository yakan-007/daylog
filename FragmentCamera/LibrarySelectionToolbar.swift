import SwiftUI
import Photos

struct LibrarySelectionToolbar: ToolbarContent {
    @Binding var isSelecting: Bool
    @Binding var selectedTab: PhotoSheetView.Tab
    let selectedCount: Int
    let onClose: () -> Void
    let onCancel: () -> Void
    let onShare: () -> Void
    let onDelete: () -> Void
    let onEnterSelection: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            if isSelecting {
                Button("キャンセル", action: onCancel)
                    .accessibilityLabel("選択をやめる")
            } else {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("閉じる")
            }
        }

        ToolbarItem(placement: .navigationBarTrailing) {
            if isSelecting {
                HStack(spacing: 14) {
                    Button(action: onShare) {
                        Image(systemName: "square.and.arrow.up")
                            .symbolRenderingMode(.hierarchical)
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 44, height: 44)
                    }
                    .disabled(selectedCount == 0)
                    .accessibilityLabel("選択した動画を書き出す")

                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                            .symbolRenderingMode(.hierarchical)
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 44, height: 44)
                    }
                    .disabled(selectedCount == 0)
                    .accessibilityLabel("選択した動画を削除")
                }
            } else if selectedTab == .list {
                Button("選択", action: onEnterSelection)
                    .accessibilityLabel("選択モードにする")
            }
        }
    }
}
