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
    static let shared = NetworkMonitor()
    
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

// MARK: - Network Status Banner

/// A banner that shows when the network is offline or constrained
struct NetworkStatusBanner: View {
    @StateObject private var networkMonitor = NetworkMonitor()
    
    var body: some View {
        if networkMonitor.status == .offline {
            HStack(spacing: 8) {
                Image(systemName: "wifi.slash")
                    .font(.subheadline.weight(.semibold))
                
                Text("No Internet Connection")
                    .font(.subheadline.weight(.medium))
                
                Spacer()
                
                Text("Some features may be unavailable")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.red.opacity(0.9))
            .foregroundColor(.white)
            .transition(.move(edge: .top).combined(with: .opacity))
        } else if networkMonitor.status == .constrained {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                
                Text("Limited Connectivity")
                    .font(.subheadline.weight(.medium))
                
                Spacer()
                
                Text("Data saver mode active")
                    .font(.caption)
                    .foregroundColor(.black.opacity(0.7))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.orange.opacity(0.9))
            .foregroundColor(.black)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
