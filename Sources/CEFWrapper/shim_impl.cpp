// CEF Shim Implementation
// Uses the libcef_dll_wrapper library for proper CEF integration
// This provides C wrappers around CEF C++ API for Swift interoperability

#include "include/cef_shim.h"

// CEF C++ API headers
#include "include/cef_app.h"
#include "include/cef_browser.h"
#include "include/cef_browser_process_handler.h"
#include "include/cef_client.h"
#include "include/cef_command_line.h"
#include "include/cef_context_menu_handler.h"
#include "include/cef_cookie.h"
#include "include/cef_display_handler.h"
#include "include/cef_life_span_handler.h"
#include "include/cef_load_handler.h"
#include "include/cef_permission_handler.h"
#include "include/cef_request_context.h"
#include "include/cef_request_context_handler.h"
#include "include/cef_request_handler.h"
#include "include/wrapper/cef_helpers.h"
#include "include/wrapper/cef_library_loader.h"

#include <map>
#include <mutex>
#include <stdio.h>
#include <string.h>
#include <string>

// macOS-specific headers
#include <limits.h>
#include <mach-o/dyld.h>

#if defined(__APPLE__)
#include <Accelerate/Accelerate.h>
#include <CoreGraphics/CoreGraphics.h>
#include <dispatch/dispatch.h>
#include <objc/message.h>
#include <objc/objc.h>
#include <objc/runtime.h>
#endif

// Forward declarations for callback storage
struct BrowserCallbacks;
extern std::map<CefBrowserHandle, BrowserCallbacks> g_callbacks;
extern std::mutex g_callbacks_mutex;

// =============================================================================
// MARK: - Callback Storage
// =============================================================================

// Callback storage for browser events
struct BrowserCallbacks {
  CefLoadStateCallback load_state_callback = nullptr;
  CefTitleChangeCallback title_change_callback = nullptr;
  CefUrlChangeCallback url_change_callback = nullptr;
  CefFaviconUrlChangeCallback favicon_url_change_callback = nullptr;
  CefSnapshotReadyCallback snapshot_ready_callback = nullptr;
  CefOpenLinkAsChildTabCallback open_link_as_child_tab_callback = nullptr;
  CefMediaPermissionRequestCallback media_permission_request_callback = nullptr;
  CefLinkClickCallback link_click_callback = nullptr;
  CefBrowserHandle handle = nullptr;
};

std::map<CefBrowserHandle, BrowserCallbacks> g_callbacks;
std::mutex g_callbacks_mutex;

// Storage for pending media permission callbacks
// When a website requests media access, we store the CEF callback here
// until Swift provides the user's decision
std::map<CefBrowserHandle, CefRefPtr<CefMediaAccessCallback>>
    g_pending_permission_callbacks;
std::mutex g_pending_permission_mutex;

// =============================================================================
// MARK: - Simple Client Implementation
// =============================================================================

// Forward declare BrowserWrapper so SimpleClient can store a back-pointer
struct BrowserWrapper;

// CefClient implementation with CefDisplayHandler and CefLoadHandler for
// browser instances This class receives callbacks from CEF and forwards them to
// Swift via registered C callbacks
class SimpleClient : public CefClient,
                     public CefLifeSpanHandler,
                     public CefLoadHandler,
                     public CefDisplayHandler,
                     public CefContextMenuHandler,
                     public CefPermissionHandler,
                     public CefRequestHandler {
public:
  explicit SimpleClient(BrowserWrapper *wrapper)
      : wrapper_(wrapper), snapshot_timer_id_(0) {}

  // CefClient methods - return handlers
  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override { return this; }
  CefRefPtr<CefLoadHandler> GetLoadHandler() override { return this; }
  CefRefPtr<CefDisplayHandler> GetDisplayHandler() override { return this; }
  CefRefPtr<CefContextMenuHandler> GetContextMenuHandler() override {
    return this;
  }
  CefRefPtr<CefPermissionHandler> GetPermissionHandler() override {
    fprintf(stderr, "[CEF] GetPermissionHandler called\n");
    return this;
  }
  CefRefPtr<CefRequestHandler> GetRequestHandler() override { return this; }

  // =========================================================================
  // CefLifeSpanHandler methods
  // =========================================================================

  void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
    fprintf(stderr, "[CEF] Browser created: %d\n", browser->GetIdentifier());
    browser_ = browser;
  }

  bool DoClose(CefRefPtr<CefBrowser> browser) override {
    fprintf(stderr, "[CEF] Browser closing: %d\n", browser->GetIdentifier());
    return false; // Allow the close
  }

  void OnBeforeClose(CefRefPtr<CefBrowser> browser) override {
    fprintf(stderr, "[CEF] Browser closed: %d\n", browser->GetIdentifier());
    browser_ = nullptr;
  }

  // =========================================================================
  // CefLoadHandler methods
  // =========================================================================

  void OnLoadStart(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                   TransitionType transition_type) override {
    if (frame->IsMain()) {
      std::string url = frame->GetURL().ToString();
      fprintf(stderr, "[CEF] Load started: %s\n", url.c_str());

      // Invoke Swift callback for load state change (isLoading = true)
      bool canGoBack = browser->CanGoBack();
      bool canGoForward = browser->CanGoForward();
      InvokeLoadStateCallback(true, canGoBack, canGoForward, url);
    }
  }

  void OnLoadEnd(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                 int httpStatusCode) override;

  void OnLoadError(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                   ErrorCode errorCode, const CefString &errorText,
                   const CefString &failedUrl) override {
    if (frame->IsMain()) {
      std::string url = failedUrl.ToString();
      fprintf(stderr, "[CEF] Load error: %s - %s\n", url.c_str(),
              errorText.ToString().c_str());

      // On error, also signal load complete (isLoading = false)
      bool canGoBack = browser->CanGoBack();
      bool canGoForward = browser->CanGoForward();
      InvokeLoadStateCallback(false, canGoBack, canGoForward, url);
    }
  }

  // CefLoadHandler: OnLoadingStateChange - called when loading state changes
  // This is the authoritative callback for isLoading state
  // CAPTURE-ON-LOAD STRATEGY: When loading completes, we schedule a debounced
  // snapshot
  void OnLoadingStateChange(CefRefPtr<CefBrowser> browser, bool isLoading,
                            bool canGoBack, bool canGoForward) override {
    CefRefPtr<CefFrame> frame = browser->GetMainFrame();
    std::string url = frame ? frame->GetURL().ToString() : "";

    fprintf(stderr,
            "[CEF] Loading state changed: isLoading=%d, canGoBack=%d, "
            "canGoForward=%d, url=%s\n",
            isLoading, canGoBack, canGoForward, url.c_str());

    // Invoke Swift callback for load state change (with navigation state)
    InvokeLoadStateCallback(isLoading, canGoBack, canGoForward, url);

    // CAPTURE-ON-LOAD: When loading finishes, schedule a debounced snapshot
    // capture This ensures we capture after:
    // 1. All iframes have loaded (multiple load events)
    // 2. JavaScript has had time to render
    // 3. The visual content is actually painted
    if (!isLoading) {
      ScheduleDebouncedSnapshot();
    } else {
      // Loading started - cancel any pending snapshot
      CancelPendingSnapshot();
    }
  }

  // =========================================================================
  // CefDisplayHandler methods
  // =========================================================================

  void OnTitleChange(CefRefPtr<CefBrowser> browser,
                     const CefString &title) override {
    std::string titleStr = title.ToString();
    fprintf(stderr, "[CEF] Title changed: %s\n", titleStr.c_str());

    // Invoke Swift callback for title change
    InvokeTitleChangeCallback(titleStr);
  }

  void OnAddressChange(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                       const CefString &url) override {
    if (frame->IsMain()) {
      std::string urlStr = url.ToString();
      fprintf(stderr, "[CEF] Address changed: %s\n", urlStr.c_str());

      // Invoke Swift callback for URL change
      InvokeUrlChangeCallback(urlStr);
    }
  }

  // CefDisplayHandler: OnFaviconURLChange - called when favicon URLs are
  // available
  void OnFaviconURLChange(CefRefPtr<CefBrowser> browser,
                          const std::vector<CefString> &icon_urls) override {
    // fprintf(stderr, "[CEF] Favicon URLs changed, count: %zu\n",
    //         icon_urls.size());

    if (icon_urls.empty()) {
      // No favicon available - pass empty string to trigger fallback
      InvokeFaviconUrlChangeCallback("");
      return;
    }

    // Select the best favicon candidate:
    // 1. Prefer .png files
    // 2. Prefer larger sizes (look for size hints in URL)
    // 3. Fall back to first URL
    std::string best_url = icon_urls[0].ToString();
    int best_score = 0;

    for (const auto &icon_url : icon_urls) {
      std::string url_str = icon_url.ToString();
      int score = 0;

      // Prefer PNG format (usually higher quality)
      if (url_str.find(".png") != std::string::npos) {
        score += 10;
      }

      // Prefer larger sizes (look for size hints like 32x32, 64x64, etc.)
      if (url_str.find("64") != std::string::npos ||
          url_str.find("128") != std::string::npos ||
          url_str.find("256") != std::string::npos) {
        score += 5;
      } else if (url_str.find("32") != std::string::npos) {
        score += 3;
      }

      // Prefer apple-touch-icon (usually high quality)
      if (url_str.find("apple-touch-icon") != std::string::npos) {
        score += 8;
      }

      if (score > best_score) {
        best_score = score;
        best_url = url_str;
      }
    }

    // fprintf(stderr, "[CEF] Selected favicon URL: %s (score: %d)\n",
    //         best_url.c_str(), best_score);
    InvokeFaviconUrlChangeCallback(best_url);
  }

  CefRefPtr<CefBrowser> GetBrowser() { return browser_; }

  // =========================================================================
  // CefContextMenuHandler methods
  // =========================================================================

  // Custom menu command IDs (must be > MENU_ID_USER_FIRST = 26500)
  enum CustomMenuIds { MENU_ID_OPEN_LINK_AS_CHILD_TAB = 26501 };

  void OnBeforeContextMenu(CefRefPtr<CefBrowser> browser,
                           CefRefPtr<CefFrame> frame,
                           CefRefPtr<CefContextMenuParams> params,
                           CefRefPtr<CefMenuModel> model) override {
    // Only add our custom menu item when right-clicking on a link
    if (params->GetTypeFlags() & CM_TYPEFLAG_LINK) {
      std::string link_url = params->GetLinkUrl().ToString();
      fprintf(stderr, "[CEF Context Menu] Link context menu for: %s\n",
              link_url.c_str());

      // Add separator before our custom item
      model->AddSeparator();

      // Add "Open Link as Child Tab" menu item
      model->AddItem(MENU_ID_OPEN_LINK_AS_CHILD_TAB, "Open Link as Child Tab");
    }
  }

  bool
  OnContextMenuCommand(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                       CefRefPtr<CefContextMenuParams> params, int command_id,
                       CefContextMenuHandler::EventFlags event_flags) override {
    if (command_id == MENU_ID_OPEN_LINK_AS_CHILD_TAB) {
      std::string link_url = params->GetLinkUrl().ToString();
      fprintf(stderr, "[CEF Context Menu] Open Link as Child Tab: %s\n",
              link_url.c_str());

      // Invoke Swift callback to create child tab
      InvokeOpenLinkAsChildTabCallback(link_url);
      return true; // We handled this command
    }
    return false; // Let CEF handle other commands
  }

  // =========================================================================
  // CefPermissionHandler methods
  // =========================================================================

  bool OnRequestMediaAccessPermission(
      CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
      const CefString &requesting_origin, uint32_t requested_permissions,
      CefRefPtr<CefMediaAccessCallback> callback) override {

    std::string origin = requesting_origin.ToString();
    fprintf(
        stderr,
        "[CEF Permission] Media access requested by %s, permissions: 0x%x\n",
        origin.c_str(), requested_permissions);

    // Store the callback for later use when Swift responds
    if (!wrapper_) {
      fprintf(stderr, "[CEF Permission] No wrapper available, denying\n");
      return false; // Let CEF handle with default (deny)
    }

    CefBrowserHandle handle = static_cast<CefBrowserHandle>(wrapper_);

    // Store the pending callback
    {
      std::lock_guard<std::mutex> lock(g_pending_permission_mutex);
      g_pending_permission_callbacks[handle] = callback;
    }

    // Invoke Swift callback to show permission UI
    InvokeMediaPermissionRequestCallback(origin, requested_permissions);

    // Return true to indicate we're handling this asynchronously
    return true;
  }

  // =========================================================================
  // CefRequestHandler methods
  // =========================================================================

  bool OnBeforeBrowse(CefRefPtr<CefBrowser> browser, CefRefPtr<CefFrame> frame,
                      CefRefPtr<CefRequest> request, bool user_gesture,
                      bool is_redirect) override {
    // Only intercept main frame navigations triggered by user gestures (clicks)
    if (!frame->IsMain() || !user_gesture || is_redirect) {
      return false; // Allow navigation
    }

    std::string url = request->GetURL().ToString();
    fprintf(stderr, "[CEF Request] OnBeforeBrowse: %s (user_gesture=%d)\n",
            url.c_str(), user_gesture);

    // Invoke Swift callback to check if we should intercept this navigation
    int allow = InvokeLinkClickCallback(url);

    // Return true to cancel navigation (Swift will handle it)
    // Return false to allow normal navigation
    return (allow == 0);
  }

