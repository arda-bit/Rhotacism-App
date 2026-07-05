import SwiftUI
import Combine

// MARK: - VectorArithmetic for smooth path morphing

struct AnimatableVector: VectorArithmetic {
    var values: [Double]

    static var zero = AnimatableVector(values: Array(repeating: 0, count: 16))

    static func + (l: Self, r: Self) -> Self {
        AnimatableVector(values: zip(l.values, r.values).map(+))
    }
    static func - (l: Self, r: Self) -> Self {
        AnimatableVector(values: zip(l.values, r.values).map(-))
    }
    mutating func scale(by rhs: Double) { values = values.map { $0 * rhs } }
    var magnitudeSquared: Double { values.reduce(0) { $0 + $1 * $1 } }
}

// MARK: - Tongue position enum (exactly 8 points each for smooth interpolation)

enum TonguePos: Equatable {
    case rest, rBunched, openVowel, midVowel, closeVowel, alveolar, velar

    // Normalized (0–1) coordinates; all must have exactly 8 tuples.
    var norm: [(Double, Double)] {
        switch self {
        case .rest:
            return [(0.26,0.84),(0.28,0.76),(0.38,0.73),
                    (0.52,0.72),(0.67,0.72),(0.82,0.74),
                    (0.94,0.78),(1.00,0.84)]
        case .rBunched:
            return [(0.26,0.84),(0.27,0.61),(0.33,0.54),
                    (0.48,0.43),(0.65,0.39),(0.82,0.46),
                    (1.00,0.63),(1.00,0.84)]
        case .openVowel:
            return [(0.26,0.90),(0.30,0.81),(0.42,0.77),
                    (0.56,0.74),(0.72,0.73),(0.86,0.75),
                    (0.95,0.79),(1.00,0.84)]
        case .midVowel:
            return [(0.26,0.84),(0.28,0.73),(0.38,0.67),
                    (0.54,0.63),(0.70,0.62),(0.84,0.65),
                    (0.95,0.72),(1.00,0.84)]
        case .closeVowel:
            return [(0.26,0.84),(0.28,0.62),(0.38,0.53),
                    (0.52,0.49),(0.65,0.52),(0.80,0.60),
                    (0.92,0.70),(1.00,0.84)]
        case .alveolar:
            return [(0.26,0.84),(0.24,0.19),(0.30,0.34),
                    (0.44,0.55),(0.60,0.64),(0.76,0.70),
                    (0.92,0.76),(1.00,0.84)]
        case .velar:
            return [(0.26,0.84),(0.28,0.78),(0.38,0.76),
                    (0.52,0.65),(0.68,0.46),(0.84,0.53),
                    (0.96,0.68),(1.00,0.84)]
        }
    }

    var accentColor: Color {
        switch self {
        case .rBunched:  return .indigo
        case .alveolar:  return .orange
        case .velar:     return .purple
        case .closeVowel:return .teal
        case .openVowel: return Color(red: 0.8, green: 0.4, blue: 0.1)
        case .midVowel:  return .blue
        case .rest:      return .gray
        }
    }
}

// MARK: - Animatable tongue shape

struct TonguePath: Shape {
    // Stored as flat [x0,y0,x1,y1,...] in canvas pixels for VectorArithmetic
    var flat: [Double]

    init(_ pos: TonguePos, w: CGFloat, h: CGFloat) {
        flat = pos.norm.flatMap { [Double($0.0) * Double(w), Double($0.1) * Double(h)] }
    }

    var animatableData: AnimatableVector {
        get { AnimatableVector(values: flat) }
        set { flat = newValue.values }
    }

    func path(in rect: CGRect) -> Path {
        let pts: [CGPoint] = stride(from: 0, to: flat.count - 1, by: 2).map {
            CGPoint(x: flat[$0], y: flat[$0 + 1])
        }
        guard pts.count >= 2 else { return Path() }
        var p = Path()
        p.move(to: pts[0])
        for i in 1..<pts.count {
            let p0 = pts[max(0, i - 2)]
            let p1 = pts[i - 1], p2 = pts[i]
            let p3 = pts[min(pts.count - 1, i + 1)]
            p.addCurve(
                to: p2,
                control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
                control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            )
        }
        p.closeSubpath()
        return p
    }
}

// MARK: - Mouth frame model

