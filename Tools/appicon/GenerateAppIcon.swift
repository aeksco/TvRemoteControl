// Renders AppIcon.appiconset from a SwiftUI drawing so the icon can be regenerated
// instead of round-tripping through a design tool. Run via `make icon`.
//
//   swift Tools/appicon/GenerateAppIcon.swift TvRemoteControl/Assets.xcassets/AppIcon.appiconset
//
// The remote follows the same geometry as UI/RemoteFigureView (190 × 560 canvas).

import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}

/// The silver clickpad remote, drawn on RemoteFigureView's 190 × 560 canvas.
private struct RemoteFigure: View {
    private static let shell = LinearGradient(
        colors: [Color(hex: 0xF0F0F3), Color(hex: 0xC6C6CC), Color(hex: 0x94949B)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    private static let clickpad = LinearGradient(
        colors: [Color(hex: 0x33343C), Color(hex: 0x1B1C22)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    private static let key = LinearGradient(
        colors: [Color(hex: 0xF4F4F7), Color(hex: 0xCACAD1)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    private static let accent = Color(hex: 0x6E9BFF)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 52, style: .continuous)
                .fill(Self.shell)
                .overlay(
                    RoundedRectangle(cornerRadius: 52, style: .continuous)
                        .stroke(Color.white.opacity(0.55), lineWidth: 2)
                        .blendMode(.plusLighter))

            // IR window
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.black.opacity(0.22))
                .frame(width: 14, height: 4)
                .position(x: 95, y: 30)

            // Clickpad, dark so the ⌘ reads: remote + command = remote hotkeys.
            Circle()
                .fill(Self.clickpad)
                .frame(width: 152, height: 152)
                .overlay(
                    Circle()
                        .stroke(Self.accent.opacity(0.9), lineWidth: 5)
                        .frame(width: 152, height: 152))
                .shadow(color: .black.opacity(0.28), radius: 4, y: 3)
                .position(x: 95, y: 152)

            Image(systemName: "command")
                .font(.system(size: 74, weight: .medium))
                .foregroundStyle(Color.white)
                .position(x: 95, y: 152)

            // Power, back, TV, play/pause, mute — RemoteKey.all's centres, minus the
            // clickpad dots and Siri side key, which turn to mush below 128 pt.
            ForEach(Array(buttons.enumerated()), id: \.offset) { _, spot in
                Circle()
                    .fill(Self.key)
                    .frame(width: spot.d, height: spot.d)
                    .shadow(color: .black.opacity(0.2), radius: 1.5, y: 1.5)
                    .position(x: spot.x, y: spot.y)
            }

            // Volume rocker on the right flank.
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Self.key)
                .frame(width: 52, height: 118)
                .overlay(
                    Rectangle()
                        .fill(Color.black.opacity(0.09))
                        .frame(width: 26, height: 1.5))
                .shadow(color: .black.opacity(0.2), radius: 1.5, y: 1.5)
                .position(x: 142, y: 375)
        }
        .frame(width: 190, height: 560)
    }

    private var buttons: [(x: CGFloat, y: CGFloat, d: CGFloat)] {
        [(141, 39, 38), (48, 276, 52), (142, 276, 52), (48, 342, 52), (48, 408, 52)]
    }
}

private struct AppIconView: View {
    // macOS icon grid: 824 pt of artwork centred on a 1024 pt canvas.
    static let canvas: CGFloat = 1024
    static let plate: CGFloat = 824

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Self.plate * 0.2237, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0x414A63), Color(hex: 0x252A38), Color(hex: 0x11131A)],
                        startPoint: .top, endPoint: .bottom))
                .overlay(
                    RadialGradient(
                        colors: [Color(hex: 0x6E9BFF).opacity(0.30), .clear],
                        center: .center, startRadius: 0, endRadius: Self.plate * 0.55)
                        .clipShape(RoundedRectangle(cornerRadius: Self.plate * 0.2237, style: .continuous)))
                .overlay(
                    RoundedRectangle(cornerRadius: Self.plate * 0.2237, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 3))
                .frame(width: Self.plate, height: Self.plate)
                .shadow(color: .black.opacity(0.35), radius: 26, y: 18)

            RemoteFigure()
                .scaleEffect(1.15)
                .shadow(color: .black.opacity(0.45), radius: 26, y: 18)
        }
        .frame(width: Self.canvas, height: Self.canvas)
    }
}

// MARK: - Rendering

@MainActor
func renderPNG(points: CGFloat) -> Data {
    let renderer = ImageRenderer(content: AppIconView())
    renderer.scale = points / AppIconView.canvas
    guard let cgImage = renderer.cgImage else { fatalError("ImageRenderer produced no image") }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    rep.size = NSSize(width: points, height: points)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("PNG encoding failed")
    }
    return data
}

struct Slot {
    let size: Int
    let scale: Int
    var pixels: Int { size * scale }
    var filename: String { "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png" }
}

let slots = [16, 32, 128, 256, 512].flatMap { [Slot(size: $0, scale: 1), Slot(size: $0, scale: 2)] }

let outputDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

MainActor.assumeIsolated {
    for slot in slots {
        let data = renderPNG(points: CGFloat(slot.pixels))
        try! data.write(to: outputDir.appendingPathComponent(slot.filename))
        print("  \(slot.filename)  \(slot.pixels)×\(slot.pixels)")
    }
}

let images = slots.map { slot in
    """
        {
          "filename" : "\(slot.filename)",
          "idiom" : "mac",
          "scale" : "\(slot.scale)x",
          "size" : "\(slot.size)x\(slot.size)"
        }
    """
}.joined(separator: ",\n")

let contents = """
{
  "images" : [
\(images)
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}

"""
try contents.write(to: outputDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("  Contents.json")
