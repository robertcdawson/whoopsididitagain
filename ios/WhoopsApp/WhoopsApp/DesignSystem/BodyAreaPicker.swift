import SwiftUI

struct BodyAreaPicker: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @State private var selectedAreaIDs: Set<String>
    @State private var selectedView: BodyMapView
    @State private var focus: BodyMapFocus?
    @State private var showsList = false

    let onUse: ([String]) -> Void

    init(
        initialAreaIDs: [String],
        initialFocus: BodyMapFocus? = nil,
        onUse: @escaping ([String]) -> Void
    ) {
        let validIDs = BodyAreaCatalog.validIDs(initialAreaIDs)
        _selectedAreaIDs = State(initialValue: Set(validIDs))
        _selectedView = State(
            initialValue: BodyAreaCatalog.definitions(for: validIDs).compactMap(\.view).first
                ?? .front)
        _focus = State(initialValue: initialFocus)
        self.onUse = onUse
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                pickerHeader
                JournalRule().padding(.horizontal, 24)
                ScrollView {
                    Group {
                        if let focus {
                            focusContent(focus)
                                .transition(
                                    reduceMotion
                                        ? .opacity
                                        : .scale(scale: 0.96).combined(with: .opacity))
                        } else {
                            overviewContent
                                .transition(
                                    reduceMotion
                                        ? .opacity
                                        : .scale(scale: 0.96).combined(with: .opacity))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .background { JournalPaperBackground() }
            .foregroundStyle(Color.journalInk)
            .font(.journal())
            .safeAreaInset(edge: .bottom) {
                useSelectionButton
            }
            .sheet(isPresented: $showsList) {
                BodyAreaListPicker(selectedAreaIDs: $selectedAreaIDs)
            }
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .topLeading) {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement()
                    .accessibilityLabel("Body area picker")
                    .accessibilityIdentifier("body-area-picker")
            }
        }
    }

    private var pickerHeader: some View {
        HStack(spacing: 12) {
            Button("Cancel") { dismiss() }
                .frame(minWidth: 64, minHeight: 44, alignment: .leading)
                .accessibilityIdentifier("body-area-cancel")
            Spacer(minLength: 8)
            Text(focus?.displayName ?? "Affected areas")
                .font(.journal(.headline, weight: .semibold))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            Button("List") { showsList = true }
                .frame(minWidth: 64, minHeight: 44, alignment: .trailing)
                .accessibilityIdentifier("body-area-list")
        }
        .buttonStyle(JournalLinkButtonStyle())
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }

    private var overviewContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(
                "Tap a broad region to take a closer look. Nothing is selected until you confirm a specific area."
            )
            .font(.journal(.subheadline))
            .foregroundStyle(Color.journalInk.opacity(0.72))

            viewPicker

            BodyMapFigure(
                view: selectedView,
                selectedAreaIDs: selectedAreaIDs,
                onSelectFocus: openFocus
            )
            .frame(maxWidth: .infinity)
            .frame(height: 430)

            if !selectedDefinitions.isEmpty {
                selectedAreasSection
            }

            Button {
                showsList = true
            } label: {
                Label("Choose from a list", systemImage: "list.bullet")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(JournalLinkButtonStyle(fillsWidth: true))
            .accessibilityIdentifier("body-area-list-fallback")
        }
    }

    @ViewBuilder
    private func focusContent(_ focus: BodyMapFocus) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                changeFocus(nil)
            } label: {
                Label("Whole body", systemImage: "chevron.left")
                    .frame(minHeight: 44)
            }
            .buttonStyle(JournalLinkButtonStyle())
            .accessibilityIdentifier("body-area-whole-body")

            Text(
                "Choose one or more specific areas. Use the entire-region option when detail would be false precision."
            )
            .font(.journal(.subheadline))
            .foregroundStyle(Color.journalInk.opacity(0.72))

            viewPicker

            if focus.region == .arm {
                armFocusContent(focus)
            } else {
                genericFocusContent(focus)
            }

            selectedAreasSection

            Button {
                changeFocus(nil)
            } label: {
                Label("Add another area", systemImage: "plus")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(JournalLinkButtonStyle(fillsWidth: true))
            .accessibilityIdentifier("body-area-add-another")

            Button {
                showsList = true
            } label: {
                Label("Choose from a list", systemImage: "list.bullet")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(JournalLinkButtonStyle(fillsWidth: true))
        }
    }

    private func armFocusContent(_ focus: BodyMapFocus) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                ArmAreaFigure(
                    side: focus.side,
                    view: selectedView,
                    selectedAreaIDs: selectedAreaIDs,
                    onToggle: toggle
                )
                .frame(width: 150, height: 250)
                areaRows(for: focus)
            }
            VStack(spacing: 12) {
                ArmAreaFigure(
                    side: focus.side,
                    view: selectedView,
                    selectedAreaIDs: selectedAreaIDs,
                    onToggle: toggle
                )
                .frame(maxWidth: .infinity)
                .frame(height: 320)
                areaRows(for: focus)
            }
        }
    }

    private func genericFocusContent(_ focus: BodyMapFocus) -> some View {
        VStack(spacing: 12) {
            ZStack {
                BodyMapFigure(
                    view: selectedView,
                    selectedAreaIDs: selectedAreaIDs,
                    onSelectFocus: nil
                )
                .scaleEffect(focusScale(for: focus), anchor: focusAnchor(for: focus))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 250)
            .clipped()
            .accessibilityHidden(true)
            areaRows(for: focus)
        }
    }

    private func focusScale(for focus: BodyMapFocus) -> CGFloat {
        switch focus.region {
        case .headNeck: 2.15
        case .torso: 1.65
        case .leg: 1.55
        case .arm: 1
        }
    }

    private func focusAnchor(for focus: BodyMapFocus) -> UnitPoint {
        switch focus.region {
        case .headNeck: .top
        case .torso: .center
        case .leg:
            focus.side == .left ? .bottomTrailing : .bottomLeading
        case .arm: .center
        }
    }

    private func areaRows(for focus: BodyMapFocus) -> some View {
        VStack(spacing: 8) {
            ForEach(BodyAreaCatalog.areas(for: focus, view: selectedView)) { area in
                Button {
                    toggle(area)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(
                            systemName: selectedAreaIDs.contains(area.id)
                                ? "checkmark.circle.fill" : "circle"
                        )
                        .foregroundStyle(
                            selectedAreaIDs.contains(area.id)
                                ? Color.journalAmberText : Color.journalInk.opacity(0.55))
                        Text(area.shortLabel)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.horizontal, 10)
                    .background(
                        selectedAreaIDs.contains(area.id)
                            ? Color.journalAmber.opacity(0.13) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(
                    selectedAreaIDs.contains(area.id) ? "Selected" : "Not selected"
                )
                .accessibilityAddTraits(
                    selectedAreaIDs.contains(area.id) ? .isSelected : []
                )
                .accessibilityIdentifier("body-area-row-\(area.id)")
            }
        }
    }

    private var selectedAreasSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(selectedDefinitions.isEmpty ? "No mapped areas" : "Selected areas")
                    .font(.journal(.subheadline, weight: .semibold))
                Spacer()
                if !selectedDefinitions.isEmpty {
                    Button("Clear") { selectedAreaIDs.removeAll() }
                        .buttonStyle(JournalLinkButtonStyle())
                        .accessibilityIdentifier("body-area-clear")
                }
            }
            if selectedDefinitions.isEmpty {
                Text("Your existing body-region text remains unchanged.")
                    .font(.journal(.footnote))
                    .foregroundStyle(Color.journalInk.opacity(0.65))
            } else {
                JournalChipLayout(spacing: 8) {
                    ForEach(selectedDefinitions) { area in
                        Button {
                            selectedAreaIDs.remove(area.id)
                        } label: {
                            Label(area.label, systemImage: "xmark")
                                .font(.journal(.footnote))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(
                                    Color.journalAmber.opacity(0.16),
                                    in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(area.label)")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var viewPicker: some View {
        Picker("View", selection: $selectedView) {
            ForEach(BodyMapView.allCases) { view in
                Text(view.displayName).tag(view)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("body-map-view")
    }

    private var useSelectionButton: some View {
        Button {
            onUse(BodyAreaCatalog.validIDs(Array(selectedAreaIDs)))
            dismiss()
        } label: {
            Text(useSelectionLabel)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(JournalPrimaryButtonStyle())
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .accessibilityIdentifier("body-area-use")
    }

    private var useSelectionLabel: String {
        selectedAreaIDs.isEmpty
            ? "Use no mapped areas"
            : "Use \(selectedAreaIDs.count) area\(selectedAreaIDs.count == 1 ? "" : "s")"
    }

    private var selectedDefinitions: [BodyAreaDefinition] {
        BodyAreaCatalog.definitions(for: Array(selectedAreaIDs))
    }

    private func openFocus(_ focus: BodyMapFocus) {
        selectedView = preferredView(for: focus)
        changeFocus(focus)
    }

    private func preferredView(for focus: BodyMapFocus) -> BodyMapView {
        selectedDefinitions.first { $0.focus == focus }?.view ?? selectedView
    }

    private func changeFocus(_ newFocus: BodyMapFocus?) {
        if reduceMotion {
            focus = newFocus
        } else {
            withAnimation(.snappy(duration: 0.28)) { focus = newFocus }
        }
    }

    private func toggle(_ area: BodyAreaDefinition) {
        let focusIDs = Set(
            BodyAreaCatalog.all.filter { $0.focus == area.focus }.map(\.id))
        let wholeFocusID = BodyAreaCatalog.all.first {
            $0.focus == area.focus && $0.isWholeFocus
        }?.id

        if area.isWholeFocus {
            let wasSelected = selectedAreaIDs.contains(area.id)
            selectedAreaIDs.subtract(focusIDs)
            if !wasSelected { selectedAreaIDs.insert(area.id) }
        } else {
            if let wholeFocusID { selectedAreaIDs.remove(wholeFocusID) }
            if selectedAreaIDs.contains(area.id) {
                selectedAreaIDs.remove(area.id)
            } else {
                selectedAreaIDs.insert(area.id)
            }
        }
    }
}

struct BodyMapFigure: View {
    let view: BodyMapView
    let selectedAreaIDs: Set<String>
    let onSelectFocus: ((BodyMapFocus) -> Void)?

    var body: some View {
        ZStack {
            Image(view == .front ? "BodyMapFront" : "BodyMapBack")
                .resizable()
                .scaledToFit()
                .accessibilityHidden(true)
            GeometryReader { geometry in
                ForEach(BodyAreaCatalog.focuses(for: view)) { focus in
                    focusControl(focus, in: geometry.size)
                }
            }
        }
        .aspectRatio(3 / 5, contentMode: .fit)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func focusControl(_ focus: BodyMapFocus, in size: CGSize) -> some View {
        let frame = normalizedFrame(for: focus, in: size)
        let isSelected = BodyAreaCatalog.containsSelection(
            in: focus,
            selectedIDs: selectedAreaIDs)
        let overlay = RoundedRectangle(cornerRadius: min(frame.width, frame.height) * 0.28)
            .fill(isSelected ? Color.journalAmber.opacity(0.28) : Color.clear)
            .overlay {
                RoundedRectangle(cornerRadius: min(frame.width, frame.height) * 0.28)
                    .stroke(
                        isSelected ? Color.journalAmberText.opacity(0.9) : Color.clear,
                        lineWidth: 2)
            }
            .frame(width: frame.width, height: frame.height)

        if let onSelectFocus {
            Button {
                onSelectFocus(focus)
            } label: {
                overlay.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .position(x: frame.midX, y: frame.midY)
            .accessibilityLabel(focus.displayName)
            .accessibilityHint("Opens a detailed area picker")
            .accessibilityValue(isSelected ? "Selected" : "Not selected")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier("body-focus-\(focus.id)")
        } else {
            overlay.position(x: frame.midX, y: frame.midY).accessibilityHidden(true)
        }
    }

    private func normalizedFrame(for focus: BodyMapFocus, in size: CGSize) -> CGRect {
        let personRightIsScreenLeft = view == .front
        let screenLeft: Bool
        switch focus.side {
        case .right: screenLeft = personRightIsScreenLeft
        case .left: screenLeft = !personRightIsScreenLeft
        case .midline: screenLeft = false
        }

        let normalized: CGRect
        switch focus.region {
        case .headNeck:
            normalized = CGRect(x: 0.39, y: 0.05, width: 0.22, height: 0.14)
        case .torso:
            normalized = CGRect(x: 0.37, y: 0.19, width: 0.26, height: 0.34)
        case .arm:
            normalized = CGRect(
                x: screenLeft ? 0.14 : 0.63,
                y: 0.19,
                width: 0.23,
                height: 0.40)
        case .leg:
            normalized = CGRect(
                x: screenLeft ? 0.31 : 0.50,
                y: 0.53,
                width: 0.19,
                height: 0.39)
        }
        return CGRect(
            x: normalized.minX * size.width,
            y: normalized.minY * size.height,
            width: normalized.width * size.width,
            height: normalized.height * size.height)
    }
}

private struct ArmAreaFigure: View {
    let side: BodyMapSide
    let view: BodyMapView
    let selectedAreaIDs: Set<String>
    let onToggle: (BodyAreaDefinition) -> Void

    var body: some View {
        ZStack {
            Image(view == .front ? "BodyMapRightArmFront" : "BodyMapRightArmBack")
                .resizable()
                .scaledToFit()
                .scaleEffect(x: side == .left ? -1 : 1, y: 1)
                .accessibilityHidden(true)
            GeometryReader { geometry in
                ForEach(specificAreas) { area in
                    let frame = hitFrame(for: area, in: geometry.size)
                    let isSelected = selectedAreaIDs.contains(area.id)
                    let cornerRadius = min(frame.width, frame.height) / 2
                    Button {
                        onToggle(area)
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: cornerRadius)
                                .fill(isSelected ? Color.journalAmber.opacity(0.3) : Color.clear)
                                .overlay {
                                    RoundedRectangle(cornerRadius: cornerRadius)
                                        .stroke(
                                            isSelected ? Color.journalAmberText : Color.clear,
                                            lineWidth: 2)
                                }
                            if isSelected {
                                Image(systemName: "checkmark.circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, Color.journalAmberText)
                                    .font(.title3)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .frame(width: frame.width, height: frame.height)
                    .position(x: frame.midX, y: frame.midY)
                    .accessibilityLabel(area.label)
                    .accessibilityValue(isSelected ? "Selected" : "Not selected")
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityIdentifier("body-area-figure-\(area.id)")
                }
            }
        }
        .aspectRatio(3 / 5, contentMode: .fit)
    }

    private var specificAreas: [BodyAreaDefinition] {
        let focus = BodyMapFocus(region: .arm, side: side)
        return BodyAreaCatalog.figureAreas(for: focus, view: view)
    }

    private func hitFrame(for area: BodyAreaDefinition, in size: CGSize) -> CGRect {
        let normalized: CGRect
        if area.id.contains("shoulder") {
            normalized = CGRect(x: 0.35, y: 0.13, width: 0.30, height: 0.16)
        } else if area.id.contains("upper-arm") {
            normalized = CGRect(x: 0.38, y: 0.25, width: 0.24, height: 0.20)
        } else if area.id.contains("elbow") {
            normalized = CGRect(x: 0.38, y: 0.43, width: 0.24, height: 0.14)
        } else if area.id.contains("forearm") {
            normalized = CGRect(x: 0.36, y: 0.51, width: 0.28, height: 0.20)
        } else {
            normalized = CGRect(x: 0.32, y: 0.69, width: 0.36, height: 0.18)
        }
        return CGRect(
            x: normalized.minX * size.width,
            y: normalized.minY * size.height,
            width: normalized.width * size.width,
            height: normalized.height * size.height)
    }
}

private struct BodyAreaListPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selectedAreaIDs: Set<String>

    var body: some View {
        NavigationStack {
            JournalList {
                ForEach(allFocuses) { focus in
                    Section(focus.displayName) {
                        ForEach(BodyAreaCatalog.all.filter { $0.focus == focus }) { area in
                            Button {
                                toggle(area)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(area.shortLabel)
                                        if let viewLabel = area.viewLabel {
                                            Text(viewLabel)
                                                .font(.journal(.caption))
                                                .foregroundStyle(Color.journalInk.opacity(0.65))
                                        }
                                    }
                                    Spacer()
                                    Image(
                                        systemName: selectedAreaIDs.contains(area.id)
                                            ? "checkmark.circle.fill" : "circle")
                                }
                                .frame(minHeight: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityValue(
                                selectedAreaIDs.contains(area.id) ? "Selected" : "Not selected"
                            )
                            .accessibilityAddTraits(
                                selectedAreaIDs.contains(area.id) ? .isSelected : []
                            )
                            .accessibilityIdentifier("body-area-list-row-\(area.id)")
                        }
                    }
                }
            }
            .navigationTitle("Affected areas")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("body-area-list-done")
                }
            }
        }
    }

    private var allFocuses: [BodyMapFocus] {
        [
            BodyMapFocus(region: .headNeck, side: .midline),
            BodyMapFocus(region: .arm, side: .left),
            BodyMapFocus(region: .arm, side: .right),
            BodyMapFocus(region: .torso, side: .midline),
            BodyMapFocus(region: .leg, side: .left),
            BodyMapFocus(region: .leg, side: .right),
        ]
    }

    private func toggle(_ area: BodyAreaDefinition) {
        let focusIDs = Set(
            BodyAreaCatalog.all.filter { $0.focus == area.focus }.map(\.id))
        let wholeFocusID = BodyAreaCatalog.all.first {
            $0.focus == area.focus && $0.isWholeFocus
        }?.id
        if area.isWholeFocus {
            let wasSelected = selectedAreaIDs.contains(area.id)
            selectedAreaIDs.subtract(focusIDs)
            if !wasSelected { selectedAreaIDs.insert(area.id) }
        } else {
            if let wholeFocusID { selectedAreaIDs.remove(wholeFocusID) }
            if selectedAreaIDs.contains(area.id) {
                selectedAreaIDs.remove(area.id)
            } else {
                selectedAreaIDs.insert(area.id)
            }
        }
    }
}
