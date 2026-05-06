import Foundation

struct RelayDockVisualQAFixtures {
    let runRecoverySnapshot: RunRecoverySnapshotResult
    let registrySnapshot: RegistrySnapshotResult

    static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> RelayDockVisualQAFixtures? {
        guard environment["RELAYDOCK_VISUAL_QA_FIXTURE"] == "prototype-density" else {
            return nil
        }

        return prototypeDensity
    }

    private static var prototypeDensity: RelayDockVisualQAFixtures {
        let runRecoverySnapshot = RunRecoverySnapshotResult(
            refreshedAtEpochSeconds: 1_777_777_777,
            hosts: prototypeRunRecoveryHosts,
            summary: RunRecoverySummary(
                connectedHosts: 2,
                runningForwards: 7,
                issueCount: 3,
                recoverableCount: 4,
                message: "存在可恢复的转发"
            ),
            lastAction: nil
        )

        let registrySnapshot = RegistrySnapshotResult(
            refreshedAtEpochSeconds: 1_777_777_777,
            hosts: prototypeRegistryHosts,
            selectedHostId: "host-home-mac-mini"
        )

        return RelayDockVisualQAFixtures(
            runRecoverySnapshot: runRecoverySnapshot,
            registrySnapshot: registrySnapshot
        )
    }

    private static var prototypeRunRecoveryHosts: [RunRecoveryHost] {
        [
            RunRecoveryHost(
                id: "host-home-mac-mini",
                name: "Mac mini (M2) - 家",
                endpoint: "admin@192.168.1.5",
                providerSummary: "SSH · 家庭宽带 / Tailscale · 家里",
                rows: [
                    connectedRow("react-frontend", "React 前端", "react.home.localhost", "3000 -> 127.0.0.1:3000", "Tailscale · 家里", "6h 12m · 2ms · 0次"),
                    connectedRow("fastapi-backend", "FastAPI Backend", "api.home.localhost", "8000 -> api.internal:8000", "Tailscale · 家里", "6h 12m · 3ms · 0次"),
                    connectedRow("redis-cache", "Redis Cache", "redis.home.localhost", "6379 -> 127.0.0.1:6379", "SSH · 家庭宽带", "24h 05m · 1ms · 0次"),
                    connectedRow("nextjs-app", "Next.js App", "next.home.localhost", "3001 -> 127.0.0.1:3001", "Tailscale · 家里", "2h 00m · 5ms · 2次"),
                    reconnectingRow("go-microservice", "Go Microservice", "go.home.localhost", "8081 -> 127.0.0.1:8081", "SSH · 家庭宽带", "保活超时，正在重连", "0m · - · 5次"),
                    errorRow("rabbitmq", "RabbitMQ", "mq.home.localhost", "5672 + 15672 -> 127.0.0.1:5672", "SSH · 家庭宽带", "本地管理端口被其它进程占用", "0m · - · 12次"),
                    recoverableRow("postgres-main", "PostgreSQL Main", "pg.home.localhost", "5432 -> 127.0.0.1:5432", "SSH · 家庭宽带", "上次 OpenSSH 进程退出，等待手动恢复"),
                    recoverableRow("elasticsearch", "ElasticSearch", "es.home.localhost", "9200 -> 127.0.0.1:9200", "SSH · 家庭宽带", "上次休眠后未自动恢复"),
                    recoverableRow("kibana", "Kibana", "kibana.home.localhost", "5601 -> 127.0.0.1:5601", "SSH · 家庭宽带", "等待用户确认恢复上次入口"),
                ]
            ),
            RunRecoveryHost(
                id: "host-ubuntu-dev",
                name: "Ubuntu Dev Server",
                endpoint: "root@10.0.0.12",
                providerSummary: "SSH · 内网直连",
                rows: [
                    connectedRow("redis-cluster", "Redis Cluster", "redis.dev.localhost", "6379 -> 127.0.0.1:6379", "SSH · 内网", "34h 10m · 45ms · 0次", hostId: "host-ubuntu-dev"),
                    reconnectingRow("docker-registry", "Docker Registry", "docker.dev.localhost", "5000 + 5001 -> registry.internal:5000", "SSH · 内网", "连续 3 次未收到响应", "0m · - · 12次", hostId: "host-ubuntu-dev"),
                ]
            ),
        ]
    }

