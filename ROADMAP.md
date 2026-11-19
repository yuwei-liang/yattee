# Yattee Y 路线图

Yattee Y 是 Yuwei 自用的 Yattee 分支：配合自家 NAS 上的 Yattee Server 和 Claude 推荐，把 app 改成自己想要的样子。
改动尽量放在独立文件里，方便合并上游更新（见 AGENTS.md 末尾的 Yattee Y 一节）。

## 已完成（2026-11-18）

- 独立身份：`com.yuweiliang.yattee`，名字 "Yattee Y"，黑鲸图标，可以和官方 Yattee 并排装。
- GitHub Actions 云端编译（Xcode 27）→ 自动传 TestFlight；开发版 IPA 供测试机安装。
- iCloud 同步：自己的 CloudKit 容器和 schema（`cloudkit/schema.ckdb`），源、订阅、记录在自己设备间同步。
- 一键添加源：`yattee://add-source` 链接，账号密码直接进钥匙串，从 Mac 用 devicectl 发到手机。
- AGENTS.md 加了分支说明；分支自己的测试 `YatteeTests/YatteeYTests.swift`；CI 跑测试。

## 进行中

- **中文字幕方块**：原因已找到——iOS 的苹方字体在沙盒外，mpv/libass 读不到文件。方案：打包 Noto Sans SC，用 `sub-fonts-dir` 加载。等确认下载字体。
- **首页 = 推荐**：设计稿 v1 已出（推荐流 + 「为什么推荐」+ ⋮ 菜单 + 不感兴趣可撤销）。待定：理由是否常显、「接着看」位置、旧快捷方块怎么处理、刷到底「换一批」还是「今天就这些」。
- **CI 测试转绿**：改用 iOS 模拟器跑（macOS 未签名会崩）。

## 下一步（候选，待需求探讨后排序）

- 推荐反馈直达 Claude：多来点这种 / 不感兴趣 / 别再推这个频道（需要服务器加反馈接口，curator 读取）。
- 回传真实观看时长和完成度，让推荐学得更准。
- 精简：隐藏用不到的源类型（Invidious / Piped / PeerTube）和多账号设置。
- 夜里 Wi-Fi 下自动预下载前几条推荐（带字幕），早上秒开、可离线。
- 中英双语字幕；视频页 Claude 摘要和要点。
- 其他设备：Mac 版走 TestFlight；Apple TV 版（TopShelf、tvOS 界面）。
- 定期合并上游 `yattee/yattee` 更新，合并后检查 CloudKit schema 是否有新字段。

## 想法池

（需求探讨里冒出来的新想法先放这里）
