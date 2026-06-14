//
//  DJIActionBLEManager.swift
//  DJI BLE Control Watch App
//
//  Created by Codex on 2026/5/1.
//

import CoreBluetooth
import CoreLocation
import Foundation
import Observation
import WatchKit

@Observable
@MainActor
final class DJIActionBLEManager: NSObject, CLLocationManagerDelegate {
    struct ControllerIdentity {
        let deviceID: UInt32
        let address: [UInt8]
        let firmwareVersion: UInt32

        static func load() -> ControllerIdentity {
            let defaults = UserDefaults.standard
            let deviceKey = "dji.controller.deviceID"
            let addressKey = "dji.controller.address"

            let deviceID: UInt32
            if let stored = defaults.object(forKey: deviceKey) as? NSNumber {
                deviceID = stored.uint32Value
            } else {
                let generated = UInt32.random(in: 0x10000000...0xEFFFFFFF)
                defaults.set(NSNumber(value: generated), forKey: deviceKey)
                deviceID = generated
            }

            let address: [UInt8]
            if let stored = defaults.data(forKey: addressKey), stored.count == 16 {
                address = Array(stored)
            } else {
                var generated = (0..<16).map { _ in UInt8(0x00) }
                for index in 0..<6 {
                    generated[index] = UInt8.random(in: 0x00...0xFF)
                }
                defaults.set(Data(generated), forKey: addressKey)
                address = generated
            }

            return ControllerIdentity(
                deviceID: deviceID,
                address: address,
                firmwareVersion: 0x00010000
            )
        }

        static func reset() -> ControllerIdentity {
            let defaults = UserDefaults.standard
            defaults.removeObject(forKey: "dji.controller.deviceID")
            defaults.removeObject(forKey: "dji.controller.address")
            return load()
        }
    }

    struct HandshakeProfile: Identifiable {
        let id: String
        let title: String
        let macAddressLength: UInt8
        let conidx: UInt8
        let verifyMode: UInt8
        let verifyData: UInt16?
        let firmwareVersion: UInt32?
        let deviceID: UInt32?
        let macAddress: [UInt8]?
        let usesRandomVerifyData: Bool

        static let all: [HandshakeProfile] = [
            HandshakeProfile(
                id: "first_pair_random",
                title: "随机配对码",
                macAddressLength: 0x06,
                conidx: 0x00,
                verifyMode: 0x00,
                verifyData: nil,
                firmwareVersion: 0x00000000,
                deviceID: 0x12345678,
                macAddress: [0x38, 0x34, 0x56, 0x78, 0x9A, 0xBC],
                usesRandomVerifyData: true
            ),
            HandshakeProfile(
                id: "first_pair_0000",
                title: "固定配对码 0000",
                macAddressLength: 0x06,
                conidx: 0x00,
                verifyMode: 0x00,
                verifyData: 0x0000,
                firmwareVersion: 0x00000000,
                deviceID: 0x12345678,
                macAddress: [0x38, 0x34, 0x56, 0x78, 0x9A, 0xBC],
                usesRandomVerifyData: false
            ),
            HandshakeProfile(
                id: "official_len6",
                title: "已配对 len6",
                macAddressLength: 0x06,
                conidx: 0x00,
                verifyMode: 0x02,
                verifyData: 0x0000,
                firmwareVersion: 0x00010000,
                deviceID: nil,
                macAddress: nil,
                usesRandomVerifyData: false
            ),
            HandshakeProfile(
                id: "official_len16",
                title: "已配对 len16",
                macAddressLength: 0x10,
                conidx: 0x00,
                verifyMode: 0x02,
                verifyData: 0x0000,
                firmwareVersion: 0x00010000,
                deviceID: nil,
                macAddress: nil,
                usesRandomVerifyData: false
            ),
            HandshakeProfile(
                id: "zero_fw",
                title: "固件版本 0",
                macAddressLength: 0x06,
                conidx: 0x00,
                verifyMode: 0x02,
                verifyData: 0x0000,
                firmwareVersion: 0x00000000,
                deviceID: nil,
                macAddress: nil,
                usesRandomVerifyData: false
            ),
            HandshakeProfile(
                id: "conidx_1",
                title: "连接索引 1",
                macAddressLength: 0x06,
                conidx: 0x01,
                verifyMode: 0x02,
                verifyData: 0x0000,
                firmwareVersion: 0x00010000,
                deviceID: nil,
                macAddress: nil,
                usesRandomVerifyData: false
            ),
            HandshakeProfile(
                id: "zero_device",
                title: "设备 ID 0",
                macAddressLength: 0x06,
                conidx: 0x00,
                verifyMode: 0x02,
                verifyData: 0x0000,
                firmwareVersion: 0x00010000,
                deviceID: 0x00000000,
                macAddress: nil,
                usesRandomVerifyData: false
            )
        ]
    }

    private enum HandshakeState: String {
        case idle = "未握手"
        case requestSent = "已发送连接请求"
        case waitingCameraChallenge = "等待相机挑战"
        case completed = "握手完成"
        case failed = "握手失败"
    }

    enum CameraMode: String {
        case video = "视频"
        case photo = "拍照"
    }

    struct CameraStatusSnapshot {
        var hasData = false
        var modeCode: UInt8 = 0
        var statusCode: UInt8 = 0
        var videoResolution: UInt8 = 0
        var fpsIndex: UInt8 = 0
        var eisMode: UInt8 = 0
        var recordTime: UInt16 = 0
        var remainCapacityMB: UInt32 = 0
        var remainPhotoCount: UInt32 = 0
        var remainTimeSeconds: UInt32 = 0
        var userMode: UInt8 = 0
        var powerMode: UInt8 = 0
        var nextModeCode: UInt8 = 0
        var temperatureState: UInt8 = 0
        var batteryPercentage: UInt8 = 0
        var modeName: String?
        var modeParameter: String?
        var updatedAt: Date?

