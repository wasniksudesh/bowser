// HelperMain.swift - Bowser Helper App Entry Point
// This is a minimal entry point for CEF subprocess handling (GPU, Renderer, etc.)
// This binary should be launched by CEF, not by users directly.

import CEFWrapper
import Foundation

/// Helper app entry point - only handles CEF subprocess execution
/// This binary is configured with LSUIElement=1 so it doesn't appear in the Dock
@main
struct BowserHelper {
  static func main() {
    // Find the CEF framework path
    let frameworkPath = findCEFFrameworkPath()

    guard let path = frameworkPath else {
      // If we can't find CEF, exit silently
      exit(1)
    }

    // Execute CEF subprocess - this will handle GPU, Renderer, etc.
    let argc = CommandLine.argc
    let argv = CommandLine.unsafeArgv

    let exitCode = path.withCString { cString in
      cef_execute_subprocess(Int32(argc), argv, cString)
    }

    // Exit with the code returned by CEF
    exit(exitCode)
  }

  /// Find the CEF framework path relative to the Helper app location
  private static func findCEFFrameworkPath() -> String? {
    let executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    let executableDir = executableURL.deletingLastPathComponent()

    // Helper is at: Bowser.app/Contents/Frameworks/Bowser Helper.app/Contents/MacOS/Bowser Helper
    // CEF Framework is at: Bowser.app/Contents/Frameworks/Chromium Embedded Framework.framework
    // So we need to go up 4 levels from MacOS to get to Frameworks
    let possiblePaths = [
      // From Helper.app inside Frameworks folder
      executableDir.appendingPathComponent(
        "../../../../Frameworks/Chromium Embedded Framework.framework"
      ).path,
      // Direct sibling in Frameworks folder
      executableDir.appendingPathComponent("../../../Chromium Embedded Framework.framework").path,
      // Development paths
      executableDir.appendingPathComponent(
        "../../Vendor/cef/Release/Chromium Embedded Framework.framework"
      ).path,
      executableDir.appendingPathComponent(
        "../../../Vendor/cef/Release/Chromium Embedded Framework.framework"
      ).path,
      executableDir.appendingPathComponent(
        "../../../../Vendor/cef/Release/Chromium Embedded Framework.framework"
      ).path,
      executableDir.appendingPathComponent(
        "../../../../../Vendor/cef/Release/Chromium Embedded Framework.framework"
      ).path,
      "./Vendor/cef/Release/Chromium Embedded Framework.framework",
    ]

    for path in possiblePaths {
      let standardizedPath = (path as NSString).standardizingPath
      if FileManager.default.fileExists(atPath: standardizedPath) {
        return standardizedPath
      }
    }

    return nil
  }
}
