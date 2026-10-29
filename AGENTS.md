# LifeOS 协作约定

适用于人和 AI 编程助手。架构与界面体系沿用 CourseOS（[Geek96/courseos](https://github.com/Geek96/courseos)）。

## 定位

LifeOS 是“高级日历”：学习之外的生活琐事放在时间上，课表和课业由 CourseOS **单向只读**叠加。
不做 checklist、完成率、逾期催促、每日反馈或反思。

## 架构

- 业务逻辑在 `LifeOSCore` 本地包（零 AI、可测试）；App target 只负责界面与系统集成。
- 工程由 `project.yml`（XcodeGen）生成，改了跑 `./Scripts/bootstrap.sh`。
- Swift 6 严格并发；新增代码注释用中文。
- App 里没有“交给 agent”“在 Obsidian 中打开”之类的按钮（用户 2026-10-22 要求去掉：自己会在会话里叫 agent）。
- **写入边界**：App 只写 LifeOS vault（事项文件的时间/状态字段、新建事项、收件箱一行、`lifeos.json`；
  健康插件开着时，在 `健康/饮食/当天.md` 的表末尾追加一行还没估算的记录；
  出行插件勾“要带”清单；物品插件快速记一件东西（新建只有名称和位置的卡）、往 `物品/想买.md` 加一行；远景插件勾项目步骤；分享的长图和 .ics 存到用户的“下载”）。
  事项正文（准备信息）由 agent 写。**永远不写 CourseOS 学期目录里的任何文件。**
- vault 格式与 agent 规则：vault 里的 `.lifeos/RULES.md`；agent skill：[Geek96/life-manager](https://github.com/Geek96/life-manager)。
- `templates/vault/` 是新 vault 的模板（RULES.md 第 10 版、入口文件、收件箱、lifeos.json 示例）。

## 插件

`lifeos.json` 的 `plugins` 开关（设置 → 插件）。数据格式写在 vault 的 `.lifeos/RULES.md`“插件”一节。
- **健康**（`plugins.health`）：`LifeOSCore/Health.swift` 解析 `健康/目标.md`、`健康/饮食/*.md`、`健康/复测/*.md`，
  训练是带 `plugin: health` 的普通事项。界面在 `LifeOS/UI/HealthViews.swift`：今天视图的健康卡片（圆环 + 今天练什么 + 记一顿）、
  左栏“插件”里直接分三页，都能按 日 / 周 / 月 看（`HealthPeriod` + `HealthPeriodBar`，`LifeOS/UI/HealthPeriodViews.swift` 里还有月历热力格 `MonthHeatGrid`、按天柱状图 `DailyBarChart`）：
  营养（`NutritionViews.swift`：日 = 圆环、记一顿 / 补记、微量营养；周月 = `nutritionSummary` 平均、按天的图、热力格）、
  健身与锻炼（`FitnessViews.swift` 的 `FitnessView`：分页 记录（日 / 周 / 月，`fitnessSummary`，计划和实际对照，“记一笔”放进收件箱）/ 长期趋势 / 计划与动作）、
  休息与放松（`SleepViews.swift` 的 `RestView`：记一晚、`sleepSummary` 平均几点睡几点起、睡眠时段图）；三页共用 `HealthPageScaffold`，`AppModel.Page.isHealth` 判断是不是这三页。
  营养页最下面是体重（`WeightSection`；`LifeOSCore/Weight.swift` 读写 `健康/体重.md`，目标范围来自 `目标.md` 的 `weight_gain_min/max`）；
  休息与放松的周 / 月有 `SleepContextSection`：训练（训练记录）和考试（`AppModel.examDays`，不受图层开关影响）标在时间轴上，`SleepComparison` 分开平均。
  新加 UI 文件后要重新跑 `xcodegen generate`（`.xcodeproj` 不进 git）。
  每天的目标按 `HealthSnapshot.targets(on:)` 取（`健康/目标历史/` + `目标.md` 的 `since`）；平均只用 `completeDays`（饮食文件 `complete`，没写时过去算记全、今天不算）。
  睡眠：`LifeOSCore/Sleep.swift` 解析 `健康/睡眠/YYYY-MM.md`（表 `| 日期 | 入睡 | 起床 | 时长 |`，日期是起床那天，没写时长就按入睡、起床算，跨午夜照算）；
  界面在 `LifeOS/UI/SleepViews.swift`（`RestView`）：“记一晚”表单（`HealthStore.recordSleep`，同一天替换、按日期插入、可撤销）+ 统计和记录；今天卡片上有“昨晚睡了”。

- **消费**（`plugins.finance`）：`LifeOS/UI/FinanceViews.swift` 的 `FinanceView` 分 概览（类别圆环 `CategoryDonut`、本月累计对照上月 `CumulativeSpendingChart`、预算进度 `BudgetProgress`）/ 流水 / 账户 / 订阅；
  `LifeOSCore/Finance.swift` 解析 `财务/流水/*.md`、`账户.md`、`订阅.md`、`预算.md`（预留），订阅扣款日上日历（期限）。
- **物品**（`plugins.things`）：`ThingsView` / `ThingsPanel`：`LifeOSCore/Things.swift` 解析 `物品/*.md`（`type: thing`），算下次补货、保养（`Interval`），
  并生成日历上的出现（退货、保修 = 期限；补货、保养 = 提前 7 天的时间窗）。界面在 `LifeOS/UI/ThingsViews.swift`：
  找东西 / 资产 / 补货与保养 / 售后 / 搬家，加上每件东西的详情页（`maintenance: detailed` 的有规格、保养计划、保养记录）。
  分页用自己画的 `TabStrip`：五个分页的原生分段控件在窄栏里会触发 AppKit 约束死循环（NSGenericException）。

- **出行**（`plugins.travel`）：`LifeOSCore/Travel.swift` 解析 `出行/*.md`（`type: trip`，按天的时间线、交通、住宿、期限、预算、要带清单）和 `出行/想去.md`；
  `TravelCalendar` 把整趟行程（跨天）、带时间的安排、期限、免费取消截止放上日历。界面 `LifeOS/UI/TravelViews.swift`：近期 / 全部 / 想去，
  详情页按天浏览（当天时间线、当天交通、当晚住宿）。App 只会改“要带”清单的勾（`TravelStore.togglePacking`，核对那一行内容才改）。
  分享：`LifeOSCore/TripShare.swift` 生成微信文字、.ics、网页（带隐私选项）；`LifeOS/UI/TripShareViews.swift` 是分享面板和长图（ImageRenderer）。
  App 只做文字、长图、.ics；分享链接（`share_url`）由用户在会话里叫 agent 发布，App 里只显示和复制已有链接。
  没写 start 的出行是“想法”（`Trip.dated == false`，start 记成 .distantFuture）：能打开详情页，不上日历，列表里放在“还没定日期”。
- **远景**（`plugins.vision`）：`LifeOSCore/Vision.swift` 解析 `远景/愿景/`（`type: vision`，`shape: timeline` 时间甬道 + checkpoint 表，
  `shape: list` 平铺清单 + 标签）、`远景/项目/`（`type: project`，步骤、进度、进展记录）、`远景/奇思妙想/`（`type: idea`，分类）。
  `FuzzyTime` 把“2026-12 中旬”“2027 夏”这类模糊时间解析成一段区间。`VisionCalendar` 只把项目里带日期的步骤放上日历
  （checkpoint 常和已有事项重合，不上日历）。界面 `LifeOS/UI/VisionViews.swift`：愿景 / 项目 / 奇思妙想，时间甬道 `VisionCorridor`。
  清单型愿景的每个地方按“行程”列（或名字）对应一个出行，点开跳到出行详情页，返回回到愿景（`tripReturnVisionID`）。
  内容都由 agent 写；App 只会改项目步骤的勾（`VisionStore.toggleStep`，核对那一行内容才改）。

## 读取 CourseOS 的什么

`courseos.json`（课程是否追踪 + 手填档案）、`.courseos/profiles/*.json`（上课时间/地点）、
`_exports/planvault-time-sensitive.md`（截止、考试、预估工作量、status）、`.courseos/projects/*.json`（追踪中的子任务）。

`lifeos.json` 的 `courseos.semester` 支持相对路径（`LifeConfig.CourseOSLink.resolvedSemesterURL(vault:)`，
以 `/` 开头按绝对路径，否则相对 vault 文件夹解析），同一个 Obsidian 目录下的两个兄弟 vault 换电脑、换用户名不用改配置；
设置里的文件夹选择器（`SettingsView.chooseSemester`）用 `LifeConfig.CourseOSLink.relativePath(from:to:)` 自动存成相对路径。

## 签名

`project.yml` 用用户免费 Apple ID 的 Personal Team（`DEVELOPMENT_TEAM: 9DHJNL5JTU`）做 Apple Development 签名，
designated requirement 绑定证书，重新编译后不变，macOS 不会反复询问“桌面”文件夹权限（vault 在桌面上）。
用 ad-hoc 签名时每次编译都会被当成新 App，授权前读不到 vault，界面全空。编译命令加 `-allowProvisioningUpdates`。

## 验证

1. `swift test --package-path LifeOSCore`
2. `xcodebuild -project LifeOS.xcodeproj -scheme LifeOS -configuration Debug -derivedDataPath build.noindex build`
3. 改了 UI 就打开 App 肉眼确认（今天 / 周 / 月 / 收件箱 / 检查器）。
