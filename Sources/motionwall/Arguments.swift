import Foundation

struct Arguments {
    var input: URL
    var name: String
    var category: String = "Custom"
    var thumbnailFrame: Int = 1
    var width: Int?
    var height: Int?
    var bitrateMbps: Int = 12
    var force: Bool = false

    static let usage = """
        MotionWall turns a video into a macOS animated wallpaper and installs it.

        usage:
          motionwall --input <path> --name <name> [options]

        required:
          --input <path>            source video
          --name <name>             wallpaper name shown in System Settings

        optional:
          --category <name>         section name (default: Custom)
          --thumbnail-frame <n>     frame used as the tile image, 1-based (default: 1)
          --width <pixels>          output width (default: source width)
          --height <pixels>         output height (default: source height)
          --bitrate <mbps>          target bitrate in Mbit/s (default: 12)
          --force                   replace an existing wallpaper without asking
          --help                    print this text

        Apple's own wallpapers and categories are never modified.
        """

    static func parse(_ raw: [String]) throws -> Arguments {
        var input: URL?
        var name: String?
        var parsed = Arguments(input: URL(fileURLWithPath: "/"), name: "")
        var index = 0

        func nextValue(for flag: String) throws -> String {
            index += 1
            guard index < raw.count else { throw MotionWallError.usage("\(flag) needs a value") }
            return raw[index]
        }

        func nextInt(for flag: String) throws -> Int {
            let text = try nextValue(for: flag)
            guard let value = Int(text) else {
                throw MotionWallError.usage("\(flag) needs a whole number, got \"\(text)\"")
            }
            return value
        }

        while index < raw.count {
            switch raw[index] {
            case "--input":
                input = URL(fileURLWithPath: try nextValue(for: "--input"))
            case "--name":
                name = try nextValue(for: "--name")
            case "--category":
                parsed.category = try nextValue(for: "--category")
            case "--thumbnail-frame":
                parsed.thumbnailFrame = try nextInt(for: "--thumbnail-frame")
            case "--width":
                parsed.width = try nextInt(for: "--width")
            case "--height":
                parsed.height = try nextInt(for: "--height")
            case "--bitrate":
                parsed.bitrateMbps = try nextInt(for: "--bitrate")
            case "--force":
                parsed.force = true
            case "--help", "-h":
                throw MotionWallError.usage(usage)
            default:
                throw MotionWallError.usage("unknown argument \"\(raw[index])\"\n\n\(usage)")
            }
            index += 1
        }

        guard let resolvedInput = input else { throw MotionWallError.usage("--input is required\n\n\(usage)") }
        guard let resolvedName = name, !resolvedName.isEmpty else {
            throw MotionWallError.usage("--name is required\n\n\(usage)")
        }
        guard parsed.thumbnailFrame >= 1 else {
            throw MotionWallError.usage("--thumbnail-frame must be 1 or greater")
        }
        guard parsed.bitrateMbps >= 1 else {
            throw MotionWallError.usage("--bitrate must be 1 or greater")
        }
        guard !parsed.category.isEmpty else {
            throw MotionWallError.usage("--category cannot be empty")
        }

        parsed.input = resolvedInput
        parsed.name = resolvedName
        return parsed
    }
}
