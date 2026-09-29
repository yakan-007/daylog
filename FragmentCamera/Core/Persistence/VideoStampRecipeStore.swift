import Foundation

struct VideoStampVisibilityOverride: Codable, Equatable, Sendable {
    var hidesStamp: Bool
    var hiddenElements: Set<DateStampElement>

    static let none = VideoStampVisibilityOverride(
        hidesStamp: false,
        hiddenElements: []
    )

    var normalized: VideoStampVisibilityOverride? {
        hidesStamp || !hiddenElements.isEmpty ? self : nil
    }
}

struct VideoStampRecipe: Codable, Equatable, Sendable {
    let assetLocalIdentifier: String
    let context: VideoPostProcessContext
    let renderingMode: StampRenderingMode
    let visibilityOverride: VideoStampVisibilityOverride?
}

/// 写真ライブラリの動画本体とは別に、変更可能なスタンプ設定を保持する。
///
/// PhotoKit の asset identifier をキーにすることで、ライブラリ再読込で表示順が
/// 変わっても同じ動画へ設定を適用できる。書き込みは atomic にして途中終了による
/// JSON 破損を避ける。
actor VideoStampRecipeStore {
    private let fileURL: URL
    private var recipesByIdentifier: [String: VideoStampRecipe] = [:]
    private var hasLoaded = false

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
    }

    func recipe(for assetLocalIdentifier: String) -> VideoStampRecipe? {
        loadIfNeeded()
        return recipesByIdentifier[assetLocalIdentifier]
    }

    func recipes(for assetLocalIdentifiers: [String]) -> [VideoStampRecipe?] {
        loadIfNeeded()
        return assetLocalIdentifiers.map { recipesByIdentifier[$0] }
    }

    func save(_ recipe: VideoStampRecipe) throws {
        loadIfNeeded()
        recipesByIdentifier[recipe.assetLocalIdentifier] = recipe
        try persist()
    }

    /// 大量書き出し時にレシピJSON全体を1本ごとに書き直さないための一括更新。
    func save(_ recipes: [VideoStampRecipe]) throws {
        guard !recipes.isEmpty else { return }
        loadIfNeeded()
        for recipe in recipes {
            recipesByIdentifier[recipe.assetLocalIdentifier] = recipe
        }
        try persist()
    }

    func removeRecipe(for assetLocalIdentifier: String) throws {
        loadIfNeeded()
        guard recipesByIdentifier.removeValue(forKey: assetLocalIdentifier) != nil else {
            return
        }
        try persist()
    }

    private func loadIfNeeded() {
        guard !hasLoaded else { return }
        hasLoaded = true
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try JSONDecoder().decode([VideoStampRecipe].self, from: data)
            recipesByIdentifier = Dictionary(
                decoded.map { ($0.assetLocalIdentifier, $0) },
                uniquingKeysWith: { _, latest in latest }
            )
        } catch {
            recipesByIdentifier = [:]
            AppLog.save.error(
                "stamp_recipe.load.fail reason=\(error.localizedDescription, privacy: .private)"
            )
        }
    }

    private func persist() throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        let ordered = recipesByIdentifier.values.sorted {
            $0.assetLocalIdentifier < $1.assetLocalIdentifier
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(ordered).write(to: fileURL, options: .atomic)
    }

    private static func defaultFileURL() -> URL {
        let baseURL = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("vlogish", isDirectory: true)
            .appendingPathComponent("video-stamp-recipes.json")
    }
}
