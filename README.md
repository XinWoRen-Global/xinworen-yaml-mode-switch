# yaml-mode-switch

> 免重启热切换 YAML 配置中的布尔/值开关（bash + sed，无外部依赖）。
> A dependency-free shell CLI to hot-toggle boolean/value keys in a YAML config without restarting your service.

由 XinWoRen 出品，从生产环境沉淀的通用工程工具脱敏开源。本仓库不绑定任何平台、模型或密钥，可作为任意运行时「配置热开关」的通用入口。

Built by [XinWoRen](https://github.com/XinWoRen-Global). It is a generic engineering utility extracted from production — no platform, model, or secret coupling.

---

## 为什么需要它 / Why

很多运行时通过 **bind-mount / 热加载**实时读取配置文件，但缺少一个**安全、幂等**的 CLI 来改配置字段。本工具提供一个通用入口：

- 只改写目标字段所在行，**保留文件其余注释与配置**
- 自动备份到 `.bak`，可 `--restore` 还原
- **智能值校验**：布尔语义值统一归一化为 `true/false`
- `--dry-run` 预览改动不落盘
- 纯 bash + sed，GNU sed（Linux/git-bash）与 BSD sed（macOS）均可

## 安装 / Install

```bash
curl -o yaml-mode-switch.sh https://raw.githubusercontent.com/XinWoRen-Global/yaml-mode-switch/main/yaml-mode-switch.sh
chmod +x yaml-mode-switch.sh
```

或 clone 本仓库后直接使用。

## 用法 / Usage

```bash
# 设置 / set
./yaml-mode-switch.sh <config.yaml> <key> <value>

# 打印当前值 / dump current value
./yaml-mode-switch.sh <config.yaml> <key> --dump

# 从备份还原 / restore from backup
./yaml-mode-switch.sh --restore <backup_file> [config]

# 预览改动，不落盘 / preview without writing
./yaml-mode-switch.sh --dry-run <config.yaml> <key> <value>
```

### 示例 / Examples

> 说明：`<key>` 传**纯字段名**（不含路径点号），工具会匹配任意缩进层级的第一处同名 key。例如
> `features:` 块下的 `test_mode`，直接写 `test_mode` 即可命中。

```bash
# 把 features 块下的 test_mode 设为 on（布尔归一化为 true）
./yaml-mode-switch.sh config.yaml test_mode on

# 把 debug 设为 true
./yaml-mode-switch.sh config.yaml debug true

# 查看当前 test_mode
./yaml-mode-switch.sh config.yaml test_mode --dump

# 归零重来：先 dry-run 确认
./yaml-mode-switch.sh --dry-run config.yaml test_mode off
./yaml-mode-switch.sh config.yaml test_mode off
```

## 退出码 / Exit codes

- `0` 成功
- `1` 参数错误 / 文件不存在

> 说明：布尔/开关语义值（on/off/yes/no/true/false/1/0）在写入前统一归一化为 `true/false`，保证生成的 YAML 语义一致。

## 无副作用 / Safety

- 每次写入前自动 `cp` 到同名 `.bak` 备份
- `--restore` 可从备份无痛回滚
- `--dry-run` 只打印「改动前/后」对比，不安全可重复执行
- 不读取、不写入任何密钥；只改你指定的那一个 key

## 贡献 / Contributing

欢迎提交 Issue / PR。参见 [CONTRIBUTING](CONTRIBUTING.md)。

## License

[MIT](./LICENSE)

版权所有 / Copyright (c) 2026 **XinWoRen**