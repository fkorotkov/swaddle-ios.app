import SwiftUI

struct LogRoute: Identifiable {
  let id = UUID()
  var kind: ActivityKind?
  var childID: UUID?
  var activity: Activity?
  var pump: PumpSession?
  var record: ProjectedRecord?
  var presentationSource: LogPresentationSource?
  var isPump: Bool { kind == nil }
}

struct TodayView: View {
  @Environment(\.babyPalette) private var palette
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.scenePhase) private var scenePhase
  @Namespace private var editorTransition
  @Bindable var store: LogStore
  var openRequest: UUID? = nil
  var openingMotion: CocoonOpeningSession? = nil
  var settingsPresentation: Binding<Bool>? = nil
  var isCurrentTab = true
  var openMilestones: ((Int) -> Void)? = nil
  private enum Destination: Hashable { case siri, overlappingFeeds, pumping(UUID) }
  @State private var navigationPath: [Destination] = []
  @State private var scrollPosition = ScrollPosition(edge: .top)
  @State private var route: LogRoute?
  @State private var calendarDay = false
  @State private var now = Date.now
  @State private var saveMotionID: UUID?
  @State private var importing = false
  @State private var showingSync = false
  @State private var importPresentationSource: LogPresentationSource?
  @State private var birthday: AgeCelebration?
  @State private var birthdayMotion: UUID?
  @Environment(\.dynamicTypeSize) private var typeSize
  private var child: ChildProfile? { store.selectedChild }
  private var calendar: Calendar {
    var value = Calendar(identifier: .gregorian)
    value.timeZone =
      TimeZone(identifier: store.snapshot.family?.timeZoneIdentifier ?? "") ?? .current
    return value
  }
  private var start: Date {
    if calendarDay {
      var calendar = Calendar.current
      calendar.timeZone =
        TimeZone(identifier: store.snapshot.family?.timeZoneIdentifier ?? "") ?? .current
      return calendar.startOfDay(for: now).addingTimeInterval(-0.001)
    }
    return now.addingTimeInterval(-86400)
  }
  private var entries: [Activity] {
    // Resolving the selected child projects the roster. Do it once, not once
    // per activity while SwiftUI is preparing a save transition.
    let childID = child?.id
    return store.snapshot.activities.filter { $0.childID == childID }
  }
  private var pumpingSummary: PumpingSummary? {
    PumpingSummary(
      snapshot: store.snapshot, caregiverID: store.caregiverID, start: start, end: now)
  }
  private var eligibleBirthday: AgeCelebration? {
    child.flatMap { AgeCelebration(child: $0, at: now, calendar: calendar) }
  }
  private var celebrationCanPlay: Bool {
    isCurrentTab && navigationPath.isEmpty && route == nil && !importing && !showingSync
      && settingsPresentation?.wrappedValue != true && store.siriNavigation == nil
  }
  var body: some View {
    // Reuse projections within this render. Repeating them for each section
    // becomes visible during save animations once a family has months of history.
    let child = self.child
    let entries = self.entries
    let recentCare = child.map { store.snapshot.recentCare(for: $0.id) } ?? []
    let visibleCare = Array(recentCare.prefix(100))
    let dayGroups = Dictionary(grouping: visibleCare) { calendar.startOfDay(for: $0.occurredAt) }
      .map { RecentCareDay(date: $0.key, entries: $0.value) }
      .sorted { $0.date > $1.date }
    let overlapping =
      child.map {
        LogRules.overlappingNursing(in: entries, childID: $0.id, now: now)
      } ?? []
    NavigationStack(path: $navigationPath) {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          identity
          if let child {
            VStack(spacing: 16) {
              summaryControls
              SummaryCards(
                summary: ActivitySummary(
                  activities: entries, childID: child.id, start: start, end: now),
                unit: store.volumeUnit,
                lastBottleAt: entries.filter { $0.payload.kind == .bottle && $0.occurredAt <= now }.map(\.occurredAt).max()
              )
              .modifier(
                FeedingReportContext(
                  store: store, child: child, period: calendarDay ? .today : .last24Hours, now: now))
            }.modifier(CocoonSummarySurface(saveID: saveMotionID))
            if let pumpingSummary {
              NavigationLink(value: Destination.pumping(pumpingSummary.caregiver.id)) {
                PumpingSummaryCard(summary: pumpingSummary, unit: store.volumeUnit)
              }
              .buttonStyle(.plain)
              .accessibilityHint("Opens your pumping history")
              .accessibilityIdentifier("today.pumpingSummary")
            }
            quickActions(child)
            quickDiapers(child)
            if !overlapping.isEmpty {
              NavigationLink(value: Destination.overlappingFeeds) {
                Label(
                  "Some breastfeeding sessions overlap. Review the entries.",
                  systemImage: "clock.badge.questionmark"
                )
                .font(.callout).frame(maxWidth: .infinity, alignment: .leading)
              }
            }
            ForEach(entries.filter { !$0.payload.isComplete }) { activity in
              Button {
                show(activity)
              } label: {
                LogCard(color: palette.surface) {
                  HStack {
                    Image(systemName: "timer").font(.title2)
                    VStack(alignment: .leading, spacing: 5) {
                      Text("Feeding in progress").font(.headline)
                      Text(activity.detail(unit: store.volumeUnit, at: now)).font(.subheadline)
                    }
                    Spacer()
                    Image(systemName: "chevron.forward")
                  }
                }
              }.buttonStyle(.plain)
            }
            HStack {
              Text("The little moments").font(LogStyle.heading(.title3)).accessibilityAddTraits(.isHeader)
              Spacer()
              Menu {
                moreActivities(child)
              } label: {
                Label("More", systemImage: "plus").font(.caption.weight(.semibold))
                  .frame(minWidth: 44, minHeight: 44).contentShape(.rect)
              }.accessibilityLabel("More activities").disabled(!store.canEdit)
            }
            if recentCare.isEmpty {
              ContentUnavailableView(
                "A fresh page", systemImage: "leaf",
                description: Text(
                  "Your first entry will appear here. Start with whatever just happened."))
            } else {
              let searchDocuments =
                store.siriDiscoveryEnabled
                ? Dictionary(
                  uniqueKeysWithValues: CareSearchCatalog.documents(
                    in: store.snapshot, recordIDs: Set(visibleCare.map(\.id))
                  ).map {
                    ($0.key.recordID, $0)
                  }) : [:]
              LazyVStack(spacing: 0) {
                ForEach(dayGroups) { group in
                  VStack(alignment: .leading, spacing: 0) {
                    if group.date != calendar.startOfDay(for: now) {
                      Text(dayTitle(group.date)).font(.subheadline.weight(.semibold))
                        .padding(.top, 14).padding(.bottom, 4)
                        .accessibilityAddTraits(.isHeader)
                    }
                    ForEach(group.entries) { entry in
                      VStack(spacing: 0) {
                        Button {
                          show(entry)
                        } label: {
                          CompactCareRow(
                            entry: entry, snapshot: store.snapshot, unit: store.volumeUnit,
                            connectsToNext: entry.id != group.entries.last?.id)
                        }.buttonStyle(.plain)
                          .modifier(
                            CareRecordContext(document: searchDocuments[entry.id], store: store))
                        if typeSize.isAccessibilitySize { Divider() }
                      }.transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: -6)))
                    }
                  }
                }
              }.animation(reduceMotion ? nil : .smooth(duration: 0.28), value: store.undoID)
            }
          } else {
            ContentUnavailableView(
              "Add a child", systemImage: "person.crop.circle.badge.plus",
              description: Text("Open Settings to add a child to your shared log."))
          }
        }.padding(.horizontal, 22).padding(.top, 8)
          .padding(.bottom, typeSize.isAccessibilitySize ? 180 : 96)
      }
      .scrollPosition($scrollPosition)
      .refreshable { await store.syncCloud() }
      .background(LogStyle.canvas).navigationTitle("").navigationBarTitleDisplayMode(.inline)
      .environment(\.calendar, calendar).environment(\.timeZone, calendar.timeZone)
      .toolbarVisibility(.hidden, for: .navigationBar)
      .sheet(isPresented: $showingSync) {
        FamilySyncDetailsView(store: store).presentationDetents([.medium, .large])
      }
      .navigationDestination(for: Destination.self) { destination in
        Group {
        switch destination {
        case .siri:
          SiriSetupView(
            store: store,
            childName: store.snapshot.children.count == 1 ? String(localized: "my baby") : child?.name ?? String(localized: "my baby"))
        case .overlappingFeeds:
          List(entries.filter { overlapping.contains($0.id) }) { activity in
            Button {
              show(activity)
            } label: {
              ActivityRow(
                activity: activity, author: store.snapshot.caregiverName(activity.authorID),
                unit: store.volumeUnit)
            }.buttonStyle(.plain)
          }.navigationTitle("Review overlapping feeds")
        case .pumping(let caregiverID):
          if let caregiver = store.snapshot.pumpingHistoryCaregivers.first(where: {
            $0.id == store.snapshot.canonicalCaregiverID(caregiverID)
          }) {
            PumpHistoryView(store: store, mother: caregiver)
              .navigationBarTitleDisplayMode(.large)
          } else {
            ContentUnavailableView("Pumping profile unavailable", systemImage: "drop.halffull")
          }
        }
        }.toolbarVisibility(.visible, for: .navigationBar)
      }
      .sheet(isPresented: $importing) {
        CareImportView(store: store)
          .logEditorTransition(source: importPresentationSource, namespace: editorTransition)
      }
      .sheet(item: $route) { route in
        Group {
          if route.isPump {
            PumpEditor(store: store, existing: route.pump)
          } else if route.kind == .breastfeeding {
            NursingEditor(store: store, childID: route.childID!, existing: route.activity)
          } else {
            ActivityEditor(store: store, route: route)
          }
        }.logEditorTransition(source: route.presentationSource, namespace: editorTransition)
      }
      .overlay(alignment: .bottom) {
        Group {
          if let toast = store.toast {
            let celebration = store.pumpingCelebration
            SaveConfirmation(
              message: celebration == nil ? toast : String(localized: "A new personal record"), undoID: store.undoID,
              celebrationDetail: celebration.map { String(localized: "\(store.volumeUnit.quantity($0.totalML)) pumped") }, undo: {
              do { try store.undo() } catch { store.report(error) }
            }, dismiss: { store.toast = nil })
            .padding(.horizontal, 16).padding(.bottom, 12)
            .transition(.opacity)
          } else if let birthday {
            BirthdayNote(celebration: birthday) { months in
              self.birthday = nil
              openMilestones?(months)
            } dismiss: { self.birthday = nil }
            .padding(.horizontal, 16).padding(.bottom, 12)
            .transition(.opacity)
          }
        }.animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: store.toast != nil)
      }
      .task {
        while !Task.isCancelled {
          now = .now
          try? await Task.sleep(for: .seconds(30))
        }
      }
      .sensoryFeedback(.success, trigger: store.undoID) { _, new in new != nil }
    }
    .modifier(CareCelebrationMotion(trigger: birthday == nil ? nil : birthdayMotion,
                                   kind: .birthday, canPlay: celebrationCanPlay))
    .modifier(PumpingRecordPresentation(store: store, canPlay: celebrationCanPlay,
                                       showsConfirmation: false))
    .onChange(of: eligibleBirthday?.id, initial: true) { presentBirthdayIfNeeded() }
    .onChange(of: isCurrentTab) {
      if isCurrentTab { presentBirthdayIfNeeded() } else { birthday = nil }
    }
    .onChange(of: celebrationCanPlay) {
      if celebrationCanPlay { presentBirthdayIfNeeded() } else { birthday = nil }
    }
    .onChange(of: store.undoID) { if store.undoID != nil { birthday = nil } }
    .task(id: birthday?.id) {
      guard birthday != nil, !UIAccessibility.isVoiceOverRunning,
            !typeSize.isAccessibilitySize else { return }
      try? await Task.sleep(for: .seconds(12))
      guard !Task.isCancelled else { return }
      birthday = nil
    }
    // Saves, edits, imports, and iCloud updates must be included immediately,
    // including entries made after the last 30-second clock refresh.
    .onChange(of: store.snapshot) { now = .now }
    .onChange(of: store.undoID) { _, id in
      if id != nil { openingMotion?.settle() }
      // A pumping save must not suggest that the child's intake changed.
      // The timeline and confirmation handle all local saves; this fold belongs
      // specifically to the bottle/diaper summary. Background sync stays still.
      if let id, let record = store.snapshot.record(id),
        case .activity(let activity) = record.revision.value,
        activity.childID == child?.id,
        activity.payload.kind == .bottle || activity.payload.kind == .diaper
      {
        saveMotionID = id
      }
    }
    .onChange(of: scenePhase) { _, phase in
      if phase == .active { now = .now; presentBirthdayIfNeeded() }
      else { birthday = nil }
    }
    .onChange(of: route?.id) { _, routeID in if routeID != nil { openingMotion?.settle() } }
    .onChange(of: navigationPath) { _, path in if !path.isEmpty { openingMotion?.settle() } }
    .onChange(of: importing) { _, presented in if presented { openingMotion?.settle() } }
    .onChange(of: openRequest) {
      navigationPath.removeAll()
      calendarDay = false
      now = .now
      scrollPosition.scrollTo(edge: .top)
    }
  }
  private func presentBirthdayIfNeeded() {
    guard scenePhase == .active, celebrationCanPlay, store.toast == nil else { return }
    guard let eligibleBirthday else { birthday = nil; return }
    if let birthday, birthday.id != eligibleBirthday.id { self.birthday = nil }
    guard store.claimAgeCelebration(eligibleBirthday) else { return }
    birthday = eligibleBirthday
    birthdayMotion = UUID()
  }
  private func show(_ activity: Activity) {
    route = LogRoute(
      kind: activity.payload.kind, childID: activity.childID, activity: activity,
      record: store.snapshot.record(activity.id))
  }
  private func show(_ entry: RecentCareEntry) {
    switch entry {
    case .activity(let activity): show(activity)
    case .pumping(let pump): route = LogRoute(pump: pump, record: store.snapshot.record(pump.id))
    }
  }
  private var identity: some View {
    Group {
      if typeSize.isAccessibilitySize {
        stackedIdentity
      } else {
        ViewThatFits(in: .horizontal) {
          HStack(spacing: 12) {
            childTitle.fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 0)
            identityActions
          }
          stackedIdentity
        }
      }
    }.padding(.bottom, 4)
  }
  private var stackedIdentity: some View {
    VStack(alignment: .leading, spacing: 12) {
      childTitle
      identityActions
    }
  }
  private var childTitle: some View {
    CompactChildTitle(
      children: store.snapshot.children, child: child, now: now, calendar: calendar,
      openingMotion: openingMotion, preferCompact: true,
      ageCelebration: eligibleBirthday, ageCelebrationTrigger: birthdayMotion
    ) {
      store.selectedChildID = $0
    }
  }
  private var identityActions: some View {
    HStack(spacing: 10) {
      NavigationLink(value: Destination.siri) {
        Image(systemName: "waveform").frame(width: 44, height: 44)
      }.buttonStyle(.plain).logGlass(in: .circle, interactive: true)
        .accessibilityLabel("Siri, log and ask hands free")
        .accessibilityIdentifier("today.siri")
      FamilySyncIndicator(status: store.syncStatus) { showingSync = true }
        .buttonStyle(.plain).logGlass(in: .circle, interactive: true)
      SettingsButton(store: store, presentation: settingsPresentation)
        .buttonStyle(.plain).logGlass(in: .circle, interactive: true)
    }.foregroundStyle(LogStyle.forest)
  }
  private var summaryControls: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 16) {
        summaryPeriod.fixedSize()
        Spacer(minLength: 0)
        VolumeUnitPicker(unit: $store.volumeUnit)
      }
      VStack(alignment: .leading, spacing: 4) {
        summaryPeriod
        VolumeUnitPicker(unit: $store.volumeUnit)
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
    }.foregroundStyle(LogStyle.blue)
  }
  private var summaryPeriod: some View {
    Menu {
      Picker("Summary period", selection: $calendarDay) {
        Text("Last 24 hours").tag(false)
        Text("Today").tag(true)
      }
    } label: {
      HStack(spacing: 6) {
        Text(calendarDay ? String(localized: "Today") : String(localized: "Last 24 hours")).font(.caption.weight(.semibold)).textCase(.uppercase).tracking(1.2)
        Image(systemName: "chevron.down").font(.caption2.bold())
      }.frame(minHeight: 44)
    }
    .accessibilityLabel("Summary period, \(calendarDay ? String(localized: "Today") : String(localized: "Last 24 hours"))")
    .accessibilityIdentifier("today.summaryPeriod")
  }
  @ViewBuilder private func moreActivities(_ child: ChildProfile) -> some View {
    Button("Record breastfeeding", systemImage: "heart") { openNursing(child) }
    Button("Paste care notes", systemImage: "text.bubble.fill") {
      importPresentationSource = reduceMotion ? nil : .importNotes
      importing = true
    }
    Button("Custom diaper", systemImage: "slider.horizontal.3") {
      route = LogRoute(kind: .diaper, childID: child.id)
    }
    Button("Add a care note", systemImage: "note.text") {
      route = LogRoute(kind: .careNote, childID: child.id)
    }
    Button("Record weight", systemImage: "scalemass") {
      route = LogRoute(kind: .weight, childID: child.id)
    }
    Button("Record length / height", systemImage: "ruler") {
      route = LogRoute(kind: .length, childID: child.id)
    }
    Button("Record head circumference", systemImage: "person.crop.circle") {
      route = LogRoute(kind: .headCircumference, childID: child.id)
    }
    Button("Record temperature", systemImage: "thermometer.medium") {
      route = LogRoute(kind: .temperature, childID: child.id)
    }
  }
  private func dayTitle(_ date: Date) -> String {
    if date == calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) {
      return String(localized: "Yesterday")
    }
    return date.formatted(.dateTime.month(.abbreviated).day().year())
  }
  private func quickActions(_ child: ChildProfile) -> some View {
    let layout = typeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
    return layout {
      Button {
        route = LogRoute(kind: .bottle, childID: child.id,
                         presentationSource: reduceMotion ? nil : .bottle)
      } label: {
        Label("Bottle", systemImage: "waterbottle.fill").frame(maxWidth: .infinity, minHeight: 44)
      }.buttonStyle(.glassProminent).tint(LogStyle.blue).foregroundStyle(LogStyle.canvas)
        .matchedTransitionSource(id: LogPresentationSource.bottle, in: editorTransition)
        .accessibilityLabel("Record bottle").accessibilityIdentifier("today.bottle")
      Button {
        route = LogRoute(childID: nil, presentationSource: reduceMotion ? nil : .pump)
      } label: {
        Label("Pumping", systemImage: "drop").frame(maxWidth: .infinity, minHeight: 44)
      }.buttonStyle(.glass).foregroundStyle(LogStyle.amber)
        .matchedTransitionSource(id: LogPresentationSource.pump, in: editorTransition)
        .accessibilityLabel("Record pumping").accessibilityIdentifier("today.pump")
    }.font(.subheadline.weight(.semibold)).buttonBorderShape(.capsule).disabled(!store.canEdit)
  }
  private func openNursing(_ child: ChildProfile) {
    let current = entries.first {
      guard case .nursing(let nursing) = $0.payload else { return false }
      return !$0.payload.isComplete && nursing.caregiverID == store.caregiverID
    }
    route = LogRoute(kind: .breastfeeding, childID: child.id, activity: current)
  }
  private func quickDiapers(_ child: ChildProfile) -> some View {
    let layout =
      typeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 6))
    return layout {
      diaperButtons(child)
      customDiaper(child)
    }.disabled(!store.canEdit)
  }
  @ViewBuilder private func diaperButtons(_ child: ChildProfile) -> some View {
    ForEach(
      [Diaper(pee: true, poo: false), Diaper(pee: false, poo: true), Diaper(pee: true, poo: true)],
      id: \.title
    ) { diaper in
      Button {
        do {
          try store.save(
            .activity(
              Activity(
                familyID: child.familyID, childID: child.id, occurredAt: .now,
                authorID: store.caregiverID, payload: .diaper(diaper))))
          store.toast = String(localized: "\(diaper.title) saved for \(child.name)")
          now = .now
        } catch { store.report(error) }
      } label: {
        Text(diaper.pee && diaper.poo ? String(localized: "Both") : diaper.pee ? String(localized: "Pee") : String(localized: "Poo"))
          .font(.subheadline).frame(minWidth: 44, maxWidth: .infinity, minHeight: 44)
          .contentShape(.rect)
      }.buttonStyle(.glass).buttonBorderShape(.capsule).foregroundStyle(LogStyle.forest)
        .accessibilityLabel("Record \(diaper.title.lowercased()) for \(child.name) now")
    }
  }
  private func customDiaper(_ child: ChildProfile) -> some View {
    Button {
      route = LogRoute(kind: .diaper, childID: child.id)
    } label: {
      Text("Custom").font(.subheadline).fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 10).frame(minWidth: 44, maxWidth: .infinity, minHeight: 44)
        .contentShape(.rect)
    }.buttonStyle(.glass).buttonBorderShape(.capsule).foregroundStyle(LogStyle.forest)
      .accessibilityLabel("Record a custom diaper for \(child.name)")
      .accessibilityHint("Choose the time, contents, and an optional note before saving")
  }
}

