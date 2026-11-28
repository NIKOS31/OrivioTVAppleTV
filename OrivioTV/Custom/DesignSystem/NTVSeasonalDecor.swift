import SwiftUI

/// Static ornaments sit beside page headings, away from navigation controls.
/// Each season has its own local preference: Halloween in October, Christmas
/// from 20 November to 6 January. Nothing here is focusable or animated,
/// except the optional Home snowfall below.
enum NTVHalloweenPlacement: Equatable { case heading, row, panel, stage, rail }
typealias NTVSeasonalPlacement = NTVHalloweenPlacement

enum NTVSeason: Equatable {
    case halloween, christmas

    static func active(on date: Date = Date(), arguments: [String] = ProcessInfo.processInfo.arguments) -> NTVSeason? {
        if arguments.contains("-ntvHalloweenDemo") { return .halloween }
        if arguments.contains("-ntvChristmasDemo") { return .christmas }
        #if DEBUG
        // UI test fixtures must not depend on the calendar: no seasonal decor
        // in a demo or fixture launch unless one of the flags above asks.
        if arguments.contains(where: { $0.hasPrefix("-") && ($0.hasSuffix("Demo") || $0.hasSuffix("Fixture")) }) {
            return nil
        }
        #endif
        let parts = Calendar.current.dateComponents([.month, .day], from: date)
        switch (parts.month ?? 0, parts.day ?? 0) {
        case (10, _): return .halloween
        case (11, let day) where day >= 20: return .christmas
        case (12, _): return .christmas
        case (1, let day) where day <= 6: return .christmas
        default: return nil
        }
    }
}

private struct NTVSeasonalModifier: ViewModifier {
    @AppStorage("ntv.seasonal.halloween.enabled") private var halloween = true
    @AppStorage("ntv.seasonal.christmas.enabled") private var christmas = true
    @Environment(\.scenePhase) private var scenePhase
    @State private var season = NTVSeason.active()
    let placement: NTVSeasonalPlacement

    private var visible: NTVSeason? {
        switch season {
        case .halloween: return halloween ? .halloween : nil
        case .christmas: return christmas ? .christmas : nil
        case nil: return nil
        }
    }

