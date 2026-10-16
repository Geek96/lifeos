---
rules-version: 1
---
# LifeOS 规则（在本 vault 工作的所有 agent 必读）

LifeOS 是一个“高级日历”：管学习之外的生活琐事。东西放在它发生的时间上，而不是清单里。
**不催、不打卡、不要求反馈或反思。** 过去的事自然淡出，没有“逾期”。

## 东西放在哪
- `事项/`：每件事一个 `.md` 文件（格式见下）。文件名 `YYYY-MM-DD 标题.md`（取 start 的日期）。
- `收件箱.md`：随手记，一行一条（`- ` 开头）。App 的“记一笔”也写这里。
- `备忘/`：查阅用的固定资料（证件到期、订阅、地址等），自由格式。
- `lifeos.json`：配置（CourseOS 学期目录、课程 section、图层），由 LifeOS App 维护。
- `.lifeos/journal.md`：agent 工作日志，只追加。

## 事项文件格式
```yaml
---
type: life-item
kind: event            # event 约定 | deadline 期限 | window 时间窗
title: 看牙
start: 2026-10-20 14:00  # event 开始；deadline 截止时间；window 窗口开始（可只写日期）
end: 2026-10-20 15:00    # event 结束（省略 = 1 小时）；window 窗口结束；deadline 不用
all_day: false           # 可选，event 全天
location: Midtown Dental # 可选
repeat: weekly:mon,wed   # 可选：daily | weekly:mon,tue,… | monthly:15 | yearly
repeat_until: 2026-12-31 # 可选
remind_days: 3           # 可选，deadline 提前几天出现在“快到了”（默认 3）
estimate: 1h             # 可选，window 大概要多久（App 据此找空档）
done: false              # 可选，deadline / window“办好了”
added_by: agent          # user | agent
created: 2026-10-15
---
正文 = 准备信息：要带什么、地址和路程、相关链接、原始邮件摘录……（agent 写，自由 markdown）
```
- 只有真正“过了会出事”的才用 deadline（续签、交税、退租、退课截止）。“这周内买菜”“11 月前换护照”用 window。
- 不要给事项加 checklist、进度、打分字段。

## 和 CourseOS 的关系（单向只读）
- LifeOS 只**读** CourseOS 学期目录（`lifeos.json` 的 `courseos.semester`）：`courseos.json`、
  `.courseos/profiles/`、`.courseos/projects/`、`_exports/planvault-time-sensitive.md`。
- **不往 CourseOS 写任何东西**，也不把课程待办复制成 LifeOS 事项——App 会把它们作为“课程图层”叠在日历上。
- 课程相关的事去 CourseOS 的 vault 处理，不在这里。

## 写入纪律
- agent 可以新建 `事项/` 文件、补写正文（准备信息）、整理 `收件箱.md`。
- 用户设过的时间字段（start/end/repeat/done）不要改，除非用户明确要求；发现有问题就在会话里说。
- 整理收件箱：每条先给用户看你打算建成什么（类型 + 时间），用户同意才建；建好的那行从收件箱删掉，
  拿不准的留着。
- 不删除、不移动、不重命名已有事项文件；用户要删，请用户自己删或明确同意。
- 从邮件、截图里提取日期时，写清来源；日期拿不准就问，不要猜。
- 语气：只陈述事实和建议，不催促、不评价、不问“今天过得怎么样”。

## 工作日志格式
每做完一件事，在 `.lifeos/journal.md` 末尾追加（只追加，不改旧内容）：

```
## 2026-10-15 10:32 · {agent 名} · {做了什么}
- 完成：…
- 待办：…
```

## 已安装的 skill
- life-manager：https://github.com/Geek96/life-manager（Claude Code：~/.claude/skills/life-manager）
