# RelayDock 信息架构与界面结构

更新时间：2026-04-22

## 1. 顶层页面

当前已稳定下来的顶层结构是：

- 运行与恢复
- 资源登记
- 日志
- 诊断
- 偏好设置

## 2. 总体壳层

产品应采用桌面原生壳层，而不是网页后台布局。

LocalPort 原型可作为壳层、信息密度和交互语义参考，具体吸收边界见 [11-localport-prototype-reference.md](/Users/workspace/relaydock/documents/11-localport-prototype-reference.md)。

已确认元素：

- 红黄绿交通灯
- 可拖拽标题栏
- Source List 风格左侧栏
- 顶部工具栏
- 底部状态栏

## 3. 运行与恢复

### 页面职责

这是运行态工作区。

它只关心：

- 正在工作的映射
- 中断但可恢复的映射
- 当前主机分组下的批量动作

### 列表结构

建议：

- 按主机分组
- 默认展开
- 支持折叠
- 只显示有运行项或恢复项的主机

### 主机头部信息

建议包含：

- 主机名
- IP/域名或连接身份摘要
- 在线状态
- 当前活跃服务数

### 服务行结构

建议采用两行紧凑布局。

第一行：

- 服务图标
- 服务名
- 本地别名入口
- 右侧 provider 指示

第二行：

- 端口映射
- 状态
- 时长
- 延迟
- 今日失败次数
- 行内动作

### UI 细则

- `via/provider` 应尽量放在右侧且轻量化
- 状态遥测应稳定右对齐
- 停止类动作放在最右
- Provider 更适合图标 + 极短标签

## 4. 资源登记

### 页面职责

这是配置中心。

负责：

- 主机
- 规则
- 预设
- Provider target
- SSH 命令导入

### 页面结构

建议采用：

- 左侧主机列表
- 右侧当前主机详情

### 主机详情上半区

应更像原生上下文工具区，而不是多个独立卡片。

建议承载：

- 当前主机摘要
- 主机设置入口
- 连接策略摘要

### 规则区

应包含：

- 当前主机规则筛选
- 导入 SSH 命令
- 新增规则
- 规则清单

### 新增规则

优先使用弹窗，而不是过重的页面内大卡片。

## 5. 日志

日志页应是沉浸式 console/terminal 风格，并把横向空间优先交给结构化日志列表。

明确不应是：

- 大窗口里再套一个黑色卡片
- 左侧全局 sidebar 之后再套一层诊断范围 sidebar

建议：

- 用顶部 tabs / segmented filter 切换日志范围
- 主要消费 `runRecoverySnapshot.events` 和当前 snapshots
- 不假装已有 provider 实时流式日志

## 6. 诊断

诊断页负责呈现当前可判定事实，而不是和日志 console 混在一个三列页面。

建议包含：

- active checks
- inspector-style bridge / snapshot facts
- recovery candidates
- runtime issue rows

说明：

- 诊断继续消费当前 snapshots 和 runtime events
- Swift 不应发明 provider/runtime 状态机

## 7. 偏好设置

设置页应保持收敛：

- 导航像 source list，不像一排按钮
- 不要后台风标签页质感

## 8. 图标与识别

### 主机图标

需要按 OS / 发行版显示图标。

### 服务图标

可综合：

- favicon
- repo icon
- 端口用途推断
- 服务名称推断

### Provider 图标

第一版重点支持：

- SSH
- Tailscale

## 9. 风格禁区

明确避免：

- Dashboard 风首页
- KPI 卡片
- 大白卡套大白卡
- 过重按钮
- 过强阴影
- 明显网页化容器层级
