import RemoteCore
import SwiftUI

/// A drawn clickpad Siri Remote used as the button selector. Geometry follows the Claude Design mockup
/// (190 × 644 canvas — the mockup's 560 plus the blank shell the real remote carries below the volume
/// rocker); the selected button gets an accent ring, buttons the profile lacks are dimmed.
/// `scale` shrinks the whole figure — hit targets included — for the menu-bar panel. `selected` draws the
/// editor's accent ring; `highlighted` lights a key up, which is how the Remotes tab shows live presses.
/// Without `onSelect` the figure is a display, not a control.
struct RemoteFigureView: View {
    let available: Set<RemoteButton>
    var selected: RemoteButton?
    var highlighted: Set<RemoteButton> = []
    var scale: CGFloat = 1
    var onSelect: ((RemoteButton) -> Void)?

    @State private var hovered: RemoteButton?

    /// Key placement is fixed to this canvas; only the shell grows with it.
    static let canvas = CGSize(width: 190, height: 644)

    private static let shell = LinearGradient(
        colors: [Color(hex: 0xE3E3E7), Color(hex: 0xB7B7BD), Color(hex: 0x9D9DA3)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    private static let key = LinearGradient(
        colors: [Color(hex: 0xF2F2F5), Color(hex: 0xCDCDD3)], startPoint: .topLeading, endPoint: .bottomTrailing)
    private static let concave = LinearGradient(
        colors: [Color(hex: 0xF6F6F9), Color(hex: 0xD2D2D8)], startPoint: .topLeading, endPoint: .bottomTrailing)
    private static let clickpad = LinearGradient(
        colors: [Color(hex: 0xECECF0), Color(hex: 0xC3C3C9)], startPoint: .topLeading, endPoint: .bottomTrailing)
    private static let side = LinearGradient(
        colors: [Color(hex: 0x9A9AA0), Color(hex: 0xC9C9CE)], startPoint: .leading, endPoint: .trailing)
    static let glyph = Color(hex: 0x55555B)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 52, style: .continuous)
                .fill(Self.shell)
                .shadow(color: Color.black.opacity(0.5), radius: 25, y: 24)
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.black.opacity(0.2))
                .frame(width: 10, height: 3.5)
                .position(x: 95, y: 28)
            Circle()
                .fill(Self.clickpad)
                .frame(width: 150, height: 150)
                .shadow(color: Color.black.opacity(0.2), radius: 2, y: 2)
                .position(x: 95, y: 151)
            RoundedRectangle(cornerRadius: 26)
                .fill(Self.key)
                .frame(width: 52, height: 118)
                .shadow(color: Color.black.opacity(0.2), radius: 1, y: 1)
                .position(x: 142, y: 375)
            Rectangle()
                .fill(Color.black.opacity(0.1))
                .frame(width: 28, height: 1)
                .position(x: 142, y: 375)
            ForEach(RemoteKey.all) { key in
                keyView(key)
            }
        }
        .frame(width: Self.canvas.width, height: Self.canvas.height)
        .scaleEffect(scale)
        .frame(width: Self.canvas.width * scale, height: Self.canvas.height * scale)
    }

    private func keyView(_ key: RemoteKey) -> some View {
        let isLit = highlighted.contains(key.button)
        return ZStack {
            face(for: key)
                .brightness(hovered == key.button ? 0.04 : 0)
            glow(for: key)
                .opacity(isLit ? 1 : 0)
            ring(for: key)
                .opacity(selected == key.button ? 1 : 0)
        }
        .animation(.easeOut(duration: 0.12), value: isLit)
        .frame(width: key.size.width + 20, height: key.size.height + 20)
        .contentShape(Rectangle())
        .onTapGesture { onSelect?(key.button) }
        .onHover { inside in
            guard onSelect != nil else { return }
            if inside { hovered = key.button } else if hovered == key.button { hovered = nil }
        }
        .opacity(available.contains(key.button) ? 1 : 0.35)
        .position(key.center)
    }

    /// A pressed key: the face washed in the accent colour, plus a halo so it reads at panel scale.
    @ViewBuilder
    private func glow(for key: RemoteKey) -> some View {
        let accent = Color.accentColor
        let fill = accent.opacity(0.5)
        let halo = accent.opacity(0.85)
        switch key.kind {
        case .round, .concave, .dot:
            Circle()
                .fill(fill)
                .frame(width: key.size.width, height: key.size.height)
                .shadow(color: halo, radius: 7)
        case .rockerTop:
            UnevenRoundedRectangle(topLeadingRadius: 26, bottomLeadingRadius: 4, bottomTrailingRadius: 4, topTrailingRadius: 26)
                .fill(fill)
                .frame(width: key.size.width, height: key.size.height - 2)
                .shadow(color: halo, radius: 7)
        case .rockerBottom:
            UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 26, bottomTrailingRadius: 26, topTrailingRadius: 4)
                .fill(fill)
                .frame(width: key.size.width, height: key.size.height - 2)
                .shadow(color: halo, radius: 7)
        case .side:
            RoundedRectangle(cornerRadius: 4)
                .fill(fill)
                .frame(width: key.size.width, height: key.size.height)
                .shadow(color: halo, radius: 6)
        }
    }

    @ViewBuilder
    private func face(for key: RemoteKey) -> some View {
        switch key.kind {
        case .round:
            Circle()
                .fill(Self.key)
                .shadow(color: Color.black.opacity(0.2), radius: 1, y: 1)
                .frame(width: key.size.width, height: key.size.height)
                .overlay(glyph(for: key.button))
        case .concave:
            Circle()
                .fill(Self.concave)
                .overlay(Circle().stroke(Color.black.opacity(0.07)))
                .frame(width: key.size.width, height: key.size.height)
        case .dot:
            Circle()
                .fill(hovered == key.button ? Color.black.opacity(0.045) : Color.clear)
                .frame(width: key.size.width, height: key.size.height)
                .overlay(Circle().fill(Color.black.opacity(0.26)).frame(width: 6, height: 6))
        case .rockerTop, .rockerBottom:
            Text(key.kind == .rockerTop ? "+" : "−")
                .font(.system(size: 22))
                .foregroundStyle(Self.glyph)
                .frame(width: key.size.width, height: key.size.height)
        case .side:
            RoundedRectangle(cornerRadius: 4)
                .fill(Self.side)
                .frame(width: key.size.width, height: key.size.height)
        }
    }

    @ViewBuilder
    private func ring(for key: RemoteKey) -> some View {
        let accent = Color.accentColor
        switch key.kind {
        case .round, .concave:
            Circle().stroke(accent, lineWidth: 2.5)
                .frame(width: key.size.width + 12, height: key.size.height + 12)
        case .dot:
            Circle().stroke(accent, lineWidth: 2)
                .frame(width: key.size.width, height: key.size.height)
        case .rockerTop:
            UnevenRoundedRectangle(topLeadingRadius: 28, bottomLeadingRadius: 6, bottomTrailingRadius: 6, topTrailingRadius: 28)
                .stroke(accent, lineWidth: 2.5)
                .frame(width: key.size.width + 12, height: key.size.height + 4)
        case .rockerBottom:
            UnevenRoundedRectangle(topLeadingRadius: 6, bottomLeadingRadius: 28, bottomTrailingRadius: 28, topTrailingRadius: 6)
                .stroke(accent, lineWidth: 2.5)
                .frame(width: key.size.width + 12, height: key.size.height + 4)
        case .side:
            RoundedRectangle(cornerRadius: 8).stroke(accent, lineWidth: 2.5)
                .frame(width: key.size.width + 10, height: key.size.height + 10)
        }
    }

    @ViewBuilder
    private func glyph(for button: RemoteButton) -> some View {
        switch button {
        case .power:
            Image(systemName: "power").font(.system(size: 17, weight: .medium)).foregroundStyle(Self.glyph)
        case .back:
            Image(systemName: "chevron.backward").font(.system(size: 21, weight: .medium)).foregroundStyle(Self.glyph)
        case .tv:
            RoundedRectangle(cornerRadius: 3).stroke(Self.glyph, lineWidth: 2).frame(width: 20, height: 15)
        case .playPause:
            Image(systemName: "playpause.fill").font(.system(size: 15)).foregroundStyle(Self.glyph)
        case .mute:
            Image(systemName: "speaker.slash.fill").font(.system(size: 15)).foregroundStyle(Self.glyph)
        default:
            EmptyView()
        }
    }
}

