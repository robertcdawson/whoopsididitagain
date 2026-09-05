import SwiftUI

private struct FormKeyboardFocusKey: EnvironmentKey {
    static var defaultValue: FocusState<UUID?>.Binding? { nil }
}

extension EnvironmentValues {
    fileprivate var formKeyboardFocus: FocusState<UUID?>.Binding? {
        get { self[FormKeyboardFocusKey.self] }
        set { self[FormKeyboardFocusKey.self] = newValue }
    }
}

extension View {
    /// Each screen owns its focus; clearing one screen never targets another window's responder.
    func formKeyboardScope(
        _ focus: FocusState<UUID?>.Binding,
        doneIdentifier: String = "dismiss-form-keyboard"
    ) -> some View {
        modifier(FormKeyboardScope(focus: focus, doneIdentifier: doneIdentifier))
    }

    /// Attach directly to a TextField/TextEditor, with independent identity for repeated rows.
    func formKeyboardField(
        dismissOnSubmit: Bool = true, singleLineText: Binding<String>? = nil
    ) -> some View {
        modifier(
            FormKeyboardField(dismissOnSubmit: dismissOnSubmit, singleLineText: singleLineText))
    }
}

private struct FormKeyboardScope: ViewModifier {
    let focus: FocusState<UUID?>.Binding
    let doneIdentifier: String
    @AppStorage("journalLeftHanded") private var leftHanded = false
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .environment(\.formKeyboardFocus, focus)
            .scrollDismissesKeyboard(.immediately)
            .onScrollPhaseChange { _, phase in
                // Clear semantic focus as well as the keyboard's presentation, so an
                // accessory or previously focused field cannot restore it after scrolling.
                if phase == .interacting { focus.wrappedValue = nil }
            }
            // Reserve real space for Done. The floating iOS keyboard toolbar can cover
            // the focused value even when the native form reports the field as hittable.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if focus.wrappedValue != nil {
                    HStack {
                        if !leftHanded { Spacer() }
                        Button("Done") { focus.wrappedValue = nil }
                            .buttonStyle(JournalLinkButtonStyle())
                            .accessibilityIdentifier(doneIdentifier)
                        if leftHanded { Spacer() }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 4)
                    .background(Color.journalPaper)
                }
            }
            .onDisappear { focus.wrappedValue = nil }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { focus.wrappedValue = nil }
            }
    }
}

private struct FormKeyboardField: ViewModifier {
    @Environment(\.formKeyboardFocus) private var focus
    @State private var id = UUID()
    let dismissOnSubmit: Bool
    let singleLineText: Binding<String>?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let focus {
            content
                .focused(focus, equals: id)
                .environment(\.journalFieldFocused, focus.wrappedValue == id)
                .submitLabel(dismissOnSubmit ? .done : .return)
                .onSubmit {
                    if dismissOnSubmit { focus.wrappedValue = nil }
                }
                .onChange(of: singleLineText?.wrappedValue) { _, value in
                    // A wrapping TextField inserts a newline instead of submitting on the
                    // software keyboard. Single-line values may wrap visually, but Done
                    // still commits focus; true multiline notes deliberately omit this binding.
                    guard let value, value.contains(where: \.isNewline) else { return }
                    singleLineText?.wrappedValue = value.components(separatedBy: .newlines)
                        .joined(separator: " ").trimmingCharacters(in: .whitespaces)
                    focus.wrappedValue = nil
                }
                .onDisappear {
                    if focus.wrappedValue == id { focus.wrappedValue = nil }
                }
        } else {
            content
        }
    }
}
