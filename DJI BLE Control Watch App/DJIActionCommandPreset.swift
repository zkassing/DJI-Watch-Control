//
//  DJIActionCommandPreset.swift
//  DJI BLE Control Watch App
//
//  Created by Codex on 2026/5/1.
//

import Foundation

enum DJIActionCommandPreset: String, CaseIterable, Identifiable {
    case queryVersion
    case subscribeStatus
    case startRecording
    case stopRecording
    case switchToVideo
    case switchToPhoto
    case quickSwitchMode
    case shutter
    case cameraSleep

    var id: String { rawValue }

    var title: String {
        switch self {
        case .queryVersion:
            return "查询版本"
        case .subscribeStatus:
            return "订阅状态"
        case .startRecording:
            return "开始录像"
        case .stopRecording:
            return "停止录像"
        case .switchToVideo:
            return "切到视频模式"
        case .switchToPhoto:
            return "切到拍照模式"
        case .quickSwitchMode:
            return "快速切模"
        case .shutter:
            return "快门"
        case .cameraSleep:
            return "休眠"
        }
    }

    var commandSet: UInt8 {
        switch self {
        case .queryVersion, .quickSwitchMode, .shutter, .cameraSleep:
            return 0x00
        case .subscribeStatus, .startRecording, .stopRecording, .switchToVideo, .switchToPhoto:
            return 0x1D
        }
    }

    var commandID: UInt8 {
        switch self {
        case .queryVersion:
            return 0x00
        case .quickSwitchMode, .shutter:
            return 0x11
        case .cameraSleep:
            return 0x1A
        case .startRecording, .stopRecording:
            return 0x03
        case .switchToVideo, .switchToPhoto:
            return 0x04
        case .subscribeStatus:
            return 0x05
        }
    }

    var commandType: DJIRSdkCommandType {
        switch self {
        case .queryVersion:
            return .waitResult
        case .subscribeStatus:
            return .noResponse
        case .startRecording, .stopRecording, .switchToVideo, .switchToPhoto, .quickSwitchMode, .shutter, .cameraSleep:
            return .responseOrNot
        }
    }

    var payload: Data {
        switch self {
        case .queryVersion:
            return Data()
        case .subscribeStatus:
            return Data([0x03, 0x14, 0x00, 0x00, 0x00, 0x00])
        case .startRecording:
            return recordControlPayload(recordControl: 0x00)
        case .stopRecording:
            return recordControlPayload(recordControl: 0x01)
        case .switchToVideo:
            return modeSwitchPayload(mode: 0x01)
        case .switchToPhoto:
            return modeSwitchPayload(mode: 0x05)
        case .quickSwitchMode:
            return keyReportPayload(keyCode: 0x02)
        case .shutter:
            return keyReportPayload(keyCode: 0x03)
        case .cameraSleep:
            return Data([0x03])
        }
    }

    private func recordControlPayload(recordControl: UInt8) -> Data {
        var data = Data()
        appendLE32(0x33FF0000, to: &data)
        data.append(recordControl)
        data.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        return data
    }

    private func modeSwitchPayload(mode: UInt8) -> Data {
        var data = Data()
        appendLE32(0xFF330000, to: &data)
        data.append(mode)
        data.append(contentsOf: [0x01, 0x47, 0x39, 0x36])
        return data
    }

    private func keyReportPayload(keyCode: UInt8) -> Data {
        var data = Data()
        data.append(keyCode)
        data.append(0x01)
        appendLE16(0x0000, to: &data)
        return data
    }
}

private func appendLE16(_ value: UInt16, to data: inout Data) {
    data.append(UInt8(value & 0x00FF))
    data.append(UInt8((value >> 8) & 0x00FF))
}

private func appendLE32(_ value: UInt32, to data: inout Data) {
    data.append(UInt8(value & 0x000000FF))
    data.append(UInt8((value >> 8) & 0x000000FF))
    data.append(UInt8((value >> 16) & 0x000000FF))
    data.append(UInt8((value >> 24) & 0x000000FF))
}
