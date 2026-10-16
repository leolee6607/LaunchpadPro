# LaunchpadPro 优化方案（只读源码分析 · 不改代码）

- 分析对象：`/Users/leo/本地/Project_Git/重要/LaunchpadPro` main @ `cf82acc`（1.2.3），文件:行号均指该版本
- 分析日期：2026-10-16；本文只出方案，未修改仓库任何文件，未 build / 安装

---

## 0. 本机实况（只读采集，是后面诊断的前提）

| 项目 | 实测值 | 对诊断的意义 |
|---|---|---|
| 系统 | **macOS 27.0.1 (26A434)** | 代码里所有"macOS 26 如何如何"的假设都没在 27 上验证过 |
| 已装版本 | LaunchpadPro 1.2.3（`com.leo.launchpadprocodex`，正在运行） | 与仓库 HEAD 一致 |
| 显示器 | 内建 3024×1964 **@120Hz**；外接 Redmi 27 NU 3840×2160 **@60Hz** | 启动器开在"鼠标所在屏"（`OverlayController.swift:37,117-132`），鼠标在外接屏时物理上限就是 60Hz |
| 内建触控板 | `ReportInterval = 8000µs` ≈ **125Hz** 报点 | 事件率 ≥ 刷新率，1:1 直驱可行，不需要"追赶式平滑" |
| 布局数据 | 55 个顶层条目（54 app + 1 文件夹内含 56 app），9×5=45/页 → **2 页 [34, 21]**，约 110 个 app | 每帧 SwiftUI 要 diff 的条目规模 ≈ 55 + 文件夹 9 个小图标 |
| 系统手势键 | `com.apple.dock showLaunchpadGestureEnabled = 0`（LaunchpadPro 已改）；`showDesktopGestureEnabled = 1`；两个触控板域 `TrackpadFourFingerPinchGesture = 2`、`TrackpadFiveFingerPinchGesture = 2`；NSGlobalDomain 无 `com.apple.trackpad.*Pinch*`；`com.apple.Spotlight` 域无手势键 | **Dock 键已经是 0，Spotlight 仍随捏合弹出 → Dock 键在 27 上无效** |
| Dock / Spotlight 二进制（只读 `strings`/`otool`） | 27.0.1 的 Dock 只含 `showDesktopGestureEnabled`，**不含 `showLaunchpadGestureEnabled`**；Dock 链接 `Gestures.framework`、`MultitouchSupport`、`SkyLight`；`Spotlight.app` 不链接任何手势/HID 框架 | LaunchpadPro 改的键在 Dock 里已无代码读取；识别方大概率仍是 Dock，Spotlight 只是被叫起来 |
| 触控板手势配置的实时位置 | IORegistry `HIDEventServiceProperties` 字典里有 `TrackpadFourFingerPinchGesture=2`、`TrackpadFiveFingerPinchGesture=2`、`MTGestureConfiguration`；`hidutil property --get` 按服务直接取这些键返回 null | 真正生效的是 HID 事件系统的实时属性，不是 defaults 文件本身 |
| LaunchpadPro 设置 | hotKey 未设（默认 ⌥Space）、五指捏合默认开、触发角开（左下）、分页模式、`columns 9 / rows 5 / iconSize 84 / backgroundDim 0.42` | |
| 系统快捷键 | Spotlight（64/65）、输入法切换（60/61）均为默认 | ⌘Space 与 ⌥Space **不**是快捷键冲突 |
| 其他手势工具 | 无 BTT / Hammerspoon 等运行 | 排除第三方干扰 |
| Leo 实测 ① | 只做五指捏合、不碰键盘，Spotlight（应用界面）与 LaunchpadPro 一起冒出来 | 问题 2 的核心事实 |
| Leo 实测 ②（LaunchpadPro 已退出） | 系统设置里「App（捏拢拇指和其他三指）」开关**关不掉**，前后 diff 只有 `com.apple.dock` mod-count +2 | 27.0.1 连 Apple 自己的开关都是空操作 |
| Leo 实测 ③（LaunchpadPro 已退出） | 直接把两个触控板域 `TrackpadFour/FiveFingerPinchGesture` 与 `-currentHost -g` 的 `four/fiveFingerPinchSwipeGesture` 写 0 并 `killall Dock`：设置界面「App」「显示桌面」都显示关了，五指捏合 Spotlight **仍弹出**（未注销）；已恢复为 2 | defaults 这一层在 27.0.1 整体拦不住 |

---

## 1. 问题 1：左右翻页"像 60Hz"、不跟手

### 1.1 源码还原：一次横向滑动从手指到屏幕走了什么

