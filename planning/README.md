# 策划 Skill 控制面

本目录维护四个策划 Skill 的清单、路由契约和验证工具，不随运行时 Skill 安装。游戏版本治理使用 `design-workflow`；Skill 自身的职责、触发、测试和发布维护留在这里。

## 权威与控制面

- 运行时权威：`skills/design-docs`、`design-evidence`、`design-inference`、`design-workflow`。
- 控制契约：本目录的 `manifest.json`、`routing-matrix.md`、schema、路由/行为 eval 和脚本。
- 仓库使用标准 `skills/` 安装布局，不保存同名生成副本。
- `grill-me` 和其他已废弃策划 Skill 只作为禁止回归项保留在 manifest。

## 验证

```powershell
pwsh -NoProfile -File 'planning/scripts/validate-planning-skills.ps1'
pwsh -NoProfile -File 'planning/scripts/run-planning-route-evals.ps1'
```

CI 或需要可复现实验时给路由脚本显式传入 `-Model <model-id>`；`-ReasoningEffort` 默认 `low`，因为这里只做分类。未传模型时脚本忽略用户配置，使用并记录 Codex CLI 内建默认模型及 CLI 版本。模型在系统临时目录中的隔离副本运行，结果目录只保存来源快照和日志。

静态验证只检查契约和文件一致性；路由评测把控制面路由策略和四个 `SKILL.md` 主体嵌入提示，只检查当前请求已授权工作的 Skill / mode 分类，不执行任务、读取深层 reference，也不代表真实自动触发测试。产物行为、真实自动触发和 A/B 质量比较必须作为独立模型评测，不得由前两者代替。

`evals/behavior-evals.json` 保存最小行为回归契约，供 `skill-creator` 的独立运行、评分和盲评流程使用；不要把这些用例或评分器复制进运行时 Skill。
