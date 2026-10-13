import SwiftUI

struct CompactChildTitle: View {
  let children: [ChildProfile]
  let child: ChildProfile?
  let now: Date
  let calendar: Calendar
  var openingMotion: CocoonOpeningSession? = nil
  var preferCompact = false
  var ageCelebration: AgeCelebration? = nil
  var ageCelebrationTrigger: UUID? = nil
  let select: (UUID) -> Void
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    Group {
      if children.count > 1 {
        Menu {
          ForEach(children) { person in
            Button(person.name, systemImage: person.id == child?.id ? "checkmark" : "person") {
              select(person.id)
            }
          }
        } label: {
          title
        }
        .accessibilityLabel("Selected child, \(child?.name ?? "none")")
        .accessibilityValue(ageAccessibilityValue)
        .accessibilityHint("Choose another child")
      } else {
        title.accessibilityAddTraits(.isHeader)
      }
    }
    .frame(minHeight: 44, alignment: .leading)
    .onChange(of: typeSize, initial: true) { _, size in
      if size.isAccessibilitySize { openingMotion?.settle() }
    }
  }

  private var title: some View {
    Group {
      if typeSize.isAccessibilitySize || preferCompact {
        compactTitle
      } else {
        ViewThatFits(in: .horizontal) {
          HStack(spacing: 10) {
            CocoonOpeningMark(session: openingMotion)
              .frame(width: 54, height: 72)
            VStack(alignment: .leading, spacing: 3) {
              wordmark
              childName.fixedSize(horizontal: true, vertical: false)
              ageCaption
            }
          }
          compactTitle
        }
      }
    }
    .foregroundStyle(LogStyle.ink)
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(.rect)
  }

  private var compactTitle: some View {
    VStack(alignment: .leading, spacing: 3) {
      if !typeSize.isAccessibilitySize {
        HStack(spacing: 6) {
          CocoonOpeningMark(session: openingMotion, size: 32).frame(width: 22, height: 22)
          wordmark
        }
      }
      childName
      ageCaption
    }
  }

  private var wordmark: some View {
    Text("SWADDLE").font(.caption2.weight(.semibold)).tracking(2.2)
      .foregroundStyle(LogStyle.forest)
  }

  private var childName: some View {
    HStack(spacing: 5) {
      Text(child?.name ?? String(localized: "Today"))
        .font(LogStyle.heading(typeSize.isAccessibilitySize ? .title2 : .largeTitle))
        .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
        .fixedSize(horizontal: false, vertical: true)
        .multilineTextAlignment(.leading)
      if children.count > 1 { Image(systemName: "chevron.down").font(.caption.bold()) }
    }
  }

  private var age: ChildAge? {
    child.flatMap { ChildAge(child: $0, at: now, calendar: calendar) }
  }

  private var ageCaption: some View {
    HStack(spacing: 5) {
      Text(age.map { String(localized: "Today · \($0.chronologicalLabel)") } ?? String(localized: "Today"))
        .foregroundStyle(LogStyle.muted).fixedSize(horizontal: false, vertical: true)
      if ageCelebration != nil {
        Image(systemName: "sparkle").foregroundStyle(LogStyle.amber).accessibilityHidden(true)
      }
    }.font(.caption)
      .accessibilityLabel(ageAccessibilityValue)
      .modifier(AgeCelebrationHighlight(trigger: ageCelebrationTrigger))
  }

  private var ageAccessibilityValue: String {
    guard let age else { return String(localized: "Today") }
    if age.chronologicalDays == 0 { return String(localized: "Today, born today") }
    return String(localized: "Today, age \(age.spokenChronologicalDuration)")
  }
}