```
触控板 scrollWheel 事件(≈125Hz)
 → NSEvent.addLocalMonitorForEvents                        OverlayController.swift:151-157
 → handleScroll                                              :179-235
    ├ 第一帧 |dx|>|dy| 才判定横滑，之前的横向分量被丢掉          :192-198
    ├ dampedHorizontalDelta：对 dx 做 EMA 低通 + 死区           :237-255
    └ LauncherBus.liveScroll(dx) → @Published liveScrollTick  LauncherBus.swift:24-27
 → SwiftUI：LauncherRootView(观察 bus, LauncherViews.swift:17) 与 PagedLauncherView(观察 bus, :37) 整体失效
 → .onChange(liveScrollTick)：只改 swipeTargetOffset(×1.14)，不改 swipeOffset   PagedLauncherView.swift:193-203
   （画面此刻不动，除非落后 >18% 屏宽才跳一下 :199-201）

CADisplayLink(panel.displayLink, 固定 120)                   OverlayController.swift:257-264
 → displayLinkFired → bus.displayFrame → @Published displayFrameTick   :271-274, LauncherBus.swift:35-38
 → 两个 View 再次整体失效
 → .onChange(displayFrameTick)：swipeOffset += (target-offset)*blend，blend≈0.47@120Hz   PagedLauncherView.swift:204-217
 → body 重算：placedEntries(:97-103)、indexMap(:107,517-526)、ForEach 全部条目(:116-129)
   每个条目带 GeometryReader→preference(:120-127)、highPriorityGesture(:262)
 → .offset(x: swipeOffset) 作用在整组上(:131)，随后 compositingGroup+blur(0)+saturation(1)+brightness(0)+opacity(1)(:132-136)
 → 55 个 GeometryReader 的 frame(in: canvasSpace) 因 offset 全部变化 → reduce 合并 55 个字典 → onPreferenceChange 写 entryFrames(:167)
 → CA 提交 → 下一个 vsync 上屏
```

### 1.2 根因诊断（按确定性排序）

**R1｜算法性滞后：两级低通 + 只在 display link 上更新画面（确定性，可计算）**

- 第一级：`dampedHorizontalDelta`（`OverlayController.swift:237-255`）对每事件 dx 做 EMA，`alpha = 0.22 + |dx|/10`，范围 [0.24, 0.86]（`:248`）。对"位移增量"做 EMA，等效于位置落后 `(1-α)/α` 个事件：慢速滑动 |dx|≈1pt 时 α≈0.32 → **落后 ≈2.1 帧**；快速 |dx|≈6pt 时 α≈0.82 再叠加 `directMix`（`:251-252`）→ ≈0.2 帧。
- 第二级：`displayFrameTick` 里的追赶 `blend = 1-exp(-76·dt)`（`PagedLauncherView.swift:210-211,215`），120Hz 下 blend≈0.469 → 再落后 `(1-β)/β ≈ 1.1 帧`；60Hz 下 blend 封顶 0.72。
- 画面不随事件更新：`liveScrollTick` 只写 `swipeTargetOffset`（`:198`），`swipeOffset` 要等下一次 display link tick 才动 → 平均再 +0.5 帧，加上 CA 提交→上屏 +1 帧。
- 合计（120Hz）：慢速 ≈ 2.1+1.1+0.5+1 ≈ **4.7 帧 ≈ 39ms**；快速 ≈ 0.2+1.1+1.5 ≈ **2.8 帧 ≈ 24ms**。AppKit 原生 1:1 滚动约 1.5–2 帧（12–17ms）。多出的 10–25ms 纯算法延迟，正是"120Hz 屏却没有 120Hz 跟手感"的主要来源——帧率可能是 120，但内容始终在手指后面拖。
- 附加：`× 1.14` 增益（`:194`）让内容比手指快 14%，不是 1:1；死区 `|dx|<0.035 / |output|<0.04`（`:239,254`）会吞掉极慢滑动的微小位移再成批释放。

**R2｜每帧两次整树失效：SwiftUI 重绘范围过大（高概率，需 Time Profiler 定量）**

