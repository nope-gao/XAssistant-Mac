# XAssistant Mac

[简体中文](README.md) | **繁體中文** | [English](README.en.md) | [日本語](README.ja.md) | [Español](README.es.md) | [Français](README.fr.md) | [Deutsch](README.de.md)

macOS 本地鍵鼠統計與 3D 熱力圖按動影片導出工具。

改編自 [xuhk/XAssistant](https://github.com/xuhk/XAssistant) 的功能與創意，使用 Swift 原生重新實現。這是非官方 macOS 版本，未複製上游 Windows 原始碼或素材，與原作者無隸屬關係。本項目採用 [MIT 許可證](LICENSE)。

## 功能

- 菜單欄後台記錄鍵鼠按動，查看每日統計與鍵盤熱力圖。
- 識別內置、外接鍵盤，提供 MacBook 與帶數字鍵區的 Mac 鍵盤佈局，並可手動選擇。
- 選擇開始、結束時間，支持“最開始”和“現在”快捷操作。
- 將鍵位按動動畫和累計熱力圖導出為 1080p、30 fps MP4，保存到“下載”資料夾；自動壓縮無操作間隔。
- 可選擇包含或不包含滑鼠，速度支持 0.5× 至 256×（含 128×）。
- 熱力圖上限可隨當前累計最高按動數動態變化，或固定為所選範圍內最終最高按動數。
- 片尾保留最終熱力圖 5 秒，攝像機緩慢旋轉。
- 每次按下都有同步敲擊聲，不同物理鍵位使用不同音色；支持鍵盤敲擊（默認）、機械鍵盤、柔和敲擊和靜音。

## 安裝

需要 **Apple Silicon Mac、macOS 13 或更新版本**。無需安裝 Xcode。

- **直接下載：** 打開 [最新版本](https://github.com/nope-gao/XAssistant-Mac/releases/latest)，下載 `XAssistant-Mac-arm64.zip`，解壓後將 **XAssistant Mac.app** 放進 `~/Applications`。
- **終端安裝 / 更新：** 先退出正在運行的應用，再執行：

```bash
curl -fsSL https://raw.githubusercontent.com/nope-gao/XAssistant-Mac/main/install.sh -o /tmp/xassistant-install.sh && bash /tmp/xassistant-install.sh
```

安裝腳本下載最新 Release、校驗 SHA-256，並檢查新版是否滿足已安裝版本的簽名要求；不兼容時停止更新，保留原應用。檢查通過後安裝到 `~/Applications`，無需 sudo。記錄數據會保留。以上方式需要倉庫已經發佈帶安裝包的 Release；GitHub 自動生成的 Source code ZIP 是原始碼，不是應用。

現有 v0.4.0 下載包採用 ad-hoc 簽名，尚未通過 Apple 公證。如果 macOS 阻止打開，請確認來源後到“系統設置 → 隱私與安全性”選擇“仍要打開”。隨後按下方說明開啓輸入監控。

## 界面語言

首次啓動默認“跟隨系統”，按 macOS 的首選語言列表選擇已支持的語言。支持 **簡體中文、繁體中文、English、日本語、Español、Français、Deutsch**；列表中沒有支持的語言時回退到英文。可在窗口底部手動選擇，或恢復“跟隨系統”，設置會保存。

界面、菜單、已有狀態提示、日期與數字格式、滑鼠標注、功能鍵名稱和影片字幕統一使用所選語言。字母鍵保留物理 ANSI 佈局。影片使用開始導出時的語言，避免中途切換造成混用；導出期間不能手動切換語言。macOS 自己的權限彈窗和底層錯誤詳情由系統控制語言。

## 影片聲音

“聲音”提供鍵盤敲擊、機械鍵盤、柔和敲擊、靜音四種選擇，默認鍵盤敲擊。每個物理鍵位有確定且不同的短促音色，僅在按下時觸發，並與首個顯示按下的動畫幀對齊。加速後的密集按動會疊加混音；選擇不包含滑鼠時也不會混入滑鼠點擊聲。片尾保留安靜的 5 秒展示。

聲音由程序合成，不使用麥克風，不採集真實鍵盤錄音，也不依賴外部音效素材。有聲導出使用 48 kHz AAC 音軌；靜音模式不生成音軌。

## 從原始碼構建

需要 Apple Silicon Mac、macOS 13 或更新版本，以及 Xcode Command Line Tools。當前構建腳本僅生成 ARM64 應用；尚未完成各系統版本的兼容性驗證。

```bash
# 未安裝開發工具時執行一次
xcode-select --install

# 在項目目錄內構建（包含簽名檢查和內置自測）
bash build.sh

# 安裝到固定位置並啓動
mkdir -p "$HOME/Applications"
ditto "dist/XAssistant Mac.app" "$HOME/Applications/XAssistant Mac.app"
open "$HOME/Applications/XAssistant Mac.app"
```

默認本地構建使用 ad-hoc 簽名，未做 Apple Developer ID 簽名或公證，適合從原始碼構建試用。

## 使用與權限

首次運行後，前往“系統設置 → 隱私與安全性 → 輸入監控”，允許安裝位置中的 **XAssistant Mac**，退出並重新打開應用。操作鍵鼠後，確認最新記錄時間和計數實際更新，再導出影片。

重新編譯或替換應用可能使原有授權失效。若開關已打開但仍無記錄，先退出應用，執行：

```bash
tccutil reset ListenEvent local.jasongao.xassistantmac
```

然後在輸入監控中重新添加已安裝的應用、開啓權限並重新啓動。該命令只重置本應用的輸入監控授權。

導出時選擇時間範圍、速度、滑鼠選項及熱力圖模式，點擊“導出影片到下載”。沒有記錄的時間段無法補錄。

## 本地數據與隱私

數據保存在 `~/Library/Application Support/XAssistantMac/`，不主動上傳，也不包含遙測。安裝腳本會連接 GitHub 下載版本。

為支持動畫回放，會保存按下/松開時間、物理鍵位、設備信息及事件順序；還會記錄應用名稱、Bundle ID 和使用時長統計。不讀取輸入法最終文字、窗口標題、網頁地址或滑鼠坐標。**鍵位及其順序仍可能推斷輸入內容，因此事件記錄屬於敏感數據；請勿公開上傳數據目錄。**

## 已知限制

- 主要支持 ANSI 鍵盤佈局，ISO/JIS 等佈局尚未完整適配；自動識別不保證覆蓋所有第三方設備。
- Fn、多媒體鍵及安全輸入場景可能無法完整記錄；Touch ID 不作為普通按鍵記錄。
- 多鍵盤同時使用時，設備歸屬可能存在限制；長按自動重復不作為多次獨立按動累計。
- 本項目使用 SceneKit、Metal 和 AVFoundation 直接渲染影片，不依賴 Blender。

## 發佈新版（維護者）

當前 v0.4.0 下載包仍是臨時簽名。只切換權限開關可能保留舊版簽名記錄，造成“開關開啓但無記錄”。已修正後續發佈流程：**正式發佈必須使用固定的 Developer ID Application 簽名身份**，缺少憑證時停止發佈。

在 GitHub Actions Secrets 配置 `SIGNING_CERTIFICATE_BASE64`（P12 憑證的 Base64）、`SIGNING_CERTIFICATE_PASSWORD` 和 `SIGNING_IDENTITY`。憑證和私密金鑰不得提交到倉庫；工作流只導入臨時鑰匙串並在結束時刪除。同一身份應持續用於後續版本。首次從臨時簽名遷移到正式簽名仍需重新授權一次。

更新 `build.sh` 中的版本號和構建號，提交代碼，然後推送對應標籤：

```bash
git tag v0.4.1
git push origin main --tags
```

推送 main 時 GitHub Actions 會構建並驗證翻譯、按動時序和實際音影片編碼；推送版本標籤並通過驗證後發佈包含應用 ZIP 和校驗檔案的 Release。後續發佈請使用新的版本號。也可在本機安裝憑證後運行 `SIGNING_IDENTITY="Developer ID Application: …" bash package.sh`，將 `dist/XAssistant-Mac-arm64.zip` 和 `dist/SHA256SUMS` 手動上傳到對應 GitHub Release。

本地測試允許 `ALLOW_ADHOC_PACKAGE=1 bash package.sh`，但這種包不能作為保持授權的升級包發佈。固定安裝路徑和 Bundle ID 本身不能解決臨時簽名變化；詳見 [Apple 關於簽名要求與隱私權限的說明](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)。
