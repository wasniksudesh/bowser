// CEF Shim Header - Pure C Interface
// Exposes only C-callable functions to Swift, hiding all CEF C++ headers

#pragma once

#include <stddef.h> // For size_t

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// MARK: - Subprocess Handling
// =============================================================================

// Execute subprocess if this is a CEF subprocess (GPU, renderer, etc.)
// Must be called very early in main(), before any CEF initialization
// argc, argv: Command line arguments from main()
// framework_path: Path to "Chromium Embedded Framework.framework" directory
// Returns:
//   -1 if this is the main browser process (continue with normal startup)
//   >= 0 if this is a subprocess (exit with this code)
int cef_execute_subprocess(int argc, char **argv, const char *framework_path);

// =============================================================================
// MARK: - Initialization
// =============================================================================

// Simplified initialization wrapper
// framework_path: Path to "Chromium Embedded Framework.framework" directory
// Returns 1 on success, 0 on failure
int cef_simple_initialize_with_path(const char *framework_path);

// Legacy initialization (tries to find framework automatically)
// Returns 1 on success, 0 on failure
int cef_simple_initialize(void);

// Shutdown CEF
void cef_simple_shutdown(void);

// Message loop work (for integration with app's run loop)
// Returns 1 if work was done, 0 otherwise
int cef_do_message_work(void);

// =============================================================================
// MARK: - Browser Management
// =============================================================================

// Opaque handle to a browser instance
typedef void *CefBrowserHandle;

// Create a browser with a parent NSView
// parent_view: NSView* cast to void*
// url: Initial URL to load
// width, height: Initial size
// disable_swipe_navigation: 1 to disable trackpad swipe gestures for
// back/forward, 0 to enable Returns browser handle on success, NULL on failure
CefBrowserHandle cef_create_browser(void *parent_view, const char *url,
                                    int width, int height,
                                    int disable_swipe_navigation);

// Destroy a browser instance
void cef_destroy_browser(CefBrowserHandle handle);

// Get the browser's NSView for embedding
// Returns NSView* cast to void*
void *cef_get_browser_view(CefBrowserHandle handle);

// =============================================================================
// MARK: - Navigation
// =============================================================================

// Navigate to a URL
void cef_navigate_to_url(CefBrowserHandle handle, const char *url);

// Navigate back
void cef_go_back(CefBrowserHandle handle);

// Navigate forward
void cef_go_forward(CefBrowserHandle handle);

// Reload the page
void cef_reload(CefBrowserHandle handle);

// Stop loading
void cef_stop_loading(CefBrowserHandle handle);

// Execute JavaScript code in the browser
void cef_execute_javascript(CefBrowserHandle handle, const char *code);

// =============================================================================
// MARK: - Editing Commands
// =============================================================================

// Copy selected text to clipboard
void cef_copy(CefBrowserHandle handle);

// Cut selected text to clipboard
void cef_cut(CefBrowserHandle handle);

// Paste from clipboard
void cef_paste(CefBrowserHandle handle);

// Select all text
void cef_select_all(CefBrowserHandle handle);

// Undo last action
void cef_undo(CefBrowserHandle handle);

// Redo last undone action
void cef_redo(CefBrowserHandle handle);

// Print the page
void cef_print(CefBrowserHandle handle);

// =============================================================================
// MARK: - Browser State
// =============================================================================

// Check if browser can go back
int cef_can_go_back(CefBrowserHandle handle);

// Check if browser can go forward
int cef_can_go_forward(CefBrowserHandle handle);

// Check if browser is loading
int cef_is_loading(CefBrowserHandle handle);

// Get loading progress (0.0 to 1.0)
double cef_get_loading_progress(CefBrowserHandle handle);

// =============================================================================
// MARK: - View Management
// =============================================================================

// Resize the browser view
void cef_resize_browser(CefBrowserHandle handle, int width, int height);

// Notify browser that a move or resize operation has started
// Call this when the parent window or view begins resizing
// This allows CEF to optimize rendering during the resize
void cef_notify_move_or_resize_started(CefBrowserHandle handle);

// Set focus to the browser
void cef_set_focus(CefBrowserHandle handle, int focus);

// =============================================================================
// MARK: - Data Management
// =============================================================================

// Delete cookies
// url: The URL to delete cookies for (NULL for all)
// cookie_name: The name of the cookie to delete (NULL for all)
void cef_delete_cookies(const char *url, const char *cookie_name);

// -----------------------------------------------------------------------------
// Zoom Management
// -----------------------------------------------------------------------------

// Set the zoom level for the browser
// 0.0 is 100%, negative is smaller, positive is larger
// Each step of 1.0 is ~20% change (e.g. 1.2 is 120%)
void cef_set_zoom_level(CefBrowserHandle handle, double zoom_level);

// Get the current zoom level for the browser
double cef_get_zoom_level(CefBrowserHandle handle);

// =============================================================================
// MARK: - Callbacks (Swift -> C -> CEF)
// =============================================================================

// Callback type definitions for CEF events
// IMPORTANT: These callbacks are invoked on the CEF UI thread (background
// thread) Swift code MUST dispatch to MainActor before updating any UI state

// Called when browser loading state changes
// is_loading: 1 if loading, 0 if complete
// can_go_back: 1 if browser can navigate back, 0 otherwise
// can_go_forward: 1 if browser can navigate forward, 0 otherwise
// url: The URL being loaded (may be empty string)
typedef void (*CefLoadStateCallback)(CefBrowserHandle handle, int is_loading,
                                     int can_go_back, int can_go_forward,
                                     const char *url);