- `LauncherBus` 把 `liveScrollTick`、`displayFrameTick` 都做成 `@Published`（`LauncherBus.swift:7-12`）。`@ObservedObject` 是对象级失效，不区分属性：每个 scroll 事件（≈125Hz）和每个 display link tick（120Hz）都让 `LauncherRootView`（`LauncherViews.swift:17`）和 `PagedLauncherView`（`PagedLauncherView.swift:37`）整体重算 body，**每秒最多 ≈245 次全树重算**。
- `PagedLauncherView.body` 每次重算都做：`placedEntries` 展平全部页（`:97-103`）、`indexMap` 重建字典（`:107,517-526`）、`ForEach` 对**所有页**的条目（不是只有可见页）生成 `LauncherEntryView` + `.position` + `.background(GeometryReader)` + `highPriorityGesture(dragGesture)`（`:116-129,262`）。`LauncherEntryView`/`AppIconView` 都带 `onLaunch` 闭包参数（`LauncherViews.swift:520,550`），闭包不可比较 → SwiftUI 无法判等短路，子 view body 跟着重算（`AppIconView.body` 含 Image/Text/shadow/contextMenu/onHover 等，`:557-602`）。
- `.onChange(of: model.displayEntries)`（`PagedLauncherView.swift:173`）要求每次 body 都算一遍 `displayEntries` → `sanitize(entries)` 全量 compactMap + 数组判等（`LaunchModel.swift:52-61,403-416`）。
- 对 Leo 当前规模（55 条目 + 文件夹 9 小图标 + 两处 glassEffect）估算：Release 下单次全树重算 1–3ms，×2 加布局/提交，一帧 4–9ms，**对 8.3ms 的 120Hz 预算是贴着线走**，光标扫过图标触发 `isHovering` 弹簧（`LauncherViews.swift:564-566,597`）时更容易掉帧。Debug(-Onone) 会放大数倍。

**R3｜每帧 55 次 GeometryReader 偏好测量是纯浪费（确定性）**

- `.offset` 在 `canvasSpace` 坐标系内部（offset 在 `:131`，coordinateSpace 在 `:166`），所以滑动时每个条目的 `proxy.frame(in: .named(canvasSpace))` 都变 → 55 个单元素字典 + `EntryFramePreference.reduce` 合并（`:11-17`）+ `onPreferenceChange` 写 `entryFrames`（`:167`），每帧一次。
- `entryFrames` 唯一用途是打开文件夹时取源矩形（`sourceFrame(forFolderID:)`，`:450-470`），而该函数本身已有用 `center()+swipeOffset` 计算的兜底（`:460-468`），完全可以替代。

**R4｜物理 60Hz 的情形（需 Leo 确认测试时鼠标在哪块屏）**

- 启动器开在鼠标所在屏（`OverlayController.swift:37,117-132`）。鼠标在 Redmi（60Hz）上时，display link 只能 60，追赶 blend 封顶 0.72，整条链路都是 60Hz。此时"像 60Hz"就是 60Hz。

**R5｜GPU/合成侧可疑项（需 Metal System Trace 定量，M5 上大概率不是主因）**

- 整组图标 `.compositingGroup()` 后挂 `blur(0)/saturation(1)/brightness(0)/opacity(1)`（`PagedLauncherView.swift:132-136`）：文件夹没打开时都是"零效果"滤镜，但 compositingGroup + CAFilter 仍可能让全屏图层每帧走离屏渲染。
- 每个图标 `.shadow(radius: 7)`（`LauncherViews.swift:565`），55 个；文件夹图标 `.glassEffect`（`:696`）随整组每帧移动需重采样背景；搜索框 `glassEffect`（`:181`）；最底下 `NSVisualEffectView(.fullScreenUI, .behindWindow)` 全屏模糊（`OverlayController.swift:91-94`）。

**R6｜附带发现（不是翻页帧率，但影响"卡"的整体印象）**

- 每次 `show()` 都在主线程同步 `model.reload()`（`OverlayController.swift:39`）→ `AppScanner.scan()` 遍历 7 个目录、对每个 app 读 Info.plist/多语言 InfoPlist.strings（`AppScanner.swift:32-80,136-155`），再 `rebuildEntries/applySort`。打开时主线程阻塞几十到几百毫秒，首帧迟。目录监视器 `AppDirectoryWatcher` 已经在，reload 其实只在有变更时需要。
- 图标首次加载在 `onAppear` 里主线程调 `NSWorkspace.icon(forFile:)`（`LauncherViews.swift:600,669-675`；`AppScanner.swift:189`），首次打开会"先占位后弹图标"。

**R7｜测量前提**：`bundle.sh` / `xcode-release.sh` 产物是 Release(-O)；Xcode Debug 配置是 `-Onone`（`project.pbxproj:414`）。所有帧率结论必须在 Release 上测。

### 1.3 方案

**Step 0｜先用 2 行改动验证 R1（不发版，只做 A/B，半小时）**

