// CefApplication.swift - Custom NSApplication for CEF Integration
// Required by CEF for proper macOS event loop integration
// See: Vendor/cef/include/cef_application_mac.h

import AppKit
import ObjectiveC

// =============================================================================
// MARK: - CEF Application Protocol Support
// =============================================================================

/// Storage key for the handlingSendEvent state using associated objects
/// This allows us to add state to NSApplication without subclassing
/// Using nonisolated(unsafe) because this is just a key address, not mutable state
nonisolated(unsafe) private var handlingSendEventKey: UInt8 = 0

/// Extension to add CEF-required protocol methods to NSApplication.
///
/// CEF (Chromium Embedded Framework) requires macOS applications to implement
/// the `CrAppControlProtocol` which includes:
/// - `isHandlingSendEvent`: returns true if sendEvent: is on stack
/// - `setHandlingSendEvent:`: sets the handling state
///
/// Instead of subclassing NSApplication (which causes issues when CEF internally
/// calls `[NSApplication sharedApplication]`), we add these methods via extension
/// using Objective-C associated objects for storage.
///
/// Without these methods, the app will crash with:
/// `-[NSApplication isHandlingSendEvent]: unrecognized selector sent to instance`
extension NSApplication {
    
    /// Tracks whether -[NSApplication sendEvent:] is currently on the stack.
    /// CEF uses this to coordinate event handling between Chromium and AppKit.
    private var _cef_handlingSendEvent: Bool {
        get {
            return objc_getAssociatedObject(self, &handlingSendEventKey) as? Bool ?? false
        }
        set {
            objc_setAssociatedObject(self, &handlingSendEventKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    // MARK: - CrAppProtocol
    
    /// Returns true if -[NSApplication sendEvent:] is currently on the stack.
    /// Required by CEF's CrAppProtocol for proper event coordination.
    /// 
    /// Note: This is exposed as an Objective-C method so CEF can call it.
    @objc var isHandlingSendEvent: Bool {
        return _cef_handlingSendEvent
    }
    
    // MARK: - CrAppControlProtocol
    
    /// Sets the handling send event state.
    /// Called by CEF's CefScopedSendingEvent to track event processing.
    ///
    /// Note: This is exposed as an Objective-C method so CEF can call it.
    @objc func setHandlingSendEvent(_ handlingSendEvent: Bool) {
        _cef_handlingSendEvent = handlingSendEvent
    }
}

// =============================================================================
// MARK: - Method Swizzling for sendEvent:
// =============================================================================

/// Swizzle NSApplication's sendEvent: to track event handling state.
/// This must be called once at app startup, before any events are processed.
func installCefApplicationSwizzling() {
    let originalSelector = #selector(NSApplication.sendEvent(_:))
    let swizzledSelector = #selector(NSApplication.cef_sendEvent(_:))
    
    guard let originalMethod = class_getInstanceMethod(NSApplication.self, originalSelector),
          let swizzledMethod = class_getInstanceMethod(NSApplication.self, swizzledSelector) else {
        print("[CefApplication] WARNING: Failed to swizzle sendEvent:")
        return
    }
    
    method_exchangeImplementations(originalMethod, swizzledMethod)
    print("[CefApplication] Installed sendEvent: swizzling for CEF compatibility")
}

extension NSApplication {
    /// Swizzled sendEvent: that tracks event handling state for CEF.
    @objc func cef_sendEvent(_ event: NSEvent) {
        // Save the previous state for nested calls
        let wasHandling = _cef_handlingSendEvent
        _cef_handlingSendEvent = true
        
        defer {
            _cef_handlingSendEvent = wasHandling
        }
        
        // Call the original implementation (which is now swapped to this selector)
        cef_sendEvent(event)
    }
}
