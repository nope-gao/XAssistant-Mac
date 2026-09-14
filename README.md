# XAssistant Mac

简体中文 | [English](README.en.md)

macOS 本地键鼠统计与 3D 热力图按动视频导出工具。

改编自 [xuhk/XAssistant](https://github.com/xuhk/XAssistant) 的功能与创意，使用 Swift 原生重新实现。这是非官方 macOS 版本，未复制上游 Windows 源码或素材，与原作者无隶属关系。本项目采用 [MIT 许可证](LICENSE)。

## 功能

- 菜单栏后台记录键鼠按动，查看每日统计与键盘热力图。
- 识别内置、外接键盘，提供 MacBook 与带数字区的 Mac 键盘布局，并可手动选择。
- 选择开始、结束时间，支持“最开始”和“现在”快捷操作。
- 将键位按动动画和累计热力图导出为 1080p、30 fps MP4，保存到“下载”文件夹；自动压缩无操作间隔。
- 可选择包含或不包含鼠标，速度支持 0.5× 至 256×（含 128×）。
- 热力图上限可随当前累计最高按动数动态变化，或固定为所选范围内最终最高按动数。
- 片尾保留最终热力图 5 秒，摄像机缓慢旋转。
- 每次按下都有同步敲击声，不同物理键位使用不同音色；支持键盘敲击（默认）、机械键盘、柔和敲击和静音。

## 安装

需要 **Apple Silicon Mac、macOS 13 或更新版本**。无需安装 Xcode。

- **直接下载：** 打开 [最新版本](https://github.com/nope-gao/XAssistant-Mac/releases/latest)，下载 `XAssistant-Mac-arm64.zip`，解压后将 **XAssistant Mac.app** 放进 `~/Applications`。
- **终端安装 / 更新：** 先退出正在运行的应用，再执行：

```bash
curl -fsSL https://raw.githubusercontent.com/nope-gao/XAssistant-Mac/main/install.sh -o /tmp/xassistant-install.sh && bash /tmp/xassistant-install.sh
```

安装脚本下载最新 Release、校验 SHA-256，并安装到 `~/Applications`，无需 sudo。记录数据会保留。以上方式需要仓库已经发布带安装包的 Release；GitHub 自动生成的 Source code ZIP 是源码，不是应用。

当前构建采用 ad-hoc 签名，尚未通过 Apple 公证。如果 macOS 阻止打开，请确认来源后到“系统设置 → 隐私与安全性”选择“仍要打开”。随后按下方说明开启输入监控。

## 界面语言

首次启动默认“跟随系统”，按 macOS 的首选语言列表选择已支持的语言。支持 **简体中文、繁體中文、English、日本語、Español、Français、Deutsch**；列表中没有支持的语言时回退到英文。可在窗口底部手动选择，或恢复“跟随系统”，设置会保存。

界面、菜单、已有状态提示、日期与数字格式、鼠标标注、功能键名称和视频字幕统一使用所选语言。字母键保留物理 ANSI 布局。视频使用开始导出时的语言，避免中途切换造成混用；导出期间不能手动切换语言。macOS 自己的权限弹窗和底层错误详情由系统控制语言。

## 视频声音

“声音”提供键盘敲击、机械键盘、柔和敲击、静音四种选择，默认键盘敲击。每个物理键位有确定且不同的短促音色，仅在按下时触发，并与首个显示按下的动画帧对齐。加速后的密集按动会叠加混音；选择不包含鼠标时也不会混入鼠标点击声。片尾保留安静的 5 秒展示。

声音由程序合成，不使用麦克风，不采集真实键盘录音，也不依赖外部音效素材。有声导出使用 48 kHz AAC 音轨；静音模式不生成音轨。

## 从源码构建

需要 Apple Silicon Mac、macOS 13 或更新版本，以及 Xcode Command Line Tools。当前构建脚本仅生成 ARM64 应用；尚未完成各系统版本的兼容性验证。

```bash
# 未安装开发工具时执行一次
xcode-select --install

# 在项目目录内构建（包含签名检查和内置自测）
bash build.sh

# 安装到固定位置并启动
mkdir -p "$HOME/Applications"
ditto "dist/XAssistant Mac.app" "$HOME/Applications/XAssistant Mac.app"
open "$HOME/Applications/XAssistant Mac.app"
```

当前版本使用本地 ad-hoc 签名，未做 Apple Developer ID 签名或公证，适合从源码构建试用。

## 使用与权限

首次运行后，前往“系统设置 → 隐私与安全性 → 输入监控”，允许安装位置中的 **XAssistant Mac**，退出并重新打开应用。操作键鼠后，确认最新记录时间和计数实际更新，再导出视频。

重新编译或替换应用可能使原有授权失效。若开关已打开但仍无记录，先退出应用，执行：

```bash
tccutil reset ListenEvent local.jasongao.xassistantmac
```

然后在输入监控中重新添加已安装的应用、开启权限并重新启动。该命令只重置本应用的输入监控授权。

导出时选择时间范围、速度、鼠标选项及热力图模式，点击“导出视频到下载”。没有记录的时间段无法补录。

## 本地数据与隐私

数据保存在 `~/Library/Application Support/XAssistantMac/`，不主动上传，也不包含遥测。

为支持动画回放，会保存按下/松开时间、物理键位、设备信息及事件顺序；还会记录应用名称、Bundle ID 和使用时长统计。不读取输入法最终文字、窗口标题、网页地址或鼠标坐标。**键位及其顺序仍可能推断输入内容，因此事件记录属于敏感数据；请勿公开上传数据目录。**

## 已知限制

- 主要支持 ANSI 键盘布局，ISO/JIS 等布局尚未完整适配；自动识别不保证覆盖所有第三方设备。
- Fn、多媒体键及安全输入场景可能无法完整记录；Touch ID 不作为普通按键记录。
- 多键盘同时使用时，设备归属可能存在限制；长按自动重复不作为多次独立按动累计。
- 本项目使用 SceneKit、Metal 和 AVFoundation 直接渲染视频，不依赖 Blender。

## 发布新版（维护者）

更新 `build.sh` 中的版本号和构建号，提交代码，然后推送对应标签：

```bash
git tag v0.4.0
git push origin main --tags
```

推送 main 时 GitHub Actions 会构建并验证翻译、按动时序和实际音视频编码；推送版本标签并通过验证后发布包含应用 ZIP 和校验文件的 Release。后续发布请使用新的版本号。也可运行 `bash package.sh`，将 `dist/XAssistant-Mac-arm64.zip` 和 `dist/SHA256SUMS` 手动上传到对应 GitHub Release。
