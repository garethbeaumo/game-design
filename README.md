# game-design

面向持续迭代开发的中文游戏策划 Skills：设计规则差量写入、专项证据调查、高影响方案收束，以及版本与多人协作治理。

这四个 Skill 按真实工作需求触发，不要求先完成整套概念案、系统地图或 GDD，也不组成固定的线性流水线。

## 一键安装

需要本机有 Node.js。在任意项目目录执行：

```bash
npx skills add garethbeaumo/game-design -y
```

常用变体：

```bash
# 安装到当前项目（推荐）
npx skills add garethbeaumo/game-design -y

# 只装到 Cursor
npx skills add garethbeaumo/game-design -a cursor -y

# 只装指定 Skill
npx skills add garethbeaumo/game-design -s design-docs -s design-inference -y

# 先列出再决定
npx skills add garethbeaumo/game-design -l
```

安装后，Cursor、Claude Code、Codex 等会按各自目录加载 `SKILL.md`（例如项目内 `.agents/skills/`，或全局 `~/.cursor/skills/`）。

基于 [skills](https://github.com/vercel-labs/skills) CLI（[skills.sh](https://skills.sh)）。

目前优先使用项目级安装；`skills` CLI 的[全局安装发现问题](https://github.com/vercel-labs/skills/issues/1874)修复前，Codex、Cursor 等可能出现安装成功但无法发现 Skill 的情况。

## Skills

| Skill | 职责 |
|-------|------|
| `design-docs` | 对概念约束、系统登记和功能规则做最小差量写入 |
| `design-evidence` | 调查竞品、试玩、指标和当前实现等专项事实 |
| `design-inference` | 收束高影响真实候选、Prototype 与可审计决定 |
| `design-workflow` | 治理版本范围、多人责任、关键路径、发布门槛与只读快照 |

## 目录

- `skills/`：四个可安装 Skill 的唯一运行时权威。
- `planning/`：清单、路由契约、评测夹具和维护脚本，不随运行时 Skill 安装。

## 校验

```powershell
# 静态契约、引用和评测覆盖
pwsh -NoProfile -File planning/scripts/validate-planning-skills.ps1

# 使用 Codex CLI 执行模型路由评测
pwsh -NoProfile -File planning/scripts/run-planning-route-evals.ps1
```

静态校验不调用模型。路由评测脚本当前要求 Windows、PowerShell 7 和已登录的 Codex CLI。
