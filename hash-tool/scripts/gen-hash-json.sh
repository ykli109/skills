#!/usr/bin/env bash

set -euo pipefail

# 在指定目录下为所有文件生成 hash.json。
#
# 用法：
#   ./gen-hash-json.sh <目录> [输出文件]
#
# 参数：
#   目录：要扫描的目标目录（必填）。
#   输出文件：输出的 json 文件路径（可选，默认：<目录>/hash.json）。
#
# 行为：
#   - 递归枚举普通文件（通过 `git ls-files` 遵循 .gitignore / exclude-standard）。
#   - 计算每个文件的 sha256。
#   - 输出稳定排序 JSON：{ "files": { "相对路径": "sha256" } }。
#   - 当输出文件位于扫描目录内时，会自动跳过该输出文件本身。
#
# 依赖：
#   - 需要安装 `git`。

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "用法: $0 <目录> [输出文件]" >&2
  exit 2
fi

TARGET_DIR="$1"
OUTPUT_PATH="${2:-$TARGET_DIR/hash.json}"

if [[ ! -d "$TARGET_DIR" ]]; then
  echo "错误：目录不存在：$TARGET_DIR" >&2
  exit 1
fi

if ! command -v git >/dev/null 2>&1; then
  echo "错误：未找到 git（请确保 git 已安装且在 PATH 中）" >&2
  exit 1
fi

# 规范化路径（兼容 macOS）。
TARGET_DIR_ABS="$(cd "$TARGET_DIR" && pwd -P)"
OUTPUT_ABS="$(cd "$(dirname "$OUTPUT_PATH")" && pwd -P)/$(basename "$OUTPUT_PATH")"

# 约定：输出 JSON 的 key 使用相对 TARGET_DIR 的路径。
# 使用 NUL 分隔以安全处理空格/换行等特殊字符。
# 通过 `git ls-files -z --others --cached --exclude-standard` 遵循 .gitignore。
# 排序：使用字节序排序确保输出稳定可复现。

TMP_JSON="$(mktemp)"
trap 'rm -f "$TMP_JSON"' EXIT

echo '{"files":{' > "$TMP_JSON"

first=1

(
  cd "$TARGET_DIR_ABS"
  git ls-files -z --others --cached --exclude-standard
) | LC_ALL=C sort -z | while IFS= read -r -d '' rel; do
  file="$TARGET_DIR_ABS/$rel"

  # 如果输出文件位于扫描目录内，跳过它本身，避免自引用导致结果不稳定。
  if [[ "$file" == "$OUTPUT_ABS" ]]; then
    continue
  fi

  # 理论上 git ls-files 只会输出存在的文件，这里做一次兜底校验。
  if [[ ! -f "$file" ]]; then
    continue
  fi

  hash="$(shasum -a 256 "$file" | awk '{print $1}')"

  # 为 JSON key 做必要转义（反斜杠、双引号，以及 \t/\n/\r）。
  esc_rel="$rel"
  esc_rel="${esc_rel//\\/\\\\}"
  esc_rel="${esc_rel//\"/\\\"}"
  esc_rel="${esc_rel//$'\t'/\\t}"
  esc_rel="${esc_rel//$'\n'/\\n}"
  esc_rel="${esc_rel//$'\r'/\\r}"

  if [[ $first -eq 1 ]]; then
    first=0
  else
    printf ',' >> "$TMP_JSON"
  fi

  printf '\n  "%s":"%s"' "$esc_rel" "$hash" >> "$TMP_JSON"
done

# 结束 JSON
printf '\n}}\n' >> "$TMP_JSON"

# 确保输出目录存在
mkdir -p "$(dirname "$OUTPUT_PATH")"

# 原子写入
mv -f "$TMP_JSON" "$OUTPUT_PATH"
trap - EXIT

echo "Wrote: $OUTPUT_PATH" >&2
