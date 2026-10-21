# 通知应用图标栏 2.0.25 候选：显示层适配与安全边界

## 路线变化

本候选已移除此前 `NativeFilterSemanticsVerified() == false` 的空壳门。生产源文件、开关、图标栏、诊断和 CI 已接线。实际使用 iOS17 `NCNotificationStructuredListViewController` 的 `- (void)removeNotificationRequest:(id)` / `- (void)insertNotificationRequest:(id)` 临时移出/恢复原生展示；不是通知派发器的清除接口，也不伪造 delivery 返回成功。

公开 Axon 的显示 hide/show 调用仅作为行为路线参考，未复制其实现、资产或拦截接收策略。本实现原始 insert/modify/remove、CoverSheet post/update/withdraw 和 Dispatcher withdraw 回调都先执行 original；之后才更新本模块状态或异步投影。不会像历史 Axon 那样吞掉原始 insert、假回 YES 或重写 clear-all。

## 可审计证据

固定头文件来源：MTACS/iOS-17-Runtime-Headers@d1d960dfaa4107765dd7fcf891e4967c0930d5fd（17.0.3，不冒称精确17.0）。相关原生声明与下载内容 SHA256 记录于 `docs/evidence/notification-app-bar-ios17.txt`。

* UserNotificationsUIKit: StructuredListViewController 的 void 单对象 insert/modify/remove、masterList；MasterList 的只读 notificationListSections 和 `_updateNotificationListPersistentState`；StructuredSectionList 的只读 allNotificationRequests；ListCell 是 UIView，具有原生 content/notification controller。
* UserNotificationsKit: NCNotificationRequest 的 sectionIdentifier、notificationIdentifier，以及原生保留的 timestamp/thread/options；NCNotificationDispatcher 的 post/modify/withdraw 和另行声明的 destination requestsClearing 接口。生产主动发送中没有任何 Dispatcher clear/withdraw/remove 调用；唯一 Dispatcher 钩子是原始撤回后的旁路观察。
* CoverSheet: CSCombinedListViewController 的 notificationListViewController、post/update/withdraw；CSQuickActionsView 的真实 flashlightButton / cameraButton。
* SpringBoard: SBLockScreenManager 的 sharedInstance、isUILocked、`_setUILocked:(bool)`。
* 参考：dakotadawolfe/axon-ios16-compatibility@5de63de57c2ccb0fdefb33e374c59e1517b0c040，AXNManager 的 showNotificationRequest / hideNotificationRequest 将请求传给展示控制器，而真正 clear 使用 dispatcher destination requestsClearing。源码只阅读用于区分路径，未移植。

运行时先验证完整钩子面的动态 class、参数个数、返回值和每个参数 ABI；再一次性安装。只接受 iOS17。具体实例还必须是原生 StructuredList 控制器、有可读 MasterList/SectionList/Request 且属于实际 CSCombined 父控制器；实际 isUILocked、可见窗口和安全空间必须同时满足。未知 ABI/归属/空间不启用。

## 恢复机制

`LSGCNotificationsAppBar.mm` 是 UIKit 无关的真实 Foundation 生产桥，macOS 测试编译同一个文件，而非另一套模拟策略。

* 只读枚举原生 section/request，按 `(sectionIdentifier, notificationIdentifier)` 去重计数，绝不读 content/bulletin/context/userNotification。
* `owned` 仅强持有本模块真正移出的原始 request，以及移出前的 section/enumeration 位置数字。可见请求只在当前快照作用域短暂保留。没有本地通知正文文件、日志或持久缓存。
* 先登记 ownership 再发送显示 remove，防止重入真实 withdrawal 后被错误重新放回缓存。真实源 remove/withdraw/user clear 会即时删掉 ownership，永不从已撤回缓存恢复。原始 modify 若未能在原生列表找到隐藏条目，会更新本模块对应的最新真实 request，而不是丢失其恢复资格。
* 切全部、关闭、离开锁屏、空间丢失、选择应用清空：仅恢复仍 owned 的真实请求。按保存的 section/position 顺序调用原生单参数 insert；保持同一 request 的原生 timestamp/thread/options，由原生接口决定排序、coalescing、Focus/外部筛选与实际卡片，不拼接假卡片或模拟点击。
* 每次 restore 用原生快照确认请求已交回；每批 hide 也确认请求实际不再出现在原生快照。void 方法正常返回但没有效果，不算成功；会锁存适配失败。恢复失败保留待恢复对象，不会为了显示成功清空缓存。
* 模块投影期间只对本模块对应 master 延后 `_updateNotificationListPersistentState`，避免临时隐藏快照被写入原生持久显示状态；全部恢复完成后执行原始持久化更新。既不替换整个 master requests 数组，也不调用全局 native toggle/迁移/隐藏集合 setter。
* 源销毁后不向死亡控制器发送消息，只清理模块内存；真实通知仓库未被改变，新原生源自行从系统加载。正常离屏会先安排原生恢复。

## UI 与性能

独立 notificationAppBar 开关默认 OFF，且受 enabled 主开关约束。横向“全部”、本地绘制应用首字母图标和去重数量，VoiceOver 保留应用标识与选择状态；无网络图标请求。仍使用原生卡片及点击/展开/回复路径。

几何来自同窗口真实 NCNotificationListCell 底边、真实手电筒/相机 bounds 和 LSGCChargingETAPill 标识。没有猜全屏坐标来强塞；无卡片、遮挡、空间不足、层级不明就不挂载并恢复。充电胶囊新增标识仅供几何避让，不改其显示策略。

所有投影主线程异步合并，每批最多32次原生变更，活跃投影规模最多512条；只在剩余实际工作时继续异步批次。有限重入标志，异常不无限自调度。没有 timer/displaylink、全局 UIView setter、draw 同步 Apply。相同 rows/selection/frame 不重建 UI，dyld 类加载检查也做合并。

## 验证与限制

CI 运行现有全部回归、新纯C++共用计数/预算测试、Foundation生产桥测试、两个包构建及 verify_packages。桥测试包括活跃到达/删除、隐藏条目撤回/用户清除不复活、最新对象修改、全量恢复、原生排序/原对象线程元数据、外部筛选所有权、快速切换、批处理/重入、源销毁、计数去重、ABI错误、native no-op拒绝伪成功与恢复失败保留对象。源码契约检查保证开关、Makefile、诊断和工作流接线。

这是可测试候选，不能用模拟测试冒充真机安全证明。尚未在目标 **iPhone 14 Pro Max / iOS17 / relaxin / RootHide** 运行：私有实现内部是否还存在其他持久化出口、历史/摘要分组恢复、异步系统撤回时序、系统卡片完整交互、复杂第三方筛选协作和布局均须真机验收。运行时签名验证不是反汇编证明；头文件17.0.3不等于所有17.x版本语义相同。仅建议在可恢复环境先以少量非敏感通知验证，开关保持默认关闭；main稳定版不合并。
