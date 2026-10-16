# Codex 施工记录

- 规格：`交付边界.md`。代码工作树 `LaunchpadPro-hybrid`，分支 `exp/hybrid`，起点 `cf82acc`，初始工作区干净。
- 当前停在 S0：实现与验证完成，Git 写入被拒绝，未提交。S1–S5 未开始。
- 未运行应用或打包脚本，未改系统设置，未 push。施工记录独立留在实验目录。

## S0：旧管线计量

- 新增纯值 `FrameStats` 与环境变量开关 `FrameMeter`。
- 已埋点：旧管线 scroll 事件、处理耗时、raw/applied dx、display link tick，以及 LauncherRootView/PagedLauncherView body。会话 mode 为 legacy。
- 关闭时入口立即返回，时钟读取受开关控制。旧平滑与翻页行为保留。
- Release 构建通过，10 个 XCTest 全过（原有 7 个，新增 FrameMeterTests 3 个）。源码无编译警告，只有构建器弃用提示。
- 新测试覆盖 tick 频率/分位数/hitch、事件延迟与累计、关闭不累计。
- 实际改动文件白名单、`git diff --check`、分支检查通过。暂存区为空，原因见停工记录。
- 新文件：`Sources/LaunchpadProCodex/FrameMeter.swift`、`Tests/LaunchpadProCodexTests/FrameMeterTests.swift`。按规格未加入 xcodeproj，合入 main 前另行处理。
- 修改文件：`OverlayController.swift`、`PagedLauncherView.swift`、`LauncherViews.swift`。
- commit：无。尝试的消息为 `S0: Instrument legacy paging frame metrics`，末段为 `Co-Authored-By: Codex`。

## 构建环境偏差

1. 默认模块缓存 `/Users/leo/.cache/clang/ModuleCache` 不可写。设置 `CLANG_MODULE_CACHE_PATH` 和 `SWIFTPM_MODULECACHE_OVERRIDE` 为工作树 `.build/module-cache`。
2. SwiftPM 嵌套沙箱报 `sandbox_apply: Operation not permitted`，使用 `--disable-sandbox`。外层 Codex 文件权限仍有效。
3. Swift 6.4 默认 swiftbuild 在 GenerateDSYMFile 步骤报 `Operation not permitted`。改用 native 构建器后通过。未改 Package.swift 或 Xcode 工程。

实际通过的命令（两个缓存环境变量均指向 `$PWD/.build/module-cache`）：

```sh
swift build --disable-sandbox --build-system native -c release
swift test --disable-sandbox --build-system native
```

最终日志：工作树 `.build/s0-release.log`、`.build/s0-test.log`。Release 构建 7.12 秒，测试构建 11.44 秒，10 项测试零失败。

## 停工：S0 无法提交

- 条款：§7.5 要求每阶段一个 commit，判据满足后才可进入下一阶段。本次提交动作受环境权限阻断，按该阶段门禁与 §7.6 记录并停工。
- `git add` 与 `git commit` 均退出 128。原始错误：

```text
fatal: Unable to create '/Users/leo/本地/Project_Git/重要/LaunchpadPro/.git/worktrees/LaunchpadPro-hybrid/index.lock': Operation not permitted
```

- 环境声明主仓库 `.git` 为可写根，但实际执行仍拒绝该元数据目录写入。当前会话不允许权限升级。未改用替代索引、仓库副本或其他绕行方式。
- 当前 HEAD 仍为 `cf82acc`，所有 S0 代码保留在工作区，未暂存。没有创建任何 commit。
- 方案一：在允许写入上述 Git 元数据目录的会话恢复。代价是调整执行权限并重跑 S0 判据，之后正常提交和继续 S1–S5。
- 方案二：Leo 在正常终端核对并提交本阶段。当前会话的后续提交仍会受相同限制，不能据此完成剩余阶段。

## 未满足项

- S0 commit 未完成，S1–S5 未实施。
- §2.4 逐条实现核验、§5 的 18 项回归走查、S1–S4 新增测试尚未执行。
- 120Hz 实机基线及 A1–A7 性能验收未测。按规格禁止自动启动应用，后续由 Leo 实测。

## S1：纯物理层（2026-10-16，本次最新状态）

- 开工核对：分支 `exp/hybrid`，HEAD 为 `9a6ac36`（`S0: add FrameMeter instrumentation`），工作区干净。前文 S0 未提交的状态已被 Claude 的提交取代。
- 本次消息中的阶段编号显示为乱码。依据只有 S0 已提交，按下一阶段 S1 施工，已发出范围澄清，未收到更正。S2–S5 未开始。
- 已实现 `PagerTuning`、`RubberBand`、`VelocityEstimator`、`PageDecision`、`SnapSpring`、`PagerMachine`。源码只导入 Foundation/CoreGraphics，未接入现有管线，已有受版本控制文件均未修改。
- 实现顺序：纯物理类型和状态机 → 指定用例与边界用例 → 全量测试 → Release 构建 → 文件白名单、分支和空白检查。首轮测试、构建均通过。

新增文件（均未加入 xcodeproj，合入 main 前另行处理）：

- `Sources/LaunchpadProCodex/PagerPhysics.swift`
- `Tests/LaunchpadProCodexTests/PagerPhysicsTests.swift`
- `Tests/LaunchpadProCodexTests/PagerMachineTests.swift`

S1 判据核验：

- 位移：500 个含正负的确定性随机 dx，包含 began/ended 的位移，逐事件核对累计和显示位置，误差小于 `1e-6`。横向锁轴补回 4pt，竖向锁定后忽略整个手势。
- 测速：60/90/120/125/240Hz，各 20 个随机种子，真实恒速 1000pt/s、时间戳 ±1ms 抖动，分别满足 8%/5% 误差。停 60ms 速度归零，反向 40ms 后小于 −1000pt/s。另测不足 8ms、稀疏采样、同时间戳及旧时间戳。
- 判定：规格中的 8 行全部覆盖，另测负方向、反向否决临界值、4pt/300pt/s 临界值。
- 阻尼：96pt/450pt 两个 L，覆盖 `[0,5L]` 的单调性、上限、反函数与导数。
- 弹簧：初始位置/速度正确，零初速单调无过冲。整页距离 W=1512，双方向、v0 从 −6000 到 6000 每 250pt/s 采样，逐毫秒验证过冲不超过 0.04W，0.7s 时满足位置与速度收敛阈值。
- 状态机：连续两次快滑翻两页、mayBegin 冻结、caught 后 ended/cancelled 吸最近页、取消回起点、加锁回弹且仍允许程序翻页、configure 缩页夹紧并保留弹簧速度、jump 立即到位。另测边界释放速度乘阻尼导数、边界打断反函数连续性、direct tick 不位移、predict 只改显示且不累入 raw。
- 通用判据：Release 构建成功，37 个 XCTest 全过（S1 新增 27 个，原有 10 个）。源码无编译警告。实际改动文件白名单检查无违规输出，`git diff --check` 通过，新文件另行检查行末空白，分支为 `exp/hybrid`，暂存区为空。

