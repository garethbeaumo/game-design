# 设计产物治理标准

本文件只回答“产物放哪里、谁是权威、状态如何流转和怎样归档”。路由与写入权限查看 `routing-matrix.md`，交付深度查看 `artifact-output-profiles.md`。

## 目录建议

```text
docs/
├── 00_evidence/        # COMP / TEST / FACT / EVID
├── 01_decisions/       # DEC 与 Prototype
├── 02_game_design/
│   ├── concept.md      # 顶层体验承诺
│   ├── system-map.md   # SYS、P0-P3、产品 MVP 与依赖
│   └── systems/
│       └── system-name.md  # RULE、对象、状态、事件与验收
├── 03_milestones/      # 路线、风险、阶段门槛判定与证据索引
├── _archive/           # 已废弃产物
└── INDEX.md            # 状态、依赖、开放问题和权威链接
```

小项目可以合并目录，但不能把证据、决策、正式设计和治理混成同一规则源。

## 产物类型与唯一主责

| artifact_type | 唯一主责 | 权威范围 |
|---------------|----------|----------|
| `competitor-evidence` | `design-evidence:competitor` | `COMP-*`、外部事实、来源、日期、可比性与规模证据 |
| `test-evidence` | `design-evidence:playtest` | `TEST-*`、样本、归因、证据强度和回归问题 |
| `implementation-evidence` | `design-evidence:implementation` | `FACT-*`、实现事实、推断、可信度与伪约束 |
| `decision` / `prototype` | `design-inference` | `DEC-*` 的约束、假设、候选与取舍，或 Prototype 计划 |
| `concept` | `design-docs:concept` | 玩家、体验承诺、支柱、核心动作循环和顶层边界 |
| `system-map` | `design-docs:system` | `SYS-*`、职责、依赖、P0-P3 与产品 MVP |
| `feature` | `design-docs:feature` | `RULE-*`、对象、流程、状态、事件与行为验收 |
| `handoff` | `design-docs:feature` | 实现消费视图，不重新定义被引用规则 |
| `milestone` / `governance` | `design-workflow` | 路线、里程碑、风险、角色、阶段门槛判定与证据索引 |
| `change-note` | 对应权威的主责入口 | 已确认差量；采纳后回写原权威，不长期并行 |

## 模块化权威源

- `INDEX.md` 只维护摘要、状态、依赖、开放问题和链接。
- 证据、决策、概念、系统、功能和治理分别维护；其他产物使用稳定 ID 引用。
- 同一文档同时承担三个以上产物类型时应渐进拆分，不为迁移模板一次性重写未受影响内容。
- `full-package` 只用 `INDEX.md` 串联模块，不创建单文件 GDD 或正文汇编。

## 文档状态

| 状态 | 含义 | 下游使用 |
|------|------|----------|
| 草案 | 内容仍可大改 | 只作参考 |
| 待确认 | 核心内容已形成，仍有高影响问题 | 有限制 |
| 已确认 | 负责人、确认来源和权威范围明确 | 可作为当前约束 |
| 已废弃 | 已被替代或取消 | 不可作为当前约束 |

状态流转：

- `草案 → 待确认`：核心骨架完成，阻塞问题可定位。
- `待确认 → 已确认`：阻塞选择已收束，负责人或指定审批者记录确认来源。
- `已确认 → 待确认`：发生实质差量且尚未重新确认。
- `任意状态 → 已废弃`：记录原因、替代产物和日期。

Skill 可以提出状态建议，但不能替用户或项目负责人确认正式产物。

## 文档头最小字段

| 字段 | 说明 |
|------|------|
| title | 文档标题 |
| artifact_type | 使用上表枚举 |
| status | 当前状态 |
| owner | 维护负责人 |
| source_of_truth | 本文档唯一负责的范围或 ID 命名空间 |
| upstream / downstream | 直接上下游权威 |
| last_updated | 具体日期 |
| open_questions | 阻塞问题数量或链接 |
| replaced_by | 仅已废弃文档需要 |

## 权威冲突裁定

1. 先按 `source_of_truth` 和 `routing-matrix.md` 判断信息所有者。
2. 同一范围内，`已确认` 优先于低状态产物。
3. 上层定义边界，下层定义细则；下层不能借更新时间覆盖上层承诺。
4. 竞品、测试、实现和 Prototype 是证据，不直接压过正式设计。
5. 仍无法判断时标为待确认，不拼接成折中规则。

## 变更与归档

实质变更至少记录日期、差量、原因、证据 / 决策来源、受影响稳定 ID、后续动作和复查条件。

- 已确认差量由拥有目标权威的 Skill / 模式回写。
- 多个下游受影响时，`design-workflow` 只登记同步任务、顺序和负责人，不另建影响规则源。
- 已废弃文档写明替代文档或废弃原因，移入 `_archive/`，并在索引记录日期。

## 交付检查

- 是否只有一个事实所有者，其他产物通过 ID 引用。
- 状态、负责人、权威范围和上下游是否明确。
- 证据、交接表或索引是否误成第二规则源。
- 确认和归档是否可追溯到来源、负责人和替代产物。
