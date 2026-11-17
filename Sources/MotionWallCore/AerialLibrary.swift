import Foundation

typealias JSONObject = [String: Any]

struct InstallTarget {
    let assetID: String
    let categoryID: String
    let subcategoryID: String
    let replacingAsset: Bool
    let reusingCategory: Bool
}

struct AerialLibrary {
    let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/com.apple.wallpaper/aerials")

    let bundledManifestURL = URL(
        fileURLWithPath:
            "/System/Library/ExtensionKit/Extensions/WallpaperAerialsExtension.appex/Contents/Resources/entries.json"
    )

    var manifestURL: URL { root.appendingPathComponent("manifest/entries.json") }
    var backupURL: URL { root.appendingPathComponent("manifest/entries.json.bak") }
    var videosDirectory: URL { root.appendingPathComponent("videos") }
    var thumbnailsDirectory: URL { root.appendingPathComponent("thumbnails") }

    func videoURL(for assetID: String) -> URL {
        videosDirectory.appendingPathComponent("\(assetID).mov")
    }

    func thumbnailURL(for assetID: String) -> URL {
        thumbnailsDirectory.appendingPathComponent("\(assetID).png")
    }

    func load() throws -> JSONObject {
        let downloaded = Self.readManifest(at: manifestURL)
        let bundled = Self.readManifest(at: bundledManifestURL)
        switch (downloaded, bundled) {
        case let (downloaded?, bundled?) where Self.version(of: bundled) > Self.version(of: downloaded):
            return Self.rebased(customEntriesOf: downloaded, onto: bundled)
        case let (downloaded?, _):
            return downloaded
        case let (nil, bundled?):
            return bundled
        case (nil, nil):
            throw MotionWallError.manifestUnreadable(manifestURL)
        }
    }