- `dampedHorizontalDelta` 直接 `return dx`（`OverlayController.swift:237-255`）；
- `.onChange(of: bus.liveScrollTick)` 里无条件 `swipeOffset = next`，增益 1.14→1.0（`PagedLauncherView.swift:194,199-201`）。
- 若手感立刻明显变"粘手"，说明 R1 是主因，再做下面的结构性方案；若仍"像 60Hz"，优先去查 R4（屏幕）和 R2（Time Profiler）。

**方案 1A（推荐）｜1:1 直驱 + 时间戳重采样 + 把每帧更新隔离到一个只改 offset 的小 view**

1. **拆 LauncherBus**（`LauncherBus.swift`）：
   - `nextPage/previousPage/reset/targetScreenTopSafeArea` 这些"每手势一次"的保留；
   - 把 `liveScroll/endScroll/displayFrame` 从 `@Published` 中移走，新建 `@Observable @MainActor final class SwipeState { var offset: CGFloat = 0; var pageIndex: Int; var pageCount: Int; var endRequest: (velocity: CGFloat, offset: CGFloat)? }`（Observation 框架按**属性**追踪，目标是 macOS 26，可用；Package 是 Swift 5 语言模式，`@Observable` 宏兼容）。
2. **新增 `SwipeEngine`（建议新文件 `SwipeEngine.swift`，由 OverlayController 持有）**：
   - 每个 scroll 事件：累加原始 `scrollingDeltaX`（`hasPreciseScrollingDeltas` 为真时就是点数），记录 `(position, timestamp)`，**立刻**写 `swipeState.offset = rubberBand(position)`（画面随事件更新，不等 display link）。
   - display link 只做两件事：(a) 没有新事件的帧用最近两事件的速度外推 `offset = p_last + v·min(T - t_last, 1.5·frameDuration)`，消除 125Hz 事件 vs 120Hz 刷新的拍频、以及外接 Magic Trackpad(≈90Hz) 的空帧——外推是**领先**不是滞后；(b) 手指抬起后不再需要（snap 交给 SwiftUI 弹簧）。`NSEvent.timestamp` 与 `CADisplayLink.targetTimestamp` 都是开机单调时钟，可直接比较（运行时做一次差值 sanity check）。
   - 删除 EMA 与死区；抬手时的 velocity 用最近 2–3 个事件的时间差算 pt/s，仅供翻页判定（阈值要换单位重调）。
   - 增益固定 1.0。
3. **PagedLauncherView 只在手势结束时参与**（`PagedLauncherView.swift`）：
   - 删除 `@ObservedObject bus` 对实时路径的依赖，删除 `.onChange(of: liveScrollTick / displayFrameTick)`（`:193-217`）；
   - 网格 `ZStack(ForEach…)` 包进一个极小的子 view：
     ```swift
     struct SwipeOffsetLayer<Content: View>: View {
         let state: SwipeState        // @Observable，只有这个 view 读 offset
         let content: Content
         var body: some View { content.offset(x: state.offset) }
     }
     ```
     父 view 不读 `state.offset`，所以每帧只有这个 view 重算，`content` 作为未变化的输入不会被重新 diff；
   - 翻页判定改为 `.onChange(of: state.endRequest)`，一手势一次：`withAnimation(snap) { currentPage = page; state.offset = 0 }`，两者在同一 transaction 内同步弹簧（现有 `snap` 参数保留，`:75`）；
   - `pageIndex/pageCount` 变化时写回 `SwipeState`，供引擎做 rubber band（逻辑搬自 `constrainedSwipeOffset/rubberBand`，`:472-486`）。
4. **删 R3 的偏好测量**：去掉 `EntryFramePreference`、`.background(GeometryReader…)`、`.onPreferenceChange`、`entryFrames`（`:11-17,54,120-127,167`），`sourceFrame(forFolderID:)` 直接用 `:460-468` 的计算路径（`center(...) + state.offset`）。
5. **`LauncherRootView` 不再观察 bus**（`LauncherViews.swift:17,28-30`）：`targetScreenTopSafeArea` 放进同一个 `@Observable` 环境对象，或在 `show()` 时通过保留的 `NSHostingView.rootView` 重新注入。
6. **`displayEntries` 改为廉价令牌**：`LaunchModel` 加 `@Published private(set) var layoutVersion: Int`，在 `entries/hiddenApps/searchText` 变化处 +1（`LaunchModel.swift` 各写入点），`PagedLauncherView:173` 改观察 `layoutVersion`。

**方案 1B（更彻底，改动大）｜横向位移下沉到 AppKit/CoreAnimation**

