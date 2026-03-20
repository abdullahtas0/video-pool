import AVFoundation
import Flutter

class ThumbnailExtractor {
    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "dev.video_pool/thumbnail",
            binaryMessenger: registrar.messenger()
        )
        channel.setMethodCallHandler { call, result in
            guard call.method == "extractThumbnail",
                  let args = call.arguments as? [String: String],
                  let videoPath = args["videoPath"],
                  let outputPath = args["outputPath"] else {
                result(FlutterError(
                    code: "INVALID_ARGS",
                    message: "Missing videoPath or outputPath",
                    details: nil
                ))
                return
            }

            extractThumbnail(videoPath: videoPath, outputPath: outputPath, result: result)
        }
    }

    static func extractThumbnail(
        videoPath: String,
        outputPath: String,
        result: @escaping FlutterResult
    ) {
        DispatchQueue.global(qos: .utility).async {
            let url = URL(fileURLWithPath: videoPath)
            let asset = AVAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 480, height: 480)

            let time = CMTime(seconds: 0.0, preferredTimescale: 600)

            do {
                let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
                let uiImage = UIImage(cgImage: cgImage)
                guard let data = uiImage.jpegData(compressionQuality: 0.7) else {
                    DispatchQueue.main.async { result(nil) }
                    return
                }
                try data.write(to: URL(fileURLWithPath: outputPath))
                DispatchQueue.main.async { result(outputPath) }
            } catch {
                DispatchQueue.main.async { result(nil) }
            }
        }
    }
}
