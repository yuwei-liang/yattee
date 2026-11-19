# Yattee Y 路线图

Yattee Y 是 Yuwei 自用的 Yattee 分支：配合自家 NAS 上的 Yattee Server 和 Claude 推荐，把 app 改成自己想要的样子。
改动尽量放在独立文件里，方便合并上游更新（见 AGENTS.md 末尾的 Yattee Y 一节）。界面改动先出设计稿，确认后再写代码。

## 已完成

- 独立身份：`com.yuweiliang.yattee`，名字 "Yattee Y"，黑鲸图标，和官方 Yattee 并排装。
- GitHub Actions 云端编译（Xcode 27，公开仓库免费）→ 自动传 TestFlight；开发版 IPA 装测试机。
- iCloud 同步：自己的 CloudKit 容器和 schema（`cloudkit/schema.ckdb`），源、订阅、记录在自己设备间同步。
- 一键添加源：`yattee://add-source` 链接，账号密码直接进钥匙串，从 Mac 用 devicectl 发到手机。
- **中文字幕不再是方块**：打包 Noto Sans SC（iOS 系统中文字体在沙盒外读不到）。XR 实机验证通过。
- 服务器：推荐反馈接口（多来点这种 / 顺着这个深挖 / 不感兴趣 / 别再推这个频道），反馈写进 Claude 挑片的提示。
- AGENTS.md 分支说明；分支测试 `YatteeTests/YatteeYTests.swift`。

## 进行中

- **首页 = 推荐**（设计稿 v1，已定）：理由一直显示；「接着看」放推荐上面；大方块换成一排小标签（打开链接、遥控放在小标签最后）；刷到底「换一批」。代码已写好，等 XR 试用。
- **点视频任何地方都直接播放**（和 YouTube 一样），详情从长按菜单打开。Apple TV 不变。
- **CI 测试转绿**：模拟器里 1087 个通过、1 个上游时间敏感测试偶发失败（`AccountsManagerTests/unreachableStatusExpires`），已改为失败自动重跑一次。

## 需求探讨 1（2026-11-18）

- 设备：iPhone、Mac、Apple TV（不用 iPad）。
- 场景：睡前躺着刷；吃饭做家务时半听半看；专门坐下来看长视频。
- 最烦：加载慢/卡；字幕问题；看完觉得在贩卖焦虑、带节奏，想直接丢给 unspin 分析。
- 看完之后：方便收藏分类；顺着这个话题推荐延伸内容。

## 接下来（按优先级）

- P1 **「用 unspin 分析」**：播放页和 ⋯ 菜单一键提交 → 服务器排队 → 家里的机器跑 unspin（YouTube 只认家里 IP）→ 报告链接推回来。已定（2026-11-18）：结果同时发 Telegram（经 Bear）和 app 内「unspin 报告」列表；分析在 Mac 上用 Claude Code（订阅额度）无界面跑，Mac 关机时任务排着等。
- P1 回传真实观看时长和完成度，让推荐学得更准。
- P2 收藏分类：书签已有标签字段，做按主题分组的书签页、加书签时一键选标签。
- P2 Mac 版（TestFlight macOS）和 Apple TV 版 Yattee Y；Apple TV 目前还在用官方版。
- P2 半听模式：切走、锁屏继续出声；「只听声音」开关（省流量、开得快）。
- P2 手机端预下载：夜里 Wi-Fi 下自动下前几条推荐（带字幕），早上秒开、可离线。
- 持续：定期合并上游 `yattee/yattee`，合并后检查 CloudKit schema 有没有新字段。

## 想法池（待挑）

- 推荐自动连播：看完自动接推荐流的下一条（睡前刷）。
- 睡眠定时器：N 分钟后停 / 播完这条就停（可参考 7inh/yattee 的 On-the-go 面板）。
- 中文字幕自动打开：人工中文 > 自动中文 > 英文。
- 中英双语字幕；视频页 Claude 摘要和要点。
- 底部标签精简：Sources 挪进设置，只留首页 / 订阅 / 下载 / 搜索。
- 精简设置：隐藏用不到的源类型（Invidious / Piped / PeerTube）和多账号。
- Mac 键盘快捷键（空格暂停、方向键快进快退）。
