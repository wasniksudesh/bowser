// MediaPermissionDialog.swift - Native macOS Permission Dialog
// Handles camera and microphone permission requests from websites

import AVFoundation
import AppKit

/// Utility class to handle media permission requests
@MainActor
final class MediaPermissionDialog {

  /// Permission types
  enum PermissionType {
    case camera
    case microphone
    case both

    var description: String {
      switch self {
      case .camera: return "camera"
      case .microphone: return "microphone"
      case .both: return "camera and microphone"
      }
    }
  }

  /// Show permission dialog and request macOS system permissions if needed
  /// - Parameters:
  ///   - origin: The website origin requesting permission
  ///   - requestedPermissions: Bitfield (1=audio, 2=video, 3=both)
  ///   - completion: Called with allowed permissions bitfield (0=deny, 1=audio, 2=video, 3=both)
  static func requestPermission(
    origin: String,
    requestedPermissions: Int,
    completion: @escaping (Int) -> Void
  ) {
    print("[MediaPermissionDialog] 🚨 requestPermission called for \(origin)")
    // Determine what's being requested
    let needsAudio = (requestedPermissions & 0x01) != 0
    let needsVideo = (requestedPermissions & 0x02) != 0

    let permissionType: PermissionType
    if needsAudio && needsVideo {
      permissionType = .both
    } else if needsAudio {
      permissionType = .microphone
    } else if needsVideo {
      permissionType = .camera
    } else {
      // No valid permissions requested
      completion(0)
      return
    }

    print("[MediaPermission] Request from \(origin) for \(permissionType.description)")

    // Check and request macOS system permissions first
    Task {
      var systemGranted = true

      // Check camera permission if needed
      if needsVideo {
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        if cameraStatus == .notDetermined {
          systemGranted = await AVCaptureDevice.requestAccess(for: .video)
        } else if cameraStatus != .authorized {
          systemGranted = false
        }
      }

      // Check microphone permission if needed
      if needsAudio && systemGranted {
        let micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if micStatus == .notDetermined {
          systemGranted = await AVCaptureDevice.requestAccess(for: .audio)
        } else if micStatus != .authorized {
          systemGranted = false
        }
      }

      // If macOS denied, show error and deny
      guard systemGranted else {
        await showSystemPermissionDeniedAlert(permissionType: permissionType)
        completion(0)
        return
      }

      // macOS permissions granted, now show browser permission dialog
      await showBrowserPermissionDialog(
        origin: origin,
        permissionType: permissionType,
        requestedPermissions: requestedPermissions,
        completion: completion
      )
    }
  }

  /// Show alert when macOS system permissions are denied
  private static func showSystemPermissionDeniedAlert(permissionType: PermissionType) async {
    let alert = NSAlert()
    alert.messageText = "System Permission Required"
    let settingsName =
      (permissionType == .camera || permissionType == .both) ? "Camera" : "Microphone"
    alert.informativeText =
      "Bowser needs \(permissionType.description) access to be enabled in System Settings.\n\nPlease go to System Settings > Privacy & Security > \(settingsName) and enable access for Bowser."
    alert.alertStyle = .warning
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }

  /// Show browser permission dialog for website
  private static func showBrowserPermissionDialog(
    origin: String,
    permissionType: PermissionType,
    requestedPermissions: Int,
    completion: @escaping (Int) -> Void
  ) async {
    let alert = NSAlert()
    alert.messageText = "Allow \(origin) to access your \(permissionType.description)?"
    alert.informativeText =
      "This website is requesting permission to use your \(permissionType.description)."
    alert.alertStyle = .informational
    alert.addButton(withTitle: "Allow")
    alert.addButton(withTitle: "Deny")

    let response = alert.runModal()

    if response == .alertFirstButtonReturn {
      // User clicked "Allow" - grant the requested permissions
      print("[MediaPermission] User allowed \(permissionType.description) for \(origin)")
      completion(requestedPermissions)
    } else {
      // User clicked "Deny" - deny all permissions
      print("[MediaPermission] User denied \(permissionType.description) for \(origin)")
      completion(0)
    }
  }
}