- 用 `NSViewRepresentable` 容器持有一个 `CALayer`，滑动时在 `CATransaction(disableActions)` 内直接改 `layer.transform/position`，SwiftUI 完全不参与每帧；或整页改成 `NSScrollView(horizontal, paging)` 让 AppKit 原生跟踪（自带 1:1、惯性、回弹）。
- 优点：延迟与原生一致、零 SwiftUI 每帧 diff；缺点：拖动排序（`dragGesture`、`previewPages`、跨页翻页 `flipPage`）和文件夹源矩形都要重新接坐标，回归面大。建议只在 1A 之后仍测出掉帧时再上。

**方案 1C（补充优化，1A 之后按测量结果择用）**

- P2：R5 的滤镜链改成"文件夹打开时才挂"——用自定义 `ViewModifier`，`progress == 0` 时原样返回 `content`（注意条件分支会改变子树 identity，`AppIconView` 的 `@State iconImage` 会重置，需先量 A/B 再决定）；给图标阴影改为在 `IconStore` 预烘焙进位图（一次离屏，之后零成本）；文件夹图标在网格里用静态 `.ultraThinMaterial`，glass 只留在打开的面板。
- P2：`IconStore` 按 `iconSize × backingScaleFactor` 预栅格化为 `CGImage` 并在扫描后后台预热（`AppScanner.swift:178-194`），消除首开占位闪动。
- P2：`show()` 不再无条件 `reload()`，改为目录监视器置脏标记后才扫，扫描放后台（`OverlayController.swift:39`，`AppDelegate.swift:140-146`）。
- P3：`ForEach` 只渲染 `clampedPage ± 1` 页的条目（对 Leo 2 页无感，对 300+ app 用户是量级差异）。
- P3：`AppIconView/LauncherEntryView` 去掉闭包参数（改走 Environment 或 model 方法），让 SwiftUI 能判等短路。

### 1.4 改动范围（1A）

| 文件 | 改动 |
|---|---|
| `OverlayController.swift` | `handleScroll` 瘦身为事件→`SwipeEngine`；display link 回调改为外推；删 EMA |
| `SwipeEngine.swift`（新） | 位置累加、时间戳外推、rubber band、抬手判定 |
| `LauncherBus.swift` | 拆为"每手势一次"的命令 + `@Observable SwipeState` |
| `PagedLauncherView.swift` | 删 3 个每帧 `onChange`、删偏好测量、加 `SwipeOffsetLayer`、`sourceFrame` 改计算路径、`displayEntries`→`layoutVersion` |
| `LauncherViews.swift` | `LauncherRootView` 去 bus 观察 |
| `LaunchModel.swift` | `layoutVersion` 令牌 |

### 1.5 风险

- 翻页判定阈值换成 pt/s 后需重调（现 `3.4 / 18` 是 EMA 单位，`PagedLauncherView.swift:219-221`）。
- 文件夹打开的缩放起点改为计算值，需核对与图标实际位置对齐（尤其拖动预览 `previewPages` 期间）。
- `@Observable` + `withAnimation` 同步两处状态是标准用法，但要确认 `currentPage` 引起的 `.position` 变化与 `offset→0` 在同一 transaction。
- 外接 Magic Trackpad 报点率可能 ≈90Hz，必须连外接板也测一遍外推逻辑。
- 1B 的拖动/文件夹坐标回归面大，不建议首轮做。

### 1.6 如何验证（量化）

1. **应用内追踪开关**（建议加 `LAUNCHPADPRO_SWIPE_TRACE=1` 环境变量，`os_log` 输出，不进 Release UI）：每次手势结束打印——事件数、事件率、display link 帧数、**丢帧数**（相邻 `targetTimestamp` 间隔 > 1.5×帧长）、**事件→上屏延迟**中位数（事件 `timestamp` 到包含该位移的 `CATransaction` 完成/`targetTimestamp`）。验收：120Hz 屏 2 秒滑动 ≥118 fps、丢帧 0、延迟中位数 ≤2 帧（≈17ms）；改前先跑一次留基线。
2. **Quartz Debug → Window → FrameMeter**（Xcode Additional Tools）：直接看 WindowServer 对内建屏的实际刷新率，排除 R4。
3. **Instruments · Time Profiler**（Release 构建，附加到运行中的进程）：滑动期间主线程每帧耗时 ≤3ms；对比 `AG::Graph` / `ViewGraph.updateOutputs` 的样本占比，改前改后各一份。
4. **Instruments · Metal System Trace**：GPU 每帧 ≤4ms；对 R5 做"去掉滤镜链 / 去掉阴影"的 A/B。
5. **iPhone 17 Pro 240fps 慢动作**拍手指与屏幕：数"手指开始动 → 内容开始动"的帧数，改前（预计 ≥6 帧@240 ≈ 25ms+）对比改后（目标 ≤4 帧 ≈ 17ms）；同机位拍 Spotlight 应用页左右翻做参照。
6. 主观对照：与 Spotlight 应用界面翻页、Safari 横向滚动比"粘手"程度。

