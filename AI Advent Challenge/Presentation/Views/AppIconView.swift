import SwiftUI

// MARK: - App Icon View
// Предназначена для предпросмотра в Xcode Canvas.
// PNG генерируется скриптом /tmp/gen_icon.py — дизайн идентичен.

struct AppIconView: View {

    // MARK: - Цветовая схема (очень светлая)

    private let bgTop     = Color.white
    private let bgBottom  = Color(red: 0.80, green: 0.66, blue: 1.00)   // светлая лаванда
    private let nodeColor = Color(red: 0.42, green: 0.15, blue: 0.82)   // среднее индиго
    private let textColor = Color(red: 0.32, green: 0.08, blue: 0.68)   // тёмное индиго

    // MARK: - Body

    var body: some View {
        ZStack {
            background
            subtleGrid
            neuralRings
            circuitNodes
            centralOrb
            aiText
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
            let lineColor = Color(red: 0.40, green: 0.15, blue: 0.80).opacity(0.06)
            var x: CGFloat = 0
            while x <= size.width {
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(path, with: .color(lineColor), lineWidth: 1)
                x += step
            }
            var y: CGFloat = 0
            while y <= size.height {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                ctx.stroke(path, with: .color(lineColor), lineWidth: 1)
                y += step
            }
        }
    }

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

    private var circuitNodes: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { i in
                let angle = Double(i) * .pi / 4
                let innerR: CGFloat = 240
                let outerR: CGFloat = 340

                NodeLine(angle: angle, innerRadius: innerR, outerRadius: outerR)
                    .stroke(nodeColor.opacity(0.18), lineWidth: 1.5)

                Circle()
                    .fill(nodeColor.opacity(0.55))
                    .frame(width: 16, height: 16)
                    .shadow(color: nodeColor.opacity(0.3), radius: 6)
                    .offset(
                        x: CGFloat(cos(angle)) * outerR,
                        y: CGFloat(sin(angle)) * outerR
                    )
            }
        }
        .frame(width: 1024, height: 1024)
    }

    private var centralOrb: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [.white, Color(red: 0.95, green: 0.91, blue: 1.00)],
                    center: .center,
                    startRadius: 0,
                    endRadius: 220
                )
            )
            .frame(width: 460, height: 460)
            .shadow(color: nodeColor.opacity(0.22), radius: 50)
            .shadow(color: nodeColor.opacity(0.12), radius: 20)
    }

    private var aiText: some View {
        Text("AI")
            .font(.system(size: 290, weight: .bold, design: .rounded))
            .foregroundStyle(
                LinearGradient(
                    colors: [textColor, nodeColor],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .shadow(color: nodeColor.opacity(0.20), radius: 10)
    }

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
                    .fill(nodeColor.opacity(0.35))
                    .frame(width: pos.2, height: pos.2)
                    .offset(x: pos.0, y: pos.1)
            }
        }
        .frame(width: 1024, height: 1024)
    }
}

// MARK: - Вспомогательные формы

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

#Preview("1024×1024") {
    AppIconView()
}

#Preview("Small 60pt") {
    AppIconView()
        .frame(width: 60, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
}
