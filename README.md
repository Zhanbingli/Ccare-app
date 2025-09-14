ChronicCare（Ccare）
====================

一个基于 SwiftUI 的慢病自我管理 App 示例，支持生命体征记录、用药提醒、依从性统计、药效评估、HealthKit 导入/导出、PDF 报告以及本地备份/恢复。

主要功能
- 生命体征：血压、血糖（支持 mg/dL / mmol/L）、体重、心率的添加与趋势图展示（Charts）。
- 用药管理：多时段提醒、通知动作（已服用/延后/跳过）、同日同时段抑制重复提醒。
- 依从性：基于“计划时段”的 7 日依从性统计（更真实）。
- 药效评估：对降压药/降糖药进行“单药级别”的启发式评估，并在趋势页做“类别汇总”。
- 健康数据：与 HealthKit 授权、导入最近 30 天数据（支持去重逻辑）、PDF 报告导出、本地 JSON 备份/恢复。

运行环境
- Xcode 15+，iOS 16+。
- `Info.plist` 需包含 `NSHealthShareUsageDescription` 与 `NSHealthUpdateUsageDescription`。
- 已包含 `ChronicCare.entitlements` 并启用 HealthKit。

项目结构（部分）
- `ChronicCare/Views/*`：页面（Dashboard/Measurements/Trends/Medications/Profile）。
- `ChronicCare/DataStore.swift`：数据层（JSON 持久化、统计、Upsert）。
- `ChronicCare/Models.swift`：模型定义（含 `MedicationCategory`）。
- `ChronicCare/EffectivenessEvaluator.swift`：药效评估算法。
- `ChronicCare/Notification*`：本地通知的管理与处理。
- `ChronicCare/HealthKitManager.swift`：HealthKit 授权、读写封装。
- `ChronicCare/PDFGenerator.swift`：PDF 报告生成（血糖单位按偏好显示）。
- `ChronicCare/DesignSystem.swift`：卡片、折叠标题、按钮瓷砖等 UI 组件。

核心闭环与数据口径
- Upsert 写入：提供 `DataStore.upsertIntake(medicationID:status:scheduleTime:at:)`，确保“同日/同药物/同时段”只有一条最终状态，避免统计与 UI 不一致。
- 依从性（7 日）：以“计划时段”为分母，当天同一时段取“最新状态”为分子（只计已服用）。`DataStore.weeklyAdherence(...)` 已按此口径实现。
- 通知抑制：通知动作（已服/跳过）会抑制当日同一时段的前台通知，避免重复横幅；延后（Snooze）仅堆叠 1 条。
- 逾期判定：Dashboard 使用“逾期宽限（15/30/60 分钟，可在 Preferences 设置）”进行 UI 判定，不写入数据。

血糖单位与目标
- 存储口径：血糖内部统一 mg/dL 存储；显示/输入按偏好单位转换（mmol/L = mg/dL / 18）。
- 偏好设置：More > Preferences 中设置“Blood Glucose Unit”（全局默认）。添加血糖时可点击“Change”仅对本次覆盖单位。
- 目标设置：More > Goals 中，血糖上下限以偏好单位显示并转换存储；Trends 的正常带与异常点判定也会按偏好单位显示。

趋势图（Trends）
- 血压：按“日中位数”聚合收缩压/舒张压（减少噪声），并显示高阈值线与阴影带。
- 其他类型：绘制原始折线，显示目标正常带，异常点红色高亮。
- KPI：最新值、变化、7 日均值、7 日达标率。

药效评估（Effectiveness Evaluator）
- 评估粒度：按“单药（Medication.id）”进行评估；类别（降压药/降糖药）仅决定指标与趋势页的“类别汇总展示”。
- 入口标注：在“用药”添加/编辑中设置“Category”（Unspecified/Antihypertensive/Antidiabetic）。未指定类别不参与评估。
- 数据窗口：
  - 降压药（血压）：用药前 2 小时内最近一次测量为“前”，用药后 1–6 小时内第一次测量为“后”；对每个“已服用”事件计算（后−前），取中位数作为“剂量级”变化（收缩/舒张）。
  - 降糖药（血糖）：用药前 1 小时为“前”，用药后 1–3 小时为“后”；对每个“已服用”事件计算（后−前），取中位数。
- 长期趋势：近 14 天均值 − 前 14 天均值（负数代表改善）。
- 依从性约束：近 7 天平均依从性需达到阈值（默认 60%）。
- 判定阈值（可配置，默认“均衡” Balanced）：
  - Balanced：BP 剂量级 ≥5 mmHg（下降）、移动平均 ≥5 mmHg（下降）；GLU 剂量级 ≥10 mg/dL、移动平均 ≥10 mg/dL；最少样本数 3；依从性 ≥0.6。
  - Conservative：BP 7 / GLU 15；Aggressive：BP 3 / GLU 7（更容易判定有效）。
