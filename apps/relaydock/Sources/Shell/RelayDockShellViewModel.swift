import Foundation

final class RelayDockShellViewModel: ObservableObject {
    @Published var selection: RelayDockSection = .runAndRecovery

    let statusSummary = StatusSummary(
        connectedHosts: 0,
        runningForwards: 0,
        issueCount: 0,
        message: "等待运行数据"
    )
}

enum RelayDockSection: String, CaseIterable, Identifiable {
    case runAndRecovery
    case registry
    case logsAndDiagnostics
    case preferences

    var id: String { rawValue }

    var title: String {
        switch self {
        case .runAndRecovery:
            "运行与恢复"
        case .registry:
            "资源登记"
        case .logsAndDiagnostics:
            "日志与诊断"
        case .preferences:
            "偏好设置"
        }
    }

    var systemImage: String {
        switch self {
        case .runAndRecovery:
            "waveform.path.ecg"
        case .registry:
            "server.rack"
        case .logsAndDiagnostics:
            "doc.text.magnifyingglass"
        case .preferences:
            "gearshape"
        }
    }
}

struct StatusSummary {
    var connectedHosts: Int
    var runningForwards: Int
    var issueCount: Int
    var message: String
}