/// Placement of one key on the 190 × 644 canvas (centre-based); unchanged from the mockup's geometry.
struct RemoteKey: Identifiable {
    enum Kind { case round, concave, dot, rockerTop, rockerBottom, side }

    let button: RemoteButton
    let center: CGPoint
    let size: CGSize
    let kind: Kind

    var id: RemoteButton { button }

    static let all: [RemoteKey] = [
        RemoteKey(button: .siri, center: CGPoint(x: 189, y: 150), size: CGSize(width: 8, height: 60), kind: .side),
        RemoteKey(button: .power, center: CGPoint(x: 141, y: 39), size: CGSize(width: 38, height: 38), kind: .round),
        RemoteKey(button: .select, center: CGPoint(x: 95, y: 151), size: CGSize(width: 66, height: 66), kind: .concave),
        RemoteKey(button: .up, center: CGPoint(x: 95, y: 97), size: CGSize(width: 30, height: 30), kind: .dot),
        RemoteKey(button: .down, center: CGPoint(x: 95, y: 205), size: CGSize(width: 30, height: 30), kind: .dot),
        RemoteKey(button: .left, center: CGPoint(x: 41, y: 151), size: CGSize(width: 30, height: 30), kind: .dot),
        RemoteKey(button: .right, center: CGPoint(x: 149, y: 151), size: CGSize(width: 30, height: 30), kind: .dot),
        RemoteKey(button: .back, center: CGPoint(x: 48, y: 276), size: CGSize(width: 52, height: 52), kind: .round),
        RemoteKey(button: .tv, center: CGPoint(x: 142, y: 276), size: CGSize(width: 52, height: 52), kind: .round),
        RemoteKey(button: .playPause, center: CGPoint(x: 48, y: 342), size: CGSize(width: 52, height: 52), kind: .round),
        RemoteKey(button: .mute, center: CGPoint(x: 48, y: 408), size: CGSize(width: 52, height: 52), kind: .round),
        RemoteKey(button: .volumeUp, center: CGPoint(x: 142, y: 345.5), size: CGSize(width: 52, height: 59), kind: .rockerTop),
        RemoteKey(button: .volumeDown, center: CGPoint(x: 142, y: 404.5), size: CGSize(width: 52, height: 59), kind: .rockerBottom),
    ]
}
