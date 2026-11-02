import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    let channel = FlutterMethodChannel(name: "ripot/report_clipboard", binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "write" else { result(FlutterMethodNotImplemented); return }
      guard let args = call.arguments as? [String: String],
            let text = args["text"], let html = args["html"] else {
        result(FlutterError(code: "arguments", message: "Missing report text.", details: nil)); return
      }
      let item = NSPasteboardItem()
      item.setString(text, forType: .string)
      item.setString(html, forType: .html)
      NSPasteboard.general.clearContents()
      if NSPasteboard.general.writeObjects([item]) { result(nil) }
      else { result(FlutterError(code: "clipboard", message: "Clipboard is unavailable. Try again.", details: nil)) }
    }

    super.awakeFromNib()
  }
}
