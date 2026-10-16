#!/bin/bash
# 用法: run-stage.sh S1   —— Codex 只做一个阶段，不 commit（.git 在沙箱里只读），由 Claude 验收后提交
S=$1
cd /Users/leo/本地/Project_Git/重要/LaunchpadPro-hybrid
codex exec -C . -s workspace-write --skip-git-repo-check -c approval_policy=never -c model_reasoning_effort=xhigh \
  --add-dir /Users/leo/本地/Project_Git/重要/LaunchpadPro-实验 \
  --add-dir /Users/leo/Library/Caches/org.swift.swiftpm --add-dir /Users/leo/Library/org.swift.swiftpm \
  -o ../LaunchpadPro-实验/codex-$S-总结.md \
  "严格按 /Users/leo/本地/Project_Git/重要/LaunchpadPro-实验/交付边界.md 施工，本次只做阶段 $S（之前阶段已由 Claude 验收提交）。注意：沙箱内 .git 只读，不要执行 git commit/add，提交由 Claude 负责，这不算违反交付边界。完成该阶段全部完成判据后停止。过程与偏差追加到 /Users/leo/本地/Project_Git/重要/LaunchpadPro-实验/施工记录-codex.md。最终回复：完成情况、改动文件、build/test 结果、未满足项。" < /dev/null > ../LaunchpadPro-实验/codex-$S-log.txt 2>&1
