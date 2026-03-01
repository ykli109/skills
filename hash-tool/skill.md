---
name: hash-tool
description: 计算指定目录的文件哈希（遵循 .gitignore）并生成 hash.json；同时支持对比目标 hash.json 与候选 hash.json 列表，找出变更最小的历史文件并输出差异摘要。
---

# Hash Tool 技能

## 概述

本技能提供两类能力：

1. **生成目录快照**：递归计算某个目录下所有文件的 sha256，并生成 `hash.json`（遵循 `.gitignore` 规则）。
2. **选择最接近快照**：输入一个目标 `hash.json` 与一组候选 `hash.json`，计算每个候选相对目标的差异（新增/修改/删除），选出“差异文件总数最少”的候选，并输出对比结果。

## 适用场景

- 产物/目录完整性校验、缓存命中判断
- 对比不同版本目录快照，快速找到最接近的历史版本
- 在 CI/本地构建前后做快照对比，定位变更范围

## 使用方式

### 1) 生成目录的 hash.json

使用脚本：[`./scripts/gen-hash-json.sh`](./scripts/gen-hash-json.sh)

```bash
./scripts/gen-hash-json.sh <目录>
# 或指定输出路径
./scripts/gen-hash-json.sh <目录> <输出hash.json路径>
```

输出 JSON 结构：

```json
{"files":{"relative/path":"<sha256>"}}
```

### 2) 从候选中找出与目标差异最小的 hash.json

使用脚本：[`./scripts/pick-closest-hash-json.sh`](./scripts/pick-closest-hash-json.sh)

```bash
./scripts/pick-closest-hash-json.sh <目标hash.json> <候选1.json> [候选2.json ...]
```

stdout 输出为一个 JSON，包含：

- `closest`：差异最小的候选文件路径
- `summary[]`：每个候选与目标差异统计（add/mod/del/total）
- `diff`：closest 的详细差异文件列表（add/mod/del）

示例输出结构：

```json
{
  "closest":"hash3.json",
  "summary":[
    {"candidate":"hash1.json","add":1,"mod":2,"del":0,"total":3}
  ],
  "diff":{
    "add":["x"],
    "mod":["y"],
    "del":["z"]
  }
}
```

## 目录结构

```text
hash-tool/
├── skill.md
└── scripts/
    ├── gen-hash-json.sh
    └── pick-closest-hash-json.sh
```

## 注意事项

- `gen-hash-json.sh` 依赖 `git`，以便通过 `git ls-files --exclude-standard` 遵循 `.gitignore`。
- `pick-closest-hash-json.sh` 依赖 `python3` 用于解析 JSON 与计算差异。
- 差异口径：
  - add：候选有、目标没有
  - del：目标有、候选没有
  - mod：两边都有但 hash 不同
