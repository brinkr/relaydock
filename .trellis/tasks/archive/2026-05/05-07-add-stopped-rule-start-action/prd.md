# Add stopped rule start action

## 背景

用户已经可以通过 SSH 命令导入规则，但导入后的规则在 `资源登记` 中显示为 `已停止` 时，行级操作只有 `映射` 和 `规则`，没有启动入口。实际启动路径已经存在：`RegistryView` 的恢复回调在 shell 层调用 `startRule(ruleId:)`，只是停止态没有把这个能力暴露出来。

## 目标

- `资源登记` 中停止态规则必须显示明确的 `启动` 操作。
- 点击 `启动` 必须复用现有启动路径，并切换到 `运行与恢复`。
- 视觉 QA 夹具必须在首屏覆盖停止态规则，避免以后只靠代码检查才发现入口缺失。

## 非目标

- 不改变 Rust runtime 状态机。
- 不改变 bridge 命令签名。
- 不处理真实 SSH 凭据、网络可达性或连接失败诊断。

## 验收标准

- [x] 停止态规则行显示 `启动`，而不是空白动作位。
- [x] `启动` 调用现有 `startRule` 路径。
- [x] Swift shell UI 规范记录资源登记状态动作包含 `启动`。
- [x] 视觉 QA 密度夹具首屏包含停止态规则。
- [x] `swift build` 通过。
- [x] `git diff --check` 通过。
- [x] `scripts/visual-qa/relaydock-window-snapshot.sh` 通过，并在资源登记截图中确认 `已停止` 行显示 `启动`。
