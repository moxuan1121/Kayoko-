# Kayoko

Feature-rich clipboard manager for iOS.

A Kayoko fork maintained by **mlgm**, based on the [OwnGoal Studio edition](https://github.com/OwnGoalStudio/Kayoko).

## Credits

- Original project: [AlexandraAurora/Kayoko](https://github.com/AlexandraAurora/Kayoko)
- Based on: [OwnGoalStudio/Kayoko](https://github.com/OwnGoalStudio/Kayoko)

## License

GPLv3. See [`COPYING`](COPYING).

## Keyboard AI branch

Branch `kayoko-keyboardai` is based on `kayoko-keyboardx` at `8adbf80`.
Long-press a text history/favorite entry to open Keyboard AI's existing word-selection
panel after Kayoko finishes hiding. Requires Keyboard AI 1.3.2 installed and injected
into the same process (normally SpringBoard). Resolves `KAOpenCopiedText` dynamically;
no KeyboardX methods, clipboard rewriting, AI request or new IPC dependency.
Image/empty/over-24,000-UTF-16 entries and missing plugin retain Kayoko preview.
The receiving panel offers Search / Copy / Close, with Keyboard AI's settings.

Package: `com.moxuan.kayoko.keyboardai`, version `4.7.9-keyboardai2`. Long-press handoff now closes Kayoko immediately instead of waiting for its 0.33-second dismissal animation before opening Keyboard AI.
Conflicts/replaces the KeyboardX edition to prevent double injection. Existing Kayoko
preference domains and data paths are retained. Original authorship and GPLv3 retained.
