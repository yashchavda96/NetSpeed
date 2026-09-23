import Foundation

enum DisplayMode: String, CaseIterable {
    case stacked, singleLine, downloadOnly, uploadOnly

    var title: String {
        switch self {
        case .stacked: return "Upload and Download (Two Lines)"
        case .singleLine: return "Upload and Download (One Line)"
        case .downloadOnly: return "Download Only"
        case .uploadOnly: return "Upload Only"
        }
    }
}

enum SpeedUnit: String {
    case bytes, bits

    var labels: [String] {
        self == .bits ? ["bps", "Kbps", "Mbps", "Gbps"] : ["B/s", "KB/s", "MB/s", "GB/s"]
    }

    /// "840 KB/s", "8.4 MB/s", "67 Mbps". Decimal units, like speed tests use.
    func format(_ bytesPerSecond: Double) -> String {
        var value = self == .bits ? bytesPerSecond * 8 : bytesPerSecond
        var scale = 0
        while value >= 1000 && scale < labels.count - 1 {
            value /= 1000
            scale += 1
        }
        let decimals = scale == 0 || value >= 100 ? 0 : 1
        return String(format: "%.\(decimals)f ", value) + labels[scale]
    }
}

enum Preferences {
    static var displayMode: DisplayMode {
        get { UserDefaults.standard.string(forKey: "displayMode").flatMap(DisplayMode.init) ?? .stacked }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "displayMode") }
    }

    static var speedUnit: SpeedUnit {
        get { UserDefaults.standard.string(forKey: "speedUnit").flatMap(SpeedUnit.init) ?? .bytes }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "speedUnit") }
    }
}
