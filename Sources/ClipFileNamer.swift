import Foundation

/// Shared filename sequence for both instant replays and edited exports.
///
/// The counter persists across launches. We also inspect existing numbered clips
/// so imported/moved files are never accidentally overwritten.
enum ClipFileNamer {
    private static let lock = NSLock()
    private static let defaultsKey = "clipNextNumber"
    private static let numberedClip = try! NSRegularExpression(
        pattern: #"^clip([0-9]+)-[0-9]{4}-[0-9]{2}-[0-9]{2}\.mp4$"#,
        options: [.caseInsensitive])

    static func nextURL(in directory: URL,
                        at date: Date = Date(),
                        defaults: UserDefaults = .standard) throws -> URL {
        lock.lock()
        defer { lock.unlock() }

        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        let fileNames = try fm.contentsOfDirectory(atPath: directory.path)
        let highest = fileNames.compactMap { fileName -> Int? in
            let range = NSRange(fileName.startIndex..<fileName.endIndex, in: fileName)
            guard let match = numberedClip.firstMatch(in: fileName, range: range),
                  let numberRange = Range(match.range(at: 1), in: fileName) else {
                return nil
            }
            return Int(fileName[numberRange])
        }.max() ?? 0

        let savedNext = defaults.integer(forKey: defaultsKey)
        let next = max(1, savedNext, highest + 1)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"

        // Padding is a minimum width: clip1000 follows clip999 naturally.
        let filename = String(format: "clip%03d-%@.mp4",
                              next, formatter.string(from: date))
        let output = directory.appendingPathComponent(filename, isDirectory: false)
        defaults.set(next + 1, forKey: defaultsKey)
        return output
    }
}
