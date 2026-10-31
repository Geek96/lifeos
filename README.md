<p align="center"><img src="docs/images/icon.png" width="128" alt="LifeOS icon"/></p>

# 🗓️ LifeOS

学习之外的生活，放在一个“高级日历”上。CourseOS 的姊妹 App：同一套 SwiftUI 架构和界面，
定位不同——不是待办清单，没有打卡、完成率和反思。

- **三种事项**：约定（有起止时间）、期限（过了会出事，提前几天出现在“快到了”）、时间窗（这段时间内找空做）
- **课程图层（只读）**：从 CourseOS 学期目录读上课时间（按你的 section）、截止、考试、长期项目节点
- **负荷**：上课 + 约定 + 课业（课程截止的预估工作量摊到截止前几天），每天标“轻松 / 一般 / 很满”
- **轻提示**：时间重叠、考试当天/前一晚有安排、很满的一天——只提醒，不拦
- **找空档**：时间窗按负荷推荐哪天哪段时间去办，一键排进去
- **收件箱**：随手记一句，交给 agent（life-manager skill）整理，它会先问你再放进日历
- **准备信息**：选中事项，让 agent 查地址、路程、要带的材料，写进事项正文
- 周视图拖动改时间（15 分钟对齐、可跨天），所有改动可撤销；过去的事自然淡出
- **重复事项只改一次**：取消某一次、只挪某一次的时间（可以挪到另一天）、只改某一次的标题 / 地点 / 备注，
  重复规则不动；改过的那一次带 ✎ 图标和“已调整（原 …）”字样，电脑和手机都显示

## 构建

```bash
./Scripts/bootstrap.sh
xcodebuild -project LifeOS.xcodeproj -scheme LifeOS -configuration Debug -derivedDataPath build.noindex build
open build.noindex/Build/Products/Debug/LifeOS.app
```

### 手机版（除了勾购物清单都只读）

`LifeOSPhone` 是 iPhone 版：今天、日历、营养三页；营养页分 记录 / 食谱 / 购物清单。食谱按顿分组，点进去看每份营养、材料（在哪买）、做法。
购物清单按在哪买分组，点一下勾上 / 取消——这是手机唯一会写的地方：只改 `健康/购物清单.md` 里那一行的勾选框，不新建、不删除、不改名任何文件；
加东西、清掉买好的还在电脑上做。vault 用 [Möbius Sync](https://www.mobiussync.com)（Syncthing）同步到手机，
文件夹设成“发送和接收”（勾的结果才能同步回电脑）；第一次打开在“文件”里选同步过来的文件夹（选 vault 的上一级，课程表也能读到）。
免费 Apple ID 签的手机 App 7 天后要重新装一次。

## 准备 vault

数据都在一个 vault 文件夹里（默认 `~/Documents/LifeOS`，首次打开可选其他位置），每件事一个 Markdown 文件，Obsidian 可读。

事项文件的完整格式见 vault 里的 `.lifeos/RULES.md`。重复事项里单独一次的改动写在 frontmatter 的 `exceptions` 列表，
用 `date`（原本那一次的日期）对上是哪一次：

```yaml
repeat: weekly:mon,wed
exceptions:
  - date: 2026-11-03      # 这次取消
    skip: true
  - date: 2026-11-05      # 这次挪到晚上（也可以挪到另一天）
    start: 2026-11-05 20:00
    end: 2026-11-05 21:00
    note: 改到晚上        # 也可以写 title / location，只改这一次
```

1. 把 `templates/vault/` 复制成你的 vault，按需改 `lifeos.json`（CourseOS 学期目录、上课起止日、section）。
2. 给 agent 装 skill：`npx skills add Geek96/life-manager`（或把 `skills/life-manager` 链接进 `~/.claude/skills/`）。
3. 打开 LifeOS，设置里选 vault 和 CourseOS 学期目录。

## 和 CourseOS 的关系

[CourseOS](https://github.com/Geek96/courseos) 管课程，LifeOS 管生活。LifeOS 只读 CourseOS 的学期目录，从不写回。
