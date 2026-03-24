// CEFBridgeTests.swift
// Tests the CEF browser engine abstraction layer via MockBrowserEngine.
//
// Feature: CEF / Browser Engine
// Coverage (3 high-signal tests):
//   1. MockBrowserEngine fully satisfies BrowserEngineProtocol at compile time
//      and tracks init/shutdown lifecycle correctly.
//   2. Browser creation → navigation → destruction: all method calls are
//      recorded and state is correct.
//   3. State-query methods (canGoBack, canGoForward, isLoading, currentURL)
//      return the configurable mock values.

import XCTest
import BowserTestSupport

@MainActor
final class CEFBridgeTests: XCTestCase {

    // MARK: - Test 1: Protocol conformance + lifecycle

    /// Verifies that MockBrowserEngine implements BrowserEngineProtocol and
    /// that initialize() / shutdown() update tracked state correctly.
    func testMockBrowserEngine_lifecycleTracking() async {
        let engine = MockBrowserEngine()

        XCTAssertFalse(engine.isInitialized, "Should not be initialized yet")
        XCTAssertFalse(engine.initializeCalled)
        XCTAssertFalse(engine.shutdownCalled)

        let initialized = await engine.initialize()

        XCTAssertTrue(initialized, "Initialization should succeed")
        XCTAssertTrue(engine.isInitialized)
        XCTAssertTrue(engine.initializeCalled)

        await engine.shutdown()

        XCTAssertTrue(engine.shutdownCalled)
        XCTAssertFalse(engine.isInitialized, "Should not be initialized after shutdown")
    }

    // MARK: - Test 2: Browser creation, navigation, destruction

    /// Verifies that createBrowser records the ID, navigate appends URLs,
    /// and destroyBrowser removes the browser from the engine's internal map.
    func testMockBrowserEngine_browserCreateNavigateDestroy() async {
        let engine = MockBrowserEngine()
        _ = await engine.initialize()

        let browserID = UUID()
        let initialURL = URL(string: "https://example.com")!

        // Create
        let handle = await engine.createBrowser(id: browserID, url: initialURL, delegate: nil)
        XCTAssertNotNil(handle, "createBrowser must return a handle")
        XCTAssertTrue(engine.createdBrowsers.contains(browserID))

        // Navigate to a second URL
        let secondURL = URL(string: "https://swift.org")!
        await engine.navigate(handle!, to: secondURL)

        let visited = engine.navigatedURLs[browserID] ?? []
        XCTAssertEqual(visited.count, 2, "Should have initial URL + navigate URL")
        XCTAssertEqual(visited.last, secondURL)

        // Destroy
        await engine.destroyBrowser(handle!)
        XCTAssertTrue(engine.destroyedBrowsers.contains(browserID))

        // After destruction, getNativeView returns nil
        let view = engine.getNativeView(for: handle!)
        XCTAssertNil(view, "View should be nil after browser is destroyed")
    }

    // MARK: - Test 3: State-query configuration

    /// Verifies that canGoBack, canGoForward, isLoading, and currentURL all
    /// reflect the values set on MockBrowserEngine's configurable properties.
    func testMockBrowserEngine_stateQueriesReturnConfiguredValues() async {
        let engine = MockBrowserEngine()
        _ = await engine.initialize()

        let id = UUID()
        let handle = await engine.createBrowser(
            id: id,
            url: URL(string: "https://start.example.com")!,
            delegate: nil
        )!

        // Default state
        XCTAssertFalse(engine.canGoBack(handle))
        XCTAssertFalse(engine.canGoForward(handle))
        XCTAssertFalse(engine.isLoading(handle))

        // Configure mock state
        engine.mockCanGoBack = true
        engine.mockCanGoForward = true
        engine.mockIsLoading = true
        engine.mockCurrentURL = URL(string: "https://configured.example.com")!

        XCTAssertTrue(engine.canGoBack(handle))
        XCTAssertTrue(engine.canGoForward(handle))
        XCTAssertTrue(engine.isLoading(handle))
        XCTAssertEqual(engine.currentURL(handle), URL(string: "https://configured.example.com")!)
    }
}
