//
//  CultureLensUITests.swift
//  CultureLensUITests
//
//  Created by 狗带菌 on 2026/7/27.
//

import XCTest

final class CultureLensUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testSampleRecognitionFlow() throws {
        let app = XCUIApplication()
        app.launchArguments.append("-UITesting")
        app.launch()

        let startScan = app.buttons["explore.startScan"]
        XCTAssertTrue(startScan.waitForExistence(timeout: 3))
        startScan.tap()

        let capture = app.buttons["scan.capture"]
        XCTAssertTrue(capture.waitForExistence(timeout: 3))
        capture.tap()

        let sampleImage = app.buttons["scan.useSampleImage"]
        XCTAssertTrue(sampleImage.waitForExistence(timeout: 3))
        sampleImage.tap()

        let confirmFocus = app.buttons["focus.confirm"]
        XCTAssertTrue(confirmFocus.waitForExistence(timeout: 5))
        confirmFocus.tap()

        XCTAssertTrue(app.staticTexts["result.title"].waitForExistence(timeout: 7))

        let save = app.buttons["result.save"]
        for _ in 0..<8 where !save.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(save.waitForExistence(timeout: 3))
        XCTAssertTrue(save.isHittable)
        save.tap()
        XCTAssertTrue(app.staticTexts["已加入扫描历史"].waitForExistence(timeout: 3))
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
