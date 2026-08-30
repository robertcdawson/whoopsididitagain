import SwiftUI

/// Field-journal visual tokens from docs/DESIGN.md, converted from the mockups'
/// oklch values to sRGB. Applied to the protocol capture and parse-review screens;
/// the rest of the app migrates in later phases.
extension Color {
    static let journalPaper = Color(red: 0.978, green: 0.959, blue: 0.921)
    static let journalInk = Color(red: 0.094, green: 0.202, blue: 0.336)
    static let journalRedPen = Color(red: 0.741, green: 0.255, blue: 0.246)
    static let journalGreen = Color(red: 0.161, green: 0.525, blue: 0.276)
    static let journalAmber = Color(red: 0.679, green: 0.446, blue: 0.111)
    static let journalDot = Color(red: 0.425, green: 0.383, blue: 0.314)
    static let journalTape = Color(red: 0.893, green: 0.846, blue: 0.671)
    static let journalCaptureBackground = Color(red: 0.078, green: 0.067, blue: 0.051)
    static let journalCaptureGold = Color(red: 0.941, green: 0.788, blue: 0.416)
}

/// Paper background with the 18-point dot grid and optional red margin rule.
struct JournalPaperBackground: View {
    var showsMarginRule = true

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
                Rectangle()
                    .fill(Color.journalRedPen.opacity(0.35))
                    .frame(width: 1.5)
                    .padding(.leading, 40)
            }
        }
        .ignoresSafeArea()
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
                .font(.system(.subheadline, design: .serif))
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
