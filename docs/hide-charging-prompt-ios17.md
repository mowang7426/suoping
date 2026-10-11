# 2.0.19 提示隐藏修复：证据与边界

基线：fef183cddfb9495e5a30f5fd16df0bdaa85a71d7（2.0.18）。仅在 fix/hide-charging-prompt-ios17 工作，main 不变。

## 已证实的代码缺陷
- 2.0.18 只为一组未经本机诊断证明的私有类安装提示 hooks；普通 UILabel 永远不进入这组 hooks/类白名单。
- 旧祖先判定仅接受 SBUI/SBUILockScreen/CSLockScreen/SBLockScreen 前缀，实际诊断中的 SBFLockScreenDateView、CSProminentDisplayView、CSCoverSheetView 均不命中。
- 提示模块从 standardUserDefaults 读取开关；设置项写入 com.minis.lockscreengradientclock，现有 LoadConfig 使用该域的 CFPreferences。旧模块未复用 Config，也未关联 enabled。
- 旧模块保存一次 alpha/hidden 后反复恢复，无法保留系统后续可见性语义；refresh 复用旧 kind、不重新核验文本。

## 不能从旧证据确定的部分
完整旧报告包含 UIView -> UILabel 430×28，但未记录该标签文本及完整祖先。截图可见白色电量文字与日期叠加；两者均不足以证明该普通标签就是唯一提示节点，更不足以证明 image-backed 私有绘制路径。

## 私有接口证据
来源为 MTACS/iOS-17-Runtime-Headers，访问时间 2026-10-11；原始内容附于 docs/evidence/*.h.txt。
- https://github.com/MTACS/iOS-17-Runtime-Headers/blob/main/PrivateFrameworks/SpringBoardFoundation.framework/SBFLockScreenDateView.h
  含 _activeSubtitleView、_dateSubtitleView、_customSubtitleView、_updateActiveSubtitleView、chargingVisualInformationTimeSubtitleFrame。证明日期宿主存在 subtitle/charging 布局接口，不证明唯一 leaf 类。
- https://github.com/MTACS/iOS-17-Runtime-Headers/blob/main/PrivateFrameworks/CoverSheet.framework/CSTeachableMomentsContainerView.h
  含 SBUILegibilityLabel *_callToActionLabel 及容器。用于已有解锁提示开关的严格宿主约束，不额外猜测叶类或安装其私有 hooks。
- https://github.com/MTACS/iOS-17-Runtime-Headers/blob/main/PrivateFrameworks/CoverSheet.framework/CSChargingViewController.h
  展示 CSBatteryChargingInfo / CSBatteryChargingView；不据此扩展强隐藏范围。

## 修改范围
- LSGCPromptPolicy.h 是生产和 C++ 行为测试共用的完整句式/百分比、祖先范围及状态机。电量须有 SBFLockScreenDateView + CSCoverSheetView；解锁须有 CSTeachableMomentsContainerView + CSCoverSheetView。只接受 UILabel 叶子，排除主时间、通知路径、LSGC 标识及既有胶囊 label tag 7001。
- 简繁中英文电量/充电完整句式必须含 0–100 的整数百分比；兼容普通/不换行/窄不换行/全角空格、全角百分号、大小写及可选冒号。未知文案、范围或非叶子仍显示，不按颜色/坐标/“电”“量”子串匹配。
- 默认关；显式使用 Config.enabled && Config.hideLockScreenPrompts。
- 复用现有 UILabel/_UIAnimatingLabel 生命周期和文本 hooks；只在状态转换时 setNeedsDisplay。绘制路径只有只读判定和原生 glyph 跳过，Rendering/SnapshotText 放行，不触发 Apply/调度。
- 不写 alpha/hidden、不隐藏日期容器、不安装 UIView setter hooks、不新增轮询。关闭开关、关闭 enabled、移出窗口、文本重用为日期均恢复绘制；系统 alpha/hidden 永远由系统持有。
- 已识别提示不会进入日期 overlay 选择，已存在日期 overlay 的标签变成提示时由原事件调度移除旧 overlay。主时间、日期渐变算法、胶囊百分比代码及偏好 UI 未改。
- 现有诊断报告新增 SystemPromptDiagnostics v2；按需列出开关、祖先链、目标类型、拒绝原因和抑制/恢复状态转换数，不高频日志、不输出原文。计数不等于上屏成功。

## 测试与实机边界
新增 tests/system_prompt_test.cpp 运行同一生产 identify/update，覆盖普通 UILabel 的目前电量句式、简繁英/空格、百分比边界、真日期农历/主时间/通知/插件/未知拒绝、日期重用、开关/enabled、脱离窗口、同值千次无重复转换和 alpha/hidden 最新语义。静态测试核验运行时接入与快照避让。测试模型不等于 UIKit 真机视觉验收。

如系统直接显示缓存图像或私有 label 的 layer 而不调用已覆盖 drawTextInRect，本候选不会强藏该未知节点。必须由 iPhone 14 Pro Max / iOS 17 / relaxin RootHide 上安装后充电、开关切换、日期恢复和唤醒实测验证。
