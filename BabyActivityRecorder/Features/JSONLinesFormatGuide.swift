import SwiftUI

struct JSONLinesFormatGuide: View {
    @State private var copiedFeeds = false
    @State private var copiedPumps = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("For exports from spreadsheets or another app. Paste one complete JSON object per line into Care notes. A leading { selects JSON Lines automatically.")
            Text("Version 1 supports bottle feeds and pumping in separate batches. Choose a child for feeds or a caregiver for pumping. Blank lines are fine. Do not include headings, code fences, or an enclosing array.")
            Text("Example bottle").font(.headline)
            Text(JSONLinesCareImport.example).font(.footnote.monospaced()).textSelection(.enabled)
            Text("Required: type is “feed”, version is 1, occurredAt includes seconds and a UTC offset (or Z), and all three amounts are in mL. Use numbers, not quoted strings. For breast milk only, set formulaML to 0; for formula only, set breastMilkML to 0.")
            Text("Unknown milk/formula split").font(.headline)
            Text(JSONLinesCareImport.unknownExample).font(.footnote.monospaced()).textSelection(.enabled)
            Text("Use null for both components when only totalML is known. Never guess a split. For a known split, the two components must add up to totalML within 0.01 mL; their sum is the saved volume.")
            Text("Pumping sessions").font(.headline)
            Text(JSONLinesPumpImport.example).font(.footnote.monospaced()).textSelection(.enabled)
            Text("Required: type is “pump”, version is 1, occurredAt includes seconds and a UTC offset, and totalML is a positive number. Optional leftML and rightML must both be numbers adding up to totalML within 0.01 mL, or both null/omitted. durationMinutes is a positive number, or null/omitted. Decimal precision is preserved.")
            Text("If the total was not recorded but both sides were, totalML may be null. Swaddle adds those two amounts and labels the calculation in review.")
            Text(JSONLinesPumpImport.totalOnlyExample).font(.footnote.monospaced()).textSelection(.enabled)
            Text("Choose the pumping profile once in the app. No child or caregiver identifier is needed in the JSON. Pumped milk does not count as consumed milk.")
            Text("Optional: notes preserves the wording; use \\n inside the string for a new line. timezone can name a zone such as America/New_York and must match the timestamp’s offset. id is a stable string from the original entry; source names the exporting app and requires id. Without source, IDs belong to “jsonl”.")
            Text("Keep the same source and ID when exporting again. Matching IDs for the selected child or pumping caregiver are excluded, even if amounts changed. Edit the saved entry to correct it. Without IDs, similar times and amounts are flagged for review.")
            Text("Limit: 50,000 characters or 500 lines. An invalid line stops the entire import and shows its line number. Review before saving; the whole batch can be undone.").foregroundStyle(.secondary)
            Button(copiedFeeds ? String(localized: "Feeding instructions copied") : String(localized: "Copy feeding export instructions"), systemImage: copiedFeeds ? "checkmark" : "doc.on.doc") {
                UIPasteboard.general.string = JSONLinesCareImport.exportInstructions
                copiedFeeds = true
            }.accessibilityIdentifier("import.copyJSONLInstructions")
            Button(copiedPumps ? String(localized: "Pumping instructions copied") : String(localized: "Copy pumping export instructions"), systemImage: copiedPumps ? "checkmark" : "doc.on.doc") {
                UIPasteboard.general.string = JSONLinesPumpImport.exportInstructions
                copiedPumps = true
            }.accessibilityIdentifier("import.copyPumpJSONLInstructions")
        }.font(.subheadline).fixedSize(horizontal: false, vertical: true)
    }
}

#Preview("Advanced import format") {
    NavigationStack {
        ScrollView { JSONLinesFormatGuide().padding(22) }
            .navigationTitle("JSON Lines").navigationBarTitleDisplayMode(.inline)
    }
}