        var isRecording: Bool {
            statusCode == 0x03 || statusCode == 0x05
        }

        var modeText: String {
            if let modeName, !modeName.isEmpty {
                return Self.localizedModeName(modeName)
            }

            return Self.modeName(for: modeCode)
        }

        var statusText: String {
            switch statusCode {
            case 0x00:
                return "屏幕关闭"
            case 0x01:
                return "待机取景"
            case 0x02:
                return "回放"
            case 0x03:
                return "拍摄中"
            case 0x05:
                return "预录制"
            default:
                return String(format: "未知 0x%02X", statusCode)
            }
        }

        var powerText: String {
            switch powerMode {
            case 0x00:
                return "正常"
            case 0x03:
                return "休眠"
            default:
                return String(format: "0x%02X", powerMode)
            }
        }

        var temperatureText: String {
            switch temperatureState {
            case 0x00:
                return "正常"
            case 0x01:
                return "偏热"
            case 0x02:
                return "过热限制"
            case 0x03:
                return "即将关机"
            default:
                return String(format: "0x%02X", temperatureState)
            }
        }

        var resolutionText: String {
            switch videoResolution {
            case 10:
                return "1080P"
            case 16:
                return "4K 16:9"
            case 45:
                return "2.7K 16:9"
            case 66:
                return "1080P 9:16"
            case 67:
                return "2.7K 9:16"
            case 95:
                return "2.7K 4:3"
            case 103:
                return "4K 4:3"
            case 109:
                return "4K 9:16"
            case 4:
                return "照片 L"
            case 3:
                return "照片 M"
            default:
                return String(format: "0x%02X", videoResolution)
            }
        }

        var fpsText: String {
            switch fpsIndex {
            case 1:
                return "24fps"
            case 2:
                return "25fps"
            case 3:
                return "30fps"
            case 4:
                return "48fps"
            case 5:
                return "50fps"
            case 6:
                return "60fps"
            case 7:
                return "120fps"
            case 8:
                return "240fps"
            case 10:
                return "100fps"
            case 19:
                return "200fps"
            default:
                return String(format: "0x%02X", fpsIndex)
            }
        }

        var eisText: String {
            switch eisMode {
            case 0:
                return "关闭"
            case 1:
                return "RS"
            case 2:
                return "HS"
            case 3:
                return "RS+"
            case 4:
                return "HB"
            default:
                return String(format: "0x%02X", eisMode)
            }
        }

        static func modeName(for code: UInt8) -> String {
            switch code {
            case 0x00:
                return "慢动作"
            case 0x01:
                return "视频"
            case 0x02:
                return "延时摄影"
            case 0x05:
                return "拍照"
            case 0x0A:
                return "运动延时"
            case 0x1A:
                return "直播"
            case 0x23:
                return "UVC 直播"
            case 0x28:
                return "超级夜景"
            case 0x34:
                return "人像模式"
            case 0x37:
                return "8K视频"
            default:
                return String(format: "模式 0x%02X", code)
            }
        }

        static func localizedModeName(_ rawName: String) -> String {
            let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            if let code = UInt8(trimmed.replacingOccurrences(of: "0x", with: ""), radix: 16) {
                return modeName(for: code)
            }

            let normalized = trimmed
                .lowercased()
                .replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: "-", with: " ")

