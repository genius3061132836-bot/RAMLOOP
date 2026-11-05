# RAMLOOP

macOS 菜单栏内存监测工具。悬停打开玻璃卡片，用银色指针查看当前占用最高的两个应用。

<p align="center"><img src="Resources/Icon.png" width="160" alt="RAMLOOP"></p>

## 使用

需要 macOS 13 或更新版本。安装包包含 Apple Silicon 和 Intel 架构。

解压 RAMLOOP.zip，将 RAMLOOP.app 拖入“应用程序”并打开。鼠标在菜单栏芯片图标上停留约 0.3 秒会展开面板，移出后约 0.06–0.10 秒收起。点击菜单栏图标或面板图钉可固定面板。通过面板菜单或右键菜单退出。

当前使用本地 ad-hoc 签名，尚未完成 Apple Developer ID 签名和公证。下载后 macOS 可能拦截首次打开。确认来源后，可按系统提示进入“系统设置 → 隐私与安全 → 仍要打开”。

## 构建

在 macOS 上安装 Xcode Command Line Tools，使用支持当前源码的 Swift 编译器。项目已使用 Swift 6.3.3 构建验证。

```sh
xcode-select --install
./build.sh
open build/RAMLOOP.app
```

输出为 build/RAMLOOP.app 和 build/RAMLOOP.zip。只依赖系统 AppKit、SwiftUI 和 Darwin，无第三方运行时依赖。

## 数据与限制

- 面板打开时，系统内存每秒采样，应用排行每 3 秒更新。收起后系统内存每 3 秒采样，暂停应用排行采样。
- 系统已用内存使用 internal - purgeable + wired + compressor 页数估算。压力来自系统内存压力级别。
- 应用内存使用可读取进程的 physical footprint，按运行中前台应用的 bundle 路径归并。应用包之外的辅助服务、不可读取进程和系统后台进程可能不计入排行，因此与活动监视器可能不同。
- GB 和 MB 按二进制单位换算。两个表盘使用相同的动态量程。
- 运行时在本机读取数据，无网络请求、遥测或历史数据保存。
- 已在开发者及朋友的 Mac 上试用，尚未覆盖所有 macOS 版本和 Intel 硬件。

## 源码与资源

Sources/main.swift 包含完整应用实现。Resources 包含应用元数据和图标。图标由 AI 辅助生成，源 PNG 随项目提供。

## 许可证

MIT。详见 LICENSE。
