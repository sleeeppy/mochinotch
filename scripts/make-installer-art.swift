#!/usr/bin/env swift
// 설치 화면에 쓰는 그림을 다시 그린다. 문구나 색을 바꿀 때만 돌리면 된다.
//
//   swift scripts/make-installer-art.swift
//
// docs/images/dmg-background.png, dmg-background@2x.png  DMG 창 배경 (600x360)
// windows/installer/welcome.bmp                           Windows 설치 첫 화면과 끝 화면 왼쪽 (164x314)
import AppKit

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let lavenderTop = NSColor(srgbRed: 0.91, green: 0.83, blue: 0.95, alpha: 1)
let lavenderBottom = NSColor(srgbRed: 0.78, green: 0.75, blue: 0.96, alpha: 1)
let ink = NSColor(srgbRed: 0.10, green: 0.09, blue: 0.20, alpha: 1)
let soft = NSColor(srgbRed: 0.33, green: 0.30, blue: 0.48, alpha: 1)

/// 왼쪽 위 원점 좌표로 그린다. Finder 아이콘 위치와 같은 좌표계다.
func render(width: Int, height: Int, scale: Int, draw: (CGContext) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width * scale, pixelsHigh: height * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let cg = context.cgContext
    cg.translateBy(x: 0, y: CGFloat(height))
    cg.scaleBy(x: 1, y: -1)
    draw(cg)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func gradient(_ cg: CGContext, width: CGFloat, height: CGFloat) {
    let colors = [lavenderTop.cgColor, lavenderBottom.cgColor] as CFArray
    let fill = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1])!
    cg.drawLinearGradient(fill, start: .zero, end: CGPoint(x: width, y: height), options: [])
}

/// 뒤집힌 좌표계에서도 글자가 바로 서도록 그 자리만 다시 뒤집는다.
func text(_ cg: CGContext, _ string: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, centerX: CGFloat, top: CGFloat) {
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
    ]
    let line = NSAttributedString(string: string, attributes: attributes)
    let bounds = line.size()
    cg.saveGState()
    cg.translateBy(x: 0, y: top + bounds.height)
    cg.scaleBy(x: 1, y: -1)
    line.draw(at: NSPoint(x: centerX - bounds.width / 2, y: 0))
    cg.restoreGState()
}

/// make-dmg.sh의 창 크기(600x360)와 아이콘 위치(160, 178), (440, 178)에 맞춘다.
func dmgBackground(scale: Int) -> NSBitmapImageRep {
    render(width: 600, height: 360, scale: scale) { cg in
        gradient(cg, width: 600, height: 360)

        text(cg, "Mochinotch를 Applications로 끌어다 놓으세요", size: 18, weight: .semibold, color: ink, centerX: 300, top: 34)
        text(cg, "Drag Mochinotch to Applications", size: 12, weight: .regular, color: soft, centerX: 300, top: 62)

        // 두 아이콘 사이 화살표.
        let arrow = CGMutablePath()
        arrow.move(to: CGPoint(x: 248, y: 178))
        arrow.addLine(to: CGPoint(x: 340, y: 178))
        cg.setStrokeColor(ink.withAlphaComponent(0.45).cgColor)
        cg.setLineWidth(4)
        cg.setLineCap(.round)
        cg.setLineDash(phase: 0, lengths: [0.5, 11])
        cg.addPath(arrow)
        cg.strokePath()
        cg.setLineDash(phase: 0, lengths: [])
        let head = CGMutablePath()
        head.move(to: CGPoint(x: 342, y: 167))
        head.addLine(to: CGPoint(x: 354, y: 178))
        head.addLine(to: CGPoint(x: 342, y: 189))
        cg.setLineJoin(.round)
        cg.addPath(head)
        cg.strokePath()

        // 아래 안내는 옅은 띠에 담아 빈 바닥처럼 보이지 않게 한다.
        cg.setFillColor(NSColor.white.withAlphaComponent(0.45).cgColor)
        cg.addPath(CGPath(roundedRect: CGRect(x: 60, y: 282, width: 480, height: 50), cornerWidth: 14, cornerHeight: 14, transform: nil))
        cg.fillPath()
        text(cg, "다운로드 폴더에서 바로 열면 AI 연결이 불가능해요. 꼭 옮긴 뒤 실행하세요.", size: 12, weight: .medium, color: ink.withAlphaComponent(0.8), centerX: 300, top: 289)
        text(cg, "Run it from Applications, not Downloads, so AI agents can connect.", size: 11, weight: .regular, color: soft, centerX: 300, top: 308)
    }
}

func welcomeBitmap() -> NSBitmapImageRep {
    let icon = NSImage(contentsOf: root.appendingPathComponent("Assets/MochinotchIcon.png"))!
    return render(width: 164, height: 314, scale: 1) { cg in
        gradient(cg, width: 164, height: 314)
        cg.saveGState()
        cg.translateBy(x: 0, y: 140)
        cg.scaleBy(x: 1, y: -1)
        icon.draw(in: NSRect(x: 30, y: 0, width: 104, height: 104))
        cg.restoreGState()
        text(cg, "Mochinotch", size: 17, weight: .bold, color: ink, centerX: 82, top: 152)
    }
}

/// NSIS는 알파 없는 24비트 BMP만 제대로 그린다.
func writeBMP(_ rep: NSBitmapImageRep, to url: URL) throws {
    let width = rep.pixelsWide, height = rep.pixelsHigh
    let row = (width * 3 + 3) & ~3
    var data = Data()
    func le32(_ v: Int) { var x = UInt32(v).littleEndian; data.append(Data(bytes: &x, count: 4)) }
    func le16(_ v: Int) { var x = UInt16(v).littleEndian; data.append(Data(bytes: &x, count: 2)) }
    data.append(contentsOf: [0x42, 0x4D]); le32(54 + row * height); le32(0); le32(54)
    le32(40); le32(width); le32(height); le16(1); le16(24); le32(0); le32(row * height); le32(2835); le32(2835); le32(0); le32(0)
    for y in (0..<height).reversed() {
        var line = [UInt8](repeating: 0, count: row)
        for x in 0..<width {
            let color = rep.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
            line[x * 3] = UInt8(round(color.blueComponent * 255))
            line[x * 3 + 1] = UInt8(round(color.greenComponent * 255))
            line[x * 3 + 2] = UInt8(round(color.redComponent * 255))
        }
        data.append(contentsOf: line)
    }
    try data.write(to: url)
}

let images = root.appendingPathComponent("docs/images")
try dmgBackground(scale: 1).representation(using: .png, properties: [:])!.write(to: images.appendingPathComponent("dmg-background.png"))
try dmgBackground(scale: 2).representation(using: .png, properties: [:])!.write(to: images.appendingPathComponent("dmg-background@2x.png"))
let installer = root.appendingPathComponent("windows/installer")
try FileManager.default.createDirectory(at: installer, withIntermediateDirectories: true)
try writeBMP(welcomeBitmap(), to: installer.appendingPathComponent("welcome.bmp"))
print("done")
