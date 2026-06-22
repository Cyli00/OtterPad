import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
    static var shareChannel: FlutterMethodChannel?
    static var pendingPdfPaths: [String] = []

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
        GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

        guard let registrar = engineBridge.pluginRegistry.registrar(
            forPlugin: "OtterPadShareReceiver"
        ) else { return }

        let channel = FlutterMethodChannel(
            name: "io.github.cyli00.otterpad/share",
            binaryMessenger: registrar.messenger()
        )
        channel.setMethodCallHandler { call, result in
            switch call.method {
            case "getInitialSharedFiles":
                let paths = AppDelegate.pendingPdfPaths
                AppDelegate.pendingPdfPaths.removeAll()
                result(paths.isEmpty ? nil : paths)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
        AppDelegate.shareChannel = channel
    }

    static func handleFileUrl(_ url: URL) {
        guard url.pathExtension.lowercased() == "pdf" else { return }

        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shared_pdfs")
        try? FileManager.default.createDirectory(
            at: tempDir, withIntermediateDirectories: true
        )

        let fileName = "\(UUID().uuidString)_\(url.lastPathComponent)"
        let destUrl = tempDir.appendingPathComponent(fileName)
        try? FileManager.default.removeItem(at: destUrl)

        guard (try? FileManager.default.copyItem(at: url, to: destUrl)) != nil else {
            return
        }

        let path = destUrl.path
        if let channel = shareChannel {
            channel.invokeMethod("onSharedFiles", arguments: [path])
        } else {
            pendingPdfPaths.append(path)
        }
    }
}
