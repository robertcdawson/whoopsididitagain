import SwiftUI

extension Font {
    /// Bundled variable fonts work offline and retain Dynamic Type scaling.
    static func journal(_ style: Font.TextStyle = .body, weight: Font.Weight = .regular) -> Font {
        let size: CGFloat
        switch style {
        case .largeTitle: size = 34
        case .title: size = 28
        case .title2: size = 24
        case .title3: size = 20
        case .headline: size = 19
        case .callout: size = 18
        case .subheadline: size = 17
        case .footnote: size = 15
        case .caption: size = 14
        case .caption2: size = 12
        default: size = 19
        }
        return .custom("Literata-Regular", size: size, relativeTo: style).weight(weight)
    }
}

/// A root journal page. Native safe areas remain outside the artwork's content area;
/// unlike the static mockups, content can grow and scroll at accessibility sizes.
struct JournalPage<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @AppStorage("journalLeftHanded") private var leftHanded = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headerLayout {
                        Text(title.lowercased())
                        if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                        Text(Date.now, format: .dateTime.month(.abbreviated).day())
                            .textCase(.lowercase)
                    }
                    .accessibilityAddTraits(.isHeader)
                    content
                }
                .frame(
                    maxWidth: .infinity, minHeight: max(0, geometry.size.height - 32),
                    alignment: .topLeading
                )
                .padding(.leading, leftHanded ? 24 : 56)
                .padding(.trailing, leftHanded ? 56 : 24)
                .padding(.vertical, 16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .scrollDismissesKeyboard(.interactively)
        }
        .background { JournalPaperBackground() }
        .font(.journal())
        .foregroundStyle(Color.journalInk)
        .buttonStyle(JournalLinkButtonStyle())
        .textFieldStyle(JournalTextFieldStyle())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("journal-page-\(title.lowercased())")
    }

    private var headerLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
    }
}

struct JournalRule: View {
    var body: some View {
        SquiggleDivider()
            .stroke(Color.journalInk.opacity(0.25), lineWidth: 1.5)
            .frame(height: 10)
            .accessibilityHidden(true)
    }
}

/// Chips wrap at their measured Dynamic Type width instead of stretching into columns.
struct JournalChipLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangement(width: proposal.width ?? 320, subviews: subviews).size
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        let result = arrangement(width: bounds.width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let frame = result.frames[index]
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrangement(width: CGFloat, subviews: Subviews) -> (size: CGSize, frames: [CGRect])
    {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0 && x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), frames)
    }
}

struct JournalSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            if !title.isEmpty {
                Text(title.lowercased())
                    .font(.journal(.subheadline))
                    .foregroundStyle(Color.journalInk.opacity(0.7))
                    .accessibilityAddTraits(.isHeader)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct JournalPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.journal(.title3, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(8)
            .foregroundStyle(Color.journalPaper)
            .tint(Color.journalPaper)
            .background(
                Color.journalInk.opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.8 : 1),
                in: RoundedRectangle(cornerRadius: 14))
    }
}

/// An action must look interactive even before the user taps it.
struct JournalLinkButtonStyle: ButtonStyle {
    var fillsWidth = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .underline()
            .foregroundStyle(configuration.role == .destructive ? Color.journalRedPen : .journalInk)
            .frame(
                minWidth: 44, maxWidth: fillsWidth ? .infinity : nil, minHeight: 44,
                alignment: .leading
            )
            .contentShape(Rectangle())
            .opacity(!isEnabled ? 0.45 : configuration.isPressed ? 0.65 : 1)
    }
}

private struct JournalFieldFocusedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var journalFieldFocused: Bool {
        get { self[JournalFieldFocusedKey.self] }
        set { self[JournalFieldFocusedKey.self] = newValue }
    }
}

private struct JournalInputBorder: ViewModifier {
    @Environment(\.journalFieldFocused) private var isFocused
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .background(Color.journalPaper, in: RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        Color.journalInk.opacity(isFocused ? 0.9 : 0.55),
                        lineWidth: isFocused ? 2 : 1
                    )
                    .allowsHitTesting(false)
            }
            .opacity(isEnabled ? 1 : 0.5)
    }
}

