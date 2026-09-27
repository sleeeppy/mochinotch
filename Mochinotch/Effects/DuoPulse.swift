import AppKit
import CoreImage
import CoreMedia
import Metal
import os
import QuartzCore
import ScreenCaptureKit

enum IconTint {
    static func color(for tool: AgentTool) -> NSColor {
        if let image = icon(for: tool), let sampled = sample(image) {
            return sampled
        }
        return NSColor(tool.tint)
    }

    private static func icon(for tool: AgentTool) -> NSImage? {
        for id in tool.iconBundleIDs {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { continue }
            let image = NSWorkspace.shared.icon(forFile: url.path)
            image.size = NSSize(width: 64, height: 64)
            return image
        }
        for name in tool.appNames {
            let url = URL(fileURLWithPath: "/Applications/\(name).app")
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            let image = NSWorkspace.shared.icon(forFile: url.path)
            image.size = NSSize(width: 64, height: 64)
            return image
        }
        return nil
    }

    /// 테두리의 바탕색은 빼고, 아이콘 본체의 색을 쓴다.
    private static func sample(_ image: NSImage) -> NSColor? {
        let side = 48
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(
            data: &bytes,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
        func components(_ index: Int) -> (Double, Double, Double, Double) {
            (
                Double(bytes[index]) / 255,
                Double(bytes[index + 1]) / 255,
                Double(bytes[index + 2]) / 255,
                Double(bytes[index + 3]) / 255
            )
        }
        var backgroundRed = 0.0, backgroundGreen = 0.0, backgroundBlue = 0.0, backgroundCount = 0.0
        for y in 0..<6 {
            for x in 0..<side {
                for point in [y, side - 1 - y] {
                    let index = (point * side + x) * 4
                    let (r, g, b, a) = components(index)
                    guard a > 0.85 else { continue }
                    backgroundRed += r
                    backgroundGreen += g
                    backgroundBlue += b
                    backgroundCount += 1
                }
            }
        }
        guard backgroundCount > 0 else { return nil }
        backgroundRed /= backgroundCount
        backgroundGreen /= backgroundCount
        backgroundBlue /= backgroundCount
        var red = 0.0, green = 0.0, blue = 0.0, weight = 0.0
        for index in stride(from: 0, to: bytes.count, by: 4) {
            let (r, g, b, a) = components(index)
            guard a > 0.85 else { continue }
            let dr = r - backgroundRed
            let dg = g - backgroundGreen
            let db = b - backgroundBlue
            let distance = (dr * dr + dg * dg + db * db).squareRoot()
            guard distance > 0.14 else { continue }
            let sampleWeight = distance * distance
            red += r * sampleWeight
            green += g * sampleWeight
            blue += b * sampleWeight
            weight += sampleWeight
        }
        guard weight > 0 else { return nil }
        return NSColor(srgbRed: red / weight, green: green / weight, blue: blue / weight, alpha: 1)
    }
}

enum DuoStudy: Int, CaseIterable, Sendable {
    case lens
    case pinch
    case prism
    case focus

    var title: String {
        switch self {
        case .focus: return "시안 1 · 초점"
        case .lens: return "시안 2 · 렌즈"
        case .pinch: return "시안 3 · 모으기"
        case .prism: return "시안 4 · 프리즘"
        }
    }
}

/// Cursor, Claude, Codex가 끝날 때, 찍힌 화면 자체를 가장자리에서 유리처럼 굴절시킨다.
/// 선으로 테두리를 그리지 않는다. 앱 색은 휜 가장자리에만 얇게 섞인다.
@MainActor
final class DuoPulse: NSObject {
    static let shared = DuoPulse()

    var onStatus: ((String?) -> Void)?

    private var window: NSWindow?
    private var view: NSView?
    private var tint = (CGFloat(0.49), CGFloat(0.36), CGFloat(0.99))
    private var study: DuoStudy = .focus
    private var displayLink: CADisplayLink?
    private var stream: SCStream?
    private var startedAt: TimeInterval = 0
    private var generation = 0
    private let duration: TimeInterval = 6.2
    private let renderer = LiveRenderer()

