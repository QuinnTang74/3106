# 3106

3106 是一个 iOS 容器管理工具：在无越狱环境下浏览应用数据、安装补丁、清理缓存、安装 PosterBoard 壁纸与拨号主题。

**仓库：** <https://github.com/t479842598/3106.git>

[English](README.en.md)

## 功能

- **iOS 26/27 容器访问**：iOS 26.7–26.7.2 与 iOS 27.0–27.3 beta 使用 `worse_query` 沙箱逃逸；iOS 26.0–26.6.1 使用 `bad_query`；iOS 17/18 保留内核链路。
- **应用数据浏览**：应用容器、App Group、扩展数据、内部守护进程；iOS 27 可列出 System Data 与部分 System Groups。
- **补丁管理**：导出 `.3106`，兼容导入 `.3105`；支持多目标、用户输入、可选密码与失败回滚。
- **清理器、壁纸与拨号主题**：按应用清理缓存、安装 `.tendies` 壁纸与 `.3105pass` 拨号主题。
- **可配置底栏**：设置中可开关底栏项目，最多 5 个槽位，首页固定显示；开发者模式默认开启。
- **三语言界面**：简体中文、English、Tiếng Việt。

## 兼容性

| 系统 | 已验证范围 | 访问后端 |
| --- | --- | --- |
| iOS 17 | 17.0–17.7.x | 内核链路 |
| iOS 18 | 18.0–18.7.1 | 内核链路 |
| iOS 26 | 26.0–26.6.1 | `bad_query` |
| iOS 26 | 26.7–26.7.2 | `worse_query` |
| iOS 27 | 27.0–27.2 | `worse_query` |
| iOS 27 | 27.3 beta 1 | `worse_query`（实验性） |

## 安装与签名

- **iOS 26.7+ / 27.x 必须有 App Group entitlement**。推荐用 AltStore、SideStore 或 Sideloadly 配合 Apple ID（免费账号即可）签名，它们会自动创建 App Group。
- 使用证书（`.p12`）与描述文件时，描述文件必须是包含 **App Groups** 能力的显式 App ID；通配符 profile 不能携带 App Group，`worse_query` 会报 “No App Group”。
- **Bundle ID：** `com.qingtang.3106`。
- LiveContainer 是否保留 App Group 取决于其签名环境；可在应用内 **设置 → App Group** 查看，若为空则 `worse_query` 无法工作。
- iOS 17/18 仍需手动启用内核链路；iOS 26/27 不需要内核漏洞。

## 构建

```bash
xcodebuild -project ThreeOneOSSix.xcodeproj -scheme 3106 \
  -configuration Release -sdk iphoneos \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build
```

策略测试：

```bash
bash Tests/run_policy_tests.sh
```

构建产物在 `dist/`，文件名形如 `3106-3.1.0-unsigned.ipa`。

## 开源协议与商用说明

本仓库整体以 **GNU GPL v3.0** 发布，完整文本见 [LICENSE](LICENSE)。

项目包含来自 3105、`worse_query`、WQ Files 等 GPL-3.0 代码。GPL-3.0 不允许再附加“禁止商用”一类额外限制，因此不能把整体改成严格意义上的非商用协议。

作者不希望本项目被用于商业用途；如需商用，请先联系仓库作者。这句话是作者意愿说明，不构成对 GPL-3.0 的额外限制，也不改变上游及第三方代码的许可。

二次修改或再分发时，必须保留 [LICENSE](LICENSE) 与 [NOTICE.md](NOTICE.md) 中的版权、来源和许可声明，并注明你做了哪些修改；这是 GPL-3.0 的要求，也是本项目的要求。

## 参考项目

本项目参考并基于 **3105 项目**（原作者 YangJiii）的 2.0 源码；iOS 27 适配、`worse_query` 移植与 3106 改名在此基础上完成。第三方代码的版权与来源声明见 [NOTICE.md](NOTICE.md)（GPL-3.0 要求，不是推广内容）。