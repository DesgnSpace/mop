import AppKit

let sizes = [16, 32, 128, 256, 512]
let outputDir = "/Users/malico/super-voice-assistant/Sources/Assets.xcassets/AppIcon.appiconset"

for size in sizes {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let rect = NSRect(origin: .zero, size: NSSize(width: size, height: size))
    let radius = max(CGFloat(size) * 0.2, 2)
    let bgPath = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    NSColor(calibratedRed: 0.18, green: 0.21, blue: 0.26, alpha: 1.0).setFill()
    bgPath.fill()

    let fontSize = CGFloat(size) * 0.5
    let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
    let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]

    let text = "M"
    let textSize = text.size(withAttributes: attributes)
    let textRect = NSRect(
        x: (CGFloat(size) - textSize.width) / 2,
        y: (CGFloat(size) - textSize.height) / 2,
        width: textSize.width,
        height: textSize.height
    )
    text.draw(in: textRect, withAttributes: attributes)
    image.unlockFocus()

    let tiffData = image.tiffRepresentation!
    let bitmap = NSBitmapImageRep(data: tiffData)!
    let pngData = bitmap.representation(using: .png, properties: [:])!

    let filename = "icon_\(size)x\(size).png"
    let path = "\(outputDir)/\(filename)"
    try? pngData.write(to: URL(fileURLWithPath: path))
    print("Created \(filename)")

    if size <= 64 {
        let filename2x = "icon_\(size)x\(size)@2x.png"
        let path2x = "\(outputDir)/\(filename2x)"

        let image2x = NSImage(size: NSSize(width: size * 2, height: size * 2))
        image2x.lockFocus()
        let rect2 = NSRect(origin: .zero, size: NSSize(width: size * 2, height: size * 2))
        let bgPath2 = NSBezierPath(roundedRect: rect2, xRadius: CGFloat(size) * 0.4, yRadius: CGFloat(size) * 0.4)
        NSColor(calibratedRed: 0.18, green: 0.21, blue: 0.26, alpha: 1.0).setFill()
        bgPath2.fill()
        let font2 = NSFont.systemFont(ofSize: CGFloat(size), weight: .bold)
        let attrs2: [NSAttributedString.Key: Any] = [.font: font2, .foregroundColor: NSColor.white]
        let t2 = "M"
        let ts2 = t2.size(withAttributes: attrs2)
        let tr2 = NSRect(
            x: (CGFloat(size * 2) - ts2.width) / 2,
            y: (CGFloat(size * 2) - ts2.height) / 2,
            width: ts2.width,
            height: ts2.height
        )
        t2.draw(in: tr2, withAttributes: attrs2)
        image2x.unlockFocus()
        let td2 = image2x.tiffRepresentation!
        let bm2 = NSBitmapImageRep(data: td2)!
        let pd2 = bm2.representation(using: .png, properties: [:])!
        try? pd2.write(to: URL(fileURLWithPath: path2x))
        print("Created \(filename2x)")
    }
}

let src1024 = NSImage(size: NSSize(width: 1024, height: 1024))
src1024.lockFocus()
let r1024 = NSRect(origin: .zero, size: NSSize(width: 1024, height: 1024))
let bp1024 = NSBezierPath(roundedRect: r1024, xRadius: 204.8, yRadius: 204.8)
NSColor(calibratedRed: 0.18, green: 0.21, blue: 0.26, alpha: 1.0).setFill()
bp1024.fill()
let f1024 = NSFont.systemFont(ofSize: 512, weight: .bold)
let a1024: [NSAttributedString.Key: Any] = [.font: f1024, .foregroundColor: NSColor.white]
let t1024 = "M"
let s1024 = t1024.size(withAttributes: a1024)
let rect1024 = NSRect(x: (1024 - s1024.width) / 2, y: (1024 - s1024.height) / 2, width: s1024.width, height: s1024.height)
t1024.draw(in: rect1024, withAttributes: a1024)
src1024.unlockFocus()
let td1024 = src1024.tiffRepresentation!
let bm1024 = NSBitmapImageRep(data: td1024)!
let pd1024 = bm1024.representation(using: .png, properties: [:])!
try? pd1024.write(to: URL(fileURLWithPath: "\(outputDir)/icon_512x512@2x.png"))
print("Created icon_512x512@2x.png")

print("Done!")