private:
  CefRefPtr<CefBrowser> browser_;
  BrowserWrapper
      *wrapper_;          // Back-pointer to get the handle for callback lookup
  int snapshot_timer_id_; // Timer ID for debounced snapshot (0 = no pending)

  // =========================================================================
  // Debounced Snapshot Capture (Capture-on-Load Strategy)
  // =========================================================================

  // Cancel any pending snapshot timer
  void CancelPendingSnapshot() {
    if (snapshot_timer_id_ != 0) {
      fprintf(stderr, "[CEF Snapshot] Cancelling pending snapshot timer %d\n",
              snapshot_timer_id_);
      snapshot_timer_id_ = 0;
    }
  }

  // Schedule a debounced snapshot capture
  // Waits 500ms after load completes to ensure:
  // 1. All sub-resources and iframes have finished
  // 2. JavaScript has rendered dynamic content
  // 3. The page is visually complete
  void ScheduleDebouncedSnapshot() {
    CancelPendingSnapshot(); // Cancel any existing timer

    if (!browser_ || !wrapper_) {
      fprintf(stderr,
              "[CEF Snapshot] Cannot schedule snapshot - no browser/wrapper\n");
      return;
    }

    // Generate a unique timer ID
    static int timer_counter = 0;
    snapshot_timer_id_ = ++timer_counter;
    int current_timer_id = snapshot_timer_id_;

    fprintf(stderr,
            "[CEF Snapshot] Scheduling debounced snapshot (timer %d, delay "
            "500ms)\n",
            current_timer_id);

    // Use dispatch_after for macOS (simpler than CEF's task posting)
    // Capture 'this' pointer safely - we check timer_id validity in the
    // callback
    SimpleClient *client = this;
    client->AddRef(); // prevent premature release

    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC),
        dispatch_get_main_queue(), ^{
          // Check if this timer is still valid (not cancelled)
          if (current_timer_id != client->snapshot_timer_id_) {
            fprintf(stderr,
                    "[CEF Snapshot] Timer %d was cancelled, skipping capture\n",
                    current_timer_id);
            client->Release();
            return;
          }

          client->snapshot_timer_id_ = 0; // Clear the timer

          if (!client->browser_ || !client->wrapper_) {
            fprintf(stderr,
                    "[CEF Snapshot] Cannot capture - browser/wrapper gone\n");
            client->Release();
            return;
          }

          fprintf(stderr,
                  "[CEF Snapshot] Executing capture-on-load snapshot\n");

          // Capture and send to Swift via callback
          client->CaptureAndSendSnapshot();
          client->Release();
        });
  }

  // Capture snapshot and invoke the Swift callback
  void CaptureAndSendSnapshot();

  // Helper to invoke load state callback
  void InvokeLoadStateCallback(bool isLoading, bool canGoBack,
                               bool canGoForward, const std::string &url);

  // Helper to invoke title change callback
  void InvokeTitleChangeCallback(const std::string &title);

  // Helper to invoke URL change callback
  void InvokeUrlChangeCallback(const std::string &url);

  // Helper to invoke favicon URL change callback
  void InvokeFaviconUrlChangeCallback(const std::string &favicon_url);

  // Helper to invoke snapshot ready callback
  void InvokeSnapshotReadyCallback(const void *buffer, int width, int height,
                                   size_t buffer_size);

  // Helper to invoke open link as child tab callback
  void InvokeOpenLinkAsChildTabCallback(const std::string &url);

  // Helper to invoke media permission request callback
  void
  InvokeMediaPermissionRequestCallback(const std::string &requesting_origin,
                                       uint32_t requested_permissions);

  // Helper to invoke link click callback
  int InvokeLinkClickCallback(const std::string &url);

  IMPLEMENT_REFCOUNTING(SimpleClient);
};

// =============================================================================
// MARK: - Browser Wrapper
// =============================================================================

struct BrowserWrapper {
  CefRefPtr<SimpleClient> client;
  CefRefPtr<CefBrowser> browser;
  void *parent_view;
  bool disable_swipe_navigation;

  BrowserWrapper() : parent_view(nullptr), disable_swipe_navigation(false) {}
};

// =============================================================================
// MARK: - SimpleClient Method Implementations (requiring BrowserWrapper)
// =============================================================================

void SimpleClient::OnLoadEnd(CefRefPtr<CefBrowser> browser,
                             CefRefPtr<CefFrame> frame, int httpStatusCode) {
  if (frame->IsMain()) {
    std::string url = frame->GetURL().ToString();
    fprintf(stderr, "[CEF] Load ended: %s (status: %d)\n", url.c_str(),
            httpStatusCode);

    // If swipe navigation should be disabled, inject CSS to prevent overscroll
    if (wrapper_ && wrapper_->disable_swipe_navigation) {
      std::string js_code =
          "(function() {"
          "  var style = document.createElement('style');"
          "  style.textContent = 'html, body { overscroll-behavior-x: none "
          "!important; }';"
          "  document.head.appendChild(style);"
          "  console.log('[Bowser] Swipe navigation disabled via CSS');"
          "})();";

      frame->ExecuteJavaScript(js_code, frame->GetURL(), 0);
      fprintf(stderr, "[CEF] Injected CSS to disable swipe navigation\n");
    }

    // Invoke Swift callback for load state change (isLoading = false)
    bool canGoBack = browser->CanGoBack();
    bool canGoForward = browser->CanGoForward();
    InvokeLoadStateCallback(false, canGoBack, canGoForward, url);
  }
}

// =============================================================================
// MARK: - SimpleClient Callback Invocation Implementation
// =============================================================================

