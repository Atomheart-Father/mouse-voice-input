#!/bin/bash
# 卸载:停掉服务并删除程序。模型和历史默认保留,加 --purge 一并删除
U=$(id -u)
for n in voice whisper-server; do
  launchctl bootout "gui/$U/local.omlx.$n" 2>/dev/null || true
  rm -f "$HOME/Library/LaunchAgents/local.omlx.$n.plist"
done
rm -rf "$HOME/Applications/OMLXVoice.app"
tccutil reset Accessibility local.omlx.voice >/dev/null 2>&1 || true
tccutil reset ListenEvent  local.omlx.voice >/dev/null 2>&1 || true
[ "${1:-}" = "--purge" ] && rm -rf "$HOME/.config/omlx-voice"
echo "已卸载。"
