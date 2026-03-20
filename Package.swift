// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.
// Using Swift 6.2 features with macOS 14+

import Foundation
import PackageDescription

// Get the package directory for absolute paths
let packageDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let cefPath = "\(packageDir)/Vendor/cef"
let cefFrameworkPath = "\(cefPath)/Release"
let cefWrapperLibPath = "\(cefPath)/build/libcef_dll_wrapper"

let package = Package(
    name: "Bowser",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Bowser", targets: ["Bowser"]),
        .executable(name: "Bowser Helper", targets: ["BowserHelper"]),
    ],
    dependencies: [],
    targets: [
        // Main executable target
        .executableTarget(
            name: "Bowser",
            dependencies: [
                "CEFWrapper"
            ],
            path: "Sources/Bowser",
            exclude: ["Info.plist"],
            resources: [
                .process("Assets.xcassets"),
                .process("Views/UILibrary/Schemas"),
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ],
            linkerSettings: [
                // Link against the CEF wrapper library
                .unsafeFlags(["-L\(cefWrapperLibPath)", "-lcef_dll_wrapper"]),
                // Required frameworks for CEF
                .linkedFramework("AppKit"),
                .linkedFramework("Cocoa"),
                .linkedFramework("IOSurface"),
                .linkedFramework("Virtualization"),
                .linkedFramework("Network"),
            ]
        ),

        // CEF Wrapper target - C/C++ shim that wraps CEF C++ API
        // Uses libcef_dll_wrapper for proper CEF integration
        .target(
            name: "CEFWrapper",
            path: "Sources/CEFWrapper",
            publicHeadersPath: "include",
            cxxSettings: [
                // Search path for CEF headers
                .headerSearchPath("../../Vendor/cef"),
                // Define to use dynamic loading on macOS
                .define("OS_MAC", to: "1"),
                // Disable exceptions/RTTI to match libcef_dll_wrapper build
                .unsafeFlags(["-fno-exceptions", "-fno-rtti"]),
            ],
            linkerSettings: [
                // Link against libcef_dll_wrapper static library
                .unsafeFlags(["-L\(cefWrapperLibPath)", "-lcef_dll_wrapper"]),
                // Required frameworks
                .linkedFramework("AppKit"),
                .linkedFramework("Cocoa"),
                .linkedFramework("IOSurface"),
                // For tab preview snapshot image resizing
                .linkedFramework("Accelerate"),
            ]
        ),

        // Bowser Helper - Minimal executable for CEF subprocesses (GPU, Renderer, etc.)
        // This is configured with LSUIElement=1 so subprocesses don't appear in the Dock
        .executableTarget(
            name: "BowserHelper",
            dependencies: [
                "CEFWrapper"
            ],
            path: "Sources/BowserHelper",
            exclude: ["Info.plist"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ],
            linkerSettings: [
                // Link against the CEF wrapper library
                .unsafeFlags(["-L\(cefWrapperLibPath)", "-lcef_dll_wrapper"]),
                // Required frameworks for CEF
                .linkedFramework("AppKit"),
                .linkedFramework("Cocoa"),
                .linkedFramework("IOSurface"),
                .linkedFramework("Virtualization"),
                .linkedFramework("Network"),
            ]
        ),

        // Unit tests for Bowser
        .testTarget(
            name: "BowserTests",
            dependencies: ["Bowser"],
            path: "Tests/BowserTests",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
    ],
    cxxLanguageStandard: .cxx17
)