构建命令沿用 S0 已验证的环境适配，两个缓存变量均指向工作树 `.build/module-cache`：

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" swift test --disable-sandbox --build-system native
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" swift build --disable-sandbox --build-system native -c release
```

- 日志：工作树 `.build/s1-test.log`、`.build/s1-release.log`。测试构建 2.02 秒，Release 构建 5.53 秒。
- 环境偏差：继续使用 native 构建器及关闭 SwiftPM 内层沙箱。只有 `--build-system native` 弃用提示，无新增源码编译警告，未改构建配置。
- 接口细化：`tick(targetTime:)` 增加可选 `frameDuration` 参数（默认 1/120 秒），供后续适配层传入真实帧长，限制 predict 外推最多一帧。属于 §2.2 允许的签名微调。
- 提交：按本次指令交由 Claude 负责，未执行 `git add` 或 `git commit`，HEAD 保持 `9a6ac36`。三个新文件留在工作区待验收。
- 未满足项：S1 自动完成判据无缺项。120Hz 实机与 A1–A7 性能未测，未启动应用或运行打包脚本。S1 完成后停止。


## S2：AppKit 条带接管翻页（2026-10-16，本次最新状态）

- 开工状态：工作树 `LaunchpadPro-hybrid`，分支 `exp/hybrid`，HEAD `b0a5225`（S1），工作区干净。S0 为 `9a6ac36`，S1 已由 Claude 提交，前文未提交状态已过时。
- 本次阶段编号仍显示为乱码。依据 S0、S1 已提交，按下一阶段 S2 施工，已发送范围澄清，未收到更正。只完成 S2，未实施 S3–S5。
- 接线顺序：容器与 pager → 外层视图、拖拽坐标、旧总线替换 → 容器及控制器测试 → Release 构建、计量测试、边界与回归走查。
- 高频位移现在只写 AppKit `bounds.origin`。触控板同步写位置，吸附使用 S1 弹簧和容器 display link，页点独立观察低频目标页。S2 仍渲染全部页。
- 内层保留图标、右键菜单、空白点击和文件夹虚化。拖拽用 `page-strip` 坐标，经 pager 换回视口坐标，重排、合并、文件夹拖出算法保留。

### 改动文件

修改（均在 `Sources/LaunchpadProCodex/`）：

- `OverlayController.swift`：持有及透传 pager，分流滚动，show/reset、hide/stop，保留滚轮累计与 0.3 秒节流。
- `LauncherBus.swift`：只保留 resetTick、targetScreenTopSafeArea 和 reset。
- `LauncherViews.swift`：只在 LauncherRootView、LauncherBody 透传 pager。
- `PagedLauncherView.swift`：构造条带、页点，删除旧翻页状态和条目几何 preference，接入 configure/锁定和坐标换算。
- `FrameMeter.swift`：移除 legacy 位置入口，改由 pager 提供显示位置与会话生命周期。

新增（未加入 xcodeproj，合入 main 前另行处理）：

- `Sources/LaunchpadProCodex/PagerController.swift`
- `Sources/LaunchpadProCodex/PageStripView.swift`
- `Tests/LaunchpadProCodexTests/PageStripViewTests.swift`

工作树外只追加本施工记录。

### 验证与过程偏差

- 最终 Release 构建通过（4.99 秒），44 项 XCTest 全过（原有 37 项，S2 新增 7 项）。最终源码无编译警告。
- 新测试覆盖：第二页子视图命中、父视图偏移、翻转及非翻转父坐标、视口外拒绝、文件夹禁用命中、顶部/页点排除区、点/矩形坐标换算、同步位移与锁轴补偿、跟手不发布页状态、收敛发布 restingPage、configure 夹紧、锁定与程序翻页、reset/stop/attach/detach、NSEvent phase 映射和 momentum 丢弃。
- 分别启用 FrameMeter 的 direct/predict 定向测试通过。合成手势包含 23 个事件，两种模式均 `sum_raw = sum_applied = -101`，ended 后会话仍在，吸附收敛后关闭。合成时钟日志不能作为实机 hz/latency 验收结果。
- 首轮 43 项测试通过。补充 NSEvent 测试时，`CGMomentumScrollPhase.continue` 在本 SDK 无此 Swift 成员，产生一次编译失败。改用有效的 `.begin` 构造非空 momentum 后，最终 44 项测试通过。
- 最终走查移除了 flipPage 中多余的 configure 调用，使配置更新只来自 onAppear/onChange。复跑完整测试与 Release 构建均通过。
- 沿用 S0/S1 的环境适配：模块缓存放在工作树 `.build/module-cache`，`--disable-sandbox --build-system native`。仅有 native 构建器弃用提示，未改 Package.swift 或构建配置。
- `git diff --check`、实际改动文件白名单、所有新文件行末空白检查通过。白名单违规输出为空，暂存区为空，分支仍为 `exp/hybrid`。
- S2 指定的 10 个红线关键词在 Sources 中均无命中。PageStripView.swift 无 compositingGroup/drawingGroup。
- 对照 HEAD 验证：LauncherViews.swift 从 SearchBar 起全部字节一致。PagedLauncherView 的 Folder Layer 仅改变 sourceFrame 的备用坐标来源，其余视觉、动画与文件夹内部逻辑字节一致。

最终命令（两个缓存变量均为 `$PWD/.build/module-cache`）：

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" swift test --disable-sandbox --build-system native
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" swift build --disable-sandbox --build-system native -c release
```

日志位于 hybrid 工作树：`.build/s2-test.log`、`.build/s2-release.log`、`.build/s2-meter-direct.log`、`.build/s2-meter-predict.log`。计量测试使用 `--skip-build --filter PageStripViewTests/testDirectEventsWriteImmediatelyWithoutPublishingPageState`，分别设置 `LAUNCHPADPRO_FRAMEMETER=1` 及同时设置 `LAUNCHPADPRO_SWIPE_PREDICT=1`。

### S2 架构硬规则核对

以下位置均相对 `Sources/LaunchpadProCodex/`：

- 唯一几何写入口：PageStripView.swift:34。关闭 CA 隐式动作后 setBoundsOrigin，无网格 transform 或 CAAnimation。
- 容器翻转、裁剪、layer-backed、不绘制：PageStripView.swift:11。hosting 的 sizingOptions/safeAreaRegions 清空：PageStripView.swift:25。hosting 不抢第一响应者：PageStripView.swift:54。内层 ignoresSafeArea：PageStripView.swift:143。
- hitTest 先转视口坐标，再检查禁用与排除区：PageStripView.swift:42。排除区由 PagedLauncherView.swift:107 提供。
- 内层绝对位置不依赖当前页：PagedLauncherView.swift:94。全页条带、空白点击、虚化链及稳定拖拽手势：PageStripView.swift:114。
- PagerState 仅 targetPage/restingPage，且只在不同值时赋值：PagerController.swift:5、144。PagerController 本身不可观察，machine 为私有字段。
- PagedLauncherView.body 不读取 targetPage/restingPage 或高频量。仅 PageDotsView.body 读取 targetPage：PageStripView.swift:159。clampedPage 只供回调路径：PagedLauncherView.swift:80。
- configure 和锁定由 onAppear/onChange 更新：PagedLauncherView.swift:164、184、203。锁定不拦程序翻页：PagerController.swift:24、93。
- step/reset/stop 与 attach/detach：PagerController.swift:39、103。updateNSView 只更新条带尺寸、命中参数、rootView：PageStripView.swift:78。
- display link 使用容器、弱代理、80–120/preferred 120，needsFrames=false 后 invalidate：PagerController.swift:155、187。direct 跟手 tick 不写位置：PagerController.swift:173。
- 坐标换算统一出口：PagerController.swift:116。拖拽回调转换：PagedLauncherView.swift:123。文件夹原点在 presentFolder 回调采样：PagedLauncherView.swift:305、370。folderLayer 的备用原点使用静态视口矩形，body 不读取 pager 高频坐标。
- FrameMeter 会话在 began 开始，ended 后继续计量吸附，在发布 restingPage 前结束：PagerController.swift:65、149、173。

### §5 回归路径走查（代码核对，尚非实机验收）

1. 慢拖阈值、回弹、方向：已核对路径 `PagerPhysics.swift:108`、`PagerController.swift:65`，沿用 S1 判定测试。
2. 小距离快甩、一次最多一页：已核对路径 `PagerPhysics.swift:108`，S1 判定表测试通过。
3. 反向否决、连续快滑继承目标：已核对路径 `PagerPhysics.swift:108`、`PagerPhysics.swift:251`，S1 状态机测试通过。
4. mayBegin 抓停、直接抬手吸最近页：已核对路径 `PagerPhysics.swift:251`、`PagerController.swift:128`，S1 状态机测试通过。
5. 边界阻尼、回弹、打断连续性：已核对路径 `PagerPhysics.swift:380`，S1 阻尼及打断测试通过。
6. 松手速度连续：已核对路径 `PagerPhysics.swift:277`、`PagerController.swift:173`，S1 弹簧测试通过。
7. 跨页拖拽、预览空页、重排/合并及持久化：已核对路径 `PagedLauncherView.swift:123`、`PagedLauncherView.swift:228`、`PagedLauncherView.swift:259`、`PagedLauncherView.swift:388`，浮层仍为视口坐标。
8. 文件夹原点、收回、虚化、拖出与命名：已核对路径 `PagedLauncherView.swift:305`、`PagedLauncherView.swift:370`、`PagedLauncherView.swift:657`、`PagedLauncherView.swift:896`、`PageStripView.swift:138`，视觉一致性待实机。
9. 搜索切换、清空回第一页、拖后搜索焦点：已核对路径 `LauncherViews.swift:105`、`PageStripView.swift:54`、`PageStripView.swift:89`、`PagerController.swift:39`，实际输入焦点待实机。
10. 启动关闭、第二页右键、重命名输入保存：已核对路径 `LauncherViews.swift:44`、`LauncherViews.swift:609`、`LauncherViews.swift:631`、`PageStripView.swift:42`，右键与输入待实机。
11. Escape 先关文件夹再关启动器：已核对路径 `OverlayController.swift:147`，原路径保留。
12. app/行列变化、页数夹紧：已核对路径 `PagedLauncherView.swift:170`、`PagedLauncherView.swift:184`、`PagerController.swift:52`，新增 configure 测试通过。
13. 页点、滚轮 0.3 秒节流：已核对路径 `PageStripView.swift:159`、`OverlayController.swift:178`。
14. 空白关闭、搜索/菜单穿透：已核对路径 `PageStripView.swift:117`、`PageStripView.swift:42`、`PagedLauncherView.swift:107`，排除区测试通过。
15. 隐藏再开回第一页、屏幕尺寸：已核对路径 `OverlayController.swift:33`、`OverlayController.swift:60`、`PagedLauncherView.swift:184`，reset/stop 测试通过，外屏待实机。
16. 后台扫描及打开耗时：已核对路径 `OverlayController.swift:36`、`LaunchModel.swift:26`，当前仍同步扫描，按阶段边界留给 S4。
17. 竖向模式：已核对路径 `LauncherViews.swift:105`、`OverlayController.swift:179`，VerticalLauncherGrid 及搜索网格未改。
18. 打开淡入：已核对路径 `OverlayController.swift:47`（面板 alpha 动画覆盖内层网格）、`LauncherViews.swift:51`，网格视觉与外层缩放效果待实机。

