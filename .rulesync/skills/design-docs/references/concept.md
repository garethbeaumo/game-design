# `concept` 模式：游戏概念权威

把已经收束并确认的方向写成项目当前有效的顶层体验承诺。它回答“这是什么游戏、给谁玩、为什么值得做”，不展开系统内部规则。

## 权限

- 写入目标玩家边界、玩家幻想、体验承诺、设计支柱、核心动作循环、主题与表现原则、玩家信任边界，以及项目级包含 / 不包含范围。
- `DEC-*`、`EVID-*`、用户确认和现有概念案是只读上游。
- 不比较候选，不定义 `SYS-*`、P0-P3、产品 MVP、`RULE-*`、实现架构或测试结论。

## 工作原则

- 方向仍有互斥候选时回 `design-inference`；概念案只采纳已确认决策，不复述推论过程。
- 缺少外部、测试或实现证据时使用 `design-evidence`，概念案只引用证据 ID。
- 目标玩家、体验承诺、支柱、核心动作循环或顶层边界仍有阻塞分支时，按 `../../design-workflow/references/grill-gate.md` 使用 `grill-me`。
- 已有概念案默认差量修订，不为模板重写未受影响内容。

## 上下文

1. 读取现有概念案、已确认 `DEC-*`、相关 `EVID-*` 和项目硬约束。
2. 核对每条顶层承诺的确认来源；无来源内容标待确认。
3. 发现仍在比较的方案时停止落档，转 `design-inference`。
4. 只保留理解当前承诺所需的最小上游摘要与链接。

## `standard` 核心骨架

1. **来源与状态**：项目、品类 / 类型、平台、直接上游决策与证据。
2. **一句话概念**：玩家反复做什么、追求什么、为什么有趣。
3. **目标玩家与体验承诺**：服务谁、不服务谁；玩家幻想、高光、核心情绪和应避免的反向情绪。
4. **设计支柱**：3～5 条以玩家行为为中心的原则，每条写“意味着什么 / 不意味着什么”。
5. **核心动作循环**：已确认的玩家动词链及其体验意义，不展开候选比较或系统映射。
6. **顶层边界**：必须提供、明确不提供、不可牺牲体验和延后方向。
7. **风险与待确认**：只列会改变上述承诺的真实问题。

## 条件模块与 reference

只有命中时读取并展开：

- 项目支柱与范围：`concept/project-pillars-scope.md`
- 主题、机制和表现：`concept/theme-mechanic-synergy.md`
- 题材、画风和市场适配：`concept/premise-artstyle-market-fit.md`
- 内容推进边界：`concept/content-progression-strategy.md`
- 玩家动机与情绪：`concept/player-motivation-emotion.md`
- 玩家信任与外部压力：`concept/player-trust-boundary.md`
- 目标玩家、用例与决策风险：`concept/player-centered-validation.md`
- 玩家能力、设备环境与可访问性：`concept/player-context-accessibility.md`
- 机制、行为与体验映射：`concept/mechanics-dynamics-aesthetics.md`
- 环境叙事：`concept/environmental-storytelling.md`

条件模块只记录项目级承诺；系统归属与 P0-P3 交 `system` 模式，内部行为交 `feature` 模式。

## 自检

- 每条结论是否已有确认来源。
- 一句话概念、体验承诺、支柱和核心循环是否互相支持。
- 是否明确目标玩家、非目标玩家、必须提供与明确不提供。
- 是否误写了候选推论、系统清单、产品 MVP 或功能细则。
