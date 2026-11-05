import SwiftUI

enum WorkspaceStatusColors {
    static let runningHex: UInt32 = 0x4F7CFF
    static let needsAttentionHex: UInt32 = 0xF5D90A
    static let badgeDotHex: UInt32 = 0xFF7A1A
    static let tabCircleHex: UInt32 = 0x555555
    static let idleGlyphHex: UInt32 = 0xD0D0D0
    static let doneGlyphHex: UInt32 = 0xFFFFFF
    static let idleDotHex: UInt32 = 0xA8A8A8

    static func hex(for state: SurfaceActivityState) -> UInt32 {
        switch state {
        case .idle: idleGlyphHex
        case .done: doneGlyphHex
        case .running: runningHex
        case .needsAttention: needsAttentionHex
        }
    }

    static func color(hex: UInt32, opacity: Double = 1) -> Color {
        Color(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    static func color(for state: SurfaceActivityState) -> Color {
        color(hex: hex(for: state))
    }
}

struct StatusIndicatorView: View {
    enum Style {
        case tab
        case compact
    }

    let state: SurfaceActivityState
    var style: Style = .tab
    var diameter: CGFloat = 12
    var tabDiameter: CGFloat = 18

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func accessibilityLabel(for state: SurfaceActivityState) -> String {
        switch state {
        case .idle: "Idle"
        case .done: "Done"
        case .running: "Running"
        case .needsAttention: "Needs you"
        }
    }

    var body: some View {
        Group {
            switch style {
            case .tab: tabIndicator
            case .compact: compactIndicator
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel(for: state))
    }

    private var tabScale: CGFloat {
        tabDiameter / 18
    }

    private var tabIndicator: some View {
        ZStack {
            Circle().fill(WorkspaceStatusColors.color(hex: WorkspaceStatusColors.tabCircleHex))
            switch state {
            case .idle:
                PromptGlyph()
                    .stroke(WorkspaceStatusColors.color(hex: WorkspaceStatusColors.idleGlyphHex), style: glyphStroke)
                    .frame(width: 11 * tabScale, height: 11 * tabScale)
            case .done:
                CheckGlyph()
                    .stroke(WorkspaceStatusColors.color(hex: WorkspaceStatusColors.doneGlyphHex), style: glyphStroke)
                    .frame(width: 12 * tabScale, height: 12 * tabScale)
            case .running:
                ArcGlyph()
                    .stroke(WorkspaceStatusColors.color(hex: WorkspaceStatusColors.runningHex), style: glyphStroke)
                    .frame(width: 12 * tabScale, height: 12 * tabScale)
                    .modifier(Spinning(period: 0.9, isActive: !reduceMotion))
            case .needsAttention:
                Circle()
                    .fill(WorkspaceStatusColors.color(hex: WorkspaceStatusColors.needsAttentionHex))
                    .frame(width: 8 * tabScale, height: 8 * tabScale)
            }
        }
        .frame(width: tabDiameter, height: tabDiameter)
    }

    private var glyphStroke: StrokeStyle {
        StrokeStyle(lineWidth: 1.75 * 12 / 24 * tabScale, lineCap: .round, lineJoin: .round)
    }

    @ViewBuilder
    private var compactIndicator: some View {
        switch state {
        case .idle:
            Circle()
                .fill(WorkspaceStatusColors.color(hex: WorkspaceStatusColors.idleDotHex))
                .frame(width: 6, height: 6)
                .frame(width: diameter, height: diameter)
        case .done:
            ZStack {
                Circle().fill(Color.white)
                CheckGlyph()
                    .stroke(
                        WorkspaceStatusColors.color(hex: 0x111111),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                    )
                    .frame(width: diameter * 0.6, height: diameter * 0.6)
            }
            .frame(width: diameter + 4, height: diameter + 4)
            .frame(width: diameter, height: diameter)
        case .running:
            ZStack {
                Circle().strokeBorder(
                    WorkspaceStatusColors.color(hex: WorkspaceStatusColors.runningHex, opacity: 0.25),
                    lineWidth: 1.5
                )
                Circle()
                    .trim(from: 0.625, to: 0.875)
                    .stroke(
                        WorkspaceStatusColors.color(hex: WorkspaceStatusColors.runningHex),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .butt)
                    )
                    .padding(0.75)
            }
            .frame(width: diameter - 1, height: diameter - 1)
            .modifier(Spinning(period: 0.9, isActive: !reduceMotion))
            .frame(width: diameter, height: diameter)
        case .needsAttention:
            Circle()
                .fill(WorkspaceStatusColors.color(hex: WorkspaceStatusColors.needsAttentionHex))
                .shadow(color: WorkspaceStatusColors.color(hex: WorkspaceStatusColors.needsAttentionHex, opacity: 0.55), radius: 3.5)
                .frame(width: diameter - 3, height: diameter - 3)
                .frame(width: diameter, height: diameter)
        }
    }
}

struct Spinning: ViewModifier {
    let period: Double
    let isActive: Bool

    @State private var angle: Double = 0

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(angle))
            .onAppear { restart() }
            .onChange(of: isActive) { _ in restart() }
    }

    private func restart() {
        var reset = Transaction()
        reset.disablesAnimations = true
        withTransaction(reset) { angle = 0 }
        guard isActive else { return }
        withAnimation(.linear(duration: period).repeatForever(autoreverses: false)) {
            angle = 360
        }
    }
}

struct PromptGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
        }
        var path = Path()
        path.move(to: point(4, 17))
        path.addLine(to: point(10, 11))
        path.addLine(to: point(4, 5))
        path.move(to: point(12, 19))
        path.addLine(to: point(20, 19))
        return path
    }
}

struct CheckGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * scale, y: rect.minY + y * scale)
        }
        var path = Path()
        path.move(to: point(20, 6))
        path.addLine(to: point(9, 17))
        path.addLine(to: point(4, 12))
        return path
    }
}

struct ArcGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) * 9 / 24
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: radius,
            startAngle: .degrees(0),
            endAngle: .degrees(270),
            clockwise: false
        )
        return path
    }
}
