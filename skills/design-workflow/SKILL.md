---
name: design-workflow
description: "中文游戏策划工作流编排、产物治理与入口边界裁定。凡用户询问下一步、该用哪个策划 Skill、文档链、里程碑、策划产物状态、阶段门槛、归档、项目或产物负责人、审批关系，要求完整 GDD、完整归档包或 full-package 编排，或要求独立数值体系、独立 UI 策划案、独立评审入口或报告时优先使用；后三类请求必须明确当前体系不提供，且不得以隐藏模式恢复。只负责流程、路由与治理；玩法状态机、系统职责、P0-P3 和产品 MVP 不属于本 Skill。"
---

# 游戏策划工作流

把项目当前状态映射到下一步动作，并确保一次请求只有一个主责入口、一个主要产物和一个可写权威。

## 权限边界

- **可写权威**：`GOV-*`、路线、里程碑、产物索引、状态记录、负责人、审批关系、风险登记、阶段门槛判定与证据索引；阶段门槛状态只由本 Skill 写入。
- **只读输入**：证据、决策、正式游戏设计和实现状态；只读取其状态与依赖。
- **禁止越权**：不创建或修改 `EVID-*`、`DEC-*`、概念、`SYS-*` 或 `RULE-*`，不因流程判断把专项产物自动标为已确认。

## 五个入口

| Skill | 唯一职责 |
|-------|----------|
| `design-workflow` | 路线、里程碑、状态与治理 |
| `grill-me` | 高影响阻塞分支的确认摘要 |
| `design-evidence` | 竞品、试玩和实现事实 |
| `design-inference` | 假设、候选、取舍、`DEC-*` 与 Prototype |
| `design-docs` | 已确认的概念、系统地图、产品 MVP 与功能规则 |

完整写入权限、模式和冲突裁定统一维护在 `references/routing-matrix.md`，不再维护第二张职责表。

## 工作原则

- 先判断用户缺的是事实、决策、正式设计、治理还是关键确认，再选择唯一主责。
- 路由回答“谁负责”，输出档位回答“交付多深”，阶段门槛回答“证据是否足够”；三者不要混写。
- 已有权威产物优先差量修订，证据报告和决策记录不得成为并行规则源。
- 存在未拍板的阻塞分支时，读取 `references/grill-gate.md` 并使用 `grill-me`；可从仓库或证据回答的问题不要反问用户。
- 当前体系不提供独立数值体系、独立 UI 策划案或独立评审报告。命中此类请求时明确拒绝恢复入口；只有正式规则成立所需的局部常量、反馈 / 显示要求或自检，才交 `design-docs` 内联处理。

## 按需读取

默认只读取路由矩阵与输出档位。其余治理 reference 只读取当前问题真正命中的一份，不做全量预读。

- 选择主责、模式或裁定冲突：`references/routing-matrix.md`。
- 选择 `brief`、`standard`、`implementation-ready` 或 `full-package`：`references/artifact-output-profiles.md`。
- 目录、状态、权威源、归档与文档头：`references/artifact-standards.md`。
- 判断是否进入下一阶段：`references/stage-gates.md`。
- 版本、里程碑、关键路径与制作推进：`references/milestone-production-planning.md`。
- 共享愿景、决策权、跨工种协作与冲突升级：`references/team-collaboration-governance.md`。

## 编排流程

1. **确认当前状态**：已有产物、证据、决策、实现和用户真正目标是什么。
2. **选择唯一主责**：按路由矩阵确认可写权威；跨域任务只选择改变核心事实的主责，其他内容列交接。
3. **选择交付深度**：咨询和小差量默认 `brief`，正式产物默认 `standard`；只有明确交实现或归档时升级。
4. **补齐前置**：事实不足先 `design-evidence`，方案未收束先 `design-inference`，阻塞选择未确认时插入 `grill-me`。
5. **落档与推进**：已确认结论交 `design-docs`；里程碑、状态、负责人、阶段门槛判定与证据索引留在本 Skill。

## 生命周期主链

```text
证据（竞品 / 试玩 / 实现）
  → 决策（推论 / Prototype / grill）
  → 正式设计（概念 → 系统 → 功能）
  → 制作治理（里程碑 / 状态 / 归档）
```

只运行当前真正缺少的环节，不要求每个请求走完整链路。

## 输出格式

- 当前状态与目标。
- 唯一主责 Skill、模式、可写权威和裁定理由。
- 输出档位与唯一主要产物。
- 必要前置、后续交接和明确不做内容。
- 阶段门槛判定、证据索引、阻塞项与下一步。
- 仅在有治理需求时展开目录、状态、负责人和审批关系。

## 维护校验

修改策划 Skill 架构后，从仓库根目录先运行静态契约校验：

```powershell
pwsh -NoProfile -File skills/design-workflow/scripts/validate-planning-skills.ps1
```

该脚本按 `references/skill-manifest.json` 比较实际入口全集，检查 frontmatter、完整 reference 图、旧入口精确 token、eval schema、路由覆盖和 fixture；成功输出会明确说明没有执行模型评测。

需要验证真实模型路由时，再运行较慢的独立命令：

```powershell
pwsh -NoProfile -File skills/design-workflow/scripts/run-planning-route-evals.ps1
```

模型命令逐条执行 `evals/evals.json`，将结构化结果与 `expected_route` 比较并在不一致时失败；不要把静态校验冒充模型路由结果。
