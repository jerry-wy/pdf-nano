import AppKit
let output = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let n = CGFloat(pixels)
        let context = NSGraphicsContext.current!.cgContext
        context.clear(CGRect(x: 0, y: 0, width: n, height: n))
        // Reduce the extra transparent border while keeping the artwork centered.
        context.translateBy(x: -n * 0.05, y: -n * 0.05)
        context.scaleBy(x: 1.1, y: 1.1)
        NSColor(calibratedRed: 0.22, green: 0.34, blue: 0.26, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: n * 0.08, y: n * 0.08, width: n * 0.84, height: n * 0.84), xRadius: n * 0.19, yRadius: n * 0.19).fill()
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: n * 0.70, weight: .medium), .foregroundColor: NSColor(calibratedWhite: 0.96, alpha: 1)]
        let text = "n" as NSString
        let bounds = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: (n - bounds.width) / 2 - n * 0.025, y: n * 0.12), withAttributes: attributes)
        NSColor(calibratedRed: 0.77, green: 0.83, blue: 0.65, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: n * 0.71, y: n * 0.24, width: n * 0.065, height: n * 0.065)).fill()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(output)/icon_\(size)x\(size)\(suffix).png"))
        if scale == 1 && [16, 32, 128].contains(size) {
            var rgba = Data()
            for y in 0..<pixels {
                for x in 0..<pixels {
                    let color = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.deviceRGB)!
                    rgba.append(contentsOf: [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent].map {
                        UInt8(max(0, min(255, ($0 * 255).rounded())))
                    })
                }
            }
            try rgba.write(to: URL(fileURLWithPath: "\(output)/icon_\(size)x\(size).rgba"))
        }
    }
}
