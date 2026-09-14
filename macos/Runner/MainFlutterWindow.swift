import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  // Retained while a long background task (e.g. the model download) is in
  // flight, so it can be ended later. macOS's App Nap throttles a minimized
  // or non-frontmost app's network/timer activity, which was cutting off a
  // multi-GB download mid-transfer when the window was minimized — this
  // activity token tells the OS not to do that for the duration.
  private var backgroundActivityToken: NSObjectProtocol?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    var windowFrame = self.frame
    self.contentViewController = flutterViewController

    let activityChannel = FlutterMethodChannel(
      name: "project_echo/background_activity",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    activityChannel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "begin":
        if self?.backgroundActivityToken == nil {
          self?.backgroundActivityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Downloading model"
          )
        }
        result(nil)
      case "end":
        if let token = self?.backgroundActivityToken {
          ProcessInfo.processInfo.endActivity(token)
          self?.backgroundActivityToken = nil
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let systemInfoChannel = FlutterMethodChannel(
      name: "project_echo/system_info",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    systemInfoChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "computerName":
        // Host.current().localizedName is the same friendly name shown in
        // System Settings → General → Sharing — not the bare network
        // hostname (Platform.localHostname on the Dart side), which is often
        // a short, unrelated-looking string.
        result(Host.current().localizedName)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    // Floor the window size so the desktop layout always has room — smaller
    // than this and Flutter's Rows overflow. Set BEFORE re-applying the
    // restored frame: macOS restores whatever frame was last saved (which can
    // be smaller than this floor from before it existed, or from dragging the
    // window small in a previous session), and minSize alone only constrains
    // *future* resizes — it does not grow an already-too-small frame. Clamp
    // the frame itself here so a stale small frame can't persist across launches.
    let minSize = NSSize(width: 960, height: 680)
    self.minSize = minSize
    if windowFrame.width < minSize.width || windowFrame.height < minSize.height {
      windowFrame.size.width = max(windowFrame.width, minSize.width)
      windowFrame.size.height = max(windowFrame.height, minSize.height)
    }
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
