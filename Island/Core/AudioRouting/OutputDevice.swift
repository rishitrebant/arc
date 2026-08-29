import Foundation

enum OutputDeviceSource: Equatable {
    case spotify
    case system
}

enum OutputDeviceType: Equatable {
    case computer
    case phone
    case speaker
    case tv
    case headphones
    case airplay
    case unknown

    var systemImage: String {
        switch self {
        case .computer:
            return "laptopcomputer"

        case .phone:
            return "iphone"

        case .speaker:
            return "speaker.wave.3.fill"

        case .tv:
            return "tv"

        case .headphones:
            return "headphones"

        case .airplay:
            return "airplayaudio"

        case .unknown:
            return "speaker.wave.2.fill"
        }
    }
}

struct OutputDevice: Identifiable, Equatable {

    let id: String
    let name: String

    let type: OutputDeviceType

    let source: OutputDeviceSource

    var isActive: Bool

    var volume: Double?
}