### 停止与未满足项

- S2 自动完成判据无缺项，完成后停止。未运行 LaunchpadPro 应用、打包脚本或修改系统设置。
- 未执行 git add/commit，HEAD 保持 `b0a5225`。按本次明确指令交 Claude 验收提交，不作为交付边界违例。
- 待 Leo 实测 §6.2 的 A1–A7，以及 §6.4 的跟手、文件夹视觉、搜索/重命名焦点、外接屏和可选 VoiceOver。未宣称达到实机 120Hz 门槛。
- S3 的窗口化/Equatable、S4 的后台扫描/show_ms 接线、S5 收尾均未实施。

## S3：相邻页渲染与条目判等（2026-10-16，本次最新状态）

- 开工状态：分支 `exp/hybrid`，HEAD `b2be2fd`（S2），工作区干净。S0 `9a6ac36`、S1 `b0a5225`、S2 均已提交，前文未提交状态已过时。
- 用户消息中的阶段编号显示为乱码。依据已提交到 S2，发送范围澄清并等待后，未收到更正，按下一阶段 S3 施工。只做 S3。
- 窗口按 `restingPage ± 2` 筛选，原页或 activePages 预览页在窗口内即保留，拖拽条目始终保留。保留原条目 ID、原始坐标和条带全宽。
- 连续翻页的目标距已发布 restingPage 达到两页时，提前移动窗口。吸附、抓停或后续跟手期间保留此窗口，避免下一帧回退到物理层旧 restingPage。收敛后与物理层同步，缩页时夹紧。
- LauncherEntryView 只比较 entry、cell、isDragging、isFolderTarget。PageStripContent 在拖拽修饰符之前应用 `.equatable()`。
- 验证进行中。未执行 git add/commit，提交交 Claude 负责。

### S3 验证结果与文件清单

- 首轮完整测试通过：49 项 XCTest，0 失败。新增 5 项均在 `Tests/LaunchpadProCodexTests/PageStripViewTests.swift`，覆盖窗口两侧边界、空集合、原页与预览页并集、拖拽跨窗口保留、双方向连续快滑、提前移窗后的抓停/取消/收敛、反向单页翻动、程序跳页及缩页夹紧。
- Release 构建通过，5.24 秒。测试构建 3.27 秒。改动源码无编译警告，仅有 `--build-system native` 弃用提示。
- 沿用 S0–S2 已验证的构建环境适配：模块缓存位于 `.build/module-cache`，关闭 SwiftPM 内层沙箱，使用 native 构建器。未改构建配置。
- 实际改动文件白名单无违规输出，`git diff --check` 通过，S2 红线关键词无命中，PageStripView.swift 不含 compositingGroup/drawingGroup。分支仍为 `exp/hybrid`，暂存区为空。
- 规格实现无偏差。阶段编号乱码及构建环境适配已如上记录。没有新增文件，无本阶段新增待加入 xcodeproj 的文件。

修改文件：

- `Sources/LaunchpadProCodex/PageStripView.swift`：纯函数 PageStripWindow 与 `.equatable()`。
- `Sources/LaunchpadProCodex/PagedLauncherView.swift`：按 restingPage 构造窗口条目及其位置。
- `Sources/LaunchpadProCodex/PagerController.swift`：提前发布窗口中心并保持到收敛。
- `Sources/LaunchpadProCodex/LauncherViews.swift`：仅 LauncherEntryView 的 Equatable 声明及比较函数。
- `Tests/LaunchpadProCodexTests/PageStripViewTests.swift`：新增 5 项测试。
- 工作树外仅追加本施工记录。