struct FamilySyncIndicator: View {
  let status: FamilySyncStatus
  let action: () -> Void
  @State private var showProgress = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Button(action: action) {
      ZStack(alignment: .topTrailing) {
        if showProgress && status.isWorking {
          if reduceMotion {
            Image(systemName: "arrow.triangle.2.circlepath").frame(width: 26, height: 26)
          } else {
            ProgressView().controlSize(.small).frame(width: 26, height: 26)
          }
        } else {
          Image(systemName: status.phase == .local ? "iphone" : "icloud")
            .font(.body).frame(width: 26, height: 26)
          if status.phase == .attention {
            statusBadge("exclamationmark.circle.fill", color: .orange)
          } else if status.phase == .checked {
            statusBadge("checkmark.circle.fill", color: .green)
          }
        }
      }
      .frame(width: 44, height: 44).contentShape(.rect)
      .animation(
        reduceMotion ? nil : .easeOut(duration: 0.18), value: showProgress && status.isWorking
      )
      .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: status.phase)
    }
    .accessibilityLabel("iCloud status, \(status.title)")
    .accessibilityHint("Shows pending uploads and when iCloud was last checked")
    .accessibilityIdentifier("today.syncStatus")
    .task(id: status.isWorking) {
      showProgress = false
      guard status.isWorking else { return }
      do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
      guard !Task.isCancelled else { return }
      showProgress = true
    }
  }

  private func statusBadge(_ symbol: String, color: Color) -> some View {
    Image(systemName: symbol)
      .font(.caption2.bold()).foregroundStyle(color)
      .background(.background, in: .circle).offset(x: 4, y: -3)
      .transition(.opacity)
  }
}

struct FamilySyncDetailsView: View {
  let store: LogStore
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Label(
            store.syncStatus.title,
            systemImage: store.syncNeedsAttention ? "exclamationmark.icloud" : "icloud"
          )
          .font(.headline)
          Text(store.syncMessage).font(.subheadline).foregroundStyle(.secondary)
          if store.pendingUploadCount > 0 {
            Text(verbatim: [String(localized: "Saved on this iPhone"),
                            String(localized: "\(store.pendingUploadCount) changes"),
                            String(localized: "Waiting to upload")].joined(separator: " · "))
            .font(.subheadline)
          }
          if store.syncNeedsAttention || (store.persistence.cloudEnabled && store.lastSync == nil) {
            Text(
              "Family updates may be missing. Totals include the entries currently on this iPhone."
            )
            .font(.subheadline).foregroundStyle(.secondary)
          }
        }
        Section {
          LabeledContent("Waiting to upload", value: store.pendingUploadCount.formatted())
          dateRow(String(localized: "Last upload"), date: store.lastUpload)
          dateRow(String(localized: "Last checked iCloud"), date: store.lastSync)
          Button {
            Task {
              await store.checkAccount()
              await store.syncCloud()
            }
          } label: {
            HStack {
              Label(
                store.isSyncing ? String(localized: "Checking iCloud…") : String(localized: "Sync now"),
                systemImage: "arrow.triangle.2.circlepath")
              Spacer()
              if store.isSyncing { ProgressView() }
            }.frame(minHeight: 44)
          }.disabled(store.isSyncing || !store.persistence.cloudEnabled)
        } footer: {
          Text(
            "An upload confirms receipt by iCloud. Each caregiver’s device downloads changes separately."
          )
        }
      }
      .navigationTitle("iCloud status").navigationBarTitleDisplayMode(.inline)
      .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
  }

  @ViewBuilder private func dateRow(_ title: String, date: Date?) -> some View {
    if let date {
      LabeledContent(title) {
        Text(date, format: .dateTime.month(.abbreviated).day().hour().minute())
      }
    } else {
      LabeledContent(title, value: "Not yet")
    }
  }
}

