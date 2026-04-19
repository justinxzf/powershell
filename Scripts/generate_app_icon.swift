#!/usr/bin/env swift

import AppKit
import Foundation

let fileManager = FileManager.default
let repositoryRoot = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
let resourcesDirectory = repositoryRoot.appendingPathComponent("Sources/PowerShell/Resources", isDirectory: true)
let iconsetDirectory = resourcesDirectory.appendingPathComponent("AppIcon.iconset", isDirectory: true)
let masterImageURL = resourcesDirectory.appendingPathComponent("AppIcon-master.png")
let icnsURL = resourcesDirectory.appendingPathComponent("AppIcon.icns")

let canvasSize = CGSize(width: 1024, height: 1024)
let glowColor = NSColor(calibratedRed: 0.19, green: 0.82, blue: 1.0, alpha: 1.0)
let frameShadowColor = NSColor.black.withAlphaComponent(0.34)
let frameBorderColor = NSColor(calibratedWhite: 0.40, alpha: 0.62)
let frameInnerBorderColor = NSColor(calibratedWhite: 1.0, alpha: 0.06)
let titleBarTopColor = NSColor(calibratedWhite: 0.20, alpha: 1.0)
let titleBarBottomColor = NSColor(calibratedWhite: 0.15, alpha: 1.0)
let terminalTopColor = NSColor(calibratedWhite: 0.10, alpha: 1.0)
let terminalBottomColor = NSColor(calibratedWhite: 0.055, alpha: 1.0)
let glyphColor = NSColor(calibratedWhite: 0.93, alpha: 1.0)
let highlightColor = NSColor.white.withAlphaComponent(0.11)

struct IconSpec {
    let filename: String
    let pixels: CGFloat
}

let iconSpecs: [IconSpec] = [
    .init(filename: "icon_16x16.png", pixels: 16),
    .init(filename: "icon_16x16@2x.png", pixels: 32),
    .init(filename: "icon_32x32.png", pixels: 32),
    .init(filename: "icon_32x32@2x.png", pixels: 64),
    .init(filename: "icon_128x128.png", pixels: 128),
    .init(filename: "icon_128x128@2x.png", pixels: 256),
    .init(filename: "icon_256x256.png", pixels: 256),
    .init(filename: "icon_256x256@2x.png", pixels: 512),
    .init(filename: "icon_512x512.png", pixels: 512),
    .init(filename: "icon_512x512@2x.png", pixels: 1024)
]

func makeDirectory(_ url: URL) throws {
    try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
}

func roundedRectPath(in rect: CGRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func fill(_ rect: CGRect, radius: CGFloat, with colors: [NSColor], angle: CGFloat) {
    let gradient = NSGradient(colors: colors)!
    gradient.draw(in: roundedRectPath(in: rect, radius: radius), angle: angle)
}

func stroke(_ rect: CGRect, radius: CGFloat, color: NSColor, lineWidth: CGFloat) {
    let path = roundedRectPath(in: rect, radius: radius)
    path.lineWidth = lineWidth
    color.setStroke()
    path.stroke()
}

func drawGlow(around rect: CGRect, radius: CGFloat, color: NSColor, blur: CGFloat, alpha: CGFloat) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color.withAlphaComponent(alpha)
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = .zero
    shadow.set()
    color.withAlphaComponent(alpha * 0.22).setFill()
    roundedRectPath(in: rect, radius: radius).fill()
    NSGraphicsContext.restoreGraphicsState()
}

