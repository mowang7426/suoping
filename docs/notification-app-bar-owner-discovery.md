# 2.0.26 owner discovery candidate

2.0.25 的设备诊断显示 enabled=1 adapter=1 mounted=0 applied=0 total=0 reason=waiting-native-owner：尚未绑定原生源，不是已执行 Geometry 后的失败。该版本 Configure 只尝试缓存 candidate；candidate 只在后续 layout 回调写入，因此已有控制器启用开关可能没有任何发现机会。Attach 又要求父链 CSCombined 的 notificationListViewController 必须严格等于自身；诊断无法区分锁定门、getter 空值/不一致和根本没见过 candidate。

2.0.26 从 SBLockScreenManager.coverSheetViewController 以及至多 8 个 SBCoverSheetWindow 的根控制器开始，按需、主线程异步合并遍历 child/presented/responder/parent（192 节点、12 层 parent），无全局 UIView/UILabel hooks、timer、display link 或 draw 内同步调用。仅已加载锁屏局部视图内发现既存 CSQuickActionsView（1024 节点）。原生 backlight transition（仅真实方法 ABI 验证通过时安装）、开关启用、原生列表 layout/appear、Combined appear、快捷按钮 layout、重新锁定、口令消失和 post/update 触发重试；无投机轮询。

归属只允许：CSCombined 明确 getter 恒等；getter 容器与 candidate/Combined 有受限真实 parent 链；或运行时确实存在、类型编码严格为 NCNotificationStructuredListViewController 的 _structuredListViewController ivar 且其真实值恒等于 candidate。不能仅凭处于锁屏根之下接受任意通知 controller。未知形态 fail closed。

公开 iOS17 头声明证据：https://github.com/MTACS/iOS-17-Runtime-Headers/tree/d1d960dfaa4107765dd7fcf891e4967c0930d5fd 。CSCombined 声明 _structuredListViewController 和 notificationListViewController（后者返回 UIViewController）；NCNotificationStructuredListViewController 继承 UIViewController。SBLockScreenManager 声明 coverSheetViewController/isUILocked/isLockScreenVisible/_isPasscodeVisible/isPasscodeEntryTransientOverlayVisible。它们是静态声明，不证明用户版本的运行时对象值、实例父链、调用语义或显示成功。所有发送前仍校验真实 ABI/类型/恒等。

保留四项锁定安全门，没有因猜测删除 selector 或改成“只要有锁屏 window 就算锁定”。新诊断逐项记录可用性与布尔值（缺失为 missing-or-ABI），并记录 candidate class/parent chain、ownership、发现节点/候选/owner、provider ABI、snapshot reason、hook ABI 和具体布局坐标，不记录通知正文。解锁进入设置时离屏/门关闭是正常快照；等待上述生命周期事件恢复发现，不作为锁屏渲染失败证据。

新增空间预留：满屏时只接受经真实 masterListView getter、NCNotificationListView : UIScrollView 类型、owner 后代、可见同窗口、全链无 transform、手动 frame 与 clipsToBounds 校验的原生列表。通过缩短该实例 viewport 并增加本插件独占 bottom inset 为栏预留真实空间；不触碰全局 UIView/UIScrollView setter。仅在 NCNotificationListView 类安装经过 UIEdgeInsets ABI 校验的 setContentInset: observer，外部绝对写入作为新 baseline，原生 setter 每次调用一次，叠加本插件贡献；关闭/卸载只减去自有贡献，frame 未被系统改写才恢复旧 frame。无 timer、draw 同步 Apply 或 setNeedsLayout 风暴。未知/AutoLayout/transform/缺 setter ABI 仍 fail closed。此实现已增加生产 coordinator mock 执行覆盖，但真实设备滚动、命中与原生系统回写语义仍未验证。

保留 2.0.25 owned 原生显示投影恢复/撤回机制，不重写 master 数组，不复制/序列化通知正文，不复活已撤回通知；owner 变化先恢复旧 owned，源销毁清理，关闭开关恢复。栏所在窗口变化时卸载并重建。

执行测试：新增 Foundation mock 直接编译执行生产 LSGCNotificationOwnerDiscovery.mm；覆盖既存根发现、candidate parent/child、getter identity/container/typed ivar、拒绝 sibling、presented/responder cycle、预算、root 变化、错误 getter ABI、锁定/解锁/口令/缺 selector。挂载空间执行生产 GapFits 策略。既有 Foundation projection 测试继续执行真实 LSGCNotificationsAppBar.mm 的投影/owned/撤回/恢复/源销毁路径。另有独立 UIKit mock 直接包含完整生产 LSGCNotificationsAppBarRuntime.mm，执行 Configure/Discover/Attach/Pump/真实 original-first 回调、亮屏重试、新旧源切换先恢复 owned、启用既有实例、关闭恢复、撤回不复活、锁定转换、Geometry 满屏拒绝、窗口迁移和错误窗口/provider ABI 拒绝。该测试只替代 UIKit/注入注册与原生方法实现，并确定性推进已排队 Pump；不替代生产策略。真实 UIKit 生命周期时序、真实窗口层级、图标绘制及原生私有方法语义仍需目标设备验证，mock 不替代设备验证。
