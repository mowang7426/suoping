# 2.0.2 真实主时间诊断增强版

本版不放宽主时间的精确祖先链与安全门，不隐藏主时间 UIView，不调整渲染效果、字体或时钟几何算法。`ClockReplacementReady` 与 2.0.1 保持逐字一致（回归脚本校验 SHA-256）。日期渐变、通知时间、充电预估不是主时间成功证据。

## 使用与提交证据

1. 按越狱类型安装 CI 对应的 Rootless / Roothide 2.0.2 包，然后注销 SpringBoard。
2. 保持希望验证的字体及时间设置；亮屏显示锁屏，至少经历一次原生时间更新/布局；不要为了测试关闭安全门。
3. 打开插件设置的诊断入口，点击“复制”，提交全文而不是弹窗截图或“日期有效”一句话。报告中必须显示 `2.0.2-standalone-diagnostics`，并包含从 `=== RealClockDiagnostics v1 ===` 到 `=== End RealClockDiagnostics ===` 的完整段落。
4. 同时提交锁屏截图和下列填写内容：

```text
设备型号：
iOS 版本：
越狱名称/版本：
包类型：Rootless / Roothide
安装包版本：2.0.2
是否已注销 SpringBoard：
其他锁屏/字体/时间插件及版本：
锁屏截图拍摄时间：
诊断复制时间（与截图是否同一次亮屏）：
预期改变（字体/宽高/偏移/渐变等）：
实际表现：

[粘贴完整诊断报告，包含旧报告头和 RealClockDiagnostics 全段]
```

诊断在设置页请求时采样，锁屏可能已隐藏；所以当前 `visible/onScreen` 失败不能证明亮屏期间从未成功。应结合主时间 draw 累计计数、最后一次 failure-before-removal 快照及截图。必要时提供“正常亮屏”与“通知展开/充电”两组报告并注明场景。

## 新增报告内容

- 所有当前窗口中精确 `_UIAnimatingLabel` 以及 `CSProminentTimeView` 子树候选，无报告条目/祖先链截断；严格 scope 的 exact-label、time/display/lock-date 有序阶段、subtitle 排除、最终 identity、InLockScreen、拒绝原因。范围函数仍只看前 64 层；完整链另外全量输出。
- InstallHooks 调用次数与 Hooked/LabelHooked/NativeClassesLoaded 的实际值；各目标类/selector 的真实 method owner，记录的 original IMP、当前 IMP 是否存在，当前是否等于记录的期望 hook，直接/继承覆盖状态。后续插件包裹 hook 会导致 currentMatchesExpectedHook 为假，不应单凭此字段认定原 hook 完全失效。
- layout/didMove/draw hook 累计调用计数；主时间 draw、原生放行、自定义 glyph 抑制累计计数。主时间计数排除 SnapshotText 镜像绘制与 super 调用链重复计数。hook 总计数含镜像/其他 UILabel；不能当主时间成功次数。
- Schedule/Apply 次数、最后 early-return/处理结果。queued 表示等待异步处理，不表示渲染成功；date-only 明确不是主时间成功。
- 最后一次主时间 SnapshotText 的请求尺寸/scale、图像尺寸/scale、像素宽高、HasAlpha、alpha > 8 的像素包围盒（位图坐标），以及空图/分配失败/预算超限状态。
- 最后一次主时间 RemoveOverlay **之前**的失败门禁快照：identity/hookReady/committed/enabled/fontReady/maskHasInk/attached/visible/onScreen/signatureCurrent/opacity/failedReasons、失败原因和几何。
- 候选 label、host/overlay 的 window rect，window bounds，完整祖先 hidden/alpha/clipsToBounds、label/overlay 逐级交集；当前候选安全门状态。
- 字体与时钟配置键值、字体注册状态及已导入字体名。

## 开销与边界

- 只保存饱和计数、有限目标类/selector 的 IMP 记录、最后一次主时间 mask 和最后一次失败快照。不持有历史视图或图像。
- 候选遍历与完整祖先几何只在用户请求报告时生成；失败现场几何只在 Apply 拒绝主时间时保存。mask 包围盒只在主时间重建快照时扫描，扫描限制 8,388,608 像素。
- 不增加轮询、Timer 或 CADisplayLink。诊断不调用隐藏、附加或移除渲染层的方法。
- 安全门通过是提交条件，不是像素上屏证明；自定义抑制计数说明 hook 放弃了原生 glyph 绘制，也不是用户看到了预期样式的最终证明。最终需完整报告与真机截图关联。

## 回归

运行五个现有 C++ 测试及 `verify_clock_safety.py`、`verify_clock_startup.py`、`verify_settings.py`、`verify_clock_diagnostics.py`。GitHub Actions 继续实际构建 Rootless/Roothide，并通过 `verify_packages.py` 验证两包。构建和源码回归均不能替代真机验证。
