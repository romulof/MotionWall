import Foundation

public enum WallpaperSelection {
    static let storeURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/com.apple.wallpaper/Store/Index.plist")
    static let backupURL = storeURL.appendingPathExtension("bak")
    static let aerialsProvider = "com.apple.wallpaper.choice.aerials"

    public static func select(assetID: String) throws {
        guard let data = try? Data(contentsOf: storeURL),
            let store = try? PropertyListSerialization.propertyList(from: data, format: nil)
        else { throw MotionWallError.wallpaperSelectionFailed("cannot read \(storeURL.path)") }

        let configuration = try PropertyListSerialization.data(
            fromPropertyList: ["assetID": assetID], format: .binary, options: 0)
        var switched = 0
        let updated = replacingAerialChoices(in: store, with: configuration, count: &switched)
        guard switched > 0 else { throw MotionWallError.wallpaperSelectionUnsupported }

        if !FileManager.default.fileExists(atPath: backupURL.path) {
            try? FileManager.default.copyItem(at: storeURL, to: backupURL)
        }
        let output = try PropertyListSerialization.data(fromPropertyList: updated, format: .binary, options: 0)
        try output.write(to: storeURL, options: .atomic)
        AerialLibrary().restartWallpaperAgent()

        Thread.sleep(forTimeInterval: 2)
        guard isSelected(assetID: assetID) else {
            throw MotionWallError.wallpaperSelectionFailed("macOS kept the previous wallpaper")
        }
    }

    static func isSelected(assetID: String) -> Bool {
        guard let data = try? Data(contentsOf: storeURL),
            let store = try? PropertyListSerialization.propertyList(from: data, format: nil)
        else { return false }
        return selectedAssetIDs(in: store).contains(assetID)
    }

    private static func replacingAerialChoices(in value: Any, with configuration: Data, count: inout Int) -> Any {
        if let array = value as? [Any] {
            return array.map { replacingAerialChoices(in: $0, with: configuration, count: &count) }
        }
        guard var dictionary = value as? [String: Any] else { return value }
        if dictionary["Provider"] as? String == aerialsProvider, dictionary["Configuration"] is Data {
            dictionary["Configuration"] = configuration
            count += 1
            return dictionary
        }
        let before = count
        for (key, child) in dictionary {
            dictionary[key] = replacingAerialChoices(in: child, with: configuration, count: &count)
        }
        if count > before, dictionary["Content"] != nil, dictionary["LastSet"] != nil {
            dictionary["LastSet"] = Date()
        }
        return dictionary
    }

    private static func selectedAssetIDs(in value: Any) -> [String] {
        if let array = value as? [Any] { return array.flatMap(selectedAssetIDs) }
        guard let dictionary = value as? [String: Any] else { return [] }
        if dictionary["Provider"] as? String == aerialsProvider, let data = dictionary["Configuration"] as? Data,
            let configuration = try? PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any],
            let assetID = configuration["assetID"] as? String
        {
            return [assetID]
        }
        return dictionary.values.flatMap(selectedAssetIDs)
    }
}
