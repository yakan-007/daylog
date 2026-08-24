import Combine
import CoreGraphics
import UIKit

struct LibraryThumbnailRequest: Hashable {
    let rawValue: Int32
}

@MainActor
protocol LibraryThumbnailProviding: AnyObject {
    @discardableResult
    func requestThumbnail(
        assetLocalIdentifier: String,
        targetSize: CGSize,
        completion: @MainActor @escaping (UIImage?) -> Void
    ) -> LibraryThumbnailRequest

    func cancelThumbnailRequest(_ request: LibraryThumbnailRequest)
}

@MainActor
final class LibraryThumbnailLoader: ObservableObject {
    @Published private(set) var image: UIImage?

    private let assetLocalIdentifier: String
    private let provider: LibraryThumbnailProviding
    private var request: LibraryThumbnailRequest?
    private var loadID: UUID?

    init(
        assetLocalIdentifier: String,
        provider: LibraryThumbnailProviding
    ) {
        self.assetLocalIdentifier = assetLocalIdentifier
        self.provider = provider
    }

    func load(targetSize: CGSize) {
        guard image == nil, request == nil else { return }
        let loadID = UUID()
        self.loadID = loadID
        request = provider.requestThumbnail(
            assetLocalIdentifier: assetLocalIdentifier,
            targetSize: targetSize
        ) { [weak self] image in
            guard let self, self.loadID == loadID else { return }
            self.image = image
            self.request = nil
            self.loadID = nil
        }
    }

    func cancel() {
        loadID = nil
        guard let request else { return }
        provider.cancelThumbnailRequest(request)
        self.request = nil
    }
}