struct MouthFrame {
    let phoneme: String      // e.g. "/r/", "/æ/", "·"
    let description: String  // e.g. "Tongue bunched high-back"
    let tongue: TonguePos
    let lipsSealed: Bool     // /p b m/
    let lipsRounded: Bool    // /w/, /oʊ/, /uː/
    let jawOpen: Bool        // open vowels
}

// MARK: - Per-word frame library

enum WordFrameLib {
    static func frames(for word: String) -> [MouthFrame] {
        lib[word.lowercased()] ?? fallback
    }

    private static func f(
        _ ph: String, _ desc: String, _ tongue: TonguePos,
        sealed: Bool = false, rounded: Bool = false, open: Bool = false
    ) -> MouthFrame {
        MouthFrame(phoneme: ph, description: desc, tongue: tongue,
                   lipsSealed: sealed, lipsRounded: rounded, jawOpen: open)
    }

    // swiftlint:disable line_length
    private static let lib: [String: [MouthFrame]] = [
        // ── Initial /r/ ──────────────────────────────────────────────────────
        "red":    [f("·",    "Mouth at rest",             .rest),
                   f("/r/",  "Tongue bunched high-back",  .rBunched),
                   f("/ɛ/",  "Mid front vowel, jaw opens",.midVowel,  open: true),
                   f("/d/",  "Tongue tip to ridge",       .alveolar)],

        "run":    [f("·",    "Mouth at rest",             .rest),
                   f("/r/",  "Tongue bunched high-back",  .rBunched),
                   f("/ʌ/",  "Central vowel, jaw opens",  .midVowel,  open: true),
                   f("/n/",  "Tongue tip to ridge",       .alveolar)],

        "rabbit": [f("·",    "Mouth at rest",             .rest),
                   f("/r/",  "Tongue bunched high-back",  .rBunched),
                   f("/æ/",  "Open front vowel",          .openVowel, open: true),
                   f("/b/",  "Lips seal together",        .rest,      sealed: true)],

        "rain":   [f("·",    "Mouth at rest",             .rest),
                   f("/r/",  "Tongue bunched high-back",  .rBunched),
                   f("/eɪ/", "Front glide vowel",         .midVowel),
                   f("/n/",  "Tongue tip to ridge",       .alveolar)],

        "robot":  [f("·",    "Mouth at rest",             .rest),
                   f("/r/",  "Tongue bunched high-back",  .rBunched),
                   f("/oʊ/", "Back rounded vowel",        .midVowel,  rounded: true),
                   f("/b/",  "Lips seal together",        .rest,      sealed: true)],

        "ring":   [f("·",    "Mouth at rest",             .rest),
                   f("/r/",  "Tongue bunched high-back",  .rBunched),
                   f("/ɪ/",  "High front vowel",          .midVowel),
                   f("/ŋ/",  "Tongue back to soft palate",.velar)],

        "river":  [f("·",    "Mouth at rest",             .rest),
                   f("/r/",  "Tongue bunched high-back",  .rBunched),
                   f("/ɪ/",  "Short high vowel",          .midVowel),
                   f("/r/",  "Rhotic ending — bunch again",.rBunched)],

        "road":   [f("·",    "Mouth at rest",             .rest),
                   f("/r/",  "Tongue bunched high-back",  .rBunched),
                   f("/oʊ/", "Back rounded vowel",        .midVowel,  rounded: true),
                   f("/d/",  "Tongue tip to ridge",       .alveolar)],

        // ── Medial /r/ ───────────────────────────────────────────────────────
        "very":   [f("/v/",  "Lip-teeth fricative",       .rest),
                   f("/ɛ/",  "Mid front vowel",           .midVowel,  open: true),
                   f("/r/",  "Tongue bunched high-back",  .rBunched),
                   f("/i/",  "High front vowel",          .closeVowel)],

        "carry":  [f("/k/",  "Tongue back — velar stop",  .velar),
                   f("/æ/",  "Open front vowel",          .openVowel, open: true),
                   f("/r/",  "Tongue bunched high-back",  .rBunched),
                   f("/i/",  "High front vowel",          .closeVowel)],

        "forest": [f("/f/",  "Lip-teeth fricative",       .rest),
                   f("/ɒ/",  "Open back vowel",           .openVowel, open: true),
                   f("/r/",  "Tongue bunched high-back",  .rBunched),
                   f("/ɪ/",  "Short high vowel",          .midVowel)],

        "orange": [f("/ɒ/",  "Open back vowel",           .openVowel, open: true),
                   f("/r/",  "Tongue bunched high-back",  .rBunched),
                   f("/ɪ/",  "Short high vowel",          .midVowel),
                   f("/n/",  "Tongue tip to ridge",       .alveolar)],

        "around": [f("/ə/",  "Schwa — neutral vowel",     .midVowel),
                   f("/r/",  "Tongue bunched high-back",  .rBunched),
                   f("/aʊ/", "Open glide vowel",          .openVowel, open: true),
                   f("/n/",  "Tongue tip to ridge",       .alveolar)],

        "parrot": [f("/p/",  "Lips seal together",        .rest,      sealed: true),
                   f("/æ/",  "Open front vowel",          .openVowel, open: true),
                   f("/r/",  "Tongue bunched high-back",  .rBunched),
                   f("/ə/",  "Schwa — jaw relaxes",       .midVowel)],

        // ── Final /r/ ────────────────────────────────────────────────────────
        "car":    [f("/k/",  "Tongue back — velar stop",  .velar),
                   f("/ɑː/", "Long open back vowel",      .openVowel, open: true),
                   f("/r/",  "Tongue bunches — rhotic end",.rBunched),
                   f("·",    "Hold the /r/ shape",        .rBunched)],

        "far":    [f("/f/",  "Lip-teeth fricative",       .rest),
                   f("/ɑː/", "Long open back vowel",      .openVowel, open: true),
                   f("/r/",  "Tongue bunches — rhotic end",.rBunched),
                   f("·",    "Hold the /r/ shape",        .rBunched)],

        "floor":  [f("/f/",  "Lip-teeth fricative",       .rest),
                   f("/l/",  "Tongue tip to ridge",       .alveolar),
                   f("/ɔː/", "Mid back rounded vowel",    .midVowel,  rounded: true),
                   f("/r/",  "Tongue bunches — rhotic end",.rBunched)],

        "door":   [f("/d/",  "Tongue tip to ridge",       .alveolar),
                   f("/ɔː/", "Mid back rounded vowel",    .midVowel,  rounded: true),
                   f("/r/",  "Tongue bunches — rhotic end",.rBunched),
                   f("·",    "Hold the /r/ shape",        .rBunched)],

        "four":   [f("/f/",  "Lip-teeth fricative",       .rest),
                   f("/ɔː/", "Mid back rounded vowel",    .midVowel,  rounded: true),
                   f("/r/",  "Tongue bunches — rhotic end",.rBunched),
                   f("·",    "Hold the /r/ shape",        .rBunched)],

        "more":   [f("/m/",  "Lips seal together",        .rest,      sealed: true),
                   f("/ɔː/", "Mid back rounded vowel",    .midVowel,  rounded: true),
                   f("/r/",  "Tongue bunches — rhotic end",.rBunched),
                   f("·",    "Hold the /r/ shape",        .rBunched)],

        // ── Cluster /r/ ──────────────────────────────────────────────────────
        "green":  [f("/g/",  "Tongue back — velar stop",  .velar),
                   f("/r/",  "Tongue bunched high-back",  .rBunched),
                   f("/iː/", "Long high front vowel",     .closeVowel),
                   f("/n/",  "Tongue tip to ridge",       .alveolar)],

        "brown":  [f("/b/",  "Lips seal together",        .rest,      sealed: true),
                   f("/r/",  "Tongue bunched high-back",  .rBunched),
                   f("/aʊ/", "Open glide vowel",          .openVowel, open: true),
                   f("/n/",  "Tongue tip to ridge",       .alveolar)],

        "three":  [f("/θ/",  "Tongue between teeth",      .alveolar),
                   f("/r/",  "Tongue pulls back to bunch", .rBunched),
                   f("/iː/", "Long high front vowel",     .closeVowel),
                   f("·",    "Release",                   .rest)],

        "bring":  [f("/b/",  "Lips seal together",        .rest,      sealed: true),
                   f("/r/",  "Tongue bunched high-back",  .rBunched),
                   f("/ɪ/",  "Short high vowel",          .midVowel),
                   f("/ŋ/",  "Tongue back to soft palate",.velar)],

        "friend": [f("/f/",  "Lip-teeth fricative",       .rest),
                   f("/r/",  "Tongue bunched high-back",  .rBunched),
                   f("/ɛ/",  "Mid front vowel",           .midVowel,  open: true),
                   f("/n/",  "Tongue tip to ridge",       .alveolar)],

        "dress":  [f("/d/",  "Tongue tip to ridge",       .alveolar),
                   f("/r/",  "Tongue bunched high-back",  .rBunched),
                   f("/ɛ/",  "Mid front vowel",           .midVowel,  open: true),
                   f("/s/",  "Tongue near ridge — sibilant",.alveolar)],
    ]
    // swiftlint:enable line_length

