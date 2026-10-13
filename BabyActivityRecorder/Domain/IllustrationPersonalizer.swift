import Foundation

/// Skin tones and hair colors are part of the bundled scene, independent of
/// profiles. Only the existing optional adult silhouette changes at runtime.
nonisolated enum IllustrationPersonalizer {
    static func data(_ data: Data, caregiverSex: CaregiverSex?) throws -> Data {
        guard let caregiverSex else { return data }
        guard var scene = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              var layers = scene["layers"] as? [[String: Any]] else { return data }
        var changed = false
        for index in layers.indices {
            guard let name = layers[index]["nm"] as? String,
                  name.hasPrefix("Caregiver hair · ") else { continue }
            layers[index]["hd"] = name != "Caregiver hair · \(caregiverSex.rawValue)"
            changed = true
        }
        guard changed else { return data }
        scene["layers"] = layers
        return try JSONSerialization.data(withJSONObject: scene, options: [.sortedKeys])
    }
}
