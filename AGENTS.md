# AGENTS — 3106 项目约定

本项目使用 **lrnev** 治理（`.lrnev/` 工作区在项目根目录），全局执行规范见 `~/.agents/AGENTS.md`。

## CHANGELOG 口径（3.2.7 起）

`CHANGELOG.md` **只描述变更本身**。

**写入正文**：
- 改了什么、为什么改、影响范围、验证方式
- 本项目自己的 issue 编号（`issue #2` / `#3` / `#70`）
- 机制名与文件扩展名（`worse_query` / `bad_query` / `.3106` / `.3106save` / `.3106cfg` / `.tendies`）
- 历史记录中的既有事实（版本沿革、`3105` 作为本仓库前身的重命名记录、已发布包的 SHA256）

**不写入正文**：
- 第三方项目名（`GestaltX` / `WQ Files` / `Erosion-CN` / `Regitela` / `YumEdit` / `WQManager` 等）
- 第三方的 issue 编号（`#138` / `#132` / `#102` 这类属于他人仓库的编号）
- "参考 X 的做法"、"同步 X 的发现"、"X release notes 的问题清单"这类归属表述
- 第三方 release 版本号（`GestaltX v1.1.1`）

来源与归属**统一归 `NOTICE.md`**。`NOTICE.md` 满足 GPL-3.0 的署名与来源要求，`LICENSE` 与 `NOTICE.md` 在任何二次分发中必须保留。

## 判定标准

遇到"这条要不要删项目名"时，看它记的是**事实**还是**归属**：

| 原文 | 性质 | 处理 |
| --- | --- | --- |
| `.3105save` 扩展名 | 事实（文件格式） | 保留 |
| 3106 基于 3105 2.0 修改 | 事实（本仓库沿革） | 保留 |
| 字段 plist 导入不再整根覆盖（GestaltX #138） | 归属 + 外部编号 | 删括号，留内容 |
| 出厂基线保护（同步 Erosion-CN v0.8.5 真机发现） | 归属 | 改为「（真机验证）」 |
| 应用通知音替换（GestaltX App Audio Library 思路，独立实现） | 归属 | 删括号 |

`ack.erosion_cn` 等致谢页本地化键**属 NOTICE 范畴**，不适用本条目 —— 那是 GPL 署名要求，必须保留。

## 每次会话开始

1. 调 `project_status` 接手当前进度（不确定进度时必做）。
2. 改代码前确认对应 task 已 `task_update(in_progress)`，完成后 `task_update(completed)`。
3. 纯只读/答问题不走治理流程。

## 验证

- 改动后必跑 `bash Tests/run_policy_tests.sh`（含键集对齐、格式符校验、策略测试）。
- 上传前必跑 Release 构建：
  ```bash
  xcodebuild -project ThreeOneOSSix.xcodeproj -scheme 3106 -configuration Release \
    -sdk iphoneos CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" -derivedDataPath /tmp/3106-dd build
  ```
- **`swiftc` 测试通过不等于 Xcode 构建通过。** 新增的 `.swift` 文件必须同时登记到 `project.pbxproj` 的四处（`PBXBuildFile`、`PBXFileReference`、所在 group 的 children、`PBXSourcesBuildPhase.files`），其中 `files` 列表要放 `PBXBuildFile` 的 ID，不是 `PBXFileReference` 的 ID。漏登记只会在 app 编译时暴露。

## 本地化

- 四语键集必须完全一致：`zh-Hans` / `en` / `vi` / `ko`，共 1579 键（3.2.8）。
- 带格式符的键（`%@` / `%lld` / `%d` / `%ld` / `%llX`）在四语中**序列必须一致** —— `String(format:)` 按出现顺序消费参数。
- 新增语言需改四处：`AppLanguage` 的 case 与 `displayName` switch、`project.pbxproj` 的 `knownRegions`、`PBXVariantGroup` 的 children（含 `PBXFileReference`）。
- `localizedBundle` 在找不到 lproj 时**静默回退 `.main`**，漏注册的后果是「选项能选中、界面全是英文」，不会报错。构建后用 `ls <app>/*.lproj` 核对。