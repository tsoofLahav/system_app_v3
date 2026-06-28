import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    self.minSize = NSSize(width: 900, height: 600)
    self.setContentSize(NSSize(width: 1200, height: 800))

    RegisterGeneratedPlugins(registry: flutterViewController)
    Self.registerClipboardImageChannel(messenger: flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }

  private static func registerClipboardImageChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "system_app/clipboard_image",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "readImage":
        Self.readClipboardImage(result: result)
      case "writeImage":
        if let data = call.arguments as? FlutterStandardTypedData {
          Self.writeClipboardImage(data.data, result: result)
        } else {
          result(FlutterError(code: "bad_args", message: "expected image bytes", details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func readClipboardImage(result: @escaping FlutterResult) {
    let pasteboard = NSPasteboard.general

    if let image = pasteboard.readObjects(forClasses: [NSImage.self], options: nil)?.first as? NSImage,
       let png = pngData(from: image) {
      result(FlutterStandardTypedData(bytes: png))
      return
    }

    if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [NSURL] {
      for url in urls {
        guard let path = url.path else { continue }
        let ext = (path as NSString).pathExtension.lowercased()
        guard ["png", "jpg", "jpeg", "gif", "webp", "bmp", "heic"].contains(ext),
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              !data.isEmpty else { continue }
        result(FlutterStandardTypedData(bytes: data))
        return
      }
    }

    let pngType = NSPasteboard.PasteboardType.png
    if let data = pasteboard.data(forType: pngType), !data.isEmpty {
      result(FlutterStandardTypedData(bytes: data))
      return
    }

    let tiffType = NSPasteboard.PasteboardType.tiff
    if let data = pasteboard.data(forType: tiffType),
       let rep = NSBitmapImageRep(data: data),
       let png = rep.representation(using: .png, properties: [:]),
       !png.isEmpty {
      result(FlutterStandardTypedData(bytes: png))
      return
    }

    result(nil)
  }

  private static func writeClipboardImage(_ data: Data, result: @escaping FlutterResult) {
    let image = NSImage(data: data) ?? NSImage()
    NSPasteboard.general.clearContents()
    NSPasteboard.general.writeObjects([image])
    result(nil)
  }

  private static func pngData(from image: NSImage) -> Data? {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return nil }
    return rep.representation(using: .png, properties: [:])
  }
}
