import SwiftUI

struct PreferencesView: View {
    var body: some View {
        PlaceholderPane(
            title: "偏好设置",
            subtitle: "后续承载启动项、Keychain、日志保留、默认 provider 策略等设置。"
        ) {
            VStack(alignment: .leading, spacing: 12) {
                PreferenceRow(title: "开机启动", value: "未启用")
                PreferenceRow(title: "默认 provider", value: "按主机配置")
                PreferenceRow(title: "日志保留", value: "待配置")
            }
            .frame(maxWidth: 420, alignment: .leading)
        }
    }
}

private struct PreferenceRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .medium))
            Spacer()
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 7)
    }
}
