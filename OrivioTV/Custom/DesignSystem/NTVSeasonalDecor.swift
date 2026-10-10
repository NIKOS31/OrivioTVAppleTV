import SwiftUI

/// Static edge ornaments never alter a control's size, material or focus frame.
/// The preference is local to this installation; October is the only active month.
enum NTVHalloweenPlacement: Equatable { case navigation, heading }

private struct NTVHalloweenModifier: ViewModifier {
    @AppStorage("ntv.seasonal.halloween.enabled") private var enabled = true
    @Environment(\.scenePhase) private var scenePhase
    @State private var month = Calendar.current.component(.month, from: Date())
    let placement: NTVHalloweenPlacement

    private var visible: Bool {
        enabled && (month == 10 || ProcessInfo.processInfo.arguments.contains("-ntvHalloweenDemo"))
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomLeading) {
                if visible && placement == .navigation {
                    HStack(alignment: .bottom, spacing: 10) {
                        NTVPumpkin().frame(width: 30, height: 24)
                        NTVBat().fill(.white.opacity(0.42)).frame(width: 38, height: 20)
                    }
                    .offset(x: 28, y: 8)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if visible && placement == .navigation {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(spacing: 0) {
                            Rectangle().fill(.white.opacity(0.24)).frame(width: 1, height: 17)
                            NTVGhost().frame(width: 22, height: 25)
                        }
                        NTVWeb().stroke(.white.opacity(0.26), lineWidth: 0.9)
                            .frame(width: 42, height: 42)
                    }
                    .offset(x: -28, y: 41)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .overlay(alignment: .trailing) {
                if visible && placement == .heading {
                    NTVCandy().stroke(.white.opacity(0.45), lineWidth: 1)
                        .frame(width: 24, height: 18)
                        .rotationEffect(.degrees(-25))
                        .offset(x: 38)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { month = Calendar.current.component(.month, from: Date()) }
            }
    }
}

extension View {
    func ntvHalloweenDecor(_ placement: NTVHalloweenPlacement) -> some View {
        modifier(NTVHalloweenModifier(placement: placement))
    }
}

private struct NTVPumpkin: View {
    var body: some View {
        ZStack {
            Ellipse().fill(Color(red: 0.58, green: 0.42, blue: 0.26))
            Ellipse().stroke(.white.opacity(0.2), lineWidth: 0.8).padding(.horizontal, 7)
            HStack(spacing: 8) {
                Circle().frame(width: 3, height: 3)
                Circle().frame(width: 3, height: 3)
            }
            .foregroundStyle(.black.opacity(0.7)).offset(y: -2)
            Capsule().fill(.black.opacity(0.65)).frame(width: 10, height: 2).offset(y: 6)
            RoundedRectangle(cornerRadius: 1).fill(Color(red: 0.46, green: 0.48, blue: 0.39))
                .frame(width: 4, height: 7).rotationEffect(.degrees(15)).offset(y: -14)
        }
    }
}

private struct NTVGhost: View {
    var body: some View {
        ZStack {
            NTVGhostOutline().stroke(.white.opacity(0.44), lineWidth: 1)
            HStack(spacing: 5) {
                Circle().frame(width: 2, height: 2)
                Circle().frame(width: 2, height: 2)
            }
            .foregroundStyle(.white.opacity(0.5)).offset(y: -2)
        }
    }
}

private struct NTVGhostOutline: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.midY),
                          control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.5))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        for index in (0..<3).reversed() {
            let x = rect.minX + CGFloat(index) * rect.width / 3
            path.addQuadCurve(to: CGPoint(x: x, y: rect.maxY),
                              control: CGPoint(x: x + rect.width / 6, y: rect.maxY - 5))
        }
        path.closeSubpath()
        return path
    }
}

private struct NTVBat: Shape {
    func path(in rect: CGRect) -> Path {
        let points: [(CGFloat, CGFloat)] = [
            (0, 0.4), (0.12, 0.28), (0.07, 0), (0.33, 0.25), (0.4, 0.18),
            (0.45, 0.27), (0.47, 0.03), (0.51, 0.16), (0.55, 0.03), (0.58, 0.27),
            (0.65, 0.18), (0.74, 0.25), (0.94, 0), (0.89, 0.28), (1, 0.4),
            (0.8, 0.53), (0.7, 0.71), (0.64, 0.58), (0.52, 0.95),
            (0.43, 0.63), (0.34, 0.72), (0.25, 0.53)
        ]
        var path = Path()
        path.addLines(points.map { CGPoint(x: rect.minX + $0.0 * rect.width, y: rect.minY + $0.1 * rect.height) })
        path.closeSubpath()
        return path
    }
}

private struct NTVWeb: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let origin = CGPoint(x: rect.minX, y: rect.minY)
        for index in 0...4 {
            let angle = Double(index) * .pi / 8
            path.move(to: origin)
            path.addLine(to: CGPoint(x: origin.x + rect.width * cos(angle), y: origin.y + rect.height * sin(angle)))
        }
        for fraction in [0.33, 0.66, 1.0] {
            let radius = min(rect.width, rect.height) * CGFloat(fraction)
            path.move(to: CGPoint(x: origin.x + radius, y: origin.y))
            path.addArc(center: origin, radius: radius,
                        startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        }
        return path
    }
}

private struct NTVCandy: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(ellipseIn: CGRect(x: rect.minX + rect.width * 0.25, y: rect.minY + rect.height * 0.15,
                                         width: rect.width * 0.5, height: rect.height * 0.7))
        for edge in [CGFloat(0), CGFloat(1)] {
            let x = rect.minX + edge * rect.width
            let innerX = rect.minX + (edge == 0 ? 0.28 : 0.72) * rect.width
            path.move(to: CGPoint(x: innerX, y: rect.midY))
            path.addLine(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}
