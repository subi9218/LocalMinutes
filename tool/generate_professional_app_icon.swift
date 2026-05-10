import AppKit

struct Palette {
  static let deepGreen = NSColor(calibratedRed: 0.043, green: 0.157, blue: 0.145, alpha: 1)
  static let green = NSColor(calibratedRed: 0.075, green: 0.322, blue: 0.275, alpha: 1)
  static let lightGreen = NSColor(calibratedRed: 0.157, green: 0.463, blue: 0.392, alpha: 1)
  static let paper = NSColor(calibratedRed: 0.965, green: 0.947, blue: 0.875, alpha: 1)
  static let paperShadow = NSColor(calibratedRed: 0.092, green: 0.126, blue: 0.118, alpha: 0.30)
  static let ink = NSColor(calibratedRed: 0.090, green: 0.113, blue: 0.106, alpha: 1)
  static let mutedInk = NSColor(calibratedRed: 0.243, green: 0.317, blue: 0.294, alpha: 1)
  static let gold = NSColor(calibratedRed: 0.846, green: 0.602, blue: 0.212, alpha: 1)
  static let goldLight = NSColor(calibratedRed: 0.982, green: 0.797, blue: 0.403, alpha: 1)
  static let cream = NSColor(calibratedRed: 1.000, green: 0.957, blue: 0.770, alpha: 1)
}