void SimpleClient::InvokeLoadStateCallback(bool isLoading, bool canGoBack,
                                           bool canGoForward,
                                           const std::string &url) {
  if (!wrapper_)
    return;

  CefBrowserHandle handle = static_cast<CefBrowserHandle>(wrapper_);

  std::lock_guard<std::mutex> lock(g_callbacks_mutex);
  auto it = g_callbacks.find(handle);
  if (it != g_callbacks.end() && it->second.load_state_callback) {
    // IMPORTANT: This callback runs on the CEF UI thread (background thread)
    // The Swift side MUST dispatch to MainActor before updating UI state
    it->second.load_state_callback(handle, isLoading ? 1 : 0, canGoBack ? 1 : 0,
                                   canGoForward ? 1 : 0, url.c_str());
  }
}

void SimpleClient::InvokeTitleChangeCallback(const std::string &title) {
  if (!wrapper_)
    return;

  CefBrowserHandle handle = static_cast<CefBrowserHandle>(wrapper_);

  std::lock_guard<std::mutex> lock(g_callbacks_mutex);
  auto it = g_callbacks.find(handle);
  if (it != g_callbacks.end() && it->second.title_change_callback) {
    // IMPORTANT: This callback runs on the CEF UI thread (background thread)
    // The Swift side MUST dispatch to MainActor before updating UI state
    it->second.title_change_callback(handle, title.c_str());
  }
}

void SimpleClient::InvokeUrlChangeCallback(const std::string &url) {
  if (!wrapper_)
    return;

  CefBrowserHandle handle = static_cast<CefBrowserHandle>(wrapper_);

  std::lock_guard<std::mutex> lock(g_callbacks_mutex);
  auto it = g_callbacks.find(handle);
  if (it != g_callbacks.end() && it->second.url_change_callback) {
    // IMPORTANT: This callback runs on the CEF UI thread (background thread)
    // The Swift side MUST dispatch to MainActor before updating UI state
    it->second.url_change_callback(handle, url.c_str());
  }
}

void SimpleClient::InvokeFaviconUrlChangeCallback(
    const std::string &favicon_url) {
  if (!wrapper_)
    return;

  CefBrowserHandle handle = static_cast<CefBrowserHandle>(wrapper_);

  std::lock_guard<std::mutex> lock(g_callbacks_mutex);
  auto it = g_callbacks.find(handle);
  if (it != g_callbacks.end() && it->second.favicon_url_change_callback) {
    // IMPORTANT: This callback runs on the CEF UI thread (background thread)
    // The Swift side MUST dispatch to MainActor before updating UI state
    it->second.favicon_url_change_callback(handle, favicon_url.c_str());
  }
}

void SimpleClient::InvokeSnapshotReadyCallback(const void *buffer, int width,
                                               int height, size_t buffer_size) {
  if (!wrapper_)
    return;

  CefBrowserHandle handle = static_cast<CefBrowserHandle>(wrapper_);

  std::lock_guard<std::mutex> lock(g_callbacks_mutex);
  auto it = g_callbacks.find(handle);
  if (it != g_callbacks.end() && it->second.snapshot_ready_callback) {
    fprintf(
        stderr,
        "[CEF Snapshot] Invoking Swift callback with %dx%d image (%zu bytes)\n",
        width, height, buffer_size);
    // IMPORTANT: This callback runs on the CEF UI thread (background thread)
    // The Swift side MUST dispatch to MainActor before updating UI state
    it->second.snapshot_ready_callback(handle, buffer, width, height,
                                       buffer_size);
  } else {
    fprintf(stderr, "[CEF Snapshot] No snapshot callback registered\n");
  }
}

void SimpleClient::InvokeOpenLinkAsChildTabCallback(const std::string &url) {
  if (!wrapper_)
    return;

  CefBrowserHandle handle = static_cast<CefBrowserHandle>(wrapper_);

  std::lock_guard<std::mutex> lock(g_callbacks_mutex);
  auto it = g_callbacks.find(handle);
  if (it != g_callbacks.end() && it->second.open_link_as_child_tab_callback) {
    fprintf(stderr,
            "[CEF Context Menu] Invoking Swift callback for child tab: %s\n",
            url.c_str());
    // IMPORTANT: This callback runs on the CEF UI thread (background thread)
    // The Swift side MUST dispatch to MainActor before updating UI state
    it->second.open_link_as_child_tab_callback(handle, url.c_str());
  } else {
    fprintf(
        stderr,
        "[CEF Context Menu] No open_link_as_child_tab callback registered\n");
  }
}

void SimpleClient::InvokeMediaPermissionRequestCallback(
    const std::string &requesting_origin, uint32_t requested_permissions) {
  if (!wrapper_)
    return;

  CefBrowserHandle handle = static_cast<CefBrowserHandle>(wrapper_);

  std::lock_guard<std::mutex> lock(g_callbacks_mutex);
  auto it = g_callbacks.find(handle);
  if (it != g_callbacks.end() && it->second.media_permission_request_callback) {
    fprintf(stderr,
            "[CEF Permission] Invoking Swift callback for media permission: "
            "%s, permissions: 0x%x\n",
            requesting_origin.c_str(), requested_permissions);
    // IMPORTANT: This callback runs on the CEF UI thread (background thread)
    // The Swift side MUST dispatch to MainActor before updating UI state
    it->second.media_permission_request_callback(
        handle, requesting_origin.c_str(), (int)requested_permissions);
  } else {
    fprintf(
        stderr,
        "[CEF Permission] No media_permission_request callback registered\n");
  }
}

int SimpleClient::InvokeLinkClickCallback(const std::string &url) {
  if (!wrapper_)
    return 1; // Allow navigation by default

  CefBrowserHandle handle = static_cast<CefBrowserHandle>(wrapper_);

  std::lock_guard<std::mutex> lock(g_callbacks_mutex);
  auto it = g_callbacks.find(handle);
  if (it != g_callbacks.end() && it->second.link_click_callback) {
    fprintf(stderr,
            "[CEF Request] Invoking Swift callback for link click: %s\n",
            url.c_str());
    // IMPORTANT: This callback runs on the CEF UI thread (background thread)
    // The Swift side MUST dispatch to MainActor before updating UI state
    // Returns 1 to allow navigation, 0 to cancel
    return it->second.link_click_callback(handle, url.c_str());
  }

  // No callback registered - allow navigation by default
  return 1;
}

// =============================================================================
// MARK: - CaptureAndSendSnapshot Implementation (macOS)
// =============================================================================

#if defined(__APPLE__)
// Forward declare the helper function (defined later in the file)
static uint8_t *resize_rgba_image(const uint8_t *src_buffer, int src_width,
                                  int src_height, int dst_width,
                                  int dst_height);

