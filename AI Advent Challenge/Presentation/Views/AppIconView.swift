import SwiftUI

// MARK: - App Icon View
// Предназначена для предпросмотра в Xcode Canvas.
// Для экспорта PNG используйте скриншот Canvas при размере 1024×1024.

struct AppIconView: View {

    // MARK: - Цветовая схема

    private let bgTop    = Color(red: 0.06, green: 0.04, blue: 0.22)
    private let bgBottom = Color(red: 0.22, green: 0.06, blue: 0.50)
    private let orbTop   = Color(red: 0.55, green: 0.35, blue: 1.00)
    private let orbBot   = Color(red: 0.25, green: 0.08, blue: 0.65)
    private let nodeColor = Color(red: 0.70, green: 0.55, blue: 1.00)

    // MARK: - Body

    var body: some View {
        ZStack {
            background
            subtleGrid
            neuralRings
            circuitNodes
            centralOrb
            brainIcon
            sparkles
        }
        .frame(width: 1024, height: 1024)
        .clipped()
    }

    // MARK: - Слои

    private var background: some View {
        LinearGradient(
            colors: [bgTop, bgBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var subtleGrid: some View {
        Canvas { ctx, size in
            let step: CGFloat = 80
            var x: CGFloat = 0
            while x <= size.width {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(path, with: .color(.white.opacity(0.04)), lineWidth: 1)
                x += step
            }
            var y: CGFloat = 0
            while y <= size.height {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(path, with: .color(.white.opacity(0.04)), lineWidth: 1)
                y += step
            }
        }
    }

    // Два полупрозрачных кольца вокруг центра
    private var neuralRings: some View {
        ZStack {
            Circle()
                .stroke(nodeColor.opacity(0.12), lineWidth: 2)
                .frame(width: 680, height: 680)
            Circle()
                .stroke(nodeColor.opacity(0.07), lineWidth: 1.5)
                .frame(width: 860, height: 860)
        }
    }

    // 8 узлов на внешнем кольце + линии к центру
    private var circuitNodes: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                let angle = Double(i) * .pi / 4
                let innerR: CGFloat = 240
                let outerR: CGFloat = 340

                // Линия центр → узел
                NodeLine(angle: angle, innerRadius: innerR, outerRadius: outerR)
                    .stroke(nodeColor.opacity(0.20), lineWidth: 1.5)

                // Узел (кружок)
                Circle()
                    .fill(nodeColor.opacity(0.55))
                    .frame(width: 16, height: 16)
                    .shadow(color: nodeColor.opacity(0.8), radius: 8)
                    .offset(
                        x: cos(angle) * outerR,
                        y: sin(angle) * outerR
                    )
            }
        }
        .frame(width: 1024, height: 1024)
    }

    // Центральный светящийся шар
    private var centralOrb: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [orbTop, orbBot],
                    center: .center,
                    startRadius: 0,
                    endRadius: 220
                )
            )
            .frame(width: 440, height: 440)
            .shadow(color: orbTop.opacity(0.6), radius: 80)
            .shadow(color: orbTop.opacity(0.3), radius: 40)
    }

    // SF Symbol мозга
    private var brainIcon: some View {
        Image(systemName: "brain.filled.head.profile")
            .resizable()
            .scaledToFit()
            .frame(width: 260)
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        .white,
                        Color(red: 0.88, green: 0.80, blue: 1.00)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .shadow(color: .white.opacity(0.6), radius: 15)
    }

    // Случайные искры вокруг
    private var sparkles: some View {
        let positions: [(CGFloat, CGFloat, CGFloat)] = [
            (-330, -350, 28),
            ( 340, -310, 20),
            (-380,  300, 22),
            ( 360,  330, 26),
            (  80, -430, 16),
            (-140,  420, 18),
            ( 420,   60, 14),
            (-420,  -80, 16)
        ]
        return ZStack {
            ForEach(Array(positions.enumerated()), id: \.offset) { _, pos in
                SparkleShape()
                    .fill(Color.white.opacity(0.70))
                    .frame(width: pos.2, height: pos.2)
                    .shadow(color: nodeColor.opacity(0.9), radius: 6)
                    .offset(x: pos.0, y: pos.1)
            }
        }
        .frame(width: 1024, height: 1024)
    }
}

// MARK: - Вспомогательные формы

/// Четырёхконечная искра (звёздочка)
private struct SparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let cx = rect.midX, cy = rect.midY
        let r = min(rect.width, rect.height) / 2
        let inner = r * 0.35

        var path = Path()
        let points = 4
        for i in 0..<points {
            let outerAngle = Double(i) * .pi / Double(points / 2) - .pi / 2
            let innerAngle = outerAngle + .pi / Double(points)

            let op = CGPoint(x: cx + CGFloat(cos(outerAngle)) * r,
                             y: cy + CGFloat(sin(outerAngle)) * r)
            let ip = CGPoint(x: cx + CGFloat(cos(innerAngle)) * inner,
                             y: cy + CGFloat(sin(innerAngle)) * inner)

            if i == 0 { path.move(to: op) } else { path.addLine(to: op) }
            path.addLine(to: ip)
        }
        path.closeSubpath()
        return path
    }
}

/// Линия от центра 1024×1024-вью наружу под заданным углом
private struct NodeLine: Shape {
    let angle: Double
    let innerRadius: CGFloat
    let outerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let cx = rect.midX, cy = rect.midY
        var p = Path()
        p.move(to: CGPoint(x: cx + CGFloat(cos(angle)) * innerRadius,
                           y: cy + CGFloat(sin(angle)) * innerRadius))
        p.addLine(to: CGPoint(x: cx + CGFloat(cos(angle)) * outerRadius,
                              y: cy + CGFloat(sin(angle)) * outerRadius))
        return p
    }
}

// MARK: - Previews

#Preview("Light 1024×1024") {
    AppIconView()
}

#Preview("Dark 1024×1024") {
    AppIconView()
        .preferredColorScheme(.dark)
}

#Preview("Small 60pt") {
    AppIconView()
        .frame(width: 60, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
}
