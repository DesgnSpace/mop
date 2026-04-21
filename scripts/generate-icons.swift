import AppKit

let sizes = [16, 32, 128, 256, 512]
let outputDir = "/Users/malico/super-voice-assistant/Sources/Assets.xcassets/AppIcon.appiconset"
let logosDir = "/Users/malico/super-voice-assistant/logos"

let bgColor = NSColor(calibratedRed: 0.05, green: 0.05, blue: 0.05, alpha: 1.0)
let waveColor = NSColor.white

func drawBackground(in rect: NSRect) {
    let radius = max(rect.width * 0.22, 2)
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    bgColor.setFill()
    path.fill()
}

func drawWaveform(in rect: NSRect) {
    let scale = rect.width
    let barWidth = scale * 0.068
    let gap = scale * 0.044
    let totalWidth = barWidth * 5 + gap * 4
    let startX = rect.origin.x + (scale - totalWidth) / 2
    let baseY = rect.origin.y

    let heights = [
        scale * 0.27,
        scale * 0.43,
        scale * 0.625,
        scale * 0.43,
        scale * 0.27
    ]

    for i in 0..<5 {
        let x = startX + CGFloat(i) * (barWidth + gap)
        let h = heights[i]
        let y = baseY + (scale - h) / 2
        let barRect = NSRect(x: x, y: y, width: barWidth, height: h)
        let path = NSBezierPath(roundedRect: barRect, xRadius: barWidth / 2, yRadius: barWidth / 2)
        waveColor.setFill()
        path.fill()
    }
}

func generateIcon(size: Int, scale: Int = 1) -> Data {
    let pixels = CGFloat(size * scale)
    let image = NSImage(size: NSSize(width: pixels, height: pixels))
    image.lockFocus()

    let rect = NSRect(origin: .zero, size: NSSize(width: pixels, height: pixels))
    drawBackground(in: rect)
    drawWaveform(in: rect)

    image.unlockFocus()

    let tiffData = image.tiffRepresentation!
    let bitmap = NSBitmapImageRep(data: tiffData)!
    return bitmap.representation(using: .png, properties: [:])!
}

// Generate AppIcon set sizes
for size in sizes {
    let filename = "icon_\(size)x\(size).png"
    let path = "\(outputDir)/\(filename)"
    let data = generateIcon(size: size)
    try? data.write(to: URL(fileURLWithPath: path))
    print("Created \(filename)")

    if size <= 64 {
        let filename2x = "icon_\(size)x\(size)@2x.png"
        let path2x = "\(outputDir)/\(filename2x)"
        let data2x = generateIcon(size: size, scale: 2)
        try? data2x.write(to: URL(fileURLWithPath: path2x))
        print("Created \(filename2x)")
    }
}

// 512@2x (1024px source)
let data1024 = generateIcon(size: 512, scale: 2)
try? data1024.write(to: URL(fileURLWithPath: "\(outputDir)/icon_512x512@2x.png"))
print("Created icon_512x512@2x.png")

// AppIcon.icns (PNG data, same as before for compatibility)
try? data1024.write(to: URL(fileURLWithPath: "/Users/malico/super-voice-assistant/Sources/AppIcon.icns"))
print("Created Sources/AppIcon.icns")

// logo.png — main marketing logo
let logoData = generateIcon(size: 1024)
try? logoData.write(to: URL(fileURLWithPath: "\(logosDir)/logo.png"))
print("Created logos/logo.png")

// logo_no_bg.png — transparent background, white waveform
let logoNoBg = NSImage(size: NSSize(width: 1024, height: 1024))
logoNoBg.lockFocus()
drawWaveform(in: NSRect(origin: .zero, size: NSSize(width: 1024, height: 1024)))
logoNoBg.unlockFocus()
let logoNoBgTiff = logoNoBg.tiffRepresentation!
let logoNoBgBitmap = NSBitmapImageRep(data: logoNoBgTiff)!
let logoNoBgPng = logoNoBgBitmap.representation(using: .png, properties: [:])!
try? logoNoBgPng.write(to: URL(fileURLWithPath: "\(logosDir)/logo_no_bg.png"))
print("Created logos/logo_no_bg.png")

// logo_edited.png — same as main logo
try? logoData.write(to: URL(fileURLWithPath: "\(logosDir)/logo_edited.png"))
print("Created logos/logo_edited.png")

print("Done!")
