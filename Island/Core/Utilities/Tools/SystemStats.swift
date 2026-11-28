import Foundation
import Darwin

/// Live CPU, memory, disk and network readings for the Activity page.
/// Samples once a second, and only while something is looking.
@MainActor
final class SystemStats: ObservableObject {

    /// 0...1
    @Published private(set) var cpu: Double = 0
    @Published private(set) var memory: Double = 0
    @Published private(set) var disk: Double = 0

    @Published private(set) var downloadRate: Double = 0   // bytes / second
    @Published private(set) var uploadRate: Double = 0

    private var timer: Timer?
    private var lastCPU: host_cpu_load_info?
    private var lastNetwork: (down: UInt64, up: UInt64, at: Date)?

    func start() {

        guard timer == nil else { return }

        sample()

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }

        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lastCPU = nil
        lastNetwork = nil
    }

    private func sample() {
        cpu = readCPU()
        memory = readMemory()
        disk = readDisk()
        readNetwork()
    }

    // MARK: - CPU

    private func readCPU() -> Double {

        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return cpu }

        defer { lastCPU = info }

        guard let last = lastCPU else { return 0 }

        let user = Double(info.cpu_ticks.0 &- last.cpu_ticks.0)
        let system = Double(info.cpu_ticks.1 &- last.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2 &- last.cpu_ticks.2)
        let nice = Double(info.cpu_ticks.3 &- last.cpu_ticks.3)

        let total = user + system + idle + nice

        return total > 0 ? (user + system + nice) / total : 0
    }

    // MARK: - Memory

    private func readMemory() -> Double {

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)

        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return memory }

        let page = Double(vm_kernel_page_size)

        // What Activity Monitor calls "memory used": app memory, wired
        // and compressed.
        let used = Double(stats.active_count + stats.wire_count + stats.compressor_page_count) * page

        return min(1, used / Double(ProcessInfo.processInfo.physicalMemory))
    }

    // MARK: - Disk

    private func readDisk() -> Double {

        let url = URL(fileURLWithPath: "/")

        guard
            let values = try? url.resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey
            ]),
            let total = values.volumeTotalCapacity,
            let free = values.volumeAvailableCapacityForImportantUsage,
            total > 0
        else {
            return disk
        }

        return 1 - Double(free) / Double(total)
    }

    // MARK: - Network

    private func readNetwork() {

        var down: UInt64 = 0
        var up: UInt64 = 0

        var addresses: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&addresses) == 0, let first = addresses else { return }

        defer { freeifaddrs(addresses) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first

        while let current = cursor {

            let interface = current.pointee

            if
                let address = interface.ifa_addr,
                address.pointee.sa_family == UInt8(AF_LINK),
                let data = interface.ifa_data,
                String(cString: interface.ifa_name).hasPrefix("en")
            {
                let counters = data.assumingMemoryBound(to: if_data.self).pointee
                down += UInt64(counters.ifi_ibytes)
                up += UInt64(counters.ifi_obytes)
            }

            cursor = interface.ifa_next
        }

        let now = Date()

        defer { lastNetwork = (down, up, now) }

        guard let last = lastNetwork else { return }

        let elapsed = now.timeIntervalSince(last.at)

        guard elapsed > 0 else { return }

        // The kernel's counters are 32-bit and wrap; a drop means a wrap.
        downloadRate = down >= last.down ? Double(down - last.down) / elapsed : 0
        uploadRate = up >= last.up ? Double(up - last.up) / elapsed : 0
    }
}