func drawIcon(in rect: CGRect) {
    let frameRect = rect.insetBy(dx: rect.width * 0.105, dy: rect.height * 0.105)
    let frameRadius = frameRect.width * 0.17
    let outerGlowRect = frameRect.insetBy(dx: -rect.width * 0.006, dy: -rect.height * 0.006)
    drawGlow(
        around: outerGlowRect,
        radius: frameRadius * 1.03,
        color: glowColor,
        blur: rect.width * 0.018,
        alpha: 0.13
    )

    NSGraphicsContext.saveGraphicsState()
    let frameShadow = NSShadow()
    frameShadow.shadowColor = frameShadowColor
    frameShadow.shadowBlurRadius = rect.width * 0.036
    frameShadow.shadowOffset = CGSize(width: 0, height: -rect.height * 0.022)
    frameShadow.set()
    fill(frameRect, radius: frameRadius, with: [
        NSColor(calibratedWhite: 0.18, alpha: 1.0),
        NSColor(calibratedWhite: 0.11, alpha: 1.0)
    ], angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    let frameInset = rect.width * 0.013
    let innerFrameRect = frameRect.insetBy(dx: frameInset, dy: frameInset)
    let innerFrameRadius = frameRadius * 0.88
    fill(innerFrameRect, radius: innerFrameRadius, with: [
        NSColor(calibratedWhite: 0.155, alpha: 1.0),
        NSColor(calibratedWhite: 0.095, alpha: 1.0)
    ], angle: -90)

    stroke(innerFrameRect, radius: innerFrameRadius, color: frameBorderColor, lineWidth: rect.width * 0.0048)
    stroke(
        innerFrameRect.insetBy(dx: rect.width * 0.004, dy: rect.width * 0.004),
        radius: innerFrameRadius * 0.96,
        color: frameInnerBorderColor,
        lineWidth: rect.width * 0.0022
    )

    let titleBarHeight = innerFrameRect.height * 0.135
    let titleBarRect = CGRect(
        x: innerFrameRect.minX,
        y: innerFrameRect.maxY - titleBarHeight,
        width: innerFrameRect.width,
        height: titleBarHeight
    )
    fill(titleBarRect, radius: innerFrameRadius * 0.74, with: [titleBarTopColor, titleBarBottomColor], angle: -90)

    let separatorY = titleBarRect.minY + rect.height * 0.0035
    let separatorPath = NSBezierPath()
    separatorPath.move(to: CGPoint(x: titleBarRect.minX + rect.width * 0.028, y: separatorY))
    separatorPath.line(to: CGPoint(x: titleBarRect.maxX - rect.width * 0.028, y: separatorY))
    separatorPath.lineWidth = rect.width * 0.0022
    NSColor.white.withAlphaComponent(0.08).setStroke()
    separatorPath.stroke()

    let toolbarPillRect = CGRect(
        x: titleBarRect.midX - titleBarRect.width * 0.11,
        y: titleBarRect.midY - titleBarRect.height * 0.13,
        width: titleBarRect.width * 0.22,
        height: titleBarRect.height * 0.26
    )
    fill(toolbarPillRect, radius: toolbarPillRect.height / 2, with: [
        NSColor.white.withAlphaComponent(0.10),
        NSColor.white.withAlphaComponent(0.04)
    ], angle: -90)

    let buttonDiameter = rect.width * 0.024
    let buttonSpacing = buttonDiameter * 0.65
    let buttonsX = titleBarRect.minX + rect.width * 0.052
    let buttonsY = titleBarRect.midY - buttonDiameter / 2
    let buttonColors: [NSColor] = [
        NSColor(calibratedRed: 0.97, green: 0.42, blue: 0.38, alpha: 0.88),
        NSColor(calibratedRed: 0.98, green: 0.77, blue: 0.32, alpha: 0.88),
        NSColor(calibratedRed: 0.28, green: 0.83, blue: 0.42, alpha: 0.88)
    ]
    for (index, color) in buttonColors.enumerated() {
        let buttonRect = CGRect(
            x: buttonsX + CGFloat(index) * (buttonDiameter + buttonSpacing),
            y: buttonsY,
            width: buttonDiameter,
            height: buttonDiameter
        )
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
        shadow.shadowBlurRadius = rect.width * 0.008
        shadow.shadowOffset = CGSize(width: 0, height: -rect.height * 0.003)
        shadow.set()
        color.setFill()
        NSBezierPath(ovalIn: buttonRect).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    let terminalInsetX = rect.width * 0.052
    let terminalInsetBottom = rect.height * 0.067
    let terminalInsetTop = titleBarHeight + rect.height * 0.03
    let terminalRect = CGRect(
        x: innerFrameRect.minX + terminalInsetX,
        y: innerFrameRect.minY + terminalInsetBottom,
        width: innerFrameRect.width - terminalInsetX * 2,
        height: innerFrameRect.height - terminalInsetBottom - terminalInsetTop
    )
    let terminalRadius = innerFrameRadius * 0.46
    fill(terminalRect, radius: terminalRadius, with: [terminalTopColor, terminalBottomColor], angle: -90)
    stroke(terminalRect, radius: terminalRadius, color: NSColor.white.withAlphaComponent(0.07), lineWidth: rect.width * 0.0024)

    let terminalGlowLineRect = CGRect(
        x: terminalRect.minX + terminalRect.width * 0.08,
        y: terminalRect.maxY - terminalRect.height * 0.16,
        width: terminalRect.width * 0.24,
        height: rect.height * 0.0046
    )
    fill(terminalGlowLineRect, radius: terminalGlowLineRect.height / 2, with: [
        glowColor.withAlphaComponent(0.46),
        glowColor.withAlphaComponent(0.08)
    ], angle: 0)

    let glossRect = CGRect(
        x: terminalRect.minX + rect.width * 0.018,
        y: terminalRect.midY + terminalRect.height * 0.06,
        width: terminalRect.width * 0.88,
        height: terminalRect.height * 0.3
    )
    let gloss = NSGradient(colors: [
        highlightColor,
        NSColor.white.withAlphaComponent(0.015)
    ])!
    gloss.draw(in: roundedRectPath(in: glossRect, radius: terminalRadius * 0.8), angle: -90)

    let glyphCenter = CGPoint(
        x: terminalRect.minX + terminalRect.width * 0.365,
        y: terminalRect.midY + terminalRect.height * 0.01
    )
    let glyphStroke = rect.width * 0.024
    let chevronWidth = terminalRect.width * 0.13
    let chevronHeight = terminalRect.height * 0.165

    let chevron = NSBezierPath()
    chevron.move(to: CGPoint(x: glyphCenter.x - chevronWidth * 0.62, y: glyphCenter.y + chevronHeight * 0.52))
    chevron.line(to: CGPoint(x: glyphCenter.x - chevronWidth * 0.08, y: glyphCenter.y))
    chevron.line(to: CGPoint(x: glyphCenter.x - chevronWidth * 0.62, y: glyphCenter.y - chevronHeight * 0.52))
    chevron.lineCapStyle = .round
    chevron.lineJoinStyle = .round
    chevron.lineWidth = glyphStroke
    glyphColor.setStroke()
    chevron.stroke()

    let underscoreRect = CGRect(
        x: glyphCenter.x + terminalRect.width * 0.02,
        y: glyphCenter.y - glyphStroke * 0.62,
        width: terminalRect.width * 0.16,
        height: glyphStroke * 0.72
    )
    glyphColor.setFill()
    roundedRectPath(in: underscoreRect, radius: underscoreRect.height / 2).fill()

    let cursorRect = CGRect(
        x: underscoreRect.maxX + terminalRect.width * 0.07,
        y: glyphCenter.y - terminalRect.height * 0.155,
        width: rect.width * 0.022,
        height: terminalRect.height * 0.31
    )
    NSGraphicsContext.saveGraphicsState()
    let cursorShadow = NSShadow()
    cursorShadow.shadowColor = glowColor.withAlphaComponent(0.72)
    cursorShadow.shadowBlurRadius = rect.width * 0.016
    cursorShadow.shadowOffset = .zero
    cursorShadow.set()
    glowColor.setFill()
    roundedRectPath(in: cursorRect, radius: cursorRect.width / 2).fill()
    NSGraphicsContext.restoreGraphicsState()

    let baseShadeRect = CGRect(
        x: terminalRect.minX,
        y: terminalRect.minY,
        width: terminalRect.width,
        height: terminalRect.height * 0.34
    )
    let baseShade = NSGradient(colors: [
        NSColor.black.withAlphaComponent(0.22),
        NSColor.black.withAlphaComponent(0.0)
    ])!
    baseShade.draw(in: roundedRectPath(in: baseShadeRect, radius: terminalRadius * 0.8), angle: 90)
}

func renderImage(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocusFlipped(false)
    NSColor.clear.setFill()
    NSRect(origin: .zero, size: image.size).fill()
    drawIcon(in: CGRect(origin: .zero, size: image.size))
    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiffData = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiffData),
          let pngData = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "AppIconGeneration", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to encode PNG at \(url.path)"])
    }
    try pngData.write(to: url)
}

try makeDirectory(resourcesDirectory)
try makeDirectory(iconsetDirectory)

for item in try fileManager.contentsOfDirectory(at: iconsetDirectory, includingPropertiesForKeys: nil) {
    try fileManager.removeItem(at: item)
}

let masterImage = renderImage(size: canvasSize.width)
try writePNG(masterImage, to: masterImageURL)

for spec in iconSpecs {
    let image = renderImage(size: spec.pixels)
    let outputURL = iconsetDirectory.appendingPathComponent(spec.filename)
    try writePNG(image, to: outputURL)
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetDirectory.path, "-o", icnsURL.path]
try iconutil.run()
iconutil.waitUntilExit()

guard iconutil.terminationStatus == 0 else {
    throw NSError(domain: "AppIconGeneration", code: Int(iconutil.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "iconutil failed with status \(iconutil.terminationStatus)"])
}