    private static var prototypeRegistryHosts: [RegistryHost] {
        [
            registryHost(
                id: "host-home-mac-mini",
                name: "Mac mini (M2) - 家",
                endpoint: "admin@192.168.1.5",
                address: "192.168.1.5",
                user: "admin",
                osHint: .macos,
                providerTargets: [
                    providerTarget("target-home-ssh", "SSH · 家庭宽带", .ssh, "192.168.1.5", 22),
                    providerTarget("target-home-tailscale", "Tailscale · 家里", .tailscale, "mac-mini.tailnet.ts.net", nil),
                ],
                presets: [
                    RegistryPreset(
                        id: "preset-workbench",
                        name: "日常工作台",
                        derivedFrom: nil,
                        rules: [
                            RegistryPresetRule(serviceName: "React 前端", targetLabel: "Tailscale · 家里"),
                            RegistryPresetRule(serviceName: "FastAPI Backend", targetLabel: "Tailscale · 家里"),
                            RegistryPresetRule(serviceName: "PostgreSQL Main", targetLabel: "SSH · 家庭宽带"),
                        ]
                    ),
                    RegistryPreset(
                        id: "preset-database",
                        name: "数据库排障",
                        derivedFrom: "日常工作台",
                        rules: [
                            RegistryPresetRule(serviceName: "PostgreSQL Main", targetLabel: "SSH · 家庭宽带"),
                            RegistryPresetRule(serviceName: "Redis Cache", targetLabel: "SSH · 家庭宽带"),
                        ]
                    ),
                ],
                rules: [
                    registryRule("react-frontend", "React 前端", "react.home.localhost", "Tailscale · 家里", "3000", .running, "target-home-tailscale"),
                    registryRule("fastapi-backend", "FastAPI Backend", "api.home.localhost", "Tailscale · 家里", "8000", .running, "target-home-tailscale"),
                    registryRule("postgres-main", "PostgreSQL Main", "pg.home.localhost", "SSH · 家庭宽带", "5432", .recoverable, "target-home-ssh"),
                    registryRule("redis-cache", "Redis Cache", "redis.home.localhost", "SSH · 家庭宽带", "6379", .running, "target-home-ssh"),
                    registryRule("go-microservice", "Go Microservice", "go.home.localhost", "SSH · 家庭宽带", "8081", .error, "target-home-ssh"),
                    registryRule("rabbitmq", "RabbitMQ", "mq.home.localhost", "SSH · 家庭宽带", "5672 + 15672", .error, "target-home-ssh"),
                    registryRule("kibana", "Kibana", "kibana.home.localhost", "SSH · 家庭宽带", "5601", .recoverable, "target-home-ssh"),
                ]
            ),
            registryHost(
                id: "host-ubuntu-dev",
                name: "Ubuntu Dev Server",
                endpoint: "root@10.0.0.12",
                address: "10.0.0.12",
                user: "root",
                osHint: .ubuntu,
                providerTargets: [providerTarget("target-dev-ssh", "SSH · 内网", .ssh, "10.0.0.12", 22)],
                presets: [],
                rules: [
                    registryRule("redis-cluster", "Redis Cluster", "redis.dev.localhost", "SSH · 内网", "6379", .running, "target-dev-ssh"),
                    registryRule("docker-registry", "Docker Registry", "docker.dev.localhost", "SSH · 内网", "5000 + 5001", .error, "target-dev-ssh"),
                ]
            ),
            registryHost(
                id: "host-office-jump",
                name: "广州跳板",
                endpoint: "relay@gz.example.net",
                address: "gz.example.net",
                user: "relay",
                osHint: .linux,
                providerTargets: [providerTarget("target-gz-ssh", "SSH · 广州跳板", .ssh, "gz.example.net", 22)],
                presets: [],
                rules: [
                    registryRule("redroid-adb", "Redroid ADB", "adb.gz.localhost", "SSH · 广州跳板", "5555", .stopped, "target-gz-ssh"),
                ]
            ),
        ]
    }

    private static func connectedRow(
        _ slug: String,
        _ serviceName: String,
        _ alias: String,
        _ portSummary: String,
        _ providerLabel: String,
        _ telemetry: String,
        hostId: String = "host-home-mac-mini"
    ) -> RunRecoveryRow {
        RunRecoveryRow(
            id: "runtime-\(slug)",
            ruleId: "rule-\(slug)",
            runtimeId: "runtime-\(slug)",
            recoveryId: nil,
            hostId: hostId,
            serviceName: serviceName,
            alias: alias,
            providerLabel: providerLabel,
            portSummary: portSummary,
            state: .connected,
            statusText: "运行中",
            telemetry: telemetry,
            error: nil,
            actions: [RunRecoveryAction(action: .stop, label: "停止")]
        )
    }