            switch normalized {
            case "video":
                return "视频"
            case "8k", "8k video":
                return "8K视频"
            case "photo":
                return "拍照"
            case "portrait":
                return "人像模式"
            case "low light", "low light video", "super night", "supernight", "super night video":
                return "超级夜景"
            case "slow motion", "slowmo", "slow mo":
                return "慢动作"
            case "timelapse", "time lapse":
                return "延时摄影"
            case "hyperlapse", "hyper lapse":
                return "运动延时"
            case "live stream", "livestream":
                return "直播"
            case "uvc live stream", "uvc livestream":
                return "UVC 直播"
            case "subject tracking", "tracking":
                return "人物跟随"
            case "custom", "custom mode":
                return "自定义模式"
            case "custom 1", "custom mode 1":
                return "自定义模式 1"
            case "custom 2", "custom mode 2":
                return "自定义模式 2"
            case "custom 3", "custom mode 3":
                return "自定义模式 3"
            case "custom 4", "custom mode 4":
                return "自定义模式 4"
            case "custom 5", "custom mode 5":
                return "自定义模式 5"
            default:
                return rawName
            }
        }
    }

    struct CameraModeOption: Identifiable {
        let code: UInt8
        let title: String
        let subtitle: String
        let icon: String

        var id: String { "\(code)-\(title)" }
    }

    enum CaptureTransition: String {
        case idle
        case starting
        case stopping
    }

    private enum DJIUUID {
        static let service = CBUUID(string: "FFF0")
        static let notifyCharacteristic = CBUUID(string: "FFF4")
        static let writeCharacteristic = CBUUID(string: "FFF5")
    }

    private(set) var discoveredDevices: [BLEDevice] = []
    private(set) var isScanning = false
    private(set) var isConnecting = false
    private(set) var connectedPeripheralID: UUID?
    private(set) var activeCharacteristicDescription: String?
    private(set) var notificationCharacteristicDescription: String?
    private(set) var lastErrorMessage: String?
    private(set) var bluetoothStateText = "初始化中"
    private(set) var lastTransmittedFrame = ""
    private(set) var lastReceivedFrame = ""
    private(set) var lastProtocolSummary = ""
    private(set) var handshakeStatusText = HandshakeState.idle.rawValue
    private(set) var isProtocolConnected = false
    private(set) var pairingStatusText = "等待连接"
    private(set) var isReadyForHandshake = false
    private(set) var handshakeProfileTitle = HandshakeProfile.all[0].title
    private(set) var controllerIdentitySummary = ""
    private(set) var pairingCodeText = "未生成"
    private(set) var currentMode: CameraMode = .video
    private(set) var isRecording = false
    private(set) var captureTransition: CaptureTransition = .idle
    private(set) var captureFeedbackText = "待机"
    private(set) var cameraStatus = CameraStatusSnapshot()
    var isTakingPhoto = false
    var isGPSEnabled = false
    private(set) var gpsStatusText = "GPS 未连接"
    private(set) var currentLatitude: Double?
    private(set) var currentLongitude: Double?
    private(set) var currentAltitude: Double?
    private(set) var currentSpeed: Double?
    private(set) var currentBearing: Double?
    private(set) var totalDistance: Double = 0
    private(set) var currentPace: Double?
    private(set) var currentSlope: Double?
    private var previousLocation: CLLocation?
    private var previousLocationTimestamp: Date?
    private var locationManager: CLLocationManager?
    private var currentLocation: CLLocation?
    private var gpsPushTimer: Timer?
    private var ignoreRecordingStatusUntil: Date?
    private var lastHapticTimes: [String: Date] = [:]

    private let lastConnectedDeviceKey = "dji.last.connected.device"
    private var centralManager: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var writableCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var nextSequence: UInt16 = 1
    private var controllerIdentity = ControllerIdentity.load()
    private var selectedHandshakeProfileIndex = 0 {
        didSet {
            handshakeProfileTitle = HandshakeProfile.all[selectedHandshakeProfileIndex].title
        }
    }
    private var handshakeState: HandshakeState = .idle {
        didSet {
            handshakeStatusText = handshakeState.rawValue
        }
    }

    override init() {
        super.init()
        controllerIdentitySummary = makeIdentitySummary()
        centralManager = CBCentralManager(delegate: self, queue: nil)
        locationManager = CLLocationManager()
        locationManager?.delegate = self
        locationManager?.desiredAccuracy = kCLLocationAccuracyBest
        locationManager?.distanceFilter = kCLDistanceFilterNone
        autoReconnect()
    }

    private func autoReconnect() {
        guard let storedIDString = UserDefaults.standard.string(forKey: lastConnectedDeviceKey),
              let storedUUID = UUID(uuidString: storedIDString) else {
            return
        }

        let foundPeripherals = centralManager.retrievePeripherals(withIdentifiers: [storedUUID])
        if let peripheral = foundPeripherals.first {
            peripherals[peripheral.identifier] = peripheral
            Task { @MainActor in
                self.connect(to: peripheral.identifier)
            }
        }
    }

    var canScan: Bool {
        centralManager.state == .poweredOn
    }

    var connectedDeviceName: String {
        guard let id = connectedPeripheralID else {
            return "未连接"
        }

        if let device = discoveredDevices.first(where: { $0.id == id }) {
            return device.displayName
        }

        if let peripheral = peripherals[id] {
            return peripheral.name ?? "未知设备"
        }

        return "已连接"
    }

    var isReadyForCommands: Bool {
        connectedPeripheralID != nil && writableCharacteristic != nil && isProtocolConnected
    }

    var isCapturePending: Bool {
        captureTransition != .idle
    }

    var modeOptions: [CameraModeOption] {
        var options = [
            CameraModeOption(code: 0x01, title: "视频", subtitle: "常规视频录制", icon: "video.fill"),
            CameraModeOption(code: 0x05, title: "拍照", subtitle: "单张照片", icon: "camera.fill"),
            CameraModeOption(code: 0x28, title: "超级夜景", subtitle: "暗光视频", icon: "moon.stars.fill"),
            CameraModeOption(code: 0x00, title: "慢动作", subtitle: "高帧率慢动作", icon: "hare.fill"),
            CameraModeOption(code: 0x02, title: "延时摄影", subtitle: "固定机位延时", icon: "timer"),
            CameraModeOption(code: 0x0A, title: "运动延时", subtitle: "Hyperlapse", icon: "figure.run")
        ]

        if cameraStatus.hasData, cameraStatus.userMode > 0 {
            let customTitle = cameraStatus.modeText.hasPrefix("自定义")
                ? cameraStatus.modeText
                : "自定义模式 \(cameraStatus.userMode)"
            options.insert(
                CameraModeOption(
                    code: cameraStatus.modeCode,
                    title: customTitle,
                    subtitle: "相机当前自定义模式",
                    icon: "slider.horizontal.3"
                ),
                at: 0
            )
        }

        return options
    }

    var connectionSummary: String {
        if isProtocolConnected {
            return "遥控器已就绪"
        }

        if connectedPeripheralID != nil {
            return isReadyForHandshake ? "等待协议握手" : "蓝牙已连接"
        }

        return isScanning ? "正在搜索腕拍" : "未连接"
    }

    func toggleScan() {
        isScanning ? stopScan() : startScan()
    }

    func startScan() {
        guard canScan else {
            lastErrorMessage = "蓝牙未开启或当前设备不支持蓝牙。"
            return
        }

        lastErrorMessage = nil
        discoveredDevices.removeAll()
        peripherals.removeAll()
        writableCharacteristic = nil
        notifyCharacteristic = nil
        activeCharacteristicDescription = nil
        notificationCharacteristicDescription = nil
        lastTransmittedFrame = ""
        lastReceivedFrame = ""
        lastProtocolSummary = ""
        isProtocolConnected = false
        isReadyForHandshake = false
        pairingStatusText = "等待连接"
        handshakeState = .idle
        isScanning = true
        centralManager.scanForPeripherals(withServices: [DJIUUID.service], options: [
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ])
    }

    func stopScan() {
        centralManager.stopScan()
        isScanning = false
    }

    func connect(to id: UUID) {
        guard let peripheral = peripherals[id] else {
            if let peripheral = centralManager.retrievePeripherals(withIdentifiers: [id]).first {
                peripherals[id] = peripheral
                performConnect(peripheral: peripheral)
            } else {
                lastErrorMessage = "找不到目标蓝牙设备。"
            }
            return
        }

        performConnect(peripheral: peripheral)
    }

    private func performConnect(peripheral: CBPeripheral) {
        lastErrorMessage = nil
        writableCharacteristic = nil
        notifyCharacteristic = nil
        activeCharacteristicDescription = nil
        notificationCharacteristicDescription = nil
        lastProtocolSummary = ""
        lastTransmittedFrame = ""
        lastReceivedFrame = ""
        isProtocolConnected = false
        isReadyForHandshake = false
        isRecording = false
        pairingStatusText = "连接中"
        handshakeState = .idle
        isConnecting = true
        stopScan()
        centralManager.connect(peripheral, options: nil)
    }

    func beginHandshake() {
        guard let _ = connectedPeripheralID,
              writableCharacteristic != nil else {
            lastErrorMessage = "请先连接 DJI 相机。"
            return
        }

        guard isReadyForHandshake else {
            lastErrorMessage = "请先完成系统蓝牙配对；如果看到验证码 0000，请先在手表或手机上确认。"
            return
        }

        let profile = selectedHandshakeProfile
        let verifyData = profile.usesRandomVerifyData ? UInt16.random(in: 0...9999) : (profile.verifyData ?? 0)
        pairingCodeText = String(format: "%04d", verifyData)
        let request = makeConnectionRequestPayload(profile: profile, verifyData: verifyData)
        print("[DJI BLE][HS] profile=\(profile.title) verifyCode=\(pairingCodeText) identity=\(controllerIdentitySummary)")
        lastErrorMessage = nil
        sendRawFrame(
            commandSet: 0x00,
            commandID: 0x19,
            commandType: .waitResult,
            payload: request
        )
        isProtocolConnected = false
        handshakeState = .requestSent
    }

    func selectNextHandshakeProfile() {
        selectedHandshakeProfileIndex = (selectedHandshakeProfileIndex + 1) % HandshakeProfile.all.count
        handshakeState = .idle
        isProtocolConnected = false
        pairingCodeText = "未生成"
        lastErrorMessage = "已切换握手配置：\(handshakeProfileTitle)"
    }

    func resetControllerIdentity() {
        controllerIdentity = ControllerIdentity.reset()
        controllerIdentitySummary = makeIdentitySummary()
        handshakeState = .idle
        isProtocolConnected = false
        pairingCodeText = "未生成"
        lastErrorMessage = "已重置控制器身份，请让腕拍忘记旧蓝牙设备后重新配对。"
    }

    func disconnect() {
        guard let peripheralID = connectedPeripheralID,
              let peripheral = peripherals[peripheralID] else {
            return
        }
        centralManager.cancelPeripheralConnection(peripheral)
    }

    func send(command: DJIActionCommandPreset) {
        guard isProtocolConnected else {
            lastErrorMessage = "请先完成协议握手。"
            playHaptic(.failure)
            return
        }

        if command == .startRecording {
            ignoreRecordingStatusUntil = nil
            captureTransition = .starting
            captureFeedbackText = "正在等待相机开始录制..."
            scheduleCaptureTimeout(for: .starting)
        } else if command == .stopRecording {
            ignoreRecordingStatusUntil = Date().addingTimeInterval(3.0)
            captureTransition = .stopping
            captureFeedbackText = "正在等待相机停止录制..."
            scheduleCaptureTimeout(for: .stopping)
        } else if command == .cameraSleep {
            playHaptic(.click)
        }

        sendRawFrame(
            commandSet: command.commandSet,
            commandID: command.commandID,
            commandType: command.commandType,
            payload: command.payload
        )
    }

    func switchMode(to option: CameraModeOption) {
        switchMode(to: option.code)
    }

    func switchMode(to modeCode: UInt8) {
        guard isProtocolConnected else {
            lastErrorMessage = "请先完成协议握手。"
            playHaptic(.failure)
            return
        }

        lastErrorMessage = "正在切换到 \(CameraStatusSnapshot.modeName(for: modeCode))..."
        playHaptic(.click)
        sendRawFrame(
            commandSet: 0x1D,
            commandID: 0x04,
            commandType: .responseOrNot,
            payload: modeSwitchPayload(mode: modeCode)
        )
    }

    func capturePhoto() {
        guard isProtocolConnected else {
            lastErrorMessage = "请先完成协议握手。"
            playHaptic(.failure)
            return
        }

        isTakingPhoto = true
        playHaptic(.click)
        send(command: .switchToPhoto)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.send(command: .startRecording)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.isTakingPhoto = false
            }
        }
    }

    private func startGPSPush() {
        if gpsPushTimer != nil {
            startGPSTracking()
            return
        }

        totalDistance = 0
        previousLocation = nil
        previousLocationTimestamp = nil
        currentBearing = nil
        currentPace = nil
        currentSlope = nil

        startGPSTracking()

        gpsPushTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pushCurrentGPSData()
            }
        }
    }

    private func stopGPSPush() {
        gpsPushTimer?.invalidate()
        gpsPushTimer = nil
        stopGPSTracking()
    }

    private func startGPSTracking() {
        guard let locationManager else { return }

        switch locationManager.authorizationStatus {
        case .notDetermined:
            gpsStatusText = "GPS 等待授权"
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            isGPSEnabled = true
            gpsStatusText = currentLocation == nil ? "GPS 定位中" : gpsStatusText
            locationManager.startUpdatingLocation()
        case .denied, .restricted:
            isGPSEnabled = false
            gpsStatusText = "GPS 未连接"
            lastErrorMessage = "GPS权限被拒绝，请在设置中开启"
        @unknown default:
            gpsStatusText = "GPS 状态未知"
        }
    }

    private func stopGPSTracking() {
        locationManager?.stopUpdatingLocation()
        isGPSEnabled = false
        gpsStatusText = "GPS 未连接"
    }

    private func scheduleCaptureTimeout(for transition: CaptureTransition) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
            guard let self, self.captureTransition == transition else { return }
            self.captureTransition = .idle
            self.captureFeedbackText = transition == .starting ? "未收到开始确认" : "未收到停止确认"
            self.playHaptic(.failure)
        }
    }

    private func playHaptic(_ type: WKHapticType, key: String? = nil, minimumInterval: TimeInterval = 2.0) {
        let hapticKey = key ?? "\(type.rawValue)"
        let now = Date()
        if let lastPlayed = lastHapticTimes[hapticKey],
           now.timeIntervalSince(lastPlayed) < minimumInterval {
            return
        }

        lastHapticTimes[hapticKey] = now
        WKInterfaceDevice.current().play(type)
    }

    private func modeSwitchPayload(mode: UInt8) -> Data {
        var data = Data()
        data.appendLE(UInt32(0xFF330000))
        data.append(mode)
        data.append(contentsOf: [0x01, 0x47, 0x39, 0x36])
        return data
    }

    private func pushCurrentGPSData() {
        guard isProtocolConnected, let location = currentLocation else { return }

        let payload = buildGPSPayload(from: location)
        sendRawFrame(
            commandSet: 0x00,
            commandID: 0x17,
            commandType: .noResponse,
            payload: payload
        )
    }

    private func buildGPSPayload(from location: CLLocation) -> Data {
        var payload = Data()

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let date = Date()
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = Int32(components.year ?? 2024)
        let month = Int32(components.month ?? 1)
        let day = Int32(components.day ?? 1)
        let yearMonthDay = year * 10000 + month * 100 + day
        payload.appendLE(yearMonthDay)

        let hour = Int32(((components.hour ?? 0) + 8) % 24)
        let minute = Int32(components.minute ?? 0)
        let second = Int32(components.second ?? 0)
        let hourMinuteSecond = hour * 10000 + minute * 100 + second
        payload.appendLE(hourMinuteSecond)

        let longitude = Int32(location.coordinate.longitude * 10_000_000)
        payload.appendLE(longitude)

        let latitude = Int32(location.coordinate.latitude * 10_000_000)
        payload.appendLE(latitude)

        let height = Int32(location.altitude * 1000)
        payload.appendLE(height)

        let velocity = gpsVelocityComponents(for: location)
        payload.appendLE(velocity.northCmS.bitPattern)
        payload.appendLE(velocity.eastCmS.bitPattern)
        payload.appendLE(velocity.downCmS.bitPattern)

        let verticalAccuracy = UInt32(max(0, location.verticalAccuracy) * 1000)
        payload.appendLE(verticalAccuracy)

        let horizontalAccuracy = UInt32(max(0, location.horizontalAccuracy) * 1000)
        payload.appendLE(horizontalAccuracy)

        let speedAccuracy = UInt32(max(10, velocity.speedAccuracyCmS))
        payload.appendLE(speedAccuracy)

        let satelliteNumber = UInt32(8)
        payload.appendLE(satelliteNumber)

        return payload
    }

    private func gpsVelocityComponents(for location: CLLocation) -> (northCmS: Float, eastCmS: Float, downCmS: Float, speedAccuracyCmS: Double) {
        var speedMS = location.speed >= 0 ? location.speed : 0
        var courseDegrees = location.course >= 0 ? location.course : currentBearing
        var downMS = 0.0

        if let previous = previousLocation {
            let elapsed = location.timestamp.timeIntervalSince(previous.timestamp)
            if elapsed > 0.05, elapsed < 10 {
                let distance = location.distance(from: previous)
                if speedMS <= 0, distance > 0.2 {
                    speedMS = distance / elapsed
                }

                if courseDegrees == nil, distance > 0.2 {
                    courseDegrees = bearing(from: previous.coordinate, to: location.coordinate)
                }

                let altitudeDelta = location.altitude - previous.altitude
                if abs(altitudeDelta) < 100 {
                    downMS = -altitudeDelta / elapsed
                }
            }
        }

        let speedCmS = Float(max(0, speedMS) * 100)
        let courseRad = Float((courseDegrees ?? 0) * .pi / 180)
        let north = cos(courseRad) * speedCmS
        let east = sin(courseRad) * speedCmS
        let down = Float(downMS * 100)
        let accuracy = location.speedAccuracy >= 0 ? location.speedAccuracy * 100 : 10

        return (north, east, down, accuracy)
    }

    private func bearing(from start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> Double {
        let startLat = start.latitude * .pi / 180
        let startLon = start.longitude * .pi / 180
        let endLat = end.latitude * .pi / 180
        let endLon = end.longitude * .pi / 180
        let deltaLon = endLon - startLon

        let y = sin(deltaLon) * cos(endLat)
        let x = cos(startLat) * sin(endLat) - sin(startLat) * cos(endLat) * cos(deltaLon)
        let degrees = atan2(y, x) * 180 / .pi
        return degrees >= 0 ? degrees : degrees + 360
    }

    private func sendRawFrame(
        commandSet: UInt8,
        commandID: UInt8,
        commandType: DJIRSdkCommandType,
        payload: Data,
        sequence overrideSequence: UInt16? = nil
    ) {
        guard let peripheralID = connectedPeripheralID,
              let peripheral = peripherals[peripheralID],
              let characteristic = writableCharacteristic else {
            lastErrorMessage = "尚未建立可写入的蓝牙连接。"
            return
        }

        let frame = DJIRSdkProtocol.makeFrame(
            commandSet: commandSet,
            commandID: commandID,
            commandType: commandType,
            payload: payload,
            sequence: overrideSequence ?? nextSequenceValue()
        )
        let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
        lastTransmittedFrame = DJIRSdkProtocol.hexString(for: frame)
        print("[DJI BLE][TX] \(lastTransmittedFrame)")
        peripheral.writeValue(frame, for: characteristic, type: writeType)
    }

    private func updateBluetoothState(_ state: CBManagerState) {
        bluetoothStateText = switch state {
        case .unknown: "未知"
        case .resetting: "重置中"
        case .unsupported: "设备不支持"
        case .unauthorized: "没有权限"
        case .poweredOff: "已关闭"
        case .poweredOn: "已开启"
        @unknown default: "未识别状态"
        }
    }

    private func appendOrUpdate(_ peripheral: CBPeripheral, rssi: NSNumber) {
        let name = peripheral.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let device = BLEDevice(
            id: peripheral.identifier,
            name: name,
            rssi: rssi.intValue
        )

        if let index = discoveredDevices.firstIndex(where: { $0.id == device.id }) {
            discoveredDevices[index] = device
        } else {
            discoveredDevices.append(device)
            discoveredDevices.sort { $0.rssi > $1.rssi }
        }
    }

    private func nextSequenceValue() -> UInt16 {
        defer { nextSequence &+= 1 }
        return nextSequence
    }

    private var selectedHandshakeProfile: HandshakeProfile {
        HandshakeProfile.all[selectedHandshakeProfileIndex]
    }

    private func makeIdentitySummary() -> String {
        let mac = controllerIdentity.address.prefix(6)
            .map { String(format: "%02X", $0) }
            .joined(separator: ":")
        return String(format: "ID 0x%08X · %@", controllerIdentity.deviceID, mac)
    }

    private func updateProtocolSummary(with data: Data) {
        guard let summary = DJIRSdkProtocol.parseSummary(from: data) else {
            lastProtocolSummary = "收到的数据不是合法的 DJI R SDK 帧"
            return
        }

        lastProtocolSummary = String(
            format: "SEQ 0x%04X · CmdType 0x%02X · CmdSet 0x%02X · CmdID 0x%02X",
            summary.sequence,
            summary.commandType,
            summary.commandSet,
            summary.commandID
        )
    }

    private func makeConnectionRequestPayload(profile: HandshakeProfile, verifyData: UInt16) -> Data {
        var data = Data()
        data.appendLE(profile.deviceID ?? controllerIdentity.deviceID)
        data.append(profile.macAddressLength)
        data.append(contentsOf: paddedMacAddress(for: profile))
        data.appendLE(profile.firmwareVersion ?? controllerIdentity.firmwareVersion)
        data.append(profile.conidx)
        data.append(profile.verifyMode)
        data.appendLE(verifyData)
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        return data
    }

    private func paddedMacAddress(for profile: HandshakeProfile) -> [UInt8] {
        var address = Array((profile.macAddress ?? Array(controllerIdentity.address.prefix(6))).prefix(16))
        if address.count < 16 {
            address.append(contentsOf: Array(repeating: 0x00, count: 16 - address.count))
        }

        return address
    }

    private func makeConnectionResponsePayload(cameraReserved: UInt8) -> Data {
        var data = Data()
        data.appendLE(controllerIdentity.deviceID)
        data.append(0x00)
        data.append(contentsOf: [cameraReserved, 0x00, 0x00, 0x00])
        return data
    }

    private func handleIncomingFrame(_ frame: DJIRSdkFrame) {
        if frame.commandSet == 0x00 && frame.commandID == 0x19 {
            handleHandshakeFrame(frame)
        } else if frame.commandSet == 0x1D && frame.commandID == 0x05 {
            handleStatusSubscription(frame)
        } else if frame.commandSet == 0x1D && frame.commandID == 0x02 {
            handleCameraStatusPush(frame)
        } else if frame.commandSet == 0x1D && frame.commandID == 0x06 {
            handleNewCameraStatusPush(frame)
        }
    }

    private func handleStatusSubscription(_ frame: DJIRSdkFrame) {
        guard frame.payload.count > 7 else { return }
        let workMode = frame.payload[7]
        switch workMode {
        case 0x01, 0x02:
            currentMode = .video
        case 0x05, 0x06:
            currentMode = .photo
        default:
            break
        }
    }

    private func handleCameraStatusPush(_ frame: DJIRSdkFrame) {
        guard frame.payload.count >= 38 else {
            return
        }

        var status = cameraStatus
        status.hasData = true
        status.modeCode = frame.payload[0]
        status.statusCode = frame.payload[1]
        status.videoResolution = frame.payload[2]
        status.fpsIndex = frame.payload[3]
        status.eisMode = frame.payload[4]
        status.recordTime = frame.payload.leUInt16(at: 5)
        status.remainCapacityMB = frame.payload.leUInt32(at: 15)
        status.remainPhotoCount = frame.payload.leUInt32(at: 19)
        status.remainTimeSeconds = frame.payload.leUInt32(at: 23)
        status.userMode = frame.payload[27]
        status.powerMode = frame.payload[28]
        status.nextModeCode = frame.payload[29]
        status.temperatureState = frame.payload[30]
        status.batteryPercentage = min(frame.payload[37], 100)
        status.updatedAt = Date()
        cameraStatus = status

        currentMode = status.modeCode == 0x05 ? .photo : .video
        updateRecordingStateFromCamera(status.isRecording && !isTakingPhoto)
    }

    private func updateRecordingStateFromCamera(_ cameraSaysRecording: Bool) {
        if cameraSaysRecording {
            if let ignoreRecordingStatusUntil, Date() < ignoreRecordingStatusUntil {
                return
            }

            ignoreRecordingStatusUntil = nil
            let shouldConfirmStart = !isRecording || captureTransition == .starting
            captureTransition = .idle
            captureFeedbackText = "相机已开始录制"
            if shouldConfirmStart {
                playHaptic(.start, key: "recording-start", minimumInterval: 3.0)
            }
            isRecording = true
            startGPSPush()
        } else {
            ignoreRecordingStatusUntil = nil
            if captureTransition == .stopping || isRecording {
                captureFeedbackText = "相机已停止录制"
                playHaptic(.stop, key: "recording-stop", minimumInterval: 3.0)
            } else if captureTransition == .starting {
                captureFeedbackText = "等待相机开始录制"
            } else {
                captureFeedbackText = "待机"
            }
            if captureTransition != .starting {
                captureTransition = .idle
            }
            isRecording = false
            stopGPSPush()
        }
    }

    private func handleNewCameraStatusPush(_ frame: DJIRSdkFrame) {
        guard frame.payload.count >= 46 else {
            return
        }

        var status = cameraStatus
        let modeNameLength = min(Int(frame.payload[1]), 20)
        let modeNameStart = 2
        let modeNameEnd = modeNameStart + modeNameLength
        status.modeName = String(bytes: frame.payload[modeNameStart..<modeNameEnd], encoding: .ascii)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let paramLength = min(Int(frame.payload[24]), 20)
        let paramStart = 25
        let paramEnd = paramStart + paramLength
        status.modeParameter = String(bytes: frame.payload[paramStart..<paramEnd], encoding: .ascii)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        status.updatedAt = Date()
        cameraStatus = status
    }

    private func handleHandshakeFrame(_ frame: DJIRSdkFrame) {
        print("[DJI BLE][HS] type=0x\(String(format: "%02X", frame.commandType)) payloadLen=\(frame.payload.count) payload=\(DJIRSdkProtocol.hexString(for: frame.payload))")

        if frame.commandType >= 0x20 {
            let retCode = frame.payload.count > 4 ? frame.payload[4] : 0xFF
            if retCode == 0x00 {
                handshakeState = .waitingCameraChallenge
                pairingStatusText = "相机已接受配对"
                lastErrorMessage = nil
            } else {
                handshakeState = .failed
                pairingStatusText = "相机拒绝配对"
                lastErrorMessage = "相机拒绝 \(handshakeProfileTitle)，返回码 0x\(String(format: "%02X", retCode))。请切换握手配置后重试。"
                playHaptic(.failure)
            }
            return
        }

        guard frame.payload.count >= 18 else {
            handshakeState = .failed
            lastErrorMessage = "收到的握手数据长度不正确。"
            playHaptic(.failure)
            return
        }

        let verifyMode = frame.payload[26]
        let verifyData = UInt16(frame.payload[27]) | (UInt16(frame.payload[28]) << 8)
        guard verifyMode == 0x02, verifyData == 0x0000 else {
            handshakeState = .failed
            lastErrorMessage = "验证参数不匹配: mode=0x\(String(format: "%02X", verifyMode)) data=0x\(String(format: "%04X", verifyData))"
            playHaptic(.failure)
            return
        }

        let cameraReserved = frame.payload.count > 29 ? frame.payload[29] : 0x00
        let responsePayload = makeConnectionResponsePayload(cameraReserved: cameraReserved)
        sendRawFrame(
            commandSet: 0x00,
            commandID: 0x19,
            commandType: .ackNoResponse,
            payload: responsePayload,
            sequence: frame.sequence
        )

        isProtocolConnected = true
        handshakeState = .completed
        pairingStatusText = "遥控器已就绪"
        lastErrorMessage = nil
        playHaptic(.success)
        send(command: .subscribeStatus)
    }
}

