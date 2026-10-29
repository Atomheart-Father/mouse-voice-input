#!/bin/bash
# 鼠标侧键语音输入:按住鼠标侧键说话,松开后自动把文字打到光标处。全程本机运行。
set -euo pipefail

MODEL_NAME="${MODEL_NAME:-large-v3-turbo-q5_0}"   # 内存小或想更快:MODEL_NAME=small-q5_1 ./install.sh
PORT=8977
CONF="$HOME/.config/omlx-voice"
APP="$HOME/Applications/OMLXVoice.app"
LA="$HOME/Library/LaunchAgents"
HERE="$(cd "$(dirname "$0")" && pwd)"
UID_=$(id -u)

[ "$(uname -m)" = "arm64" ] || { echo "需要 Apple 芯片(M1 及以上)的 Mac"; exit 1; }
command -v brew >/dev/null  || { echo "请先安装 Homebrew:https://brew.sh"; exit 1; }
command -v swiftc >/dev/null || { echo "请先运行 xcode-select --install 安装命令行工具,装完再重试"; exit 1; }

echo "==> 安装 whisper-cpp"
brew list whisper-cpp >/dev/null 2>&1 || brew install whisper-cpp

mkdir -p "$CONF" "$APP/Contents/MacOS" "$LA"
MODEL="$CONF/ggml-$MODEL_NAME.bin"
if [ ! -f "$MODEL" ]; then
  echo "==> 下载语音识别模型 ggml-$MODEL_NAME(来自 huggingface.co/ggerganov/whisper.cpp)"
  curl -L --fail -o "$MODEL.part" "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-$MODEL_NAME.bin"
  mv "$MODEL.part" "$MODEL"
fi

echo "==> 编译"
swiftc -O "$HERE/OMLXVoice.swift" -o "$APP/Contents/MacOS/omlx-voice"
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.omlx.voice</string>
<key>CFBundleName</key><string>OMLXVoice</string>
<key>CFBundleExecutable</key><string>omlx-voice</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
<key>NSMicrophoneUsageDescription</key><string>按住鼠标侧键说话,转成文字输入。</string>
</dict></plist>
PL
codesign --force -s - "$APP"

echo "==> 设置开机自启"
cat > "$LA/local.omlx.whisper-server.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>local.omlx.whisper-server</string>
<key>ProgramArguments</key><array>
<string>$(brew --prefix)/bin/whisper-server</string>
<string>-m</string><string>$MODEL</string>
<string>--host</string><string>127.0.0.1</string><string>--port</string><string>$PORT</string>
</array>
<key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
</dict></plist>
PL
cat > "$LA/local.omlx.voice.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>local.omlx.voice</string>
<key>ProgramArguments</key><array><string>$APP/Contents/MacOS/omlx-voice</string></array>
<key>RunAtLoad</key><true/><key>ProcessType</key><string>Interactive</string>
</dict></plist>
PL
for n in whisper-server voice; do
  launchctl bootout "gui/$UID_/local.omlx.$n" 2>/dev/null || true
  launchctl bootstrap "gui/$UID_" "$LA/local.omlx.$n.plist"
done
# 重新编译会让系统旧授权失效,这里清掉让它重新申请
tccutil reset Accessibility local.omlx.voice >/dev/null 2>&1 || true
tccutil reset ListenEvent  local.omlx.voice >/dev/null 2>&1 || true
launchctl kickstart -k "gui/$UID_/local.omlx.voice" >/dev/null 2>&1 || true

cat <<MSG

安装完成。还差最后一步,请在系统设置里放行:
  1. 隐私与安全性 → 辅助功能:打开 OMLXVoice
  2. 隐私与安全性 → 输入监控:打开 OMLXVoice
  3. 第一次说话时,允许麦克风
然后按住鼠标侧键(前进键)说话,松开即出字。菜单栏 🎙 里能找回最近说过的话。
MSG
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" || true
