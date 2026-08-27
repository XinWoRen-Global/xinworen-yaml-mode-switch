#!/usr/bin/env bash
#
# yaml-mode-switch.sh - 免重启热切换 YAML 配置中的布尔/值开关
#
# 场景：很多运行时通过 bind-mount / 热加载实时读取配置文件，但缺少一个安全、
#       幂等的 CLI 来改配置字段。本工具提供一个通用入口：
#         - 按 key 名匹配任意缩进层级的目标行，只替换该行的值，保留文件其余注释与配置
#         - 自动备份到 .bak（可 --restore 还原）
#         - 智能值归一化（布尔语义值统一写 true/false）
#         - --dry-run 预览改动不落盘
#         - 纯 bash + sed，无外部依赖；GNU sed（Linux/git-bash）与 BSD sed（macOS）均可
#
# 用法：
#   yaml-mode-switch.sh <config> <key> <value>           # 设置 key=value
#   yaml-mode-switch.sh <config> <key> --dump            # 打印当前值
#   yaml-mode-switch.sh --restore <backup_file> [config] # 从备份还原
#   yaml-mode-switch.sh --dry-run <config> <key> <value> # 预览不落盘
#
# 说明：
#   - key 为「字段名」（不含路径点号）。匹配任意缩进层级的第一处同名 key。
#     例：features:\n  test_mode: off -> 用 test_mode 即可命中。
#   - 若配置中不存在该 key，则在文件末尾追加一行（不带缩进）。
#
# 退出码：0 成功；1 参数错误/文件不存在。
#
# 示例：
#   ./yaml-mode-switch.sh config.yaml test_mode on
#   ./yaml-mode-switch.sh config.yaml debug true
#   ./yaml-mode-switch.sh config.yaml test_mode --dump

set -euo pipefail

# ── 可选：通过环境变量自定义日志前缀（不绑定任何平台） ──
LOG_PREFIX="${YMS_LOG_PREFIX:-yaml-mode-switch}"

err() { echo "[$LOG_PREFIX] ERROR: $*" >&2; }

usage() {
    echo "Usage: yaml-mode-switch.sh <config> <key> <value>"
    echo "       yaml-mode-switch.sh <config> <key> --dump"
    echo "       yaml-mode-switch.sh --restore <backup_file> [config]"
    echo "       yaml-mode-switch.sh --dry-run <config> <key> <value>"
    echo "Options:"
    echo "  --dump       打印当前 key 值"
    echo "  --restore    从备份文件还原配置"
    echo "  --dry-run    预览改动，不写入文件"
    echo "  -h, --help   显示此帮助"
}

# 归一化布尔语义值 -> true/false；非布尔原样返回
normalize_value() {
    case "$(echo "$1" | tr '[:upper:]' '[:lower:]')" in
        true|on|1|yes) echo "true" ;;
        false|off|0|no) echo "false" ;;
        *) echo "$1" ;;
    esac
}

is_boolish() {
    case "$(echo "$1" | tr '[:upper:]' '[:lower:]')" in
        on|off|true|false|yes|no) return 0 ;;
        *) return 1 ;;
    esac
}

CONFIG=""
KEY=""
VALUE=""
BACKUP_FILE=""
DRY_RUN=0
RESTORE=0
PROG_MODE=""

# ── 参数解析（无 getopt 依赖，位置参数 + 选项混合） ──
ARGS=("$@")
i=0
while [ $i -lt ${#ARGS[@]} ]; do
    a="${ARGS[$i]}"
    case "$a" in
        -h|--help)
            usage; exit 0 ;;
        --dump)
            PROG_MODE=dump ;;
        --restore)
            RESTORE=1
            if [ $((i+1)) -lt ${#ARGS[@]} ]; then BACKUP_FILE="${ARGS[$((i+1))]}"; i=$((i+1)); fi
            ;;
        --dry-run)
            DRY_RUN=1 ;;
        -*)
            err "未知参数: $a"; usage >&2; exit 1 ;;
        *)
            if [ -z "$CONFIG" ]; then CONFIG="$a"
            elif [ -z "$KEY" ]; then KEY="$a"
            elif [ -z "$VALUE" ]; then VALUE="$a"
            else err "多余参数: $a"; usage >&2; exit 1; fi
            ;;
    esac
    i=$((i+1))