    func play(tint color: NSColor, study: DuoStudy = .focus) {
        self.study = study
        let rgb = color.usingColorSpace(.sRGB) ?? color
        tint = (rgb.redComponent, rgb.greenComponent, rgb.blueComponent)
        guard CGPreflightScreenCaptureAccess() else {
            onStatus?("화면 왜곡 · 화면 기록 스위치가 이 실행 파일에는 아직 안 붙었어요")
            Self.log("preflight denied, prompt skipped")
            return
        }
        generation += 1
        let token = generation
        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.startLive()
                guard token == self.generation else { return }
                self.onStatus?(nil)
            } catch {
                guard token == self.generation else { return }
                self.onStatus?("화면 왜곡 · 화면을 읽지 못했어요")
                Self.log("capture failed: \(error)")
            }
        }
    }

    func openSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    private func startLive() async throws {
        stopTimer()
        await stopStream()
        let notch = NotchGeometry.current()
        guard let screen = NSScreen.screens.first(where: { $0.frame.equalTo(notch.screenFrame) })
                ?? NSScreen.main
                ?? NSScreen.screens.first
        else { return }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let displayID = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
        guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
            throw CaptureError.noDisplay
        }
        renderer.resize(pixels: CGSize(width: display.width, height: display.height), points: screen.frame.size)
        renderer.update(envelope: 0, time: 0, tint: tint, study: study, active: true)

        if window == nil {
            let panel = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            panel.isOpaque = true
            panel.backgroundColor = .black
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.isReleasedWhenClosed = false
            let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.wantsLayer = true
            view.layer = renderer.metalLayer
            panel.contentView = view
            self.view = view
            window = panel
        }
        window?.setFrame(screen.frame, display: false)
        view?.frame = NSRect(origin: .zero, size: screen.frame.size)
        renderer.metalLayer.frame = view?.bounds ?? .zero
        window?.alphaValue = 0
        window?.orderFrontRegardless()

        let ownID = Bundle.main.bundleIdentifier
        let excluded = content.applications.filter { $0.bundleIdentifier == ownID }
        let filter = SCContentFilter(display: display, excludingApplications: excluded, exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = display.width
        configuration.height = display.height
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = false
        configuration.capturesAudio = false
        configuration.queueDepth = 4
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(renderer, type: .screen, sampleHandlerQueue: renderer.queue)
        try await stream.startCapture()
        self.stream = stream

        startedAt = CACurrentMediaTime()
        guard let view else { return }
        let link = view.displayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        step()
    }

    private func step() {
        let t = (CACurrentMediaTime() - startedAt) / duration
        if t >= 1 {
            finish()
            return
        }
        let envelope = Self.level(t)
        window?.alphaValue = envelope
        renderer.update(envelope: envelope, time: t * duration, tint: tint, study: study, active: true)
    }

    private func finish() {
        renderer.update(envelope: 0, time: 0, tint: tint, study: study, active: false)
        stopTimer()
        window?.orderOut(nil)
        Task { await self.stopStream() }
    }

    private func stopStream() async {
        guard let stream else { return }
        self.stream = nil
        try? await stream.stopCapture()
    }

    private func stopTimer() {
        displayLink?.invalidate()
        displayLink = nil
    }

    /// 들어올 때는 약 1.7초. 1.2초 머문 뒤, 초점과 테두리가 약 3.3초에 걸쳐 같이 사라진다.
    private static func level(_ t: TimeInterval) -> Double {
        let clamped = min(1, max(0, t))
        let rise = smootherstep(0, 0.28, clamped)
        let fall = 1 - smootherstep(0.47, 1, clamped)
        return rise * fall
    }

    /// 맥북 패널 모서리. 포인트 단위.
    nonisolated fileprivate static let screenCornerRadius: CGFloat = 32
    nonisolated(unsafe) private static var borderMaskCache: (key: (CGFloat, CGFloat, CGFloat), image: CIImage)?

    nonisolated fileprivate static func frame(
        source: CIImage,
        envelope: Double,
        tint: (CGFloat, CGFloat, CGFloat),
        cornerRadius: CGFloat
    ) -> CIImage {
        focusFrame(source, extent: source.extent, envelope: envelope, tint: tint, cornerRadius: cornerRadius)
    }

    /// 가장자리만 흐리고, 그 흐린 자리에 앱 색을 아주 약하게 섞는다. 가운데는 원본이다.
    /// 경계는 원이 아니라 맥북 화면처럼 모서리가 살짝 둥근 사각형이다.
    nonisolated private static func focusFrame(
        _ source: CIImage,
        extent: CGRect,
        envelope: Double,
        tint: (CGFloat, CGFloat, CGFloat),
        cornerRadius: CGFloat
    ) -> CIImage {
        guard envelope > 0.001 else { return source }
        let small = source.transformed(by: CGAffineTransform(scaleX: 0.22, y: 0.22))
        let blurredSmall = small.clampedToExtent()
            .applyingGaussianBlur(sigma: 5.5 * envelope)
            .cropped(to: small.extent)
        let blurred = blurredSmall
            .transformed(by: CGAffineTransform(scaleX: 1 / 0.22, y: 1 / 0.22))
            .cropped(to: extent)
        let wash = CIImage(color: CIColor(red: tint.0, green: tint.1, blue: tint.2, alpha: 1))
            .cropped(to: extent)
        let tintMask = CIImage(color: CIColor(red: 0.30 * envelope, green: 0.30 * envelope, blue: 0.30 * envelope, alpha: 1))
            .cropped(to: extent)
        let tinted = wash.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: blurred,
            kCIInputMaskImageKey: tintMask
        ])
        let falloff = roundedBorderMask(extent: extent, cornerRadius: cornerRadius).applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: envelope, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: envelope, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: envelope, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
        ])
        return tinted.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: source,
            kCIInputMaskImageKey: falloff
        ])
    }

    /// 화면 가장자리에서 안쪽으로 옅어지는 마스크. 모서리 반경은 맥북 패널에 맞춘다.
    nonisolated private static func roundedBorderMask(extent: CGRect, cornerRadius: CGFloat) -> CIImage {
        let key = (extent.width, extent.height, cornerRadius)
        if let cached = borderMaskCache, cached.key == key {
            return cached.image
        }
        let width = 480
        let height = max(80, Int((extent.height / max(extent.width, 1)) * CGFloat(width)))
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let band = min(extent.width, extent.height) * 0.14
        let radius = min(cornerRadius, min(extent.width, extent.height) / 2)
        for y in 0..<height {
            for x in 0..<width {
                let px = (CGFloat(x) + 0.5) / CGFloat(width) * extent.width - extent.midX
                let py = (CGFloat(y) + 0.5) / CGFloat(height) * extent.height - extent.midY
                let distance = roundedRectSDF(x: px, y: py, halfWidth: extent.width / 2, halfHeight: extent.height / 2, radius: radius)
                let inside = max(0, -distance)
                let clear = smoothstep(0, band, inside)
                let strength = UInt8(min(255, max(0, (1 - clear) * 255)))
                let index = (y * width + x) * 4
                bytes[index] = strength
                bytes[index + 1] = strength
                bytes[index + 2] = strength
                bytes[index + 3] = 255
            }
        }
        let image = CIImage(
            bitmapData: Data(bytes),
            bytesPerRow: width * 4,
            size: CGSize(width: width, height: height),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        ).transformed(by: CGAffineTransform(scaleX: extent.width / CGFloat(width), y: extent.height / CGFloat(height)))
        borderMaskCache = (key, image)
        return image
    }

    nonisolated private static func roundedRectSDF(
        x: CGFloat,
        y: CGFloat,
        halfWidth: CGFloat,
        halfHeight: CGFloat,
        radius: CGFloat
    ) -> CGFloat {
        let corner = min(radius, min(halfWidth, halfHeight))
        let qx = abs(x) - (halfWidth - corner)
        let qy = abs(y) - (halfHeight - corner)
        let outsideX = max(qx, 0)
        let outsideY = max(qy, 0)
        let outside = (outsideX * outsideX + outsideY * outsideY).squareRoot()
        let inside = min(max(qx, qy), 0)
        return outside + inside - corner
    }

    nonisolated private static func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ value: CGFloat) -> CGFloat {
        guard edge1 > edge0 else { return value < edge0 ? 0 : 1 }
        let t = min(1, max(0, (value - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }

    nonisolated private static func refract(
        _ source: CIImage,
        extent: CGRect,
        time: TimeInterval,
        envelope: Double,
        tint: (CGFloat, CGFloat, CGFloat),
        kind: DuoStudy
    ) -> CIImage {
        let field = fieldImages(extent: extent, time: time, envelope: envelope, study: kind)
        let warped = displace(source, map: field.displacement, scale: field.scale)
        let colored = warped.applyingFilter("CIColorMonochrome", parameters: [
            "inputColor": CIColor(red: tint.0, green: tint.1, blue: tint.2),
            "inputIntensity": 0.7
        ])
        return colored.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: warped,
            kCIInputMaskImageKey: field.mask
        ])
    }

    nonisolated private static func mixChannels(green: CIImage, red: CIImage, blue: CIImage) -> CIImage {
        func isolate(_ image: CIImage, r: CGFloat, g: CGFloat, b: CGFloat) -> CIImage {
            image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: r, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: g, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: b, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
            ])
        }
        let merged = isolate(red, r: 1, g: 0, b: 0)
            .applyingFilter("CIAdditionCompositing", parameters: [
                kCIInputBackgroundImageKey: isolate(green, r: 0, g: 1, b: 0)
            ])
        return isolate(blue, r: 0, g: 0, b: 1)
            .applyingFilter("CIAdditionCompositing", parameters: [
                kCIInputBackgroundImageKey: merged
            ])
    }

    nonisolated private static func displace(_ image: CIImage, map: CIImage, scale: Double) -> CIImage {
        guard scale > 0.4 else { return image }
        return image.applyingFilter("CIDisplacementDistortion", parameters: [
            "inputDisplacementImage": map,
            kCIInputScaleKey: scale
        ])
    }

    /// 빨강·초록은 픽셀을 미는 방향(0.5가 제자리). 마스크는 가장자리와 고리에서만 앱 색을 섞는다.
    nonisolated private static func fieldImages(
        extent: CGRect,
        time: TimeInterval,
        envelope: Double,
        study: DuoStudy
    ) -> (displacement: CIImage, mask: CIImage, fringe: CIImage, scale: Double, chroma: Double) {
        let width = 420
        let height = max(80, Int((extent.height / extent.width) * CGFloat(width)))
        var displacement = [UInt8](repeating: 128, count: width * height * 4)
        var mask = [UInt8](repeating: 0, count: width * height * 4)
        var fringe = [UInt8](repeating: 0, count: width * height * 4)
        let aspect = extent.width / extent.height
        let motion = Self.motion(for: study)
        for y in 0..<height {
            for x in 0..<width {
                let u = (Double(x) + 0.5) / Double(width)
                let v = (Double(y) + 0.5) / Double(height)
                let sample = motion.sample(u, v, aspect, time, envelope)
                let index = (y * width + x) * 4
                displacement[index] = byte(0.5 + sample.dx)
                displacement[index + 1] = byte(0.5 + sample.dy)
                displacement[index + 2] = 128
                displacement[index + 3] = 255
                let wash = UInt8(min(1, sample.tint) * 255)
                mask[index] = wash
                mask[index + 1] = wash
                mask[index + 2] = wash
                mask[index + 3] = 255
                let split = UInt8(min(1, sample.fringe) * 255)
                fringe[index] = split
                fringe[index + 1] = split
                fringe[index + 2] = split
                fringe[index + 3] = 255
            }
        }
        let row = width * 4
        let map = CIImage(
            bitmapData: Data(displacement),
            bytesPerRow: row,
            size: CGSize(width: width, height: height),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        let wash = CIImage(
            bitmapData: Data(mask),
            bytesPerRow: row,
            size: CGSize(width: width, height: height),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        let split = CIImage(
            bitmapData: Data(fringe),
            bytesPerRow: row,
            size: CGSize(width: width, height: height),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        let fitted = CGAffineTransform(scaleX: extent.width / CGFloat(width), y: extent.height / CGFloat(height))
        return (map.transformed(by: fitted), wash.transformed(by: fitted), split.transformed(by: fitted), motion.scale, motion.chroma)
    }

    private struct FieldMotion {
        var scale: Double
        var chroma: Double
        var sample: (Double, Double, Double, TimeInterval, Double) -> (dx: Double, dy: Double, tint: Double, fringe: Double)
    }

    nonisolated private static func motion(for study: DuoStudy) -> FieldMotion {
        switch study {
        case .lens, .pinch, .focus:
            return FieldMotion(scale: 1, chroma: 1) { _, _, _, _, _ in (0, 0, 0, 0) }
        case .prism:
            return FieldMotion(scale: 1, chroma: 1) { u, v, _, _, envelope in
                let corner = smoothstep(0.55, 0.0, hypot(min(u, 1 - u), min(v, 1 - v)))
                return (0, 0, 0, corner * envelope)
            }
        }
    }

    nonisolated private static func inward(_ u: Double, _ v: Double) -> (Double, Double) {
        let k = 22.0
        var gx = exp(-u * k) - exp(-(1 - u) * k)
        var gy = exp(-v * k) - exp(-(1 - v) * k)
        let length = max(hypot(gx, gy), 0.0001)
        gx /= length
        gy /= length
        return (gx, gy)
    }

    nonisolated private static func smoothstep(_ edge0: Double, _ edge1: Double, _ value: Double) -> Double {
        let t = min(1, max(0, (value - edge0) / (edge1 - edge0)))
        return t * t * (3 - 2 * t)
    }

    /// 시작과 끝의 가속도까지 0이라 더 둥글게 붙고 떨어진다.
    nonisolated private static func smootherstep(_ edge0: Double, _ edge1: Double, _ value: Double) -> Double {
        let t = min(1, max(0, (value - edge0) / (edge1 - edge0)))
        return t * t * t * (t * (t * 6 - 15) + 10)
    }

    nonisolated private static func byte(_ value: Double) -> UInt8 {
        UInt8(min(255, max(0, Int((value * 255).rounded()))))
    }

    private enum CaptureError: Error {
        case noDisplay
    }

    private static func log(_ message: String) {
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Mochinotch")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let line = "\(Date()) \(message)\n"
        let url = folder.appendingPathComponent("duo.log")
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path), let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}

/// 화면 스트림의 각 프레임을 그 자리에서 굴절시킨다. 콜백이 끝나는 버퍼는 붙잡지 않는다.
private final class LiveRenderer: NSObject, SCStreamOutput {
    let metalLayer = CAMetalLayer()
    let queue = DispatchQueue(label: "dev.sleeeppy.mochinotch.duo.stream", qos: .userInteractive)
    private let context: CIContext?
    private let commandQueue: MTLCommandQueue?
    private let state = OSAllocatedUnfairLock(initialState: Visuals())

    override init() {
        let device = MTLCreateSystemDefaultDevice()
        commandQueue = device?.makeCommandQueue()
        context = device.map { CIContext(mtlDevice: $0, options: [.cacheIntermediates: false]) }
        super.init()
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = false
        metalLayer.isOpaque = true
    }

    func resize(pixels: CGSize, points: CGSize) {
        metalLayer.drawableSize = pixels
        let scale = pixels.width / max(points.width, 1)
        metalLayer.contentsScale = scale
        state.withLock { $0.cornerRadius = DuoPulse.screenCornerRadius * scale }
    }

    func update(envelope: Double, time: TimeInterval, tint: (CGFloat, CGFloat, CGFloat), study: DuoStudy, active: Bool) {
        state.withLock {
            $0.envelope = envelope
            $0.time = time
            $0.tint = tint
            $0.study = study
            $0.active = active
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let pixelBuffer = sampleBuffer.imageBuffer else { return }
        let visuals = state.withLock { $0 }
        guard visuals.active, let context, let commandQueue,
              let drawable = metalLayer.nextDrawable(),
              let buffer = commandQueue.makeCommandBuffer()
        else { return }
        let output = DuoPulse.frame(
            source: CIImage(cvPixelBuffer: pixelBuffer),
            envelope: visuals.envelope,
            tint: visuals.tint,
            cornerRadius: visuals.cornerRadius
        )
        context.render(
            output,
            to: drawable.texture,
            commandBuffer: buffer,
            bounds: CGRect(origin: .zero, size: metalLayer.drawableSize),
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        buffer.present(drawable)
        buffer.commit()
    }
}

private struct Visuals: Sendable {
    var active = false
    var envelope = 0.0
    var time = 0.0
    var tint = (CGFloat(0.5), CGFloat(0.5), CGFloat(0.5))
    var study = DuoStudy.focus
    var cornerRadius: CGFloat = 32
}