---

## 2. 问题 2：五指捏合唤醒时 Spotlight 应用界面一起弹出（按 Leo 决定：只留结论，不再深挖）

### 2.1 唤醒机制（源码）

- **监听**：私有框架 `MultitouchSupport`（`Package.swift:15-16`；`FiveFingerPinchMonitor.swift:17-36`），对每个多点设备 `MTRegisterContactFrameCallback` + `MTDeviceStart`（`:223-226`），IOKit 热插拔重扫（`:240-277`）。回调在私有框架线程上收到**原始触点帧**，**只观察、固定 `return 0`**（`:68-85`，注释说明 return 1 在 26 上不是可靠的抑制手段）。
- **识别**：≥5 个 state 3/4 触点（`:298`），触点云收缩到 ≤0.90、质心漂移 ≤0.16、连续 2 帧（`:533-539,598-607`）。门槛低（≈10% 收缩），所以 LaunchpadPro **先于**系统识别。
- **触发后**：主线程 `overlay.show()`（`:307`，`AppDelegate.swift:176`）→ `makeKeyAndOrderFront` + `NSApp.activate(ignoringOtherApps:)`（`OverlayController.swift:50-51`）；面板 `maximumWindow` 层级、`hidesOnDeactivate = false`、全代码无失活/失键处理、无 `applicationWillTerminate`（`:83,89`）。
- **不模拟按键/修饰键**：全仓库无 `CGEvent`/`CGEventTap`/`addGlobalMonitor`（已 grep）；快捷键是 Carbon ⌥Space（`HotKey.swift:45-52`，`AppSettings.swift:55`），与 ⌘Space 无关，注册返回值被忽略。
- **唯一的"接管"**：`SystemPinchGestureOverride` 把 `com.apple.dock showLaunchpadGestureEnabled` 写 0 + `killall Dock`，每 300s 和唤醒后巡检（`FiveFingerPinchMonitor.swift:324-528`，依据写在 `:312-323` 注释里：macOS 26 上 Dock 仅凭该键决定）。

### 2.2 结论

1. **打架的时序**：两个识别器看同一个物理手势。LaunchpadPro 门槛低先弹出并激活；系统随后识别"拇指+三指捏合"拉起 Spotlight 应用界面并抢走激活；LaunchpadPro 不随失活隐藏（`OverlayController.swift:89`，且无 `didResignActive` 处理）→ 两个界面同屏，键盘焦点在 Spotlight。`return 0` 的观察式回调（`:84`）从机制上就不可能阻止系统那一路。
2. **现有接管在 27.0.1 必然失效**：27.0.1 的 Dock 二进制里已经没有 `showLaunchpadGestureEnabled` 字符串（只剩 `showDesktopGestureEnabled`），LaunchpadPro 改的是一把没人读的键。Leo 实测进一步证明 defaults 这一层整体不可用：系统设置里「App」开关本身关不掉（只动 mod-count）；直接写两个触控板域 + `-currentHost -g` 的捏合键并 `killall Dock`，UI 显示已关但捏合仍拉起 Spotlight（未注销）。"Apple 自己的开关都是空操作"说明大概率是 27.0.1 的系统 bug 或硬连线，不值得再押注任何 defaults 键。
3. **识别方**：Dock 仍链接 `Gestures.framework` / `MultitouchSupport` / `SkyLight`，`Spotlight.app` 不链接任何手势框架 → 识别大概率仍在 Dock（或 WindowServer/SkyLight），Spotlight 只是被叫起来显示。触控板手势配置的实时副本在 HID 事件系统的 `HIDEventServiceProperties`（含 `TrackpadFour/FiveFingerPinchGesture=2`、`MTGestureConfiguration`），这是系统设置本应实时下发的那一层。
4. 已排除：快捷键冲突（⌥Space ≠ ⌘Space，系统快捷键为默认）、第三方手势工具。

### 2.3 不依赖这些键的方向（按性价比排序；只列方向，不再做额外调研）

