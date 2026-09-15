# WebShell —— 把网站包成 iOS App（模仿 PC 端打开）

一个最小化的 iOS WebView 壳：全屏 `WKWebView`，强制桌面版 User-Agent + 桌面宽度渲染，把任意网址当成一个"App"打开。不需要 Xcode 工程文件，直接命令行编译成 IPA。

## 三个前提（务必先看）

1. **IPA 里的可执行文件只有 macOS + Xcode 能编译**，Windows 上无论如何变不出来。本项目借助 GitHub Actions 的 `macos` runner 自动编译，产出**未签名**的 IPA。
2. 未签名 IPA **不能直接安装**，必须用你自己的 Apple ID 签名：Sideloadly / AltStore（免费账号每 7 天重签一次；付费开发者账号 1 年）。
3. 改内容（网址、UA、图标）看下文。

## 路线一：GitHub Actions（推荐，零本地依赖）

1. 把 `webshell/` 整个目录推送到一个 GitHub 仓库。
2. 仓库 → **Actions** → 选 `Build iOS IPA` → **Run workflow**。
   可填：App 显示名、Bundle ID、首页地址；`mode` 选 `adhoc`。
3. 等待约 2–5 分钟，去 **Artifacts** 下载 `WebShell-ipa`（一个未签名的 `.ipa`）。
4. 用 Sideloadly 选中该 IPA，填你的 Apple ID，连接 iPhone 安装。

### 推送到 GitHub（本地已 git init 并提交好）

仓库已经初始化、提交完成（分支 `main`）。你只需要两步：

1. 在 https://github.com/new 新建一个**空仓库**（不要勾 README / .gitignore）。
2. 在本目录执行（把 `<用户名>/<仓库名>` 换成你自己的）：

```bash
git remote add origin https://github.com/<用户名>/<仓库名>.git
git push -u origin main
```

推送完成即**自动触发构建**（工作流监听 `main` 分支的 push）。约 2–5 分钟后，在仓库 **Actions** 页面点进那次运行，滚到最下面的 **Artifacts**，下载 `WebShell-ipa`。

注意：GitHub 会把产物再包一层 zip，下载后解压，里面的 `WebShell.ipa` 才是真正要签名的文件。

想改作者名（初始提交用的是占位身份）：

```bash
git config user.name "你的名字"
git config user.email "你的邮箱"
git commit --amend --reset-author
```

## 路线二：本地 Mac

```bash
bash scripts/build.sh
# 产出 build/WebShell.ipa（Ad-hoc 自签名）
```

用开发者证书签名（付费账号 / 有 p12 + mobileprovision 时）：

```bash
CODE_SIGN_IDENTITY="你的证书名" PROFILE=xxx.mobileprovision bash scripts/build.sh
```

## 路线三：没有 Mac，也不想折腾 GitHub

云端 macOS CI 同样能产出 IPA，且不需要 GitHub Actions：

- **Codemagic**（codemagic.io）：支持 iOS 构建，免费额度可用于少量构建，配置里指向本仓库，产物直接下载 `.ipa`。
- **Bitrise**：免费计划含 macOS 分钟数。
- **MacinCloud**：按小时租一台云 Mac，SSH 上去直接 `bash scripts/build.sh`。

无论哪条路，最终拿到的都是 `WebShell.ipa` 这个文件，签名由你自己处理。

## 常见调整（改源码）

在 `Sources/WebViewController.swift`：

- 首页地址：`kHomeURL`
- 桌面 / 移动 UA：`kDesktopUA` / `kMobileUA`（底部工具栏可一键切换）
- 强制桌面宽度：`kForceDesktopViewport`（默认开，把 viewport 撑到 1280 宽，按 PC 布局渲染）
- 自签证书放行：`kTrustSelfSignedCertificates`（企业内网 VPN 门户常用自签证书，默认开）
- 显示 / 隐藏底部工具条：`kShowToolbar`（返回 / 前进 / 首页 / 切换 UA / 刷新）

## 安装签名（Sideloadly，免费方案）

1. 下载 Sideloadly（sideloadly.com）。
2. iPhone 连电脑 → 信任电脑；Mac/Windows 上开启 iTunes Wi-Fi 同步（或数据线）。
3. 选 IPA + 填 Apple ID → **Start**。
4. 手机上：**设置 → 通用 → VPN与设备管理** → 信任该 Apple ID 开发者。
5. 免费账号每 7 天需重签一次。

## 文件结构

```
webshell/
├─ Sources/
│  ├─ AppDelegate.swift        # 入口
│  └─ WebViewController.swift  # 核心：WebView、桌面 UA、工具条、证书放行
├─ Resources/
│  ├─ Info.plist               # 应用元信息
│  ├─ Entitlements.plist
│  ├─ LaunchScreen.storyboard  # 启动图
│  └─ Assets.xcassets/         # 应用图标（由 tools/make_icon.py 生成）
├─ scripts/build.sh            # 编译 + 打包（在 macOS 上运行）
├─ .github/workflows/
│  └─ build-ipa.yml            # 自动构建工作流
└─ tools/                      # 图标生成 / 校验脚本
```

## 已知限制

- 真机安装依赖 Apple 签名，本工程只负责产出结构正确的未签名 IPA，签名由 Sideloadly 完成。
- 免费 Apple ID 重签周期为 7 天；如需长期稳定，请用付费开发者账号（`mode: developer`，并在仓库 Secrets 配置 `P12_BASE64` / `P12_PASSWORD` / `MOBILEPROVISION_BASE64` / `SIGN_IDENTITY`）。
- 极少数站点会检测 WebView 并限制打开（如银行、部分流媒体），此类页面在壳内可能不正常。
