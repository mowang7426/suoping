# LockScreenGradientClock 1.5.0 — JSON 导入导出与遮罩修复测试版

## 1.5.0 当前版本

新增配置文件按钮：导出当前全部视觉参数为 JSON，通过分享面板保存到文件；导入 JSON 校验 format/schema、已知参数类型和范围，文件限 256 KB，未知键忽略，缺失键保留当前值。导入确认之后才保存回退快照并应用。范围仅为本插件视觉设置，不包含总开关、兼容模式、严格层级、已保存方案库及原 Liquidify 设置。取消/校验失败不更改设置；导入后可用恢复上一次设置撤销。

重绘修复：不再把内部 cc_maskAttributedString 画布属性用于普通标签；复制显示标签的富文本，渲染完整 UILabel，避免 textRect + drawTextInRect 的二次定位。渐变和彩边内部统一零原点，原遮罩位置转换到 host 的局部坐标；补充源遮罩 bounds/transform/owner 等几何缓存条件。此为针对截图水平截断的修复尝试，无法凭截图确认唯一根因，仍需两种模式真机对照。

从 1.4.1 替换六文件：Tweak.xm、control、Preferences/Makefile、Preferences/LSGCRootListController.m、Preferences/Resources/Root.plist、Preferences/Resources/Info.plist。原有两个 Math 头文件保留。主 Makefile / 工作流不变；设置 Makefile 新增 UniformTypeIdentifiers 框架，不能漏换。

验证：真实 iPhoneOS16.5 SDK 下核心和设置控制器 arm64/arm64e 对象编译，-Wall -Wextra -Werror。尚未完整链接打包、文件选择器/分享/导入端到端或真机视觉验收。以下为历史记录。

## 1.4.1 历史更新

仅将五色渐变的五行文字按钮折叠为一排五个颜色圆点。圆点显示已保存颜色，点击仍调用系统选色器；改色时发送本进程刷新通知。方案切换、恢复及面板重载时重新读取实际颜色。原 color1～color5 键和 Root.plist 配置保留用于方案保存，不迁移或重置设置。彩边选色等其他界面不变。

从 1.4.0 升级替换 Preferences/LSGCRootListController.m、Preferences/Resources/Info.plist、control；Tweak.xm、Root.plist、头文件和构建配置不用改。圆点单元格与控制器放在同一个源文件内，无需改 Makefile。

已通过 iPhoneOS16.5 SDK 下 arm64/arm64e 设置控制器对象文件编译（-Wall -Wextra -Werror）。未做真实设置应用渲染验证，系统主题插件可能影响显示；安装新包并关闭重开设置后检查。核心兼容诊断仍显示原核心版本 1.4.0，因为核心未修改。

## 1.4.0 历史更新

保留 1.3.0 所有旧设置和默认值，新增自定义角度、五个颜色位置、一键颜色反转、三色独立彩边和方案保存/切换/删除/恢复。自定义角度、自定义位置、独立彩边默认关闭，反转默认关闭；不启用就沿用旧路径。

- 角度按显示尺寸计算，0° 水平、90° 垂直；开启后暂时覆盖旧方向选项，不改写旧方向。
- 五个位置取值 0～1。交叉值在渲染时投影到有序序列，至少间隔 0.01；设置滑条保留输入值，建议自行保持递增。反转仅调整颜色顺序，不修改颜色本身或位置。
- 开启独立彩边使用三色选色器；关闭后恢复冰蓝紫/粉金/原五色选项，不替用户改配色。
- 方案最多 20 个，名称 1～32 字，同名不覆盖。仅保存当前插件的视觉参数；不包含 enabled、strictScope、maskMode、诊断和原 Liquidify 设置。
- 恢复上一次设置：每次进入面板首次手动改动前保存快照；切换方案前也保存。恢复操作交换当前/上一次视觉参数，可来回比较。不是无限历史或逐个滑条撤销。
- 仅重置彩边也重置新增独立彩边参数，不清除字芯配色。新增仅重置位置与角度操作不清空方案。

