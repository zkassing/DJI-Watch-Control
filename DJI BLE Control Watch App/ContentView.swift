//
//  ContentView.swift
//  DJI BLE Control Watch App
//
//  Created by 张有宽 on 1/5/2026.
//

import SwiftUI

struct ContentView: View {
    @Environment(DJIActionBLEManager.self) private var bleManager
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ConnectionView(selectedTab: $selectedTab)
                .tabItem {
                    Image(systemName: bleManager.isProtocolConnected ? "checkmark.circle.fill" : "antenna.radiowaves.left.and.right")
                    Text("连接")
                }
                .tag(0)

            CameraInfoView()
                .tabItem {
                    Image(systemName: "info.circle.fill")
                    Text("状态")
                }
                .tag(1)

            ActionControlView()
                .tabItem {
                    Image(systemName: bleManager.currentMode == .video ? "video.fill" : "camera.fill")
                    Text("控制")
                }
                .tag(2)

            if bleManager.isRecording {
                RecordingView(selectedTab: $selectedTab)
                    .tabItem {
                        Image(systemName: "record.circle")
                        Text("录制")
                    }
                    .tag(3)
            }
        }
        .tint(.orange)
        .onChange(of: bleManager.isProtocolConnected) { _, newValue in
            if newValue {
                selectedTab = 1
            }
        }
        .onChange(of: bleManager.isRecording) { _, newValue in
            if newValue && !bleManager.isTakingPhoto {
                selectedTab = 3
            } else if !newValue && selectedTab == 3 {
                selectedTab = 2
            }
        }
    }
}

// MARK: - 连接页面

struct ConnectionView: View {
    @Environment(DJIActionBLEManager.self) private var bleManager
    @Binding var selectedTab: Int

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                connectionHeader

