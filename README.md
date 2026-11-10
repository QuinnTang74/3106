<p align="center">
  <img src="docs/images/app-icon.png" width="120" alt="3106">
</p>

<h1 align="center">3106</h1>

<p align="center">
  无越狱的 iOS 容器管理工具：应用数据、补丁、清理、壁纸与拨号主题。
</p>

<p align="center">
  <a href="README.en.md">English</a> ·
  <a href="CHANGELOG.md">更新日志</a> ·
  <a href="docs/PATCH_GUIDE.md">补丁指南</a>
</p>

## 项目信息

| 项目 | 内容 |
| --- | --- |
| 当前版本 | **3.1.12**（正式版） |
| 当前发布 | **v3.1.12**（build 16，壁纸导入/扫描、更新提示与切页性能修复） |
| 支持系统 | iOS 17.0–18.7.1 · 26.0–26.7.2 · 27.0–27.3 beta 1 |
| 访问后端 | kernel / `bad_query` / `worse_query` |
| 界面语言 | 简体中文 · English · Tiếng Việt |
| 签名要求 | iOS 26.7+ / 27.x 需要 App Group entitlement |
| Bundle ID | `com.qingtang.3106` |
| 仓库 | <https://github.com/QuinnTang74/3106.git> |

## 功能

| 模块 | 说明 |
| --- | --- |
| 应用数据浏览 | 应用容器、App Group、扩展数据、内部守护进程；iOS 27 可列出 System Data 与部分 System Groups |
| 收藏夹 | 长按文件夹收藏；文件标签页顶部的收藏 Section 直接列出收藏文件夹路径 |
| 补丁管理 | 导出 `.3106`，兼容导入 `.3105`；多目标、用户输入、可选密码、失败回滚 |
| 清理器 | 按应用清理 `Library/Caches` 与 `tmp`，支持符号链接 Caches 的容器内安全删除 |
| 壁纸与主题 | 安装 `.tendies` PosterBoard 壁纸与 `.3105pass` 拨号主题 |
| 可配置底栏 | 设置中开关底栏项目，最多 5 个槽位，首页固定；开发者模式默认开启 |
| 三语言界面 | 简体中文、English、Tiếng Việt |

## 最近更新

| 版本 | 主要内容 |
| --- | --- |
| **3.1.12** | 正式版：修复壁纸导入/扫描、已安装最新版仍提示更新、清理切文件页卡顿；包含 3.1.8–3.1.11 的全部修复 |
| **3.1.11** | 测试构建：直接用已成功的 tree 枚举收集 descriptors，避免早期枚举被沙箱挡住；导入增加 extracting/extracted/inspected 阶段日志；启动日志显示版本号 |
| **3.1.10** | 测试构建：修复 `.tendies` 解包后 `isContained` 的 `/var` 与 `/private/var` 误判；设备端 descriptor 改用枚举器优先，解决“树里有目录、扫描说没有” |
| **3.1.9** | 测试构建：壁纸扫描强制 `/private/var`；ZIP 支持 GB18030 文件名、反斜杠路径、重复目录和 768MB 视频条目；文件页复用 LS/文件系统缓存并跳过冗余 MHA 扫描 |
| **3.1.8** | 修复已安装最新版仍提示更新；修复清理扫描时切底栏卡死；修复壁纸扫描的 `/var` 路径拼写导致看不到 descriptors，并补充导入错误日志 |
| **3.1.7** | 壁纸：修复 27.3 布局扫描提前失败、Mercury 目录名、视频 descriptor 映射与散装 descriptor 包；清理器改为逐应用刷新并显示已加载数量 |
| **3.1.6** | 收藏夹：长按文件夹收藏，文件标签页顶部直接列出收藏路径；兼容 3105 2.0 的收藏数据 |
| **3.1.5** | 应用数据浏览器恢复全部容器：移除 MHA 硬门禁、LaunchServices `bdsl` 解析、未识别容器单独分组且只读 |
| **3.1.4-r2** | 项目地址迁移至 **QuinnTang74/3106**；应用内 GitHub 入口、更新检查与 README 同步 |
| **3.1.4** | 清理删除改用扫描记录的真实容器路径；`FileManager` 安全删除并拒绝跳出容器的符号链接 |
| 3.1.3 | 壁纸扫描器支持 27.3 的嵌套/非标准 PosterBoard 布局，按需创建扩展 descriptors 目录 |
| 3.1.2 | 清理测量改用 `FileManager` 枚举；壁纸按 PosterBoard 存储目录反查容器；清理页常驻设置齿轮 |
| 3.1.1 | 清理器加入文件系统枚举与容器索引回退；壁纸扫描/探针/安装/重置逐目录授权 |
| 3.1.0 | 底栏配置、默认开发者模式、移除推广与致谢、中文 README |

