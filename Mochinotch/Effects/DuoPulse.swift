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

/// Cursor, Claude, Codex가 끝날 때, 찍힌 화면의 가장자리에 노치에서 흘러나온 빛과 앱 색을 입힌다.
/// 선으로 테두리를 그리지 않는다. 앱 색은 휜 가장자리에만 얇게 섞인다.
@MainActor
final class DuoPulse: NSObject {
    static let shared = DuoPulse()

    var onStatus: ((String?) -> Void)?
    /// 화면 효과와 같이 움직인다. envelope, 0~1 진행, 틴트.
    var onGlow: ((Double, Double, NSColor) -> Void)?

    private var window: NSWindow?
    private var view: NSView?
    private var tint = (CGFloat(0.49), CGFloat(0.36), CGFloat(0.99))
    private var displayLink: CADisplayLink?
    private var stream: SCStream?
    private var startedAt: TimeInterval = 0
    private var requestedAt: TimeInterval = 0
    private var generation = 0
    private var duration: TimeInterval { Self.fallStart + Self.fallLength }
    private let renderer = LiveRenderer()

    /// `rim`이 1보다 크면 가장자리 색이 화면 끝에 바짝 붙는다.
    func play(tint color: NSColor, rim: Double = 1) {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        tint = (rgb.redComponent, rgb.greenComponent, rgb.blueComponent)
        renderer.setRim(rim)
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
        // `SCDisplay` 크기는 포인트다. 그대로 찍으면 레티나에서 반 해상도라, 효과 동안 화면 전체가 뿌예진다.
        let scale = screen.backingScaleFactor
        let pixelWidth = Int((CGFloat(display.width) * scale).rounded())
        let pixelHeight = Int((CGFloat(display.height) * scale).rounded())
        renderer.resize(pixels: CGSize(width: pixelWidth, height: pixelHeight), points: screen.frame.size)
        renderer.placeNotch(notch)
        renderer.update(envelope: 0, time: 0, tint: tint, active: true)

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
        configuration.width = pixelWidth
        configuration.height = pixelHeight
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
        requestedAt = startedAt
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
        // 첫 프레임이 늦게 오면 그동안 흐른 시간만큼 창이 한 번에 켜진다. 첫 프레임이 그려진 때부터 잰다.
        guard renderer.hasPresented else {
            startedAt = CACurrentMediaTime()
            window?.alphaValue = 0
            if startedAt - requestedAt > 1.5 { finish() }
            return
        }
        let seconds = CACurrentMediaTime() - startedAt
        if seconds >= duration {
            finish()
            return
        }
        let envelope = Self.level(seconds)
        let falling = seconds >= Self.fallStart
        // 차오르는 동안은 창을 다 띄우고 세기는 효과 안에서만 올린다. 창 투명도와 세기를 같이 올리면
        // 둘이 곱해져 초반이 비고, 둘이 따로 움직이면 그 사이에서 깜빡인다.
        window?.alphaValue = falling ? envelope : Double(Self.smoothstep(0, 0.12, CGFloat(seconds)))
        let strength = falling ? envelope : Self.swell(seconds)
        renderer.update(envelope: strength, time: seconds, tint: tint, active: true)
        let color = NSColor(srgbRed: tint.0, green: tint.1, blue: tint.2, alpha: 1)
        onGlow?(envelope, seconds / Self.glowSpan, color)
    }