extension DJIActionBLEManager: CBCentralManagerDelegate {
    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            updateBluetoothState(central.state)
            if central.state == .poweredOn {
                autoReconnect()
            } else {
                stopScan()
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        Task { @MainActor in
            peripherals[peripheral.identifier] = peripheral
            let looksLikeDJI = (peripheral.name?.localizedCaseInsensitiveContains("DJI") ?? false)
                || (peripheral.name?.localizedCaseInsensitiveContains("Osmo") ?? false)
                || ((advertisementData[CBAdvertisementDataLocalNameKey] as? String)?.localizedCaseInsensitiveContains("DJI") ?? false)

            if looksLikeDJI {
                appendOrUpdate(peripheral, rssi: RSSI)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            isConnecting = false
            connectedPeripheralID = peripheral.identifier
            UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: lastConnectedDeviceKey)
            peripheral.delegate = self
            pairingStatusText = "已连接，读取服务中"
            peripheral.discoverServices([DJIUUID.service])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            isConnecting = false
            lastErrorMessage = error?.localizedDescription ?? "连接失败。"
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            if connectedPeripheralID == peripheral.identifier {
                connectedPeripheralID = nil
                writableCharacteristic = nil
                notifyCharacteristic = nil
                activeCharacteristicDescription = nil
                notificationCharacteristicDescription = nil
                isProtocolConnected = false
                isReadyForHandshake = false
                isRecording = false
                pairingStatusText = "已断开"
                handshakeState = .idle
            }

            if let error {
                lastErrorMessage = "设备已断开：\(error.localizedDescription)"
            }
        }
    }
}