private struct RecentCareDay: Identifiable {
  var id: Date { date }
  let date: Date
  let entries: [RecentCareEntry]
}

struct MetricLabel: View {
  let title: String
  let value: String
  let symbol: String
  @Environment(\.dynamicTypeSize) private var typeSize
  var body: some View {
    Group {
      if typeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 4) {
          Label(title, systemImage: symbol).foregroundStyle(.secondary)
          Text(value).fontWeight(.semibold).monospacedDigit()
            .logValueTransition(value: value)
        }.fixedSize(horizontal: false, vertical: true)
      } else {
        HStack(spacing: 6) {
          Image(systemName: symbol).imageScale(.small)
          Text(title).foregroundStyle(.secondary)
          Text(value).fontWeight(.semibold).monospacedDigit()
            .logValueTransition(value: value)
        }
      }
    }.font(.subheadline).accessibilityElement(children: .combine)
  }
}
struct ActivityRow: View {
  @Environment(\.babyPalette) private var palette
  let activity: Activity
  let author: String
  let unit: VolumeUnit
  var conflict = false
  @Environment(\.dynamicTypeSize) private var typeSize
  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      if !typeSize.isAccessibilitySize {
        Image(systemName: activity.payload.kind.symbol).font(.body).foregroundStyle(palette.accent)
          .frame(width: 42, height: 42).background(
            activity.payload.kind == .diaper ? LogStyle.apricot : palette.surface, in: .circle)
      }
      VStack(alignment: .leading, spacing: 5) {
        let layout =
          typeSize.isAccessibilitySize
          ? AnyLayout(VStackLayout(alignment: .leading, spacing: 5))
          : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        layout {
          Text(
            activity.payload.kind == .diaper
              ? activity.detail(unit: unit) : activity.payload.kind.title
          ).font(.headline)
          if !typeSize.isAccessibilitySize { Spacer(minLength: 4) }
          Text(activity.occurredAt, format: .dateTime.hour().minute()).font(.caption)
            .foregroundStyle(.secondary)
        }
        if activity.payload.kind != .diaper {
          Text(activity.detail(unit: unit)).font(.subheadline).foregroundStyle(.secondary)
            .lineLimit(typeSize.isAccessibilitySize ? nil : 3)
        }
        Text(
          "\(author) · \(activity.occurredAt.formatted(date: .abbreviated, time: .omitted))\(conflict ? String(localized: " · Review edits") : "")"
        )
        .font(.caption).foregroundStyle(.secondary)
        if !activity.note.isEmpty && activity.payload.kind != .careNote {
          Text(activity.note).font(.caption).lineLimit(2)
        }
      }.fixedSize(horizontal: false, vertical: true)
    }.padding(.vertical, 14).contentShape(.rect).accessibilityElement(children: .combine)
  }
}