完整记录见 [CHANGELOG.md](CHANGELOG.md)。

## 兼容性

| 系统 | 已验证范围 | 访问后端 |
| --- | --- | --- |
| iOS 17 | 17.0–17.7.x | 内核链路 |
| iOS 18 | 18.0–18.7.1 | 内核链路 |
| iOS 26 | 26.0–26.6.1 | `bad_query` |
| iOS 26 | 26.7–26.7.2 | `worse_query` |
| iOS 27 | 27.0–27.2 | `worse_query` |
| iOS 27 | 27.3 beta 1（`24C5037i`） | `worse_query`（实验性） |

> iOS 17/18 仍需手动启用内核链路；iOS 26/27 不涉及内核漏洞。System Data 在 iOS 27 上仅可列目录。

## 安装与签名

| 签名方式 | App Group | 说明 |
| --- | --- | --- |
| AltStore / SideStore / Sideloadly + Apple ID | 自动创建 | 推荐；免费 Apple ID 即可 |
| 自有开发者账号 | 需显式 App ID + App Groups 能力 | 在开发者后台创建专用 profile |
| 证书（`.p12`）+ 通配符 profile | 不支持 | `worse_query` 会报 “No App Group” |
| LiveContainer | 取决于签名环境 | 在应用内 **设置 → App Group** 检查 |

使用证书与描述文件时，描述文件必须是包含 **App Groups** 能力的显式 App ID；通配符 profile 无法携带 App Group。

## 构建与测试

| 任务 | 命令 |
| --- | --- |
| 无签名构建 | `xcodebuild -project ThreeOneOSSix.xcodeproj -scheme 3106 -configuration Release -sdk iphoneos CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" build` |
| 策略测试 | `bash Tests/run_policy_tests.sh` |
| 产物目录 | `dist/`，本次文件名 `3106-3.1.12-unsigned.ipa` |

## 下载

正式版发布在 GitHub Releases：

<https://github.com/QuinnTang74/3106/releases>

发布资产为未签名 IPA，需要按上面的签名方式自行签名后安装。

当前版本：`3106-3.1.12-unsigned.ipa`（SHA256 `788fafd2814aaa626d474f07e1dc3369ff3e2320eaf95a3368d274f03f9a56cf`）。

## 开源协议与商用说明

本仓库整体以 **GNU GPL v3.0** 发布，完整文本见 [LICENSE](LICENSE)。

项目包含来自 3105、`worse_query`、WQ Files 等 GPL-3.0 代码。GPL-3.0 不允许再附加“禁止商用”一类额外限制，因此不能把整体改成严格意义上的非商用协议。

作者不希望本项目被用于商业用途；如需商用，请先联系仓库作者。这句话是作者意愿说明，不构成对 GPL-3.0 的额外限制，也不改变上游及第三方代码的许可。

二次修改或再分发时，必须保留 [LICENSE](LICENSE) 与 [NOTICE.md](NOTICE.md) 中的版权、来源和许可声明，并注明你做了哪些修改；这是 GPL-3.0 的要求，也是本项目的要求。

## 参考项目

本项目参考并基于 **3105 项目**（原作者 YangJiii）的 2.0 源码；iOS 27 适配、`worse_query` 移植、清理器与壁纸修复、3106 改名均在此基础上完成。第三方代码的版权与来源声明见 [NOTICE.md](NOTICE.md)（GPL-3.0 要求，不是推广内容）。