void SimpleClient::CaptureAndSendSnapshot() {
  if (!browser_ || !wrapper_) {
    fprintf(stderr,
            "[CEF Snapshot] CaptureAndSendSnapshot: No browser/wrapper\n");
    return;
  }

  // Use the parent view (Swift CEFContainerView) which contains the CEF content
  void *parent_view = wrapper_->parent_view;
  if (!parent_view) {
    fprintf(stderr, "[CEF Snapshot] CaptureAndSendSnapshot: No parent view\n");
    return;
  }

  // Max thumbnail width for preview
  const int max_width = 320;

  fprintf(stderr,
          "[CEF Snapshot] CaptureAndSendSnapshot: Starting capture...\n");

  // Use Objective-C runtime to access the NSView
  id view = (id)parent_view;

  // Get the view bounds
  CGRect (*boundsIMP)(id, SEL) = (CGRect(*)(id, SEL))objc_msgSend;
  CGRect bounds = boundsIMP(view, sel_registerName("bounds"));

  if (bounds.size.width <= 0 || bounds.size.height <= 0) {
    fprintf(stderr,
            "[CEF Snapshot] CaptureAndSendSnapshot: Invalid bounds %.0fx%.0f\n",
            bounds.size.width, bounds.size.height);
    return;
  }

  int src_width = (int)bounds.size.width;
  int src_height = (int)bounds.size.height;

  fprintf(stderr, "[CEF Snapshot] View size %dx%d\n", src_width, src_height);

  uint8_t *src_buffer = nullptr;
  size_t src_buffer_size = 0;
  size_t imgWidth = src_width;
  size_t imgHeight = src_height;
  bool captured = false;

  // Get the window for screen-relative capture
  id (*windowIMP)(id, SEL) = (id(*)(id, SEL))objc_msgSend;
  id window = windowIMP(view, sel_registerName("window"));

  if (!window) {
    fprintf(stderr, "[CEF Snapshot] CaptureAndSendSnapshot: No window\n");
    return;
  }

  // Get window number
  long long (*windowNumberIMP)(id, SEL) = (long long (*)(id, SEL))objc_msgSend;
  long long windowNumber =
      windowNumberIMP(window, sel_registerName("windowNumber"));

  // Convert view bounds to screen coordinates
  CGRect (*convertRectIMP)(id, SEL, CGRect, id) =
      (CGRect(*)(id, SEL, CGRect, id))objc_msgSend;
  CGRect windowRect = convertRectIMP(
      view, sel_registerName("convertRect:toView:"), bounds, nil);

  CGRect (*convertToScreenIMP)(id, SEL, CGRect) =
      (CGRect(*)(id, SEL, CGRect))objc_msgSend;
  CGRect screenRect = convertToScreenIMP(
      window, sel_registerName("convertRectToScreen:"), windowRect);

  fprintf(stderr,
          "[CEF Snapshot] Window %lld, screen rect: %.0f,%.0f %.0fx%.0f\n",
          windowNumber, screenRect.origin.x, screenRect.origin.y,
          screenRect.size.width, screenRect.size.height);

  // Strategy: Use CGWindowListCreateImage to capture ONLY the specific window
  // The key is using the window ID directly - this captures just this window's
  // content at the specified rect, not any overlapping windows or UI elements
  // from other sources
  if (windowNumber > 0) {
    // Suppress deprecation warning for CGWindowListCreateImage
    // TODO: Migrate to ScreenCaptureKit when async capture is feasible
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    CGImageRef cgImage = CGWindowListCreateImage(
        screenRect, kCGWindowListOptionIncludingWindow,
        (CGWindowID)windowNumber,
        kCGWindowImageBoundsIgnoreFraming | kCGWindowImageNominalResolution);
#pragma clang diagnostic pop

    if (cgImage) {
      imgWidth = CGImageGetWidth(cgImage);
      imgHeight = CGImageGetHeight(cgImage);

      if (imgWidth > 0 && imgHeight > 0) {
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        if (colorSpace) {
          src_buffer_size = imgWidth * imgHeight * 4;
          src_buffer = (uint8_t *)calloc(1, src_buffer_size);

          if (src_buffer) {
            CGContextRef context = CGBitmapContextCreate(
                src_buffer, imgWidth, imgHeight, 8, imgWidth * 4, colorSpace,
                kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);

            if (context) {
              CGContextDrawImage(context, CGRectMake(0, 0, imgWidth, imgHeight),
                                 cgImage);
              CGContextRelease(context);
              captured = true;
              fprintf(stderr,
                      "[CEF Snapshot] Captured via CGWindowListCreateImage: "
                      "%zux%zu\n",
                      imgWidth, imgHeight);
            } else {
              free(src_buffer);
              src_buffer = nullptr;
            }
          }
          CGColorSpaceRelease(colorSpace);
        }
      }
      CGImageRelease(cgImage);
    }
  }

  // Fallback: Use bitmapImageRepForCachingDisplay if window capture failed
  if (!captured) {
    fprintf(
        stderr,
        "[CEF Snapshot] Trying bitmapImageRepForCachingDisplay fallback...\n");

    SEL bitmapRepSel =
        sel_registerName("bitmapImageRepForCachingDisplayInRect:");
    id (*bitmapRepIMP)(id, SEL, CGRect) = (id(*)(id, SEL, CGRect))objc_msgSend;
    id bitmapRep = bitmapRepIMP(view, bitmapRepSel, bounds);

    if (bitmapRep) {
      SEL cacheDisplaySel =
          sel_registerName("cacheDisplayInRect:toBitmapImageRep:");
      void (*cacheDisplayIMP)(id, SEL, CGRect, id) =
          (void (*)(id, SEL, CGRect, id))objc_msgSend;
      cacheDisplayIMP(view, cacheDisplaySel, bounds, bitmapRep);

      SEL bitmapDataSel = sel_registerName("bitmapData");
      unsigned char *(*bitmapDataIMP)(id, SEL) =
          (unsigned char *(*)(id, SEL))objc_msgSend;
      unsigned char *repData = bitmapDataIMP(bitmapRep, bitmapDataSel);

      SEL pixelsWideSel = sel_registerName("pixelsWide");
      SEL pixelsHighSel = sel_registerName("pixelsHigh");
      long long (*intValueIMP)(id, SEL) = (long long (*)(id, SEL))objc_msgSend;
      imgWidth = intValueIMP(bitmapRep, pixelsWideSel);
      imgHeight = intValueIMP(bitmapRep, pixelsHighSel);

      if (repData && imgWidth > 0 && imgHeight > 0) {
        src_buffer_size = imgWidth * imgHeight * 4;
        src_buffer = (uint8_t *)malloc(src_buffer_size);
        if (src_buffer) {
          memcpy(src_buffer, repData, src_buffer_size);
          captured = true;
          fprintf(stderr,
                  "[CEF Snapshot] Captured via bitmapImageRep: %zux%zu\n",
                  imgWidth, imgHeight);
        }
      }
    }
  }

  if (!captured || !src_buffer) {
    fprintf(stderr, "[CEF Snapshot] All capture methods failed\n");
    return;
  }

  // Check if buffer has actual content
  bool has_content = false;
  size_t sample_count = std::min(src_buffer_size / 4, (size_t)10000);
  for (size_t i = 0; i < sample_count && !has_content; i++) {
    size_t idx = (i * src_buffer_size / 4 / sample_count) * 4;
    if (src_buffer[idx] > 10 || src_buffer[idx + 1] > 10 ||
        src_buffer[idx + 2] > 10) {
      has_content = true;
    }
  }

  if (!has_content) {
    fprintf(stderr,
            "[CEF Snapshot] Buffer appears empty - content not captured\n");
    free(src_buffer);
    return;
  }

  // Calculate target dimensions
  float aspect_ratio = (float)imgHeight / (float)imgWidth;
  int dst_width = max_width;
  int dst_height = (int)(max_width * aspect_ratio);
  if (dst_height < 1)
    dst_height = 1;

  fprintf(stderr, "[CEF Snapshot] Resizing from %zux%zu to %dx%d\n", imgWidth,
          imgHeight, dst_width, dst_height);

  // Resize the image
  uint8_t *dst_buffer = resize_rgba_image(
      src_buffer, (int)imgWidth, (int)imgHeight, dst_width, dst_height);
  free(src_buffer);

  if (!dst_buffer) {
    fprintf(stderr, "[CEF Snapshot] Resize failed\n");
    return;
  }

  size_t dst_buffer_size = dst_width * dst_height * 4;

  fprintf(stderr,
          "[CEF Snapshot] SUCCESS: Captured %dx%d thumbnail (%zu bytes)\n",
          dst_width, dst_height, dst_buffer_size);

  // Send to Swift via callback
  InvokeSnapshotReadyCallback(dst_buffer, dst_width, dst_height,
                              dst_buffer_size);

  free(dst_buffer);
}

#else
// Non-macOS stub
void SimpleClient::CaptureAndSendSnapshot() {
  fprintf(stderr, "[CEF Snapshot] CaptureAndSendSnapshot: Not implemented on "
                  "this platform\n");
}
#endif

// =============================================================================
// MARK: - Simple App Implementation
// =============================================================================

// CefApp implementation to handle command-line processing
class SimpleApp : public CefApp, public CefBrowserProcessHandler {
public:
  SimpleApp() {}

  // CefApp methods
  CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override {
    return this;
  }

  // CefBrowserProcessHandler methods
  void OnBeforeCommandLineProcessing(
      const CefString &process_type,
      CefRefPtr<CefCommandLine> command_line) override {
    fprintf(stderr,
            "[CEF] OnBeforeCommandLineProcessing called (process_type: %s)\n",
            process_type.ToString().c_str());

    // Add --use-mock-keychain switch for proper keychain handling on macOS
    command_line->AppendSwitch("use-mock-keychain");
    fprintf(stderr, "[CEF] Added --use-mock-keychain switch\n");

    // Enable media stream (camera/microphone) support
    // These switches are needed for getUserMedia to work properly
    command_line->AppendSwitch("enable-media-stream");
    fprintf(stderr, "[CEF] Added --enable-media-stream switch\n");

    // Allow fake UI for testing device selection (optional)
    // command_line->AppendSwitch("use-fake-ui-for-media-stream");

    // Enable GPU-accelerated video decode
    command_line->AppendSwitch("enable-accelerated-video-decode");

    // Additional WebRTC flags for better Google compatibility
    // Enable WebRTC hardware video encoding/decoding
    command_line->AppendSwitch("enable-webrtc-hw-encoding");
    command_line->AppendSwitch("enable-webrtc-hw-decoding");

    // Enable unified plan (modern WebRTC standard used by Google Meet)
    command_line->AppendSwitch("enable-features=WebRtcUseModernCreateOffer");

    fprintf(stderr, "[CEF] Added WebRTC compatibility switches\n");

    // Force support for Manifest V2 extensions (needed for uBlock Origin)
    command_line->AppendSwitchWithValue(
        "disable-features",
        "ExtensionManifestV2Unsupported,ExtensionManifestV2Disabled");
    fprintf(stderr, "[CEF] Added switches to force Manifest V2 support\n");

    // Load persisted extensions from UserDefaults
    // Use Objective-C runtime to access NSUserDefaults to support extension
    // loading on startup since dynamic loading via LoadExtension is not
    // available in this CEF build.
    Class NSUserDefaultsClass = objc_getClass("NSUserDefaults");
    SEL standardUserDefaultsSel = sel_registerName("standardUserDefaults");
    id (*standardUserDefaultsIMP)(Class, SEL) = (id(*)(Class, SEL))objc_msgSend;
    id defaults =
        standardUserDefaultsIMP(NSUserDefaultsClass, standardUserDefaultsSel);

    if (defaults) {
      SEL stringArrayForKeySel = sel_registerName("stringArrayForKey:");
      id (*stringArrayForKeyIMP)(id, SEL, id) =
          (id(*)(id, SEL, id))objc_msgSend;

      // Create NSString key
      Class NSStringClass = objc_getClass("NSString");
      SEL stringWithUTF8StringSel = sel_registerName("stringWithUTF8String:");
      id (*stringWithUTF8StringIMP)(Class, SEL, const char *) =
          (id(*)(Class, SEL, const char *))objc_msgSend;
      id key = stringWithUTF8StringIMP(NSStringClass, stringWithUTF8StringSel,
                                       "bowser.extensions.paths");

      id pathsArray = stringArrayForKeyIMP(defaults, stringArrayForKeySel, key);

      if (pathsArray) {
        SEL countSel = sel_registerName("count");
        unsigned long (*countIMP)(id, SEL) =
            (unsigned long (*)(id, SEL))objc_msgSend;
        unsigned long count = countIMP(pathsArray, countSel);

        if (count > 0) {
          std::string extensions_paths;

          SEL objectAtIndexSel = sel_registerName("objectAtIndex:");
          id (*objectAtIndexIMP)(id, SEL, unsigned long) =
              (id(*)(id, SEL, unsigned long))objc_msgSend;

          SEL UTF8StringSel = sel_registerName("UTF8String");
          const char *(*UTF8StringIMP)(id, SEL) =
              (const char *(*)(id, SEL))objc_msgSend;

          for (unsigned long i = 0; i < count; i++) {
            id path = objectAtIndexIMP(pathsArray, objectAtIndexSel, i);
            const char *pathCStr = UTF8StringIMP(path, UTF8StringSel);

            if (pathCStr) {
              if (!extensions_paths.empty()) {
                extensions_paths += ",";
              }
              extensions_paths += pathCStr;
            }
          }

          if (!extensions_paths.empty()) {
            command_line->AppendSwitchWithValue("load-extension",
                                                extensions_paths);
            fprintf(stderr, "[CEF] Loaded persisted extensions: %s\n",
                    extensions_paths.c_str());
          }
        }
      }
    }
  }

private:
  IMPLEMENT_REFCOUNTING(SimpleApp);
};

