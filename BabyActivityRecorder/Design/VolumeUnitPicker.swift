import SwiftUI

struct VolumeUnitPicker: View {
    @Binding var unit: VolumeUnit
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Picker("Volume unit", selection: $unit) {
            Text("mL").accessibilityLabel("Milliliters").tag(VolumeUnit.ml)
            Text("oz").accessibilityLabel("Ounces").tag(VolumeUnit.oz)
        }
        .pickerStyle(.segmented)
        .controlSize(typeSize.isAccessibilitySize ? .large : .regular)
        .frame(width: typeSize.isAccessibilitySize ? 132 : 116)
        .frame(minHeight: 44)
        .accessibilityHint("Sets volume units across the app")
        .accessibilityIdentifier("volumeUnit.picker")
    }
}
