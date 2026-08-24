import SwiftUI

struct LibraryThumbnailView<Placeholder: View>: View {
    let assetIdentifier: String?
    let targetSize: CGSize

    @StateObject private var loader: LibraryThumbnailLoader
    private let placeholder: Placeholder

    init(
        assetIdentifier: String?,
        thumbnailProvider: LibraryThumbnailProviding,
        targetSize: CGSize,
        @ViewBuilder placeholder: () -> Placeholder
    ) {
        self.assetIdentifier = assetIdentifier
        self.targetSize = targetSize
        self.placeholder = placeholder()
        _loader = StateObject(
            wrappedValue: LibraryThumbnailLoader(
                assetLocalIdentifier: assetIdentifier ?? "",
                provider: thumbnailProvider
            )
        )
    }

    var body: some View {
        placeholder
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                if let image = loader.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
            .onAppear(perform: load)
            .onDisappear {
                loader.cancel()
            }
    }

    private func load() {
        guard assetIdentifier != nil else { return }
        let scale = UIScreen.main.scale
        loader.load(targetSize: CGSize(
            width: max(targetSize.width, 1) * scale,
            height: max(targetSize.height, 1) * scale
        ))
    }
}
