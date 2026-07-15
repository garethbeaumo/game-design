# 固定实现证据：敌人警戒

以下内容是用于 eval 的最小合成 fixture，不代表 Project Line 当前真实实现。

## 脚本摘录

```csharp
[SerializeField] private float _alertDistance = 10f;
[SerializeField] private float _alertDelay = 1.5f;

if (_state == AlertState.Idle && distance <= _alertDistance)
    _state = AlertState.Suspicious;

if (_state == AlertState.Suspicious && _suspiciousSeconds >= _alertDelay)
    _state = AlertState.Alert;
```

## Prefab 序列化值

```yaml
EnemyAlertController:
  _alertDistance: 12
  _alertDelay: 2
```

## 场景引用

场景中的 `EnemyGuard_A` 使用上述 Prefab，没有实例级字段覆盖。

## 旧文档

旧文档写的是：“玩家进入 8 米范围后，敌人立即从 Idle 进入 Alert。”

可直接反推：该场景实例采用 12 米距离和 2 秒延迟，并经过 `Suspicious`；这与旧文档的 8 米、立即警戒不一致。fixture 没有运行时跟踪、其他 Prefab 变体或代码调用方，不能据此证明整个项目都采用相同行为。
