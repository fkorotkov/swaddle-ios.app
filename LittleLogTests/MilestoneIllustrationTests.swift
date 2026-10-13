import Foundation
import Lottie
import Testing
import UIKit
@testable import BabyActivityRecorder

@MainActor
struct MilestoneIllustrationTests {
    @Test func adultStyleVariantsDecodeInTheNativeRenderer() throws {
        for sex: CaregiverSex? in [nil, .female, .male] {
            for id in ["cdc-2-smilestalk2", "cdc-9-is_shy", "who-walking-assisted"] {
                let skill = try #require(MilestoneCatalog.skill(id))
                let data = try #require(NSDataAsset(name: MilestoneIllustrationCatalog.assetName(for: skill))?.data)
                let animation = try LottieAnimation.from(data: IllustrationPersonalizer.data(data, caregiverSex: sex))
                let view = LottieAnimationView(animation: animation,
                    configuration: LottieConfiguration(renderingEngine: .coreAnimation))
                view.frame = CGRect(x: 0, y: 0, width: 420, height: 280)
                view.layoutIfNeeded()
                view.currentFrame = CGFloat(MilestoneIllustrationCatalog.posterFrame(for: skill))
                view.forceDisplayUpdate()
                #expect(view.currentRenderingEngine == .coreAnimation)
                #expect(animation.bounds.size == CGSize(width: 420, height: 280))
                #expect(animation.endFrame == 180)
            }
        }
    }

    @Test func maleFemaleAndNeutralArtProduceDistinctRenderedSilhouettes() throws {
        let skill = try #require(MilestoneCatalog.skill("cdc-2-smilestalk2"))
        let data = try #require(NSDataAsset(name: MilestoneIllustrationCatalog.assetName(for: skill))?.data)
        var portraits = Set<Data>()
        for sex: CaregiverSex? in [nil, .female, .male] {
            let animation = try LottieAnimation.from(data: IllustrationPersonalizer.data(data, caregiverSex: sex))
            let view = LottieAnimationView(animation: animation,
                configuration: LottieConfiguration(renderingEngine: .mainThread))
            view.frame = CGRect(x: 0, y: 0, width: 420, height: 280)
            view.layoutIfNeeded(); view.currentFrame = 100; view.forceDisplayUpdate()
            let format = UIGraphicsImageRendererFormat(); format.scale = 1
            let image = UIGraphicsImageRenderer(size: view.bounds.size, format: format).image {
                view.layer.render(in: $0.cgContext)
            }
            portraits.insert(try #require(image.pngData()))
        }
        #expect(portraits.count == 3, "Adult variants must differ in rendered pixels, not only filenames")
    }
    @Test func everyMilestoneHasAnOfflineNativeIllustration() throws {
        #expect(MilestoneCatalog.all.count == 106)
        #expect(Set(MilestoneIllustrationCatalog.descriptions.keys) == Set(MilestoneCatalog.all.map(\.id)))
        for skill in MilestoneCatalog.all {
            try autoreleasepool {
                let data = try #require(NSDataAsset(name: MilestoneIllustrationCatalog.assetName(for: skill))?.data,
                                        "Missing bundled illustration for \(skill.id)")
                let animation = try LottieAnimation.from(data: data)
                #expect(animation.framerate == 30)
                #expect(animation.endFrame - animation.startFrame == 180)
                #expect(animation.bounds.size == CGSize(width: 420, height: 280))
                let poster = try #require(animation.frameTime(forMarker: "poster"))
                #expect(poster == CGFloat(MilestoneIllustrationCatalog.posterFrame(for: skill)))
                let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
                #expect(json["nm"] as? String == skill.id)
                #expect((json["assets"] as? [Any])?.isEmpty == true)
                #expect(json["fonts"] == nil && json["glyphs"] == nil)
                let player = LottieAnimationView(animation: animation,
                    configuration: LottieConfiguration(renderingEngine: .coreAnimation))
                player.frame = CGRect(x: 0, y: 0, width: 420, height: 280)
                player.layoutIfNeeded()
                for frame in [CGFloat(30), poster, CGFloat(150)] {
                    player.currentFrame = frame
                    player.forceDisplayUpdate()
                    #expect(player.currentRenderingEngine == .coreAnimation, "Native renderer: \(skill.id)")
                }
            }
        }
    }

