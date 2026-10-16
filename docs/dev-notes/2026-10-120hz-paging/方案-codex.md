推荐先修复翻页的事件累计、双重平滑和全页面更新，再处理 Spotlight 与启动器的焦点交接。源码没有“固定限制为 60Hz”的证据，也没有模拟 Cmd+空格；真实呈现帧率和当前系统的手势兼容性仍需实测。

本方案基于 `main` 分支 `cf82acc1`。本机已安装版本为 **1.2.3**，系统实际为 **macOS 27.0.1（26A434）**。本次仅做只读检查，未修改文件或系统设置，未采集运行时性能数据。

## 1. 左右翻页不够流畅

### 1.1 根因诊断

**① 已请求 120Hz，但请求频率不能证明画面达到 120fps。**

[OverlayController.swift:257](/Users/leo/本地/Project_Git/重要/LaunchpadPro/Sources/LaunchpadProCodex/OverlayController.swift:257) 已通过 `panel.displayLink(...)` 创建 `CADisplayLink`，设置 `minimum/maximum/preferred = 120`，并加入主线程 `.common` RunLoop。翻页没有使用 `CVDisplayLink` 或普通定时器驱动。

窗口绑定方式本身合适，能与窗口所在显示器同步。实际回调频率仍受显示器和系统调度影响，更不等于 SwiftUI 每次都完成了一帧可见更新。[Apple：窗口 DisplayLink](https://developer.apple.com/documentation/appkit/nswindow/displaylink%28target%3Aselector%3A%29)、[帧率请求范围](https://developer.apple.com/documentation/quartzcore/cadisplaylink/preferredframeraterange)

**② 两层平滑明确增加了跟手延迟。**

第一层位于 [OverlayController.swift:237](/Users/leo/本地/Project_Git/重要/LaunchpadPro/Sources/LaunchpadProCodex/OverlayController.swift:237)：每个滚动事件先经过自适应低通滤波，小位移还会被阈值过滤。

第二层位于 [PagedLauncherView.swift:193](/Users/leo/本地/Project_Git/重要/LaunchpadPro/Sources/LaunchpadProCodex/PagedLauncherView.swift:193)：事件只改变 `swipeTargetOffset`，显示帧再通过 `1 - exp(-76 * dt)` 让实际位移追赶目标。

在 120Hz 下，第二层每帧只追赶约 47% 的差值。仅这一层，对目标位置阶跃达到约 90% 就需要约 4 帧。这个数字是算法推算，不是实测端到端延迟。

因此，即使画面确实以 120fps 更新，也可能有明显的拖尾感。第一层滤波按事件次数计算，还会随内置、外接触控板的事件频率改变手感。

**③ 滚动总线可能丢失位移增量。**

[LauncherBus.swift:24](/Users/leo/本地/Project_Git/重要/LaunchpadPro/Sources/LaunchpadProCodex/LauncherBus.swift:24) 每次只覆盖 `latestScrollDX`，再递增 `liveScrollTick`。分页视图在 `.onChange` 中只消费一次最新值，没有累计事件之间的全部位移。

如果一次 SwiftUI 更新前收到多个滚动事件，通知可能合并，而前面的增量已经被覆盖。这会表现为移动距离不足、忽快忽慢，主线程繁忙时更容易出现。

这是明确的实现风险，发生频率需要记录“收到的位移总和”和“消费的位移总和”确认。

**④ 每帧更新影响范围过大，工作量随总应用数量增长。**

[LauncherViews.swift:14](/Users/leo/本地/Project_Git/重要/LaunchpadPro/Sources/LaunchpadProCodex/LauncherViews.swift:14) 的根视图和分页视图都观察同一个 `LauncherBus`。总线中的滚动通知、帧通知都会使观察者失效，根视图即使只需要安全区信息，也会参与更新。

[ PagedLauncherView.swift:97](/Users/leo/本地/Project_Git/重要/LaunchpadPro/Sources/LaunchpadProCodex/PagedLauncherView.swift:97) 将所有页面展开到同一个 `ForEach`，每次计算页面索引映射。每个图标还有 `GeometryReader`，再通过 [PagedLauncherView.swift:167](/Users/leo/本地/Project_Git/重要/LaunchpadPro/Sources/LaunchpadProCodex/PagedLauncherView.swift:167) 把坐标字典写回状态。

这些结构会增加视图计算、几何更新和状态反馈的负担。外层 `.clipped()` 不能代替分页虚拟化。但不能仅凭源码认定所有图标每帧都被重新绘制，具体成本应通过 Instruments 确认。

**⑤ 唤醒和目录变化会在主线程同步扫描应用。**

[OverlayController.swift:36](/Users/leo/本地/Project_Git/重要/LaunchpadPro/Sources/LaunchpadProCodex/OverlayController.swift:36) 每次 `show()` 都先执行 `model.reload()`。

[LaunchModel.swift:26](/Users/leo/本地/Project_Git/重要/LaunchpadPro/Sources/LaunchpadProCodex/LaunchModel.swift:26) 属于 `@MainActor`，同步执行目录扫描、布局读取和排序。[AppScanner.swift:32](/Users/leo/本地/Project_Git/重要/LaunchpadPro/Sources/LaunchpadProCodex/AppScanner.swift:32) 还会读取应用包信息、本地化名称和文件属性。

[AppDirectoryWatcher.swift:52](/Users/leo/本地/Project_Git/重要/LaunchpadPro/Sources/LaunchpadProCodex/AppDirectoryWatcher.swift:52) 虽然在后台监听目录，却把扫描回调送回主线程。桌面、下载目录变化也可能触发扫描。

这能解释“刚唤醒就滑动时卡一下”以及偶发停顿，不能单独解释所有热态翻页都像 60Hz。

**⑥ 图标已有缓存，但首次加载和合成成本仍需检查。**

[AppScanner.swift:178](/Users/leo/本地/Project_Git/重要/LaunchpadPro/Sources/LaunchpadProCodex/AppScanner.swift:178) 已有按路径保存的 `NSImage` 缓存。缓存未命中时，会持锁同步调用 `NSWorkspace.icon(forFile:)`；没有显式的目标像素尺寸预解码流程，也没有容量上限或文件更新失效机制。

普通图标通过 `onAppear` 加载，文件夹预览则在视图计算中访问缓存。图标阴影、文件夹玻璃效果和全屏背景材质也增加合成成本，见 [LauncherViews.swift:559](/Users/leo/本地/Project_Git/重要/LaunchpadPro/Sources/LaunchpadProCodex/LauncherViews.swift:559)、[LauncherViews.swift:684](/Users/leo/本地/Project_Git/重要/LaunchpadPro/Sources/LaunchpadProCodex/LauncherViews.swift:684)。

目前不能断言 GPU 或图标解码是主要瓶颈，需要分别对冷缓存、热缓存和文件夹较多的页面采样。

**⑦ 抬手后换了一套动画驱动，速度交接不连续。**

[OverlayController.swift:206](/Users/leo/本地/Project_Git/重要/LaunchpadPro/Sources/LaunchpadProCodex/OverlayController.swift:206) 在手指结束时立即停止 DisplayLink，后续惯性事件没有参与翻页。吸附交给 SwiftUI 弹簧，初速度固定为 0。

[ PagedLauncherView.swift:218](/Users/leo/本地/Project_Git/重要/LaunchpadPro/Sources/LaunchpadProCodex/PagedLauncherView.swift:218) 使用的“速度”实际是单次事件的滤波位移，没有除以时间。不同事件频率下，相同动作可能得到不同翻页结果。

这会影响抬手后的连续感，但不能据此认定 SwiftUI 弹簧只能运行在 60Hz。

### 1.2 推荐方案：先收紧现有 SwiftUI 管线

**A. 建立独立的分页运动状态。**

滚动事件只负责累计原始位移、记录时间和阶段。DisplayLink 每帧消费全部待处理增量，更新一次分页容器位移。

取消两层追赶式平滑。跟手阶段直接映射累计位移，仅在页首、页尾应用边界阻尼。若实测确有输入噪声，再增加一层按时间计算的轻量滤波。

速度统一为“点/秒”。手势结束前先消费剩余位移，再决定目标页；取消事件单独处理，不能继续沿用正常抬手的翻页判定。

**B. 将高频状态限制在分页容器。**

把屏幕安全区、重置命令与逐帧运动状态分开。根视图、搜索框和静态图标不再订阅逐帧通知。

页面布局、应用映射和显示条目只在数据或网格配置变化时更新。普通翻页只改变整页容器的平移量。

**C. 普通翻页只保留当前页及相邻页。**

默认维持前一页、当前页、后一页。拖拽到新页时再扩展必要页面，并保持条目 ID 稳定。

图标位置优先由已有网格公式计算。只在文件夹展开、拖拽等确实需要时测量实际坐标，避免翻页期间持续回写全量坐标字典。

**D. 跟手和吸附使用连续的运动状态。**

保留窗口绑定的 `CADisplayLink`，让它覆盖跟手和吸附两个阶段。吸附继承抬手速度，新手势可以立即打断。

按目标显示器能力请求帧率，跨屏时更新配置。运动结束后停止回调，隐藏时清空全部运动状态。120Hz 是活动期间的目标，60Hz 外接屏按其实际能力运行。

**E. 移走主线程扫描，分阶段准备图标。**

唤醒先展示已有应用快照。目录变化只标记刷新需求，后台扫描完成后在主线程合并结果。用扫描版本号丢弃过期结果，避免覆盖用户刚完成的拖拽或重命名。

优先准备当前页和相邻页图标，按显示尺寸与 backing scale 缓存。图标获取、解码和发布分别遵守所用 API 的线程约束，不能直接把整段 AppKit 代码搬进后台任务。缓存锁只保护字典访问，不包住耗时加载。

### 1.3 备选方案：局部改用 AppKit/Core Animation

如果完成上述改动后，热态翻页仍因 SwiftUI 更新超出帧预算，再把分页位移放入 `NSViewRepresentable` 容器，由 Core Animation 平移整页。

保留现有 SwiftUI 图标、菜单和文件夹业务。需要额外处理视觉坐标与点击、拖拽、无障碍坐标的一致性。

不建议第一步重写整个渲染器，也没有证据支持仅把 `CADisplayLink` 换成 `CVDisplayLink` 就能解决问题。

### 1.4 改动范围与风险

主要涉及事件接收、分页状态、视图订阅、页面布局、应用扫描和图标缓存。

风险集中在跨页拖拽、文件夹展开原点、快速反向滑动，以及后台扫描与用户编辑同时发生。减少平滑后手感会更直接，需要重新校准位移比例和翻页阈值；预加载范围过大则会增加内存。

### 1.5 如何验证

**先建立同条件基线。**

使用 Release 构建，分别记录持续拖动、抬手吸附、首次唤醒后的第一次翻页。内置屏、外接屏分别测，记录刷新率设置、电源状态、缩放比例、触控板类型和应用数量。

使用 Instruments 的 SwiftUI、Time Profiler、Hitches 轨道区分视图计算、主线程阻塞和呈现迟到。Apple 的 SwiftUI 性能工具支持查看更新次数及更新因果关系。[Apple：SwiftUI 性能分析](https://developer.apple.com/documentation/xcode/understanding-and-improving-swiftui-performance)

**增加以下测量点。**

- 输入：事件时间、原始位移、累计位移、消费位移。验证事件合并前后位移守恒。
- 调度：DisplayLink 相邻回调间隔、预期显示时间、实际执行时间。分别统计跟手和吸附阶段。
- 工作量：每帧主线程耗时、根视图与图标视图更新次数、扫描耗时、图标缓存未命中次数。

**建议验收目标。**

在确认系统允许 120Hz、持续运动且缓存已热的条件下：

- 呈现间隔主要集中在约 **8.33ms**，不长期停留在 **16.67ms**。持续运动区间有效更新率目标 **≥115fps**。
- 应用侧逐帧主线程工作耗时 **P95＜4ms**。超过两个刷新周期的更新间隔占比 **＜1%**。
- 普通热态翻页期间没有同步全量扫描，没有图标加载造成的明显主线程停顿。
- 60/120/240Hz 的合成输入序列具有相同累计位移时，得到一致的移动距离和接近的翻页判定。

这些是验收目标，不是现有实测成绩。DisplayLink 回调计数不能代替呈现帧率；需要观察跟手延迟时，可用 240fps 相机同时拍摄手指和屏幕，普通 60fps 录屏不足以验证 120Hz。

## 2. 手势唤醒与 Cmd+空格冲突

### 2.1 根因诊断

**① 唤醒直接读取触控板触点，没有模拟键盘操作。**

[FiveFingerPinchMonitor.swift:17](/Users/leo/本地/Project_Git/重要/LaunchpadPro/Sources/LaunchpadProCodex/FiveFingerPinchMonitor.swift:17) 通过私有框架 `MultitouchSupport` 枚举设备、注册触点帧回调并启动监听。

识别器要求至少五个有效触点，检查收缩比例和中心漂移。识别成功后，将动作派发到主线程，见 [FiveFingerPinchMonitor.swift:279](/Users/leo/本地/Project_Git/重要/LaunchpadPro/Sources/LaunchpadProCodex/FiveFingerPinchMonitor.swift:279)。最终直接调用 `overlay.show()`，见 [AppDelegate.swift:172](/Users/leo/本地/Project_Git/重要/LaunchpadPro/Sources/LaunchpadProCodex/AppDelegate.swift:172)。

源码没有 `CGEvent` 按键注入、修饰键模拟或全局键盘事件监听。窗口显示后的本地 `NSEvent` 监听只处理滚动和 Escape，不是唤醒来源。

**② 自定义手势和系统应用搜索可能同时识别同一动作。**

[FiveFingerPinchMonitor.swift:68](/Users/leo/本地/Project_Git/重要/LaunchpadPro/Sources/LaunchpadProCodex/FiveFingerPinchMonitor.swift:68) 的原始触点回调是观察性的，不能可靠阻断系统手势。Apple 的 macOS 26 文档确认，四指或五指捏合可打开 Spotlight 的应用界面。[Apple：Magic Trackpad 手势](https://support.apple.com/en-is/guide/imac/apdea23385dd/mac)

项目已有抑制措施：将 `com.apple.dock showLaunchpadGestureEnabled` 写为 0，发生变化时重启 Dock，见 [FiveFingerPinchMonitor.swift:443](/Users/leo/本地/Project_Git/重要/LaunchpadPro/Sources/LaunchpadProCodex/FiveFingerPinchMonitor.swift:443)。

本机只读检查得到：

- Dock 覆盖键当前为 **0**，应用记录的覆盖状态为 **启用**。
- 内置和蓝牙触控板的四指、五指设置值均为 **2**。
- 系统 Cmd+空格快捷键仍启用。

因此，“忘记关闭系统捏合手势”不符合当前配置。更需要验证的是：**这个未公开配置键在 macOS 27.0.1 上是否仍能控制系统响应，以及 Dock 是否已经采用它。** 源码中的兼容性注释针对 macOS 26，不能直接当作 macOS 27 的事实。

可能的触发路径是：

```text
一次捏合
  ├─ LaunchpadPro 识别成功 → show() → 激活窗口
  └─ 系统仍识别该动作     → Spotlight 应用界面出现
```

是否实际走了第二条路径，需通过复现确认。

**③ 启动器的窗口层级和失焦行为，会放大冲突。**

[OverlayController.swift:83](/Users/leo/本地/Project_Git/重要/LaunchpadPro/Sources/LaunchpadProCodex/OverlayController.swift:83) 把面板放到 `.maximumWindow` 层级，并设置 `hidesOnDeactivate = false`。源码没有失去 key window 或应用激活状态后的关闭逻辑。

用户在启动器中按 Cmd+空格时，Spotlight 可能已取得键盘焦点，但启动器仍留在上层。视觉焦点和键盘焦点因此可能不一致，表现为遮挡、输入跑到另一处或来回抢焦点。

这里可以确认窗口策略存在问题，但 Spotlight 在当前系统上的具体层级和通知顺序仍需实测。

**④ 重复显示和异步动作缺少时序保护。**

每次手势成功都重新 `show()`，即使窗口已经显示，也会扫描应用、清空搜索、重置页面并再次激活。

同时，[OverlayController.swift:62](/Users/leo/本地/Project_Git/重要/LaunchpadPro/Sources/LaunchpadProCodex/OverlayController.swift:62) 的隐藏动画结束后无条件执行 `orderOut`。若期间又发生显示，旧隐藏回调仍可能关掉新显示的窗口。

这些问题可造成焦点回抢和闪烁，应与系统手势冲突一起处理。

**⑤ 外接触控板存在共享识别状态的问题。**

触点回调丢弃了设备参数，所有设备共用一个识别器。某个设备的零触点帧会重置整体识别状态，见前述回调和 [FiveFingerPinchMonitor.swift:158](/Users/leo/本地/Project_Git/重要/LaunchpadPro/Sources/LaunchpadProCodex/FiveFingerPinchMonitor.swift:158)。

内置与外接触控板同时产生事件时，可能互相打断识别，或使一次动作重新获得触发资格。这是额外的重复唤醒风险，不是模拟 Cmd+空格的证据。

**⑥ 快捷键注册也缺少冲突反馈。**

[AppDelegate.swift:159](/Users/leo/本地/Project_Git/重要/LaunchpadPro/Sources/LaunchpadProCodex/AppDelegate.swift:159) 没有 Cmd+空格预设，默认是 Option+空格。因此当前问题不能直接归因于注册了相同快捷键。

但 [HotKey.swift:26](/Users/leo/本地/Project_Git/重要/LaunchpadPro/Sources/LaunchpadProCodex/HotKey.swift:26) 忽略了事件处理器安装和快捷键注册的返回状态。本机另一个已启用的系统快捷键绑定 Cmd+Option+空格，与应用提供的一个预设重叠。选择该预设时，应明确报告冲突。

### 2.2 推荐方案：先修焦点交接，再验证系统手势接管

**A. 修复窗口生命周期，保留系统 Cmd+空格。**

将面板从最高层级降至满足启动器需求的最低层级，先从 `.floating` 验证普通桌面与全屏 Space。

监听窗口失去 key 状态和应用失活。当焦点转交给外部界面时关闭启动器，并停止运动。对应用自己的设置窗口、菜单和模态对话框区分处理，避免误关。

不能只依赖本地监听 Cmd+空格，系统快捷键可能在本地事件监视器收到之前就被处理。

**B. 让显示、隐藏和手势动作有明确顺序。**

增加 `hidden / showing / visible / hiding` 状态和操作版本号。旧动画完成回调只能结束自己所属的操作。

同一屏幕已显示时，重复 `show()` 不再清空搜索或重置页面。跨屏唤醒单独移动窗口。

手势回调携带设备、动作序号和识别时间。焦点交接后丢弃此前尚未执行的旧动作，新发生的明确捏合仍允许唤醒。移除同步扫描后，也能减少回调排队造成的焦点回抢。

**C. 将系统手势覆盖改成可验证的兼容性模块。**

保留现有 Dock 键方案，但先验证 macOS 27.0.1 的实际效果。成功写入配置只代表保存成功，不能代表系统已经停止响应手势。

检查偏好同步结果、Dock 重启结果和重新读取的值。启用、修复、关闭、恢复全部串行执行，避免后台修复与用户关闭交错。

旧版本迁移只恢复确实有迁移记录的键。当前 [FiveFingerPinchMonitor.swift:486](/Users/leo/本地/Project_Git/重要/LaunchpadPro/Sources/LaunchpadProCodex/FiveFingerPinchMonitor.swift:486) 会把读到的 0 恢复为保存值或默认值，即使用户本来就希望该功能关闭，也可能被改回去。

恢复时应保留“原值不存在”的状态，并只恢复仍由本应用持有的改动。正常退出释放接管，异常退出后保留恢复信息，供下次启动处理。

**D. 按设备维护识别器，并报告快捷键注册失败。**

内置、外接触控板分别保存识别状态。零触点帧只重置对应设备。热插拔时用设备注册版本号排除旧回调，再由应用层合并重复唤醒。

快捷键注册检查 `OSStatus`，设置页显示是否注册成功。不要把失败的注册显示为可用。

### 2.3 兼容性失败时的退路

如果实测证明 macOS 27 已不再接受现有 Dock 配置键，先确认当前系统是否提供独立关闭应用搜索手势的公开设置。

若没有可靠方式，应把五指接管标为当前系统不兼容，保留现有 Option+空格或触发角入口。不要通过禁用 Cmd+空格、反复关闭 Spotlight、伪造 Escape 或提高窗口层级来掩盖冲突。

### 2.4 改动范围与风险

主要涉及面板显示状态、焦点监听、手势设备管理、系统偏好恢复和快捷键状态展示。

风险集中在系统私有接口随版本变化、全屏 Space 中的窗口行为，以及菜单和模态对话框引起的短暂失焦。异常退出无法保证立即恢复系统偏好，这个限制应明确保留。

### 2.5 如何验证

先在现有版本记录事件顺序，再与修改版使用同一流程对比：

1. 仅五指捏合，不碰键盘。确认是否也出现系统 Spotlight 应用界面。
2. 启动器显示后按 Cmd+空格。确认 Spotlight 能正常输入，启动器退出且不回抢。
3. Spotlight 显示时再捏合。确认新动作只唤醒一次启动器。
4. 快速执行显示、隐藏、再次显示。确认旧动画不会关闭新窗口。
5. 分别使用内置、外接及两者交替操作，再覆盖蓝牙重连、睡眠唤醒和跨屏唤醒。

日志记录识别时间、设备、动作序号、显示来源、窗口可见状态、key 状态和应用激活变化。

每种主要场景连续执行 **50 次**，目标是无双重唤醒、无错误隐藏、无焦点回抢。补充关闭手势、正常退出和重新启动后的恢复验证，并确认系统展开显示桌面的手势仍可用。

## 3. 需要 Leo 实测确认的假设

1. **卡顿发生阶段。** 持续拖动、抬手吸附、首次打开后的第一次翻页，可能对应不同原因。当前没有证据证明三者都只有 60fps。
2. **冲突的具体形态。** 单独捏合就出现两个界面，支持系统手势接管失效；只有按 Cmd+空格后异常，更支持窗口层级和焦点交接问题。
3. **显示器与触控板条件。** 需要确认问题是否只发生在外接屏、外接触控板、混合刷新率或睡眠恢复之后。本次系统信息没有返回可用于确认实际显示刷新率的数据。
4. **已安装包与源码的一致性。** 两者版本号均为 1.2.3，但安装包没有提供可直接核对的提交号。性能对照应使用同一源码构建的修改前后 Release 版本。

## 4. 预计改动文件与工作量

**现有文件：**

- 翻页与视图：`OverlayController.swift`、`LauncherBus.swift`、`PagedLauncherView.swift`、`LauncherViews.swift`。
- 数据与图标：`LaunchModel.swift`、`AppScanner.swift`、`AppDirectoryWatcher.swift`。
- 手势与焦点：`AppDelegate.swift`、`FiveFingerPinchMonitor.swift`、`HotKey.swift`、`SettingsView.swift`。
- 工程与测试：`LaunchpadPro.xcodeproj/project.pbxproj`、现有 `FiveFingerPinchRecognizerTests.swift`。

**建议新增：**

- `PagingMotionState.swift`：位移累计、速度估计、边界阻尼和吸附。
- `SystemPinchGestureOverride.swift`：从手势监听文件中拆出系统接管与恢复逻辑。
- `PerformanceDiagnostics.swift`：可关闭的性能和唤醒时序记录。
- 对应测试：位移守恒与采样频率一致性、显示隐藏竞态、偏好恢复，以及多设备识别隔离。

**工作量估算：**

- 基线采样与冲突复现：**0.5–1 人日**。
- 翻页管线、扫描和图标优化：**2–3 人日**。
- 焦点、系统手势接管和设备隔离：**1.5–2 人日**。
- 自动化测试与内外屏、触控板回归：**1 人日**。

推荐方案合计约 **5–7 人日**。若性能采样证明仍需局部 AppKit/Core Animation 分页容器，另加 **2–3 人日**；macOS 27 私有手势机制若已变化，需要单独评估兼容性探索时间。