    private func finish() {
        renderer.update(envelope: 0, time: 0, tint: tint, active: false)
        onGlow?(0, 1, NSColor(srgbRed: tint.0, green: tint.1, blue: tint.2, alpha: 1))
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

    /// 테두리 색이 사라지기 시작하는 시각.
    private static let fallStart: TimeInterval = 2.25
    /// 사라지는 데 걸리는 시간.
    private static let fallLength: TimeInterval = 3
    /// 노치 빛줄기의 진행이 0에서 1까지 가는 시간. 효과 길이와 따로 두어 빛줄기 속도는 그대로다.
    private static let glowSpan: TimeInterval = 6.2

    /// 노치 빛줄기가 따르는 세기. 들어올 때는 약 1.7초. 머문 뒤, 테두리 색과 같이 3초에 걸쳐 사라진다.
    private static func level(_ seconds: TimeInterval) -> Double {
        let rise = smootherstep(0, 1.74, CGFloat(seconds))
        let fall = 1 - smootherstep(CGFloat(fallStart), CGFloat(fallStart + fallLength), CGFloat(seconds))
        return Double(rise * fall)
    }

    /// 들어올 때 테두리 색이 차오르는 세기. 쏟아지는 빛 바로 뒤를 따라가도록 처음부터 차오르고,
    /// 빛이 바닥에 닿을 무렵 부드럽게 다 찬다.
    private static func swell(_ seconds: Double) -> Double {
        let linear = min(1, max(0, seconds / 1.45))
        return 1 - pow(1 - linear, 2.2)
    }

    /// 맥북 패널 모서리. 포인트 단위.
    nonisolated fileprivate static let screenCornerRadius: CGFloat = 32
    nonisolated(unsafe) private static var borderMaskCache: (key: (CGFloat, CGFloat, CGFloat), image: CIImage)?

    nonisolated fileprivate static func frame(
        source: CIImage,
        envelope: Double,
        time: Double,
        tint: (CGFloat, CGFloat, CGFloat),
        rim: Double,
        cornerRadius: CGFloat,
        notch: CGRect
    ) -> CIImage {
        focusFrame(
            source,
            extent: source.extent,
            envelope: envelope,
            time: time,
            tint: tint,
            rim: rim,
            cornerRadius: cornerRadius,
            notch: notch
        )
    }

    /// 가장자리에만 앱 색을 아주 약하게 섞는다. 가운데는 원본이다.
    /// 경계는 원이 아니라 맥북 화면처럼 모서리가 살짝 둥근 사각형이다.
    /// 효과는 노치에서 쏟아져 나와 가장자리를 타고 흘러내린다. 흐르는 앞머리는 앱 색 빛으로 밝다.
    nonisolated private static func focusFrame(
        _ source: CIImage,
        extent: CGRect,
        envelope: Double,
        time: Double,
        tint: (CGFloat, CGFloat, CGFloat),
        rim: Double,
        cornerRadius: CGFloat,
        notch: CGRect
    ) -> CIImage {
        let pour = pourState(time)
        guard envelope > 0.001 || pour.front > 0.001 else { return source }
        let wash = CIImage(color: CIColor(red: tint.0, green: tint.1, blue: tint.2, alpha: 1))
            .cropped(to: extent)
        let feathered = featheredBorder(extent: extent, cornerRadius: cornerRadius)
        let border = rim > 1.001
            ? feathered.applyingFilter("CIGammaAdjust", parameters: ["inputPower": rim])
            : feathered
        let origin = notch.width > 2
            ? CGPoint(x: notch.midX, y: notch.minY)
            : CGPoint(x: extent.midX, y: extent.maxY)
        let reach = hypot(max(origin.x - extent.minX, extent.maxX - origin.x), origin.y - extent.minY) * 1.05
        let spill = pourMasks(origin: origin, reach: reach, progress: pour.progress, extent: extent)
        let poured = multiply(border, spill.reveal)
        let front = multiply(border, spill.front)
        // 가장자리는 0.44. 화면 안쪽 끝은 같은 자리에서 더 부드럽게 0이 된다.
        let tintMask = add(scaled(front, by: 0.34 * pour.front), to: scaled(poured, by: 0.44 * envelope))
        let tinted = wash.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: source,
            kCIInputMaskImageKey: multiply(tintMask, scaled(poured, by: envelope))
        ])
        // 밝은 화면에 어두운 앱 색(Cursor 회색)이 섞이면 가장자리가 눌려 보인다. 원래보다 조금만 어두워진다.
        let focused = tinted.applyingFilter("CIMaximumCompositing", parameters: [
            kCIInputBackgroundImageKey: scaled(source, by: 0.9)
        ])
        guard pour.front > 0.001 else { return focused }
        // 앞머리 빛. 어두운 앱 색도 빛으로 보이게 흰색 쪽으로 들어 올린다.
        let lift: CGFloat = 0.45
        let strength = CGFloat(0.4 * pour.front)
        let light = front.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: (tint.0 + (1 - tint.0) * lift) * strength, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: (tint.1 + (1 - tint.1) * lift) * strength, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: (tint.2 + (1 - tint.2) * lift) * strength, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
        ])
        return add(light, to: focused).cropped(to: extent)
    }

    /// 색만 더하고 불투명도는 1로 둔다. `CIAdditionCompositing`은 불투명도까지 더해 2가 되고,
    /// 그 상태로 색이 변환되면 효과가 없는 가운데까지 밝아졌다가 빛이 끝날 때 확 어두워진다.
    nonisolated private static func add(_ image: CIImage, to background: CIImage) -> CIImage {
        image.applyingFilter("CILinearDodgeBlendMode", parameters: [kCIInputBackgroundImageKey: background])
    }

    /// 쏟아지는 데 걸리는 시간. 처음엔 빠르게 튀어나오고 아래로 갈수록 느려진다.
    nonisolated private static let pourDuration = 1.35

    /// 진행(0~1, 감속)과 앞머리 빛의 세기. 빛은 바로 켜지고 다 흘러내리면 꺼진다.
    /// 노치 옆에서 세게 켜지면 앞머리가 금방 지나가 그 자리가 확 어두워진다. 노치에서는 은은하게 나와
    /// 옆으로 흐르며 밝아진다.
    nonisolated private static func pourState(_ time: Double) -> (progress: CGFloat, front: Double) {
        let linear = min(1, max(0, time / pourDuration))
        let eased = 1 - pow(1 - linear, 2)
        let front = Double(smoothstep(0, 0.25, CGFloat(linear))) * pow(1 - linear, 1.3)
        return (CGFloat(eased), front)
    }

    /// 노치에서 퍼지는 원. 안쪽은 이미 흘러내린 자리, 테는 지금 흐르는 앞머리다.
    nonisolated private static func pourMasks(
        origin: CGPoint,
        reach: CGFloat,
        progress: CGFloat,
        extent: CGRect
    ) -> (reveal: CIImage, front: CIImage) {
        let soft = reach * 0.45
        let radius = progress * (reach + soft)
        let center = CIVector(x: origin.x, y: origin.y)
        func disc(inner: CGFloat, outer: CGFloat) -> CIImage {
            CIFilter(name: "CIRadialGradient", parameters: [
                "inputCenter": center,
                "inputRadius0": max(0, inner),
                "inputRadius1": max(1, outer),
                "inputColor0": CIColor.white,
                "inputColor1": CIColor.black
            ])?.outputImage?.cropped(to: extent) ?? CIImage(color: .black).cropped(to: extent)
        }
        // 원 그라데이션은 직선이라, 다 찬 자리에서 차오르는 속도가 꺾여 멈칫해 보인다. 양 끝을 눕힌다.
        let reveal = progress >= 1
            ? CIImage(color: .white).cropped(to: extent)
            : disc(inner: radius - soft, outer: radius).applyingFilter("CIToneCurve", parameters: [
                "inputPoint0": CIVector(x: 0, y: 0),
                "inputPoint1": CIVector(x: 0.25, y: 0.12),
                "inputPoint2": CIVector(x: 0.5, y: 0.5),
                "inputPoint3": CIVector(x: 0.75, y: 0.88),
                "inputPoint4": CIVector(x: 1, y: 1)
            ])
        // 앞은 짧게 밝아지고, 지나간 뒤는 길게 식는다.
        let band = soft * 0.5
        let outer = disc(inner: radius - band, outer: radius)
        let inner = disc(inner: radius - band * 4.5, outer: radius - band)
        let front = inner.applyingFilter("CISubtractBlendMode", parameters: [
            kCIInputBackgroundImageKey: outer
        ])
        return (reveal, front)
    }

    nonisolated private static func multiply(_ image: CIImage, _ mask: CIImage) -> CIImage {
        image.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: mask])
    }

    nonisolated private static func scaled(_ mask: CIImage, by amount: Double) -> CIImage {
        mask.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: amount, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: amount, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: amount, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1)
        ])
    }

    /// 도달 거리는 그대로 두고, 화면 안쪽 끝만 흐린다.
    nonisolated private static func featheredBorder(extent: CGRect, cornerRadius: CGFloat) -> CIImage {
        let sigma = min(extent.width, extent.height) * 0.02
        return roundedBorderMask(extent: extent, cornerRadius: cornerRadius)
            .clampedToExtent()
            .applyingGaussianBlur(sigma: sigma)
            .cropped(to: extent)
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
                let clear = smootherstep(0, band, inside)
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

    /// 양 끝이 더 평평해서, 선명한 화면과 만나는 안쪽 경계가 덜 보인다.
    nonisolated private static func smootherstep(_ edge0: CGFloat, _ edge1: CGFloat, _ value: CGFloat) -> CGFloat {
        guard edge1 > edge0 else { return value < edge0 ? 0 : 1 }
        let t = min(1, max(0, (value - edge0) / (edge1 - edge0)))
        return t * t * t * (t * (t * 6 - 15) + 10)
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

/// 화면 스트림의 각 프레임에 그 자리에서 효과를 입힌다. 콜백이 끝나는 버퍼는 붙잡지 않는다.
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

    func placeNotch(_ info: NotchInfo) {
        let relative: CGRect
        if let notch = info.notchFrame {
            relative = CGRect(
                x: notch.minX - info.screenFrame.minX,
                y: notch.minY - info.screenFrame.minY,
                width: notch.width,
                height: notch.height
            )
        } else {
            relative = .zero
        }
        state.withLock {
            $0.notch = relative
            $0.points = info.screenFrame.size
        }
    }

    func update(envelope: Double, time: TimeInterval, tint: (CGFloat, CGFloat, CGFloat), active: Bool) {
        state.withLock {
            if active, !$0.active { $0.presented = false }
            $0.envelope = envelope
            $0.time = time
            $0.tint = tint
            $0.active = active
        }
    }

    func setRim(_ rim: Double) {
        state.withLock { $0.rim = rim }
    }

    /// 이번 효과에서 한 프레임이라도 그렸는지.
    var hasPresented: Bool {
        state.withLock { $0.presented }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let pixelBuffer = sampleBuffer.imageBuffer else { return }
        let visuals = state.withLock { $0 }
        guard visuals.active, let context, let commandQueue,
              let drawable = metalLayer.nextDrawable(),
              let buffer = commandQueue.makeCommandBuffer()
        else { return }
        let source = CIImage(cvPixelBuffer: pixelBuffer)
        let output = DuoPulse.frame(
            source: source,
            envelope: visuals.envelope,
            time: visuals.time,
            tint: visuals.tint,
            rim: visuals.rim,
            cornerRadius: visuals.cornerRadius,
            notch: Visuals.notchPixels(visuals.notch, points: visuals.points, extent: source.extent)
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
        state.withLock { if $0.active { $0.presented = true } }
    }
}

private struct Visuals: Sendable {
    var active = false
    var presented = false
    var envelope = 0.0
    var time = 0.0
    var tint = (CGFloat(0.5), CGFloat(0.5), CGFloat(0.5))
    var rim = 1.0
    var cornerRadius: CGFloat = 32
    /// 화면 원점 기준 포인트. 노치가 없으면 zero.
    var notch = CGRect.zero
    var points = CGSize.zero

    nonisolated static func notchPixels(_ notch: CGRect, points: CGSize, extent: CGRect) -> CGRect {
        guard notch.width > 2, notch.height > 2, points.width > 1, points.height > 1 else { return .zero }
        let scaleX = extent.width / points.width
        let scaleY = extent.height / points.height
        return CGRect(
            x: extent.minX + notch.minX * scaleX,
            y: extent.minY + notch.minY * scaleY,
            width: notch.width * scaleX,
            height: notch.height * scaleY
        )
    }
}
