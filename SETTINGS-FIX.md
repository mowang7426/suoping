# 1.0.1 设置入口修复说明

本版本修复设置面板的构建与打包，不代表渐变效果已完成真机验证。

## 更新仓库

请将压缩包中 LockScreenGradientClock 目录的内容放到仓库根目录，保留隐藏的 .github 目录。
不要在现有仓库中再套一层 LockScreenGradientClock 目录。

更新：
- Makefile（aggregate.mk、arm64/arm64e、16.5 SDK）
- Preferences/Makefile（arm64/arm64e、16.5 SDK）
- control（版本 1.0.1）
- .github/workflows/build.yml（安装包内容强校验）

新增：
- Preferences/Resources/Info.plist
- Preferences/Resources/Root.plist
- layout/Library/PreferenceLoader/Preferences/LockScreenGradientClockPrefs.plist
- scripts/verify_packages.py

删除旧文件：
- layout/entry.plist
- Preferences/entry.plist
- Preferences/Info.plist
- Preferences/Root.plist

## 安装和检查

重新运行 Actions，必须等待 Verify packages 通过后下载本次构建产物。
安装与你的越狱环境匹配的 rootless 或 roothide 包，确认版本是 1.0.1。
确认设备已安装相应环境版本的 PreferenceLoader，且允许插件注入设置应用。
关闭设置应用、完成注销后重新打开，查找“锁屏时间渐变”。
若仍没有入口，请提供设备系统版本、越狱工具/环境名称，以及此次 Verify packages 完整日志。

这里只完成源码结构、plist 与校验脚本静态检查；没有运行 Xcode 编译或真机测试。
