#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

MATRIX="../pixelforge-plan/05-quality/COVERAGE-MATRIX-M1.md"
if [[ ! -f "${MATRIX}" ]]; then
  echo "Coverage matrix not found: ${MATRIX}" >&2
  exit 1
fi

if grep -Eq 'TODO|TBD|未覆盖' "${MATRIX}"; then
  echo "Coverage matrix still contains unresolved coverage markers." >&2
  exit 1
fi

TEST_NAMES=()
while IFS= read -r test_name; do
  TEST_NAMES+=("${test_name}")
done < <(grep -Eo 'test_[A-Za-z0-9_]+' "${MATRIX}" | sort -u)
if [[ "${#TEST_NAMES[@]}" -eq 0 ]]; then
  echo "Coverage matrix does not reference any tests." >&2
  exit 1
fi

missing=()
for test_name in "${TEST_NAMES[@]}"; do
  if ! rg -q "func ${test_name}\\(" tests; then
    missing+=("${test_name}")
  fi
done

if [[ "${#missing[@]}" -gt 0 ]]; then
  printf 'Coverage matrix references missing tests:\n' >&2
  printf ' - %s\n' "${missing[@]}" >&2
  exit 1
fi

echo "Coverage matrix references ${#TEST_NAMES[@]} existing tests."

# 反向完整性检查（M1.1 改进新增）：
# 正向检查只防"矩阵引用了不存在的测试"，不防"新增公开 API 漏列入矩阵"。
# 这里枚举 core/pixel/*.gd 全部 static func 公开方法（下划线开头的私有方法除外），
# 断言其名称出现在矩阵（行为矩阵或附录映射表，含 EXEMPT 豁免）中。
missing_api=()
while IFS= read -r api_name; do
  if ! grep -q "${api_name}" "${MATRIX}"; then
    missing_api+=("${api_name}")
  fi
done < <(grep -h '^static func [a-z]' core/pixel/*.gd | sed 's/static func \([a-z_0-9]*\).*/\1/' | sort -u)

if [[ "${#missing_api[@]}" -gt 0 ]]; then
  printf 'core/pixel public APIs missing from coverage matrix (add row or EXEMPT with reason):\n' >&2
  printf ' - %s\n' "${missing_api[@]}" >&2
  exit 1
fi

echo "All core/pixel public APIs are present in the coverage matrix."
