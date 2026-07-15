# 推论归档模板

只在用户明确要求正式决策记录、Prototype 计划或可归档文件时读取。普通咨询和单一取舍使用 `brief`，不为套流程生成 constraint / breadth / depth 三件套。

一次只创建一种主要产物：`DEC-*` 或 Prototype 计划。证据、正式设计与治理信息只通过稳定 ID 引用，不复制正文。

## `DEC-*` 决策记录

```markdown
# DEC-[ID] [决策标题]

## 文档头
| 字段 | 内容 |
|------|------|
| artifact_type | decision |
| status | 草案 / 待确认 / 已确认 / 已废弃 |
| owner | |
| source_of_truth | 本记录负责的唯一决策问题 |
| upstream | EVID / 现有设计 / 用户确认 |
| downstream | 待修订的 design-docs 产物 |
| last_updated | |
| replaced_by | |

## 决策问题与层级
- 必须决定：
- 为什么现在决定：
- 所属层级：概念 / 系统 / 功能
- 本次不回答：

## 约束与证据
| 约束 / 证据 ID | 类型或适用性 | 对选择的影响 | 未知项 |
|----------------|----------------|--------------|--------|
| | 硬约束 / 软约束 / EVID | | |

## 候选比较
| 候选 | 玩家价值 | 学习点 | 顶层支持 | 主要风险 | 验证成本 |
|------|----------|--------|----------|----------|----------|
| A | | | | | |
| B | | | | | |

## 决定
- 选择：
- 主要依据：
- 放弃项与反选代价：
- 仍成立的假设：
- 验证信号：
- 复查条件：
- 失败回退：

## 正式落点
- `design-docs` 模式：concept / system / feature
- 需要修订的稳定 ID：
```

## Prototype 计划

Prototype 的类型、字段和交接规则读取 `prototype-validation-plan.md`。归档时使用：

```markdown
# Prototype-[ID] [验证标题]

## 文档头
| 字段 | 内容 |
|------|------|
| artifact_type | prototype |
| status | 草案 / 待确认 / 已确认 / 已废弃 |
| owner | |
| upstream | DEC / EVID / 假设 |
| downstream | 计划创建的 TEST / EVID 与返回的决策问题 |
| last_updated | |

## 致命假设与范围
- 致命假设：
- 包含：
- 不包含：

| 观察证据 | 通过标准 | 失败标准 | 失败回退 |
|----------|----------|----------|----------|
| | | | |
```

Prototype 执行结果不写回本模板；录像、日志、样本、观察和归因由 `design-evidence:playtest` 建立 `TEST-*` / `EVID-*`。