从 1.3.0 升级：替换 Tweak.xm、control、Preferences/LSGCRootListController.m、Preferences/Resources/Root.plist、Preferences/Resources/Info.plist；新增根目录 LSGCGradientMath.h（必须）。LSGCEdgeMath.h 保留。Makefile 和 build.yml 均无需修改。

验证：iPhoneOS16.5 SDK 下核心和设置面板 arm64/arm64e 对象文件编译通过；渐变角度/比例/非法输入/颜色位置测试和彩边回归测试通过；旧设置及构建文件比较未变。未运行本版完整 Theos 打包、真机界面或偏好持久化端到端测试。

## 1.3.0 历史更新

上一版所有设置项、默认值、选色器、渐变动画、玻璃融合及兼容诊断均保留。新增“彩边玻璃”分组，默认关闭；不开启时走原来的渲染路径，不生成彩边位图。新功能只操作本插件的复制遮罩和附加图层，不修改原 Liquidify 二进制或图层参数。

开启后可设置冰蓝紫／粉金／原五色配色、字芯染色保留比例、彩边强度、宽度与高光。字芯比例只乘在当前染色浓度上，不覆盖旧配置。关闭新开关即可恢复旧浓度。只有原渐变总开关开启时附加功能才生效。

“显示时短暂高光”默认关闭，在新增图层从不可见状态重新附加时播放一次，不承诺每次物理亮屏触发。低电量模式或减少动态效果开启时不播放。新增彩边是拟玻璃装饰，不是新的真实折射引擎；边缘无法生成时保留旧渲染。

从 1.2.0 升级：替换 Tweak.xm、control、Preferences/LSGCRootListController.m、Preferences/Resources/Root.plist、Preferences/Resources/Info.plist；新增根目录 LSGCEdgeMath.h（必须，不能漏）。Makefile 和 .github/workflows/build.yml 不变。可一并上传 tests/edge_math_test.cpp 运行算法测试。

验证：两个架构的核心和设置控制器对象文件编译通过；彩边算法的透明字芯、内外轮廓、定向高光、越界与非法输入测试通过；原设置资源逐项比较未改变。尚未完成本版完整 GitHub 打包或真机视觉验证。以下为历史设计记录。

## 1.2.0 更新

玻璃融合模式默认开启，使用独立 `glassTint` 浓度（默认 0.32，上限 0.65），不继承旧版可能已设为 1 的普通浓度。复制遮罩的笔画边缘降低染色，尝试保留原玻璃边缘细节；若检测到同一父图层内的可见 rimView，则把染色层放在其下。不改原插件图层的透明度或滤镜。关闭玻璃模式可回到普通渐变。

本版为半透明色彩融合，不是新造折射着色器。原插件本身必须已显示玻璃效果；纯色/模糊背景也可能使折射难以察觉。不能保证仅靠染色就变成参考效果。

从 1.1.0 升级需替换：Tweak.xm、control、Preferences/Resources/Root.plist、Preferences/Resources/Info.plist。工作流和 Makefile 无需修改。安装后注销，先测试玻璃染色浓度 0.32。

最终核心和原设置控制器均通过 iPhoneOS16.5 SDK 下 arm64/arm64e 对象文件编译（-Wall -Wextra -Werror）；未完成完整打包及真机视觉测试。以下为 1.1.0 基础设计记录，安装本次包请以 1.2.0 为准。


## 本版做什么

这是为 Liquidify 的玻璃时钟添加五色渐变的独立伴随插件，不是第二个时钟。
包标识保持 com.minis.lockscreengradientclock，可覆盖旧版本。
保留已安装的 Liquidify；本工程不包含、不修改、不重新分发其二进制、字体或授权组件。

分析对象：用户提供的 com.charlieleung.liquidify，版本 1.3.7-4+repair.4，RootHide 包。
静态元数据确认存在 CCLiquidGlassLabel 及 textMaskLayer、setTextMaskLayer:、layoutSubviews、setCachedBuildFinished:、cc_maskAttributedString 等接口。
静态元数据不能证明设备上的锁屏实际一定走这些接口；因此本版包含诊断功能。

