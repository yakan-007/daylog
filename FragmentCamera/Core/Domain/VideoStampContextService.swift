@preconcurrency import CoreLocation
import Foundation

protocol PlaceNameResolving: Sendable {
    func placeName(for location: CLLocation) async -> String?
}

/// 逆ジオコードを一か所へ集約し、同じ場所の短い動画で問い合わせを繰り返さない。
final class PlaceNameResolver: PlaceNameResolving, @unchecked Sendable {
    private struct InFlightResolution {
        let id: UUID
        let task: Task<String?, Never>
    }

    private enum Lookup {
        case cached(String)
        case resolving(InFlightResolution)
    }

    private struct CoordinateKey: Hashable {
        let latitude: Int
        let longitude: Int

        init(_ location: CLLocation) {
            // 約100m単位。表示する地名の粒度を保ちつつ連続撮影をまとめる。
            latitude = Int((location.coordinate.latitude * 1_000).rounded())
            longitude = Int((location.coordinate.longitude * 1_000).rounded())
        }
    }

    private let timeout: TimeInterval
    private let cacheLock = NSLock()
    private var cache: [CoordinateKey: String] = [:]
    private var inFlight: [CoordinateKey: InFlightResolution] = [:]

    init(timeout: TimeInterval = 1.5) {
        self.timeout = timeout
    }

    func placeName(for location: CLLocation) async -> String? {
        let key = CoordinateKey(location)
        let lookup = cacheLock.withLock { () -> Lookup in
            if let cached = cache[key] {
                return .cached(cached)
            }
            if let existing = inFlight[key] {
                return .resolving(existing)
            }
            let resolution = InFlightResolution(
                id: UUID(),
                task: Task { [timeout] in
                    await Self.resolve(
                        location: location,
                        timeout: timeout
                    )
                }
            )
            inFlight[key] = resolution
            return .resolving(resolution)
        }
        if case .cached(let cached) = lookup {
            return cached
        }
        guard case .resolving(let resolution) = lookup else { return nil }
        let resolved = await resolution.task.value
        cacheLock.withLock {
            if let resolved {
                cache[key] = resolved
            }
            if inFlight[key]?.id == resolution.id {
                inFlight[key] = nil
            }
        }
        return resolved
    }

    private static func resolve(
        location: CLLocation,
        timeout: TimeInterval
    ) async -> String? {
        await withCheckedContinuation { continuation in
            let request = ReverseGeocodeRequest(continuation: continuation)
            request.start(
                location: location,
                locale: Locale.current,
                timeout: timeout
            )
        }
    }
}

/// 完了はロックで一度だけ取り出す。CLGeocoderは開始後のcancelを別キューから受けられる。
private final class ReverseGeocodeRequest: @unchecked Sendable {
    private let geocoder = CLGeocoder()
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String?, Never>?

    init(continuation: CheckedContinuation<String?, Never>) {
        self.continuation = continuation
    }

    func start(location: CLLocation, locale: Locale, timeout: TimeInterval) {
        geocoder.reverseGeocodeLocation(location, preferredLocale: locale) { [self] placemarks, error in
            if let error,
               (error as? CLError)?.code != .geocodeCanceled {
                AppLog.location.notice(
                    "location.reverse_geocode.unavailable reason=\(error.localizedDescription, privacy: .private)"
                )
            }
            let placeName = placemarks?.first.flatMap { placemark in
                PlaceNameFormatter.string(
                    locality: placemark.locality,
                    subAdministrativeArea: placemark.subAdministrativeArea,
                    administrativeArea: placemark.administrativeArea,
                    country: placemark.country
                )
            }
            finish(with: placeName)
        }

        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout) { [self] in
            geocoder.cancelGeocode()
            finish(with: nil)
        }
    }

    private func finish(with result: String?) {
        let continuation = lock.withLock { () -> CheckedContinuation<String?, Never>? in
            defer { self.continuation = nil }
            return self.continuation
        }
        continuation?.resume(returning: result)
    }
}

struct VideoStampSource: @unchecked Sendable {
    let assetLocalIdentifier: String
    let capturedAt: Date
    let location: CLLocation?
    let fallbackTimeZoneIdentifier: String

    init(
        assetLocalIdentifier: String,
        capturedAt: Date,
        location: CLLocation?,
        fallbackTimeZoneIdentifier: String = TimeZone.current.identifier
    ) {
        self.assetLocalIdentifier = assetLocalIdentifier
        self.capturedAt = capturedAt
        self.location = location
        self.fallbackTimeZoneIdentifier = fallbackTimeZoneIdentifier
    }
}

/// 再生・単体書き出し・一日書き出しが同じスタンプ決定ロジックを使うための窓口。
final class VideoStampContextService: @unchecked Sendable {
    private struct ResolvedContext: Sendable {
        let index: Int
        let context: VideoPostProcessContext?
        let updatedRecipe: VideoStampRecipe?
    }

    private let recipeStore: VideoStampRecipeStore
    private let placeNameResolver: any PlaceNameResolving

    init(
        recipeStore: VideoStampRecipeStore = VideoStampRecipeStore(),
        placeNameResolver: any PlaceNameResolving = PlaceNameResolver()
    ) {
        self.recipeStore = recipeStore
        self.placeNameResolver = placeNameResolver
    }

    func recipe(for assetLocalIdentifier: String) async -> VideoStampRecipe? {
        await recipeStore.recipe(for: assetLocalIdentifier)
    }

    func recipes(for assetLocalIdentifiers: [String]) async -> [VideoStampRecipe?] {
        await recipeStore.recipes(for: assetLocalIdentifiers)
    }

