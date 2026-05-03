# RelayDock Provider 与网络场景

更新时间：2026-04-22

## 1. 为什么需要 Provider 抽象

用户的真实需求不是“永远 SSH”，而是“在当前环境下选最合适的连接目标”。

因此产品不能只支持 SSH。

## 2. 第一版 Provider 范围

第一版至少支持：

- `ssh`
- `tailscale`

## 3. 对底层实现的态度

RelayDock 不需要深入理解：

- SSH Jump Host 内部如何中转
- Tailscale 是直连还是 DERP
- Tailscale 是否通过其它机器二次转发

这些都应视为 provider target 的一部分。

## 4. 已确认的真实场景

### 家庭网络

- 可直连 Tailscale
- 体验通常优于直接 SSH

### 公司网络

- Tailscale/WireGuard 特征可能被限制
- 此时可能需要退回 SSH

### 广州跳板场景

- 用户到广州服务器延迟较低
- 广州服务器可再通过 Tailscale 或其它方式访问春川
- 这类目标对 RelayDock 来说，只需要表现成一个可选 target

## 5. 目标表达方式

UI 不应该长期使用很重的长句。

建议表达为：

- SSH + 短标签
- Tailscale + 短标签

例如：

- `SSH · 家庭`
- `Tailscale · 直连`
- `SSH · 广州`

## 6. Host 默认与 Rule 覆盖

这个能力后续很重要。

建议方向：

- 主机级可以有默认 target
- 单条规则可以覆盖
- 预设也可以覆盖

## 7. 预设的未来方向

已确认未来更合理的预设能力包括：

- 基础预设
- 派生预设
- 局部覆盖

例如：

- `日常开发 (基础)`
- `公司办公 (派生)`

派生预设可以只改少数规则的 target，而不是复制整套集合。

## 8. ProxyJump 的产品处理

对于：

- `ProxyJump`
- 先 SSH 到广州再进入另一个目标

RelayDock 不需要把它单独做成产品概念。

对用户来说，它仍然只是：

- 一个 SSH target

## 9. 典型示例

### 示例 1：单 SSH 目标

- `ssh -> sanjose`

### 示例 2：Tailscale 直连

- `tailscale -> chuncheon`

### 示例 3：广州中转后的可用 target

- `ssh -> guangzhou-relay-for-chuncheon`

对 RelayDock 而言，这三者都应该以统一 target 形式出现。