struct JournalTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration.textFieldStyle(.plain).modifier(JournalInputBorder())
    }
}

/// Native Form/List behavior with journal rows, not white inset-grouped cards.
struct JournalForm<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Form {
            Group { content }.listRowBackground(Color.clear)
        }
        .journalForm()
    }
}

struct JournalList<Content: View>: View {
    let showsMarginRule: Bool
    let content: Content

    init(showsMarginRule: Bool = false, @ViewBuilder content: () -> Content) {
        self.showsMarginRule = showsMarginRule
        self.content = content()
    }

    var body: some View {
        List {
            Group { content }.listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .journalForm(showsMarginRule: showsMarginRule)
    }
}

struct JournalTapeCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .padding(.top, 4)
            .background {
                Color(red: 0.994, green: 0.987, blue: 0.965)
                    .shadow(color: .journalDot.opacity(0.15), radius: 6, x: 2, y: 4)
            }
            .overlay(Rectangle().stroke(Color.journalDot.opacity(0.25), lineWidth: 1))
            .overlay(alignment: .top) {
                Rectangle().fill(Color.journalTape.opacity(0.75))
                    .frame(width: 84, height: 20)
                    .rotationEffect(.degrees(1.5)).offset(y: -9)
                    .accessibilityHidden(true)
            }
            .padding(.top, 9)
    }
}

/// The mockup's rounded, pen-drawn tab outline, not a rasterized screenshot.
struct JournalTabOutline: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 7, y: 4))
        path.addCurve(
            to: CGPoint(x: 7, y: rect.height - 4),
            control1: CGPoint(x: 1, y: 2), control2: CGPoint(x: 1, y: rect.height - 2))
        path.addLine(to: CGPoint(x: rect.width - 7, y: rect.height - 4))
        path.addCurve(
            to: CGPoint(x: rect.width - 7, y: 4),
            control1: CGPoint(x: rect.width - 1, y: rect.height - 2),
            control2: CGPoint(x: rect.width - 1, y: 2))
        path.closeSubpath()
        return path
    }
}

extension View {
    func journalInput() -> some View {
        modifier(JournalInputBorder())
    }

