import Foundation

/// Fictional, date-relative examples. These are never imported into a real family.
struct DemoFamily {
    let family: Family
    let child: ChildProfile
    let caregivers: [Caregiver]
    let records: [RecordValue]

    static func make(now: Date = .now, calendar: Calendar = Calendar(identifier: .gregorian)) throws -> DemoFamily {
        guard let birth = calendar.date(byAdding: .month, value: -3, to: calendar.startOfDay(for: now)),
              let ageDays = calendar.dateComponents([.day], from: birth, to: now).day else {
            throw LogError.message(String(localized: "Couldn’t prepare the demo. Try again."))
        }
        let familyID = UUID()
        let sam = Caregiver(familyID: familyID, name: "Sam", isMother: true, sex: .female)
        let alex = Caregiver(familyID: familyID, name: "Alex", sex: .male)
        let family = Family(id: familyID, name: "Robin & family", timeZoneIdentifier: calendar.timeZone.identifier, ownerID: sam.id)
        let child = ChildProfile(familyID: familyID, name: "Robin", birthDate: birth, gender: .boy,
                                 gestationalAgeAtBirthDays: 39 * 7 + 1)
        var records: [RecordValue] = [.child(child), .caregiver(sam), .caregiver(alex)]

        func activity(_ payload: ActivityPayload, at date: Date, author: UUID, note: String = "") -> RecordValue {
            .activity(Activity(familyID: familyID, childID: child.id, occurredAt: date,
                               timeZoneIdentifier: calendar.timeZone.identifier, createdAt: date,
                               authorID: author, source: "Demo", note: note, payload: payload))
        }
        // A month of ordinary, varied care. Pumped milk stays separate from intake.
        // Relative times keep the last-24-hours overview useful even at midnight.
        for day in 0..<31 {
            let offset = Double(day * 86_400)
            for feed in 0..<6 {
                let at = now.addingTimeInterval(-offset - Double(feed * 14_400 + 2_700))
                let total = 120 + ((day + feed) % 4) * 15
                let formula = feed == 4 ? 60 : 0
                records.append(activity(.bottle(Bottle(milkML: Decimal(total - formula), formulaML: Decimal(formula), unit: .ml)),
                                        at: at, author: feed.isMultiple(of: 2) ? sam.id : alex.id))
            }
            for change in 0..<6 {
                let at = now.addingTimeInterval(-offset - Double(change * 14_000 + 1_200))
                records.append(activity(.diaper(Diaper(pee: true, poo: (day + change).isMultiple(of: 3))),
                                        at: at, author: change.isMultiple(of: 2) ? alex.id : sam.id))
            }
            for pump in 0..<4 {
                let at = now.addingTimeInterval(-offset - Double(pump * 21_600 + 5_400))
                let left = Decimal(75 + ((day + pump) % 4) * 10)
                let right = Decimal(80 + ((day + pump + 1) % 3) * 10)
                records.append(.pumping(PumpSession(familyID: familyID, motherID: sam.id,
                    occurredAt: at, createdAt: at, authorID: pump == 2 ? alex.id : sam.id,
                    source: "Demo", totalML: left + right, leftML: left, rightML: right,
                    unit: .ml, minutes: Decimal(15 + pump * 2), timeZoneIdentifier: calendar.timeZone.identifier)))
            }
            if day.isMultiple(of: 3) {
                let at = now.addingTimeInterval(-offset - 10_800)
                let nursing = Nursing(caregiverID: sam.id, segments: [
                    NursingSegment(side: .left, start: at, end: at.addingTimeInterval(420)),
                    NursingSegment(side: .right, start: at.addingTimeInterval(450), end: at.addingTimeInterval(810))
                ], finished: true)
                records.append(activity(.nursing(nursing), at: at, author: sam.id))
            }
        }

        // Rounded measurements near the WHO median, computed from the same offline
        // tables as the charts. 39w1d is full term: no prematurity adjustment applies.
        let measurementDays = Set(Array(stride(from: 0, through: ageDays, by: 7)) + [ageDays - 4, ageDays]).sorted()
        for day in measurementDays {
            guard let date = calendar.date(byAdding: .day, value: day, to: birth),
                  let kg = WHOWeightForAge.kilograms(zScore: 0.08 * sin(Double(day) / 24), ageDays: day, sex: .male),
                  let length = MeasurementForAge.whoCentimeters(zScore: 0.1, metric: .length, ageDays: day, sex: .male),
                  let head = MeasurementForAge.whoCentimeters(zScore: -0.08, metric: .headCircumference, ageDays: day, sex: .male)
            else { throw LogError.message(String(localized: "Couldn’t prepare the demo. Try again.")) }
            let at = min(date.addingTimeInterval(9 * 3600), now)
            for payload: ActivityPayload in [
                .weight(grams: Decimal((kg * 100).rounded() * 10), unit: "kg"),
                .length(centimeters: Decimal((length * 10).rounded()) / 10, unit: .cm, position: .lyingDown),
                .headCircumference(centimeters: Decimal((head * 10).rounded()) / 10, unit: .cm)
            ] { records.append(activity(payload, at: at, author: sam.id)) }
        }

        // Completed two-month observations and a few emerging four-month skills.
        // Upcoming skills are left unchecked, rather than inventing a completion score.
        let skills = MilestoneCatalog.skills(at: 2) + Array(MilestoneCatalog.skills(at: 4).prefix(2))
        for (index, skill) in skills.enumerated() {
            let day = skill.months == 2 ? 28 + index * 3 : 76 + index % 4
            guard let first = calendar.date(byAdding: .day, value: day, to: birth) else { continue }
            records.append(.milestone(MilestoneObservation(familyID: familyID, childID: child.id,
                skillID: skill.id, sourceVersion: skill.sourceVersion, skillTitle: skill.title,
                status: .seen, firstNoticedAt: first, authorID: index.isMultiple(of: 2) ? sam.id : alex.id,
                recordedAt: first.addingTimeInterval(3600))))
        }
        records.append(activity(.temperature(celsius: Decimal(string: "36.8")!, unit: "°C", method: ""),
                                at: now.addingTimeInterval(-3 * 86_400), author: alex.id))
        records.append(activity(.careNote, at: now.addingTimeInterval(-86_400 - 7_200), author: alex.id,
                                note: String(localized: "A little smile during our morning walk.")))
        return DemoFamily(family: family, child: child, caregivers: [sam, alex], records: records)
    }

    var snapshot: FamilySnapshot {
        FamilySnapshot(family: family, records: records.map { value in
            let revision = RecordRevision(id: UUID(), recordID: value.id, parentIDs: [], value: value,
                                          date: child.birthDate ?? .distantPast, editorID: family.ownerID, deleted: false)
            return ProjectedRecord(revision: revision, heads: [revision])
        })
    }
}
