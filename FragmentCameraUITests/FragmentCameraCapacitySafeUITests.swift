import XCTest

/// 実動画の作成・結合・書き出しを行わずに、実機固有の主要導線を確認する。
@MainActor
final class FragmentCameraCapacitySafeUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        let isolatedSelf = UIActorBox(self)
        MainActor.assumeIsolated {
            let testCase = isolatedSelf.value
            testCase.continueAfterFailure = false
            XCUIDevice.shared.orientation = .portrait

            testCase.app = XCUIApplication()
            testCase.app.launchArguments = [
                "-ui-testing",
                "-ui-testing-reset-settings",
                "-ui-testing-disable-stamp-fade"
            ]
            testCase.registerPermissionHandler()
            testCase.app.launch()
            testCase.handlePermissionsIfNeeded()
        }
    }

    override func tearDownWithError() throws {
        let isolatedSelf = UIActorBox(self)
        MainActor.assumeIsolated {
            let testCase = isolatedSelf.value
            XCUIDevice.shared.orientation = .portrait
            testCase.app?.terminate()
            testCase.app = nil
        }
    }

    func testSettingsControlsStampVisibility() throws {
        XCTAssertTrue(app.buttons["capture.settings"].waitForExistence(timeout: 15))
        app.buttons["capture.settings"].tap()
        XCTAssertTrue(element("settings.done").waitForExistence(timeout: 5))

        let storage = element("settings.storage.mode")
        XCTAssertTrue(storage.waitForExistence(timeout: 5))
        storage.buttons["節約"].tap()
        XCTAssertTrue(storage.buttons["節約"].isSelected)
        storage.buttons["標準"].tap()
        XCTAssertTrue(storage.buttons["標準"].isSelected)

        let stampToggle = element("settings.stamp.enabled")
        XCTAssertTrue(scrollToElement(stampToggle))
        let position = element("settings.stamp.position")
        XCTAssertTrue(position.waitForExistence(timeout: 3))

        let stampValueBeforeToggle = String(describing: stampToggle.value ?? "")
        tapSwitch(stampToggle)
        XCTAssertTrue(
            waitUntil(timeout: 3) {
                String(describing: stampToggle.value ?? "") != stampValueBeforeToggle
            },
            "タイムスタンプ表示トグル自体が切り替わりませんでした。"
        )
        if position.exists {
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "stamp-disabled-settings"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            print(app.debugDescription)
        }
        XCTAssertTrue(
            waitUntil(timeout: 3) { !position.exists },
            "スタンプを非表示にしても表示位置が残っています。"
        )
        tapSwitch(stampToggle)
        XCTAssertTrue(position.waitForExistence(timeout: 3))

        let place = element("settings.stamp.element.place")
        XCTAssertTrue(scrollToElement(place))
        place.tap()
        XCTAssertTrue(
            waitUntil(timeout: 3) { (place.value as? String) == "選択中" },
            "場所を選択状態にできませんでした。"
        )
        let preview = element("settings.stamp.preview.text")
        XCTAssertTrue(scrollToElement(preview))
        XCTAssertTrue(preview.label.contains("地名"), "場所を選んでもプレビューへ反映されませんでした。")

        XCTAssertTrue(scrollToElement(place, swipeUp: false))
        place.tap()
        XCTAssertTrue(
            waitUntil(timeout: 3) { (place.value as? String) == "未選択" },
            "場所を未選択状態へ戻せませんでした。"
        )

        let fade = element("settings.stamp.fade")
        XCTAssertTrue(scrollToElement(fade))
        tapSwitch(fade)
        tapSwitch(fade)

        let size = element("settings.stamp.size")
        XCTAssertTrue(scrollToElement(size))
        size.buttons["大"].tap()
        XCTAssertTrue(size.buttons["大"].isSelected)
        size.buttons["中"].tap()
        XCTAssertTrue(size.buttons["中"].isSelected)

        let done = app.buttons["settings.done"].firstMatch
        XCTAssertTrue(done.isHittable)
        done.tap()
        XCTAssertTrue(app.buttons["capture.shutter"].waitForExistence(timeout: 8))
    }

    func testCameraLensesFocusExposureCameraSwitchAndRecovery() throws {
        XCTAssertTrue(waitForCameraReady(), "カメラが撮影可能になりませんでした。")

        let zoomButtons = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "capture.zoom.")
        )
        XCTAssertTrue(
            waitUntil(timeout: 8) { zoomButtons.count >= 3 },
            "iPhone 13 Proの背面レンズ候補が3つ以上表示されませんでした。"
        )
        let backLensIdentifiers = (0..<zoomButtons.count).map {
            zoomButtons.element(boundBy: $0).identifier
        }
        XCTAssertEqual(
            backLensIdentifiers,
            ["capture.zoom.0.5", "capture.zoom.1.0", "capture.zoom.3.0"],
            "iPhone 13 Proの物理レンズに対応する0.5×・1×・3×が正確に表示されていません。"
        )

        for index in 0..<zoomButtons.count {
            let zoom = zoomButtons.element(boundBy: index)
            zoom.tap()
            XCTAssertTrue(
                waitUntil(timeout: 3) { !String(describing: zoom.value ?? "").isEmpty },
                "選んだレンズが選択状態になりませんでした。"
            )
        }

        let torch = app.buttons["capture.torch"]
        XCTAssertTrue(torch.waitForExistence(timeout: 3))
        XCTAssertTrue(torch.isEnabled, "iPhone 13 Proの背面ライトを利用できません。")
        let torchLabel = torch.label
        torch.tap()
        XCTAssertTrue(
            waitUntil(timeout: 3) { torch.label != torchLabel },
            "ライトを点灯状態へ切り替えられませんでした。"
        )
        torch.tap()
        XCTAssertTrue(
            waitUntil(timeout: 3) { torch.label == torchLabel },
            "ライトを消灯状態へ戻せませんでした。"
        )

        let previewPoint = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.38))
        previewPoint.tap()
        let focusIndicator = element("capture.focus.indicator")
        XCTAssertTrue(focusIndicator.waitForExistence(timeout: 2), "タップした位置にフォーカス表示が出ませんでした。")

        previewPoint.press(forDuration: 0.7)
        XCTAssertTrue(
            waitUntil(timeout: 3) { focusIndicator.label.contains("ロック") },
            "長押しでAE/AFロックになりませんでした。"
        )
        let initialExposure = String(describing: focusIndicator.value ?? "")
        previewPoint.press(
            forDuration: 0.1,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.25))
        )
        XCTAssertTrue(
            waitUntil(timeout: 3) {
                String(describing: focusIndicator.value ?? "") != initialExposure
            },
            "上下操作で露出補正値が変化しませんでした。"
        )

        let grid = app.buttons["capture.grid"]
        XCTAssertTrue(grid.waitForExistence(timeout: 3))
        let gridLabel = grid.label
        grid.tap()
        XCTAssertTrue(waitUntil(timeout: 3) { grid.label != gridLabel })
        grid.tap()

        let cameraSwitch = app.buttons["capture.camera.switch"]
        cameraSwitch.tap()
        XCTAssertTrue(
            waitUntil(timeout: 8) { zoomButtons.count == 1 },
            "前面カメラへ切り替わったことをレンズUIで確認できませんでした。"
        )
        cameraSwitch.tap()
        XCTAssertTrue(
            waitUntil(timeout: 8) { zoomButtons.count >= 3 },
            "背面カメラへ戻ったことをレンズUIで確認できませんでした。"
        )

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(waitForCameraReady(timeout: 15), "バックグラウンド復帰後にカメラが再開しませんでした。")
    }

    func testLibraryCalendarClipStampEditorAndDayPlayback() throws {
        XCTAssertTrue(waitForCameraReady(), "カメラが撮影可能になりませんでした。")

        app.buttons["capture.library"].tap()
        XCTAssertTrue(
            app.buttons["library.day.play"].firstMatch.waitForExistence(timeout: 20),
            "ライブラリに動画が表示されませんでした。"
        )

        let calendarOpen = app.buttons["navigation.calendar"]
        XCTAssertTrue(calendarOpen.waitForExistence(timeout: 5))
        calendarOpen.tap()

        let calendarMonth = app.staticTexts["calendar.month"].firstMatch
        XCTAssertTrue(calendarMonth.waitForExistence(timeout: 5))
        XCTAssertTrue(calendarMonth.label.contains("月"), "カレンダーの月表記が日本語になっていません。")

        let calendarDay = app.buttons["calendar.day.recorded"].firstMatch
        XCTAssertTrue(calendarDay.waitForExistence(timeout: 8), "録画のある日がカレンダーに表示されませんでした。")
        calendarDay.tap()
        XCTAssertTrue(app.buttons["library.day.play"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["library.clip.menu"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["calendar.day.back"].tap()
        XCTAssertTrue(calendarMonth.waitForExistence(timeout: 5))

        app.buttons["calendar.back"].tap()

        let dayDetails = app.buttons["library.day.details"].firstMatch
        XCTAssertTrue(dayDetails.waitForExistence(timeout: 5))
        dayDetails.tap()
        let clipMenu = app.buttons["library.clip.menu"].firstMatch
        XCTAssertTrue(clipMenu.waitForExistence(timeout: 5))
        clipMenu.tap()
        let stampEditorButton = app.buttons["library.clip.stamp"].firstMatch
        XCTAssertTrue(stampEditorButton.waitForExistence(timeout: 5))
        stampEditorButton.tap()
        let stampEditorCancel = app.buttons["stampEditor.cancel"].firstMatch
        XCTAssertTrue(stampEditorCancel.waitForExistence(timeout: 5))
        XCTAssertTrue(element("stampEditor.toggle.date").waitForExistence(timeout: 15))
        XCTAssertTrue(element("stampEditor.toggle.time").exists)
        XCTAssertTrue(element("stampEditor.toggle.place").exists)
        XCTAssertTrue(element("stampEditor.caption").exists)
        stampEditorCancel.tap()

        XCTAssertTrue(app.buttons["library.day.play"].waitForExistence(timeout: 8))
        app.buttons["library.day.play"].tap()
        XCTAssertTrue(app.buttons["playback.close"].waitForExistence(timeout: 15))
        if !element("playback.date").exists {
            app.tap()
        }
        XCTAssertTrue(element("playback.item").waitForExistence(timeout: 8))
        XCTAssertTrue(element("playback.date").exists)
        XCTAssertTrue(element("playback.time").exists)
        XCTAssertTrue(element("playback.stamp").waitForExistence(timeout: 8), "再生時のスタンプレイヤーが表示されませんでした。")
        XCTAssertFalse(app.buttons["capture.shutter"].isHittable, "再生中も背面のカメラを操作できる状態です。")
        app.swipeLeft()
        XCTAssertTrue(app.buttons["playback.close"].exists)
        app.buttons["playback.close"].tap()
        // 再生を閉じると、開いていた記録の画面に戻る。
        XCTAssertTrue(
            app.buttons["library.day.play"].waitForExistence(timeout: 12),
            "再生を閉じた後、記録の画面に戻りませんでした。"
        )
    }

    func testPlaybackSwipeChangesExactlyOneBrowsableClip() throws {
        XCTAssertTrue(waitForCameraReady(), "カメラが撮影可能になりませんでした。")
        app.buttons["capture.library"].tap()

        let dayDetails = app.buttons["library.day.details"].firstMatch
        XCTAssertTrue(dayDetails.waitForExistence(timeout: 20), "ライブラリに動画が表示されませんでした。")
        dayDetails.tap()
        let firstClip = app.buttons["library.clip"].firstMatch
        XCTAssertTrue(firstClip.waitForExistence(timeout: 8), "個別動画の一覧を開けませんでした。")
        firstClip.tap()

        XCTAssertTrue(app.buttons["playback.close"].waitForExistence(timeout: 15))
        let playbackItem = element("playback.item")
        let position = element("playback.position")
        if !position.exists {
            app.tap()
        }
        XCTAssertTrue(playbackItem.waitForExistence(timeout: 8))
        XCTAssertTrue(position.waitForExistence(timeout: 8))

        let components = position.label
            .split(separator: "/")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        guard components.count == 2, components[1] > 1 else {
            throw XCTSkip("同じ日にスワイプ確認できる動画が2本以上ありません。")
        }

        let initialItemID = String(describing: playbackItem.value ?? "")
        let initialPosition = position.label
        if components[0] < components[1] {
            app.swipeLeft()
        } else {
            app.swipeRight()
        }

        XCTAssertTrue(
            waitUntil(timeout: 8) {
                String(describing: playbackItem.value ?? "") != initialItemID
                    && position.label != initialPosition
            },
            "スワイプ後に隣の動画へ切り替わりませんでした。"
        )
        XCTAssertTrue(app.buttons["playback.close"].isHittable)
        app.buttons["playback.close"].tap()
        XCTAssertTrue(
            app.buttons["library.clip"].firstMatch.waitForExistence(timeout: 12),
            "再生を閉じた後、1日の詳細に戻りませんでした。"
        )
    }

    func testSettingsAccessibilityAudit() throws {
        XCTAssertTrue(app.buttons["capture.settings"].waitForExistence(timeout: 15))
        app.buttons["capture.settings"].tap()
        XCTAssertTrue(element("settings.done").waitForExistence(timeout: 5))
        try app.performAccessibilityAudit(
            for: [.hitRegion, .sufficientElementDescription, .textClipped]
        )
    }

    func testCaptureAndLibraryAccessibilityAudit() throws {
        XCTAssertTrue(waitForCameraReady())
        try app.performAccessibilityAudit(
            for: [.hitRegion, .sufficientElementDescription, .textClipped]
        )

        app.buttons["capture.library"].tap()
        XCTAssertTrue(app.buttons["library.day.play"].firstMatch.waitForExistence(timeout: 20))
        try app.performAccessibilityAudit(
            for: [.hitRegion, .sufficientElementDescription, .textClipped]
        )
    }

    func testEnglishLocalizationAndSettings() throws {
        app.terminate()
        app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing",
            "-ui-testing-reset-settings",
            "-ui-testing-disable-stamp-fade",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US"
        ]
        app.launch()
        handlePermissionsIfNeeded()

        XCTAssertTrue(app.buttons["capture.settings"].waitForExistence(timeout: 15))
        app.buttons["capture.settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        let stampSwitch = element("settings.stamp.enabled")
        XCTAssertTrue(stampSwitch.waitForExistence(timeout: 5))
        XCTAssertTrue(stampSwitch.label.contains("Add a stamp to your videos"), "設定の文言が英語になっていません。")
        let position = element("settings.stamp.position")
        XCTAssertTrue(scrollToElement(position))
        XCTAssertTrue(position.label.contains("Position"))
        XCTAssertTrue(position.label.contains("Top Right"))

        XCTAssertEqual(element("settings.stamp.element.date").label, "Date")
        XCTAssertEqual(element("settings.stamp.element.time").label, "Time")
        XCTAssertEqual(element("settings.stamp.element.place").label, "Place")
        let dateOrder = element("settings.stamp.dateOrder")
        XCTAssertTrue(scrollToElement(dateOrder))
        XCTAssertTrue(dateOrder.buttons["M D Y"].exists, "日付の順番が英語になっていません。")

        app.buttons["settings.done"].firstMatch.tap()
        XCTAssertTrue(app.buttons["capture.library"].waitForExistence(timeout: 8))
        app.buttons["capture.library"].tap()
        XCTAssertTrue(app.buttons["library.day.play"].firstMatch.waitForExistence(timeout: 20))
        app.buttons["navigation.calendar"].tap()
        let month = app.staticTexts["calendar.month"].firstMatch
        XCTAssertTrue(month.waitForExistence(timeout: 5))
        XCTAssertNotEqual(
            month.label.range(of: "[A-Za-z]+", options: .regularExpression),
            nil,
            "The calendar month was not localized to English."
        )
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func waitForCameraReady(timeout: TimeInterval = 25) -> Bool {
        let shutter = app.buttons["capture.shutter"]
        let start = app.buttons["capture.intro.start"]
        if start.waitForExistence(timeout: 3) {
            start.tap()
            handlePermissionsIfNeeded()
        }
        return waitUntil(timeout: timeout) { shutter.exists && shutter.isEnabled }
    }

    private func scrollToElement(
        _ target: XCUIElement,
        maxSwipes: Int = 8,
        swipeUp: Bool = true
    ) -> Bool {
        if target.exists && target.isHittable { return true }
        for _ in 0..<maxSwipes {
            if swipeUp {
                app.swipeUp()
            } else {
                app.swipeDown()
            }
            if target.exists && target.isHittable { return true }
        }
        return target.exists && target.isHittable
    }

    private func tapSwitch(_ element: XCUIElement) {
        // Form内のToggleは行全体がアクセシビリティ枠になるため、実スイッチ側を押す。
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    }

    private func waitUntil(timeout: TimeInterval, condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return condition()
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

    private func handlePermissionsIfNeeded() {
        for _ in 0..<3 {
            app.tap()
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
    }
}
