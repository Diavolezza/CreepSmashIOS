import UIKit
import CreepSmashCore

/// Pictures for the map cards in the menus: the small versions (480 px), decoded ahead of time.
/// Decoding all the large pictures at the moment a page opened made the cards flicker.
@MainActor
enum MapThumbnails {
    private static var cache: [String: UIImage] = [:]

    private static func assetName(_ map: GameMap) -> String {
        String(map.imageName.split(separator: ".").first ?? "") + "_small"
    }

    /// Decodes all of them in the background (at app start).
    static func preload() {
        let names = GameMap.all.map(assetName)
        Task.detached(priority: .utility) {
            var images: [String: UIImage] = [:]
            for name in names {
                if let image = UIImage(named: name)?.preparingForDisplay() { images[name] = image }
            }
            let loaded = images
            await MainActor.run { cache.merge(loaded) { current, _ in current } }
        }
    }

    static func image(for map: GameMap) -> UIImage {
        let name = assetName(map)
        if let image = cache[name] { return image }
        let image = UIImage(named: name)?.preparingForDisplay() ?? UIImage()
        cache[name] = image
        return image
    }
}