    private static func reconnectingRow(
        _ slug: String,
        _ serviceName: String,
        _ alias: String,
        _ portSummary: String,
        _ providerLabel: String,
        _ errorSummary: String,
        _ telemetry: String,
        hostId: String = "host-home-mac-mini"
    ) -> RunRecoveryRow {
        RunRecoveryRow(
            id: "runtime-\(slug)",
            ruleId: "rule-\(slug)",
            runtimeId: "runtime-\(slug)",
            recoveryId: nil,
            hostId: hostId,
            serviceName: serviceName,
            alias: alias,
            providerLabel: providerLabel,
            portSummary: portSummary,
            state: .reconnecting,
            statusText: "重连中",
            telemetry: telemetry,
            error: RunRecoveryRowError(code: "keep_alive_timeout", summary: errorSummary, detail: nil),
            actions: [
                RunRecoveryAction(action: .retry, label: "重试"),
                RunRecoveryAction(action: .stop, label: "停止"),
            ]
        )
    }

    private static func errorRow(
        _ slug: String,
        _ serviceName: String,
        _ alias: String,
        _ portSummary: String,
        _ providerLabel: String,
        _ errorSummary: String,
        _ telemetry: String
    ) -> RunRecoveryRow {
        RunRecoveryRow(
            id: "runtime-\(slug)",
            ruleId: "rule-\(slug)",
            runtimeId: "runtime-\(slug)",
            recoveryId: nil,
            hostId: "host-home-mac-mini",
            serviceName: serviceName,
            alias: alias,
            providerLabel: providerLabel,
            portSummary: portSummary,
            state: .error,
            statusText: "异常",
            telemetry: telemetry,
            error: RunRecoveryRowError(code: "port_conflict", summary: errorSummary, detail: nil),
            actions: [
                RunRecoveryAction(action: .retry, label: "重试"),
                RunRecoveryAction(action: .stop, label: "停止"),
            ]
        )
    }

    private static func recoverableRow(
        _ slug: String,
        _ serviceName: String,
        _ alias: String,
        _ portSummary: String,
        _ providerLabel: String,
        _ errorSummary: String
    ) -> RunRecoveryRow {
        RunRecoveryRow(
            id: "recovery-\(slug)",
            ruleId: "rule-\(slug)",
            runtimeId: nil,
            recoveryId: "recovery-\(slug)",
            hostId: "host-home-mac-mini",
            serviceName: serviceName,
            alias: alias,
            providerLabel: providerLabel,
            portSummary: portSummary,
            state: .recoverable,
            statusText: "待恢复",
            telemetry: nil,
            error: RunRecoveryRowError(code: "recoverable", summary: errorSummary, detail: nil),
            actions: [
                RunRecoveryAction(action: .recover, label: "恢复"),
                RunRecoveryAction(action: .changeLocalPort, label: "改本地端口"),
                RunRecoveryAction(action: .clear, label: "清除"),
            ]
        )
    }

    private static func registryHost(
        id: String,
        name: String,
        endpoint: String,
        address: String,
        user: String,
        osHint: RegistryHostOsHint,
        providerTargets: [RegistryProviderTarget],
        presets: [RegistryPreset],
        rules: [RegistryRule]
    ) -> RegistryHost {
        RegistryHost(
            id: id,
            name: name,
            endpoint: endpoint,
            status: .online,
            osHint: osHint,
            address: address,
            port: 22,
            user: user,
            tags: [],
            osDistro: nil,
            providerTargets: providerTargets,
            presets: presets,
            rules: rules
        )
    }

    private static func providerTarget(
        _ id: String,
        _ label: String,
        _ kind: RegistryProviderKind,
        _ targetAddress: String,
        _ targetPort: UInt16?
    ) -> RegistryProviderTarget {
        RegistryProviderTarget(
            id: id,
            label: label,
            kind: kind,
            targetAddress: targetAddress,
            targetPort: targetPort
        )
    }

    private static func registryRule(
        _ slug: String,
        _ serviceName: String,
        _ alias: String,
        _ providerLabel: String,
        _ portSummary: String,
        _ runtimeState: RegistryRuleRuntimeState,
        _ providerTargetId: String
    ) -> RegistryRule {
        let mainPort = UInt16(portSummary.split(separator: " ").first ?? "") ?? 3000

        return RegistryRule(
            id: "rule-\(slug)",
            serviceName: serviceName,
            alias: alias,
            providerLabel: providerLabel,
            portSummary: portSummary,
            runtimeState: runtimeState,
            providerTargetId: providerTargetId,
            remoteHost: "127.0.0.1",
            mainLocalPort: mainPort,
            mainRemoteHost: "127.0.0.1",
            mainRemotePort: mainPort,
            secondaryPorts: [],
            kind: nil,
            tags: [],
            notes: nil
        )
    }
}