// =============================================================================
// MARK: - Global State
// =============================================================================

static bool g_cef_initialized = false;
static bool g_library_loaded = false;
static std::map<CefBrowserHandle, BrowserWrapper *> g_browsers;
static std::mutex g_browsers_mutex;
static std::string g_framework_path;

// =============================================================================
// MARK: - C API Implementation
// =============================================================================

extern "C" {

int cef_execute_subprocess(int argc, char **argv, const char *framework_path) {
  if (!framework_path || strlen(framework_path) == 0) {
    fprintf(stderr, "[CEF] No framework path provided for subprocess\n");
    return -1;
  }

  // Build the full path to the framework binary
  std::string lib_path =
      std::string(framework_path) + "/Chromium Embedded Framework";

  // Load CEF library if not already loaded
  if (!g_library_loaded) {
    fprintf(stderr, "[CEF Subprocess] Loading library from: %s\n",
            lib_path.c_str());
    if (!cef_load_library(lib_path.c_str())) {
      fprintf(stderr, "[CEF Subprocess] Failed to load CEF library\n");
      return -1;
    }
    g_library_loaded = true;
    g_framework_path = framework_path;
  }

  // Create main args from command line
  CefMainArgs main_args(argc, argv);

  // Create app instance to handle command-line processing
  CefRefPtr<SimpleApp> app(new SimpleApp());

  // Execute the subprocess - this will return immediately for the browser
  // process or block until exit for subprocess types (renderer, GPU, etc.)
  int exit_code = CefExecuteProcess(main_args, app, nullptr);

  fprintf(stderr, "[CEF] CefExecuteProcess returned: %d\n", exit_code);
  return exit_code;
}

int cef_simple_initialize_with_path(const char *framework_path) {
  if (g_cef_initialized) {
    fprintf(stderr, "[CEF] Already initialized\n");
    return 1;
  }

  if (!framework_path || strlen(framework_path) == 0) {
    fprintf(stderr, "[CEF] No framework path provided\n");
    return 0;
  }

  // Build the full path to the framework binary
  std::string framework_path_str = std::string(framework_path);
  std::string lib_path = framework_path_str + "/Chromium Embedded Framework";

  // Load library if not already loaded (might be loaded from
  // cef_execute_subprocess)
  if (!g_library_loaded) {
    fprintf(stderr, "[CEF] Loading library from: %s\n", lib_path.c_str());

    // Use the library loader from libcef_dll_wrapper
    if (!cef_load_library(lib_path.c_str())) {
      fprintf(stderr, "[CEF] Failed to load CEF library\n");
      return 0;
    }

    g_library_loaded = true;
    g_framework_path = framework_path;
    fprintf(stderr, "[CEF] Library loaded successfully\n");
  } else {
    fprintf(stderr, "[CEF] Library already loaded\n");
  }

  // Create main args for macOS
  CefMainArgs main_args(0, nullptr);

  // Configure minimal settings
  CefSettings settings;
  settings.no_sandbox = true;
  settings.windowless_rendering_enabled = false;
  settings.multi_threaded_message_loop = false;

  // Set cache paths to avoid process singleton conflicts and the warning
  // message Using a unique path in the user's home directory
  const char *home_dir = getenv("HOME");
  if (home_dir) {
    std::string cache_path =
        std::string(home_dir) + "/Library/Caches/Bowser/CEF";
    CefString(&settings.root_cache_path).FromASCII(cache_path.c_str());
    CefString(&settings.cache_path).FromASCII(cache_path.c_str());
    fprintf(stderr, "[CEF] Cache path: %s\n", cache_path.c_str());
  }

  // Set a Chrome-compatible User-Agent to avoid detection by Google websites
  // Google sites (Meet, Gemini, YouTube) block WebRTC/getUserMedia for
  // unknown browsers Using a standard Chrome User-Agent ensures full media
  // permission support Note: Update the Chrome version periodically to stay
  // current
  CefString(&settings.user_agent)
      .FromASCII("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                 "AppleWebKit/537.36 (KHTML, like Gecko) "
                 "Chrome/120.0.0.0 Safari/537.36");

  // On macOS, we need to set the external_message_pump to integrate with the
  // macOS run loop This is required when using CefDoMessageLoopWork() instead
  // of CefRunMessageLoop()
  settings.external_message_pump = true;

  // Set framework directory path
  CefString(&settings.framework_dir_path).FromASCII(framework_path);

  // Set resources directory path (on macOS, resources are inside the
  // framework's Resources folder)
  std::string resources_path = framework_path_str + "/Resources";
  CefString(&settings.resources_dir_path).FromASCII(resources_path.c_str());
  fprintf(stderr, "[CEF] Resources path: %s\n", resources_path.c_str());

  // Set locales directory path (on macOS, locales are inside the framework's
  // Resources folder) Note: According to CEF docs, this is ignored on macOS
  // but we set it anyway
  CefString(&settings.locales_dir_path).FromASCII(resources_path.c_str());

  // Get executable path for subprocess handling
  char exe_path[PATH_MAX];
  uint32_t size = sizeof(exe_path);
  std::string exe_full_path;
  std::string exe_dir;

  if (_NSGetExecutablePath(exe_path, &size) == 0) {
    // Resolve any symlinks to get the real path
    char real_path[PATH_MAX];
    if (realpath(exe_path, real_path) != nullptr) {
      exe_full_path = std::string(real_path);
    } else {
      exe_full_path = std::string(exe_path);
    }

    // Get the directory containing the executable
    exe_dir = exe_full_path;
    size_t last_slash = exe_dir.rfind('/');
    if (last_slash != std::string::npos) {
      exe_dir = exe_dir.substr(0, last_slash);
    }

    // Set main_bundle_path to the executable directory
    CefString(&settings.main_bundle_path).FromASCII(exe_dir.c_str());
    fprintf(stderr, "[CEF] Main bundle path: %s\n", exe_dir.c_str());

    // Set browser_subprocess_path to the Helper app
    // The Helper app is located at:
    // Bowser.app/Contents/Frameworks/Bowser
    // Helper.app/Contents/MacOS/Bowser Helper This prevents subprocesses
    // from appearing in the Dock (Helper has LSUIElement=1)
    std::string helper_path =
        exe_dir +
        "/../Frameworks/Bowser Helper.app/Contents/MacOS/Bowser Helper";

    // Resolve the path to handle symlinks and relative paths
    char resolved_helper_path[PATH_MAX];
    if (realpath(helper_path.c_str(), resolved_helper_path) != nullptr) {
      CefString(&settings.browser_subprocess_path)
          .FromASCII(resolved_helper_path);
      fprintf(stderr, "[CEF] Browser subprocess path (Helper): %s\n",
              resolved_helper_path);
    } else {
      // Fallback: use the main executable (old behavior)
      fprintf(stderr,
              "[CEF] Warning: Helper app not found at %s, using main "
              "executable\n",
              helper_path.c_str());
      CefString(&settings.browser_subprocess_path)
          .FromASCII(exe_full_path.c_str());
      fprintf(stderr, "[CEF] Browser subprocess path (fallback): %s\n",
              exe_full_path.c_str());
    }
  }

  // Set log severity - use INFO for debugging initialization issues
  settings.log_severity = LOGSEVERITY_INFO;

  // Create app instance to handle command-line processing
  CefRefPtr<SimpleApp> app(new SimpleApp());

  // Initialize CEF
  fprintf(stderr, "[CEF] Calling CefInitialize...\n");

  if (!CefInitialize(main_args, settings, app, nullptr)) {
    fprintf(stderr, "[CEF] CefInitialize failed!\n");
    cef_unload_library();
    g_library_loaded = false;
    return 0;
  }

  g_cef_initialized = true;
  fprintf(stderr, "[CEF] Initialization successful\n");

  return 1;
}

int cef_simple_initialize(void) {
  // Try to initialize without a specific path - not supported
  fprintf(stderr, "[CEF] cef_simple_initialize called without path - use "
                  "cef_simple_initialize_with_path\n");
  return 0;
}

void cef_simple_shutdown(void) {
  if (!g_cef_initialized) {
    return;
  }

  fprintf(stderr, "[CEF] Shutting down...\n");

  // Clean up all browsers
  {
    std::lock_guard<std::mutex> lock(g_browsers_mutex);
    for (auto &pair : g_browsers) {
      if (pair.second && pair.second->browser) {
        pair.second->browser->GetHost()->CloseBrowser(true);
      }
      delete pair.second;
    }
    g_browsers.clear();
  }

  CefShutdown();
  g_cef_initialized = false;

  if (g_library_loaded) {
    cef_unload_library();
    g_library_loaded = false;
  }

  fprintf(stderr, "[CEF] Shutdown complete\n");
}

int cef_do_message_work(void) {
  if (!g_cef_initialized) {
    return 0;
  }

  CefDoMessageLoopWork();
  return 1;
}

CefBrowserHandle cef_create_browser(void *parent_view, const char *url,
                                    int width, int height,
                                    int disable_swipe_navigation) {
  if (!g_cef_initialized) {
    fprintf(stderr, "[CEF] Not initialized - cannot create browser\n");
    return nullptr;
  }

  if (!parent_view) {
    fprintf(stderr, "[CEF] No parent view provided\n");
    return nullptr;
  }

  fprintf(stderr,
          "[CEF] Creating browser with URL: %s, size: %dx%d, "
          "disable_swipe_navigation: %d\n",
          url ? url : "(null)", width, height, disable_swipe_navigation);

  // Create browser wrapper first
  BrowserWrapper *wrapper = new BrowserWrapper();
  wrapper->parent_view = parent_view;
  wrapper->disable_swipe_navigation = (disable_swipe_navigation != 0);

  // Create client with back-pointer to wrapper for callback invocation
  wrapper->client = new SimpleClient(wrapper);

  // Configure window info for macOS
  CefWindowInfo window_info;
  window_info.SetAsChild(static_cast<CefWindowHandle>(parent_view),
                         CefRect(0, 0, width, height));

  // Configure browser settings
  CefBrowserSettings browser_settings;

  // Create browser synchronously
  CefString cef_url;
  if (url && strlen(url) > 0) {
    cef_url.FromASCII(url);
  } else {
    cef_url.FromASCII("about:blank");
  }

  // Store the disable_swipe_navigation flag in the wrapper for later use
  // We'll inject CSS to disable overscroll behavior after the browser is
  // created This is more reliable than trying to set unregistered CEF
  // preferences
  CefRefPtr<CefRequestContext> request_context = nullptr;

  wrapper->browser = CefBrowserHost::CreateBrowserSync(
      window_info, wrapper->client, cef_url, browser_settings,
      nullptr,        // extra_info
      request_context // request_context (nullptr for default, or custom)
  );

  if (!wrapper->browser) {
    fprintf(stderr, "[CEF] Failed to create browser\n");
    delete wrapper;
    return nullptr;
  }

  // Store in global map
  CefBrowserHandle handle = static_cast<CefBrowserHandle>(wrapper);
  {
    std::lock_guard<std::mutex> lock(g_browsers_mutex);
    g_browsers[handle] = wrapper;
  }

  fprintf(stderr, "[CEF] Browser created successfully, handle: %p\n", handle);
  return handle;
}

void cef_destroy_browser(CefBrowserHandle handle) {
  if (!handle) {
    return;
  }

  fprintf(stderr, "[CEF] Destroying browser: %p\n", handle);

  // Unregister callbacks first
  {
    std::lock_guard<std::mutex> lock(g_callbacks_mutex);
    g_callbacks.erase(handle);
  }

  BrowserWrapper *wrapper = nullptr;
  {
    std::lock_guard<std::mutex> lock(g_browsers_mutex);
    auto it = g_browsers.find(handle);
    if (it != g_browsers.end()) {
      wrapper = it->second;
      g_browsers.erase(it);
    }
  }

  if (wrapper) {
    if (wrapper->browser) {
      wrapper->browser->GetHost()->CloseBrowser(true);
    }
    delete wrapper;
  }
}

void *cef_get_browser_view(CefBrowserHandle handle) {
  if (!handle) {
    return nullptr;
  }

  BrowserWrapper *wrapper = static_cast<BrowserWrapper *>(handle);
  if (wrapper->browser) {
    return static_cast<void *>(wrapper->browser->GetHost()->GetWindowHandle());
  }
  return nullptr;
}

void cef_navigate_to_url(CefBrowserHandle handle, const char *url) {
  if (!handle || !url) {
    return;
  }

  fprintf(stderr, "[CEF] Navigating to: %s\n", url);

  BrowserWrapper *wrapper = static_cast<BrowserWrapper *>(handle);
  if (wrapper->browser) {
    CefRefPtr<CefFrame> frame = wrapper->browser->GetMainFrame();
    if (frame) {
      frame->LoadURL(CefString(url));
    }
  }
}

void cef_go_back(CefBrowserHandle handle) {
  if (!handle) {
    return;
  }

  BrowserWrapper *wrapper = static_cast<BrowserWrapper *>(handle);
  if (wrapper->browser && wrapper->browser->CanGoBack()) {
    wrapper->browser->GoBack();
  }
}

void cef_go_forward(CefBrowserHandle handle) {
  if (!handle) {
    return;
  }

  BrowserWrapper *wrapper = static_cast<BrowserWrapper *>(handle);
  if (wrapper->browser && wrapper->browser->CanGoForward()) {
    wrapper->browser->GoForward();
  }
}

void cef_reload(CefBrowserHandle handle) {
  if (!handle) {
    return;
  }

  BrowserWrapper *wrapper = static_cast<BrowserWrapper *>(handle);
  if (wrapper->browser) {
    wrapper->browser->Reload();
  }
}

void cef_stop_loading(CefBrowserHandle handle) {
  if (!handle) {
    return;
  }

  BrowserWrapper *wrapper = static_cast<BrowserWrapper *>(handle);
  if (wrapper->browser) {
    wrapper->browser->StopLoad();
  }
}

void cef_execute_javascript(CefBrowserHandle handle, const char *code) {
  if (!handle || !code) {
    return;
  }

  BrowserWrapper *wrapper = static_cast<BrowserWrapper *>(handle);
  if (wrapper->browser) {
    CefRefPtr<CefFrame> frame = wrapper->browser->GetMainFrame();
    if (frame) {
      frame->ExecuteJavaScript(code, frame->GetURL(), 0);
    }
  }
}

int cef_can_go_back(CefBrowserHandle handle) {
  if (!handle) {
    return 0;
  }

  BrowserWrapper *wrapper = static_cast<BrowserWrapper *>(handle);
  if (wrapper->browser) {
    return wrapper->browser->CanGoBack() ? 1 : 0;
  }
  return 0;
}

int cef_can_go_forward(CefBrowserHandle handle) {
  if (!handle) {
    return 0;
  }

  BrowserWrapper *wrapper = static_cast<BrowserWrapper *>(handle);
  if (wrapper->browser) {
    return wrapper->browser->CanGoForward() ? 1 : 0;
  }
  return 0;
}

int cef_is_loading(CefBrowserHandle handle) {
  if (!handle) {
    return 0;
  }

  BrowserWrapper *wrapper = static_cast<BrowserWrapper *>(handle);
  if (wrapper->browser) {
    return wrapper->browser->IsLoading() ? 1 : 0;
  }
  return 0;
}

double cef_get_loading_progress(CefBrowserHandle handle) {
  if (!handle) {
    return 0.0;
  }

  BrowserWrapper *wrapper = static_cast<BrowserWrapper *>(handle);
  if (wrapper->browser) {
    // CEF doesn't expose loading progress directly, so we track it via load
    // state For now, return 1.0 if not loading, 0.0 if loading A more
    // sophisticated implementation would require tracking in SimpleClient
    return wrapper->browser->IsLoading() ? 0.5 : 1.0;
  }
  return 0.0;
}

void cef_resize_browser(CefBrowserHandle handle, int width, int height) {
  if (!handle || width <= 0 || height <= 0) {
    return;
  }

  BrowserWrapper *wrapper = static_cast<BrowserWrapper *>(handle);
  if (wrapper->browser) {
    // Get the CEF browser's NSView
    void *window_handle = wrapper->browser->GetHost()->GetWindowHandle();
    if (window_handle) {
      // Use Objective-C runtime to resize the NSView
      // This ensures the CEF browser view matches the container size
      id nsView = (id)window_handle;

      // Create NSRect for new frame: {{0, 0}, {width, height}}
      // Using objc_msgSend to call setFrame:
      typedef void (*SetFrameMsgSend)(id, SEL, CGRect);
      SetFrameMsgSend setFrame = (SetFrameMsgSend)objc_msgSend;

      CGRect newFrame = CGRectMake(0, 0, width, height);
      SEL setFrameSel = sel_registerName("setFrame:");
      setFrame(nsView, setFrameSel, newFrame);
    }

    // Notify CEF that resize operation started - helps with rendering
    // optimization
    wrapper->browser->GetHost()->NotifyMoveOrResizeStarted();

    // Call WasResized to trigger content reflow
    // This is needed even for windowed mode when we manually set the frame
    wrapper->browser->GetHost()->WasResized();
  }
}

void cef_notify_move_or_resize_started(CefBrowserHandle handle) {
  if (!handle) {
    return;
  }

  BrowserWrapper *wrapper = static_cast<BrowserWrapper *>(handle);
  if (wrapper->browser) {
    // Notify CEF that a move or resize operation has started
    // This allows CEF to optimize rendering during the operation
    wrapper->browser->GetHost()->NotifyMoveOrResizeStarted();
  }
}

void cef_set_focus(CefBrowserHandle handle, int focus) {
  if (!handle) {
    return;
  }

  BrowserWrapper *wrapper = static_cast<BrowserWrapper *>(handle);
  if (wrapper->browser) {
    wrapper->browser->GetHost()->SetFocus(focus != 0);
  }
}

void cef_set_zoom_level(CefBrowserHandle handle, double zoom_level) {
  if (!handle) {
    return;
  }

  BrowserWrapper *wrapper = static_cast<BrowserWrapper *>(handle);
  if (wrapper->browser) {
    wrapper->browser->GetHost()->SetZoomLevel(zoom_level);
  }
}

double cef_get_zoom_level(CefBrowserHandle handle) {
  if (!handle) {
    return 0.0;
  }

  BrowserWrapper *wrapper = static_cast<BrowserWrapper *>(handle);
  if (wrapper->browser) {
    return wrapper->browser->GetHost()->GetZoomLevel();
  }
  return 0.0;
}

void cef_register_callbacks(
    CefBrowserHandle handle, CefLoadStateCallback load_state_callback,
    CefTitleChangeCallback title_change_callback,
    CefUrlChangeCallback url_change_callback,
    CefFaviconUrlChangeCallback favicon_url_change_callback,
    CefSnapshotReadyCallback snapshot_ready_callback,
    CefOpenLinkAsChildTabCallback open_link_as_child_tab_callback,
    CefMediaPermissionRequestCallback media_permission_request_callback,
    CefLinkClickCallback link_click_callback) {
  if (!handle) {
    return;
  }

  std::lock_guard<std::mutex> lock(g_callbacks_mutex);

  BrowserCallbacks &callbacks = g_callbacks[handle];
  callbacks.handle = handle;
  callbacks.load_state_callback = load_state_callback;
  callbacks.title_change_callback = title_change_callback;
  callbacks.url_change_callback = url_change_callback;
  callbacks.favicon_url_change_callback = favicon_url_change_callback;
  callbacks.snapshot_ready_callback = snapshot_ready_callback;
  callbacks.open_link_as_child_tab_callback = open_link_as_child_tab_callback;
  callbacks.media_permission_request_callback =
      media_permission_request_callback;
  callbacks.link_click_callback = link_click_callback;

  fprintf(stderr,
          "[CEF] Callbacks registered for browser: %p (snapshot=%s, "
          "childTab=%s, mediaPermission=%s, linkClick=%s)\n",
          handle, snapshot_ready_callback ? "yes" : "no",
          open_link_as_child_tab_callback ? "yes" : "no",
          media_permission_request_callback ? "yes" : "no",
          link_click_callback ? "yes" : "no");
}

// Clean up callbacks when browser is destroyed
void cef_unregister_callbacks(CefBrowserHandle handle) {
  if (!handle) {
    return;
  }

  std::lock_guard<std::mutex> lock(g_callbacks_mutex);
  g_callbacks.erase(handle);

  // Also clean up any pending permission callbacks
  {
    std::lock_guard<std::mutex> perm_lock(g_pending_permission_mutex);
    g_pending_permission_callbacks.erase(handle);
  }

  fprintf(stderr, "[CEF] Callbacks unregistered for browser: %p\n", handle);
}

// Respond to a media permission request
void cef_respond_to_media_permission(CefBrowserHandle handle,
                                     int allowed_permissions) {
  if (!handle)
    return;

  std::lock_guard<std::mutex> lock(g_pending_permission_mutex);
  auto it = g_pending_permission_callbacks.find(handle);

  if (it != g_pending_permission_callbacks.end()) {
    uint32_t permission_flags = 0;
    if (allowed_permissions & 1)
      permission_flags |= CEF_MEDIA_PERMISSION_DEVICE_AUDIO_CAPTURE;
    if (allowed_permissions & 2)
      permission_flags |= CEF_MEDIA_PERMISSION_DEVICE_VIDEO_CAPTURE;

    fprintf(stderr,
            "[CEF Permission] Responding to media permission: 0x%x -> 0x%x\n",
            allowed_permissions, permission_flags);

    it->second->Continue(permission_flags);
    g_pending_permission_callbacks.erase(it);
  } else {
    fprintf(stderr,
            "[CEF Permission] No pending callback found for handle %p\n",
            handle);
  }
}

// =============================================================================
// MARK: - Data Management Implementation
// =============================================================================

void cef_delete_cookies(const char *url, const char *cookie_name) {
  CefRefPtr<CefCookieManager> manager =
      CefCookieManager::GetGlobalManager(nullptr);

  if (manager) {
    CefString urlStr = url ? url : "";
    CefString nameStr = cookie_name ? cookie_name : "";

    // Delete cookies (asynchronous)
    manager->DeleteCookies(urlStr, nameStr, nullptr);

    fprintf(stderr, "[CEF Data] Deleted cookies (url: %s, name: %s)\n",
            url ? url : "all", cookie_name ? cookie_name : "all");
  } else {
    fprintf(stderr, "[CEF Data] Failed to get global cookie manager\n");
  }
}

// =============================================================================
// MARK: - Editing Commands
// =============================================================================

void cef_copy(CefBrowserHandle handle) {
  if (!handle) {
    return;
  }

  BrowserWrapper *wrapper = static_cast<BrowserWrapper *>(handle);
  if (wrapper->browser) {
    CefRefPtr<CefFrame> frame = wrapper->browser->GetMainFrame();
    if (frame) {
      frame->Copy();
    }
  }
}

void cef_cut(CefBrowserHandle handle) {
  if (!handle) {
    return;
  }

  BrowserWrapper *wrapper = static_cast<BrowserWrapper *>(handle);
  if (wrapper->browser) {
    CefRefPtr<CefFrame> frame = wrapper->browser->GetMainFrame();
    if (frame) {
      frame->Cut();
    }
  }
}

void cef_paste(CefBrowserHandle handle) {
  if (!handle) {
    return;
  }

  BrowserWrapper *wrapper = static_cast<BrowserWrapper *>(handle);
  if (wrapper->browser) {
    CefRefPtr<CefFrame> frame = wrapper->browser->GetMainFrame();
    if (frame) {
      frame->Paste();
    }
  }
}

void cef_select_all(CefBrowserHandle handle) {
  if (!handle) {
    return;
  }

  BrowserWrapper *wrapper = static_cast<BrowserWrapper *>(handle);
  if (wrapper->browser) {
    CefRefPtr<CefFrame> frame = wrapper->browser->GetMainFrame();
    if (frame) {
      frame->SelectAll();
    }
  }
}

void cef_undo(CefBrowserHandle handle) {
  if (!handle) {
    return;
  }

  BrowserWrapper *wrapper = static_cast<BrowserWrapper *>(handle);
  if (wrapper->browser) {
    CefRefPtr<CefFrame> frame = wrapper->browser->GetMainFrame();
    if (frame) {
      frame->Undo();
    }
  }
}

void cef_redo(CefBrowserHandle handle) {
  if (!handle) {
    return;
  }

  BrowserWrapper *wrapper = static_cast<BrowserWrapper *>(handle);
  if (wrapper->browser) {
    CefRefPtr<CefFrame> frame = wrapper->browser->GetMainFrame();
    if (frame) {
      frame->Redo();
    }
  }
}

void cef_print(CefBrowserHandle handle) {
  if (!handle) {
    return;
  }

  BrowserWrapper *wrapper = static_cast<BrowserWrapper *>(handle);
  if (wrapper->browser) {
    wrapper->browser->GetHost()->Print();
  }
}

// =============================================================================
// MARK: - Extension Management
// =============================================================================

// Extension callbacks
static CefExtensionLoadedCallback g_extension_loaded_callback = nullptr;
static CefExtensionLoadFailedCallback g_extension_load_failed_callback =
    nullptr;
static CefExtensionUnloadedCallback g_extension_unloaded_callback = nullptr;

void cef_register_extension_callbacks(
    CefExtensionLoadedCallback loaded_callback,
    CefExtensionLoadFailedCallback load_failed_callback,
    CefExtensionUnloadedCallback unloaded_callback) {
  g_extension_loaded_callback = loaded_callback;
  g_extension_load_failed_callback = load_failed_callback;
  g_extension_unloaded_callback = unloaded_callback;
}

void cef_load_extension(const char *path) {
  if (!path)
    return;

  // Get global request context
  CefRefPtr<CefRequestContext> context = CefRequestContext::GetGlobalContext();
  if (!context) {
    fprintf(
        stderr,
        "[CEF] Failed to get global request context for extension loading\n");
    return;
  }

  std::string pathStr = path;
  fprintf(stderr, "[CEF] Loading extension from: %s\n", pathStr.c_str());

  // We're not passing a handler yet, so we won't get callbacks
  // TODO: Implement CefExtensionHandler
  // context->LoadExtension(pathStr, nullptr, nullptr);
  fprintf(stderr,
          "[CEF] LoadExtension not available in CefRequestContext. Please "
          "restart the application to load the extension via command line.\n");
}

void cef_unload_extension(const char *extension_id) {
  if (!extension_id)
    return;
  fprintf(stderr, "[CEF] Unload extension not implemented for ID: %s\n",
          extension_id);
  // Implementation requires tracking CefExtension objects
}

const char *cef_get_extension_info_json(void) {
  // Return empty JSON array for now as we're not tracking extensions yet
  // Caller expects to free this string
  return strdup("[]");
}

void cef_free_string(const char *str) {
  if (str) {
    free((void *)str);
  }
}

} // extern "C"