done

if [ "$RESTORE" -eq 1 ]; then
    if [ -z "$BACKUP_FILE" ]; then
        err "--restore 需要备份文件路径"; usage >&2; exit 1
    fi
    [ -f "$BACKUP_FILE" ] || { err "备份文件不存在: $BACKUP_FILE"; exit 1; }
    if [ -z "$CONFIG" ]; then
        CONFIG="${BACKUP_FILE%.bak}"
    fi
    [ -f "$CONFIG" ] || { err "目标配置文件不存在: $CONFIG"; exit 1; }
    cp "$BACKUP_FILE" "$CONFIG"
    echo "[$LOG_PREFIX] 已从备份还原: $BACKUP_FILE -> $CONFIG"
    exit 0
fi

if [ "$PROG_MODE" = "dump" ]; then
    if [ -z "$CONFIG" ] || [ -z "$KEY" ]; then
        err "--dump 需要 <config> 与 <key>"; usage >&2; exit 1
    fi
    [ -f "$CONFIG" ] || { err "配置文件不存在: $CONFIG"; exit 1; }
    if ! grep -qE "^[[:space:]]*${KEY}:" "$CONFIG"; then
        echo "[$LOG_PREFIX] key '$KEY' 未存在于 $CONFIG"
        exit 1
    fi
    val="$(grep -E "^[[:space:]]*${KEY}:" "$CONFIG" | head -n1 \
        | sed -E 's/^[[:space:]]*[^:]+:[[:space:]]*([^#]*).*/\1/' \
        | sed -E 's/[[:space:]]+$//')"
    echo "$val"
    exit 0
fi

if [ -z "$CONFIG" ] || [ -z "$KEY" ] || [ -z "$VALUE" ]; then
    err "需要 <config> <key> <value>（或 --dump / --restore）"; usage >&2; exit 1
fi
[ -f "$CONFIG" ] || { err "配置文件不存在: $CONFIG"; exit 1; }

# 转义 key 中的正则元字符（此时 key 为纯字段名，一般无特殊字符，仍做防御）
KEY_ESC=$(echo "$KEY" | sed -E 's/([.[\\*^$+?()|{}])/\\\1/g')

NORMALIZED_VALUE="$(normalize_value "$VALUE")"

# key 已存在（任意缩进层级）？
EXISTS=0
if grep -qE "^[[:space:]]*${KEY_ESC}:[[:space:]]*" "$CONFIG"; then
    EXISTS=1
fi

if [ "$DRY_RUN" -eq 1 ]; then
    echo "[$LOG_PREFIX] (dry-run) 将设置 $KEY = $NORMALIZED_VALUE"
    if [ "$EXISTS" -eq 1 ]; then
        before="$(grep -E "^[[:space:]]*${KEY_ESC}:" "$CONFIG" | head -n1)"
        echo "  before: $before"
        echo "  after : ${before%%:*}: $NORMALIZED_VALUE"
    else
        echo "  (key 不存在，将追加一行)"
    fi
    exit 0
fi

# ── 实际写入：先备份（cp 与 sed -i.bak 都会在 ${CONFIG}.bak 保留改动前内容），再改写；不存在则追加 ──
cp "$CONFIG" "${CONFIG}.bak"
if [ "$EXISTS" -eq 1 ]; then
    sed -E -i.bak "/^[[:space:]]*${KEY_ESC}:/s/(^[[:space:]]*${KEY_ESC}:)[[:space:]]*.*/\1 $NORMALIZED_VALUE/" "$CONFIG"
else
    printf "\n%s: %s\n" "$KEY" "$NORMALIZED_VALUE" >> "$CONFIG"
fi

echo "[$LOG_PREFIX] 已设置 $KEY = $NORMALIZED_VALUE -> $CONFIG （备份: $CONFIG.bak，热生效）"