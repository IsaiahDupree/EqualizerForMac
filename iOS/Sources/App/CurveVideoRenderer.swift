import AVFoundation
import SwiftUI

struct CurveVideoFrame: Equatable {
    let title: String
    let settings: MobileEQSettings
    let sampleRate: Double
    let progress: Double
    var showsSignal = false
    var outputAnalysis: AudioAnalysisFrame?
}

@MainActor
final class CurveVideoRenderer {
    private let size = CGSize(width: 480, height: 270)
    private let pool: CVPixelBufferPool?

    init() {
        var pool: CVPixelBufferPool?
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height),
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]
        CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
        self.pool = pool
    }

    func render(_ frame: CurveVideoFrame) -> CMSampleBuffer? {
        var buffer: CVPixelBuffer?
        guard let pool, CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess,
              let buffer else { return nil }
        guard CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let bitmap = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        guard let address = CVPixelBufferGetBaseAddress(buffer),
              let context = CGContext(data: address, width: Int(size.width), height: Int(size.height),
                                      bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmap) else { return nil }
        let renderer = ImageRenderer(content: video(frame))
        renderer.isOpaque = true
        renderer.render { _, draw in draw(context) }

        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: buffer,
                                                           formatDescriptionOut: &format) == noErr, let format else { return nil }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 5),
                                        presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
                                        decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: buffer, formatDescription: format,
                                                      sampleTiming: &timing, sampleBufferOut: &sample) == noErr else {
            return nil
        }
        return sample
    }

    private func video(_ frame: CurveVideoFrame) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(frame.title)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 8)
            if frame.showsSignal {
                AudioSpectrumView(frame: frame.outputAnalysis).frame(height: 136)
                AudioWaveformView(frame: frame.outputAnalysis).frame(height: 59)
            } else {
                ResponsePlot(bands: frame.settings.bands, sampleRate: frame.sampleRate, selection: nil,
                             bypassed: frame.settings.bypassed)
            }
            GeometryReader { geometry in
                Capsule().fill(.white.opacity(0.2))
                    .overlay(alignment: .leading) {
                        Capsule().fill(Color(red: 0.57, green: 0.73, blue: 1))
                            .frame(width: geometry.size.width * frame.progress)
                    }
            }
            .frame(height: 4)
            .padding(.horizontal, 8)
        }
        .padding(.horizontal, 12)
        .frame(width: size.width, height: size.height)
        .background(Color(red: 0.05, green: 0.07, blue: 0.12))
    }
}
