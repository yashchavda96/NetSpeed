import Foundation

struct ByteCounts {
    var received: UInt64 = 0
    var sent: UInt64 = 0

    /// Sums the kernel's 64-bit byte counters for Wi-Fi, Ethernet and cellular.
    /// Loopback, VPN tunnels and bridges are skipped: their traffic also passes
    /// through a physical interface, so it would be counted twice.
    static func read() -> ByteCounts {
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0 else { return ByteCounts() }
        var buffer = [UInt8](repeating: 0, count: length)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &length, nil, 0) == 0 else { return ByteCounts() }

        var total = ByteCounts()
        buffer.withUnsafeBytes { raw in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= length {
                // Messages are packed back to back, so they aren't necessarily aligned.
                let message = raw.baseAddress! + offset
                let header = message.loadUnaligned(as: if_msghdr.self)
                guard header.ifm_msglen > 0 else { break }
                offset += Int(header.ifm_msglen)

                guard Int32(header.ifm_type) == RTM_IFINFO2 else { continue }
                let info = message.loadUnaligned(as: if_msghdr2.self)
                var name = [CChar](repeating: 0, count: Int(IF_NAMESIZE))
                guard if_indextoname(UInt32(info.ifm_index), &name) != nil else { continue }

                let interface = String(cString: name)
                if interface.hasPrefix("en") || interface.hasPrefix("pdp_ip") {
                    total.received += info.ifm_data.ifi_ibytes
                    total.sent += info.ifm_data.ifi_obytes
                }
            }
        }
        return total
    }
}

/// Turns successive counter readings into current speeds and totals since launch.
final class TrafficMeter {
    private(set) var downloadRate = 0.0  // bytes per second
    private(set) var uploadRate = 0.0
    private(set) var total = ByteCounts()

    private var lastReading = ByteCounts.read()
    private var lastReadingTime = Date()

    /// Takes a new reading and returns the bytes transferred since the previous one.
    func sample() -> ByteCounts {
        let now = Date()
        let reading = ByteCounts.read()
        let elapsed = now.timeIntervalSince(lastReadingTime)
        guard elapsed > 0 else { return ByteCounts() }

        // Counters go backwards when an interface disappears or resets (sleep, Wi-Fi
        // reconnect, unplugging an adapter), so treat that interval as no traffic.
        // Totals add up these deltas for the same reason, instead of subtracting the
        // launch reading from the current one.
        let received = reading.received >= lastReading.received ? reading.received - lastReading.received : 0
        let sent = reading.sent >= lastReading.sent ? reading.sent - lastReading.sent : 0

        downloadRate = Double(received) / elapsed
        uploadRate = Double(sent) / elapsed
        total.received &+= received
        total.sent &+= sent
        lastReading = reading
        lastReadingTime = now
        return ByteCounts(received: received, sent: sent)
    }
}
