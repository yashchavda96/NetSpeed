import Foundation

/// Runs Apple's built-in `networkQuality` tool (macOS 12+), the same test as
/// `networkQuality` in Terminal. Takes around 20 seconds.
enum SpeedTest {
    struct Result {
        let download: Double  // bytes per second
        let upload: Double
    }

    /// Calls back on the main queue, with nil if the test couldn't run or finish.
    static func run(completion: @escaping (Result?) -> Void) {
        DispatchQueue.global(qos: .utility).async {
            let result = measure()
            DispatchQueue.main.async { completion(result) }
        }
    }

    private static func measure() -> Result? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/networkQuality")
        process.arguments = ["-c", "-M", "30"]  // JSON output, give up after 30 seconds
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        guard (try? process.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let download = json["dl_throughput"] as? NSNumber,  // bits per second
              let upload = json["ul_throughput"] as? NSNumber
        else { return nil }
        return Result(download: download.doubleValue / 8, upload: upload.doubleValue / 8)
    }
}
