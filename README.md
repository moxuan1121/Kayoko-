# Kayoko

Feature-rich clipboard manager for iOS.

A Kayoko fork maintained by **mlgm**, based on the [OwnGoal Studio edition](https://github.com/OwnGoalStudio/Kayoko).

## Credits

- Original project: [AlexandraAurora/Kayoko](https://github.com/AlexandraAurora/Kayoko)
- Based on: [OwnGoalStudio/Kayoko](https://github.com/OwnGoalStudio/Kayoko)

## License

GPLv3. See [`COPYING`](COPYING).

## RegionShot 分词接入

在 `kayoko-keyboardai` 分支中，长按文字历史或收藏条目会先关闭 Kayoko，再打开 RegionShot 分词窗口。动态调用 `RSInputOpenCopiedText`，需要 RegionShotInput 已注入同一进程；不再调用或依赖 KeyboardAI。

图片、空文本、超过 24,000 UTF-16 单元的文本，以及 RegionShot 未加载时，保留 Kayoko 原有预览。传递原文，不改写剪贴板，不发送 AI 请求。

软件包标识保留原值以便覆盖升级；设置域、历史数据路径和原有作者信息保持不变。