- 置信度：综合（剂量级改变量占比 + 移动平均改变量占比）× 样本数比例 × 依从性因子 得到 0–100%，在 Medications/Trends 中展示。
- 结果呈现：
  - Medications：每个已分类药物显示“类别 + 结论 + 置信度”。
  - Trends（血压/血糖）：图表下方“药效评估”卡片显示“同类别”药物的有效/不确定/无效数量，并列出最多 3 个药物的结论与置信度。
- 局限与说明：该算法用于自我管理的趋势参考，不构成医疗建议；样本不足、多药联用、饮食/运动/睡眠等混杂因素会影响结论，详见 More > How It Works。

偏好设置（Preferences）
- Haptics：触觉反馈开关（`hapticsEnabled`）。
- Overdue Grace：逾期宽限（15/30/60 分钟，`prefs.graceMinutes`）。
- Blood Glucose Unit：血糖显示单位（`units.glucose`）。
- Effectiveness Settings：
  - Mode（`eff.mode`）：conservative / balanced / aggressive。
  - Min Samples（`eff.minSamples`）：最少样本数（3/5/7）。
  - 依从性阈值（内部 `eff.adh`，默认 0.6，可扩展暴露）。

数据导入/导出
- HealthKit：Connect / Import 30d（导入最近 30 天，含简单去重），DEBUG 下可 Export Recent 10（带确认与本地去重标记）。
- PDF 报告：Export Report (PDF)，包含药物清单、最近测量摘要、7 日依从性概览（血糖单位随偏好）。
- 本地备份：Export Data（JSON，包含 measurements/medications/intakeLogs），可 Restore；偏好设置不包含在备份内。

More 页交互与分组
- 顶部四张概览卡片等宽对齐。
- Quick Actions / Preferences / Goals / About / How It Works 均可折叠，并记忆展开状态。
- DEBUG-only：Load Samples、Export Recent 10 仅在 Debug 构建可见。

公共 API 摘要
- `DataStore.upsertIntake(medicationID:status:scheduleTime:at:)`：同日/同时段唯一状态写入。
- `DataStore.weeklyAdherence(for:endingOn:)`：近 7 天按“计划时段”口径的依从性数组。
- `DataStore.effectiveness(for:) -> MedicationEffectResult`：对单药进行评估（算法见上）。

如何操作（药效评估）
1) 在“用药”中为相关药物设置类别（降压/降糖）。
2) 正常记录“已服用”，并在“前后窗口”内记录相应测量（血压/血糖）。
3) 在“趋势”选择血压或血糖，查看图表下方“药效评估”统计卡片。
4) 如需调整算法敏感度与样本门槛：More > Preferences > Effectiveness Settings。

免责声明
- 本 App 为健康自我管理与趋势参考工具，药效评估为启发式算法，并非医疗建议；如有任何疑问，请咨询专业医生。

提交到 GitHub（说明）
1) 初始化与首次提交（如未初始化仓库）：
   ```bash
   git init
   git add .
   git commit -m "feat: add effectiveness evaluator, preferences, collapsible UI, units + goals, trends card"
   ```
2) 创建远端仓库（GitHub 网页或 CLI），拿到远端地址（例如 `git@github.com:YOUR_NAME/ChronicCare.git`）。
3) 绑定远端并推送：
   ```bash
   git remote add origin git@github.com:YOUR_NAME/ChronicCare.git
   git branch -M main
   git push -u origin main
   ```
如需我代为推送，请提供 GitHub 仓库地址与可用凭据（PAT/SSH），并授权网络访问。

后续建议（可选）
- 数据导出/导入：支持 CSV/JSON 文件备份与恢复。
- 用药编辑：允许修改时间与剂量并自动重排/重计划通知。
- 健康数据去重：以更稳健的唯一键（type+time±阈值+值）合并，避免重复导入。
- 错误提示：将加载/保存/HealthKit 错误反馈到 UI（非仅控制台）。
- 自动化测试：为 `DataStore.weeklyAdherence`、通知调度与 PDF 生成添加单元测试。

故障排查
- HealthKit 授权失败：确认已在 Capabilities 中启用 HealthKit 且 `Info.plist` 两个描述键已填写。
- 通知不弹出：首次授权被拒绝可在系统设置中重新开启，或在 iOS 模拟器的“功能-触发通知”检查。
