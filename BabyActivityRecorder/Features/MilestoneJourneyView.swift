import SwiftUI

struct MilestoneCheckInRoute: Identifiable {
    let id = UUID()
    let child: ChildProfile
    let skill: MilestoneSkill
    var observation: MilestoneObservation? = nil
}

struct MilestoneCheckpointRequest: Equatable {
    let id = UUID()
    let childID: UUID
    let months: Int
}

struct MilestoneJourneyView: View {
    @Bindable var store: LogStore
    var settingsPresentation: Binding<Bool>? = nil
    var checkpointRequest: MilestoneCheckpointRequest? = nil
    @State private var route: MilestoneCheckInRoute?
    @State private var draft: MilestoneCheckInDraft?
    @State private var pendingRoute: MilestoneCheckInRoute?
    @State private var confirmReplacement = false
    @State private var compactColumn: NavigationSplitViewColumn = .sidebar
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var childEditor: ChildEditRoute?
    @State private var scrollAnchor: String?
    @State private var savedID: UUID?
    @State private var confirmation: String?
    @State private var error: String?
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.calendar) private var calendar
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var storyTitleSize = 34
    private var usesColumns: Bool { sizeClass == .regular && !typeSize.isAccessibilitySize }
    private var observations: [MilestoneObservation] {
        store.snapshot.milestoneObservations.filter { $0.childID == store.selectedChild?.id }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $compactColumn) {
            journeyContent
                .navigationSplitViewColumnWidth(min: 300, ideal: 360, max: 440)
        } detail: {
            if let route, let draft {
                MilestoneCheckInView(store: store, route: route, draft: draft, onClose: closeCheckIn) { id in
                    savedID = id
                    withAnimation(.easeOut(duration: 0.18)) { confirmation = String(localized: "Observation saved") }
                }.id(route.id).environment(\.careWideLayout, usesColumns)
            } else {
                VStack(spacing: 24) {
                    CocoonOpeningMark(size: 120).frame(width: 90, height: 120)
                    Text("Their unfolding\nstory.").font(LogStyle.heading(.largeTitle)).multilineTextAlignment(.center)
                    Text("Explore any chapter").font(.title3).foregroundStyle(LogStyle.muted)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).background(LogStyle.canvas)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .environment(\.horizontalSizeClass, typeSize.isAccessibilitySize ? .compact : sizeClass)
        .confirmationDialog("Discard your changes?", isPresented: $confirmReplacement, titleVisibility: .visible) {
            Button("Discard changes", role: .destructive) {
                if let pendingRoute { activate(pendingRoute) }
                pendingRoute = nil
            }
            Button("Keep editing", role: .cancel) { pendingRoute = nil }
        }
    }

    private var journeyContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let child = store.selectedChild {
                    journey(child)
                } else {
                    ContentUnavailableView("Choose a child", systemImage: "leaf", description: Text("Add a child in Settings to begin their story."))
                }
            }.padding(.horizontal, 22).padding(.top, 14).padding(.bottom, 36)
                .frame(maxWidth: 640).frame(maxWidth: .infinity)
        }
        .scrollPosition(id: $scrollAnchor, anchor: .top)
        .background(LogStyle.canvas)
        .navigationTitle(usesColumns ? "" : String(localized: "Milestones")).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                if let child = store.selectedChild {
                    NavigationLink { MilestoneHistoryView(store: store, child: child) } label: {
                        Label("Family observations", systemImage: "clock.arrow.circlepath")
                    }.labelStyle(.iconOnly)
                }
                NavigationLink { MilestoneSourcesView() } label: { Label("About milestones", systemImage: "info.circle") }
                    .labelStyle(.iconOnly)
            }
            ToolbarItem(placement: .topBarTrailing) {
                SettingsButton(store: store, presentation: settingsPresentation)
            }
        }
        .sheet(item: $childEditor) { ChildEditor(store: store, existing: $0.child) }
        .overlay(alignment: .bottom) {
            if let confirmation {
                SaveConfirmation(message: confirmation, undoID: store.undoID == savedID ? savedID : nil) {
                    do { try store.undo(); self.confirmation = String(localized: "Observation undone") }
                    catch { self.error = error.localizedDescription }
                } dismiss: {
                    withAnimation(.easeOut(duration: 0.18)) { self.confirmation = nil }
                }
                .padding(16)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task(id: savedID) {
            guard savedID != nil else { return }
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.18)) { confirmation = nil }
        }
        .sensoryFeedback(.success, trigger: savedID)
        #if DEBUG && targetEnvironment(simulator)
        .task {
            if let argument = MotionReview.arguments.first(where: { $0.hasPrefix("--milestone-illustration=") }),
               let skill = MilestoneCatalog.skill(String(argument.dropFirst("--milestone-illustration=".count))),
               let child = store.selectedChild {
                select(.init(child: child, skill: skill))
            } else if MotionReview.has("--milestone-detail"), let child = store.selectedChild {
                select(.init(child: child, skill: MilestoneCatalog.motorSkills[0]))
            }
            if MotionReview.has("--milestone-scroll-review") {
                // Exercise real scroll geometry with fictional data, including reversing direction.
                for target in ["chapter-6", "chapter-2", "motor"] {
                    try? await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeInOut(duration: 2.4)) { scrollAnchor = target }
                }
            }
        }
        #endif
        .onChange(of: store.selectedChildID) { _, _ in
            scrollAnchor = nil
            confirmation = nil
            // Keep an unfinished observation attached to its original child.
            if draft?.isDirty != true { closeCheckIn() }
        }
        .onChange(of: checkpointRequest, initial: true) {
            guard let checkpointRequest, checkpointRequest.childID == store.selectedChild?.id,
                  MilestoneCatalog.checkpoints.contains(checkpointRequest.months) else { return }
            scrollAnchor = "chapter-\(checkpointRequest.months)"
        }
        .alert("Couldn’t update observation", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
    }

    @ViewBuilder private func journey(_ child: ChildProfile) -> some View {
        let age = MilestoneAge(child: child, now: .now, calendar: calendar)
        VStack(alignment: .leading, spacing: 18) {
            childHeading(child)
            if !typeSize.isAccessibilitySize && !usesColumns {
                Text("Their unfolding\nstory.")
                    .font(.system(size: storyTitleSize, weight: .semibold, design: .serif))
                    .tracking(-0.7).lineSpacing(-2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
        }
        if let age {
            if age.isCorrected {
                let corrected = ChildAge(child: child, at: .now, calendar: calendar)?.correctedLabel ?? ""
                Label(age.beforeDueDate ? String(localized: "Looking ahead from their due date") : String(localized: "Chapters use corrected age · \(corrected)"), systemImage: "calendar")
                    .font(.subheadline).foregroundStyle(LogStyle.muted)
            } else if age.completedMonths > 24 {
                Text("Your saved story stays here. This collection covers the first two years; CDC has checklists through age five.")
                    .font(.subheadline).foregroundStyle(LogStyle.muted)
            }
        } else {
            LogCard(color: LogStyle.sage) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Explore any chapter").font(.headline)
                    Text("Add a birth date to suggest the age checklist. If your baby was born early, add gestational age too.")
                        .font(.subheadline)
                    Button("Add birth details") { childEditor = ChildEditRoute(child: child) }
                        .buttonStyle(.glass).disabled(!store.canEdit)
                }
            }
        }
        VStack(spacing: 0) {
            if let recent = observations.first {
                StoryRibbonRow(symbol: recent.status == .seen ? (MilestoneCatalog.skill(recent.skillID)?.domain.symbol ?? recent.status.symbol) : recent.status.symbol) {
                    Button { open(recent, child: child) } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("\((recent.firstNoticedAt ?? recent.recordedAt).formatted(.dateTime.month(.abbreviated).day())) · \(store.snapshot.caregiverName(recent.authorID))")
                                    .font(.caption).foregroundStyle(LogStyle.muted)
                                Text(recent.localizedTitle).font(LogStyle.heading(.headline)).foregroundStyle(LogStyle.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(recent.status.title).font(.caption).foregroundStyle(LogStyle.forest)
                                if store.snapshot.record(recent.id)?.hasConflict == true {
                                    Text("Competing edits · Review in Settings").font(.caption).foregroundStyle(LogStyle.amber)
                                }
                            }
                            Spacer(minLength: 0)
                            if !typeSize.isAccessibilitySize {
                                Image(systemName: "chevron.forward").font(.caption.weight(.semibold)).foregroundStyle(LogStyle.muted)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, typeSize.isAccessibilitySize ? 18 : 25).padding(.trailing, 16).padding(.vertical, 15)
                            .background { MilestonePaper(tone: .memory) }
                    }.buttonStyle(LogPressStyle())
                        .accessibilityHint("Open this family observation")
                }.id("latest-observation")
            }
            ForEach(MilestoneCatalog.checkpoints, id: \.self) { months in
                let stage = age?.current == months ? String(localized: "Current chapter") : age?.upcoming == months ? String(localized: "Looking ahead") : String(localized: "Explore")
                StoryRibbonRow(symbol: months == 2 ? "leaf.fill" : months < 12 ? "sparkles" : "figure.child", prominent: months == (age?.suggested ?? 2)) {
                    MilestoneChapterCard(
                        months: months, stage: stage, featured: months == (age?.suggested ?? 2),
                        observations: observations.filter { MilestoneCatalog.skill($0.skillID)?.months == months },
                        snapshot: store.snapshot, selectedSkillID: route?.skill.id,
                        openRequest: checkpointRequest?.childID == child.id && checkpointRequest?.months == months
                            ? checkpointRequest?.id : nil
                    ) { skill in select(.init(child: child, skill: skill)) }
                }.id("chapter-\(months)")
            }
            StoryRibbonRow(symbol: "figure.child") {
                MilestoneMotorCard { skill in select(.init(child: child, skill: skill)) }
            }.id("motor")
        }.scrollTargetLayout()
            .background(alignment: .topLeading) {
                if !typeSize.isAccessibilitySize { MilestoneRibbon().frame(width: 58).padding(.leading, -4) }
            }
        if !observations.isEmpty {
            NavigationLink {
                MilestoneHistoryView(store: store, child: child)
            } label: {
                Label("Family observations (\(observations.count))", systemImage: "book.closed")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }.buttonStyle(.glass)
        }
        Text("CDC age checklists describe skills most children (75% or more) show by that age. This is a shared journal, not a developmental screening test.")
            .font(.footnote).foregroundStyle(LogStyle.muted)
        NavigationLink("Sources & age guidance") { MilestoneSourcesView() }.frame(minHeight: 44)
        MilestoneConcernNotice()
    }

    private func select(_ next: MilestoneCheckInRoute) {
        if draft?.isDirty == true {
            pendingRoute = next
            confirmReplacement = true
        } else { activate(next) }
    }

    private func activate(_ next: MilestoneCheckInRoute) {
        route = next
        draft = MilestoneCheckInDraft(route: next, snapshot: store.snapshot)
        compactColumn = .detail
        if usesColumns, let months = next.skill.months {
            scrollAnchor = "chapter-\(months)"
        }
    }

    private func closeCheckIn() {
        compactColumn = .sidebar
        route = nil
        draft = nil
    }

    private func open(_ observation: MilestoneObservation, child: ChildProfile) {
        guard let skill = MilestoneCatalog.skill(observation.skillID) else { return }
        select(.init(child: child, skill: skill, observation: observation))
    }

    private func childHeading(_ child: ChildProfile) -> some View {
        HStack(spacing: 12) {
            if !typeSize.isAccessibilitySize {
                CocoonOpeningMark(size: 80).frame(width: 48, height: 66)
            }
            VStack(alignment: .leading, spacing: 2) {
                if !typeSize.isAccessibilitySize {
                    Text("SWADDLE").font(.system(.caption2, weight: .semibold)).tracking(2.5).foregroundStyle(LogStyle.forest)
                }
                if store.snapshot.children.count > 1 {
                    Menu {
                        ForEach(store.snapshot.children) { item in
                            Button(item.name, systemImage: item.id == child.id ? "checkmark" : "person") { store.selectedChildID = item.id }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text(child.name).font(LogStyle.heading(.title))
                            Image(systemName: "chevron.down").font(.caption.weight(.semibold))
                        }.frame(minHeight: 44).contentShape(.rect)
                    }.accessibilityLabel("Selected child, \(child.name)").accessibilityHint("Choose a different child")
                } else {
                    Text(child.name).font(LogStyle.heading(.title))
                }
                if let age = ChildAge(child: child, at: .now, calendar: calendar) {
                    Text(age.chronologicalDays == 0 ? String(localized: "Born today") : String(localized: "\(age.spokenChronologicalDuration) old"))
                        .font(.subheadline).foregroundStyle(LogStyle.muted)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct StoryRibbonRow<Content: View>: View {
    let symbol: String
    var prominent = false
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        content.padding(.leading, typeSize.isAccessibilitySize ? 0 : 40).padding(.bottom, 16)
            .overlay(alignment: .topLeading) {
                if !typeSize.isAccessibilitySize {
                    MilestoneMedallion(symbol: symbol, prominent: prominent)
                        .padding(.top, prominent ? 54 : 22).padding(.leading, prominent ? 0 : 5)
                }
            }
    }
}

private struct MilestoneChapterCard: View {
    let months: Int
    let stage: String
    let featured: Bool
    let observations: [MilestoneObservation]
    let snapshot: FamilySnapshot
    let selectedSkillID: String?
    let openRequest: UUID?
    let open: (MilestoneSkill) -> Void
    @State private var expanded: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var scheme
    private var skills: [MilestoneSkill] { MilestoneCatalog.skills(at: months) }
    init(months: Int, stage: String, featured: Bool, observations: [MilestoneObservation], snapshot: FamilySnapshot, selectedSkillID: String? = nil, openRequest: UUID? = nil, open: @escaping (MilestoneSkill) -> Void) {
        self.months = months; self.stage = stage; self.featured = featured
        self.observations = observations; self.snapshot = snapshot; self.open = open
        self.openRequest = openRequest
        self.selectedSkillID = selectedSkillID
        #if DEBUG && targetEnvironment(simulator)
        expanded = MotionReview.has("--milestone-expanded") && featured
        #else
        expanded = false
        #endif
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                toggleChapter()
            } label: {
                VStack(alignment: .leading, spacing: featured ? 9 : 4) {
                    if featured { Text(stage.uppercased()).font(.caption2.weight(.semibold)).tracking(1.8).foregroundStyle(LogStyle.forest).padding(.trailing, 24) }
                    HStack(alignment: .firstTextBaseline) {
                        Text(MilestoneCatalog.title(at: months)).font(LogStyle.heading(featured ? .largeTitle : .title2))
                        Spacer(minLength: 4)
                        if !featured {
                            Image(systemName: "chevron.forward").font(.caption.weight(.semibold))
                                .rotationEffect(.degrees(expanded ? 90 : 0)).foregroundStyle(LogStyle.muted)
                        }
                    }
                    Text(MilestoneCatalog.subtitle(at: months)).font(.subheadline).foregroundStyle(LogStyle.muted).fixedSize(horizontal: false, vertical: true)
                    if featured {
                        HStack(spacing: 8) {
                            Text(expanded ? String(localized: "Close check-in") : String(localized: "Open check-in")).font(.subheadline.weight(.semibold))
                                .contentTransition(.identity)
                            Image(systemName: "chevron.forward").font(.caption.weight(.semibold))
                                .rotationEffect(.degrees(expanded ? -90 : 0))
                        }
                        .foregroundStyle(LogStyle.canvas).frame(maxWidth: .infinity, minHeight: 44)
                        .background(LinearGradient(colors: [LogStyle.forest, LogStyle.forest.opacity(0.88)], startPoint: .topLeading, endPoint: .bottomTrailing), in: .capsule)
                        .overlay { Capsule().strokeBorder(.white.opacity(scheme == .light ? 0.18 : 0.10), lineWidth: 1) }
                        .padding(.top, 4)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, typeSize.isAccessibilitySize ? 18 : 25).padding(.trailing, 18).padding(.vertical, featured ? 20 : 17).contentShape(.rect)
            }.buttonStyle(LogPressStyle())
                .accessibilityLabel("\(MilestoneCatalog.title(at: months)), \(stage)")
                .accessibilityValue(expanded ? String(localized: "Expanded") : String(localized: "Collapsed"))
                .accessibilityHint("\(expanded ? String(localized: "Hide") : String(localized: "Show")) milestone check-in")
                .accessibilityIdentifier("milestones.chapter.\(months)")
            if expanded {
                VStack(alignment: .leading, spacing: 16) {
                    Text("CDC · By \(MilestoneCatalog.title(at: months).lowercased())").font(.caption).foregroundStyle(LogStyle.muted)
                    ForEach(MilestoneDomain.allCases, id: \.self) { domain in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(domain.title).font(.subheadline.weight(.semibold)).foregroundStyle(LogStyle.forest)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(skills.filter { $0.domain == domain }) { skill in
                                let latest = observations.first { $0.skillID == skill.id }
                                Button { open(skill) } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        Image(systemName: latest?.status.symbol ?? "circle").frame(width: 22).padding(.top, 2)
                                        VStack(alignment: .leading, spacing: 6) {
                                            Text(skill.localizedTitle).foregroundStyle(LogStyle.ink)
                                            if let latest {
                                                Text(snapshot.record(latest.id)?.hasConflict == true ? String(localized: "Competing edits · Review in Settings") : String(localized: "\(latest.status.title) · \(snapshot.caregiverName(latest.authorID))"))
                                                    .font(.caption).foregroundStyle(LogStyle.muted)
                                            }
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: "chevron.forward").font(.caption2).padding(.top, 4).foregroundStyle(LogStyle.muted)
                                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).padding(.vertical, 8).contentShape(.rect)
                                }
                                .background(selectedSkillID == skill.id ? LogStyle.forest.opacity(0.10) : .clear, in: .rect(cornerRadius: 12))
                                .buttonStyle(.plain).accessibilityIdentifier("milestones.skill.\(skill.id)")
                                    .accessibilityAddTraits(selectedSkillID == skill.id ? .isSelected : [])
                                    .accessibilityHint("Open skill and family observations")
                                Divider()
                            }
                        }
                    }
                }.padding(.horizontal, 20).padding(.bottom, 20)
                    .transition(reduceMotion ? .opacity : .offset(y: -6).combined(with: .opacity))
            }
        }.foregroundStyle(LogStyle.ink)
            .background { MilestonePaper(tone: featured ? .sage : .ivory, folded: featured && !typeSize.isAccessibilitySize, unfolded: expanded) }
            .sensoryFeedback(.selection, trigger: expanded)
            .onChange(of: selectedSkillID, initial: true) {
                if skills.contains(where: { $0.id == selectedSkillID }) { expanded = true }
            }
            .onChange(of: openRequest, initial: true) { if openRequest != nil { expanded = true } }
            #if DEBUG && targetEnvironment(simulator)
            .task {
                guard featured, MotionReview.has("--milestone-motion") else { return }
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                toggleChapter()
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                toggleChapter()
            }
            #endif
    }

    private func toggleChapter() {
        withAnimation(reduceMotion ? nil : .smooth(duration: 0.28)) { expanded.toggle() }
    }
}

private struct MilestoneMotorCard: View {
    let open: (MilestoneSkill) -> Void
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                withAnimation(reduceMotion ? nil : .smooth(duration: 0.24)) { expanded.toggle() }
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Movement, in their time.").font(LogStyle.heading(.title2))
                    Text("WHO · Six motor skills").font(.subheadline)
                    Label(expanded ? String(localized: "Close") : String(localized: "Explore observed ranges"), systemImage: expanded ? "chevron.up" : "chevron.down").font(.subheadline.weight(.semibold))
                }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(.rect)
            }.buttonStyle(LogPressStyle()).accessibilityIdentifier("milestones.motor")
            if expanded {
                ForEach(MilestoneCatalog.motorSkills) { skill in
                    Button { open(skill) } label: {
                        HStack { Text(skill.localizedTitle); Spacer(); Image(systemName: "chevron.forward").font(.caption) }
                            .frame(minHeight: 44).contentShape(.rect)
                    }.buttonStyle(.plain)
                    Divider()
                }
                Text("Reference ranges, not deadlines. These are separate from CDC age checklists.").font(.caption).foregroundStyle(LogStyle.muted)
            }
        }.padding(20).background { MilestonePaper(tone: .sage) }
    }
}