完成命令（在 hybrid 工作树执行）：

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" swift test --disable-sandbox --build-system native
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" swift build --disable-sandbox --build-system native -c release
```

日志：`.build/s3-test.log`、`.build/s3-release.log`。

### S3 完成判据走查

以下源码位置均相对 `Sources/LaunchpadProCodex/`：

- 窗口成员：已核对路径 `PageStripView.swift:5`、`PagedLauncherView.swift:95`。原页或 activePages 位置进入闭区间即保留，拖拽条目无条件保留，筛选不改变原 ID/page/index 或顺序。
- 状态隔离：已核对路径 `PagedLauncherView.swift:98`、`PageStripView.swift:180`、`PagerController.swift:144`。Paged body 只读取 restingPage，targetPage 仅页点和回调读取。提前移窗比较已发布的 restingPage，不随每帧旧物理 restingPage 回退，只有值不同才发布。
- 条目判等：已核对路径 `LauncherViews.swift:527`、`PageStripView.swift:146`。只比较规格中的四个字段，忽略 model/闭包，手势修饰符仍在 Equatable 外层。
- 几何与拖拽身份：已核对路径 `PageStripView.swift:109`、`PagedLauncherView.swift:102`、`PagedLauncherView.swift:406`。条带保持全宽，位置仍用 selectedPage=0，拖拽条目保留原始位置，预览条目使用 activePages 位置。
- 限定修改范围：与 HEAD 逐字比较，LauncherViews 的 LauncherEntryView 以外全部一致，PagedLauncherView 的 Folder Layer 全部一致。

### §5 回归路径复核（代码走查，非实机验收）

1. 慢拖阈值、回弹与方向：已核对路径 `PagerPhysics.swift:108`、`PagerController.swift:65`，物理层未改，原测试通过。
2. 小距离快甩、单次最多一页：已核对路径 `PagerPhysics.swift:108`、`PagerPhysics.swift:277`，原测试通过。
3. 反向快滑与连续两次快滑：已核对路径 `PagerPhysics.swift:251`、`PagerController.swift:144`，新增双方向控制器测试验证移窗不回退。
4. 吸附抓停与就近吸附：已核对路径 `PagerPhysics.swift:251`、`PagerPhysics.swift:369`，物理层未改，原测试通过。
5. 边界阻尼：已核对路径 `PagerPhysics.swift:380`，原阻尼与打断连续性测试通过。
6. 松手速度连续：已核对路径 `PagerPhysics.swift:277`、`PagerController.swift:182`，窗口发布不修改几何与速度。
7. 跨页拖图标：已核对路径 `PageStripView.swift:14`、`PagedLauncherView.swift:128`、`PagedLauncherView.swift:233`、`PagedLauncherView.swift:264`、`PagedLauncherView.swift:393`。新增测试验证跨窗口拖拽条目始终存在，预览迁入条目可见。
8. 文件夹原点、虚化、拖出与改名：已核对路径 `PagedLauncherView.swift:375`、`PagedLauncherView.swift:662`、`PagedLauncherView.swift:816`、`PagedLauncherView.swift:901`、`PageStripView.swift:155`，相关视觉与逻辑未改。
9. 搜索与焦点：已核对路径 `LauncherViews.swift:105`、`PageStripView.swift:70`、`PagerController.swift:39`，搜索分支与 hosting 不抢焦点规则保留。
10. 点击启动、右键菜单与重命名：已核对路径 `LauncherViews.swift:44`、`LauncherViews.swift:594`、`LauncherViews.swift:608`、`PageStripView.swift:58`。AppIconView 未改，Equatable 比较不包裹拖拽回调。
11. Escape：已核对路径 `OverlayController.swift:158`，先关闭文件夹再关闭启动器的路径未改。
12. 页数增减与改行列：已核对路径 `PagedLauncherView.swift:175`、`PagedLauncherView.swift:189`、`PagerController.swift:52`、`PagerController.swift:144`，新增缩页测试通过。
13. 页点与滚轮：已核对路径 `PageStripView.swift:183`、`OverlayController.swift:194`，程序跳页纳入窗口更新，0.3 秒节流未改。
14. 空白关闭与搜索/设置命中：已核对路径 `PageStripView.swift:58`、`PageStripView.swift:135`、`PagedLauncherView.swift:112`，全条带空白层及命中排除区保留。
15. 重新打开与屏幕尺寸：已核对路径 `OverlayController.swift:33`、`OverlayController.swift:60`、`PagedLauncherView.swift:189`，reset/stop/configure 测试通过。
16. 后台扫描与打开耗时：已核对路径 `OverlayController.swift:36`、`LaunchModel.swift:26`，仍为同步扫描，按边界留在 S4。
17. 竖向模式：已核对路径 `LauncherViews.swift:105`、`OverlayController.swift:179`，竖向及搜索网格代码逐字未改，仅分页条带使用 `.equatable()`。
18. 网格淡入：已核对路径 `OverlayController.swift:47`、`LauncherViews.swift:51`，淡入路径未改，视觉效果待实机。

### S3 停止与未满足项

- S3 全部自动完成判据满足，完成后停止。S4/S5 未开始。
- 本次未执行 git add/commit，HEAD 保持 `b2be2fd`，五个代码/测试文件留在工作区，由 Claude 验收提交。
- 未运行 LaunchpadPro 应用或打包脚本，未改系统设置。§6.2 A1–A7 与 §6.4 实机项目未测，仍需 Leo 验证，不能据此宣称达到 120Hz 性能门槛。

## S4：扫描移出主线程（2026-10-16，本次最新状态）

- 开工状态：分支 `exp/hybrid`，HEAD `9147175`（S3），工作区干净。S0 `9a6ac36`、S1 `b0a5225`、S2 `b2be2fd`、S3 均已提交。
- 用户消息中的阶段编号显示为乱码。依据已提交到 S3，发送范围澄清并等待后未收到更正，按下一阶段 S4 施工。只做 S4，S5 不开展。
- 已接入 `reloadAsync(force:)`：主线程递增 generation，`Task.detached(priority: .userInitiated)` 扫描，回 MainActor 校验 generation 与结果差异后应用。默认相等结果直接返回，不触发任何 Published 属性赋值。
- `init()` 保持同步 reload。同步 reload 同样递增 generation，防止设置页同步重扫后被在途旧扫描覆盖。应用步骤仍为 apps、appIndex、load、rebuildEntries、applySort，扫描规则与持久化格式未改。
- show 与 watcher 改为异步扫描，菜单重扫使用 force=true。show 的同步调用耗时接入已有 FrameMeter.noteShow/show_ms，关闭计量时不读取时钟。
- 沿用 S4 明确允许的测试范围：不改 LaunchModel 构造方式，只测生产代码调用的 generation/结果判定纯函数。现构造会同步扫描，并通过 layoutURL 访问真实布局目录，不为测试增加注入参数或触碰真实布局。
- 新增 `Tests/LaunchpadProCodexTests/LaunchModelReloadTests.swift`，覆盖扫描乱序完成、相等新结果仍淘汰旧结果、force 不越过 generation、新增/删除/元数据变化和空列表。
- 正在执行构建与测试。未执行 git add/commit，提交交 Claude 负责。

### S4 验证结果与改动文件

- 首轮完整测试通过：53 项 XCTest，0 失败，测试构建 2.77 秒。新增 LaunchModelReloadTests 4 项，原有 49 项全部通过。
- Release 构建通过，5.46 秒。改动源码无编译警告，仅有 `--build-system native` 弃用提示。
- 构建沿用 S0–S3 已验证的环境适配：模块缓存位于工作树 `.build/module-cache`，关闭 SwiftPM 内层沙箱，使用 native 构建器。未修改 Package.swift 或 Xcode 工程。
- 文件白名单检查包含已跟踪改动和未跟踪新文件，违规输出为空。暂存区白名单检查也为空，`git diff --check` 和新文件行末空白检查通过。分支仍为 `exp/hybrid`，暂存区为空，HEAD 仍为 `9147175`。
- S2 红线关键词无命中，PageStripView.swift 无 compositingGroup/drawingGroup。对照 HEAD 逐字确认：applyScan 的五个应用步骤与旧 reload 的扫描后逻辑完全一致，LaunchModel 从 app(for:) 起全部未改。
- 测试范围采用 S4 允许的纯函数方案，未构造 LaunchModel，未动态验证真实扫描线程或订阅发布次数。MainActor 返回路径、判定前无属性发布、同步 reload 淘汰旧请求均已走查。
- 无实现规格偏差。FrameMeter 在 S0 已具备 noteShow、毫秒换算及 show_ms 输出，本阶段只接入 show 的计时入口，无需修改 FrameMeter.swift。SettingsView 的重扫按钮仍同步调用 reload，属于明确禁止修改的设置界面范围。

修改文件：

- `Sources/LaunchpadProCodex/LaunchModel.swift`：异步扫描、generation 与差异判定，共用原应用步骤。
- `Sources/LaunchpadProCodex/OverlayController.swift`：show 异步重扫及同步部分计时。
- `Sources/LaunchpadProCodex/AppDelegate.swift`：watcher 异步重扫，菜单强制异步重扫。

新增文件：`Tests/LaunchpadProCodexTests/LaunchModelReloadTests.swift`。按边界未加入 xcodeproj，合入 main 前另行处理。工作树外只追加本施工记录。

最终命令（hybrid 工作树）：

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" swift test --disable-sandbox --build-system native
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" swift build --disable-sandbox --build-system native -c release
```

日志：`.build/s4-test.log`、`.build/s4-release.log`。

### S4 完成判据走查

以下源码位置均相对 `Sources/LaunchpadProCodex/`：

- 后台扫描与主线程应用：已核对路径 `LaunchModel.swift:5`、`:32`、`:36`、`:46`。外层 Task 继承 MainActor，detached 内只调用 AppScanner.scan，await 后返回 MainActor 应用结果。
- generation 及相等结果不发布：已核对路径 `LaunchModel.swift:19`、`:28`、`:33`、`:39`、`:50`。请求发起时递增，同步请求也使旧结果过期，force 只绕过结果相等检查。
- 保留构造与应用语义：已核对路径 `LaunchModel.swift:23`、`:60`。init 同步 reload，应用顺序和扫描规则未变。
- 三个入口：已核对路径 `OverlayController.swift:42`、`AppDelegate.swift:137`、`:142`。
- 拖拽守卫：已核对路径 `PagedLauncherView.swift:175`，保留 draggingID == nil，无额外拖拽处理。
- show_ms：已核对路径 `OverlayController.swift:33`、`FrameMeter.swift:114`、`:127`。defer 记录 show 返回前同步耗时，包含面板准备与安装 monitor，不包含后台扫描和动画完成时间，关闭时不读时钟。

### §5 回归路径复核（代码走查，非实机验收）

1. 慢拖阈值、回弹和方向：已核对路径 `PagerPhysics.swift:108`、`PagerController.swift:65`，未改，原测试通过。
2. 快甩与单次最多一页：已核对路径 `PagerPhysics.swift:108`、`:277`，未改，原测试通过。
3. 反向否决和连续翻页：已核对路径 `PagerPhysics.swift:251`、`PagerController.swift:144`，未改，原测试通过。
4. 抓停与就近吸附：已核对路径 `PagerPhysics.swift:251`、`:369`，未改，原测试通过。
5. 边界阻尼：已核对路径 `PagerPhysics.swift:380`，未改，原测试通过。
6. 松手继承速度：已核对路径 `PagerPhysics.swift:277`、`PagerController.swift:182`，未改，原测试通过。
7. 跨页拖拽：已核对路径 `PagedLauncherView.swift:175`、`:233`、`:264`、`:393`、`PageStripView.swift:14`。扫描结果到达时仍受 draggingID 守卫，重排、预览页、合并算法未改。
8. 文件夹：已核对路径 `PagedLauncherView.swift:375`、`:662`、`:816`、`:901`、`PageStripView.swift:155`，坐标、视觉和内部逻辑未改。
9. 搜索与焦点：已核对路径 `LauncherViews.swift:105`、`PageStripView.swift:70`、`PagerController.swift:39`、`OverlayController.swift:43`，搜索清空、回第一页及焦点路径保留。
10. 启动、右键与重命名：已核对路径 `LauncherViews.swift:44`、`:594`、`:608`、`PageStripView.swift:58`，未改。
11. Escape：已核对路径 `OverlayController.swift:164`，先关文件夹再关面板的路径未改。
12. 页数与行列：已核对路径 `LaunchModel.swift:60`、`PagedLauncherView.swift:175`、`:189`、`PagerController.swift:52`，最新扫描应用后仍走原显示条目更新与夹紧逻辑。
13. 页点与滚轮：已核对路径 `PageStripView.swift:183`、`OverlayController.swift:200`，0.3 秒节流未改。
14. 空白关闭和搜索/设置命中：已核对路径 `PageStripView.swift:58`、`:135`、`PagedLauncherView.swift:112`，未改。
15. 重开与屏幕尺寸：已核对路径 `OverlayController.swift:33`、`:66`、`PagedLauncherView.swift:189`，reset、stop 和屏幕 frame 设置保留。
16. 打开不卡顿与新 app 出现：已核对路径 `OverlayController.swift:42`、`AppDelegate.swift:142`、`LaunchModel.swift:32`。扫描已移出 show 同步路径，最新结果稍后在主线程应用，实际 show_ms 待 Leo 实测。
17. 竖向模式：已核对路径 `LauncherViews.swift:105`、`OverlayController.swift:185`，网格和滚动分流未改。
18. 打开淡入：已核对路径 `OverlayController.swift:53`、`:60`、`LauncherViews.swift:51`，原面板 alpha 动画保留。