| 优先 | 方向 | 原理 | 代价 / 把握 | 风险 |
|---|---|---|---|---|
| ① 推荐先做 | **焦点再夺回 + 失活隐藏**（`OverlayController.swift`） | 因捏合 `show()` 后 1.5s 内，若 `NSWorkspace.didActivateApplicationNotification` 报 `com.apple.Spotlight`（本机已核对 bundle id）激活，立即 `NSApp.activate` + `panel.makeKeyAndOrderFront`——Spotlight 失焦即自动收起；窗口期外失活 → `hide()`（与原生 Launchpad 一致）；`hide()` 后把激活还给 `show()` 前记住的前台 app | 公开 API，0.5 天；**结果层兜底，不管谁识别了手势都成立** | 可能有一帧 Spotlight 闪现（面板在 `maximumWindow` 层级，闪现多半只透过背景模糊可见）；`activate(ignoringOtherApps:)` 在 14+ 弃用但可用，被拒时改 `NSRunningApplication.current.activate(from:options:)` |
| ② | **替代手势**（识别器 + `SettingsView.swift`） | 新增「五指轻点 / 五指按住 250ms」唤起选项，系统未绑定这两个手势（五指上下滑会被当四指滑动，不要用）；识别器已有触点云与时间戳，加两个分支即可 | 0.5 天；**从构造上 100% 消除竞争** | 改用户习惯；仍依赖私有 MultitouchSupport 读帧（现状已接受） |
| ③ spike | **HID 实时属性** | 系统设置本应通过 `IOHIDEventSystemClient` 把 `TrackpadFour/FiveFingerPinchGesture=0` 实时下发到 `HIDEventServiceProperties`；用 `hidutil property --set` 或 `IOHIDEventSystemClientSetProperty` 直接改这一层，绕过 defaults | 1 小时验证；把握中——设置开关本身坏了，可能坏的就是这条路 | 同时关掉张开→显示桌面；要恢复逻辑；属性粒度/权限未知 |
| ④ spike | **CGEventTap 吞手势事件** | 活动 tap（`kCGSessionEventTap` 或 `kCGHIDEventTap`，`headInsert`）在五指按下期间对 type 29/30/31 及可疑私有类型（如 `kCGSEventDockControl`）返回 nil | 1–2 小时验证；**把握低中**——BTT / Swish / Multitouch 三个带辅助功能权限的成熟产品都要求用户关系统手势而非拦截；公开资料只证实 tap **能看见** type 29，没有拦截成功的案例 | 需辅助功能权限（TCC 随签名变化可能静默失效）；tap 回调必须在独立线程并处理 `tapDisabledByTimeout/ByUserInput` 重启，否则会给全系统输入加延迟；误吞会杀掉两指缩放、三四指滑动；若 Dock 经 SkyLight 私有通道或 `Gestures.framework` 直接读触点，tap 根本看不到 |
| ⑤ 10 分钟 | `return 1` 复测 | 回调返回 1（`:84`）在 26 上不可靠，27 未测 | 极低成本 | 26 上会让后续触点序列失效，需验证 27 行为 |
| ⑥ 5 分钟 | 注销复测 | 写键 → 注销重登 → 捏合 | 若生效可作"需注销"保底 | 体验差；设置开关自身失效暗示大概率无效 |
| 顺带必修 | 退出恢复 / 去 `killall` 风暴 | `applicationWillTerminate` 调 `restoreOriginals()`；巡检不再无节制 `killall Dock`（`:435-463`）；`RegisterEventHotKey` 返回值上报 | 1 小时 | — |

**④ 如要做，spike 步骤**：A 观察——listen-only tap、`kCGEventMaskForAllEvents`，捏合时记录 type、`CGEventField(110)`（HID 类型）与 0…200 字段快照，对比两指缩放找"系统手势"标记；B 粗暴拦截——活动 tap 对所有手势类事件返 nil，捏合 10 次看 Spotlight 是否出现；**B 失败即放弃**；C 精细化——只在 `FiveFingerPinchMonitor` 看到 ≥4 触点期间、只对标记类型吞，验证两指缩放/三四指滑动/张开不受影响。

### 2.4 验证

- 修复后 20 次捏合：Spotlight 出现 0 次（或出现即消失），捏合后盲打 3 个字母应落在 LaunchpadPro 搜索框；修复前先记基线。
- `log stream --style compact --predicate 'process == "Spotlight" OR process == "Dock" OR process == "LaunchpadPro"'` 看拉起时序与谁在反应。
- 开/关功能后 `defaults read` 两个触控板域 + dock 域确认恢复；外接妙控板重复一遍。

---

## 3. 需要 Leo 实测确认的假设