// =============================================================================
// MARK: - Tab Preview Snapshot Implementation
// =============================================================================

#if defined(__APPLE__)
#include <Accelerate/Accelerate.h>
#include <CoreGraphics/CoreGraphics.h>
#include <objc/message.h>
#include <objc/objc.h>
#include <objc/runtime.h>

// Helper function to resize RGBA image data using Accelerate framework
// Returns new buffer that caller must free(), or nullptr on failure
static uint8_t *resize_rgba_image(const uint8_t *src_buffer, int src_width,
                                  int src_height, int dst_width,
                                  int dst_height) {
  if (!src_buffer || src_width <= 0 || src_height <= 0 || dst_width <= 0 ||
      dst_height <= 0) {
    return nullptr;
  }

  // Allocate destination buffer
  size_t dst_size = dst_width * dst_height * 4;
  uint8_t *dst_buffer = (uint8_t *)malloc(dst_size);
  if (!dst_buffer) {
    return nullptr;
  }

  // Set up vImage buffers
  vImage_Buffer src = {.data = (void *)src_buffer,
                       .height = (vImagePixelCount)src_height,
                       .width = (vImagePixelCount)src_width,
                       .rowBytes = (size_t)(src_width * 4)};

  vImage_Buffer dst = {.data = dst_buffer,
                       .height = (vImagePixelCount)dst_height,
                       .width = (vImagePixelCount)dst_width,
                       .rowBytes = (size_t)(dst_width * 4)};

  // Perform high-quality scaling
  vImage_Error error =
      vImageScale_ARGB8888(&src, &dst, nullptr, kvImageHighQualityResampling);

  if (error != kvImageNoError) {
    free(dst_buffer);
    fprintf(stderr, "[CEF Snapshot] vImage scaling failed with error: %ld\n",
            error);
    return nullptr;
  }

  return dst_buffer;
}