### S4 停止与未满足项

- S4 自动完成判据全部满足，完成后停止。S5 未开始。
- 未执行 git add/commit，三个源码文件和一个新测试文件留在工作区，交 Claude 验收提交。
- 未运行应用、打包脚本或修改系统设置。§6.2 A1–A7、show_ms ≤10ms 以及 §6.4 实机项目未测，仍需 Leo 验证。

## S5：收尾自检（2026-10-16，本次最新状态）

- 开工状态：分支 `exp/hybrid`，HEAD `3758ba1`（S4），工作区干净。用户消息的阶段编号显示为乱码，已发送澄清，等待期间继续只读核查。未收到更正，依据 S0–S4 均已提交，按下一阶段 S5 施工。
- 范围：清理无调用函数、无读取字段、固定传参及无用 import，逐条核对 §2.4 和 §5，汇总提交、新文件与实机待验项。未执行 git add/commit，提交由 Claude 负责，按用户指令不算边界违例。
- 已确认 `mergedPages` 在 Sources/Tests 只有定义，无调用。实际合并由 `finishDrag` → `commitMergeToModel` 完成。`FolderPanelMetrics.rows` 无读取，保留用于高度计算的局部 rows。`position` 唯一调用固定传 selectedPage=0，删除该冗余参数，底层 center 的 selectedPage 仍用于拖拽命中。FrameMeter 未使用 QuartzCore 符号。
- 开始清理并验证。源码位置和最终结果见下续记。

### S5 清理与验证结果

- 修改 `Sources/LaunchpadProCodex/PagedLauncherView.swift`：删除未调用的 `mergedPages`、未读取的 `FolderPanelMetrics.rows` 及其构造实参，删除 `position` 固定为 0 的 selectedPage 参数。局部 rows 仍参与高度计算，实际合并、排序、持久化和拖拽算法未改。
- 修改 `Sources/LaunchpadProCodex/FrameMeter.swift`：删除未使用的 QuartzCore import。本阶段没有新增源码或测试文件，工作树外仅追加本记录。
- `swift test`：53 项 XCTest 全过，0 失败，测试构建 3.49 秒。`swift build -c release`：通过，5.54 秒。源码无编译警告，仅 SwiftPM 的 `--build-system native` 弃用提示。
- 沿用前序构建环境适配：工作树内模块缓存、`--disable-sandbox --build-system native`，未改 Package.swift 或工程配置。日志为 `.build/s5-test.log`、`.build/s5-release.log`。
- 本阶段、暂存区、累计改动和未跟踪文件的白名单违规输出均为空，`git diff --check` 通过。S2 红线、条带 compositingGroup/drawingGroup 和图层变换位移检查均无命中。分支 `exp/hybrid`，HEAD `3758ba1`，暂存区为空。
- 对照 S4：四个受保护的文件夹视图函数，以及实际合并、重排、命中和 center 函数逐字一致。position 仅把原有实参 0 内联，folderPanelMetrics 仅删除无读取的构造实参，已做文本等价检查。
- 扩展到起点 `cf82acc` 的逐字检查首次报告 folderLayer 不同。差异仅为前序 S2 已提交的 sourceFrame 来源替换（当前 `PagedLauncherView.swift:642`），属于 §3 允许范围。排除此单项后，上述函数与起点一致，无新增行为偏差。
- 框架入口 `updateLayer`、`acceptsFirstResponder`、`dismantleNSView` 等虽没有普通调用点，仍由 AppKit/SwiftUI 使用，保留。此次清理不新增行为，沿用已有完整测试。