struct PumpActivityRow: View {
  @Environment(\.babyPalette) private var palette
  @Environment(\.dynamicTypeSize) private var typeSize
  let pump: PumpSession
  let caregiver: String
  let author: String
  let unit: VolumeUnit
  var conflict = false

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      if !typeSize.isAccessibilitySize {
        Image(systemName: "drop.halffull").font(.body).foregroundStyle(palette.accent)
          .frame(width: 42, height: 42).background(LogStyle.apricot, in: .circle)
      }
      VStack(alignment: .leading, spacing: 5) {
        let layout =
          typeSize.isAccessibilitySize
          ? AnyLayout(VStackLayout(alignment: .leading, spacing: 5))
          : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        layout {
          Text("Pumping").font(.headline)
          if !typeSize.isAccessibilitySize { Spacer(minLength: 4) }
          Text(pump.occurredAt, format: .dateTime.hour().minute()).font(.caption).foregroundStyle(
            .secondary)
        }
        Text("\(caregiver) · \(unit.quantity(pump.totalML)) pumped")
          .font(.subheadline).foregroundStyle(.secondary)
        if let minutes = pump.minutes {
          Text("\(minutes.formatted()) min").font(.caption).foregroundStyle(.secondary)
        }
        Text(
          "Recorded by \(author) · \(pump.occurredAt.formatted(date: .abbreviated, time: .omitted))\(conflict ? String(localized: " · Review edits") : "")"
        )
        .font(.caption).foregroundStyle(.secondary)
        if !pump.note.isEmpty {
          Text(pump.note).font(.caption).lineLimit(typeSize.isAccessibilitySize ? nil : 2)
        }
      }.fixedSize(horizontal: false, vertical: true)
    }.padding(.vertical, 14).contentShape(.rect).accessibilityElement(children: .combine)
  }
}