    func body(content: Content) -> some View {
        decorated(content)
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { season = NTVSeason.active() }
            }
    }

    @ViewBuilder private func decorated(_ content: Content) -> some View {
        switch visible {
        case .halloween: halloweenDecor(content)
        case .christmas: christmasDecor(content)
        case nil: content
        }
    }

    @ViewBuilder private func halloweenDecor(_ content: Content) -> some View {
        switch placement {
        case .heading:
            HStack(alignment: .center, spacing: 18) {
                content
                HStack(spacing: 12) {
                    NTVPumpkin().frame(width: 34, height: 28)
                    NTVBat().fill(.white.opacity(0.5)).frame(width: 38, height: 22)
                }.allowsHitTesting(false).accessibilityHidden(true)
            }
        case .row:
            content.overlay(alignment: .trailing) {
                NTVCandy().fill(Color(red: 0.68, green: 0.48, blue: 0.30).opacity(0.65))
                    .frame(width: 28, height: 15).offset(x: 42)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        case .panel:
            VStack(spacing: 12) {
                content
                HStack {
                    NTVWeb().stroke(.white.opacity(0.3), lineWidth: 1.2)
                        .frame(width: 42, height: 42).rotationEffect(.degrees(90))
                    Spacer()
                    NTVPumpkin().frame(width: 30, height: 24)
                    NTVGhost().frame(width: 30, height: 38)
                }
                .padding(.horizontal, 8)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        case .stage:
            content.overlay(alignment: .topTrailing) {
                NTVWeb().stroke(.white.opacity(0.24), lineWidth: 1.1)
                    .frame(width: 36, height: 36).rotationEffect(.degrees(90))
                    .padding(.top, 8).padding(.trailing, 8)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        case .rail:
            content
        }
    }

    // Christmas keeps the app's charcoal and off-white: frost-white
    // snowflakes, one warm gold star, muted fir green and a deep red bauble.
    @ViewBuilder private func christmasDecor(_ content: Content) -> some View {
        switch placement {
        case .heading:
            // Santa's sleigh and reindeer sit beside every page title
            // (owner's request, 28 Nov 2026): visible on each main screen,
            // clear of every control.
            HStack(alignment: .center, spacing: 20) {
                content
                NTVSleighScene().frame(width: 160, height: 56)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        case .row:
            content.overlay(alignment: .trailing) {
                NTVSnowflake().stroke(.white.opacity(0.45), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .frame(width: 20, height: 20).offset(x: 36)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        case .panel:
            VStack(spacing: 12) {
                content
                HStack(alignment: .bottom) {
                    NTVSnowflake().stroke(.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                        .frame(width: 26, height: 26)
                    Spacer()
                    NTVBauble().frame(width: 24, height: 30)
                    NTVFir().frame(width: 34, height: 42)
                }
                .padding(.horizontal, 8)
                .allowsHitTesting(false).accessibilityHidden(true)
            }
        case .stage:
            content.overlay(alignment: .topTrailing) {
                HStack(alignment: .top, spacing: 10) {
                    NTVSnowflake().stroke(.white.opacity(0.18), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
                        .frame(width: 18, height: 18).offset(y: 14)
                    NTVSnowflake().stroke(.white.opacity(0.24), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                        .frame(width: 30, height: 30)
                }
                .padding(.top, 10).padding(.trailing, 12)
                .allowsHitTesting(false).accessibilityHidden(true)
            }
        case .rail:
            content.overlay(alignment: .top) {
                NTVGarland().frame(width: 58, height: 16).offset(y: -7)
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
    }
}

extension View {
    func ntvSeasonalDecor(_ placement: NTVSeasonalPlacement) -> some View {
        modifier(NTVSeasonalModifier(placement: placement))
    }
}

private enum NTVChristmasPalette {
    static let gold = Color(red: 0.86, green: 0.72, blue: 0.42)
    static let fir = Color(red: 0.30, green: 0.44, blue: 0.36)
    static let red = Color(red: 0.62, green: 0.20, blue: 0.22)
}

/// Optional, Home only: a sparse, slow snowfall behind the content. Off by
/// default; never drawn with Reduce Motion, on low-power models or while the
/// app is in the background. One Canvas, forty flakes (six-armed near ones,
/// small far dots), 30 fps.
struct NTVSnowfall: View {
    @AppStorage("ntv.seasonal.christmas.enabled") private var christmas = true
    @AppStorage("ntv.seasonal.snow.enabled") private var snow = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var season = NTVSeason.active()

    private var active: Bool {
        let demo = ProcessInfo.processInfo.arguments.contains("-ntvSnowDemo")
        // An explicit choice: once enabled, it snows whatever the date.
        return christmas && (snow || demo) && !reduceMotion && !PerformanceProfile.isLowPower
    }

    var body: some View {
        Group {
            if active {
                TimelineView(.animation(minimumInterval: 1.0 / 30, paused: scenePhase != .active)) { context in
                    Canvas { graphics, size in
                        let time = context.date.timeIntervalSinceReferenceDate
                        for index in 0..<40 {
                            let seed = Double(index)
                            let baseX = (seed * 0.618_034).truncatingRemainder(dividingBy: 1) * size.width
                            let travel = size.height + 60
                            // Two layers (owner: "just dots"): every third flake is a
                            // small far-away dot, the rest are real six-armed flakes
                            // that fall faster and turn slowly, nearer the viewer.
                            let near = index % 3 != 0
                            let speed = (near ? 34 : 18) + (seed * 7).truncatingRemainder(dividingBy: 18)
                            let y = (time * speed + seed * 97).truncatingRemainder(dividingBy: travel) - 30
                            let x = baseX + sin(time * 0.35 + seed) * 22
                            if near {
                                let radius = 7 + (seed * 3.7).truncatingRemainder(dividingBy: 7)
                                var flake = graphics
                                flake.translateBy(x: x, y: y)
                                flake.rotate(by: .radians(time * 0.4 + seed))
                                let path = NTVSnowflake().path(in: CGRect(x: -radius, y: -radius,
                                                                          width: radius * 2, height: radius * 2))
                                flake.stroke(path, with: .color(.white.opacity(0.32 + radius * 0.02)),
                                             style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                            } else {
                                let radius = 1.4 + (seed * 3.7).truncatingRemainder(dividingBy: 1.4)
                                let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                                graphics.fill(Path(ellipseIn: rect), with: .color(.white.opacity(0.22)))
                            }
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .ignoresSafeArea()
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { season = NTVSeason.active() }
        }
    }
}

private struct NTVSnowflake: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        for index in 0..<6 {
            let angle = Double(index) * .pi / 3 - .pi / 2
            let tip = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            path.move(to: center)
            path.addLine(to: tip)
            // Two short barbs at two thirds of each arm.
            let barbBase = CGPoint(x: center.x + radius * 0.62 * cos(angle), y: center.y + radius * 0.62 * sin(angle))
            for side in [-1.0, 1.0] {
                let barbAngle = angle + side * .pi / 4
                path.move(to: barbBase)
                path.addLine(to: CGPoint(x: barbBase.x + radius * 0.28 * cos(barbAngle),
                                         y: barbBase.y + radius * 0.28 * sin(barbAngle)))
            }
        }
        return path
    }
}

private struct NTVStar: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.45
        for index in 0..<10 {
            let angle = Double(index) * .pi / 5 - .pi / 2
            let radius = index.isMultiple(of: 2) ? outer : inner
            let point = CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle))
            index == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        path.closeSubpath()
        return path
    }
}

private struct NTVFir: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            NTVFirShape().fill(NTVChristmasPalette.fir.opacity(0.85))
            RoundedRectangle(cornerRadius: 1).fill(Color(red: 0.36, green: 0.28, blue: 0.22))
                .frame(width: 5, height: 6)
            NTVStar().fill(NTVChristmasPalette.gold).frame(width: 10, height: 10)
                .frame(maxHeight: .infinity, alignment: .top).offset(y: -4)
        }
    }
}

private struct NTVFirShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let tiers: [(CGFloat, CGFloat)] = [(0.0, 0.42), (0.22, 0.68), (0.44, 0.88)]
        for (top, bottom) in tiers {
            let width = rect.width * (0.45 + bottom * 0.55)
            path.move(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * top))
            path.addLine(to: CGPoint(x: rect.midX + width / 2, y: rect.minY + rect.height * bottom))
            path.addLine(to: CGPoint(x: rect.midX - width / 2, y: rect.minY + rect.height * bottom))
            path.closeSubpath()
        }
        return path
    }
}

private struct NTVBauble: View {
    var body: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1).fill(NTVChristmasPalette.gold.opacity(0.8))
                .frame(width: 7, height: 5)
            Circle().fill(NTVChristmasPalette.red)
                .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 0.8))
                .overlay(alignment: .topLeading) {
                    Circle().fill(.white.opacity(0.35)).frame(width: 5, height: 5).padding(5)
                }
        }
    }
}

