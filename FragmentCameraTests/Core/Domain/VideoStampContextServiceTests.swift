import CoreLocation
import XCTest
@testable import FragmentCamera

final class VideoStampContextServiceTests: XCTestCase {
    func testMissingPlaceIsResolvedPersistedAndSharedByEveryDisplayPath() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoStampContextServiceTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let store = VideoStampRecipeStore(fileURL: fileURL)
        let placeResolver = StubPlaceNameResolver(result: "渋谷区")
        let service = VideoStampContextService(
            recipeStore: store,
            placeNameResolver: placeResolver
        )
        let recipe = makeRecipe(placeName: nil)
        try await store.save(recipe)
        let source = VideoStampSource(
            assetLocalIdentifier: recipe.assetLocalIdentifier,
            capturedAt: recipe.context.stampDate,
            location: CLLocation(latitude: 35.6595, longitude: 139.7005)
        )
        let settings = makeSettings(elements: [.date, .place])

        let initial = service.displayContext(
            source: source,
            recipe: recipe,
            settings: settings,
            storageMode: .standard
        )
        let resolved = await service.resolvedDisplayContext(
            source: source,
            recipe: recipe,
            settings: settings,
            storageMode: .standard
        )

        XCTAssertNil(initial?.placeName)
        XCTAssertEqual(resolved?.placeName, "渋谷区")
        let persisted = await store.recipe(for: recipe.assetLocalIdentifier)
        XCTAssertEqual(persisted?.context.placeName, "渋谷区")

        _ = await service.resolvedDisplayContext(
            source: source,
            recipe: persisted,
            settings: settings,
            storageMode: .standard
        )
        let resolvedCallCount = await placeResolver.callCount()
        XCTAssertEqual(resolvedCallCount, 1)
    }

    func testHiddenPlaceNeverTriggersReverseGeocode() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoStampContextServiceTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let store = VideoStampRecipeStore(fileURL: fileURL)
        let placeResolver = StubPlaceNameResolver(result: "渋谷区")
        let service = VideoStampContextService(
            recipeStore: store,
            placeNameResolver: placeResolver
        )
        let recipe = makeRecipe(
            placeName: nil,
            visibilityOverride: VideoStampVisibilityOverride(
                hidesStamp: false,
                hiddenElements: [.place]
            )
        )
        let source = VideoStampSource(
            assetLocalIdentifier: recipe.assetLocalIdentifier,
            capturedAt: recipe.context.stampDate,
            location: CLLocation(latitude: 35.6595, longitude: 139.7005)
        )

        let context = await service.resolvedDisplayContext(
            source: source,
            recipe: recipe,
            settings: makeSettings(elements: [.date, .place]),
            storageMode: .standard
        )

        XCTAssertNotNil(context)
        XCTAssertNil(context?.placeName)
        XCTAssertEqual(context?.elements, [.date])
        XCTAssertEqual(context?.position, .bottomTrailing)
        let hiddenCallCount = await placeResolver.callCount()
        XCTAssertEqual(hiddenCallCount, 0)
    }

    func testBatchResolutionLimitsConcurrencyPreservesOrderAndPersistsPlaces() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoStampContextServiceTests-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let store = VideoStampRecipeStore(fileURL: fileURL)
        let placeResolver = ConcurrentPlaceNameResolver()
        let service = VideoStampContextService(
            recipeStore: store,
            placeNameResolver: placeResolver
        )
        let recipes = (0..<9).map { index in
            makeRecipe(
                identifier: "asset-\(index)",
                placeName: nil
            )
        }
        try await store.save(recipes)
        let sources = recipes.enumerated().map { index, recipe in
            VideoStampSource(
                assetLocalIdentifier: recipe.assetLocalIdentifier,
                capturedAt: recipe.context.stampDate,
                location: CLLocation(
                    latitude: Double(index),
                    longitude: 139
                )
            )
        }
        let progress = BatchProgressRecorder()

        let contexts = await service.resolvedDisplayContexts(
            sources: sources,
            recipes: recipes.map(Optional.some),
            settings: makeSettings(elements: [.date, .place]),
            storageMode: .standard,
            maximumConcurrentResolutions: 4,
            progress: progress.record
        )

        XCTAssertEqual(
            contexts.map(\.?.placeName),
            (0..<9).map { "場所\($0)" }
        )
        let maximumConcurrency = await placeResolver.maximumConcurrency()
        XCTAssertEqual(maximumConcurrency, 4)
        XCTAssertEqual(progress.completedValues, Array(1...9))
        XCTAssertEqual(progress.totalValues, Array(repeating: 9, count: 9))

        let persisted = await store.recipes(
            for: recipes.map(\.assetLocalIdentifier)
        )
        XCTAssertEqual(
            persisted.map { $0?.context.placeName },
            (0..<9).map { "場所\($0)" }
        )
    }

    private func makeSettings(
        elements: Set<DateStampElement>
    ) -> DateStampSettings {
        DateStampSettings(
            isEnabled: true,
            format: DateStampFormatter.compactDateTime,
            isZeroPadded: false,
            timeStyle: .twentyFourHour,
            sizeKey: DateStampStyle.medium,
            position: .bottomTrailing,
            elements: elements,
            fadesOut: false
        )
    }

    private func makeRecipe(
        identifier: String = "asset-1",
        placeName: String?,
        visibilityOverride: VideoStampVisibilityOverride? = nil
    ) -> VideoStampRecipe {
        VideoStampRecipe(
            assetLocalIdentifier: identifier,
            context: VideoPostProcessContext(
                stampEnabled: true,
                stampDate: Date(timeIntervalSince1970: 1_700_000_000),
                format: DateStampFormatter.compactDateTime,
                zeroPadded: false,
                timeStyle: .twentyFourHour,
                sizeKey: DateStampStyle.medium,
                position: .topTrailing,
                elements: [.date, .time],
                fadesOut: true,
                placeName: placeName,
                timeZoneIdentifier: "Asia/Tokyo",
                storageMode: .standard
            ),
            renderingMode: .playbackOverlay,
            visibilityOverride: visibilityOverride
        )
    }
}

private actor ConcurrentPlaceNameResolver: PlaceNameResolving {
    private var activeCount = 0
    private var highestActiveCount = 0

    func placeName(for location: CLLocation) async -> String? {
        activeCount += 1
        highestActiveCount = max(highestActiveCount, activeCount)
        try? await Task.sleep(nanoseconds: 20_000_000)
        activeCount -= 1
        return "場所\(Int(location.coordinate.latitude))"
    }

    func maximumConcurrency() -> Int {
        highestActiveCount
    }
}

private final class BatchProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [(completed: Int, total: Int)] = []

    func record(completed: Int, total: Int) {
        lock.withLock {
            values.append((completed, total))
        }
    }

    var completedValues: [Int] {
        lock.withLock { values.map(\.completed) }
    }

    var totalValues: [Int] {
        lock.withLock { values.map(\.total) }
    }
}

private actor StubPlaceNameResolver: PlaceNameResolving {
    private let result: String?
    private var calls = 0

    init(result: String?) {
        self.result = result
    }

    func placeName(for location: CLLocation) async -> String? {
        calls += 1
        return result
    }

    func callCount() -> Int {
        calls
    }
}
