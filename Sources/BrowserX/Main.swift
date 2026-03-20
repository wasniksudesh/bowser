// Main.swift - Bowser Application Entry Point
// Swift 6.2 with strict concurrency

import AppKit
import CEFWrapper

/// Application entry point using NSApplicationMain pattern
/// This avoids the need for main.swift or @main attribute issues with AppKit
@main
struct BowserApp {
    static func main() {
        // CRITICAL: Install CEF compatibility methods on NSApplication FIRST
        // CEF requires NSApplication to implement:
        // - isHandlingSendEvent: returns true if sendEvent: is on stack
        // - setHandlingSendEvent: sets the handling state
        // Without this, closing tabs/browsers will crash with:
        // "-[NSApplication isHandlingSendEvent]: unrecognized selector sent to instance"
        //
        // We use method swizzling and extensions to add these methods to the
        // standard NSApplication class, which avoids issues with CEF internally
        // calling [NSApplication sharedApplication] and expecting a specific type.
        installCefApplicationSwizzling()

        // Get the shared application instance (standard NSApplication)
        let app = NSApplication.shared

        // CEF subprocess handling - check if we're a subprocess (GPU, renderer, etc.)
        let frameworkPath = findCEFFrameworkPath()
        if let path = frameworkPath {
            let argc = CommandLine.argc
            let argv = CommandLine.unsafeArgv

            // cef_execute_subprocess returns -1 for browser process (continue startup)
            // or >= 0 for subprocess (exit with that code)
            let exitCode = path.withCString { cString in
                cef_execute_subprocess(Int32(argc), argv, cString)
            }

            if exitCode >= 0 {
                // This is a CEF subprocess, exit with the given code
                exit(exitCode)
            }
            // exitCode == -1 means this is the main browser process, continue
        }

        // Create and set the app delegate
        let delegate = AppDelegate()
        app.delegate = delegate

        // Activate the app (bring to front)
        app.setActivationPolicy(.regular)

        // Run the main event loop
        app.run()
    }

    /// Find the CEF framework path (duplicated from AppDelegate for early access)
    private static func findCEFFrameworkPath() -> String? {
        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        let executableDir = executableURL.deletingLastPathComponent()

        // Priority 1: Check for bundled framework (for built .app)
        // This is at: Bowser.app/Contents/Frameworks/Chromium Embedded Framework.framework
        let bundledFrameworkPath = executableDir.appendingPathComponent(
            "../Frameworks/Chromium Embedded Framework.framework"
        ).path
        let standardizedBundledPath = (bundledFrameworkPath as NSString).standardizingPath
        if FileManager.default.fileExists(atPath: standardizedBundledPath) {
            return standardizedBundledPath
        }

        // Priority 2: Check Bundle.main (alternative bundled location)
        if let bundlePath = Bundle.main.path(
            forResource: "Chromium Embedded Framework", ofType: "framework")
        {
            return bundlePath
        }

        // Priority 3: Development paths (for running from Xcode/.build)
        let devPaths = [
            executableDir.appendingPathComponent(
                "../../Vendor/cef/Release/Chromium Embedded Framework.framework"
            ).path,
            executableDir.appendingPathComponent(
                "../../../Vendor/cef/Release/Chromium Embedded Framework.framework"
            ).path,
            executableDir.appendingPathComponent(
                "../../../../Vendor/cef/Release/Chromium Embedded Framework.framework"
            ).path,
            "./Vendor/cef/Release/Chromium Embedded Framework.framework",
        ]

        for path in devPaths {
            let standardizedPath = (path as NSString).standardizingPath
            if FileManager.default.fileExists(atPath: standardizedPath) {
                return standardizedPath
            }
        }

        return nil
    }
}