/// A short string of warm lights draped over the closed rail pill.
private struct NTVGarland: View {
    private let colors: [Color] = [NTVChristmasPalette.gold, NTVChristmasPalette.red,
                                   NTVChristmasPalette.fir, NTVChristmasPalette.gold, NTVChristmasPalette.red]
    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width, height = geometry.size.height
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: height * 0.25))
                    path.addQuadCurve(to: CGPoint(x: width, y: height * 0.25),
                                      control: CGPoint(x: width / 2, y: height * 1.1))
                }
                .stroke(.white.opacity(0.28), lineWidth: 1)
                ForEach(colors.indices, id: \.self) { index in
                    let t = CGFloat(index + 1) / CGFloat(colors.count + 1)
                    // Point on the quadratic curve at t.
                    let x = width * t
                    let y = height * 0.25 * (1 - t) * (1 - t) + height * 1.1 * 2 * t * (1 - t) + height * 0.25 * t * t
                    Circle().fill(colors[index]).frame(width: 6, height: 6)
                        .position(x: x, y: y + 2)
                }
            }
        }
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

/// Two reindeer pulling Santa's sleigh, in side view, facing left. A static
/// Canvas in the app's palette: warm off-white reindeer, a deep red sleigh
/// and coat, gold runner and harness.
struct NTVSleighScene: View {
    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            func point(_ x: CGFloat, _ y: CGFloat, in box: CGRect) -> CGPoint {
                CGPoint(x: box.minX + x * box.width, y: box.minY + y * box.height)
            }
            func reindeer(in box: CGRect) {
                let outline: [(CGFloat, CGFloat)] = [
                    (0.30, 0.36), (0.70, 0.33), (0.82, 0.40), (0.90, 0.32), (0.86, 0.46),
                    (0.82, 0.54), (0.97, 0.78), (0.93, 0.83), (0.72, 0.62), (0.46, 0.61),
                    (0.30, 0.63), (0.10, 0.79), (0.07, 0.74), (0.24, 0.55), (0.23, 0.45),
                    (0.17, 0.30), (0.12, 0.22), (0.02, 0.27), (0.04, 0.33), (0.15, 0.35)
                ]
                var body = Path()
                body.addLines(outline.map { point($0.0, $0.1, in: box) })
                body.closeSubpath()
                context.fill(body, with: .color(NTVDesign.textPrimary.opacity(0.78)))
                var antlers = Path()
                for (from, to) in [((0.14, 0.22), (0.21, 0.02)), ((0.18, 0.11), (0.28, 0.06)),
                                   ((0.13, 0.21), (0.08, 0.04)), ((0.10, 0.12), (0.03, 0.09))] {
                    antlers.move(to: point(from.0, from.1, in: box))
                    antlers.addLine(to: point(to.0, to.1, in: box))
                }
                context.stroke(antlers, with: .color(NTVDesign.textPrimary.opacity(0.78)),
                               style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            }
            let first = CGRect(x: 0, y: h * 0.18, width: w * 0.26, height: h * 0.62)
            let second = CGRect(x: w * 0.24, y: h * 0.10, width: w * 0.26, height: h * 0.62)
            reindeer(in: first)
            reindeer(in: second)

            let sleigh = CGRect(x: w * 0.55, y: h * 0.05, width: w * 0.45, height: h * 0.9)
            // Harness from the reindeer to the sleigh's front.
            var harness = Path()
            harness.move(to: point(0.10, 0.45, in: first.union(second)))
            harness.addQuadCurve(to: point(0.10, 0.62, in: sleigh),
                                 control: CGPoint(x: w * 0.50, y: h * 0.62))
            context.stroke(harness, with: .color(NTVChristmasPalette.gold.opacity(0.8)), lineWidth: 1.2)
            // Runner with a curled front.
            var runner = Path()
            runner.move(to: point(0.10, 0.70, in: sleigh))
            runner.addQuadCurve(to: point(0.12, 0.92, in: sleigh), control: point(0.0, 0.84, in: sleigh))
            runner.addLine(to: point(0.94, 0.92, in: sleigh))
            runner.addQuadCurve(to: point(0.98, 0.80, in: sleigh), control: point(1.0, 0.92, in: sleigh))
            context.stroke(runner, with: .color(NTVChristmasPalette.gold), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            // Sleigh body.
            var box = Path()
            box.addLines([point(0.14, 0.80, in: sleigh), point(0.18, 0.56, in: sleigh), point(0.46, 0.60, in: sleigh),
                          point(0.62, 0.60, in: sleigh), point(0.76, 0.30, in: sleigh), point(0.94, 0.28, in: sleigh),
                          point(0.90, 0.80, in: sleigh)])
            box.closeSubpath()
            context.fill(box, with: .color(NTVChristmasPalette.red))
            // Santa: coat, beard and face, hat with its pompom.
            let coat = CGRect(x: sleigh.minX + sleigh.width * 0.44, y: sleigh.minY + sleigh.height * 0.30,
                              width: sleigh.width * 0.26, height: sleigh.height * 0.36)
            context.fill(Path(ellipseIn: coat), with: .color(NTVChristmasPalette.red.opacity(0.95)))
            let face = CGRect(x: sleigh.minX + sleigh.width * 0.49, y: sleigh.minY + sleigh.height * 0.14,
                              width: sleigh.width * 0.15, height: sleigh.height * 0.20)
            context.fill(Path(ellipseIn: face), with: .color(NTVDesign.textPrimary.opacity(0.92)))
            var hat = Path()
            hat.addLines([point(0.48, 0.17, in: sleigh), point(0.65, 0.17, in: sleigh), point(0.74, 0.02, in: sleigh)])
            hat.closeSubpath()
            context.fill(hat, with: .color(NTVChristmasPalette.red))
            let pompom = CGRect(x: sleigh.minX + sleigh.width * 0.715, y: sleigh.minY - sleigh.height * 0.02,
                                width: sleigh.width * 0.06, height: sleigh.width * 0.06)
            context.fill(Path(ellipseIn: pompom), with: .color(NTVDesign.textPrimary))
        }
    }
}
