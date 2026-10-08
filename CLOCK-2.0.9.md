# 2.0.9：传统原生层级与失败保底

## 已确认与未确认

基线 main 675e24b（2.0.8）只把 `_UIAnimatingLabel -> CSProminentTimeView -> CSProminentDisplayView -> SBFLockScreenDateView` 认作主时间，且 Hooked 要求四类同时存在。报告的传统 `UILabel -> SBUILegibilityLabel -> SBFLockScreenDateView` 因此不能命中；prominent 三类未加载解释了主时间扫描、Apply、draw/suppress 为零和 Snapshot never-attempted。无需假设 iOS 系统版本变化。

这证明的是识别/门禁不兼容，不是“插件已经抑制了主时间”。基线 DateOverlayParent 必须先遇到 subtitle 再遇到 SBFLockScreenDateView；报告的主时间以及两个直接 UILabel 没有 subtitle，不能进入日期隐藏路径。dateGradient=0 也不支持该日期隐藏路径已执行的断言。传统 image 绘制没有被基线直接 Hook；其 ImageView 的 layer contents 不是 UILabel drawTextInRect。已发现日期路径存在保存 alpha/hidden 后写 alpha=0、缓存命中再次写 alpha=0 和关闭时恢复旧值的风险，但报告不能证明它导致本次时间消失。

设置页所有 visible=0 不能证明锁屏亮屏状态；字体注册成功、用户几何参数也不能解释 never-attempted。仍需真机锁屏截图与同一次亮屏的完整诊断、关闭功能/禁用其他时间插件对照以确定消失的实际原因。

## 策略

- prominent 保留严格祖先链、透明 UIView 包装的唯一豁免、原 sibling host、CoreText 字形/独立加厚描边及安全提交门。
- prominent 和 traditional 按各自类及真实 override 覆盖判断，不再把四类同时加载作为传统层级前提。
- traditional 的候选只来自精确直接父子结构，不依据字体大小。纯文字路径还要求唯一时间来源、严格时间内容、实际 draw Hook 覆盖；直接 UILabel 必须由容器 timeLabel 引用确认身份。重复时间、未知绘制父层、非唯一 wrapper 和未知 override 拒绝替换。
- 对本次报告含 `_UILegibilityView/_UILegibilityImageView` 的复合主时间明确采用系统保底，而非声称完全自定义支持。哪怕设置页 image 节点不可见也拒绝；不修改它们的 image、contents、alpha、hidden，不仅抑制其中 UILabel，不生成双重字形。风险高时“不渲染自定义效果”优先于消失或叠字。
- 日期限精确 subtitle 容器、排除时间内容，保留不同语言的日期文字；image-backed 日期同样保底。删除所有系统 UILabel alpha/hidden 写入和旧状态恢复。日期在遮罩、挂载、签名、真实 Hook、可见性、opacity、裁剪门通过后仅抑制文字绘制；失效/关闭立即移除插件层并放行系统 draw。
- 日期仅渐变无描边，大时间独立加厚/描边，共享五色管线保持不变。继续事件驱动、弱引用集合、signature/revision 缓存，无轮询、Timer、DisplayLink。

## 验证与诊断

新增 legacy_clock_test.cpp 和 verify_legacy_clock.py，CI 同时执行；覆盖两套层级、传统 image/歧义/未知 Hook 拒绝、日期/农历/通知/充电结构排除、关闭/字体/遮罩/挂载/签名/可见性失败矩阵及 prominent wrapper 不变。源码契约保证无系统 alpha/hidden 写入、draw 失效先撤插件 overlay 再原生放行。包验证检查 2.0.9 版本及新增诊断/保底标记。

报告新增每层级 Hook 就绪、传统候选/验证结果、image-backed 保底原因、实际安全门结果；深层候选扫描包括传统节点和 legibility 类真实 IMP 覆盖。候选、Hook 就绪和编译/包测试都不等于像素上屏成功。

真机验收应安装对应包并注销 SpringBoard，在锁屏亮屏场景分别测试：开启/关闭；dateGradient=0/1；通知展开/充电；原生/导入字体；失败与超界参数。传统 image-backed 场景预期保持系统时间，不保证自定义字体/渐变；不能把 CI success 当作此项已验收。
