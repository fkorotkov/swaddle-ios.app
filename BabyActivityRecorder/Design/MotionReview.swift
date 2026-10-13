#if DEBUG && targetEnvironment(simulator)
  import SwiftUI

  /// Explicit, Simulator-only fixtures. Never opens the shared store or publishes widgets.
  enum MotionReview {
    static let arguments = ProcessInfo.processInfo.arguments
    static var isRequested: Bool { arguments.contains("--motion-review") }
    static func has(_ flag: String) -> Bool { arguments.contains(flag) }

    @MainActor static func makeStore() -> LogStore {
      let suite = "motion-review.\(UUID())"
      let defaults = UserDefaults(suiteName: suite)!
      let store = LogStore(
        persistence: PersistenceController(inMemory: true),
        defaults: defaults, publishesWidgets: false)
      if has("--welcome") { return store }
      do {
        let pumper = !has("--helper")
        try store.createFamily(
          childName: has("--long-name") ? "Alexandra Beatrice" : "Robin",
          caregiverName: "Sam", mother: pumper, unit: .oz)
        guard var child = store.selectedChild else { return store }
        child.birthDate = .now.addingTimeInterval(
          -Double((has("--long-history") ? 180 : 24) * 86400))
        if has("--milestones") {
          child.birthDate = .now.addingTimeInterval(-Double((has("--milestone-current") ? 90 : 42) * 86400))
        }
        // One coherent, fictional family across the App Store captures. This
        // fixture is compiled only into Simulator debug builds.
        if has("--store-listing") {
          child.birthDate = Calendar.current.date(byAdding: .day, value: -70, to: .now)
        }
        if has("--milestones-no-birth") { child.birthDate = nil }
        if let argument = arguments.first(where: { $0.hasPrefix("--birthday-week=") }),
           let week = Int(argument.dropFirst("--birthday-week=".count)), (1...4).contains(week) {
          var calendar = Calendar(identifier: .gregorian)
          calendar.timeZone = TimeZone(identifier: store.snapshot.family!.timeZoneIdentifier)!
          child.birthDate = calendar.date(byAdding: .day, value: -week * 7, to: .now)
        }
        child.gender = has("--gender-unset") ? nil : .boy
        child.growthReferenceSex = has("--growth-unset") ? nil : .male
        if has("--preterm") { child.gestationalAgeAtBirthDays = 35 * 7 + 4 }
        if has("--growth-comparisons") {
          child.gestationalAgeAtBirthDays = 35 * 7 + 4
          child.birthDate = Calendar.current.date(byAdding: .day, value: -36, to: .now)
        }
        if has("--growth-transition") {
          child.gestationalAgeAtBirthDays = 35 * 7 + 4
          child.birthDate = Calendar.current.date(byAdding: .day, value: -201, to: .now)
        }
        if has("--preterm-too-early") {
          child.gestationalAgeAtBirthDays = 22 * 7
        }
        try store.save(.child(child))
        if var me = store.snapshot.caregivers.first(where: { $0.id == store.caregiverID }) {
          me.sex = arguments.first(where: { $0.hasPrefix("--illustration-sex=") })
              .flatMap({ CaregiverSex(rawValue: String($0.dropFirst("--illustration-sex=".count))) })
          try store.save(.caregiver(me))
        }
        let alex = Caregiver(familyID: child.familyID, name: "Alex", isMother: true)
        try store.save(.caregiver(alex))
        if (has("--milestones") || has("--store-listing")), !has("--empty") {
          let skill = MilestoneCatalog.skill("cdc-2-smilestalk2")!
          try store.save(.milestone(MilestoneObservation(
            familyID: child.familyID, childID: child.id, skillID: skill.id,
            sourceVersion: skill.sourceVersion, skillTitle: skill.title, status: .seen,
            firstNoticedAt: .now.addingTimeInterval(-2 * 86400), note: "A smile back during our morning cuddle.",
            authorID: store.caregiverID, recordedAt: .now.addingTimeInterval(-86400))))
          try store.save(.milestone(MilestoneObservation(
            familyID: child.familyID, childID: child.id, skillID: skill.id,
            sourceVersion: skill.sourceVersion, skillTitle: skill.title, status: .unsure,
            note: "I’m watching for it too.", authorID: alex.id, recordedAt: .now.addingTimeInterval(-3 * 86400))))
        }
        if has("--twins") {
          try store.save(.child(ChildProfile(familyID: child.familyID, name: "Jamie")))
        }
        if !has("--empty") {
          let now = Date.now
          let amounts = [150, 120, 105, 120, 90, 105, 120, 75]
          let formula = [0, 15, 0, 30, 0, 0, 15, 0]
          for day in 0..<14 {
            for index in amounts.indices {
              let time = now.addingTimeInterval(-Double(day * 86400 + index * 10800 + 2700))
              let variation = has("--store-listing") && day > 0 ? ((day + index) % 5 - 2) * 15 : 0
              try store.save(
                .activity(
                  Activity(
                    familyID: child.familyID, childID: child.id, occurredAt: time,
                    authorID: index.isMultiple(of: 2) ? store.caregiverID : alex.id,
                    payload: .bottle(
                      Bottle(
                        milkML: Decimal(amounts[index] - formula[index] + variation),
                        formulaML: Decimal(formula[index]), unit: .oz)))),
                rememberBottle: day == 0 && index == 0)
            }
            for index in 0..<4 {
              try store.save(
                .pumping(
                  PumpSession(
                    familyID: child.familyID, motherID: pumper ? store.caregiverID : alex.id,
                    occurredAt: now.addingTimeInterval(-Double(day * 86400 + index * 18000 + 5400)),
                    authorID: alex.id, totalML: Decimal(180 + ((day + index) % 4) * 15), unit: .oz))
              )
            }
          }
          for index in 0..<4 {
            try store.save(
              .activity(
                Activity(
                  familyID: child.familyID, childID: child.id,
                  occurredAt: now.addingTimeInterval(-Double(index * 18000 + 4500)),
                  authorID: alex.id, payload: .diaper(Diaper(pee: true, poo: index == 0)))))
          }
          for (day, grams) in [(20, 3360), (16, 3290), (12, 3420), (7, 3600), (0, 3860)] {
            let weight = has("--growth-comparisons") && day == 0 ? 4180 : grams + (has("--store-listing") ? 1500 : 0)
            try store.save(
              .activity(
                Activity(
                  familyID: child.familyID, childID: child.id,
                  occurredAt: now.addingTimeInterval(-Double(day * 86400 + 3600)),
                  authorID: store.caregiverID, payload: .weight(
                    grams: Decimal(has("--growth-transition") ? weight + 3500 : weight), unit: "kg")))
            )
          }
          for (day, lengthCM, headCM) in [(20, 46.0, 33.4), (12, 47.3, 34.3), (7, 49.0, 35.0), (0, 50.5, 36.5)] {
            let at = now.addingTimeInterval(-Double(day * 86400 + 3600))
            for payload: ActivityPayload in [.length(centimeters: Decimal(lengthCM + (has("--store-listing") ? 8 : 0)), unit: .cm, position: .lyingDown),
              .headCircumference(centimeters: Decimal(headCM + (has("--store-listing") ? 3 : 0)), unit: .cm)] {
              try store.save(.activity(Activity(familyID: child.familyID, childID: child.id,
                occurredAt: at, authorID: store.caregiverID, payload: payload)))
            }
          }
          if has("--long-history") {
            // Bulk-seed older fictional history so the review measures
            // normal interaction, not thousands of individual imports.
            var olderBottles: [Activity] = []
            var olderPumps: [PumpSession] = []
            for day in 14..<180 {
              for index in amounts.indices {
                let time = now.addingTimeInterval(-Double(day * 86400 + index * 10800 + 2700))
                let bottle = Bottle(
                  milkML: Decimal(amounts[index] - formula[index]),
                  formulaML: Decimal(formula[index]), unit: .oz)
                olderBottles.append(
                  Activity(
                    familyID: child.familyID, childID: child.id,
                    occurredAt: time, authorID: store.caregiverID,
                    payload: .bottle(bottle)))
              }
              for index in 0..<4 {
                let time = now.addingTimeInterval(-Double(day * 86400 + index * 18000 + 5400))
                olderPumps.append(
                  PumpSession(
                    familyID: child.familyID,
                    motherID: pumper ? store.caregiverID : alex.id,
                    occurredAt: time, authorID: store.caregiverID,
                    totalML: Decimal(180 + ((day + index) % 4) * 15), unit: .oz))
              }
            }
            _ = try store.importActivities(olderBottles)
            _ = try store.importPumpingSessions(olderPumps)
          }
        }
        store.selectedChildID = child.id
        if has("--ml") { store.volumeUnit = .ml }
        store.toast = nil
      } catch { assertionFailure("Motion review fixture failed: \(error)") }
      return store
    }
  }

  struct MotionReviewRoot: View {
    @State private var store = MotionReview.makeStore()

    var body: some View {
      Group {
        if MotionReview.has("--sync-study") {
          MotionReviewSyncStudy()
        } else if let skill = MotionReview.arguments.first(where: { $0.hasPrefix("--illustration-skill=") })
            .flatMap({ MilestoneCatalog.skill(String($0.dropFirst("--illustration-skill=".count))) }),
            let child = store.selectedChild {
          MilestoneCheckInView(store: store, route: .init(child: child, skill: skill), onSave: { _ in })
        } else if MotionReview.has("--caregiver-profile") {
          CaregiverEditor(store: store, existing: store.snapshot.caregivers.first { $0.id == store.caregiverID })
        } else if MotionReview.has("--milestones") {
          ContentView(store: store)
        } else if MotionReview.has("--growth-length") {
          TrendsView(store: store, initialMetric: .length, initialDays: 30)
        } else if MotionReview.has("--growth-head") {
          TrendsView(store: store, initialMetric: .headCircumference, initialDays: 30)
        } else if MotionReview.has("--growth") {
          TrendsView(store: store, initialMetric: .weight, initialDays: 30)
        } else if MotionReview.has("--trends") {
          ContentView(store: store)
        } else if MotionReview.has("--pump") {
          PumpEditor(store: store, existing: nil)
        } else if MotionReview.has("--bottle") {
          ActivityEditor(
            store: store, route: LogRoute(kind: .bottle, childID: store.selectedChildID))
        } else if MotionReview.has("--child-profile") {
          ChildEditor(store: store, existing: store.selectedChild)
        } else if MotionReview.has("--settings") {
          SettingsView(store: store)
        } else {
          ContentView(store: store, openingDuration: MotionReview.has("--slow-opening") ? 20 : 0.85)
        }
      }
      .tint(LogStyle.forest)
      .foregroundStyle(LogStyle.ink)
      .preferredColorScheme(
        MotionReview.has("--dark") ? .dark : MotionReview.has("--light") ? .light : nil
      )
      .modifier(MotionReviewAccessibility())
      .task {
        guard MotionReview.has("--celebration-record"), let family = store.snapshot.family else { return }
        try? await Task.sleep(for: .seconds(3))
        guard !Task.isCancelled else { return }
        do {
          let session = PumpSession(familyID: family.id, motherID: store.caregiverID,
                                    occurredAt: .now, authorID: store.caregiverID,
                                    totalML: 270, unit: .oz)
          try store.save(.pumping(session))
          store.toast = "Pumping saved for Sam"
        } catch { store.report(error) }
      }
    }
  }

  /// Manual fixture controls for studying real status rendering without an account.
  private struct MotionReviewSyncStudy: View {
    @State private var phase = "Checked"
    @State private var showDetails = false
    private var status: FamilySyncStatus {
      FamilySyncStatus(
        cloudEnabled: phase != "Local", isSyncing: phase == "Working",
        pendingUploads: phase == "Pending" ? 1 : 0,
        needsAttention: phase == "Attention",
        lastCheck: phase == "Preparing" ? nil : .now)
    }
    var body: some View {
      NavigationStack {
        ScrollView {
          VStack(alignment: .leading, spacing: 24) {
            Text("Status motion study").font(LogStyle.heading())
            Text("Simulated states · no iCloud connection").font(.caption)
            HStack {
              Text("Robin").font(LogStyle.heading(.largeTitle))
              Spacer()
              FamilySyncIndicator(status: status) { showDetails = true }
                .buttonStyle(.glass).buttonBorderShape(.circle)
            }
            Text(status.title).font(.headline).frame(minHeight: 44)
            ForEach(
              ["Local", "Preparing", "Pending", "Working", "Checked", "Attention"], id: \.self
            ) { value in
              Button(value) { phase = value }
                .frame(minHeight: 44).buttonStyle(.bordered)
            }
          }.padding(24)
        }.background(LogStyle.canvas)
          .alert(status.title, isPresented: $showDetails) { Button("OK", role: .cancel) {} }
      }
    }
  }

  private struct MotionReviewAccessibility: ViewModifier {
    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
      content
        .environment(
          \.dynamicTypeSize, MotionReview.has("--large-text") ? .accessibility5 : typeSize)
    }
  }
#endif