    @Test func loopsReturnToTheirStartingPoseWithValidParentRigs() throws {
        for skill in MilestoneCatalog.all {
            let data = try #require(NSDataAsset(name: MilestoneIllustrationCatalog.assetName(for: skill))?.data)
            let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let layers = try #require(json["layers"] as? [[String: Any]])
            let reset = try #require(layers.first { $0["nm"] as? String == "Loop reset · hidden return" })
            let indices = layers.compactMap { $0["ind"] as? Int }
            #expect(Set(indices).count == layers.count, "Unique layer IDs: \(skill.id)")
            let parents = Dictionary(uniqueKeysWithValues: layers.compactMap { layer -> (Int, Int)? in
                guard let id = layer["ind"] as? Int, let parent = layer["parent"] as? Int else { return nil }
                return (id, parent)
            })
            for id in indices {
                var seen = Set<Int>(), cursor = id
                while let parent = parents[cursor] {
                    #expect(indices.contains(parent), "Missing parent: \(skill.id)")
                    guard seen.insert(cursor).inserted else {
                        Issue.record("Cyclic character rig: \(skill.id)")
                        break
                    }
                    cursor = parent
                }
            }
            let opacity = try #require((reset["ks"] as? [String: Any])?["o"] as? [String: Any])
            let opacityKeys = try #require(opacity["k"] as? [[String: Any]])
            #expect(opacityKeys.first?["s"] as? [Int] == [0])
            #expect(opacityKeys.last?["s"] as? [Int] == [0])
            var animatedProperties = 0
            func verify(_ value: Any) {
                if let object = value as? [String: Any] {
                    if object["a"] as? Int == 1, let frames = object["k"] as? [[String: Any]],
                       let first = frames.first, let last = frames.last {
                        animatedProperties += 1
                        #expect(last["t"] as? Int == 180, "Complete loop duration: \(skill.id)")
                        if let initial = first["s"] as? NSArray, let final = last["s"] as? NSArray {
                            #expect(initial.isEqual(final), "Loop pose must match: \(skill.id)")
                        } else { Issue.record("Missing animation values: \(skill.id)") }
                        let times = frames.compactMap { $0["t"] as? Int }
                        #expect(zip(times, times.dropFirst()).allSatisfy { $0 < $1 }, "Ordered keyframes: \(skill.id)")
                    } else { for nested in object.values { verify(nested) } }
                } else if let array = value as? [Any] { for nested in array { verify(nested) } }
            }
            verify(layers)
            #expect(animatedProperties > 3, "Skill-specific motion: \(skill.id)")
        }
    }

    @Test func resetActuallyHidesTheArtworkInTheRenderer() throws {
        // Parenting in Lottie does not inherit opacity. Verify the resulting
        // pixels, rather than trusting the opacity on a null character rig.
        for id in ["cdc-12-bye_bye", "cdc-6-rolls_tummy", "cdc-9-smiles_laughs", "who-crawling"] {
            let skill = try #require(MilestoneCatalog.skill(id))
            let data = try #require(NSDataAsset(name: MilestoneIllustrationCatalog.assetName(for: skill))?.data)
            let animation = try LottieAnimation.from(data: data)
            let view = LottieAnimationView(animation: animation,
                configuration: LottieConfiguration(renderingEngine: .mainThread))
            view.frame = CGRect(x: 0, y: 0, width: 420, height: 280)
            view.layoutIfNeeded()
            func hasArtwork(at frame: CGFloat) throws -> Bool {
                view.currentFrame = frame
                view.forceDisplayUpdate()
                let format = UIGraphicsImageRendererFormat()
                format.scale = 1
                format.opaque = false
                // The stationary cloth sits below this crop.
                let image = UIGraphicsImageRenderer(size: CGSize(width: 420, height: 180), format: format).image {
                    view.layer.render(in: $0.cgContext)
                }
                let cgImage = try #require(image.cgImage)
                var pixels = [UInt8](repeating: 0, count: 420 * 180 * 4)
                let context = try #require(CGContext(data: &pixels, width: 420, height: 180,
                    bitsPerComponent: 8, bytesPerRow: 420 * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 420, height: 180))
                return stride(from: 3, to: pixels.count, by: 4).contains { pixels[$0] > 0 }
            }
            #expect(try !hasArtwork(at: 0), "Fade must reach the drawn layers: \(id)")
            #expect(try hasArtwork(at: CGFloat(MilestoneIllustrationCatalog.posterFrame(for: skill))), "Meaningful visible poster: \(id)")
            #expect(try !hasArtwork(at: 180), "Reset is hidden: \(id)")
        }
    }
}