    private static let fallback: [MouthFrame] = [
        f("·",   "Mouth at rest",            .rest),
        f("/r/", "Tongue bunched high-back", .rBunched),
        f("·",   "Release",                  .rest),
    ]
}

// MARK: - Sheet

struct MouthDiagramSheet: View {
    let word: String
    let errorType: ErrorType?

    @Environment(\.dismiss) private var dismiss

    private var frames: [MouthFrame] { WordFrameLib.frames(for: word) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    WordAnimationPlayer(word: word, frames: frames)
                        .frame(height: 260)
                        .padding(.horizontal, 4)
                        .padding(.top, 8)

                    correctionCard
                    stepsCard
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("\"\(word.capitalized)\" — Mouth Guide")
                        .font(.headline)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(.indigo)
                }
            }
        }
    }

    private var info: DiagramInfo { DiagramInfo.make(errorType: errorType) }

    @ViewBuilder
    private var correctionCard: some View {
        if errorType != nil {
            HStack(spacing: 14) {
                Image(systemName: info.icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(info.color)
                VStack(alignment: .leading, spacing: 3) {
                    Text(info.title)
                        .font(.subheadline.weight(.semibold))
                    Text(info.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(14)
            .background(info.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(info.color.opacity(0.2), lineWidth: 0.5))
        }
    }

    private var stepsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(errorType == .correct ? "Keep doing this" : "How to produce /r/")
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

// MARK: - Animated player

struct WordAnimationPlayer: View {
    let word: String
    let frames: [MouthFrame]

    @State private var frameIndex: Int = 0
    @State private var tonguePos: TonguePos = .rest
    @State private var isPlaying: Bool = true

    private let ticker = Timer.publish(every: 0.85, on: .main, in: .common).autoconnect()

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height * 0.72   // leave room for controls below
            let cf = frames[frameIndex]
            let isRhotic = (cf.tongue == .rBunched)

            VStack(spacing: 0) {
                // ── Canvas ───────────────────────────────────────────────────
                ZStack {
                    Color(.systemBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14))

                    // Ghost /r/ target (dashed green) — visible when not on /r/ frame
                    if !isRhotic {
                        TonguePath(.rBunched, w: w, h: h)
                            .fill(Color.green.opacity(0.09))
                        TonguePath(.rBunched, w: w, h: h)
                            .stroke(Color.green.opacity(0.45),
                                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                    }

                    // Animated tongue
                    TonguePath(tonguePos, w: w, h: h)
                        .fill(cf.tongue.accentColor.opacity(0.32))
                    TonguePath(tonguePos, w: w, h: h)
                        .stroke(cf.tongue.accentColor.opacity(0.90), lineWidth: 2.4)

                    // Static anatomy drawn on top
                    MouthAnatomyCanvas(w: w, h: h, frame: cf)

                    // Live labels
                    MouthLabelOverlay(w: w, h: h, frame: cf)
                }
                .frame(width: w, height: h)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
                )

                // ── Phoneme label + description ──────────────────────────────
                VStack(spacing: 3) {
                    Text(cf.phoneme)
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(cf.tongue.accentColor)
                        .contentTransition(.numericText())
                        .animation(.spring(duration: 0.3), value: cf.phoneme)

                    Text(cf.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .animation(.easeInOut(duration: 0.2), value: cf.description)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 10)

                // ── Progress dots + play/pause ────────────────────────────────
                HStack(spacing: 0) {
                    // Frame dots
                    HStack(spacing: 6) {
                        ForEach(frames.indices, id: \.self) { i in
                            Capsule()
                                .fill(i == frameIndex
                                      ? frames[i].tongue.accentColor
                                      : Color.primary.opacity(0.18))
                                .frame(width: i == frameIndex ? 18 : 6, height: 6)
                                .animation(.spring(duration: 0.3), value: frameIndex)
                        }
                    }

                    Spacer()

                    // Legend
                    if !isRhotic {
                        HStack(spacing: 4) {
                            HStack(spacing: 2) {
                                ForEach(0..<3, id: \.self) { _ in
                                    Capsule().fill(Color.green.opacity(0.6)).frame(width: 4, height: 2)
                                    Spacer().frame(width: 2)
                                }
                            }
                            .frame(width: 20)
                            Text("target /r/")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    // Play / pause
                    Button {
                        isPlaying.toggle()
                    } label: {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(Color.indigo)
                    }
                }
                .padding(.top, 10)
            }
        }
        .onReceive(ticker) { _ in
            guard isPlaying else { return }
            advance()
        }
        .onAppear {
            tonguePos = frames[0].tongue
        }
    }

    private func advance() {
        let next = (frameIndex + 1) % frames.count
        frameIndex = next
        withAnimation(.easeInOut(duration: 0.40)) {
            tonguePos = frames[next].tongue
        }
    }
}

// MARK: - Anatomy canvas (palate, jaw, lips, teeth, ridge)

struct MouthAnatomyCanvas: View {
    let w: CGFloat
    let h: CGFloat
    let frame: MouthFrame

    var body: some View {
        Canvas { ctx, _ in
            let lipsSealed  = frame.lipsSealed
            let lipsRounded = frame.lipsRounded
            let jawOpen     = frame.jawOpen

            // jaw drop offset for open vowels
            let jawDrop: CGFloat = jawOpen ? h * 0.06 : 0

            // ── Upper palate ─────────────────────────────────────────────
            var palate = Path()
            palate.move(to: p(0.10, 0.50))
            palate.addCurve(to:       p(0.24, 0.16),
                            control1: p(0.11, 0.28), control2: p(0.16, 0.14))
            palate.addCurve(to:       p(1.00, 0.11),
                            control1: p(0.40, 0.18), control2: p(0.72, 0.09))
            ctx.stroke(palate, with: .color(.secondary.opacity(0.50)),
                       style: StrokeStyle(lineWidth: 3.5, lineCap: .round))

            // ── Lower jaw (shifted down for open vowels) ──────────────────
            var jaw = Path()
            jaw.move(to: CGPoint(x: w * 0.10, y: h * 0.50 + jawDrop))
            jaw.addCurve(to:       CGPoint(x: w * 0.24, y: h * 0.84 + jawDrop),
                         control1: CGPoint(x: w * 0.11, y: h * 0.73 + jawDrop),
                         control2: CGPoint(x: w * 0.16, y: h * 0.86 + jawDrop))
            jaw.addLine(to: CGPoint(x: w * 1.00, y: h * 0.84 + jawDrop))
            ctx.stroke(jaw, with: .color(.secondary.opacity(0.50)),
                       style: StrokeStyle(lineWidth: 3.5, lineCap: .round))

            // ── Lips ──────────────────────────────────────────────────────
            if lipsSealed {
                // Sealed: flat horizontal line
                var sealLine = Path()
                sealLine.move(to: p(0.02, 0.50))
                sealLine.addLine(to: p(0.10, 0.50))
                ctx.stroke(sealLine, with: .color(.pink.opacity(0.85)),
                           style: StrokeStyle(lineWidth: 6, lineCap: .round))
            } else {
                // Upper lip
                var ul = Path()
                ul.move(to: p(lipsRounded ? 0.03 : 0.04, 0.36))
                ul.addCurve(to:       p(0.10, 0.50),
                            control1: p(0.03, 0.41), control2: p(0.07, 0.46))
                ctx.stroke(ul, with: .color(.pink.opacity(0.80)),
                           style: StrokeStyle(lineWidth: lipsRounded ? 6 : 5, lineCap: .round))

                // Lower lip
                var ll = Path()
                ll.move(to: CGPoint(x: w * 0.10, y: h * 0.50 + jawDrop))
                ll.addCurve(
                    to:       CGPoint(x: w * (lipsRounded ? 0.03 : 0.04), y: h * (0.64 + jawDrop / h * 0.5)),
                    control1: CGPoint(x: w * 0.07, y: h * (0.54 + jawDrop / h * 0.3)),
                    control2: CGPoint(x: w * 0.03, y: h * (0.60 + jawDrop / h * 0.4))
                )
                ctx.stroke(ll, with: .color(.pink.opacity(0.80)),
                           style: StrokeStyle(lineWidth: lipsRounded ? 6 : 5, lineCap: .round))
            }

            // ── Upper teeth ───────────────────────────────────────────────
            for i in 0..<2 {
                let tx = w * (0.12 + Double(i) * 0.048)
                let tooth = Path(roundedRect: CGRect(x: tx, y: h * 0.22,
                                                     width: w * 0.038, height: h * 0.26),
                                 cornerRadius: 2)
                ctx.fill(tooth, with: .color(.white))
                ctx.stroke(tooth, with: .color(.gray.opacity(0.22)), lineWidth: 0.8)
            }

            // ── Alveolar ridge dot ────────────────────────────────────────
            ctx.fill(
                Path(ellipseIn: CGRect(x: w*0.235, y: h*0.155, width: 10, height: 10)),
                with: .color(.orange.opacity(0.80))
            )
        }
        .frame(width: w, height: h)
    }

    private func p(_ rx: Double, _ ry: Double) -> CGPoint {
        CGPoint(x: w * rx, y: h * ry)
    }
}

// MARK: - Label overlay

struct MouthLabelOverlay: View {
    let w: CGFloat
    let h: CGFloat
    let frame: MouthFrame

    var body: some View {
        ZStack {
            // "Ridge" label
            Text("Ridge ▲")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color.orange)
                .position(x: w * 0.35, y: h * 0.07)

            // "Lip" label
            Text("Lip")
                .font(.system(size: 9))
                .foregroundStyle(Color.pink.opacity(0.9))
                .position(x: w * 0.04, y: h * 0.50)

            // "Sealed" banner
            if frame.lipsSealed {
                Text("LIPS SEALED")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.pink, in: Capsule())
                    .position(x: w * 0.15, y: h * 0.50)
            }

            // Rounded lips indicator
            if frame.lipsRounded {
                Text("lips rounded ●")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Color.teal)
                    .position(x: w * 0.15, y: h * 0.22)
            }

            // Contact dot for alveolar frames
            if frame.tongue == .alveolar {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 9, height: 9)
                    .position(x: w * 0.24, y: h * 0.20)
            }
        }
        .frame(width: w, height: h)
    }
}