复现命令（hybrid 工作树）：

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" swift test --disable-sandbox --build-system native
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" swift build --disable-sandbox --build-system native -c release
```

### §2.4 硬规则逐条核对

以下源码位置均相对 `Sources/LaunchpadProCodex/`，以本次最终工作区为准。

- [x] 唯一可观察分页状态：`PagerState` 是 `@Observable @MainActor final class`，仅含 targetPage/restingPage。两者只在值变化时发布，目标来自判定/命令/夹紧，静止页在收敛/jump 时同步，保留 S3 明确允许的连续翻页提前移窗例外。已核对路径：`PagerController.swift:5`、`PagerController.swift:144`、`PagerPhysics.swift:220`、`PagerPhysics.swift:277`、`PagerPhysics.swift:300`、`PagerPhysics.swift:321`、`PagerPhysics.swift:330`。
- [x] 高频量隔离：PagerController 本身不可观察，machine 私有，stripX/速度/手势没有 Published 标记。事件与帧直接写容器几何，视图不读取 machine。已核对路径：`PagerController.swift:11`、`PagerController.swift:65`、`PagerController.swift:182`、`PageStripView.swift:50`。
- [x] body 只读 restingPage：PagedLauncherView 求值时只用 restingPage 计算窗口。targetPage 在 PageDotsView 和 clampedPage 中读取，clampedPage 只由翻页、落点、重排和合并回调使用。Root/Body 只透传 pager。已核对路径：`PagedLauncherView.swift:79`、`PagedLauncherView.swift:91`、`PagedLauncherView.swift:392`、`PagedLauncherView.swift:440`、`PagedLauncherView.swift:449`、`PagedLauncherView.swift:479`、`PageStripView.swift:176`、`LauncherViews.swift:19`、`LauncherViews.swift:96`。
- [x] 配置无 body 副作用：configurePager/updatePagerLock 由 onAppear/onChange 回调触发，涵盖尺寸、页数、行列、数据、复位和锁定条件变化。已核对路径：`PagedLauncherView.swift:168`、`PagedLauncherView.swift:174`、`PagedLauncherView.swift:180`、`PagedLauncherView.swift:188`、`PagedLauncherView.swift:203`、`PagedLauncherView.swift:207`、`PagedLauncherView.swift:625`。
- [x] 锁定表达式完整：draggingID/presentedFolderID/openFolderID 任一存在即锁定。锁定忽略滚动，跟手时弹回 startPage，snap/step 等程序翻页仍可用。已核对路径：`PagedLauncherView.swift:190`、`PagedLauncherView.swift:207`、`PagerController.swift:24`、`PagerController.swift:65`、`PagerController.swift:93`、`PagerPhysics.swift:236`、`PagerPhysics.swift:251`。
- [x] 命令和几何更新：step 按 targetPage 加步长且速度 0，reset 跳 0，stop 跳目标并停 display link。updateNSView 仅更新条带尺寸、命中参数和内容，不写 stripX。页宽页数经 configure 更新。已核对路径：`PagerController.swift:52`、`PagerController.swift:93`、`PagerController.swift:103`、`PagerController.swift:113`、`PagerController.swift:164`、`PageStripView.swift:94`。
- [x] 生命周期：OverlayController 持有 pager，makeNSView attach 并跳 0，dismantleNSView detach。detach 先 stop 回 idle、停帧，再解除锁定及容器关联。未 attach 时配置、锁定、滚动、命令和帧输入均由 guard 忽略。已核对路径：`OverlayController.swift:17`、`PagerController.swift:24`、`PagerController.swift:39`、`PagerController.swift:45`、`PagerController.swift:52`、`PagerController.swift:65`、`PagerController.swift:93`、`PagerController.swift:107`、`PagerController.swift:182`、`PageStripView.swift:83`、`PageStripView.swift:105`。
- [x] display link：使用 container.displayLink 和弱代理，帧率范围 80/120/120，在 main/common 运行，needsFrames=false 时 invalidate。事件传 event.timestamp，弹簧 tick 使用 targetTimestamp，两者没有 Date/墙钟混算。direct 跟手 tick 不写位置。已核对路径：`PagerController.swift:58`、`PagerController.swift:164`、`PagerController.swift:177`、`PagerController.swift:182`、`PagerController.swift:196`、`PagerPhysics.swift:213`、`PagerPhysics.swift:300`。

### §5 功能回归走查

以下均为代码核对，不能替代 Leo 实机验收。原有测试本轮全部通过。

1. 慢拖阈值、回弹与方向。已核对路径：`PagerPhysics.swift:108`、`PagerPhysics.swift:277`、`PagerPhysics.swift:345`。
2. 小距离快甩、一次最多一页。已核对路径：`PagerPhysics.swift:108`、`PagerPhysics.swift:277`。
3. 反向否决、连续快滑继承目标并移窗。已核对路径：`PagerPhysics.swift:108`、`PagerPhysics.swift:262`、`PagerController.swift:144`。
4. mayBegin 抓停、直接抬手或取消后吸最近页。已核对路径：`PagerPhysics.swift:255`、`PagerPhysics.swift:286`、`PagerPhysics.swift:369`。
5. 首末页阻尼、回弹、打断连续性。已核对路径：`PagerPhysics.swift:27`、`PagerPhysics.swift:265`、`PagerPhysics.swift:283`、`PagerPhysics.swift:380`。
6. 松手速度继承及每帧弹簧位移。已核对路径：`PagerPhysics.swift:279`、`PagerPhysics.swift:300`、`PagerPhysics.swift:321`、`PagerController.swift:182`。
7. 跨页拖拽、空页预览、合并与持久化。已核对路径：`PageStripView.swift:14`、`PageStripView.swift:147`、`PagedLauncherView.swift:127`、`PagedLauncherView.swift:139`、`PagedLauncherView.swift:232`、`PagedLauncherView.swift:263`、`PagedLauncherView.swift:392`、`PagedLauncherView.swift:515`。条目身份保留，浮层和落点保持视口坐标。
8. 文件夹展开/收回原点、虚化、拖出与命名。已核对路径：`PagedLauncherView.swift:309`、`PagedLauncherView.swift:332`、`PagedLauncherView.swift:374`、`PagedLauncherView.swift:638`、`PagedLauncherView.swift:791`、`PagedLauncherView.swift:876`、`PageStripView.swift:155`。
9. 搜索切换、清空回第一页、拖后焦点。已核对路径：`LauncherViews.swift:74`、`LauncherViews.swift:105`、`PageStripView.swift:70`、`PagerController.swift:39`。实际输入焦点待实机。
10. 启动关闭、第二页右键、重命名输入保存。已核对路径：`LauncherViews.swift:45`、`LauncherViews.swift:594`、`LauncherViews.swift:608`、`LauncherViews.swift:626`、`PageStripView.swift:58`。菜单与输入待实机。
11. Escape 先关文件夹，再关启动器。已核对路径：`OverlayController.swift:164`。
12. 应用/行列变化后的分页与夹紧。已核对路径：`LaunchModel.swift:60`、`PagedLauncherView.swift:174`、`PagedLauncherView.swift:180`、`PagedLauncherView.swift:189`、`PagerController.swift:52`、`PagerPhysics.swift:220`。
13. 页点与鼠标滚轮，保留 0.3 秒节流。已核对路径：`PageStripView.swift:183`、`OverlayController.swift:184`、`OverlayController.swift:200`。
14. 空白关闭、搜索和设置菜单命中排除。已核对路径：`PageStripView.swift:58`、`PageStripView.swift:133`、`PagedLauncherView.swift:111`。
15. 重开回第一页、屏幕尺寸。已核对路径：`OverlayController.swift:33`、`OverlayController.swift:52`、`OverlayController.swift:66`、`PagedLauncherView.swift:182`、`PagedLauncherView.swift:188`、`PagerController.swift:113`。外接屏待实机。
16. 后台扫描及打开耗时。已核对路径：`LaunchModel.swift:32`、`LaunchModel.swift:50`、`OverlayController.swift:33`、`OverlayController.swift:42`、`AppDelegate.swift:137`、`AppDelegate.swift:142`、`FrameMeter.swift:113`。generation 与相等结果测试通过，真实 show_ms 待实机。
17. 竖向模式和搜索结果网格。已核对路径：`LauncherViews.swift:105`、`OverlayController.swift:185`。相关网格与事件分流本阶段未改。
18. 打开网格淡入。已核对路径：`OverlayController.swift:53`、`OverlayController.swift:60`、`LauncherViews.swift:51`。整面板 alpha 动画保留，视觉待实机。

### 提交与累计新文件

- 起点 `cf82acc`（1.2.3）。S0 `9a6ac36`，S1 `b0a5225`，S2 `b2be2fd`，S3 `9147175`，S4 `3758ba1`，已用 git log 核实。
- S5 未提交，按用户指令由 Claude 验收提交。建议消息：`S5: remove dead code and verify pager boundaries`。本轮没有执行 git add/commit。
- 累计新增源码：`Sources/LaunchpadProCodex/FrameMeter.swift`、`PagerPhysics.swift`、`PagerController.swift`、`PageStripView.swift`（后三者同目录）。
- 累计新增测试：`Tests/LaunchpadProCodexTests/FrameMeterTests.swift`、`PagerPhysicsTests.swift`、`PagerMachineTests.swift`、`PageStripViewTests.swift`、`LaunchModelReloadTests.swift`（后四者同目录）。
- 上述九个文件均未加入 xcodeproj，工程文件无改动，合入 main 前另行处理。本阶段新增文件为零。

### 未满足项与停止状态

- S5 清理、§2.4 八条硬规则核对、§5 十八条路径核对及通用自动判据全部完成，停止施工。无本阶段自动判据未满足项。
- §6.2 A1–A7 与 §6.4 尚未实机验证，不能据代码和测试宣称达到 120Hz 门槛。需 Leo 用内置 120Hz 屏、光标位于内置屏、bundle.sh 产物，第二次打开后左右各滑 10 次验收。
- 还需 Leo 验证跟手/反向快滑/吸附、predict A/B、外接触控板和 60Hz 屏、文件夹虚化与淡入、页点/文件夹覆盖和点击、搜索/重命名焦点，VoiceOver 第二页图标可选。按交付边界 §6.4 操作，实测前保存「布局记忆」，实验版与正式版共用布局。
- 本轮未运行应用、打包或发布脚本，未改系统设置，未写 .git。提交及工程纳入属于后续交接事项。

## 拖拽让位动画回归修复（2026-10-16）

- 开工：hybrid 分支 `exp/hybrid`，HEAD `772ecae`，工作区干净。按《修复-让位动画.md》施工，不执行 git add/commit，不启动应用或运行打包脚本。
- 根因代码核对：原版 `cf82acc` 的 updateDrag、finishDrag 两个提交分支均用 `flow`（response 0.24、dampingFraction 0.80）。当前仍有这些调用，但网格已迁入独立 NSHostingView，updateNSView 仅在外层 withTransaction 中替换 rootView，内层只有 folderProgress 的动画绑定。
- 改法：向 PageStripContent 传入完整 activePages 的条目 ID 顺序和 draggingID 作为布局签名，把 representable 收到的事务作为值传入，在内层 ForEach 上用 `.animation(_:value:)` 建立动画。沿用调用方原有 Animation，disablesAnimations 或无动画事务时不启用布局动画。draggingID 进入签名是为了覆盖预览顺序不变、松手解除原位锚定的落位情况。
- 动画只作用于条目集合。正在拖拽的网格占位与外层浮动图标的位置禁用动画，浮层的文件夹虚化修饰符仍在其外侧。未修改文件夹层内部、拖拽/合并算法、PagerController 或 LauncherViews.swift。
- 新增测试覆盖签名变化、文件夹元数据不触发位置动画、翻页渲染窗口与签名隔离，并用无窗口 NSHostingView 测试内部动画事务。测试不构造 LaunchModel，避免读取和保存真实布局。开始运行完整 swift test，结果续记。

### 验证与交付

- 无窗口对照测试确认根因：只在外层 withTransaction 中替换 hosting.rootView，内层收到的 animation 为 nil。使用本次生产代码的布局动画修饰符后，预览让位、同顺序松手落位、合并后的重排均收到原版 flow 弹簧。
- 新增 7 项测试。首轮 58 项中 1 项失败，原因是测试要求首次布局一定调用 transaction 探针，SwiftUI 在无动画时可省略该回调。改为检查首次布局不出现动画，并补充旧路径对照和签名不变测试。最终完整测试 60 项全过，0 失败，构建 0.95 秒。Release 构建通过，5.39 秒。
- 源码无编译警告。仅 SwiftPM 的 `--build-system native` 弃用提示。沿用既有模块缓存和构建器参数，未改 Package.swift 或工程配置。
- 分支仍为 `exp/hybrid`，HEAD `772ecae`，暂存区为空。工作区改动仅下列 3 个已有文件，无新增文件。白名单、git diff --check、S2 禁用关键词和条带图层红线检查全部通过。

改动文件与位置（相对 hybrid 工作树）：

- `Sources/LaunchpadProCodex/PageStripView.swift:5`：布局签名和内层动画修饰符。`:108`、`:122`：事务显式传值。`:176`：拖拽占位禁用动画。`:183`：动画限定在条目集合内。
- `Sources/LaunchpadProCodex/PagedLauncherView.swift:119`：传入完整布局签名。`:144`：浮动图标位置禁用动画，文件夹虚化仍在外层。
- `Tests/LaunchpadProCodexTests/PageStripViewTests.swift:9`：新增签名、hosting 边界与动画开关测试。

原版与红线核对：

- `PagedLauncherView.swift:61` 的 flow 以及 beginDrag、updateDrag（`:237`）、finishDrag（`:268`）、canMerge、commitMergeToModel 与 `cf82acc` 逐字一致，覆盖让位、落位、拖入文件夹后的重排。签名含 draggingID，避免松手时预览 ID 顺序不变而漏掉落位动画。
- folderLayer、folderGrid、folderAppCell、folderTitle、finishFolderDrag、updateFolderEjectPreview、position 与修复前 HEAD 逐字一致。文件夹拖出预览原有 flow 也由同一桥接恢复，未更改文件夹层内部动画。
- PagerController、PagerPhysics、FrameMeter、LauncherViews 与 HEAD 逐字一致。签名只含布局和 draggingID，不读 stripX、速度、targetPage 或每帧状态，仍只在已有 SwiftUI 更新时计算。翻页位移仍由 AppKit 处理，FrameMeter 的会话及 body 计数口径不变。
- 无动画事务、disablesAnimations、首次 hosting 布局与签名不变的更新均未启用重排动画。页数结构变化只有原调用方本就提供动画时才启用，条带尺寸不在布局动画修饰符范围内。搜索结果网格未修改。

复现命令：

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" swift test --disable-sandbox --build-system native
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" swift build --disable-sandbox --build-system native -c release
```

