import Lottie
import UIKit

@MainActor
enum MilestoneAnimationCache {
    private static let cache: NSCache<NSString, LottieAnimation> = {
        let value = NSCache<NSString, LottieAnimation>()
        value.countLimit = 12
        return value
    }()

    static func animation(for skill: MilestoneSkill, caregiverSex: CaregiverSex?) -> LottieAnimation? {
        let asset = MilestoneIllustrationCatalog.assetName(for: skill)
        let key = (asset + ":" + (caregiverSex?.rawValue ?? "neutral")) as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let original = NSDataAsset(name: asset)?.data else { return nil }
        do {
            let data = try IllustrationPersonalizer.data(original, caregiverSex: caregiverSex)
            let animation = try LottieAnimation.from(data: data)
            cache.setObject(animation, forKey: key)
            return animation
        } catch {
            assertionFailure("Invalid bundled milestone illustration: \(skill.id)")
            return LottieAnimation.asset(asset)
        }
    }
}