| # | 假设 | 怎么确认 | 影响 |
|---|---|---|---|
| H1 | 测"像 60Hz"时鼠标/启动器在内建 120Hz 屏，不是 Redmi | 拔掉外接屏或把鼠标放内建屏再测 | 若在外接屏，R4 成立，软件层面无解 |
| H2 | R1 是跟手感主因 | §1.3 Step 0 的 2 行 A/B | 决定是否值得做 1A 全套 |
| H3 | R2 让主线程逼近 8.3ms | Time Profiler（Release）滑动时主线程每帧耗时 | 决定 1C 的 P2/P3 是否要做 |
| H4 | R5 滤镜链/阴影/glass 不是 GPU 瓶颈 | Metal System Trace 去滤镜 A/B | 决定是否改视觉实现 |
| H5 | Spotlight 失焦会自动收起、`activate(ignoringOtherApps:)` 在 27 上仍被允许 | 捏合出现双界面时点一下 LaunchpadPro 面板，看 Spotlight 是否消失、焦点是否回来 | 决定 §2.3 ① 的实现细节 |
| H6 | 捏合后面板"看得见打不进字"的频率 | 捏合后立刻盲打 3 个字母 | §2.3 ① 的基线 |
| H7 | §2.3 ③/④ 两个 spike 是否可行 | 各 1–2 小时，B 步失败即放弃 | 决定是否存在"真正接管"的路，否则以 ①+② 收口 |
| H9 | 是否存在"没捏合也莫名弹出" | 回忆/观察是否发生在鼠标到左下角时 | 触发角（左下，已开启，`AppDelegate.swift:186-219`）鼠标扫过 Dock 左端即触发，属误触而非手势冲突 |
| H10 | 外接 Magic Trackpad 报点率 | `ioreg -rc AppleMultitouchDevice -d 1 \| grep ReportInterval`（连上外接板时） | 决定 1A 外推逻辑的测试覆盖 |

---

## 4. 总结：改动文件清单与工作量

| 问题 | 文件 | 工作量（含自测） |
|---|---|---|
| 1 · Step 0 A/B | `OverlayController.swift`、`PagedLauncherView.swift` | 0.5h |
| 1 · 方案 1A | `OverlayController.swift`、`SwipeEngine.swift`(新)、`LauncherBus.swift`、`PagedLauncherView.swift`、`LauncherViews.swift`、`LaunchModel.swift` | 1–1.5 天 |
| 1 · 测量工具（trace 开关 + 基线） | `OverlayController.swift`/`SwipeEngine.swift` | 0.5 天 |
| 1 · 方案 1C（按测量择用） | `LauncherViews.swift`、`AppScanner.swift`、`OverlayController.swift`、`AppDelegate.swift` | 0.5–1 天 |
| 2 · ① 焦点再夺回 / 失活隐藏 / 还焦点 + 顺带必修（退出恢复、去 killall） | `OverlayController.swift`、`AppDelegate.swift`、`FiveFingerPinchMonitor.swift`、`HotKey.swift` | 0.5–1 天 |
| 2 · ② 替代手势选项 | `FiveFingerPinchMonitor.swift`、`SettingsView.swift`、`AppSettings.swift` | 0.5 天 |
| 2 · ③④⑤⑥ spike（只验证不承诺） | 独立脚本，不入仓库 | 合计 ≤ 半天 |

合计：核心（1A + 2①）约 2–2.5 天；加 1C、2②、spike 约 3.5–4 天。建议顺序：问题 1 Step 0 验证（半小时）→ 1A → 2① → 按测量做 1C → 2② / spike 视需要。

---

## 5. 参考

- BetterTouchTool 论坛《Launchpad Shortcut with Trackpad: How Can I Customise it or Disable it?? (macOS 26)》：设置项在 26/26.1 移除、手势仍有效、26.x 上关"显示桌面"可停掉（27.0.1 上 Leo 实测该开关已失效）；BTT 作者明确不拦截系统手势 — https://community.folivora.ai/t/launchpad-shortcut-with-trackpad-how-can-i-customise-it-or-disable-it-macos-26/45525
- Apple《Use Multi-Touch gestures on Mac》（"Apps：拇指与三指捏合"）— https://support.apple.com/en-us/HT204895
- Docket 项目 PR #105 / Issue #35：`com.apple.dock.prefchanged` 是 Dock **发出**的分布式通知，未见证据可反向命令 Dock 重读 — https://github.com/nparashar150/docket/pull/105 、 https://github.com/nparashar150/docket/issues/35
- opendisplay Issue #5：监听级 CGEventTap 能看到手势事件(type 29)，但不说明能拦截系统手势 — https://github.com/peetzweg/opendisplay/issues/5
- Jamf 社区（10.7 时代）`showLaunchpadGestureEnabled` + `TrackpadFour/FiveFingerPinchGesture` 用法，说明这组键的历史语义 — https://community.jamf.com/general-discussions-2/disabling-more-gestures-in-10-7-5-38302
