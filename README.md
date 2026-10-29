# 鼠标侧键语音输入(macOS)

按住鼠标侧键说话,松开后几秒内把文字打到光标处。识别全程在本机完成(whisper.cpp),不上传任何音频。

- 中文、英文、中英混说都能识别,自动输出简体中文和标点
- 在任何应用的输入框里都能用
- 菜单栏 🎙 保存最近 50 句话,点一句就能重新贴到光标处;也可按 `⌃⌥V` 重贴上一句
- 录音最长 2 分钟自动结束

## 系统要求

- Apple 芯片的 Mac(M1 及以上),macOS 13 以上
- 已安装 [Homebrew](https://brew.sh) 和 Xcode 命令行工具(`xcode-select --install`)
- 一个带侧键的鼠标(默认用"前进"键)

## 安装

```bash
git clone https://github.com/Atomheart-Father/mouse-voice-input.git
cd mouse-voice-input
./install.sh
```

脚本会:用 Homebrew 装 `whisper-cpp`,下载识别模型(默认 `large-v3-turbo-q5_0`,约 570 MB),编译小工具,并设成开机自启。

内存 8 GB 或想要更快的响应,换小模型:

```bash
MODEL_NAME=small-q5_1 ./install.sh
```

安装后到"系统设置 → 隐私与安全性",给 **OMLXVoice** 打开**辅助功能**和**输入监控**;第一次说话时允许**麦克风**。

## 调整识别效果(提示词)

whisper 会参考 `~/.config/omlx-voice/prompt.txt` 里的文字来判断风格:默认是一句中文加一句英文,让中文、英文都能带标点、不偏向某一种语言。想让中英混说更准,可以改成你常说的混合句子,例如 `我们用 Python 写个 API,然后 deploy 到 server。`。保存后下一次说话就生效,不用重启。

## 换触发按键

默认用鼠标按键编号 4(多数鼠标的"前进"侧键)。想换成别的键:

```bash
echo 3 > ~/.config/omlx-voice/button   # 3 通常是"后退"键;改完后重启服务
launchctl kickstart -k gui/$(id -u)/local.omlx.voice
```

> 触发键会被小工具拦下来,不会再触发浏览器的前进/后退。

## 卸载

```bash
./uninstall.sh          # 保留模型和历史
./uninstall.sh --purge  # 全部删除
```

## 说明

- 识别服务是 `whisper-server`,监听 `127.0.0.1:8977`,仅本机可访问。
- 历史保存在 `~/.config/omlx-voice/history.jsonl`,只在本机。
- 粘贴时会临时借用剪贴板,随后还原原有内容。
- 每次重新编译都会让系统旧的授权失效,重装后需重新打开上述权限开关。

## 许可

MIT
