import Foundation
import Network
import SwiftUI

enum NetworkStatus: Equatable {
    case checking
    case online
    case constrained
    case offline

    var isReachable: Bool {
        switch self {
        case .online, .constrained:
            return true
        default:
            return false
        }
    }

    var iconName: String {
        switch self {
        case .online:
            return "checkmark.seal.fill"
        case .constrained:
            return "exclamationmark.triangle.fill"
        case .offline:
            return "wifi.exclamationmark"
        case .checking:
            return "wifi"
        }
    }

    var tintColor: Color {
        switch self {
        case .online:
            return .green
        case .constrained:
            return .orange
        case .offline:
            return .red
        case .checking:
            return .secondary
        }
    }
}

@MainActor
final class NetworkMonitor: ObservableObject {
    @Published private(set) var status: NetworkStatus = .checking

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.hawala.network.monitor")

    init() {
        monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let newStatus: NetworkStatus
            if path.status == .satisfied {
                newStatus = path.isConstrained ? .constrained : (path.isExpensive ? .constrained : .online)
            } else {
                newStatus = .offline
            }

            DispatchQueue.main.async {
                guard let self else { return }
                if self.status != newStatus {
                    self.status = newStatus
                }
            }
        }

        monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }
}
