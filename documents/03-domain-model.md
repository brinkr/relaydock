# RelayDock 领域模型

更新时间：2026-04-22

## 1. 建模原则

RelayDock 的建模遵循以下原则：

- 配置态和运行态分离
- 主机优先
- 服务不等于 Web 页面
- Provider 可替换
- 本地端口占用作为共享底层能力
- 不以 TunnelGroup 作为一级核心对象

## 2. Host

表示一台可连接的主机或逻辑连接入口。

建议字段：

- `id`
- `name`
- `address`
- `port`
- `user`
- `tags`
- `os_family`
- `os_distro`
- `status_hint`
- `provider_targets[]`

说明：

- `Host` 负责表达“这是哪台机器”
- `Host` 不是某种具体隧道
- `ProxyJump` 等逻辑不应额外建成新的产品概念，只在 target 层或连接配置层体现

## 3. ProviderTarget

表示某条规则最终要连接的目标。

第一版至少支持两类：

- `ssh`
- `tailscale`

建议字段：

- `id`
- `host_id`
- `type`
- `label`
- `target_address`
- `target_port`
- `auth_ref`
- `meta`

示例：

- `家庭宽带 (SSH)`
- `Tailscale 直连`
- `广州跳板 (SSH)`
- `广州中转后的 Tailscale`

说明：

- 工具只需要知道“该连接哪个 target”
- 不需要建模底层链路细节

## 4. Rule / Service

这是最重要的配置对象，代表一个可访问的远端能力。

建议字段：

- `id`
- `host_id`
- `name`
- `alias`
- `provider_target_id`
- `remote_host`
- `main_port`
- `secondary_ports[]`
- `kind`
- `icon_hint`
- `tags[]`
- `notes`

说明：

- `Rule` 面向的是用户要访问的能力，不是底层命令本身
- 一个服务可以只映射一个端口，也可以包含一个主端口和多个附属端口
- 多端口只是这个服务的属性，不应反客为主变成产品主对象

## 5. Preset

表示一组规则的配置级集合。

建议字段：

- `id`
- `name`
- `host_id`
- `base_preset_id`
- `items[]`
- `description`

说明：

- `Preset` 属于资源登记，不属于运行页
- 后续建议支持基础预设 + 局部覆盖

覆盖场景包括：

- 在家优先 Tailscale
- 公司改走 SSH
- 某些规则不变，某些规则覆盖成另一个 target

## 6. RuntimeInstance

表示某条规则当前的运行实例。

建议字段：

- `id`
- `rule_id`
- `host_id`
- `provider_target_id`
- `local_bindings[]`
- `status`
- `latency_ms`
- `uptime_seconds`
- `failure_count_today`
- `started_at`
- `last_error`

说明：

- 运行页展示的是 `RuntimeInstance`
- 不是 `Rule` 本身

## 7. RecoveryItem

表示“上次运行过，但当前未连接”的候选恢复对象。

建议字段：

- `rule_id`
- `host_id`
- `provider_target_id`
- `last_local_bindings[]`
- `last_seen_status`
- `recoverable_since`

说明：

- `RecoveryItem` 不是普通 stopped
- 它携带“恢复上次运行集合”的语义

## 8. LocalPortBinding

表示某个远端目标和本地端口的绑定关系。

建议字段：

- `local_port`
- `remote_host`
- `remote_port`
- `temporary_override`

显示规则建议：

- 本地/远端都是 loopback 且端口一致：只显示端口
- 本地和远端端口不同：显示 `本地 -> 远端`
- 远端不是 loopback：显示 `本地 -> 远端IP:端口`

## 9. LocalPortOverride

表示一次运行中的临时本地端口改写。

建议字段：

- `runtime_instance_id`
- `original_port`
- `effective_port`
- `reason`
- `persisted`

说明：

- 用户已明确要求支持“本次临时改，不一定写回配置”
- 所以 override 不能简单直接改写 `Rule`

## 10. PortUsage / PortClaim

表示本机端口占用情况。

建议字段：

- `port`
- `protocol`
- `pid`
- `process_name`
- `command`
- `owner_type`
- `owner_ref`
- `killable`

说明：

- 这层能力应同时服务：
  - 隧道启动前的冲突检测
  - 本地端口诊断

## 11. LocalAlias

表示本地访问入口。

建议字段：

- `hostname`
- `rule_id`
- `generated`
- `editable`

说明：

- 别名应可自动生成且允许手改
- 唯一性由系统保证

