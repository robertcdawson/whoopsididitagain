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
    func formKeyboardField(dismissOnSubmit: Bool = true) -> some View {
        modifier(FormKeyboardField(dismissOnSubmit: dismissOnSubmit))
    }
}

private struct FormKeyboardScope: ViewModifier {
    let focus: FocusState<UUID?>.Binding
    let doneIdentifier: String
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
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    if focus.wrappedValue != nil {
                        Spacer()
                        Button("Done") { focus.wrappedValue = nil }
                            .accessibilityIdentifier(doneIdentifier)
                    }
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

    @ViewBuilder
    func body(content: Content) -> some View {
        if let focus {
            content
                .focused(focus, equals: id)
                .submitLabel(dismissOnSubmit ? .done : .return)
                .onSubmit {
                    if dismissOnSubmit { focus.wrappedValue = nil }
                }
                .onDisappear {
                    if focus.wrappedValue == id { focus.wrappedValue = nil }
                }
        } else {
            content
        }
    }
}
