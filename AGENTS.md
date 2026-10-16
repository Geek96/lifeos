# LifeOS 协作约定

适用于人和 AI 编程助手。架构与界面体系沿用 CourseOS（[Geek96/courseos](https://github.com/Geek96/courseos)）。

## 定位

LifeOS 是“高级日历”：学习之外的生活琐事放在时间上，课表和课业由 CourseOS **单向只读**叠加。
不做 checklist、完成率、逾期催促、每日反馈或反思。

## 架构

- 业务逻辑在 `LifeOSCore` 本地包（零 AI、可测试）；App target 只负责界面与系统集成。
- 工程由 `project.yml`（XcodeGen）生成，改了跑 `./Scripts/bootstrap.sh`。
- Swift 6 严格并发；新增代码注释用中文。
- **写入边界**：App 只写 LifeOS vault（事项文件的时间/状态字段、新建事项、收件箱一行、`lifeos.json`）。
  事项正文（准备信息）由 agent 写。**永远不写 CourseOS 学期目录里的任何文件。**
- vault 格式与 agent 规则：vault 里的 `.lifeos/RULES.md`；agent skill：[Geek96/life-manager](https://github.com/Geek96/life-manager)。
- `templates/vault/` 是新 vault 的模板（RULES.md 第 1 版、入口文件、收件箱、lifeos.json 示例）。

## 读取 CourseOS 的什么

`courseos.json`（课程是否追踪 + 手填档案）、`.courseos/profiles/*.json`（上课时间/地点）、
`_exports/planvault-time-sensitive.md`（截止、考试、预估工作量、status）、`.courseos/projects/*.json`（追踪中的子任务）。

## 验证

1. `swift test --package-path LifeOSCore`
2. `xcodebuild -project LifeOS.xcodeproj -scheme LifeOS -configuration Debug -derivedDataPath build.noindex build`
3. 改了 UI 就打开 App 肉眼确认（今天 / 周 / 月 / 收件箱 / 检查器）。
