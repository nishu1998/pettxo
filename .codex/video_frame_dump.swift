import Foundation
import AVFoundation
import AppKit

guard CommandLine.arguments.count >= 3 else {
  fputs("usage: video_frame_dump <input> <outputDir>\n", stderr)
  Foundation.exit(2)
}

let input = URL(fileURLWithPath: CommandLine.arguments[1])
let outputDir = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
try? FileManager.default.createDirectory(
  at: outputDir,
  withIntermediateDirectories: true,
)

let asset = AVURLAsset(url: input)
let duration = CMTimeGetSeconds(asset.duration)
let generator = AVAssetImageGenerator(asset: asset)
generator.appliesPreferredTrackTransform = true
generator.maximumSize = CGSize(width: 600, height: 600)

let samples = 6
for index in 0..<samples {
  let progress = samples == 1 ? 0.0 : Double(index) / Double(samples - 1)
  let seconds = duration * progress
  let time = CMTime(seconds: seconds, preferredTimescale: 600)

  do {
    let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
    let image = NSImage(cgImage: cgImage, size: .zero)
    guard
      let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:])
    else {
      continue
    }

    let fileURL = outputDir.appendingPathComponent(
      String(format: "frame_%02d.png", index),
    )
    try png.write(to: fileURL)
    print("\(index):\(seconds):\(fileURL.path)")
  } catch {
    print("frame \(index) failed: \(error)")
  }
}

if let track = asset.tracks(withMediaType: .video).first {
  let transformed = track.naturalSize.applying(track.preferredTransform)
  print("duration=\(duration)")
  print("size=\(abs(transformed.width))x\(abs(transformed.height))")
  print("fps=\(track.nominalFrameRate)")
}