    static func readManifest(at url: URL) -> JSONObject? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? JSONObject
    }

    static func version(of manifest: JSONObject) -> Int {
        manifest["version"] as? Int ?? 0
    }

    // The aerials extension ignores the downloaded manifest once the one bundled with macOS has a higher version.
    static func rebased(customEntriesOf downloaded: JSONObject, onto bundled: JSONObject) -> JSONObject {
        let customCategories = (downloaded["categories"] as? [JSONObject] ?? [])
            .filter { !isAppleOwned(category: $0) }
        let customAssets = (downloaded["assets"] as? [JSONObject] ?? [])
            .filter { !isAppleOwned(asset: $0) }
        var manifest = bundled
        manifest["categories"] = (bundled["categories"] as? [JSONObject] ?? []) + customCategories
        manifest["assets"] = (bundled["assets"] as? [JSONObject] ?? []) + customAssets
        return manifest
    }

    func save(_ manifest: JSONObject) throws {
        if !FileManager.default.fileExists(atPath: backupURL.path) {
            try? FileManager.default.copyItem(at: manifestURL, to: backupURL)
        }
        let data = try JSONSerialization.data(withJSONObject: manifest)
        try data.write(to: manifestURL)
    }

    func prepareDirectories() throws {
        for directory in [videosDirectory, thumbnailsDirectory, manifestURL.deletingLastPathComponent()] {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
        }
    }

    static func isAppleOwned(category: JSONObject) -> Bool {
        let id = category["id"] as? String ?? ""
        let key = category["localizedNameKey"] as? String ?? ""
        return id == "dynamic-aerials" || key.hasPrefix("AerialCategory")
    }

    static func isAppleOwned(asset: JSONObject) -> Bool {
        let url = asset["url-4K-SDR-240FPS"] as? String ?? ""
        return !url.hasPrefix("file://")
    }

    static func matches(category: JSONObject, name: String) -> Bool {
        let key = category["localizedNameKey"] as? String ?? ""
        let appleStyle = "AerialCategory" + name.replacingOccurrences(of: " ", with: "")
        return key.caseInsensitiveCompare(name) == .orderedSame
            || key.caseInsensitiveCompare(appleStyle) == .orderedSame
    }

    func resolveTarget(
        name: String,
        category categoryName: String,
        in manifest: JSONObject,
        confirmOverwrite: (String, String) -> Bool
    ) throws -> InstallTarget {
        let categories = manifest["categories"] as? [JSONObject] ?? []
        let assets = manifest["assets"] as? [JSONObject] ?? []

        let existingCategory = categories.first { Self.matches(category: $0, name: categoryName) }
        if let existingCategory, Self.isAppleOwned(category: existingCategory) {
            throw MotionWallError.appleCategory(categoryName)
        }

        let categoryID = existingCategory?["id"] as? String ?? UUID().uuidString.uppercased()
        let subcategoryID =
            (existingCategory?["subcategories"] as? [JSONObject])?.first?["id"] as? String
            ?? UUID().uuidString.uppercased()

        let existingAsset = assets.first { asset in
            let assetName = asset["localizedNameKey"] as? String ?? ""
            let assetCategories = asset["categories"] as? [String] ?? []
            return assetName.caseInsensitiveCompare(name) == .orderedSame
                && assetCategories.contains(categoryID)
        }

        if let existingAsset {
            if Self.isAppleOwned(asset: existingAsset) {
                throw MotionWallError.appleAsset(name, categoryName)
            }
            guard confirmOverwrite(name, categoryName) else {
                throw MotionWallError.cancelledByUser
            }
            return InstallTarget(
                assetID: existingAsset["id"] as? String ?? UUID().uuidString.uppercased(),
                categoryID: categoryID,
                subcategoryID: subcategoryID,
                replacingAsset: true,
                reusingCategory: existingCategory != nil
            )
        }

        return InstallTarget(
            assetID: UUID().uuidString.uppercased(),
            categoryID: categoryID,
            subcategoryID: subcategoryID,
            replacingAsset: false,
            reusingCategory: existingCategory != nil
        )
    }

    func updated(
        _ manifest: JSONObject,
        target: InstallTarget,
        name: String,
        categoryName: String
    ) -> JSONObject {
        let thumbnail = thumbnailURL(for: target.assetID).absoluteString
        let shotID = "CUSTOM_" + target.assetID.replacingOccurrences(of: "-", with: "_")

        let asset: JSONObject = [
            "id": target.assetID,
            "categories": [target.categoryID],
            "subcategories": [target.subcategoryID],
            "pointsOfInterest": ["0": shotID + "_0"],
            "shotID": shotID,
            "includeInShuffle": true,
            "previewImage": thumbnail,
            "accessibilityLabel": name,
            "preferredOrder": 0,
            "localizedNameKey": name,
            "url-4K-SDR-240FPS": videoURL(for: target.assetID).absoluteString,
            "showInTopLevel": true,
        ]

        var manifest = manifest
        var assets = manifest["assets"] as? [JSONObject] ?? []
        assets.removeAll { ($0["id"] as? String) == target.assetID }
        assets.append(asset)
        manifest["assets"] = assets

        var categories = manifest["categories"] as? [JSONObject] ?? []
        var category =
            categories.first { ($0["id"] as? String) == target.categoryID }
            ?? [
                "id": target.categoryID,
                "localizedNameKey": categoryName,
                "localizedDescriptionKey": "Wallpapers made with MotionWall",
                "preferredOrder": 1,
            ]
        category["previewImage"] = thumbnail
        category["representativeAssetID"] = target.assetID

        var subcategories = category["subcategories"] as? [JSONObject] ?? []
        if subcategories.isEmpty {
            subcategories = [
                [
                    "id": target.subcategoryID,
                    "preferredOrder": 0,
                    "localizedNameKey": categoryName,
                    "localizedDescriptionKey": "Wallpapers made with MotionWall",
                ]
            ]
        }
        subcategories = subcategories.map { existing in
            var updated = existing
            if (updated["id"] as? String) == target.subcategoryID {
                updated["previewImage"] = thumbnail
                updated["representativeAssetID"] = target.assetID
            }
            return updated
        }
        category["subcategories"] = subcategories

        categories.removeAll { ($0["id"] as? String) == target.categoryID }
        categories.append(category)
        manifest["categories"] = categories

        return manifest
    }

    func restartWallpaperAgent() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["WallpaperAgent"]
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}
