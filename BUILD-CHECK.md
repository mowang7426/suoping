# 本地验证记录 — 1.1.0

使用 iPhoneOS16.5.sdk、Theos headers、Alpine Clang 19.1.4。
目标 arm64-apple-ios15.0 与 arm64e-apple-ios15.0。
参数 -fobjc-arc -fblocks -c -Wall -Wextra -Werror。

Tweak.xm（Objective-C++）：两个目标均成功生成对象文件。
Preferences/LSGCRootListController.m（Objective-C）：两个目标均成功生成对象文件。

这验证了真实 SDK 下的语法、类型检查与对象代码生成，不等同于完整 Theos 链接、签名、GitHub Actions 运行、安装或真机视觉验收。
本压缩包不包含测试用 SDK、原插件二进制或提取的第三方资源。

静态依据：用户上传包的 Objective-C 类与方法元数据。本版本基于这些接口编写，未验证运行时调用链。