extern "C" {

int cef_capture_snapshot(CefBrowserHandle handle, int max_width,
                         CefSnapshotCallback callback) {
  if (!handle || !callback || max_width <= 0) {
    fprintf(stderr,
            "[CEF Snapshot] Invalid parameters: handle=%p, callback=%p, "
            "max_width=%d\n",
            handle, (void *)callback, max_width);
    return 0;
  }

  BrowserWrapper *wrapper = static_cast<BrowserWrapper *>(handle);
  if (!wrapper->browser) {
    fprintf(stderr, "[CEF Snapshot] No browser instance\n");
    return 0;
  }

  // Get the NSView handle from CEF browser
  void *window_handle = wrapper->browser->GetHost()->GetWindowHandle();
  if (!window_handle) {
    fprintf(stderr, "[CEF Snapshot] No window handle available\n");
    return 0;
  }

  fprintf(stderr,
          "[CEF Snapshot] Starting capture for browser %p, max_width: %d\n",
          handle, max_width);

  // Force a repaint to ensure we have the latest content
  // This helps with race conditions where the view might be stale
  wrapper->browser->GetHost()->Invalidate(PET_VIEW);

  // Use Objective-C runtime to snapshot the NSView
  // NSView* view = (NSView*)window_handle;
  id view = (id)window_handle;

  // Get the view bounds: CGRect bounds = [view bounds];
  CGRect (*boundsIMP)(id, SEL) = (CGRect(*)(id, SEL))objc_msgSend;
  CGRect bounds = boundsIMP(view, sel_registerName("bounds"));

  if (bounds.size.width <= 0 || bounds.size.height <= 0) {
    fprintf(stderr,
            "[CEF Snapshot] Invalid view bounds: %.0fx%.0f - forcing minimum "
            "size\n",
            bounds.size.width, bounds.size.height);
    // Try to get frame instead if bounds is invalid
    CGRect frame = boundsIMP(view, sel_registerName("frame"));
    if (frame.size.width > 0 && frame.size.height > 0) {
      bounds.size = frame.size;
      fprintf(stderr, "[CEF Snapshot] Using frame size instead: %.0fx%.0f\n",
              bounds.size.width, bounds.size.height);
    } else {
      return 0;
    }
  }

  int src_width = (int)bounds.size.width;
  int src_height = (int)bounds.size.height;

  fprintf(stderr, "[CEF Snapshot] View size: %dx%d\n", src_width, src_height);

  // Create bitmap context to render the view
  CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
  if (!colorSpace) {
    fprintf(stderr, "[CEF Snapshot] Failed to create color space\n");
    return 0;
  }

  size_t src_buffer_size = src_width * src_height * 4;
  uint8_t *src_buffer = (uint8_t *)calloc(1, src_buffer_size);
  if (!src_buffer) {
    CGColorSpaceRelease(colorSpace);
    fprintf(stderr, "[CEF Snapshot] Failed to allocate source buffer\n");
    return 0;
  }

  CGContextRef context = CGBitmapContextCreate(
      src_buffer, src_width, src_height,
      8,             // bits per component
      src_width * 4, // bytes per row
      colorSpace,
      kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big // RGBA
  );

  CGColorSpaceRelease(colorSpace);

  if (!context) {
    free(src_buffer);
    fprintf(stderr, "[CEF Snapshot] Failed to create bitmap context\n");
    return 0;
  }

  // Get NSGraphicsContext from CGContext
  // NSGraphicsContext* nsContext = [NSGraphicsContext
  // graphicsContextWithCGContext:context flipped:NO];
  Class NSGraphicsContextClass = objc_getClass("NSGraphicsContext");
  SEL graphicsContextSel =
      sel_registerName("graphicsContextWithCGContext:flipped:");
  id (*contextIMP)(Class, SEL, CGContextRef, BOOL) =
      (id(*)(Class, SEL, CGContextRef, BOOL))objc_msgSend;
  id nsContext =
      contextIMP(NSGraphicsContextClass, graphicsContextSel, context, NO);

  if (!nsContext) {
    CGContextRelease(context);
    free(src_buffer);
    fprintf(stderr, "[CEF Snapshot] Failed to create NSGraphicsContext\n");
    return 0;
  }

  // Save current graphics context and set the new one
  // [NSGraphicsContext saveGraphicsState];
  void (*saveStateIMP)(Class, SEL) = (void (*)(Class, SEL))objc_msgSend;
  saveStateIMP(NSGraphicsContextClass, sel_registerName("saveGraphicsState"));

  // [NSGraphicsContext setCurrentContext:nsContext];
  void (*setContextIMP)(Class, SEL, id) =
      (void (*)(Class, SEL, id))objc_msgSend;
  setContextIMP(NSGraphicsContextClass, sel_registerName("setCurrentContext:"),
                nsContext);

  // Render the view hierarchy
  // BOOL cacheDisplay = YES;
  // NSBitmapImageRep* rep = [view
  // bitmapImageRepForCachingDisplayInRect:bounds]; [view
  // cacheDisplayInRect:bounds toBitmapImageRep:rep];

  // Alternative: Use layer-based rendering if available
  // CALayer* layer = [view layer];
  id (*layerIMP)(id, SEL) = (id(*)(id, SEL))objc_msgSend;
  id layer = layerIMP(view, sel_registerName("layer"));

  if (layer) {
    // [layer renderInContext:context];
    void (*renderIMP)(id, SEL, CGContextRef) =
        (void (*)(id, SEL, CGContextRef))objc_msgSend;
    renderIMP(layer, sel_registerName("renderInContext:"), context);
    fprintf(stderr, "[CEF Snapshot] Rendered via CALayer\n");
  } else {
    // Fallback: try displayRectIgnoringOpacity:inContext:
    // This requires NSGraphicsContext but works with most views
    // Note: This may not capture CEF's hardware-accelerated content
    fprintf(stderr, "[CEF Snapshot] No layer available, trying displayRect\n");

    // Try the cacheDisplayInRect approach
    SEL bitmapRepSel =
        sel_registerName("bitmapImageRepForCachingDisplayInRect:");
    id (*bitmapRepIMP)(id, SEL, CGRect) = (id(*)(id, SEL, CGRect))objc_msgSend;
    id bitmapRep = bitmapRepIMP(view, bitmapRepSel, bounds);

    if (bitmapRep) {
      SEL cacheDisplaySel =
          sel_registerName("cacheDisplayInRect:toBitmapImageRep:");
      void (*cacheDisplayIMP)(id, SEL, CGRect, id) =
          (void (*)(id, SEL, CGRect, id))objc_msgSend;
      cacheDisplayIMP(view, cacheDisplaySel, bounds, bitmapRep);

      // Get the CGImage from bitmap rep
      SEL cgImageSel = sel_registerName("CGImage");
      CGImageRef (*cgImageIMP)(id, SEL) = (CGImageRef(*)(id, SEL))objc_msgSend;
      CGImageRef cgImage = cgImageIMP(bitmapRep, cgImageSel);

      if (cgImage) {
        CGContextDrawImage(context, bounds, cgImage);
      }
    }
  }

  // Restore graphics context
  // [NSGraphicsContext restoreGraphicsState];
  void (*restoreStateIMP)(Class, SEL) = (void (*)(Class, SEL))objc_msgSend;
  restoreStateIMP(NSGraphicsContextClass,
                  sel_registerName("restoreGraphicsState"));

  CGContextRelease(context);

  // Calculate target dimensions maintaining aspect ratio
  float aspect_ratio = (float)src_height / (float)src_width;
  int dst_width = max_width;
  int dst_height = (int)(max_width * aspect_ratio);

  // Ensure minimum dimensions
  if (dst_height < 1)
    dst_height = 1;

  fprintf(stderr, "[CEF Snapshot] Resizing from %dx%d to %dx%d\n", src_width,
          src_height, dst_width, dst_height);

  // Resize the image using Accelerate framework
  uint8_t *dst_buffer = resize_rgba_image(src_buffer, src_width, src_height,
                                          dst_width, dst_height);

  free(src_buffer); // Done with source buffer

  if (!dst_buffer) {
    fprintf(stderr, "[CEF Snapshot] Resize failed\n");
    return 0;
  }

  // Invoke callback with resized data
  size_t dst_buffer_size = dst_width * dst_height * 4;
  callback(dst_buffer, dst_width, dst_height, dst_buffer_size);

  free(dst_buffer);

  fprintf(stderr, "[CEF Snapshot] Capture complete: %dx%d (%zu bytes)\n",
          dst_width, dst_height, dst_buffer_size);

  return 1;
}

} // extern "C" for cef_capture_snapshot

#else
// Non-macOS stub
extern "C" {
int cef_capture_snapshot(CefBrowserHandle handle, int max_width,
                         CefSnapshotCallback callback) {
  fprintf(stderr, "[CEF Snapshot] Not implemented on this platform\n");
  return 0;
}
} // extern "C"
#endif