#if DEBUG
  private struct RecentPumpingPreview: View {
    var body: some View {
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          Text("Recent activity").font(.title2.bold()).padding(.bottom, 8)
          let caregiverID = UUID()
          let familyID = UUID()
          let pump = PumpSession(
            familyID: familyID, motherID: caregiverID, occurredAt: .now,
            authorID: UUID(), totalML: 135, unit: .ml, minutes: 20, note: "Left 75 mL, right 60 mL")
          PumpActivityRow(pump: pump, caregiver: "Elnara", author: "Fedor", unit: .ml)
          Divider().padding(.leading, 56)
          ActivityRow(
            activity: Activity(
              familyID: familyID, childID: UUID(), occurredAt: .now.addingTimeInterval(-1800),
              authorID: caregiverID,
              payload: .bottle(Bottle(milkML: 90, formulaML: 0, unit: .ml))), author: "Elnara",
            unit: .ml)
          Divider().padding(.leading, 56)
          PumpActivityRow(
            pump: pump, caregiver: "Alexandra", author: "Alexandra", unit: .oz, conflict: true)
        }.padding(22)
      }.background(LogStyle.canvas)
    }
  }

  #Preview("Recent pumping") { RecentPumpingPreview() }
  #Preview("Recent pumping · Large dark") {
    RecentPumpingPreview().preferredColorScheme(.dark).environment(
      \.dynamicTypeSize, .accessibility3)
  }
#endif