    /// Keep form controls native while applying the journal's paper and typography.
    func journalForm(showsMarginRule: Bool = false) -> some View {
        self.scrollContentBackground(.hidden)
            .background { JournalPaperBackground(showsMarginRule: showsMarginRule) }
            .font(.journal(.subheadline))
            .foregroundStyle(Color.journalInk)
            .tint(.journalInk)
            .buttonStyle(JournalLinkButtonStyle(fillsWidth: true))
            .textFieldStyle(JournalTextFieldStyle())
            .toolbarBackground(Color.journalPaper, for: .navigationBar)
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// Presentation only: these bands explain existing scores without changing assessment rules.
struct JournalReadinessMetric: Identifiable, Equatable {
    enum Status: Equatable {
        case positive, caution, low, restricted, unavailable

        var symbol: String {
            switch self {
            case .positive: "checkmark.circle"
            case .caution: "exclamationmark.triangle"
            case .low: "arrow.down.circle"
            case .restricted: "hand.raised"
            case .unavailable: "questionmark.circle"
            }
        }

        var label: String {
            switch self {
            case .positive: "Good"
            case .caution: "Caution"
            case .low: "Low"
            case .restricted: "Restricted"
            case .unavailable: "Unavailable"
            }
        }

        var color: Color {
            switch self {
            case .positive: .journalGreenText
            case .caution: .journalAmberText
            case .low, .restricted: .journalRedPen
            case .unavailable: .journalInk.opacity(0.7)
            }
        }
    }

    let title: String
    let value: String
    let status: Status
    var id: String { title }

    static func rows(for assessment: ReadinessAssessment) -> [Self] {
        let hasRestriction = assessment.reasons.contains { $0.direction == .restriction }
        let tissueCaution = assessment.reasons.contains {
            $0.direction == .caution
                && ($0.code.hasPrefix("restriction.")
                    || ["check-in.movement-pain", "check-in.tissue-signals"].contains($0.code))
        }
        let tissueStatus: Status
        if hasRestriction {
            tissueStatus = .restricted
        } else if let score = assessment.tissueScore {
            tissueStatus = score < 40 ? .low : tissueCaution ? .caution : .positive
        } else {
            tissueStatus = .unavailable
        }
        return [
            scoreRow("Body", score: assessment.systemicScore, low: 40, good: 65),
            scoreRow("Sleep", score: assessment.sleepScore, low: 70, good: 90),
            Self(
                title: "Tissue",
                value: hasRestriction ? "Restricted" : scoreText(assessment.tissueScore),
                status: tissueStatus),
        ]
    }

    private static func scoreRow(_ title: String, score: Int?, low: Int, good: Int) -> Self {
        Self(
            title: title, value: scoreText(score),
            status: score.map { $0 < low ? .low : $0 < good ? .caution : .positive } ?? .unavailable
        )
    }

    private static func scoreText(_ score: Int?) -> String {
        score.map { "\($0)/100" } ?? "Unavailable"
    }
}

struct JournalReadinessRows: View {
    let assessment: ReadinessAssessment
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(JournalReadinessMetric.rows(for: assessment)) { metric in
                let layout =
                    dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
                layout {
                    Text(metric.title)
                    if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                    Label(metric.value, systemImage: metric.status.symbol)
                        .foregroundStyle(metric.status.color)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(metric.title)
                .accessibilityValue(
                    metric.value == metric.status.label
                        ? metric.value : "\(metric.value), \(metric.status.label)"
                )
                .accessibilityIdentifier("readiness-\(metric.title.lowercased())")
            }
        }
        .font(.journal(.subheadline))
    }
}

/// Field-journal visual tokens from docs/DESIGN.md, converted from the mockups'
/// oklch values to sRGB. Shared by the native journal and its entry flows.
extension Color {
    static let journalPaper = Color(red: 0.978, green: 0.959, blue: 0.921)
    static let journalInk = Color(red: 0.094, green: 0.202, blue: 0.336)
    static let journalRedPen = Color(red: 0.741, green: 0.255, blue: 0.246)
    static let journalGreen = Color(red: 0.161, green: 0.525, blue: 0.276)
    static let journalAmber = Color(red: 0.679, green: 0.446, blue: 0.111)
    // Small status text needs more contrast than decorative marks on the paper.
    static let journalGreenText = Color(red: 0.12, green: 0.48, blue: 0.24)
    static let journalAmberText = Color(red: 0.60, green: 0.38, blue: 0.075)
    static let journalDot = Color(red: 0.425, green: 0.383, blue: 0.314)
    static let journalTape = Color(red: 0.893, green: 0.846, blue: 0.671)
    static let journalCaptureBackground = Color(red: 0.078, green: 0.067, blue: 0.051)
    static let journalCaptureGold = Color(red: 0.941, green: 0.788, blue: 0.416)
}

/// Paper background with the 18-point dot grid and optional red margin rule.
struct JournalPaperBackground: View {
    var showsMarginRule = true
    @AppStorage("journalLeftHanded") private var leftHanded = false