struct SummaryCards: View {
  let summary: ActivitySummary
  let unit: VolumeUnit
  var lastBottleAt: Date?
  @Environment(\.dynamicTypeSize) private var typeSize
  @ScaledMetric(relativeTo: .largeTitle) private var amountSize = 46

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      let layout = typeSize.isAccessibilitySize
        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
        : AnyLayout(HStackLayout(alignment: .lastTextBaseline, spacing: 8))
      layout {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          Text(unit.string(summary.totalML))
            .font(.system(size: amountSize, weight: .medium, design: .rounded))
            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
            .logValueTransition(value: unit.quantity(summary.totalML))
          Text(unit.label).font(.title2).foregroundStyle(LogStyle.blue)
        }.accessibilityElement(children: .combine)
        if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
        VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 3) {
          Text("Bottle intake").font(.caption)
          Text("\(summary.bottles) feeds")
            .font(.caption).foregroundStyle(LogStyle.blue)
        }
      }
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 16) { milk.fixedSize(); formula.fixedSize() }
        VStack(alignment: .leading, spacing: 8) { milk; formula }
      }
      if summary.unknownML > 0 {
        Label("\(unit.quantity(summary.unknownML)) · Split not recorded", systemImage: "questionmark.circle")
          .font(.caption).foregroundStyle(LogStyle.muted)
      }
      Divider().overlay(LogStyle.blue.opacity(0.1))
      ViewThatFits(in: .horizontal) {
        HStack(alignment: .top, spacing: 16) {
          lastBottle.fixedSize()
          Spacer(minLength: 0)
          diapers(alignment: .trailing).fixedSize()
        }
        VStack(alignment: .leading, spacing: 12) {
          lastBottle
          diapers(alignment: .leading)
        }
      }
      if summary.nursingSessions > 0 {
        Divider()
        let nursingDetails = [String(localized: "Breastfeeding"),
                              String(localized: "\(summary.nursingSessions) sessions"),
                              LogAnalytics.recordedMinutes(summary.nursingSeconds)].joined(separator: " · ")
        Label(nursingDetails, systemImage: "heart")
          .font(.caption).foregroundStyle(LogStyle.muted)
      }
    }
  }

  private var lastBottle: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("Last bottle").font(.caption).foregroundStyle(LogStyle.blue)
      if let lastBottleAt {
        Text(lastBottleAt, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
          .font(.subheadline.weight(.semibold))
      } else { Text("None recorded").font(.subheadline) }
    }.accessibilityElement(children: .combine)
  }
  private func diapers(alignment: HorizontalAlignment) -> some View {
    VStack(alignment: alignment, spacing: 4) {
      Text("\(summary.changes) diaper changes")
        .font(.subheadline.weight(.semibold)).logValueTransition(value: summary.changes)
      Text("\(summary.wet) wet · \(summary.soiled) soiled")
        .font(.caption).foregroundStyle(LogStyle.blue)
      Text("\(summary.peeOnly) pee · \(summary.pooOnly) poo · \(summary.both) both")
        .font(.caption2).foregroundStyle(LogStyle.muted)
        .accessibilityLabel("\(summary.peeOnly) pee only, \(summary.pooOnly) poo only, \(summary.both) both")
    }.accessibilityElement(children: .combine)
  }
  private var milk: some View {
    Label("Milk \(unit.string(summary.milkML))", systemImage: "drop.fill")
      .font(.caption.weight(.medium)).foregroundStyle(LogStyle.blue)
      .accessibilityLabel("Milk, \(unit.quantity(summary.milkML))")
  }
  private var formula: some View {
    Label("Formula \(unit.string(summary.formulaML))", systemImage: "circle.lefthalf.filled")
      .font(.caption.weight(.medium)).foregroundStyle(LogStyle.amber)
      .accessibilityLabel("Formula, \(unit.quantity(summary.formulaML))")
  }
}

struct CompactCareRow: View {
  let entry: RecentCareEntry
  let snapshot: FamilySnapshot
  let unit: VolumeUnit
  var connectsToNext = true
  @Environment(\.babyPalette) private var palette
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    if typeSize.isAccessibilitySize {
      switch entry {
      case .activity(let activity):
        ActivityRow(
          activity: activity, author: snapshot.caregiverName(activity.authorID),
          unit: unit, conflict: hasConflict)
      case .pumping(let pump):
        PumpActivityRow(
          pump: pump, caregiver: snapshot.caregiverName(pump.motherID),
          author: snapshot.caregiverName(pump.authorID), unit: unit, conflict: hasConflict)
      }
    } else {
      HStack(alignment: .top, spacing: 10) {
        Image(systemName: symbol).font(.body).foregroundStyle(eventTint)
          .frame(width: 32, height: 34)
          .background(eventTint.opacity(0.09), in: .ellipse)
        VStack(alignment: .leading, spacing: 4) {
          HStack(alignment: .firstTextBaseline, spacing: 8) {
            titleLabel.font(.subheadline.weight(.semibold)).fixedSize(
              horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Text(entry.occurredAt, format: .dateTime.hour().minute())
              .font(.caption).foregroundStyle(LogStyle.muted).fixedSize()
          }
          Text(detail).font(.caption).foregroundStyle(LogStyle.muted)
            .fixedSize(horizontal: false, vertical: true)
          if hasConflict {
            Label("Review edits", systemImage: "exclamationmark.circle").font(.caption)
              .foregroundStyle(.orange)
          }
          if !note.isEmpty {
            Text(note).font(.caption).foregroundStyle(LogStyle.muted).lineLimit(2)
          }
        }
      }
      .padding(.vertical, 10).frame(minHeight: 68)
      .background(alignment: .topLeading) {
        if connectsToNext {
          Rectangle().fill(LogStyle.forest.opacity(0.16)).frame(width: 1)
            .padding(.top, 47).padding(.leading, 16).accessibilityHidden(true)
        }
      }
      .contentShape(.rect).accessibilityElement(children: .combine)
    }
  }