func roundedRect(_ rect: CGRect, _ radius: CGFloat) -> NSBezierPath {
  NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func strokeLine(
  from: CGPoint,
  to: CGPoint,
  color: NSColor,
  width: CGFloat,
  cap: NSBezierPath.LineCapStyle = .round
) {
  let path = NSBezierPath()
  path.move(to: from)
  path.line(to: to)
  path.lineWidth = width
  path.lineCapStyle = cap
  color.setStroke()
  path.stroke()
}

func fillPath(_ points: [CGPoint], color: NSColor) {
  guard let first = points.first else { return }
  let path = NSBezierPath()
  path.move(to: first)
  for point in points.dropFirst() {
    path.line(to: point)
  }
  path.close()
  color.setFill()
  path.fill()
}

func drawIcon(size: CGFloat) -> NSImage {
  let image = NSImage(size: CGSize(width: size, height: size))
  image.lockFocus()

  let ctx = NSGraphicsContext.current!.cgContext
  ctx.saveGState()
  ctx.scaleBy(x: size / 1024.0, y: size / 1024.0)

  let bounds = CGRect(x: 0, y: 0, width: 1024, height: 1024)
  ctx.clear(bounds)

  let mask = roundedRect(CGRect(x: 24, y: 24, width: 976, height: 976), 224)
  mask.addClip()

  let bgGradient = NSGradient(colors: [
    NSColor(calibratedRed: 0.039, green: 0.145, blue: 0.137, alpha: 1),
    Palette.green,
    Palette.deepGreen,
  ])!
  bgGradient.draw(in: bounds, angle: 135)

  let glow = NSBezierPath(ovalIn: CGRect(x: 92, y: 650, width: 520, height: 360))
  NSColor(calibratedRed: 0.440, green: 0.740, blue: 0.650, alpha: 0.16).setFill()
  glow.fill()

  let lowerGlow = NSBezierPath(ovalIn: CGRect(x: 470, y: 42, width: 390, height: 330))
  NSColor(calibratedRed: 0.960, green: 0.715, blue: 0.250, alpha: 0.10).setFill()
  lowerGlow.fill()

  let tileShadow = roundedRect(CGRect(x: 192, y: 162, width: 640, height: 700), 96)
  Palette.paperShadow.setFill()
  tileShadow.fill()

  let document = roundedRect(CGRect(x: 172, y: 188, width: 640, height: 700), 86)
  Palette.paper.setFill()
  document.fill()

  NSColor(calibratedWhite: 1, alpha: 0.42).setStroke()
  document.lineWidth = 8
  document.stroke()

  let fold = NSBezierPath()
  fold.move(to: CGPoint(x: 654, y: 888))
  fold.line(to: CGPoint(x: 812, y: 730))
  fold.line(to: CGPoint(x: 654, y: 730))
  fold.close()
  NSColor(calibratedRed: 0.890, green: 0.860, blue: 0.745, alpha: 1).setFill()
  fold.fill()

  strokeLine(from: CGPoint(x: 654, y: 730), to: CGPoint(x: 812, y: 730), color: NSColor(calibratedWhite: 1, alpha: 0.42), width: 6)

  let waveColor = Palette.lightGreen
  let waveWidth: CGFloat = 26
  let wave = NSBezierPath()
  wave.move(to: CGPoint(x: 284, y: 664))
  wave.curve(to: CGPoint(x: 438, y: 664), controlPoint1: CGPoint(x: 326, y: 736), controlPoint2: CGPoint(x: 396, y: 592))
  wave.curve(to: CGPoint(x: 592, y: 664), controlPoint1: CGPoint(x: 480, y: 736), controlPoint2: CGPoint(x: 550, y: 592))
  wave.curve(to: CGPoint(x: 692, y: 664), controlPoint1: CGPoint(x: 620, y: 712), controlPoint2: CGPoint(x: 665, y: 616))
  wave.lineWidth = waveWidth
  wave.lineCapStyle = .round
  waveColor.setStroke()
  wave.stroke()

  strokeLine(from: CGPoint(x: 286, y: 544), to: CGPoint(x: 658, y: 544), color: Palette.ink, width: 34)
  strokeLine(from: CGPoint(x: 286, y: 466), to: CGPoint(x: 594, y: 466), color: Palette.mutedInk, width: 26)
  strokeLine(from: CGPoint(x: 286, y: 392), to: CGPoint(x: 512, y: 392), color: Palette.mutedInk, width: 26)

  for (x, y) in [(650.0, 512.0), (718.0, 512.0), (650.0, 444.0)] {
    let dot = NSBezierPath(ovalIn: CGRect(x: x, y: y, width: 34, height: 34))
    Palette.gold.setFill()
    dot.fill()
  }

  ctx.saveGState()
  ctx.translateBy(x: 724, y: 260)
  ctx.rotate(by: -28 * .pi / 180)

  let penShadow = roundedRect(CGRect(x: -30, y: -18, width: 92, height: 430), 42)
  NSColor(calibratedWhite: 0, alpha: 0.22).setFill()
  penShadow.fill()

  let barrel = roundedRect(CGRect(x: -48, y: 34, width: 96, height: 376), 44)
  NSColor(calibratedRed: 0.095, green: 0.219, blue: 0.190, alpha: 1).setFill()
  barrel.fill()
  NSColor(calibratedWhite: 1, alpha: 0.20).setStroke()
  barrel.lineWidth = 6
  barrel.stroke()

  let capBand = roundedRect(CGRect(x: -48, y: 292, width: 96, height: 52), 22)
  Palette.gold.setFill()
  capBand.fill()

  let nibBase = roundedRect(CGRect(x: -45, y: -4, width: 90, height: 82), 24)
  Palette.goldLight.setFill()
  nibBase.fill()

  fillPath([
    CGPoint(x: -45, y: 44),
    CGPoint(x: 45, y: 44),
    CGPoint(x: 0, y: -88),
  ], color: Palette.goldLight)

  let nibHole = NSBezierPath(ovalIn: CGRect(x: -12, y: -20, width: 24, height: 24))
  Palette.ink.setFill()
  nibHole.fill()
  strokeLine(from: CGPoint(x: 0, y: -4), to: CGPoint(x: 0, y: -78), color: Palette.ink, width: 8)

  strokeLine(from: CGPoint(x: -26, y: 382), to: CGPoint(x: 26, y: 382), color: Palette.cream, width: 14)

  ctx.restoreGState()

  let rim = roundedRect(CGRect(x: 24, y: 24, width: 976, height: 976), 224)
  NSColor(calibratedWhite: 1, alpha: 0.16).setStroke()
  rim.lineWidth = 8
  rim.stroke()

  ctx.restoreGState()
  image.unlockFocus()
  return image
}

func writePNG(_ image: NSImage, pixelSize: Int, to url: URL) throws {
  guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: pixelSize,
    pixelsHigh: pixelSize,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
  ) else {
    throw NSError(domain: "IconWriter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"])
  }
  bitmap.size = CGSize(width: pixelSize, height: pixelSize)

  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
  image.draw(in: CGRect(x: 0, y: 0, width: pixelSize, height: pixelSize))
  NSGraphicsContext.restoreGraphicsState()

  guard let png = bitmap.representation(using: .png, properties: [:]) else {
    throw NSError(domain: "IconWriter", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"])
  }
  try png.write(to: url)
}

let args = CommandLine.arguments
guard args.count == 2 else {
  FileHandle.standardError.write("Usage: swift tool/generate_professional_app_icon.swift <AppIcon.appiconset>\n".data(using: .utf8)!)
  exit(64)
}

let outputDir = URL(fileURLWithPath: args[1], isDirectory: true)
let sizes: [Int] = [16, 32, 64, 128, 256, 512, 1024]

for size in sizes {
  let image = drawIcon(size: CGFloat(size))
  let url = outputDir.appendingPathComponent("app_icon_\(size).png")
  try writePNG(image, pixelSize: size, to: url)
  print("Wrote \(url.path)")
}
