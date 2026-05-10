import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  // Flutter ↔ native 사이 채널: themeMode 동기화용.
  private var appearanceChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // macOS 모던 앱 패턴 (Notion / Linear / Slack):
    //  - titlebarAppearsTransparent + fullSizeContentView 로 traffic light 영역까지 Flutter 가 그리도록.
    //  - NSWindow.backgroundColor 는 NSColor.windowBackgroundColor (NSAppearance 따라 자동 light/dark).
    //  - NSAppearance 자체는 Flutter 의 themeMode 변경 시 platform channel 로 토글한다.
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)
    self.isMovableByWindowBackground = false
    self.backgroundColor = NSColor.windowBackgroundColor

    // ── Platform channel: app/appearance ─────────────────────────
    // Flutter 가 'setMode' 호출 → 'light' / 'dark' / 'system' 인자 받아
    // NSApp.appearance 를 그에 맞춰 지정.
    let messenger = flutterViewController.engine.binaryMessenger
    let channel = FlutterMethodChannel(
      name: "app/appearance",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { (call, result) in
      if call.method == "setMode" {
        let mode = (call.arguments as? String) ?? "system"
        switch mode {
        case "light":
          NSApp.appearance = NSAppearance(named: .aqua)
        case "dark":
          NSApp.appearance = NSAppearance(named: .darkAqua)
        default:
          NSApp.appearance = nil // system 따라감
        }
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    self.appearanceChannel = channel

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