  private var eventTint: Color {
    switch entry {
    case .pumping: LogStyle.amber
    case .activity(let value): value.payload.kind == .bottle ? LogStyle.blue : LogStyle.forest
    }
  }
  private var titleLabel: Text {
    let parts = title.components(separatedBy: " · ")
    guard parts.count > 1 else { return Text(title) }
    return Text("\(parts[0])  \(Text(parts.dropFirst().joined(separator: " · ")).foregroundStyle(eventTint))")
  }

  private var hasConflict: Bool { snapshot.record(entry.id)?.hasConflict ?? false }
  private var symbol: String {
    switch entry {
    case .activity(let activity): activity.payload.kind.symbol
    case .pumping: "drop.halffull"
    }
  }
  private var title: String {
    switch entry {
    case .pumping(let pump): return String(localized: "Pumping · \(unit.quantity(pump.totalML))")
    case .activity(let activity):
      switch activity.payload {
      case .bottle(let bottle):
        if bottle.unknownML > 0 { return String(localized: "Bottle · \(unit.quantity(bottle.totalML))") }
        if bottle.formulaML == 0 { return String(localized: "Bottle · \(unit.quantity(bottle.milkML)) milk") }
        if bottle.milkML == 0 { return String(localized: "Bottle · \(unit.quantity(bottle.formulaML)) formula") }
        return String(localized: "Bottle · \(unit.quantity(bottle.totalML))")
      case .diaper(let diaper): return diaper.title
      case .careNote: return String(localized: "Care note")
      default: return String(localized: "\(activity.payload.kind.title) · \(activity.detail(unit: unit))")
      }
    }
  }
  private var detail: String {
    switch entry {
    case .pumping(let pump):
      var text = String(localized: "\(snapshot.caregiverName(pump.motherID)) · Family pumping")
      if pump.authorID != pump.motherID {
        text += String(localized: " · Recorded by \(snapshot.caregiverName(pump.authorID))")
      }
      if let minutes = pump.minutes { text += String(localized: " · \(minutes.formatted()) min") }
      return text
    case .activity(let activity):
      let author = snapshot.caregiverName(activity.authorID)
      if case .bottle(let bottle) = activity.payload {
        if bottle.unknownML > 0 { return String(localized: "Split not recorded · \(author)") }
        if bottle.milkML > 0 && bottle.formulaML > 0 {
          return
            String(localized: "\(unit.quantity(bottle.milkML)) milk · \(unit.quantity(bottle.formulaML)) formula · \(author)")
        }
      }
      return author
    }
  }
  private var note: String {
    switch entry {
    case .pumping(let pump): pump.note
    case .activity(let activity): activity.note
    }
  }
}

#if DEBUG
private struct ChildAgeTitlePreview: View {
  var daysOld = 34
  var name = "Robin"

  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    return calendar
  }

  var body: some View {
    let calendar = self.calendar
    let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 11))!
    let child = ChildProfile(
      familyID: UUID(), name: name,
      birthDate: calendar.date(byAdding: .day, value: -daysOld, to: now),
      gestationalAgeAtBirthDays: 35 * 7 + 4)
    CompactChildTitle(
      children: [child], child: child, now: now, calendar: calendar,
      preferCompact: true, select: { _ in })
      .padding(24)
      .background(LogStyle.canvas)
  }
}

#Preview("Age header · Months", traits: .fixedLayout(width: 375, height: 200)) {
  ChildAgeTitlePreview().preferredColorScheme(.dark)
}

#Preview("Age header · Newborn", traits: .fixedLayout(width: 375, height: 200)) {
  ChildAgeTitlePreview(daysOld: 27).preferredColorScheme(.light)
}

#Preview("Age header · Large text", traits: .fixedLayout(width: 375, height: 500)) {
  ChildAgeTitlePreview(name: "Alexandra Beatrice")
    .preferredColorScheme(.light).environment(\.dynamicTypeSize, .accessibility5)
}
#endif