日志：hybrid 工作树 `.build/yield-animation-test.log`、`.build/yield-animation-release.log`。

未实测事项：未启动 LaunchpadPro。仍需 Leo 检查让位、松手落位、拖入已有/新文件夹后的重排、跨页与空页拖拽的 1:1 跟手、首次显示/页数变化/搜索切换无额外滑入，以及内置 120Hz 屏翻页的 `body_root/paged/strip=0/0/0`。自动测试验证内部动画事务，不能替代实际动画观感或帧率验收。未执行 git add/commit，交 Claude 提交。

## 拖拽重排第 2 轮（2026-10-16）

- 已先看 `拖拽bug截图.png`。当前分支 `exp/hybrid`，HEAD `0e79ca8`，开工时工作区干净。按新任务不提交，只改三个授权源码及测试。
- 优先核对翻页：旧签名来自完整 activePages，不随窗口成员变化。PagerController 的事件/帧入口未触发签名计算。暂不能把实机卡顿归因于“每帧签名计算”或“restingPage 改变签名”。本轮移除布局签名及全 ForEach 动画，改为拖拽操作显式触发的条目 token。
- 截图重影：原位条目被保留以维持手势，LauncherEntryView 使用 0.30 透明度，position 把该条目锚在原位。原版 cf82acc 也保留此占位。本轮按新要求将条带中的整个拖拽条目立即隐藏，保留身份和手势。
- Equatable 已比较完整 entry/cell/isDragging/isFolderTarget，预览、溢出和位置算法与原版一致。补测试核对这些路径，不把未经复现的猜测写成根因。

### 根因、改动与证据

以下未标提交号的位置均指本轮工作区，源码路径相对 `Sources/LaunchpadProCodex/`。

1. **现象 3：翻页变卡。** 未复现真实触控板卡顿，不能确认实机根因。已推翻“窗口变化会改变签名”和“事件/帧入口每帧计算签名”的猜测。旧 `0e79ca8:PageStripView.swift:22` 把完整布局签名动画挂在整个 ForEach，本轮删除这条路径。改为 `PageStripView.swift:12` 只在显式重排时记录位置变化条目的 token，`:24` 只按 token 启动原版 flow，`:33` 清除继承的位置动画，`:52` 禁止窗口条目过渡。触发点仅为 `PagedLauncherView.swift:308`、`:323`、`:336`、`:983`，分别对应预览、合并、提交和文件夹拖出预览。翻页、吸附、首次显示、窗口增减均不写 token。
2. **现象 1：名字残留。** `PageStripView.swift:65` 为维持跨窗口手势保留拖拽条目，`PagedLauncherView.swift:462` 将其锚在原位，`LauncherViews.swift:559` 又留下 30% 可见内容，后续条目移入后造成截图中的重叠。原版 cf82acc 也保留原位条目，不能通过删除 ForEach 成员修复，否则会取消手势。本轮 `PageStripView.swift:37` 在整个图标、标签和单元外统一隐藏占位并统一定位。外层浮动图标的无动画事务保持不变。
3. **现象 2：瞬移。** 旧 `0e79ca8:PageStripView.swift:122` 每次更新用临时 context.transaction 覆盖 layoutTransaction。无窗口测试复现：预览后的普通指针更新在 hosting 求值前到达，会把 flow 替换为空事务，旧实现测试失败，日志 `.build/reorder2-before.log`。本轮 token 携带重排意图，弹簧在内层按固定 response=0.24、dampingFraction=0.80 建立，不再依赖下一次外层事务。整组动画改成条目位置动画。对“远处 app 也动”未找到不同于 cf82acc 的算法证据，未改变重排语义。原算法提取为 `PagedLauncherView.swift:11` 的纯函数供回归验证，仅位置发生变化的现存条目获得新 token。
4. **Equatable 怀疑已排除。** 原实现已比较完整 entry。`LauncherViews.swift:519` 将同样的四个判等字段收拢为 RenderInput，`:534` 直接用它判等。测试覆盖 app ID、同 ID 文件夹名称/成员/顺序、单元尺寸、拖拽和合并目标状态。没有修改图标视图、标签视觉或竖向网格行为。

### 自动核验

- `swift test`：62 项通过，0 失败。替换已删除的签名机制测试，保留原有分页、命中、物理等回归测试。Release 构建通过，6.09 秒。源码无编译警告，只有既有 native 构建器弃用提示。
- `PageStripViewTests.swift:9`：三页、每页八项，192 组同页起点/插入点组合，验证只移动两点之间的连续条目，其他页不变，token 仅给受影响条目。`:37` 验证跨页溢出、返回原位、新空页和不重复级联。
- `PageStripViewTests.swift:97`：预览与普通指针更新合并后仍收到 flow，后续提交、合并 token 同样生效。`:137` 验证已有非零 token 的条目进出窗口不触发动画。
- `PageStripViewTests.swift:156`：ImageRenderer 对生产 PageStripEntryPlacement 作像素断言，图标和标签两个色块在拖拽时均消失，普通移动时均位移 60pt。跨窗口保留拖拽身份的原测试继续通过。
- `PageStripViewTests.swift:389`：真实 PagerController、PageStripContainerView、PageDotsView、生产位置修饰符和双 NSHostingView，无窗口模拟左右滑动。每方向 30 次跟手事件、共 107 个合成帧，逐帧检查 paged/strip 计数无增长。收敛后窗口确实重算，作为探针有效的正向对照。启用 FrameMeter 后两方向日志均为 `body_root/paged/strip=0/0/0`，`sum_raw=sum_applied=±360`。
- **计量范围：** 上述 hosting 测试使用与生产相同的 restingPage 依赖和窗口逻辑，但 paged/strip 是测试视图，未构造会读写真实布局的 LaunchModel，也未运行完整应用。root 计数无实际根视图覆盖。生产路径另作核对：`PagedLauncherView.swift:140` 只观察 restingPage，PageStripContent 不读取任何 pager 状态，事件/帧代码与 772ecae 完全相同。合成时钟日志中的 120Hz 不是实屏帧率证据。

