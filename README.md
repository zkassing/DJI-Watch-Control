# DJI Watch Control

DJI Watch Control 是一个运行在 Apple Watch 上的实验性相机控制 App，用于通过 BLE 连接 DJI Action 相机，在手腕上完成拍摄控制和状态查看。

这个项目的目标是让户外、骑行、滑雪、运动拍摄等场景里的常用操作更顺手：不用掏手机，也不用伸手摸相机，就能在手表上开始/停止录像、切换模式、触发快门，并查看相机状态。

## 功能

- 扫描并连接附近的 DJI Action 设备
- DJI R SDK over BLE 帧封装与解析
- 相机握手与协议连接状态显示
- 查询版本、订阅状态、切换视频/拍照模式
- 开始录像、停止录像、快门、休眠等快捷控制
- 查看电量、录制状态、剩余容量/时长、温度状态等相机信息
- 录像时从 Apple Watch 获取 GPS，并尝试向相机推送 GPS 数据

## 运行要求

- Xcode 26 或更新版本
- watchOS 26.0 或更新版本
- 支持独立 watchOS App 的 Apple Watch
- 支持 BLE 控制的 DJI Action 相机
- 一台用于签名和安装的 Apple 开发者账号

## 使用方式

1. Clone 仓库。
2. 用 Xcode 打开 `DJI BLE Control.xcodeproj`。
3. 在 Signing & Capabilities 中选择你自己的 Team。
4. 选择 `DJI BLE Control Watch App` scheme。
5. Destination 选择实体 Apple Watch。
6. 构建并运行。
7. 打开 App 后扫描 DJI 设备并连接。

如果 Xcode 提示模拟器 runtime 或 `MessagesApplicationStub` 相关错误，请确认当前选择的是实体 Apple Watch，而不是 iPhone Simulator、Apple Watch Simulator 或 `Any watchOS Device`。

## 权限说明

App 会请求以下权限：

- Bluetooth：用于扫描、连接和控制 DJI 相机。
- Location：用于在录像时获取 Apple Watch 的 GPS 信息，并尝试推送给相机。

项目不包含服务器，也不会上传你的蓝牙设备信息、定位信息或拍摄状态。

## 项目状态

这是一个个人实验项目，目前主要用于验证 Apple Watch 直接控制 DJI Action 相机的可行性。不同 DJI 机型、固件版本、BLE 协议行为可能存在差异，部分功能可能需要继续调试。

## 免责声明

本项目不是 DJI 官方项目，也不隶属于 DJI。项目中涉及的协议和命令仅用于学习、研究和个人设备控制实验。使用前请自行确认风险，避免在重要拍摄任务中依赖未经充分验证的控制逻辑。

## License

暂未指定 License。开源发布前建议补充明确的许可证，例如 MIT、Apache-2.0 或 GPL。