                if bleManager.connectedPeripheralID == nil {
                    deviceListSection
                } else {
                    connectedDeviceSection
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(
            LinearGradient(
                colors: [.black, Color(red: 0.05, green: 0.08, blue: 0.07)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .navigationTitle("腕拍")
        .onAppear {
            if bleManager.canScan && bleManager.connectedPeripheralID == nil {
                bleManager.startScan()
            }
        }
        .onChange(of: bleManager.canScan) { _, newValue in
            if newValue && bleManager.connectedPeripheralID == nil {
                bleManager.startScan()
            }
        }
    }

    private var connectionHeader: some View {
        VStack(spacing: 6) {
            if let name = bleManager.connectedPeripheralID != nil ? bleManager.connectedDeviceName : nil {
                HStack {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(.green)
                    Text(name)
                        .font(.headline)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var deviceListSection: some View {
        VStack(spacing: 6) {
            if bleManager.discoveredDevices.isEmpty {
                Text(bleManager.isScanning ? "搜索中..." : "没有发现设备")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            } else {
                ForEach(bleManager.discoveredDevices) { device in
                    Button {
                        bleManager.connect(to: device.id)
                    } label: {
                        HStack {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.caption)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(device.displayName)
                                    .font(.caption)
                                    .lineLimit(1)
                                Text(device.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if bleManager.isConnecting && bleManager.connectedPeripheralID == device.id {
                                ProgressView()
                                    .scaleEffect(0.6)
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(bleManager.isConnecting)
                }
            }

            Button {
                bleManager.toggleScan()
            } label: {
                HStack {
                    Image(systemName: bleManager.isScanning ? "stop.fill" : "arrow.clockwise")
                    Text(bleManager.isScanning ? "停止" : "重新扫描")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(.orange)
            .disabled(!bleManager.canScan)
        }
    }

    private var connectedDeviceSection: some View {
        VStack(spacing: 8) {
            HStack {
                Image(systemName: "link")
                Text(bleManager.connectedDeviceName)
                    .font(.caption)
                Spacer()
                if bleManager.isProtocolConnected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
            }

            Button("断开连接") {
                bleManager.disconnect()
            }
            .font(.caption)
            .buttonStyle(.bordered)
            .tint(.red)
        }
        .padding(10)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - 相机状态页面

struct CameraInfoView: View {
    @Environment(DJIActionBLEManager.self) private var bleManager

    private var status: DJIActionBLEManager.CameraStatusSnapshot {
        bleManager.cameraStatus
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                headerCard

                if status.hasData {
                    storageCard
                    parameterCard
                    systemCard
                } else {
                    emptyCard
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(
            LinearGradient(
                colors: [.black, Color(red: 0.04, green: 0.07, blue: 0.09)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .navigationTitle("状态")
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(status.hasData ? status.modeText : "等待相机状态")
                        .font(.headline)
                        .lineLimit(1)
                    Text(status.modeParameter?.isEmpty == false ? status.modeParameter! : status.statusText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                statusBadge
            }

            HStack(spacing: 8) {
                metricPill(
                    icon: "battery.100percent",
                    title: "电量",
                    value: status.hasData ? "\(status.batteryPercentage)%" : "--"
                )
                metricPill(
                    icon: "timer",
                    title: status.isRecording ? "已录" : "可录",
                    value: formatDuration(status.isRecording ? UInt32(status.recordTime) : status.remainTimeSeconds)
                )
            }
        }
        .padding(10)
        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(status.hasData ? status.statusText : bleManager.connectionSummary)
                .font(.caption2)
                .fontWeight(.semibold)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(statusColor.opacity(0.18), in: Capsule())
    }

    private var storageCard: some View {
        VStack(spacing: 6) {
            infoRow("SD 剩余", value: formatCapacity(status.remainCapacityMB), icon: "sdcard")
            infoRow("剩余照片", value: "\(status.remainPhotoCount)", icon: "photo.on.rectangle")
            infoRow("剩余录像", value: formatDuration(status.remainTimeSeconds), icon: "video")
        }
        .padding(10)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    private var parameterCard: some View {
        VStack(spacing: 6) {
            infoRow("分辨率", value: status.resolutionText, icon: "rectangle.dashed")
            infoRow("帧率", value: status.fpsText, icon: "speedometer")
            infoRow("增稳", value: status.eisText, icon: "waveform.path.ecg")
        }
        .padding(10)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    private var systemCard: some View {
        VStack(spacing: 6) {
            infoRow("电源", value: status.powerText, icon: "power")
            infoRow("温度", value: status.temperatureText, icon: "thermometer")
            infoRow("GPS", value: bleManager.gpsStatusText, icon: bleManager.isGPSEnabled ? "location.fill" : "location.slash")
        }
        .padding(10)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    private var emptyCard: some View {
        VStack(spacing: 8) {
            Image(systemName: bleManager.isProtocolConnected ? "dot.radiowaves.left.and.right" : "link.badge.plus")
                .font(.title3)
                .foregroundStyle(.orange)
            Text(bleManager.isProtocolConnected ? "已订阅状态，等待相机推送" : "连接并握手后显示相机信息")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }

    private var statusColor: Color {
        guard status.hasData else {
            return bleManager.isProtocolConnected ? .orange : .gray
        }

        if status.temperatureState >= 2 {
            return .red
        }

        if status.powerMode == 0x03 {
            return .blue
        }

        return status.isRecording ? .red : .green
    }

    private func metricPill(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 10))
    }

    private func infoRow(_ title: String, value: String, icon: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption2)
                .fontWeight(.semibold)
                .lineLimit(1)
        }
    }

    private func formatCapacity(_ megabytes: UInt32) -> String {
        if megabytes >= 1024 {
            return String(format: "%.1fGB", Double(megabytes) / 1024.0)
        }

        return "\(megabytes)MB"
    }

    private func formatDuration(_ seconds: UInt32) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }

        return String(format: "%02d:%02d", minutes, secs)
    }
}

// MARK: - Action 控制页面

struct ActionControlView: View {
    @Environment(DJIActionBLEManager.self) private var bleManager

    private var status: DJIActionBLEManager.CameraStatusSnapshot {
        bleManager.cameraStatus
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    modeHeader

                    topButtons

                    switchModeButton

                    sleepButton
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .background(
                LinearGradient(
                    colors: [.black, Color(red: 0.05, green: 0.08, blue: 0.07)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .navigationTitle("腕拍")
        }
    }

    private var modeHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("当前模式")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(currentModeText)
                    .font(.headline)
                    .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                Text(status.hasData ? status.statusText : bleManager.connectionSummary)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(statusColor.opacity(0.16), in: Capsule())
        }
        .padding(10)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var topButtons: some View {
        if isPhotoMode {
            photoCaptureButton
        } else {
            HStack(spacing: 8) {
                recordButton
                photoCaptureButton
            }
        }
    }

    private var recordButton: some View {
        Button {
            bleManager.send(command: .startRecording)
        } label: {
            VStack(spacing: 3) {
                if bleManager.captureTransition == .starting {
                    ProgressView()
                        .frame(height: 28)
                } else {
                    Image(systemName: primaryCaptureIcon)
                        .font(.title2)
                }
                Text(bleManager.captureTransition == .starting ? "确认中" : primaryCaptureTitle)
                    .font(.caption2)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .disabled(!bleManager.isReadyForCommands || bleManager.isRecording || bleManager.isCapturePending)
    }

    private var photoCaptureButton: some View {
        Button {
            bleManager.capturePhoto()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: "camera.fill")
                    .font(.title2)
                Text("拍照")
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
        .disabled(!bleManager.isReadyForCommands || bleManager.isRecording || bleManager.isCapturePending)
    }

    private var switchModeButton: some View {
        NavigationLink {
            ModeSelectionView()
        } label: {
            HStack {
                Image(systemName: "rectangle.grid.2x2.fill")
                Text("选择模式")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
        .disabled(!bleManager.isReadyForCommands || bleManager.isRecording || bleManager.isCapturePending)
    }

    private var sleepButton: some View {
        Button {
            bleManager.send(command: .cameraSleep)
        } label: {
            HStack {
                Image(systemName: "moon.zzz.fill")
                Text("休眠")
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
        .disabled(!bleManager.isReadyForCommands || bleManager.isRecording || bleManager.isCapturePending)
    }

    private var currentModeText: String {
        if status.hasData {
            return status.modeText
        }

        return bleManager.currentMode.rawValue
    }

    private var primaryCaptureTitle: String {
        guard status.hasData else {
            return bleManager.currentMode == .photo ? "拍照" : "录制视频"
        }

        switch status.modeCode {
        case 0x05:
            return "拍照"
        case 0x00:
            return "录制慢动作"
        case 0x02:
            return "录制延时"
        case 0x0A:
            return "录制运动"
        case 0x28:
            return "录制超级夜景"
        case 0x37:
            return "录制8K视频"
        default:
            return "录制\(status.modeText)"
        }
    }

    private var primaryCaptureIcon: String {
        if status.hasData, status.modeCode == 0x05 {
            return "camera.fill"
        }

        return "record.circle"
    }

    private var isPhotoMode: Bool {
        if status.hasData {
            return status.modeCode == 0x05 || status.modeText == "拍照"
        }

        return bleManager.currentMode == .photo
    }

    private var statusColor: Color {
        guard status.hasData else {
            return bleManager.isProtocolConnected ? .orange : .gray
        }

        if status.temperatureState >= 2 {
            return .red
        }

        if status.powerMode == 0x03 {
            return .blue
        }

        return status.isRecording ? .red : .green
    }
}

struct ModeSelectionView: View {
    @Environment(DJIActionBLEManager.self) private var bleManager
    @Environment(\.dismiss) private var dismiss

    private var currentModeCode: UInt8? {
        bleManager.cameraStatus.hasData ? bleManager.cameraStatus.modeCode : nil
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(bleManager.modeOptions) { option in
                    Button {
                        bleManager.switchMode(to: option)
                        dismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: option.icon)
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .frame(width: 18)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.title)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                Text(option.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            if currentModeCode == option.code {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!bleManager.isReadyForCommands || bleManager.isCapturePending)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .navigationTitle("选择模式")
    }
}

// MARK: - 录制页面

struct RecordingView: View {
    @Environment(DJIActionBLEManager.self) private var bleManager
    @Binding var selectedTab: Int
    @State private var recordingDuration: Int = 0
    @State private var timer: Timer?
    @State private var hasStartedTimer: Bool = false

    private var gpsStatusView: some View {
        HStack(spacing: 4) {
            Image(systemName: bleManager.isGPSEnabled ? "location.fill" : "location.slash")
                .font(.caption2)
                .foregroundStyle(bleManager.isGPSEnabled ? .green : .gray)
            Text(bleManager.gpsStatusText)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Circle()
                    .fill(.red)
                    .frame(width: 6, height: 6)
                Text("录制中")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)

            VStack(spacing: 4) {
                Text(formatDuration(recordingDuration))
                    .font(.system(.title, design: .rounded).monospacedDigit())
                    .fontWeight(.bold)

                gpsStatusView
            }

            Button {
                bleManager.send(command: .stopRecording)
            } label: {
                VStack(spacing: 3) {
                    if bleManager.captureTransition == .stopping {
                        ProgressView()
                            .frame(width: 50, height: 36)
                    } else {
                        Image(systemName: "stop.fill")
                            .font(.title3)
                            .frame(width: 50, height: 36)
                    }
                    Text(bleManager.captureTransition == .stopping ? "确认中" : "停止")
                        .font(.caption2)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .padding(.top, 4)
            .disabled(bleManager.isCapturePending)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [.black, Color(red: 0.1, green: 0.05, blue: 0.05)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .onAppear {
            ensureTimerRunning()
        }
        .onDisappear {
            // 不停止定时器，保持计时
        }
        .onChange(of: bleManager.isRecording) { _, newValue in
            if newValue {
                ensureTimerRunning()
            } else {
                stopTimer()
                recordingDuration = 0
                hasStartedTimer = false
            }
        }
    }

    private func ensureTimerRunning() {
        if !hasStartedTimer {
            recordingDuration = 0
            hasStartedTimer = true
        }
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            recordingDuration += 1
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func formatDuration(_ seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, secs)
    }
}

#Preview {
    ContentView()
        .environment(DJIActionBLEManager())
}
