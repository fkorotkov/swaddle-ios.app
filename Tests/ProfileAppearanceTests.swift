import Foundation
import Testing
@testable import LittleLogCore

struct ProfileAppearanceTests {
    @Test func legacyVersionSixProfilesIgnoreRetiredChoicesAndKeepCareData() throws {
        let family = UUID()
        let values: [RecordValue] = [
            .child(ChildProfile(familyID: family, name: "Robin", birthDate: Date(timeIntervalSince1970: 1_750_000_000),
                gender: .boy, gestationalAgeAtBirthDays: 249)),
            .caregiver(Caregiver(familyID: family, name: "Sam", isMother: true, cloudIdentity: "linked", sex: .female))
        ]
        for value in values {
            let envelope = RecordEnvelope(value: value)
            var legacy = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(envelope)) as? [String: Any])
            legacy["version"] = 6
            var tagged = try #require(legacy["value"] as? [String: [String: Any]])
            let kind = try #require(tagged.keys.first)
            var profile = try #require(tagged[kind]?["_0"] as? [String: Any])
            profile["raceEthnicities"] = ["asian", "white"]
            profile["illustrationAppearance"] = ["skinTone": "golden", "hairColor": "black"]
            tagged[kind]?["_0"] = profile; legacy["value"] = tagged
            let decoded = try JSONDecoder().decode(RecordEnvelope.self, from: JSONSerialization.data(withJSONObject: legacy))
            #expect(decoded.version == 6 && decoded.value == value)
            let saved = try JSONEncoder().encode(RecordEnvelope(value: decoded.value))
            let text = String(decoding: saved, as: UTF8.self)
            #expect(!text.contains("raceEthnicities") && !text.contains("illustrationAppearance"))
            #expect(try JSONDecoder().decode(RecordEnvelope.self, from: saved).value == value)
        }
    }

    @Test func sexIsOptionalAndNeverInferredFromPumpingOrGrowth() throws {
        let family = UUID()
        let person = Caregiver(familyID: family, name: "Sam", isMother: true)
        #expect(person.sex == nil && RecordEnvelope(value: .caregiver(person)).version == 1)
        var female = person; female.sex = .female
        #expect(RecordEnvelope(value: .caregiver(female)).version == 6)
        #expect(try JSONDecoder().decode(Caregiver.self, from: JSONEncoder().encode(female)) == female)
        let child = ChildProfile(familyID: family, name: "Robin", gender: .boy)
        #expect(child.effectiveGrowthReferenceSex == .male && child.paletteGender == .boy)
    }

    @Test func anUnchangedSexDraftPreservesRemoteProfileEdits() {
        let baseline = Caregiver(familyID: UUID(), name: "Sam")
        var latest = baseline; latest.sex = .female; latest.cloudIdentity = "newly-linked"
        let edited = CaregiverSexEdits.applying(to: latest, baseline: baseline, sex: nil)
        #expect(edited.sex == .female && edited.cloudIdentity == "newly-linked")
        let cleared = CaregiverSexEdits.applying(to: edited, baseline: edited, sex: nil)
        #expect(cleared.sex == nil && cleared.cloudIdentity == "newly-linked")
    }

    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }
    private func data(for id: String) throws -> Data {
        try Data(contentsOf: root.appending(path: "BabyActivityRecorder/Assets.xcassets/MilestoneIllustrations/milestone-\(id).dataset/illustration.json"))
    }

    @Test func sceneCastingIsBalancedIndependentAndContainsNoProfileData() throws {
        let manifest = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: root.appending(path:
            "ReferenceData/MilestoneIllustrations/manifest.json"))) as? [String: Any])
        let rows = try #require(manifest["illustrations"] as? [[String: Any]])
        #expect(Set(rows.compactMap { $0["id"] as? String }) == Set(MilestoneCatalog.all.map(\.id)))
        let distribution = try #require(manifest["distribution"] as? [String: [String: [String: Int]]])
        for role in ["child", "caregiver"] {
            #expect(distribution[role]?["skinTone"]?.count == 6)
            for counts in try #require(distribution[role]).values {
                #expect(try #require(counts.values.max()) - #require(counts.values.min()) <= 1)
            }
        }
        #expect(distribution["child"]?["hairStyle"]?.count == 4)
        var differentPairs = 0
        for row in rows {
            let id = try #require(row["id"] as? String)
            let cast = try #require(row["cast"] as? [String: [String: String]])
            if let adult = cast["caregiver"], adult["skinTone"] != cast["child"]?["skinTone"] { differentPairs += 1 }
            let scene = try #require(JSONSerialization.jsonObject(with: data(for: id)) as? [String: Any])
            #expect(scene["swaddleActors"] == nil, "No runtime color-personalization metadata")
            #expect(scene["raceEthnicities"] == nil && scene["illustrationAppearance"] == nil)
        }
        #expect(differentPairs > 20, "Adult and child palettes must not be locked together")
    }

    @Test func adultSilhouettesKeepTheBakedCastAndEveryMotionKey() throws {
        for skill in MilestoneCatalog.all {
            let original = try data(for: skill.id)
            #expect(try IllustrationPersonalizer.data(original, caregiverSex: nil) == original)
            let scene = try #require(JSONSerialization.jsonObject(with: original) as? [String: Any])
            let before = try #require(scene["layers"] as? [[String: Any]])
            for sex in CaregiverSex.allCases {
                let output = try IllustrationPersonalizer.data(original, caregiverSex: sex)
                let changed = try #require(JSONSerialization.jsonObject(with: output) as? [String: Any])
                let after = try #require(changed["layers"] as? [[String: Any]])
                #expect(before.count == after.count)
                for (old, new) in zip(before, after) {
                    var unchanged = new
                    if old["hd"] == nil { unchanged.removeValue(forKey: "hd") } else { unchanged["hd"] = old["hd"] }
                    let difference = jsonDifference(old, unchanged)
                    #expect(difference == nil, "Only adult hair visibility may change: \(skill.id), \(old["nm"] ?? ""): \(difference ?? "")")
                }
                let variants = after.filter { ($0["nm"] as? String)?.hasPrefix("Caregiver hair · ") == true }
                if !variants.isEmpty {
                    let visible = variants.filter { $0["hd"] as? Bool != true }
                    #expect(visible.count == 1 && visible.first?["nm"] as? String == "Caregiver hair · \(sex.rawValue)")
                }
            }
        }
    }

    /// Foundation may serialize a pigment with a different final decimal bit.
    /// Compare JSON values recursively, allowing only floating-point roundoff.
    private func jsonDifference(_ lhs: Any, _ rhs: Any, path: String = "root") -> String? {
        if let a = lhs as? [String: Any], let b = rhs as? [String: Any] {
            guard Set(a.keys) == Set(b.keys) else { return path + ": keys differ" }
            for key in a.keys.sorted() {
                if let difference = jsonDifference(a[key]!, b[key]!, path: path + "." + key) { return difference }
            }
            return nil
        }
        if let a = lhs as? [Any], let b = rhs as? [Any] {
            guard a.count == b.count else { return path + ": counts differ" }
            for index in a.indices {
                if let difference = jsonDifference(a[index], b[index], path: path + "[\(index)]") { return difference }
            }
            return nil
        }
        if let a = lhs as? NSNumber, let b = rhs as? NSNumber {
            return abs(a.doubleValue - b.doubleValue) < 1e-10 ? nil : path + ": \(a) != \(b)"
        }
        if let a = lhs as? String, let b = rhs as? String, a == b { return nil }
        if lhs is NSNull && rhs is NSNull { return nil }
        return path + ": \(lhs) != \(rhs)"
    }
}