extension DJIActionBLEManager: CBPeripheralDelegate {
    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            if let error {
                lastErrorMessage = "读取服务失败：\(error.localizedDescription)"
                return
            }

            peripheral.services?.forEach { service in
                guard service.uuid == DJIUUID.service else {
                    return
                }

                peripheral.discoverCharacteristics([DJIUUID.notifyCharacteristic, DJIUUID.writeCharacteristic], for: service)
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                lastErrorMessage = "读取特征失败：\(error.localizedDescription)"
                return
            }

            service.characteristics?.forEach { characteristic in
                if characteristic.uuid == DJIUUID.writeCharacteristic {
                    writableCharacteristic = characteristic
                    activeCharacteristicDescription = "\(service.uuid.uuidString) / \(characteristic.uuid.uuidString)"
                }

                if characteristic.uuid == DJIUUID.notifyCharacteristic {
                    notifyCharacteristic = characteristic
                    notificationCharacteristicDescription = "\(service.uuid.uuidString) / \(characteristic.uuid.uuidString)"
                    peripheral.setNotifyValue(true, for: characteristic)
                }
            }

            if writableCharacteristic != nil, notifyCharacteristic != nil {
                isReadyForHandshake = true
                pairingStatusText = "自动握手中..."
                beginHandshake()
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                lastErrorMessage = "命令发送失败：\(error.localizedDescription)"
                playHaptic(.failure)
            } else {
                lastErrorMessage = nil
            }
        }
    }

    nonisolated func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                lastErrorMessage = "读取通知失败：\(error.localizedDescription)"
                return
            }

            guard let data = characteristic.value else {
                return
            }

            lastReceivedFrame = DJIRSdkProtocol.hexString(for: data)
            print("[DJI BLE][RX] \(lastReceivedFrame)")
            updateProtocolSummary(with: data)
            if let frame = DJIRSdkProtocol.parseFrame(from: data) {
                handleIncomingFrame(frame)
            }
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            if let error {
                lastErrorMessage = "启用通知失败：\(error.localizedDescription)"
                return
            }

            if characteristic.uuid == DJIUUID.notifyCharacteristic, characteristic.isNotifying {
                pairingStatusText = "通知已启用，可先完成系统配对"
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        if let prev = previousLocation {
            previousLocationTimestamp = prev.timestamp
        }

        currentBearing = location.course >= 0 ? location.course : nil

        if let previous = previousLocation {
            let distance = location.distance(from: previous)
            totalDistance += distance

            let altitudeDiff = location.altitude - previous.altitude
            let distanceForSlope = max(distance, 1.0)
            currentSlope = (altitudeDiff / distanceForSlope) * 100
        }

        if let speed = currentSpeed, speed > 0 {
            currentPace = 1000.0 / speed
        } else {
            currentPace = nil
        }

        previousLocation = currentLocation
        currentLocation = location
        currentLatitude = location.coordinate.latitude
        currentLongitude = location.coordinate.longitude
        currentAltitude = location.altitude
        currentSpeed = max(0, location.speed)
        gpsStatusText = signalStrengthText(for: location.horizontalAccuracy)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        lastErrorMessage = "GPS定位失败：\(error.localizedDescription)"
        playHaptic(.failure)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            if isRecording {
                isGPSEnabled = true
                gpsStatusText = currentLocation == nil ? "GPS 定位中" : "GPS 已连接"
                locationManager?.startUpdatingLocation()
            } else {
                stopGPSTracking()
            }
        case .denied, .restricted:
            isGPSEnabled = false
            gpsStatusText = "GPS 未连接"
            lastErrorMessage = "GPS权限被拒绝，请在设置中开启"
            playHaptic(.failure)
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    private func signalStrengthText(for accuracy: CLLocationAccuracy) -> String {
        if accuracy < 0 {
            return "GPS 无信号"
        } else if accuracy <= 25 {
            return "GPS 信号强"
        } else {
            return "GPS 信号弱"
        }
    }
}

private extension Data {
    func leUInt16(at index: Int) -> UInt16 {
        guard index + 1 < count else { return 0 }
        return UInt16(self[index]) | (UInt16(self[index + 1]) << 8)
    }

    func leUInt32(at index: Int) -> UInt32 {
        guard index + 3 < count else { return 0 }
        return UInt32(self[index])
            | (UInt32(self[index + 1]) << 8)
            | (UInt32(self[index + 2]) << 16)
            | (UInt32(self[index + 3]) << 24)
    }

    mutating func appendLE(_ value: UInt16) {
        append(UInt8(value & 0x00FF))
        append(UInt8((value >> 8) & 0x00FF))
    }

    mutating func appendLE(_ value: UInt32) {
        append(UInt8(value & 0x000000FF))
        append(UInt8((value >> 8) & 0x000000FF))
        append(UInt8((value >> 16) & 0x000000FF))
        append(UInt8((value >> 24) & 0x000000FF))
    }

    mutating func appendLE(_ value: Int32) {
        appendLE(UInt32(bitPattern: value))
    }
}
