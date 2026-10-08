# 2.0.10 图像型原生时间/日期适配

目标：iPhone 11 / iOS 15.0.1 Rootless；两种安装方案均以 iOS 15.0 为最低部署目标。

严格识别 UILabel → SBUILegibilityLabel → SBFLockScreenDateView 时间链，及 subtitleDateView / alternateDateLabel 日期农历链。内部 hidden UILabel 仅提供文本，是否替换由可见原生 glyph、legibility 分支、窗口交集、实际挂载与有效 alpha 决定。

overlay 挂载到原生 _UILegibilityView.layer。时间沿用 CoreText/font 导入、五色渐变、几何、描边；日期/农历使用原生图像 alpha，不重排、不描边，坐标跟随可见 glyph。仿射基向量映射通过运行时共用函数测试，避免重复应用祖先变换。

仅使用空 CALayer.mask 租约抑制原生图像；不写原生 alpha / hidden / image / contents。系统更新 mask 后保存最新值，关闭、更新、失败或销毁时仅恢复自己仍持有的租约，外部新 mask 不覆盖。原生内容/文字/设置更新会撤销旧 overlay 和缓存，再按事件重建；连续布局只更新坐标，位图复用。

精确 tree、可见 glyph 或字体/alpha/挂载准备失败时保留原生显示；未知日期原生 mask、非完整 contentsRect、非直立 UIImage 暂不重绘，安全保底。iOS17 prominent 的 sibling-wrapper、date-only/no-edge 契约保持原有严格回归。构建/测试成功不等于实体锁屏像素验收；设置页隐藏窗口不作为视觉成功证据。

验证包括 C++ 角色/租约/缓存/旋转剪切测试、Python 集成契约，以及安装包版本、adapter 二进制标记、arm64/arm64e Mach-O 最低部署、Rootless 路径与动态库依赖检查。