复现命令（沿用前轮已验证的沙箱和缓存适配）：

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" swift test --disable-sandbox --build-system native
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" swift build --disable-sandbox --build-system native -c release
LAUNCHPADPRO_FRAMEMETER=1 CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" swift test --disable-sandbox --build-system native --filter PageStripViewTests
```

日志位于 hybrid 工作树 `.build/reorder2-tests.log`、`.build/reorder2-release.log`、`.build/reorder2-meter.log`。

### 红线与未实测项

- 工作区仅修改 `PageStripView.swift`、`PagedLauncherView.swift`、`LauncherViews.swift`、`Tests/LaunchpadProCodexTests/PageStripViewTests.swift` 四个已有文件。无新增源码。分支 `exp/hybrid`，HEAD `0e79ca8`，暂存区为空，未 git add/commit。
- 已用函数块逐字比较核对：folderLayer/folderGrid/folderAppCell/folderTitle、finishFolderDrag、position、reorderSlot、mergeTarget、canMerge、commitMergeToModel、flipPage 均未改变。AppIconView/FolderIconView/SearchBar/VerticalLauncherGrid/SimpleFolderOverlay 未改变。
- PagerController/PagerPhysics/FrameMeter 与 772ecae 逐字相同。禁用关键词、条带图层红线、文件白名单与 git diff --check 均通过。
- 未启动 LaunchpadPro，未打包、安装、修改系统设置或写 .git。实机卡顿根因、翻页手感是否恢复到 772ecae、120Hz A1–A7、真实图标动画观感和拖拽手势连续性仍待 Leo 按交付边界 §6.4 验收，本轮不能宣称这些已通过。
- 交付时尝试打开记录所在 Finder 文件夹。`open <目录>` 返回 -10661，显式指定 Finder 返回 -10827（可执行文件不可用），当前环境未能打开 Finder。

## 拖拽第 3 轮：外层 SwiftUI 网格（2026-10-16）

- 开工：hybrid 分支 `exp/hybrid`，HEAD `643683c`。已有未提交改动仅 PageStripView.swift（PageStripStore、renderSignature、内部位置状态与 DebugTrace），保留 store/signature，按任务删除日志。此次不 git add/commit。
- 采用内层网格 opacity=0，容器与手势条目保持挂载、保持拖拽命中。外层网格禁止命中，使用共享格点计算和原版 flow 弹簧。切换以禁用动画的同一次状态事务完成。
- 外层接管期间记录页偏移，边缘翻页用原版页面弹簧。浮层保持无动画跟手，松手后从释放点落位，完成后同步 pager 并恢复条带。文件夹内拖拽保持原路径。
- 将补坐标对齐、落位/切回状态、手势宿主保留与非拖拽翻页零重算测试，再执行 Release 构建及完整测试。

### 实现与核验

- `PagedLauncherView.swift:362`：拖拽起点捕获实际 stripOffset，在同一个禁用动画事务内设置 draggingID 和 dragPresentation。后者同时控制条带隐藏与外层网格出现。外层先按捕获位置显示，再允许预览让位。
- `PageStripView.swift:76`：opacity 仅作用于内层 SwiftUI 绘制，不设置 NSView 的 alphaValue/isHidden，不移除 representable、host 或正在拖拽的 ForEach 条目。拖拽期间维持命中，外层 PageDragGrid 禁止命中。松手进入落位后才暂停条带命中，结束后恢复。PageStripStore 与 renderSignature 保留，签名增加 hiddenForDrag，DebugTrace 及调用全部删除。
- `PagedLauncherView.swift:11`、`:201`、`PageStripView.swift:86`：两套网格共用 PageGridGeometry、同一 positions 字典和 cell。条带为绝对页坐标，外层仅减去 stripOffset。缺失位置的回退也使用实际格点，移除 `.zero` 回退。
- `PagedLauncherView.swift:247`、`:497`：外层 ForEach + position 接收原版 flow（0.24/0.80），边缘翻页使用原版 spring（0.32/0.84），保留 0.55 秒节流、预览扩页和合并算法。隐藏条带用 pager.jump 同步页号，普通翻页仍由原 PagerController 处理。
- `PagedLauncherView.swift:268`、`:413`：浮层拖拽时继续禁用动画。松手记录最终 dragPoint，下一主线程轮次提交，保留同一个浮层从释放点弹向目标格，同时恢复正常缩放和阴影。对应网格条目继续隐藏，避免名字或图标重影。合并后的邻居重排仍用 flow。
- `PagedLauncherView.swift:462`、`:487`：等落位/合并重排及尚未结束的页面弹簧都触发 `.removed` completion 后，再以无动画事务恢复条带。切回前 configure + jump，使 restingPage 与外层目标页一致。会话 UUID 和页面动画 UUID 排除过期 completion。

### 自动验证结果

- 新增 4 项测试，默认环境 `swift test` 共 66 项全过，0 失败、0 跳过。Release 构建通过（5.60 秒）。无源码编译警告，仅既有 `--build-system native` 弃用提示。
- `PageStripViewTests.swift:9`：3 种页宽（含小数）、原布局/跨页预览/新增空页、6 个视口页，共 3240 个条目位置组合，逐项验证外层坐标等于真实 PagerController 换算值，并与 cf82acc 格点公式独立比较。另测半途滑动接管的 540 个条目位置。
- `PageStripViewTests.swift:60`：生产 PageDragGrid 用图标/标签色块替身，在 2 倍缩放、4 种偏移（含半页位置）下，与整条带平移参考图逐字节比较像素，全部一致。该测试验证布局，不代替真实图标与文件夹材质的实屏观感。
- `PageStripViewTests.swift:97`：生产可见性修饰符与无窗口 NSHostingView 探针反复切换隐藏，手势条目只出现一次、未消失，宿主身份和 AppKit 命中保持。未合成真实鼠标按住/移动/松开事件，实际拖拽连续性留待实机验证。
- `PageStripViewTests.swift:126`：分别覆盖页面弹簧先结束和落位先结束，两者都结束才允许切回。
- 原 `testPagingHostingBodiesStayIdleDuringTrackingAndSnap`（`:524`）继续通过。启用 FrameMeter 后，两方向各 107 个合成帧均为 `body_root/paged/strip=0/0/0`，位移守恒为 ±360。该探针使用真实 pager/container 与测试 hosting 视图，不启动 LaunchpadPro，不代表实屏 120Hz 或生产完整根视图已测。计量开启的全套测试 65 通过、1 项按条件跳过（验证计量默认关闭的测试），之后默认环境已完整复跑 66 项。

复现命令：

```sh
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" swift build --disable-sandbox --build-system native -c release
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" swift test --disable-sandbox --build-system native
LAUNCHPADPRO_FRAMEMETER=1 CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache" swift test --disable-sandbox --build-system native
```

日志：hybrid 工作树 `.build/drag3-release.log`、`.build/drag3-tests.log`、`.build/drag3-meter.log`。

### 交付边界与实测项

- 改动仅 `Sources/LaunchpadProCodex/PagedLauncherView.swift`、`Sources/LaunchpadProCodex/PageStripView.swift`、`Tests/LaunchpadProCodexTests/PageStripViewTests.swift`，以及本文追加记录。LauncherViews.swift 无需修改，无新增源码。开工已有的 PageStripStore/signature 改动继续保留。
- folderLayer/folderGrid/folderAppCell/folderTitle、finishFolderDrag、updateFolderEjectPreview、reorderSlot、mergeTarget、canMerge、commitMergeToModel 与 HEAD 函数块逐字一致。PagerController、PagerPhysics、FrameMeter、LauncherViews 全文件与 HEAD 一致。
- 非拖拽 body 仍只读取 pager.state.restingPage，stripOffset 只在拖拽起点回调捕获。没有新增每帧 SwiftUI 发布或将高频 pager 状态引入 body。
- 文件白名单、禁用关键词、条带图层红线和 git diff --check 均通过。分支 `exp/hybrid`、HEAD `643683c`、暂存区为空。未启动应用，未运行打包脚本，未安装、改系统设置或执行 git add/commit。
- Leo 需实测：按住后持续拖动与连续跨页不中断；让位、松手从释放点落位、合并重排；图标与名称无原位残留；接管/切回无闪烁；跨页与新增空页落位后页点正确；文件夹内拖拽/拖出、搜索输入与焦点；正常翻页 120Hz 和 `body_root/paged/strip=0/0/0`。
- 已尝试在 Finder 打开 hybrid 工作树，当前环境返回 `Unable to find application named 'Finder'`。
- 显式使用 `/System/Library/CoreServices/Finder.app` 再试，返回 `-10827 kLSNoExecutableErr`（可执行文件缺失），未能打开 Finder。