## 实现范围

- 只 Hook CCLiquidGlassLabel，不再 Hook 全局 UIView 或匹配 time/date 子串。
- 先确认该类在运行时继承 UILabel，再安装 Hook；兼容不同注入加载顺序。
- 默认要求标签处于锁屏祖先链，并且内容形态为时间。
- 优先复制原文字遮罩的绘制结果，不把原 mask 从原插件移走。
- 若遮罩不可读取，按原标签的字体、富文本、对齐重绘文字遮罩。
- 在现有玻璃效果上以可调浓度叠加渐变；不是修改玻璃折射着色器。
- 支持五色系统选色器、渐变方向、浓度、缓慢变色、即时设置通知。
- 跟随布局、文字、字体、遮罩及异步构建完成事件更新。
- 低频定时维护已发现标签的可见性；缓存遮罩，避免无变化时重复绘制。
- 禁用时只移除本插件图层，不清空原插件视图。

## GitHub 编译

将本目录内容（含隐藏的 .github）上传到仓库根目录，不再嵌套一层工程目录。
使用 .github/workflows/build.yml；保留用户提供的 macos-14 / RootHide Theos / iPhoneOS16.5 SDK 环境。
支持 rootless、roothide 两种打包方案；这不是已经完成两种设备的真机适配证明。
Actions 的 Verify packages 必须通过后才能上传安装包。

本地构建命令：

```sh
make clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless
make clean package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide
```

需要已配置的 RootHide Theos，以及 iPhoneOS16.5.sdk。最低部署目标 15.0。
iOS 15–17 是否能运行取决于设备的越狱注入环境和对应 Liquidify 实现；本版不声称全版本已验证。

## 安装测试

1. 保留原来的 88 液态玻璃插件，并开启其“锁屏时间”。
2. 安装对应环境的本工程 1.1.0（覆盖旧的渐变插件），注销。
3. 设置 → 锁屏时间渐变 → 开启“启用渐变叠加”。
4. 首次测试把渐变浓度设为 0.8；字体、字号和折射仍在原插件中设置。
5. 锁屏并亮屏查看一次，然后回到本面板点击“读取兼容诊断”。
6. 若未见变化，复制报告反馈。类未加载、Hook 未安装、时间标签为 0、锁屏范围为 0 分别代表不同问题，不要盲目反复重装。
7. 若时间标签存在而锁屏范围为 0，可临时关闭“严格限定锁屏层级”测试。这个开关可能让其他时间形态的 Liquidify 标签也变色，不建议作为长期默认。
8. 若有渐变但位置不对，将遮罩来源改为“同字体重绘”测试并反馈。

诊断不记录时钟文字、通知内容或其他屏幕文字，只记录计数、类名、渲染状态和祖先类名。
若要撤销兼容层，关闭“启用渐变叠加”或卸载本插件并注销，不需要卸载 Liquidify。

## 验证结果与限制

已通过：
- iPhoneOS16.5 SDK + Theos headers，Clang 19 对 Tweak.xm 的 Objective-C++ 编译。
- 设置控制器 Objective-C 编译。
- arm64、arm64e 两种架构，-Wall -Wextra -Werror，均生成 Mach-O 对象文件。
- plist 结构、设置入口对应关系和源代码包完整性检查。

未完成：
- GitHub Actions 的完整链接、签名与 deb 安装测试。
- 真机锁屏遮罩坐标、玻璃层顺序、AOD、景深、切换壁纸和其他插件冲突验证。
- 与最初截图完全一致的设置 UI。本版是系统设置中的五色选色与兼容参数页面，不冒充已还原截图中全部字重、宽度和圆润度控件。

原生 CALayer 的 renderInContext 对某些特殊图层、滤镜、3D 效果有局限；因此不能假设任何 Liquidify 遮罩都能直接截图，本版提供同字体备用遮罩。
