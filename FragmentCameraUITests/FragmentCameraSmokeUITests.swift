import XCTest

final class FragmentCameraSmokeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait

        app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-ui-testing-reset-settings",
            "-ui-testing-disable-stamp-fade"
        ]
        registerPermissionHandler()
        app.launch()
        handleOnboardingAndPermissions()
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
        app?.terminate()
        app = nil
    }

    /// 13 Proの背面3レンズと、横向き＋節約モードを合計4秒だけ実撮影する。
    func testCaptureEachBackLensLandscapeCompactSaveLibraryAndPlayback() throws {
        let shutter = app.buttons["capture.shutter"]
        XCTAssertTrue(
            waitUntil(shutter, matches: NSPredicate(format: "exists == true AND enabled == true"), timeout: 25),
            "カメラが撮影可能になりませんでした。権限、端末ロック、またはカメラ初期化を確認してください。"
        )

        let oneSecond = app.buttons["capture.duration.1"]
        XCTAssertTrue(oneSecond.waitForExistence(timeout: 5), "1秒の撮影時間を選べませんでした。")
        oneSecond.tap()

        let library = app.buttons["capture.library"]
        XCTAssertTrue(library.waitForExistence(timeout: 5), "日別ライブラリボタンを確認できませんでした。")

        let expectedBackLenses = [
            "capture.zoom.0.5",
            "capture.zoom.1.0",
            "capture.zoom.3.0"
        ]
        for identifier in expectedBackLenses {
            let lens = app.buttons[identifier]
            XCTAssertTrue(lens.waitForExistence(timeout: 8), "\(identifier)を選べませんでした。")
            lens.tap()
            XCTAssertTrue(
                waitUntil(
                    lens,
                    matches: NSPredicate(format: "value != ''"),
                    timeout: 3
                ),
                "\(identifier)が選択状態になりませんでした。"
            )
            try captureOneSecond(shutter: shutter, library: library)
        }

        XCTAssertTrue(app.buttons["capture.settings"].waitForExistence(timeout: 8))
        app.buttons["capture.settings"].tap()
        let orientation = app.descendants(matching: .any)["settings.capture.orientation"]
        XCTAssertTrue(orientation.waitForExistence(timeout: 5))
        orientation.buttons["横"].tap()
        XCTAssertTrue(
            waitUntil(timeout: 8) { self.app.frame.width > self.app.frame.height },
            "横向き撮影画面へ切り替わりませんでした。"
        )
        let storage = app.descendants(matching: .any)["settings.storage.mode"]
        XCTAssertTrue(storage.waitForExistence(timeout: 5))
        storage.buttons["節約"].tap()
        XCTAssertTrue(storage.buttons["節約"].isSelected)
        app.buttons["settings.done"].firstMatch.tap()

        XCTAssertTrue(
            waitUntil(
                shutter,
                matches: NSPredicate(format: "exists == true AND enabled == true"),
                timeout: 20
            )
        )
        let oneX = app.buttons["capture.zoom.1.0"]
        XCTAssertTrue(oneX.waitForExistence(timeout: 5))
        oneX.tap()
        try captureOneSecond(shutter: shutter, library: library)

        library.tap()

        let dayDetails = app.buttons["library.day.details"].firstMatch
        XCTAssertTrue(
            dayDetails.waitForExistence(timeout: 20),
            "撮影した日がライブラリに反映されませんでした。"
        )
        dayDetails.tap()
        let firstClip = app.buttons["library.clip"].firstMatch
        XCTAssertTrue(
            firstClip.waitForExistence(timeout: 8),
            "撮影した動画の一覧を開けませんでした。"
        )
        firstClip.tap()

        let playbackClose = app.buttons["playback.close"]
        XCTAssertTrue(
            playbackClose.waitForExistence(timeout: 15),
            "単体動画の再生画面を開けませんでした。"
        )
        playbackClose.tap()

        XCTAssertTrue(
            app.buttons["capture.shutter"].waitForExistence(timeout: 8),
            "再生画面からカメラへ戻れませんでした。"
        )
    }

    private func captureOneSecond(
        shutter: XCUIElement,
        library: XCUIElement
    ) throws {
        let clipCountBeforeCapture = library.label
        shutter.tap()

        XCTAssertTrue(
            waitUntil(
                library,
                matches: NSPredicate(format: "label != %@", clipCountBeforeCapture),
                timeout: 35
            ),
            "撮影した動画が今日の一覧へ反映されませんでした。"
        )
        XCTAssertTrue(
            waitUntil(
                shutter,
                matches: NSPredicate(
                    format: "enabled == true AND (label CONTAINS %@ OR label CONTAINS[c] %@)",
                    "開始",
                    "record"
                ),
                timeout: 35
            ),
            "撮影後の保存処理が完了しませんでした。"
        )
    }

    private func registerPermissionHandler() {
        addUIInterruptionMonitor(withDescription: "System permissions") { alert in
            let affirmativeButtons = [
                "フルアクセスを許可",
                "すべての写真へのアクセスを許可",
                "写真を選択…",
                "許可",
                "Allow Full Access",
                "Allow Access to All Photos",
                "Allow While Using App",
                "Allow"
            ]

            for title in affirmativeButtons where alert.buttons[title].exists {
                alert.buttons[title].tap()
                return true
            }
            return false
        }
    }

    private func handleOnboardingAndPermissions() {
        let start = app.buttons["capture.intro.start"]
        if start.waitForExistence(timeout: 3) {
            start.tap()
        }

        // Interruption monitors run after an interaction with the app. Repeat to
        // handle camera, microphone, photo library and location prompts in order.
        for _ in 0..<5 {
            app.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        }
    }

    private func waitUntil(
        _ element: XCUIElement,
        matches predicate: NSPredicate,
        timeout: TimeInterval
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return condition()
    }
}
