# game-design

中文游戏策划 Skills：证据、推论、正式落档、工作流治理与定案前拷问。

## 一键安装

需要本机有 Node.js。在任意项目目录执行：

```bash
npx skills add garethbeaumo/game-design -y
```

常用变体：

```bash
# 安装到当前项目（默认）
npx skills add garethbeaumo/game-design -y

# 全局安装，所有项目可用
npx skills add garethbeaumo/game-design -g -y

# 只装到 Cursor
npx skills add garethbeaumo/game-design -a cursor -y

# 只装指定 skill
npx skills add garethbeaumo/game-design -s design-workflow -s grill-me -y

# 先列出再决定
npx skills add garethbeaumo/game-design -l
```

安装后，Cursor / Claude Code / Codex 等会按各自目录加载 `SKILL.md`（例如项目内 `.agents/skills/`，或全局 `~/.cursor/skills/`）。

基于 [skills](https://github.com/vercel-labs/skills) CLI（[skills.sh](https://skills.sh)）。

## Skills

| Skill | 职责 |
|-------|------|
| `design-workflow` | 路线、里程碑、产物治理与入口路由 |
| `design-evidence` | 竞品 / 试玩 / 实现事实 |
| `design-inference` | 候选、取舍、`DEC-*`、Prototype |
| `design-docs` | 已确认概念 / 系统地图 / 功能规则 |
| `grill-me` | 高影响阻塞分支确认 |

## 目录

源文件在 `skills/`。

## 校验

```powershell
pwsh -NoProfile -File skills/design-workflow/scripts/validate-planning-skills.ps1
```