    func displayContext(
        source: VideoStampSource,
        recipe: VideoStampRecipe?,
        settings: DateStampSettings,
        storageMode: VideoStorageMode
    ) -> VideoPostProcessContext? {
        let effectiveSettings = settings.applying(recipe?.visibilityOverride)
        return makeDisplayContext(
            source: source,
            baseContext: recipe?.context,
            fallbackPlaceName: nil,
            settings: effectiveSettings,
            storageMode: storageMode
        )
    }

    func resolvedDisplayContext(
        source: VideoStampSource,
        recipe: VideoStampRecipe?,
        settings: DateStampSettings,
        storageMode: VideoStorageMode
    ) async -> VideoPostProcessContext? {
        let resolved = await resolveDisplayContext(
            index: 0,
            source: source,
            recipe: recipe,
            settings: settings,
            storageMode: storageMode
        )
        if let updatedRecipe = resolved.updatedRecipe {
            do {
                try await recipeStore.save(updatedRecipe)
            } catch {
                AppLog.save.error(
                    "stamp_recipe.place_update.fail asset=\(source.assetLocalIdentifier, privacy: .private(mask: .hash)) reason=\(error.localizedDescription, privacy: .private)"
                )
            }
        }
        return resolved.context
    }

    /// 大量書き出し向け。順序を維持しながら地名解決だけを上限付きで並列化し、
    /// 更新されたレシピは最後に一度だけ永続化する。
    func resolvedDisplayContexts(
        sources: [VideoStampSource],
        recipes: [VideoStampRecipe?],
        settings: DateStampSettings,
        storageMode: VideoStorageMode,
        maximumConcurrentResolutions: Int = 4,
        progress: @escaping @Sendable (_ completed: Int, _ total: Int) async -> Void = { _, _ in }
    ) async -> [VideoPostProcessContext?] {
        guard !sources.isEmpty else { return [] }
        let normalizedRecipes = recipes.count == sources.count
            ? recipes
            : Array(repeating: nil, count: sources.count)
        let concurrencyLimit = min(
            max(maximumConcurrentResolutions, 1),
            sources.count
        )
        var contexts = Array<VideoPostProcessContext?>(
            repeating: nil,
            count: sources.count
        )
        var updatedRecipes: [VideoStampRecipe] = []
        updatedRecipes.reserveCapacity(sources.count)

        await withTaskGroup(of: ResolvedContext.self) { group in
            var nextIndex = 0
            for _ in 0..<concurrencyLimit {
                let index = nextIndex
                nextIndex += 1
                group.addTask { [self] in
                    await resolveDisplayContext(
                        index: index,
                        source: sources[index],
                        recipe: normalizedRecipes[index],
                        settings: settings,
                        storageMode: storageMode
                    )
                }
            }

            var completed = 0
            while let resolved = await group.next() {
                contexts[resolved.index] = resolved.context
                if let updatedRecipe = resolved.updatedRecipe {
                    updatedRecipes.append(updatedRecipe)
                }
                completed += 1
                await progress(completed, sources.count)

                if Task.isCancelled {
                    group.cancelAll()
                    break
                }

                if nextIndex < sources.count {
                    let index = nextIndex
                    nextIndex += 1
                    group.addTask { [self] in
                        await resolveDisplayContext(
                            index: index,
                            source: sources[index],
                            recipe: normalizedRecipes[index],
                            settings: settings,
                            storageMode: storageMode
                        )
                    }
                }
            }
        }

        if !updatedRecipes.isEmpty {
            do {
                try await recipeStore.save(updatedRecipes)
            } catch {
                AppLog.save.error(
                    "stamp_recipe.place_batch_update.fail count=\(updatedRecipes.count, privacy: .public) reason=\(error.localizedDescription, privacy: .private)"
                )
            }
        }
        return contexts
    }

    private func resolveDisplayContext(
        index: Int,
        source: VideoStampSource,
        recipe: VideoStampRecipe?,
        settings: DateStampSettings,
        storageMode: VideoStorageMode
    ) async -> ResolvedContext {
        let effectiveSettings = settings.applying(recipe?.visibilityOverride)
        var baseContext = recipe?.context
        var placeName = baseContext?.placeName
        var updatedRecipe: VideoStampRecipe?
        if effectiveSettings.shouldResolvePlaceName(
            storedPlaceName: placeName,
            hasAssetLocation: source.location != nil
        ), let location = source.location,
           let resolved = await placeNameResolver.placeName(for: location) {
            placeName = resolved
            if let recipe, let storedContext = baseContext {
                let updatedContext = storedContext.replacingPlaceName(resolved)
                baseContext = updatedContext
                updatedRecipe = VideoStampRecipe(
                    assetLocalIdentifier: recipe.assetLocalIdentifier,
                    context: updatedContext,
                    renderingMode: recipe.renderingMode,
                    visibilityOverride: recipe.visibilityOverride
                )
            }
        }

        return ResolvedContext(
            index: index,
            context: makeDisplayContext(
                source: source,
                baseContext: baseContext,
                fallbackPlaceName: placeName,
                settings: effectiveSettings,
                storageMode: storageMode
            ),
            updatedRecipe: updatedRecipe
        )
    }

    private func makeDisplayContext(
        source: VideoStampSource,
        baseContext: VideoPostProcessContext?,
        fallbackPlaceName: String?,
        settings: DateStampSettings,
        storageMode: VideoStorageMode
    ) -> VideoPostProcessContext? {
        baseContext
            .flatMap {
                settings.displayContext(
                    basedOn: $0,
                    storageMode: storageMode
                )
            }
            ?? settings.displayContext(
                capturedAt: source.capturedAt,
                placeName: fallbackPlaceName,
                timeZoneIdentifier: source.fallbackTimeZoneIdentifier,
                storageMode: storageMode
            )
    }
}
