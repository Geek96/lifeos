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
- **重复事项的单独一次**：事项 frontmatter 的 `exceptions` 块状列表（`Frontmatter.list` / `setList` 读写，
  其他字段仍是单行 `key: value`；`Frontmatter.update` 删改块状字段时连缩进行一起处理）。每条 `date` = 原本那一次的日期，
  `skip: true` 取消；`start` / `end` 挪时间（可跨天；只写 `start` 按原时长平移，`start` 只写日期沿用原时刻）；`title` / `location` / `note` 只改这次。
  `LifeItem.exceptions`（`RecurrenceException`）→ `Recurrence.occurrences` 展开时套用：挪进区间的那次即使原日期在区间外也出现；
  `Occurrence.seriesStart` 是原本的开始、`adjusted` 标记改过、`note` 是这次的备注、`adjustedSummary` 给界面用的文字；
  id 仍按原日期（`路径@YYYY-MM-DD`），挪了也能保持选中。没有 `exceptions` 的文件行为不变，不重复的事项忽略它。
  电脑版检查器“这一次”：只改这一次…（`OccurrenceEditorSheet`）/ 取消这一次 / 恢复成原样，经 `VaultStore.setException` 写回；
  拖动已调整过的那一次只改它自己，拖动其他的仍是整个系列。界面用 `Occurrence.adjustedSystemImage` 图标 + 文字标出（不只靠颜色）。
  手机版只显示。注意：改系列的 start（编辑或拖动整个系列）不会跟着改 `exceptions` 的 date，挪了日期后旧例外可能对不上。
- `templates/vault/` 是新 vault 的模板（RULES.md 第 11 版、入口文件、收件箱、lifeos.json 示例）。

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
  营养页分页 记录 / 食谱 / 购物清单 / 备餐（`RecipeViews.swift`；`LifeOSCore/Recipes.swift`：`Recipe` 读 `健康/食谱/`，
  `ShoppingList` 按食谱和份数合并材料、读写 `购物清单.md`，`MealPrep` 读写 `备餐.md`；“吃了一个”用 `appendMeal(nutrition:)` 按表头填营养）。
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

## 手机版（`LifeOSPhone/`）

- **除了勾购物清单都只读**：内容由电脑决定。vault 通过 Möbius Sync（iPhone 上的 Syncthing 客户端）同步到手机，
  文件夹在 Möbius 里设成“发送和接收”（Send & Receive），手机勾的购物清单才能同步回电脑。
  手机唯一的写入是 `PhoneModel.toggleShopping` → `ShoppingList.toggle`（`LifeOSCore/Recipes.swift`，电脑版 `AppModel.toggleShopping` 也用它）：
  写前在 `NSFileCoordinator` 里从磁盘重读，按 段 + 文字 + 同段重名序号（`ShoppingItem.occurrence`）+ 当前勾选状态找那一行，
  只把勾选框里那一个字节在空格和 `x` 之间换（`X` 取消时也变空格），其他字节原样；找不到 / 对不上（电脑上改过）就不写，重新读并提示一句。
  新内容先写到 App 自己的 tmp 目录，再 `rename(2)` 换掉原文件（同卷原子，不往 vault 里放临时文件）。
  手机不新建、不删除、不改名任何 vault 文件，不加项、不清掉买好的（这些在电脑上做）。其他页面（今天、日历、营养记录、食谱）仍然只读。
- 共用 `LifeOSCore`，以及 `LifeOS/UI/Shared/` 里的 `Theme.swift`、`Fmt.swift`（这两个文件不能依赖 `AppModel` 或 AppKit）。
  `PhoneModel` 的日历算法要和 `AppModel` 保持一致（`occurrences` / `loads` / `upcoming`）。
- 第一次打开在“文件”里选同步过来的文件夹：选 vault 本身或它的上级（往下找三层有 `lifeos.json` 或 `.lifeos/` 的文件夹）。
  `lifeos.json` 里的 CourseOS 是相对路径（`../GT-semseters/2026Fall`），所以要读课程就得选 vault 的上级，
  Möbius 里也要同步学期目录的 `courseos.json`、`_exports/`、`.courseos/`。选的文件夹存成 bookmark。
- 没有文件监听（`VaultWatcher` 只有 macOS 有），回到前台和下拉时重新读。
- 现在三页：今天、日历（月历 + 这天 / 这周）、营养。营养页顶部分段 记录 / 食谱 / 购物清单（和电脑版营养页的分页对应，备餐只在电脑上）：
  记录 = 某天对目标 + 吃了什么 + 7 天热量柱；食谱（`PhoneRecipeViews.swift`）按顿分组，点进去看每份营养、材料和在哪买、做法、备注；
  购物清单按在哪买分组，点一下勾 / 取消。放进营养页的分段而不是单独一个 tab：和电脑版的结构一致，底栏保持三个。
- 调试：启动参数 `-debugVaultPath <路径>` 跳过文件选择（只在 Debug），`-debugTab 0|1|2` 直接打开某一页，
  `-debugNutritionPage 1|2` 打开营养页的 食谱 / 购物清单，`-debugRecipe <名字>` 打开某个食谱，
  `-debugToggleShopping <那一项的文字>` 启动时勾 / 取消一次（只对 `-debugVaultPath` 指的副本，测勾选写回用）。
  模拟器读 `~/Desktop` 会卡在系统授权上，先把 vault 复制到别处再指过去。

## 签名

`project.yml` 用用户免费 Apple ID 的 Personal Team（`DEVELOPMENT_TEAM: 9DHJNL5JTU`）做 Apple Development 签名，
designated requirement 绑定证书，重新编译后不变，macOS 不会反复询问“桌面”文件夹权限（vault 在桌面上）。
用 ad-hoc 签名时每次编译都会被当成新 App，授权前读不到 vault，界面全空。编译命令加 `-allowProvisioningUpdates`。

## 验证

1. `swift test --package-path LifeOSCore`
2. `xcodebuild -project LifeOS.xcodeproj -scheme LifeOS -configuration Debug -derivedDataPath build.noindex build`
   手机版：`xcodebuild -project LifeOS.xcodeproj -scheme LifeOSPhone -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath build.noindex build`
3. 改了 UI 就打开 App 肉眼确认（今天 / 周 / 月 / 收件箱 / 检查器）。