// Called when page title changes
// title: The new page title (may be empty string for blank pages)
typedef void (*CefTitleChangeCallback)(CefBrowserHandle handle,
                                       const char *title);

// Called when URL changes (navigation)
// url: The new URL
typedef void (*CefUrlChangeCallback)(CefBrowserHandle handle, const char *url);

// Called when favicon URL changes
// favicon_url: The URL of the favicon (best candidate from available icons)
// May be empty string if no favicon is available
typedef void (*CefFaviconUrlChangeCallback)(CefBrowserHandle handle,
                                            const char *favicon_url);

// Called when a tab preview snapshot is ready (Capture-on-Load strategy)
// This is called automatically ~500ms after page load completes
// buffer: RGBA pixel data (4 bytes per pixel)
// width: Image width in pixels
// height: Image height in pixels
// buffer_size: Total buffer size in bytes
// The buffer is only valid during the callback - copy data if needed
typedef void (*CefSnapshotReadyCallback)(CefBrowserHandle handle,
                                         const void *buffer, int width,
                                         int height, size_t buffer_size);

// Called when user selects "Open Link as Child Tab" from context menu
// url: The URL of the link that was right-clicked
// This allows Swift to create a new child tab with the current tab as parent
typedef void (*CefOpenLinkAsChildTabCallback)(CefBrowserHandle handle,
                                              const char *url);

// Called when a website requests camera/microphone access
// requesting_origin: The URL origin requesting permission (e.g.,
// "https://example.com") requested_permissions: Bitfield of requested
// permissions:
//   1 (0x01) = CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE (microphone)
//   2 (0x02) = CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE (camera)
//   3 (0x03) = Both audio and video
// Swift must call cef_respond_to_media_permission() with the user's decision
typedef void (*CefMediaPermissionRequestCallback)(CefBrowserHandle handle,
                                                  const char *requesting_origin,
                                                  int requested_permissions);

// Called when user clicks a link (before navigation)
// url: The URL of the link that was clicked
// Returns: 1 to allow navigation (default), 0 to cancel navigation
// Use this to intercept link clicks for stack mode
typedef int (*CefLinkClickCallback)(CefBrowserHandle handle, const char *url);

// Register callbacks for browser events
// Must be called after cef_create_browser
// All callbacks may be NULL if not needed
void cef_register_callbacks(
    CefBrowserHandle handle, CefLoadStateCallback load_state_callback,
    CefTitleChangeCallback title_change_callback,
    CefUrlChangeCallback url_change_callback,
    CefFaviconUrlChangeCallback favicon_url_change_callback,
    CefSnapshotReadyCallback snapshot_ready_callback,
    CefOpenLinkAsChildTabCallback open_link_as_child_tab_callback,
    CefMediaPermissionRequestCallback media_permission_request_callback,
    CefLinkClickCallback link_click_callback);

// Unregister callbacks for a browser (called automatically by
// cef_destroy_browser)
void cef_unregister_callbacks(CefBrowserHandle handle);

// =============================================================================
// MARK: - Tab Preview Snapshot
// =============================================================================

// Callback type for receiving snapshot data
// buffer: RGBA pixel data (4 bytes per pixel, top-to-bottom, left-to-right)
// width: Image width in pixels
// height: Image height in pixels
// buffer_size: Total buffer size in bytes (width * height * 4)
// The buffer is only valid during the callback - copy data if needed
typedef void (*CefSnapshotCallback)(const void *buffer, int width, int height,
                                    size_t buffer_size);

// Capture a snapshot of the browser's current view
// The snapshot is resized to thumbnail dimensions (max_width) to save memory
// Callback is invoked on the main thread with RGBA pixel data
// max_width: Maximum width of the thumbnail (height scales proportionally)
// Returns 1 if capture started, 0 on failure
int cef_capture_snapshot(CefBrowserHandle handle, int max_width,
                         CefSnapshotCallback callback);

// =============================================================================
// MARK: - Media Permissions
// =============================================================================

// Respond to a media permission request from a website
// This must be called in response to a CefMediaPermissionRequestCallback
// handle: The browser handle from the callback
// allowed_permissions: Bitfield of allowed permissions:
//   0 = Deny all permissions
//   1 (0x01) = Allow microphone (CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE)
//   2 (0x02) = Allow camera (CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE)
//   3 (0x03) = Allow both microphone and camera
void cef_respond_to_media_permission(CefBrowserHandle handle,
                                     int allowed_permissions);

// =============================================================================
// MARK: - Extension Management
// =============================================================================

// Extension callbacks
typedef void (*CefExtensionLoadedCallback)(const char *extension_json);
typedef void (*CefExtensionLoadFailedCallback)(const char *path,
                                               int error_code);
typedef void (*CefExtensionUnloadedCallback)(const char *extension_id);

// Register extension callbacks
void cef_register_extension_callbacks(
    CefExtensionLoadedCallback loaded_callback,
    CefExtensionLoadFailedCallback load_failed_callback,
    CefExtensionUnloadedCallback unloaded_callback);

// Load an extension from a directory path
// path: Absolute path to the extension directory containing manifest.json
void cef_load_extension(const char *path);

// Unload an extension by ID
// extension_id: The unique ID of the extension to unload
void cef_unload_extension(const char *extension_id);

// Get the number of loaded extensions
int cef_get_extension_count(void);

// Get extension info as JSON array
// Returns a JSON string containing array of extension objects
// Caller must free the returned string using cef_free_string
const char *cef_get_extension_info_json(void);

// Free a string returned by CEF functions
void cef_free_string(const char *str);

#ifdef __cplusplus
}
#endif
