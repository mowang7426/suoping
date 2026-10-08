# 2.0.6 完整字形 / 实体填充 / 主时间独立外描边

## 2.0.5 的源码根因

1. `SnapshotText` 的镜像 UILabel 和 UIGraphics 画布均固定为原生 `label.bounds.size`。字体、kern 和冒号尺寸改变后没有按真实 glyph bearing/ink bounds 扩展画布，也没有 stroke/outset padding。UILabel 自身 backing store 的裁切已经发生在截图阶段；超采样只提高被裁切图的分辨率，放大 host 无法恢复缺失像素。
2. `InstallMask` / `dateHost.bounds` 继续强制原生标签尺寸。主时间默认 `clockScale=2.35`，乘以 width/height 和原生映射，可能进一步超过物理屏幕宽度。原来的 host 安全检查拒绝祖先裁切，但无法修复已经被截断的 bitmap。
3. 主时间只有一层 gradient+mask，`clockOpacity` 默认 0.32、设置上限 0.65；没有实体字芯底层或专属外描边。2.0.5 的独立时间/日期分支不调用 `BuildEdgeImages` / `InstallEdgeContents`，所以设置下方 `edgeEnabled/Width/Strength/Highlight/Core` 等不能给主时间生成描边，日期独立分支也没有生成这些内容。生成代码位于提前 return 后的旧 Liquidify 分支。`rimView` 只是旧插件宿主排序参考，不是独立主时间描边。
4. 若 edgeHost 存在，共用 `ApplyStyle` 原本还会把 glyph alpha 乘以 `edgeCore`（默认 .22）。不能把这个日期内轮廓逻辑移植成主时间实体描边。

## 实现

- 主时间以 CoreText 排版后的每个 run/glyph 真正路径绘制；保留 font/kern/colon font，使用真实路径 bounding box，归一化负 bearing、Y 轴方向。
- 完整画布：`max(sourceSize, inkSize + 2*(ceil(weight+outline)+2))`。填充、遮罩、dateHost 和 CAShapeLayer rim 使用同一逻辑画布，禁止挤回原生 label bounds。超采样预算包含 padding，限制单边 4096、总像素 8M。
- 实体渐变 glyph fill：所有主时间颜色 alpha 归一为 1，gradient 控制整体填充 alpha。默认 1；旧非零低透明度提升到至少 .85；显式 0 保留系统回退。描边不降低字芯透明度。
- 独立 `LSGC.ClockOutline` CAShapeLayer 位于填充后方，外描边宽度 `2*(weight+edgeWidth)`，圆角连接，实心 stroke/fill；不依赖柔软内轮廓 CPU contour。
- 新增主时间独立参数：`clockWeight` 0..4（默认 .8）、`clockEdgeEnabled` 默认 true、`clockEdgeWidth` .5..6（默认 1.5）、`clockEdgeStrength` 0..1（默认 1）、`clockEdgeColor` 默认白色。宽度为放大前逻辑点，屏幕粗细随主时间缩放。
- 原有 `edge*` 参数明确为日期/农历内轮廓；日期独立分支现已接入生成逻辑，日期签名仅包含日期 edge enabled/width。主时间完全忽略 date edgeCore 等参数。
- 保留已验证 `alpha-zero-wrapper-sibling` 宿主选择、限制 source wrapper 例外、仅 suppress native glyph 的提交顺序及失败回退。未放宽祖先透明度、mask、clip、3D 安全拒绝。
- 保留 convertPoint basis 一次映射、原生通知/缩放层级及用户 offsets；原生动画祖先变换没有重复叠加。完整时间超过物理屏幕宽度时，在计算出的 overlay transform 上额外应用一次等比例宽度适配；不修改源 transform 或 native geometry。偏移/纵向超大设置仍可能有意移出屏幕。
- 字形/画布仅在文本、字体、spacing、colon、采样或 weight/edge-width/edge-enable 签名变化时重建。布局事件只更新宿主几何；无轮询、timer 或 CADisplayLink。纯描边颜色/强度变更仅更新 layer style。
- 就绪检查要求启用描边时路径、非零宽度及挂载均存在；位图空、字体失败、宿主失败、alpha=0 等走原生回退。诊断增加 canvasSize、outlineWidth/Opacity/Attached/Ready。

## 可执行回归

`tests/clock_render_test.cpp`：108 组画布/字重/描边组合，完整 padding、实体 fill、非零 outline coverage、透明 bitmap 边框、零 alpha/空 mask/未挂载回退。使用面积覆盖而非像素中心点，覆盖 .5pt 亚像素描边。

`scripts/verify_clock_render.py`：检查真实 CoreText 路径、padded canvas、mask/host 一致、主时间专属 edge 控件连接、日期隔离、opaque colors、描边就绪门控、缓存和无轮询。

现有 7 个 C++ 测试（含本次新增）及 settings/startup/safety/host-order/diagnostics source contracts 全部保留，Actions 新增上述回归。包校验新增版本、ClockOutline、clockWeight、clockEdgeWidth 二进制标记。

这些是可执行数学/源码/包契约测试，不是 UIKit 真机视觉证明。

## 真机验收条件

- 使用成功的 alpha-zero-wrapper-sibling 层级设备安装匹配越狱方案的 2.0.6 包并重启 SpringBoard；默认 offsets=0，clockOpacity=1。
- 默认及自定义字体：00:00、08:08、11:11、23:59；spacing=-10/0/20；colon=.5/1/1.5；确认四个数字、冒号和上下外描边完整，无矩形裁切。
- clockWeight=0/.8/4、clockEdgeWidth=.5/1.5/6，观察字重与描边改变；clockEdgeStrength=0/1 和不同颜色确认独立轮廓有效；纯色和渐变都应有实心字芯。
- 日期 edgeWidth/Core/Strength 改变时主时间不变；主时间独立设置不改变日期。日期彩边开关在日期渐变开启时生效。
- 通知展开/收起、原生锁屏缩放/解锁、分钟切换、亮灭屏、旋转（若设备支持）、自定义字体切换；确认一次几何映射、无双倍 transform、无轮询。
- 关闭插件、缺失字体/损坏字体、零 clockOpacity（手工导入配置）、拒绝宿主：不得隐藏系统时间；诊断说明 native-glyph-pass。
- 极端 offset/height 可故意把字形移出物理屏幕，不能把这种物理越界误认为 bitmap 裁切；默认居中条件应完整。AOD 按既有低功耗 motion bit 降低整体亮度，并非正常亮屏低 alpha。
