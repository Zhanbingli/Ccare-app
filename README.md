Ccare
================

一个基于 SwiftUI 的慢病自我管理 App 示例，支持记录生命体征、用药提醒、依从性统计、HealthKit 数据导入/导出以及 PDF 报告导出。

主要功能
- 生命体征：血压、血糖、体重、心率的添加与趋势图展示（Charts）。
- 用药管理：按时间提醒、快速标记是否已服药、贪睡 10 分钟。
- 依从性：近 7 天总体或按药品统计并列表展示最近记录。
- 健康数据：与 HealthKit 授权、导入最近 30 天、导出最近 10 条至 Health。
- 报告导出：生成最近数据的 PDF 并通过系统分享。

运行环境
- Xcode 15 或以上，iOS 16 及以上（使用 Swift Concurrency 与 Charts）。
- 需要在项目 `Info.plist` 中配置 `NSHealthShareUsageDescription` 与 `NSHealthUpdateUsageDescription` 描述。
- 已包含 `ChronicCare.entitlements` 并启用 HealthKit。

项目结构
- `ChronicCare/Views/*`：各个页面（Dashboard/Measurements/Trends/Medications/Adherence/Profile）。
- `ChronicCare/DataStore.swift`：数据层（本地 JSON 持久化、统计计算）。
- `ChronicCare/Models.swift`：模型定义。
- `ChronicCare/Notification*`：本地通知的管理与处理。
- `ChronicCare/HealthKitManager.swift`：HealthKit 授权、读写封装。
- `ChronicCare/PDFGenerator.swift`：PDF 报告生成。

本次优化
- 主线程一致性：将 `DataStore` 标注为 `@MainActor`，确保跨线程调用（如通知回调）时 UI 状态安全更新。
- 插入保持排序：`addMeasurement` 根据日期降序插入，避免在视图层重复排序，改善内存与 CPU 开销。
- 持久化防抖：对 `@Published` 变更增加 300ms debounce，减少频繁写盘的 I/O 抖动。
- 更安全的写入：写文件使用 `atomic + completeFileProtection`，在设备锁定时提供更高数据保护。
- 通知去重：贪睡通知在重新计划前先移除旧的相同 ID，避免堆叠；删除药品时同时移除已送达与待触发通知。

后续建议（可选）
- 数据导出/导入：支持 CSV/JSON 文件备份与恢复。
- 用药编辑：允许修改时间与剂量并自动重排/重计划通知。
- 健康数据去重：以更稳健的唯一键（type+time±阈值+值）合并，避免重复导入。
- 错误提示：将加载/保存/HealthKit 错误反馈到 UI（非仅控制台）。
- 自动化测试：为 `DataStore.weeklyAdherence`、通知调度与 PDF 生成添加单元测试。

故障排查
- HealthKit 授权失败：确认已在 Capabilities 中启用 HealthKit 且 `Info.plist` 两个描述键已填写。
- 通知不弹出：首次授权被拒绝可在系统设置中重新开启，或在 iOS 模拟器的“功能-触发通知”检查。