// MARK: - Error-specific text info

struct DiagramInfo {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let steps: [String]

    static func make(errorType: ErrorType?) -> DiagramInfo {
        switch errorType {
        case .correct:
            return DiagramInfo(
                title: "Correct /r/", subtitle: "Great tongue position — keep it up!",
                icon: "checkmark.circle.fill", color: .green,
                steps: [
                    "Keep your tongue body bunched and high toward the back of your mouth.",
                    "Tongue tip floats freely — it should not touch the palate.",
                    "Lips stay neutral and slightly spread."
                ]
            )
        case .wSubstitution:
            return DiagramInfo(
                title: "Lip rounding detected", subtitle: "Lips are rounding like /w/ instead of staying flat.",
                icon: "exclamationmark.circle.fill", color: .red,
                steps: [
                    "Spread your lips slightly — imagine a small horizontal slit.",
                    "Raise the BACK of your tongue, not the front.",
                    "Tongue tip should float mid-mouth, not curl down."
                ]
            )
        case .lSubstitution:
            return DiagramInfo(
                title: "Tongue touching palate", subtitle: "Tongue tip hitting the alveolar ridge — sounds like /l/.",
                icon: "exclamationmark.circle.fill", color: .orange,
                steps: [
                    "Pull your tongue tip away from the ridge behind your upper teeth.",
                    "Raise the BACK of your tongue toward the soft palate instead.",
                    "Tongue tip should hover freely, not touch anything."
                ]
            )
        case .partial:
            return DiagramInfo(
                title: "Partial /r/", subtitle: "Close — tongue is not raised high enough.",
                icon: "exclamationmark.triangle.fill", color: .yellow,
                steps: [
                    "Push the back of your tongue a little higher.",
                    "Hold the tongue shape through the full vowel sound.",
                    "Try sustaining 'rrrr' for two full seconds to build muscle memory."
                ]
            )
        default:
            return DiagramInfo(
                title: "Target /r/ position", subtitle: "Watch the animation to learn the correct mouth shape.",
                icon: "mouth.fill", color: .indigo,
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
    MouthDiagramSheet(word: "red", errorType: .wSubstitution)
}
