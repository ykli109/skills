#!/usr/bin/env bash

set -euo pipefail

# 从一组候选 hash.json 中，找出与目标 hash.json “差异文件数最少”的那一个。
#
# 用法：
#   ./pick-closest-hash-json.sh <目标hash.json> <候选1.json> [候选2.json ...]
#
# 输入格式要求：
#   JSON 需满足：{ "files": { "path": "sha256", ... } }
#
# 输出：
#   - stdout 输出一个 JSON，包含：
#     - closest：与目标差异最小的候选文件路径
#     - summary：每个候选与目标的 add/mod/del/total 统计
#     - diff：closest 的详细差异文件列表（add/mod/del）
#
# 说明：
#   - 新增(add):  候选有、目标没有。
#   - 删除(del):  目标有、候选没有。
#   - 修改(mod):  两边都有但 hash 不同。
#   - 总差异(total) = add + del + mod。

if [[ $# -lt 2 ]]; then
  echo "用法: $0 <目标hash.json> <候选1.json> [候选2.json ...]" >&2
  exit 2
fi

TARGET_JSON="$1"
shift
CANDIDATES=("$@")

if [[ ! -f "$TARGET_JSON" ]]; then
  echo "错误：目标文件不存在：$TARGET_JSON" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "错误：未找到 python3（请确保 python3 已安装且在 PATH 中）" >&2
  exit 1
fi

python3 - "$TARGET_JSON" "${CANDIDATES[@]}" <<'PY'
import json
import os
import sys


def load_files_map(path: str) -> dict:
    try:
        with open(path, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except Exception as e:
        raise SystemExit(f"错误：无法解析 JSON：{path}\n原因：{e}")

    if not isinstance(data, dict) or 'files' not in data or not isinstance(data['files'], dict):
        raise SystemExit(f"错误：JSON 格式不符合预期（需要 {{\"files\":{{...}}}}）：{path}")

    m = {}
    for k, v in data['files'].items():
        if not isinstance(k, str) or not isinstance(v, str):
            raise SystemExit(f"错误：files 字段的 key/value 必须为字符串：{path}")
        m[k] = v
    return m


def diff_detail(target: dict, cand: dict):
    """计算候选相对目标的差异。

    口径：
      - 新增(add)：候选有、目标没有
      - 删除(del)：目标有、候选没有
      - 修改(mod)：两边都有但 hash 不同

    返回： (add_list, mod_list, del_list)
    """
    t_keys = set(target.keys())
    c_keys = set(cand.keys())

    add_list = sorted(c_keys - t_keys)
    del_list = sorted(t_keys - c_keys)

    common = t_keys & c_keys
    mod_list = sorted([k for k in common if target[k] != cand[k]])

    return add_list, mod_list, del_list


def diff_counts(target: dict, cand: dict):
    add_list, mod_list, del_list = diff_detail(target, cand)
    add = len(add_list)
    mod = len(mod_list)
    delete = len(del_list)
    total = add + mod + delete
    return add, mod, delete, total


def main(argv):
    if len(argv) < 3:
        raise SystemExit("用法: pick-closest-hash-json.py <target.json> <cand1.json> [cand2.json ...]")

    target_path = argv[1]
    cand_paths = argv[2:]

    target = load_files_map(target_path)

    rows = []
    for p in cand_paths:
        if not os.path.isfile(p):
            raise SystemExit(f"错误：候选文件不存在：{p}")
        cand = load_files_map(p)
        add, mod, delete, total = diff_counts(target, cand)
        rows.append((total, add, mod, delete, p))

    # 稳定排序：total 更小优先；再按 add/mod/del；最后按路径名
    rows.sort(key=lambda x: (x[0], x[1], x[2], x[3], x[4]))

    best = rows[0][4]
    best_map = load_files_map(best)
    add_list, mod_list, del_list = diff_detail(target, best_map)

    out = {
        "closest": best,
        "summary": [
            {
                "candidate": p,
                "add": add,
                "mod": mod,
                "del": delete,
                "total": total,
            }
            for (total, add, mod, delete, p) in rows
        ],
        "diff": {
            "add": add_list,
            "mod": mod_list,
            "del": del_list,
        },
    }

    print(json.dumps(out, ensure_ascii=False, separators=(",", ":")))


if __name__ == '__main__':
    main(sys.argv)
PY