    var body: some View {
        ZStack(alignment: .leading) {
            Color.journalPaper
            Canvas { context, size in
                let spacing: CGFloat = 18
                var y = spacing / 2
                while y < size.height {
                    var x = spacing / 2
                    while x < size.width {
                        context.fill(
                            Path(
                                ellipseIn: CGRect(x: x - 1.4, y: y - 1.4, width: 2.8, height: 2.8)
                            ),
                            with: .color(.journalDot.opacity(0.16))
                        )
                        x += spacing
                    }
                    y += spacing
                }
            }
            if showsMarginRule {
                Canvas { context, size in
                    let marginX = leftHanded ? size.width - 40 : 40
                    let holeX = leftHanded ? size.width - 19 : 19
                    var rule = Path()
                    rule.move(to: CGPoint(x: marginX, y: 0))
                    rule.addLine(to: CGPoint(x: marginX, y: size.height))
                    context.stroke(rule, with: .color(.journalRedPen.opacity(0.35)), lineWidth: 1.5)
                    for y in stride(from: CGFloat(136), to: size.height, by: 280) {
                        let hole = Path(
                            ellipseIn: CGRect(x: holeX - 8, y: y - 8, width: 16, height: 16))
                        context.fill(hole, with: .color(.journalPaper))
                        context.stroke(hole, with: .color(.journalDot.opacity(0.4)), lineWidth: 1.5)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The slightly hand-drawn check stroke used for completed and cleared states.
struct DrawnCheckmark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        path.move(to: CGPoint(x: 0.17 * width, y: 0.56 * height))
        path.addCurve(
            to: CGPoint(x: 0.42 * width, y: 0.83 * height),
            control1: CGPoint(x: 0.25 * width, y: 0.66 * height),
            control2: CGPoint(x: 0.35 * width, y: 0.75 * height)
        )
        path.addCurve(
            to: CGPoint(x: 0.88 * width, y: 0.17 * height),
            control1: CGPoint(x: 0.54 * width, y: 0.62 * height),
            control2: CGPoint(x: 0.71 * width, y: 0.33 * height)
        )
        return path
    }
}

struct DrawnCheckmarkView: View {
    var color = Color.journalGreen
    var size: CGFloat = 20

    var body: some View {
        DrawnCheckmark()
            .stroke(color, style: StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size * 0.9)
            .accessibilityHidden(true)
    }
}

/// The slightly irregular hand-drawn checkbox square from the docket mockup.
struct DrawnCheckboxShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        path.move(to: CGPoint(x: 0.17 * width, y: 0.21 * height))
        path.addCurve(
            to: CGPoint(x: 0.17 * width, y: 0.83 * height),
            control1: CGPoint(x: 0.12 * width, y: 0.42 * height),
            control2: CGPoint(x: 0.12 * width, y: 0.63 * height)
        )
        path.addLine(to: CGPoint(x: 0.83 * width, y: 0.87 * height))
        path.addCurve(
            to: CGPoint(x: 0.83 * width, y: 0.17 * height),
            control1: CGPoint(x: 0.88 * width, y: 0.63 * height),
            control2: CGPoint(x: 0.88 * width, y: 0.38 * height)
        )
        path.closeSubpath()
        return path
    }
}

/// Checkbox with the drawn-stroke completion animation: the green check draws
/// itself in and overflows the box slightly, like a pen mark.
struct DrawnCheckbox: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var isChecked: Bool
    var size: CGFloat = 24

    var body: some View {
        ZStack {
            DrawnCheckboxShape()
                .stroke(Color.journalInk, lineWidth: 2)
            DrawnCheckmark()
                .trim(from: 0, to: isChecked ? 1 : 0)
                .stroke(
                    Color.journalGreen,
                    style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                )
                .scaleEffect(1.35)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: isChecked)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Rounded-full bordered chip; the selected chip fills with ink (or the provided
/// fill) and flips to paper-colored text. Tap targets stay at least 44 points tall.
struct JournalChip: View {
    let label: String
    var isSelected = false
    var selectedFill = Color.journalInk
    var isProminent = false
    var accessibilityID: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.journal(.subheadline))
                .fontWeight(isProminent ? .bold : .regular)
                .foregroundStyle(isSelected ? Color.journalPaper : Color.journalInk)
                .padding(.horizontal, 13)
                .padding(.vertical, 6)
                .background(Capsule().fill(isSelected ? selectedFill : Color.clear))
                .overlay(
                    Capsule().strokeBorder(
                        isSelected
                            ? selectedFill
                            : Color.journalInk.opacity(isProminent ? 1 : 0.4),
                        lineWidth: isSelected || isProminent ? 2 : 1.5
                    )
                )
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityID ?? "chip-\(label)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Circular -/+ stepper with a serif value between, for deviation controls like sets and
/// reps (RecordActual) — a real stepper, unlike `ProtocolParseReviewView.perWeekStepper`,
/// which fakes one out of two `JournalChip`s. The circular buttons render at 34 points per
/// the mockup, but each sits in a >=44pt tappable area so the visual size never shrinks
/// the hit target.
struct JournalStepper: View {
    let label: String
    let value: Int
    var minusAccessibilityID: String
    var plusAccessibilityID: String
    let onDecrement: () -> Void
    let onIncrement: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.journal(.footnote))
                .foregroundStyle(Color.journalInk.opacity(0.6))
            HStack(spacing: 14) {
                stepperButton(
                    symbol: "−", accessibilityID: minusAccessibilityID, action: onDecrement)
                Text("\(value)")
                    .font(.journal(.title3, weight: .bold))
                    .foregroundStyle(Color.journalInk)
                    .frame(minWidth: 28)
                stepperButton(
                    symbol: "+", accessibilityID: plusAccessibilityID, action: onIncrement)
            }
        }
        .frame(minHeight: 44)
    }

    private func stepperButton(
        symbol: String, accessibilityID: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(symbol)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(Color.journalInk)
                .frame(width: 34, height: 34)
                .overlay(Circle().strokeBorder(Color.journalInk.opacity(0.5), lineWidth: 2))
        }
        .buttonStyle(.plain)
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityIdentifier(accessibilityID)
    }
}

/// Bordered square used for discrete numeric scales (pain 0–10, RPE, energy/motivation
/// 1–5) — DESIGN.md's "chip scale", distinct from `JournalChip`'s "pill chip". The
/// selected square fills with `selectedFill` (red pen for pain, ink for neutral scales)
/// and flips to paper-colored text. Renders at the mockup's ~26×36, centered inside a
/// >=44pt tappable area.
struct JournalScaleChip: View {
    let value: Int
    var isSelected = false
    var selectedFill = Color.journalInk
    var accessibilityID: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("\(value)")
                .font(.journal(.subheadline))
                .fontWeight(isSelected ? .bold : .regular)
                .foregroundStyle(isSelected ? Color.journalPaper : Color.journalInk)
                .frame(minWidth: 26, minHeight: 36)
                .background(isSelected ? selectedFill : Color.clear)
                .overlay(
                    Rectangle().strokeBorder(
                        isSelected ? selectedFill : Color.journalInk.opacity(0.4),
                        lineWidth: isSelected ? 2 : 1.5
                    )
                )
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityID ?? "scale-chip-\(value)")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Horizontally scrollable row of `JournalScaleChip`s over an arbitrary integer range
/// (0...10 for pain, 1...5 for energy/motivation, etc.), so the row survives Dynamic
/// Type without wrapping or clipping instead of laying every value out edge to edge.
/// `selected` is nil until a value is tapped; the row never invents a default.
struct JournalScaleChipRow: View {
    let range: ClosedRange<Int>
    let selected: Int?
    var selectedFill = Color.journalInk
    var accessibilityID: (Int) -> String = { "scale-chip-\($0)" }
    let onSelect: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(Array(range), id: \.self) { value in
                        JournalScaleChip(
                            value: value,
                            isSelected: selected == value,
                            selectedFill: selectedFill,
                            accessibilityID: accessibilityID(value)
                        ) {
                            onSelect(value)
                        }
                    }
                }
            }
            if range.count > 5 {
                Text("\(range.lowerBound)–\(range.upperBound) · swipe for more")
                    .font(.journal(.caption2))
                    .foregroundStyle(Color.journalInk.opacity(0.7))
            }
        }
    }
}

/// A shallow hand-drawn wave, replacing hairlines per DESIGN.md's "squiggle
/// divider". Shared rather than screen-local so a second screen reaching for one
/// gets this wave instead of drawing its own slightly different curve.
struct SquiggleDivider: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let midY = rect.midY
        let amplitude = rect.height / 2
        path.move(to: CGPoint(x: 0, y: midY))
        var x: CGFloat = 0
        var direction: CGFloat = -1
        let step = width / 4
        while x < width {
            path.addQuadCurve(
                to: CGPoint(x: min(x + step, width), y: midY),
                control: CGPoint(x: x + step / 2, y: midY + direction * amplitude)
            )
            x += step
            direction *= -1
        }
        return path
    }
}
