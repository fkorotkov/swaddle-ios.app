import SwiftUI

enum ActivityEditorField: Hashable { case milk, formula, value, ounces, note, duration }

struct AmountField: View {
    let title: String
    let symbol: String
    let color: Color
    @Binding var draft: VolumeDraft
    let component: VolumeDraft.Component
    var focus: FocusState<ActivityEditorField?>.Binding? = nil
    var focusValue: ActivityEditorField = .milk
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.babyPalette) private var palette
    @ScaledMetric(relativeTo: .title3) private var adjustmentSymbolSize = 18
    var body: some View {
        LogCard(color: color, verticalPadding: 16) {
            GlassEffectContainer(spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    ViewThatFits(in: .horizontal) {
                        HStack { heading.fixedSize(); Spacer(); stepHint }
                        VStack(alignment: .leading, spacing: 4) { heading; stepHint }
                    }
                    if typeSize.isAccessibilitySize {
                        amount
                        HStack { adjustment(-1); Spacer(); adjustment(1) }
                    } else {
                        HStack(spacing: 16) {
                            adjustment(-1)
                            amount
                            adjustment(1)
                        }
                    }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: draft.amount(for: component))
    }
    private var heading: some View { Label(title, systemImage: symbol).font(.headline) }
    private var stepHint: some View { Text("± \(draft.stepLabel)").font(.caption).foregroundStyle(LogStyle.muted).fixedSize() }
    private var amount: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            // The hidden text gives the editable quantity a natural width beside its unit.
            Text(draft.text(for: component).isEmpty ? "0" : draft.text(for: component))
                .font(.system(.largeTitle, design: .rounded, weight: .semibold)).monospacedDigit()
                .lineLimit(1).padding(.horizontal, 4).frame(minWidth: 48, minHeight: 52)
                .hidden().accessibilityHidden(true)
                .overlay {
                    if let focus { input.focused(focus, equals: focusValue) }
                    else { input }
                }
            Text(draft.unit.label).font(.body).foregroundStyle(LogStyle.muted).fixedSize()
        }.frame(maxWidth: .infinity, minHeight: 52)
    }
    private var input: some View {
        let editing = focus == nil || focus?.wrappedValue == focusValue
        // Keep the real field as the hit target and accessibility element. Only
        // its unfocused display rolls between step values; typing stays immediate.
        return TextField("0", text: Binding(get: { draft.text(for: component) }, set: { draft.setText($0, for: component) }),
                         prompt: Text("0").foregroundStyle(editing ? Color.secondary : .clear))
            .keyboardType(.decimalPad).multilineTextAlignment(.center)
            .font(.system(.largeTitle, design: .rounded, weight: .semibold)).monospacedDigit()
            .foregroundStyle(editing ? Color.primary : .clear)
            .overlay {
                if !editing {
                    Text(draft.text(for: component).isEmpty ? "0" : draft.text(for: component))
                        .font(.system(.largeTitle, design: .rounded, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(draft.text(for: component).isEmpty ? Color.secondary : .primary)
                        .logValueTransition(value: draft.text(for: component))
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .accessibilityLabel("\(title) amount in \(draft.unit == .ml ? String(localized: "milliliters") : String(localized: "ounces"))")
            .accessibilityHint("Enter an exact amount, or use the decrease and increase buttons")
    }
    private func adjustment(_ direction: Int) -> some View {
        Button {
            focus?.wrappedValue = nil
            draft.adjust(direction, component: component)
        } label: {
            Image(systemName: direction > 0 ? "plus" : "minus")
                .font(.system(size: min(adjustmentSymbolSize, 24), weight: .semibold)).frame(width: 48, height: 48)
                .foregroundStyle(draft.canAdjust(direction, component: component) ? palette.accent : .secondary)
                .contentShape(.circle)
                // Keep one pressed response on repeating controls;
                // LogPressStyle supplies their spring feedback.
                .logGlass(in: .circle, fallback: LogStyle.card)
        }.buttonStyle(LogPressStyle()).foregroundStyle(palette.accent)
            .buttonRepeatBehavior(.enabled)
            .disabled(!draft.canAdjust(direction, component: component))
            .accessibilityLabel("\(direction > 0 ? String(localized: "Increase") : String(localized: "Decrease")) \(title.lowercased()) by \(draft.stepLabel)")
            .accessibilityValue(draft.unit.quantity(draft.amount(for: component) ?? 0))
            .accessibilityHint("Touch and hold to keep adjusting")
    }
}

struct EventTimeField: View {
    @Environment(\.babyPalette) private var palette
    @Binding var date: Date
    var title = String(localized: "When")
    var quickMinutes = [0, 15, 30]
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var chosenMinutes: Int?
    @State private var chosenDate: Date?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !typeSize.isAccessibilitySize { Text(title).font(.headline) }
            LogDatePicker(title: typeSize.isAccessibilitySize ? title : String(localized: "Date and time"), selection: $date)
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
            layout {
                ForEach(quickMinutes, id: \.self) { minutes in
                    let selected = chosenMinutes == minutes && chosenDate == date
                    Button {
                        let value = Date.now.addingTimeInterval(TimeInterval(-minutes * 60))
                        chosenMinutes = minutes
                        chosenDate = value
                        date = value
                    } label: {
                        Text(minutes == 0 ? String(localized: "Now") : String(localized: "\(minutes) min ago")).font(
                            .subheadline.weight(.medium)
                        )
                            .padding(.horizontal, 12).frame(minHeight: 44)
                        .background(palette.accent.opacity(selected ? 0.22 : 0.10), in: .capsule)
                        .overlay {
                            Capsule().strokeBorder(
                                palette.accent.opacity(selected ? 1 : 0), lineWidth: 1.5)
                        }
                    }.buttonStyle(LogPressStyle()).foregroundStyle(palette.accent)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityValue(selected ? String(localized: "Selected") : "")
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: selected)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: chosenDate)
    }
}

struct ActivityEditor: View {
    let store: LogStore
    let route: LogRoute
    @Environment(\.dismiss) private var dismiss
    @State private var volume: VolumeDraft
    @State private var pee: Bool
    @State private var poo: Bool
    @State private var occurredAt: Date
    @State private var note: String
    @State private var value: String
    @State private var ounces: String
    @State private var measureUnit: String
    @State private var method: String
    @State private var lengthPosition: LengthMeasurementPosition
    @State private var error: String?
    @State private var saving = false
    @State private var confirmDelete = false
    @State private var preset: String
    @State private var unknownSplit: Bool
    @FocusState private var focusedField: ActivityEditorField?
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.verticalSizeClass) private var verticalSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let commandID = UUID()
    private let activityID: UUID
    private let parents: Set<UUID>
    private let restored: Bool
    private var kind: ActivityKind { route.kind ?? .bottle }
    private var child: ChildProfile? { store.snapshot.children.first { $0.id == route.childID } }
    private var palette: BabyPalette { BabyPalette(gender: child?.paletteGender) }

    init(store: LogStore, route: LogRoute) {
        self.store = store; self.route = route
        activityID = route.activity?.id ?? UUID()
        parents = Set(route.record?.heads.map(\.id) ?? [])
        let previous = route.childID.flatMap { store.previousBottle(childID: $0) }
        var bottle: Bottle? = route.activity == nil && route.kind == .bottle ? previous : nil
        var diaper = Diaper(pee: false, poo: false)
        let preferredLengthUnit = UserDefaults.standard.string(forKey: LengthUnit.preferenceKey).flatMap(LengthUnit.init(rawValue:)) ?? .cm
        let bodyMeasurement = route.kind.map { [.length, .headCircumference].contains($0) } ?? false
        var numeric = "", unit = route.kind == .temperature ? "°C" : bodyMeasurement ? preferredLengthUnit.rawValue : "kg", measurementMethod = ""
        var position: LengthMeasurementPosition = .lyingDown
        if let child = store.snapshot.children.first(where: { $0.id == route.childID }),
           let age = ChildAge(child: child, at: .now, calendar: .current), age.chronologicalDays >= 731 { position = .standing }
        if let activity = route.activity {
            switch activity.payload {
            case .bottle(let b): bottle = b
            case .diaper(let d): diaper = d
            case .weight(let grams, _): numeric = (grams / 1000).formatted(.number.precision(.fractionLength(0...4)))
            case .length(let cm, let u, let p): unit = u.rawValue; position = p; numeric = u.fromCentimeters(cm).formatted(.number.precision(.fractionLength(0...4)))
            case .headCircumference(let cm, let u): unit = u.rawValue; numeric = u.fromCentimeters(cm).formatted(.number.precision(.fractionLength(0...4)))
            case .temperature(let c, let u, let m): unit = u; measurementMethod = m; numeric = (u == "°F" ? c * 9 / 5 + 32 : c).formatted(.number.precision(.fractionLength(0...2)))
            default: break
            }
        }
        unknownSplit = (bottle?.unknownML ?? 0) > 0
        volume = VolumeDraft(unit: bottle?.unit ?? store.volumeUnit, firstML: (bottle?.unknownML ?? 0) > 0 ? bottle?.unknownML : bottle?.milkML, secondML: bottle?.formulaML)
        pee = diaper.pee; poo = diaper.poo; occurredAt = route.activity?.occurredAt ?? .now
        note = route.activity?.note ?? ""; value = numeric; measureUnit = unit; method = measurementMethod; ounces = ""
        lengthPosition = position
        preset = bottle.map { $0.milkML > 0 && $0.formulaML > 0 ? "Both" : $0.formulaML > 0 ? "Formula" : "Milk" } ?? "Both"
        restored = route.activity == nil && bottle != nil
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: verticalSize == .compact ? 12 : 20) {
                    Label(child?.name ?? String(localized: "Child unavailable"), systemImage: "person.crop.circle").font(.subheadline.weight(.semibold)).foregroundStyle(palette.accent)
                    if let record = route.record, record.hasConflict {
                        Label("There are competing edits. Saving this version resolves them; all prior versions remain in history.", systemImage: "exclamationmark.bubble").font(.callout)
                    }
                    switch kind {
                    case .bottle:
                        if !typeSize.isAccessibilitySize && verticalSize != .compact {
                            Text("A little nourishment.").font(LogStyle.heading())
                        }
                        bottleFields
                    case .diaper: diaperFields
                    case .weight, .temperature: measurementFields
                    case .length, .headCircumference: bodyMeasurementFields
                    case .careNote: TextField("What would you like to note?", text: $note, axis: .vertical).lineLimit(5...12).focused($focusedField, equals: .note)
                    default: EmptyView()
                    }
                    EventTimeField(date: $occurredAt, quickMinutes: kind == .bottle ? [0, 30, 45] : [0, 15, 30])
                    DisclosureGroup {
                        if kind != .careNote { TextField("Add a note", text: $note, axis: .vertical).lineLimit(2...5).focused($focusedField, equals: .note).padding(.top, 10) }
                        if let activity = route.activity {
                            Text("Recorded by \(store.snapshot.caregiverName(activity.authorID)) · \(activity.source)").font(.caption).foregroundStyle(LogStyle.muted)
                            RevisionHistory(store: store, id: activity.id)
                        }
                    } label: { Text("More details").frame(minHeight: 44) }
                    if let error { ErrorNotice(message: error) }
                    if route.activity != nil && store.canEdit {
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Text("Delete entry").frame(minHeight: 44).contentShape(.rect)
                        }
                    }
                }.padding(22)
            }.scrollDismissesKeyboard(.interactively).background(LogStyle.canvas)
                .navigationTitle(route.activity == nil ? String(localized: "Record \(kind.title.lowercased())") : kind.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                }
                .safeAreaInset(edge: .bottom) {
                    if store.canEdit {
                        EditorActionBar(editing: focusedField != nil,
                                        nextTitle: kind == .bottle && !unknownSplit && preset == String(localized: "Both") && focusedField == .milk ? String(localized: "Next: Formula") : nil,
                                        next: { focusedField = .formula }, done: { focusedField = nil }) {
                            PrimaryButton(title: saveTitle, disabled: saving || (kind == .diaper && !pee && !poo) || (kind == .bottle && (try? volume.validated()) == nil)) { save() }
                        }
                    }
                }
                .confirmationDialog("Delete this entry?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete entry", role: .destructive) {
                        guard let record = route.record else { return }
                        do { try store.delete(record); dismiss() } catch { self.error = error.localizedDescription }
                    }
                } message: { Text("The deletion will be shared with your family. Previous versions remain in the change history.") }
        }.foregroundStyle(LogStyle.ink).babyPalette(for: child?.paletteGender)
    }
    private var saveTitle: String {
        if route.activity != nil { return String(localized: "Save changes") }
        if kind == .bottle {
            guard volume.total > 0 else { return String(localized: "Save feed") }
            return typeSize.isAccessibilitySize ? String(localized: "Save \(volume.unit.quantity(volume.total))") : String(localized: "Save \(volume.unit.quantity(volume.total)) feed")
        }
        if kind == .diaper { return String(localized: "Save \(Diaper(pee: pee, poo: poo).title.lowercased())") }
        return String(localized: "Save \(kind.title.lowercased())")
    }
    private var bottleFields: some View {
        VStack(alignment: .leading, spacing: 16) {
            VolumePicker(unit: Binding(get: { volume.unit }, set: { volume.changeUnit($0) }))
            if route.activity != nil {
                Toggle("Split not recorded", isOn: $unknownSplit).onChange(of: unknownSplit) {
                    let total = volume.total
                    volume = VolumeDraft(unit: volume.unit, firstML: unknownSplit ? total : nil, secondML: nil)
                    preset = "Both"
                }
            }
            if unknownSplit {
                AmountField(title: String(localized: "Total"), symbol: "waterbottle", color: LogStyle.bottleSurface, draft: $volume, component: .first, focus: $focusedField, focusValue: .milk)
                Text("This total is kept separately from milk and formula. Turn off “Split not recorded” to enter the composition.").font(.caption).foregroundStyle(LogStyle.muted)
            } else {
                Picker("Bottle contents", selection: $preset) {
                    ForEach(["Milk", "Formula", "Both"], id: \.self) { Text(LocalizedStringKey($0)) }
                }.logPickerStyle().onChange(of: preset) {
                    if preset == "Milk" { volume.setSecond("0") }
                    if preset == "Formula" { volume.setFirst("0") }
                    if focusedField == .milk && preset == "Formula" { focusedField = .formula }
                    if focusedField == .formula && preset == "Milk" { focusedField = .milk }
                }
                if preset != "Formula" {
                    AmountField(
                        title: String(localized: "Milk"), symbol: "drop.fill", color: LogStyle.bottleSurface,
                        draft: $volume,
                        component: .first, focus: $focusedField, focusValue: .milk
                    ).transition(.opacity)
                }
                if preset != "Milk" {
                    AmountField(
                        title: String(localized: "Formula"), symbol: "circle.lefthalf.filled", color: LogStyle.apricot,
                        draft: $volume, component: .second, focus: $focusedField,
                        focusValue: .formula
                    ).transition(.opacity)
                }
            }
            if restored { Label("From your last bottle", systemImage: "arrow.counterclockwise").font(.subheadline).foregroundStyle(LogStyle.muted) }
            Text("Amounts consumed · Milk includes expressed or donor milk.").font(.caption).foregroundStyle(LogStyle.muted)
        }
        .animation(
            reduceMotion || focusedField != nil ? nil : .smooth(duration: 0.2), value: preset)
    }
    private var diaperFields: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !typeSize.isAccessibilitySize && verticalSize != .compact {
                Text("A little change.").font(.system(.title, design: .serif, weight: .semibold))
            }
            Text("Choose one or both. It’s always one diaper.").foregroundStyle(LogStyle.muted)
            DiaperChoice(title: String(localized: "Pee"), symbol: "drop.fill", isSelected: $pee)
            DiaperChoice(title: String(localized: "Poo"), symbol: "circle.hexagongrid.fill", isSelected: $poo)
        }
    }
    private var bodyMeasurementFields: some View {
        VStack(alignment: .leading, spacing: 18) {
            Picker("Measurement unit", selection: $measureUnit) {
                ForEach(LengthUnit.allCases) { Text($0.label).tag($0.rawValue) }
            }.logPickerStyle().onChange(of: measureUnit) { old, new in
                UserDefaults.standard.set(new, forKey: LengthUnit.preferenceKey)
                guard let amount = Decimal.input(value), let oldUnit = LengthUnit(rawValue: old),
                      let newUnit = LengthUnit(rawValue: new) else { return }
                value = newUnit.fromCentimeters(oldUnit.toCentimeters(amount)).formatted(.number.precision(.fractionLength(0...4)))
            }
            if kind == .length {
                Text("Measured").font(.headline)
                Picker("Measurement position", selection: $lengthPosition) {
                    ForEach(LengthMeasurementPosition.allCases) { Text($0.title).tag($0) }
                }.logPickerStyle()
            }
            LogCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text(kind == .length ? lengthPosition.measurementTitle : String(localized: "Head circumference")).font(.headline)
                    HStack(alignment: .firstTextBaseline) {
                        TextField("Measurement", text: $value).keyboardType(.decimalPad)
                            .focused($focusedField, equals: .value).font(.largeTitle)
                            .accessibilityLabel(kind == .length ? lengthPosition.measurementTitle : String(localized: "Head circumference"))
                            .accessibilityIdentifier("measurement.value")
                        Text(measureUnit).foregroundStyle(LogStyle.muted)
                    }
                }
            }
            Text(kind == .length
                 ? String(localized: "Length is measured lying down; height is measured standing. Save the original measurement. Trends handles WHO’s length/height comparison adjustment.")
                 : String(localized: "Save the circumference around the head. Your dated measurements and growth comparisons appear in Trends."))
                .font(.subheadline).foregroundStyle(LogStyle.muted)
        }
    }
    private var measurementFields: some View {
        VStack(alignment: .leading, spacing: 18) {
            Picker("Unit", selection: $measureUnit) {
                ForEach(kind == .weight ? ["kg", "g", "lb + oz"] : ["°C", "°F"], id: \.self) { Text($0) }
            }.logPickerStyle().onChange(of: measureUnit) { old, new in
                guard let amount = Decimal.input(value) else { return }
                if kind == .temperature { value = (new == "°F" ? amount * 9 / 5 + 32 : (amount - 32) * 5 / 9).formatted(.number.precision(.fractionLength(0...2))) }
                else {
                    let grams = old == "kg" ? amount * 1000 : old == "g" ? amount : amount * Decimal(string: "453.59237")! + (Decimal.input(ounces) ?? 0) * Decimal(string: "28.349523125")!
                    if new == "lb + oz" {
                        let pounds = Int((grams / Decimal(string: "453.59237")!).double)
                        value = pounds.formatted()
                        ounces = ((grams - Decimal(pounds) * Decimal(string: "453.59237")!) / Decimal(string: "28.349523125")!).formatted(.number.precision(.fractionLength(0...2)))
                    } else { value = (new == "kg" ? grams / 1000 : grams).formatted(.number.precision(.fractionLength(0...4))) }
                }
            }
            LogCard {
                HStack(alignment: .firstTextBaseline) {
                    TextField(kind == .weight ? String(localized: "Weight") : String(localized: "Temperature"), text: $value).keyboardType(.decimalPad).focused($focusedField, equals: .value).font(.largeTitle).accessibilityLabel(kind.title)
                    Text(measureUnit == String(localized: "lb + oz") ? String(localized: "lb") : measureUnit).foregroundStyle(LogStyle.muted)
                }
                if measureUnit == "lb + oz" {
                    HStack { TextField("Ounces", text: $ounces).keyboardType(.decimalPad).focused($focusedField, equals: .ounces).font(.title); Text("oz") }.padding(.top)
                }
            }
            if kind == .temperature {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Method").font(.headline)
                    Picker("Method", selection: $method) {
                        Text("Not specified").tag("")
                        ForEach([
                            ("Rectal", String(localized: "Rectal")),
                            ("Axillary", String(localized: "Axillary")),
                            ("Ear", String(localized: "Ear")),
                            ("Forehead", String(localized: "Forehead")),
                            ("Oral", String(localized: "Oral")),
                            ("Other", String(localized: "Other"))
                        ], id: \.0) { Text($0.1).tag($0.0) }
                    }.pickerStyle(.menu).controlSize(.large).frame(minHeight: 44)
                }
            }
        }
    }
    private func save() {
        saving = true
        defer { saving = false }
        do {
            guard let family = store.snapshot.family, let child else { throw LogError.message(String(localized: "This child is no longer available.")) }
            let payload: ActivityPayload
            switch kind {
            case .bottle:
                let (milk, formula) = try volume.validated()
                payload = .bottle(unknownSplit ? Bottle(milkML: 0, formulaML: 0, unit: volume.unit, unclassifiedML: milk + formula) : Bottle(milkML: milk, formulaML: formula, unit: volume.unit))
            case .diaper: payload = .diaper(Diaper(pee: pee, poo: poo))
            case .weight:
                guard let amount = Decimal.input(value) else { throw LogError.message(String(localized: "Enter a valid weight.")) }
                var grams = measureUnit == "kg" ? amount * 1000 : amount
                if measureUnit == "lb + oz" {
                    guard let oz = ounces.isEmpty ? 0 : Decimal.input(ounces), amount >= 0, oz >= 0, oz < 16 else { throw LogError.message(String(localized: "Use nonnegative pounds and ounces from 0 to less than 16.")) }
                    grams = amount * Decimal(string: "453.59237")! + oz * Decimal(string: "28.349523125")!
                }
                payload = .weight(grams: grams, unit: measureUnit)
            case .length, .headCircumference:
                guard let amount = Decimal.input(value), let unit = LengthUnit(rawValue: measureUnit) else {
                    throw LogError.message(String(localized: "Enter a valid measurement."))
                }
                let cm = unit.toCentimeters(amount)
                payload = kind == .length ? .length(centimeters: cm, unit: unit, position: lengthPosition) : .headCircumference(centimeters: cm, unit: unit)
            case .temperature:
                guard let amount = Decimal.input(value) else { throw LogError.message(String(localized: "Enter a valid temperature.")) }
                payload = .temperature(celsius: measureUnit == "°C" ? amount : (amount - 32) * 5 / 9, unit: measureUnit, method: method)
            case .careNote: payload = .careNote
            default: return
            }
            let activity = Activity(id: activityID, familyID: family.id, childID: child.id, occurredAt: occurredAt, timeZoneIdentifier: route.activity?.timeZoneIdentifier ?? TimeZone.current.identifier, createdAt: route.activity?.createdAt ?? .now, authorID: route.activity?.authorID ?? store.caregiverID, source: route.activity?.source ?? "App", note: note, payload: payload)
            try store.save(.activity(activity), parentIDs: parents, commandID: commandID, rememberBottle: route.activity == nil && kind == .bottle)
            store.toast = String(localized: "\(kind.title) saved for \(child.name)")
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct DiaperChoice: View {
    @Environment(\.babyPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .title2) private var symbolSize = 26
    let title: String
    let symbol: String
    @Binding var isSelected: Bool
    var body: some View {
        Button { isSelected.toggle() } label: {
            HStack(spacing: 18) {
                Image(systemName: symbol).font(.system(size: min(symbolSize, 32))).frame(width: 42)
                Text(title).font(.title2.weight(.semibold))
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle").font(.system(size: min(symbolSize, 32)))
                    .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
            }.padding(24).background(isSelected ? palette.surface : LogStyle.card, in: .rect(cornerRadius: 24))
        }.buttonStyle(LogPressStyle()).accessibilityValue(isSelected ? String(localized: "Selected") : String(localized: "Not selected"))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: isSelected)
            .sensoryFeedback(.selection, trigger: isSelected)
    }
}

struct RevisionHistory: View {
    let store: LogStore
    let id: UUID
    var body: some View {
        DisclosureGroup("Change history") {
            ForEach(store.history(for: id)) { revision in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(store.snapshot.caregiverName(revision.editorID)) · \(revision.date.formatted(date: .abbreviated, time: .shortened))").font(.caption.bold())
                    if revision.deleted { Text("Deleted").font(.caption) }
                    else if case .activity(let activity) = revision.value { Text(activity.detail(unit: store.volumeUnit)).font(.caption) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
            }
        }.font(.subheadline).padding(.top, 8)
    }
}
