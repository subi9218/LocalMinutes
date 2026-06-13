import Cocoa
import FlutterMacOS
import Security

class MainFlutterWindow: NSWindow {
  // Flutter ↔ native 사이 채널: themeMode 동기화용.
  private var appearanceChannel: FlutterMethodChannel?
  private var bookmarkChannel: FlutterMethodChannel?
  private var systemAudioChannel: FlutterMethodChannel?
  private var activeSecurityScopedURLs: [String: URL] = [:]
  // 온라인 회의용 시스템 오디오 캡처 (macOS 14.2+). 미지원 OS에서는 nil 유지.
  private var systemAudioRecorder: AnyObject?

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

    // App Store sandbox에서 사용자가 선택한 녹음 저장 폴더 권한을
    // 앱 재실행 뒤에도 복원하기 위한 security-scoped bookmark 처리.
    let bookmarkChannel = FlutterMethodChannel(
      name: "app/security_scoped_bookmark",
      binaryMessenger: messenger
    )
    bookmarkChannel.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else {
        result(FlutterError(code: "unavailable", message: "Window is gone", details: nil))
        return
      }

      switch call.method {
      case "isSandboxed":
        let task = SecTaskCreateFromSelf(nil)
        let value = task.flatMap {
          SecTaskCopyValueForEntitlement($0, "com.apple.security.app-sandbox" as CFString, nil)
        }
        result((value as? Bool) == true)

      case "createBookmark":
        guard
          let args = call.arguments as? [String: Any],
          let path = args["path"] as? String,
          !path.isEmpty
        else {
          result(FlutterError(code: "bad_args", message: "Missing path", details: nil))
          return
        }

        DispatchQueue.global(qos: .userInitiated).async {
          do {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            let data = try url.bookmarkData(
              options: [.withSecurityScope],
              includingResourceValuesForKeys: nil,
              relativeTo: nil
            )
            DispatchQueue.main.async {
              result(data.base64EncodedString())
            }
          } catch {
            DispatchQueue.main.async {
              result(FlutterError(code: "bookmark_create_failed", message: error.localizedDescription, details: nil))
            }
          }
        }

      case "startAccessingBookmark":
        guard
          let args = call.arguments as? [String: Any],
          let bookmark = args["bookmark"] as? String,
          let data = Data(base64Encoded: bookmark)
        else {
          result(FlutterError(code: "bad_args", message: "Missing bookmark", details: nil))
          return
        }

        DispatchQueue.global(qos: .userInitiated).async {
          do {
            var stale = false
            let url = try URL(
              resolvingBookmarkData: data,
              options: [.withSecurityScope],
              relativeTo: nil,
              bookmarkDataIsStale: &stale
            )
            let accessing = url.startAccessingSecurityScopedResource()
            DispatchQueue.main.async {
              if accessing {
                self.activeSecurityScopedURLs[bookmark] = url
              }
              result([
                "path": url.path,
                "stale": stale,
                "accessing": accessing
              ])
            }
          } catch {
            DispatchQueue.main.async {
              result(FlutterError(code: "bookmark_resolve_failed", message: error.localizedDescription, details: nil))
            }
          }
        }

      case "stopAccessingBookmark":
        guard
          let args = call.arguments as? [String: Any],
          let bookmark = args["bookmark"] as? String
        else {
          result(nil)
          return
        }
        if let url = self.activeSecurityScopedURLs.removeValue(forKey: bookmark) {
          url.stopAccessingSecurityScopedResource()
        }
        result(nil)

      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.bookmarkChannel = bookmarkChannel

    // ── Platform channel: app/system_audio ───────────────────────
    // 온라인 회의(시스템 출력) 오디오 캡처. macOS 14.2+ 에서만 동작.
    let systemAudioChannel = FlutterMethodChannel(
      name: "app/system_audio",
      binaryMessenger: messenger
    )
    systemAudioChannel.setMethodCallHandler { [weak self] (call, result) in
      guard let self = self else {
        result(FlutterError(code: "unavailable", message: "Window is gone", details: nil))
        return
      }
      switch call.method {
      case "isSupported":
        if #available(macOS 14.2, *) {
          result(true)
        } else {
          result(false)
        }

      case "start":
        guard #available(macOS 14.2, *) else {
          result(FlutterError(code: "unsupported", message: "Requires macOS 14.2+", details: nil))
          return
        }
        guard
          let args = call.arguments as? [String: Any],
          let path = args["path"] as? String,
          !path.isEmpty
        else {
          result(FlutterError(code: "bad_args", message: "Missing path", details: nil))
          return
        }
        let recorder: SystemAudioRecorder
        if let existing = self.systemAudioRecorder as? SystemAudioRecorder {
          recorder = existing
        } else {
          recorder = SystemAudioRecorder()
          self.systemAudioRecorder = recorder
        }
        if let error = recorder.start(outputPath: path) {
          result(FlutterError(code: "start_failed", message: error, details: nil))
        } else {
          result(true)
        }

      case "stop":
        if #available(macOS 14.2, *) {
          (self.systemAudioRecorder as? SystemAudioRecorder)?.stop()
        }
        result(nil)

      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.systemAudioChannel = systemAudioChannel

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
