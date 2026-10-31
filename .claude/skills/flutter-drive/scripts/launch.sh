#!/bin/bash
# 后台启动 flutter run，记录 VM Service 地址、flutter 进程 pid 与日志，供 fd.mjs 使用。
# 用法：launch.sh [device]   默认 macos；其余 flutter run 参数可通过 FLUTTER_RUN_ARGS 传入
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
S=.dart_tool/flutter_drive
mkdir -p "$S"

# 已有会话先结束，避免两个 app 实例抢同一个 VM Service 记录
if [[ -f $S/pid ]] && kill -0 "$(cat $S/pid)" 2>/dev/null; then
  kill "$(cat $S/pid)" 2>/dev/null || true
  sleep 2
fi
# flutter run 断开后应用可能还活着；结束本仓库构建出的残留实例，避免两份应用同时读写数据
pkill -f "$PWD/build/.*\.app/Contents/MacOS/" 2>/dev/null && sleep 1 || true
rm -f "$S/vm_uri" "$S/pid" "$S/run.log" "$S/log_pos"

# stdin 接 /dev/null：后台没有终端，热重载走 SIGUSR1/SIGUSR2，不靠按键
nohup flutter run -d "${1:-macos}" \
  --pid-file "$PWD/$S/pid" \
  --vmservice-out-file "$PWD/$S/vm_uri" \
  ${FLUTTER_RUN_ARGS:-} </dev/null >"$S/run.log" 2>&1 &

# 等 VM Service 就绪（首次构建可能较慢）
for _ in $(seq 1 600); do
  if [[ -s $S/vm_uri && -s $S/pid ]]; then
    echo "ready: $(cat $S/vm_uri)"
    exit 0
  fi
  if ! kill -0 $! 2>/dev/null; then
    echo "flutter run 已退出，日志末尾：" >&2
    tail -40 "$S/run.log" >&2
    exit 1
  fi
  sleep 1
done
echo "等待超时，查看 $S/run.log" >&2
exit 1
