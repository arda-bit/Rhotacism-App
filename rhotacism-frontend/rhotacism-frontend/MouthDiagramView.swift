import SwiftUI

// MARK: - Sheet entry point

struct MouthDiagramSheet: View {
    let errorType: ErrorType?
    let score: Double
    @Environment(\.dismiss) private var dismiss

    private var info: DiagramInfo { DiagramInfo.make(errorType: errorType, score: score) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    statusCard
                    diagramCard
                    stepsCard
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Mouth Position")
                        .font(.headline)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.indigo)
                }
            }
        }
    }

    private var statusCard: some View {
        HStack(spacing: 14) {
            Image(systemName: info.icon)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(info.color)
            VStack(alignment: .leading, spacing: 3) {
                Text(info.title)
                    .font(.title3.bold())
                Text(info.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(16)
        .background(info.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(info.color.opacity(0.2), lineWidth: 0.5))
        .padding(.top, 8)
    }

    private var diagramCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Side cross-section view", systemImage: "eye")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)

            MouthDiagramCanvas(errorType: errorType)
                .frame(height: 190)
                .background(
                    Color(.systemBackground),
                    in: RoundedRectangle(cornerRadius: 10)
                )
                .padding(.horizontal, 2)

            HStack(spacing: 20) {
                DiagramLegend(color: info.color, label: "Your tongue", dashed: false)
                if errorType != .correct {
                    DiagramLegend(color: .green, label: "Target /r/", dashed: true)
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
    }

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(errorType == .correct ? "Keep doing this" : "How to correct it")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            ForEach(info.steps.indices, id: \.self) { i in
                HStack(alignment: .top, spacing: 10) {
                    Text("\(i + 1)")
                        .font(.caption.weight(.bold))
                        .frame(width: 22, height: 22)
                        .background(Color.indigo.opacity(0.12), in: Circle())
                        .foregroundStyle(.indigo)
                    Text(info.steps[i])
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
    }
}

// MARK: - Canvas

struct MouthDiagramCanvas: View {
    let errorType: ErrorType?

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                // Ghost ideal position (dashed green) — shown when not already correct
                if errorType != .correct {
                    TonguePath(pts: TonguePoints.correct.scaled(w: w, h: h))
                        .fill(Color.green.opacity(0.10))
                    TonguePath(pts: TonguePoints.correct.scaled(w: w, h: h))
                        .stroke(Color.green.opacity(0.50),
                                style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                }
                // Current tongue
                TonguePath(pts: TonguePoints.from(errorType).scaled(w: w, h: h))
                    .fill(tongueColor.opacity(0.38))
                TonguePath(pts: TonguePoints.from(errorType).scaled(w: w, h: h))
                    .stroke(tongueColor.opacity(0.85), lineWidth: 2.2)
                // Structural anatomy on top
                MouthStructureView(w: w, h: h)
                // Text labels
                DiagramLabels(w: w, h: h, errorType: errorType)
            }
        }
    }

    private var tongueColor: Color {
        switch errorType {
        case .correct:       return .green
        case .wSubstitution: return .red
        case .lSubstitution: return .orange
        case .partial:       return .yellow
        default:             return .indigo
        }
    }
}

// MARK: - Tongue path shape

struct TonguePath: Shape {
    let pts: [CGPoint]

    func path(in rect: CGRect) -> Path {
        guard pts.count >= 2 else { return Path() }
        var path = Path()
        path.move(to: pts[0])
        for i in 1..<pts.count {
            let prev2 = pts[max(0, i - 2)]
            let prev  = pts[i - 1]
            let curr  = pts[i]
            let next  = pts[min(pts.count - 1, i + 1)]
            let cp1   = CGPoint(x: prev.x + (curr.x - prev2.x) / 6,
                                y: prev.y + (curr.y - prev2.y) / 6)
            let cp2   = CGPoint(x: curr.x - (next.x - prev.x) / 6,
                                y: curr.y - (next.y - prev.y) / 6)
            path.addCurve(to: curr, control1: cp1, control2: cp2)
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Tongue point sets (normalised 0…1)

struct TonguePoints {
    let raw: [(Double, Double)]

    func scaled(w: CGFloat, h: CGFloat) -> [CGPoint] {
        raw.map { CGPoint(x: w * $0.0, y: h * $0.1) }
    }

    static func from(_ errorType: ErrorType?) -> TonguePoints {
        switch errorType {
        case .correct:       return correct
        case .wSubstitution: return wSubstitution
        case .lSubstitution: return lSubstitution
        default:             return partial
        }
    }

    // Bunched /r/: tongue body raised high in back, tip floating mid-height
    static let correct = TonguePoints(raw: [
        (0.26, 0.84),   // front base at jaw
        (0.27, 0.61),   // tip floating (NOT touching palate)
        (0.33, 0.54),
        (0.48, 0.43),   // body rising
        (0.65, 0.39),   // peak of tongue body (bunched high-back)
        (0.82, 0.46),   // back slope
        (1.00, 0.63),   // back of tongue
        (1.00, 0.84),   // back at jaw
    ])

    // /w/ substitution: tongue flat and low, lips rounded
    static let wSubstitution = TonguePoints(raw: [
        (0.26, 0.84),
        (0.28, 0.75),   // tip very low
        (0.40, 0.70),
        (0.58, 0.68),   // barely elevated — nearly flat
        (0.76, 0.70),
        (1.00, 0.76),
        (1.00, 0.84),
    ])

    // /l/ substitution: tip contacts alveolar ridge (front-high), body lower
    static let lSubstitution = TonguePoints(raw: [
        (0.26, 0.84),   // front base
        (0.24, 0.19),   // TIP contacting alveolar ridge
        (0.30, 0.32),   // behind tip, top surface
        (0.44, 0.54),
        (0.60, 0.63),
        (0.78, 0.70),
        (1.00, 0.76),
        (1.00, 0.84),
    ])

    // Partial: tongue raised but not enough — mid-height body
    static let partial = TonguePoints(raw: [
        (0.26, 0.84),
        (0.28, 0.68),   // tip slightly up but not high
        (0.36, 0.61),
        (0.52, 0.54),
        (0.68, 0.52),   // body somewhat elevated
        (0.84, 0.57),
        (1.00, 0.70),
        (1.00, 0.84),
    ])
}

// MARK: - Anatomical structure (palate, jaw, lips, teeth, ridge)

struct MouthStructureView: View {
    let w: CGFloat
    let h: CGFloat

    var body: some View {
        Canvas { ctx, _ in
            // ── Upper palate ──────────────────────────────────────────────────
            var palate = Path()
            palate.move(to: p(0.10, 0.50))
            palate.addCurve(to:       p(0.24, 0.16),
                            control1: p(0.11, 0.27),
                            control2: p(0.16, 0.14))
            palate.addCurve(to:       p(1.00, 0.11),
                            control1: p(0.40, 0.18),
                            control2: p(0.72, 0.09))
            ctx.stroke(palate, with: .color(.secondary.opacity(0.55)),
                       style: StrokeStyle(lineWidth: 3.5, lineCap: .round))

            // ── Lower jaw ─────────────────────────────────────────────────────
            var jaw = Path()
            jaw.move(to: p(0.10, 0.50))
            jaw.addCurve(to:       p(0.24, 0.84),
                         control1: p(0.11, 0.73),
                         control2: p(0.16, 0.86))
            jaw.addLine(to: p(1.00, 0.84))
            ctx.stroke(jaw, with: .color(.secondary.opacity(0.55)),
                       style: StrokeStyle(lineWidth: 3.5, lineCap: .round))

            // ── Upper lip ─────────────────────────────────────────────────────
            var upperLip = Path()
            upperLip.move(to: p(0.04, 0.34))
            upperLip.addCurve(to:       p(0.10, 0.50),
                               control1: p(0.03, 0.40),
                               control2: p(0.07, 0.46))
            ctx.stroke(upperLip, with: .color(.pink.opacity(0.75)),
                       style: StrokeStyle(lineWidth: 5, lineCap: .round))

            // ── Lower lip ─────────────────────────────────────────────────────
            var lowerLip = Path()
            lowerLip.move(to: p(0.10, 0.50))
            lowerLip.addCurve(to:       p(0.04, 0.66),
                               control1: p(0.07, 0.54),
                               control2: p(0.03, 0.60))
            ctx.stroke(lowerLip, with: .color(.pink.opacity(0.75)),
                       style: StrokeStyle(lineWidth: 5, lineCap: .round))

            // ── Upper teeth (2 blocks) ────────────────────────────────────────
            for i in 0..<2 {
                let tx = w * (0.12 + Double(i) * 0.048)
                let toothRect = CGRect(x: tx, y: h * 0.22, width: w * 0.038, height: h * 0.26)
                var tooth = Path(roundedRect: toothRect, cornerRadius: 2)
                ctx.fill(tooth, with: .color(.white))
                ctx.stroke(tooth, with: .color(.gray.opacity(0.25)), lineWidth: 0.8)
            }

            // ── Alveolar ridge dot ────────────────────────────────────────────
            ctx.fill(
                Path(ellipseIn: CGRect(x: w*0.24 - 5, y: h*0.16 - 5, width: 10, height: 10)),
                with: .color(.orange.opacity(0.85))
            )
        }
        .frame(width: w, height: h)
    }

    private func p(_ rx: Double, _ ry: Double) -> CGPoint {
        CGPoint(x: w * rx, y: h * ry)
    }
}

// MARK: - Text labels overlay

struct DiagramLabels: View {
    let w: CGFloat
    let h: CGFloat
    let errorType: ErrorType?

    var body: some View {
        ZStack {
            // Alveolar ridge label
            Text("Ridge ▲")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.orange)
                .position(x: w * 0.34, y: h * 0.07)

            // Lip label
            Text("Lip")
                .font(.system(size: 9))
                .foregroundStyle(Color.pink.opacity(0.9))
                .position(x: w * 0.04, y: h * 0.50)

            // Contact marker for L-substitution
            if errorType == .lSubstitution {
                Circle()
                    .fill(Color.red)
                    .frame(width: 9, height: 9)
                    .position(x: w * 0.24, y: h * 0.20)
                Text("Contact!")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.red)
                    .position(x: w * 0.42, y: h * 0.13)
            }

            // Rounded lip indicator for W-substitution
            if errorType == .wSubstitution {
                Text("Lips rounding →")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.red.opacity(0.8))
                    .position(x: w * 0.16, y: h * 0.20)
            }
        }
        .frame(width: w, height: h)
    }
}

// MARK: - Legend row

struct DiagramLegend: View {
    let color: Color
    let label: String
    let dashed: Bool

    var body: some View {
        HStack(spacing: 6) {
            if dashed {
                HStack(spacing: 2) {
                    ForEach(0..<4, id: \.self) { _ in
                        Capsule().fill(color).frame(width: 5, height: 2)
                        Color.clear.frame(width: 2, height: 2)
                    }
                }
                .frame(width: 28)
            } else {
                Capsule().fill(color).frame(width: 28, height: 3)
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Data model

struct DiagramInfo {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let steps: [String]

    static func make(errorType: ErrorType?, score: Double) -> DiagramInfo {
        switch errorType {
        case .correct:
            return DiagramInfo(
                title: "Correct /r/ position",
                subtitle: "Great work — your tongue is in the right place.",
                icon: "checkmark.circle.fill",
                color: .green,
                steps: [
                    "Keep your tongue body bunched high toward the back of your mouth.",
                    "Your tongue tip floats freely — it doesn't touch the palate.",
                    "Lips stay neutral and slightly spread, not rounded."
                ]
            )
        case .wSubstitution:
            return DiagramInfo(
                title: "Lips rounding like /w/",
                subtitle: "Your lips are rounding instead of staying flat.",
                icon: "exclamationmark.circle.fill",
                color: .red,
                steps: [
                    "Spread your lips slightly — imagine a small horizontal slit.",
                    "Raise the BACK of your tongue toward your soft palate, not the front.",
                    "Keep your tongue tip floating mid-mouth — not curling down."
                ]
            )
        case .lSubstitution:
            return DiagramInfo(
                title: "Tongue tip touching palate",
                subtitle: "Your tongue tip is hitting the alveolar ridge, making /l/.",
                icon: "exclamationmark.circle.fill",
                color: .orange,
                steps: [
                    "Pull your tongue tip away from the ridge behind your upper teeth.",
                    "Raise the BACK of your tongue toward the soft palate instead.",
                    "Your tongue tip should hover — not touch anything."
                ]
            )
        case .partial:
            return DiagramInfo(
                title: "Partial /r/",
                subtitle: "You're close — hold the position a little longer.",
                icon: "exclamationmark.triangle.fill",
                color: .yellow,
                steps: [
                    "Push the back of your tongue slightly higher.",
                    "Sustain the tongue shape through the full vowel that follows.",
                    "Try holding 'rrrr' for two full seconds to build muscle memory."
                ]
            )
        default:
            return DiagramInfo(
                title: "Target /r/ position",
                subtitle: "Here's where your tongue should be for a clear /r/.",
                icon: "mouth.fill",
                color: .indigo,
                steps: [
                    "Raise the back of your tongue toward your soft palate.",
                    "Let your tongue tip float freely — don't touch anything.",
                    "Keep your lips neutral and slightly spread."
                ]
            )
        }
    }
}

#Preview {
    MouthDiagramSheet(errorType: .wSubstitution, score: 0.2)
}
