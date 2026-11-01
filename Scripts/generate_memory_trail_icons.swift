import AppKit
import Foundation

let fileManager = FileManager.default

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: generate_memory_trail_icons.swift <repo-root>\n", stderr)
    exit(2)
}

let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let masterURL = root.appendingPathComponent("Branding/MemoryTrailIconMaster.png")
let appIconDirectory = root.appendingPathComponent(
    "MemoryTrail/Resources/Assets.xcassets/AppIcon.appiconset",
    isDirectory: true
)
let onboardingDirectory = root.appendingPathComponent(
    "MemoryTrail/Resources/Assets.xcassets/OnboardingIcon.imageset",
    isDirectory: true
)

try fileManager.createDirectory(at: appIconDirectory, withIntermediateDirectories: true)
try fileManager.createDirectory(at: onboardingDirectory, withIntermediateDirectories: true)

guard let master = NSImage(contentsOf: masterURL) else {
    fputs("Unable to load Memory Trail master icon at \(masterURL.path)\n", stderr)
    exit(3)
}

func renderIcon(size: Int) -> NSImage {
    let dimensions = NSSize(width: size, height: size)
    let image = NSImage(size: dimensions)
    image.lockFocus()

    NSGraphicsContext.current?.imageInterpolation = .high
    NSColor.clear.setFill()
    NSRect(origin: .zero, size: dimensions).fill()

    master.draw(
        in: NSRect(origin: .zero, size: dimensions),
        from: NSRect(origin: .zero, size: master.size),
        operation: .sourceOver,
        fraction: 1.0,
        respectFlipped: true,
        hints: [.interpolation: NSImageInterpolation.high]
    )

    image.unlockFocus()
    return image
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard let tiff = image.tiffRepresentation,
          let representation = NSBitmapImageRep(data: tiff),
          let data = representation.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "MemoryTrailIcon", code: 1)
    }

    try data.write(to: url, options: .atomic)
}

let appIconTargets: [(String, Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (filename, size) in appIconTargets {
    try writePNG(
        renderIcon(size: size),
        to: appIconDirectory.appendingPathComponent(filename)
    )
}

try writePNG(
    renderIcon(size: 512),
    to: onboardingDirectory.appendingPathComponent("OnboardingIcon.png")
)
try writePNG(
    renderIcon(size: 1024),
    to: onboardingDirectory.appendingPathComponent("OnboardingIcon@2x.png")
)

print("Memory Trail icons generated from Branding/MemoryTrailIconMaster.png")
