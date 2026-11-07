import Flutter
import ImageIO
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let invoiceImageQueue = DispatchQueue(
    label: "paxfox.invoice-image-preparation",
    qos: .userInitiated
  )
  private var invoiceImageChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "InvoiceImagePreparation"
    ) else { return }
    let channel = FlutterMethodChannel(
      name: "paxfox/invoice_images",
      binaryMessenger: registrar.messenger()
    )
    let queue = invoiceImageQueue
    channel.setMethodCallHandler { call, result in
      guard call.method == "prepare" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let arguments = call.arguments as? [String: Any],
        let path = arguments["path"] as? String,
        !path.isEmpty
      else {
        result(FlutterError(
          code: "image_preparation",
          message: "Cannot read this invoice image.",
          details: nil
        ))
        return
      }
      // Serial native decoding bounds peak memory when several pages arrive.
      // Never run image decoding or JPEG encoding on Flutter's platform thread.
      queue.async {
        let response: Any = autoreleasepool {
          do {
            return FlutterStandardTypedData(bytes: try prepareInvoiceImage(at: path))
          } catch let error as InvoiceImagePreparationError {
            return FlutterError(
              code: "image_preparation",
              message: error.message,
              details: nil
            )
          } catch {
            return FlutterError(
              code: "image_preparation",
              message: "Cannot read this invoice image.",
              details: nil
            )
          }
        }
        DispatchQueue.main.async { result(response) }
      }
    }
    invoiceImageChannel = channel
  }
}

private enum InvoiceImagePreparationError: Error {
  case tooLarge
  case unsupported

  var message: String {
    switch self {
    case .tooLarge:
      return "An image is too large (25 MB limit)."
    case .unsupported:
      return "Unsupported invoice image."
    }
  }
}

private func prepareInvoiceImage(at path: String) throws -> Data {
  let maximumSourceBytes = 25 * 1024 * 1024
  let targetBytes = 1024 * 1024
  let maximumPixels = 4_000_000.0
  let url = URL(fileURLWithPath: path)
  let attributes = try FileManager.default.attributesOfItem(atPath: path)
  guard let sourceSize = attributes[.size] as? NSNumber else {
    throw InvoiceImagePreparationError.unsupported
  }
  guard sourceSize.int64Value <= Int64(maximumSourceBytes) else {
    throw InvoiceImagePreparationError.tooLarge
  }
  let bytes = try Data(contentsOf: url, options: .mappedIfSafe)
  guard bytes.count <= maximumSourceBytes else {
    throw InvoiceImagePreparationError.tooLarge
  }
  guard !bytes.isEmpty,
    let source = CGImageSourceCreateWithData(
      bytes as CFData,
      [kCGImageSourceShouldCache: false] as CFDictionary
    ),
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
      as? [CFString: Any],
    let pixelWidth = properties[kCGImagePropertyPixelWidth] as? NSNumber,
    let pixelHeight = properties[kCGImagePropertyPixelHeight] as? NSNumber
  else {
    throw InvoiceImagePreparationError.unsupported
  }
  let width = pixelWidth.doubleValue
  let height = pixelHeight.doubleValue
  guard width.isFinite, height.isFinite, width > 0, height > 0 else {
    throw InvoiceImagePreparationError.unsupported
  }
  let shortEdge = min(width, height)
  let longEdge = max(width, height)
  let pixelCount = width * height
  let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
  let isJpeg = CGImageSourceGetType(source).map { $0 as String } == UTType.jpeg.identifier
  // Inspect metadata before requesting any pixels: compatible small JPEGs need
  // neither a decode nor another lossy encode, and remain byte-identical.
  if isJpeg && orientation == 1 && bytes.count <= targetBytes
    && shortEdge <= 2000 && longEdge <= 6000 && pixelCount <= maximumPixels {
    return bytes
  }

  let scale = min(
    1.0,
    min(2000.0 / shortEdge, min(6000.0 / longEdge, sqrt(maximumPixels / pixelCount)))
  )
  var maximumDimension = max(1, Int(floor(longEdge * scale)))
  // Account for ImageIO rounding the other edge up to a whole pixel.
  while maximumDimension > 1
    && Double(maximumDimension) * ceil(Double(maximumDimension) * shortEdge / longEdge)
      > maximumPixels {
    maximumDimension -= 1
  }
  let thumbnailOptions: [CFString: Any] = [
    kCGImageSourceCreateThumbnailFromImageAlways: true,
    kCGImageSourceCreateThumbnailWithTransform: true,
    kCGImageSourceThumbnailMaxPixelSize: maximumDimension,
    kCGImageSourceShouldCacheImmediately: true,
  ]
  // ImageIO performs decoder-level downsampling and applies EXIF orientation;
  // a full camera-sized bitmap and a PNG round trip are never requested.
  guard let image = CGImageSourceCreateThumbnailAtIndex(
    source, 0, thumbnailOptions as CFDictionary
  ) else {
    throw InvoiceImagePreparationError.unsupported
  }
  let output = NSMutableData()
  guard let destination = CGImageDestinationCreateWithData(
    output as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil
  ) else {
    throw InvoiceImagePreparationError.unsupported
  }
  // ImageIO's documented default composites alpha onto white for JPEG. Keep
  // that default rather than allocating another bitmap for opaque camera photos.
  CGImageDestinationAddImage(
    destination,
    image,
    [kCGImageDestinationLossyCompressionQuality: 0.86] as CFDictionary
  )
  guard CGImageDestinationFinalize(destination) else {
    throw InvoiceImagePreparationError.unsupported
  }
  return output as Data
}
