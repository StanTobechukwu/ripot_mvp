import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: "ripot/report_clipboard", binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { call, result in
        guard call.method == "write" else { result(FlutterMethodNotImplemented); return }
        guard let args = call.arguments as? [String: String],
              let text = args["text"], let html = args["html"] else {
          result(FlutterError(code: "arguments", message: "Missing report text.", details: nil)); return
        }
        UIPasteboard.general.setItems([["public.utf8-plain-text": text, "public.html": Data(html.utf8)]],
                                     options: [.localOnly: true])
        result(nil)
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
