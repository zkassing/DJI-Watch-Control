//
//  DJIRSdkProtocol.swift
//  DJI BLE Control Watch App
//
//  Created by Codex on 2026/5/1.
//

import Foundation

enum DJIRSdkCommandType: UInt8 {
    case noResponse = 0x00
    case responseOrNot = 0x01
    case waitResult = 0x02
    case ackNoResponse = 0x20
    case ackResponseOrNot = 0x21
    case ackWaitResult = 0x22
}

struct DJIRSdkFrameSummary {
    let sequence: UInt16
    let commandType: UInt8
    let commandSet: UInt8
    let commandID: UInt8
}

struct DJIRSdkFrame {
    let sequence: UInt16
    let commandType: UInt8
    let commandSet: UInt8
    let commandID: UInt8
    let payload: Data
}

enum DJIRSdkProtocol {
    static func makeFrame(
        commandSet: UInt8,
        commandID: UInt8,
        commandType: DJIRSdkCommandType,
        payload: Data,
        sequence: UInt16
    ) -> Data {
        var frame = Data()
        let frameLength = 12 + 2 + payload.count + 4
        let verLength = UInt16(frameLength & 0x03FF)

        frame.append(0xAA)
        frame.appendLE(verLength)
        frame.append(commandType.rawValue)
        frame.append(0x00)
        frame.append(contentsOf: [0x00, 0x00, 0x00])
        frame.appendLE(sequence)

        let headerCRC = crc16(frame)
        frame.appendLE(headerCRC)
        frame.append(commandSet)
        frame.append(commandID)
        frame.append(payload)

        let tailCRC = crc32(frame)
        frame.appendLE(tailCRC)

        return frame
    }

    static func parseSummary(from frame: Data) -> DJIRSdkFrameSummary? {
        guard let parsed = parseFrame(from: frame) else {
            return nil
        }

        return DJIRSdkFrameSummary(
            sequence: parsed.sequence,
            commandType: parsed.commandType,
            commandSet: parsed.commandSet,
            commandID: parsed.commandID
        )
    }

    static func parseFrame(from frame: Data) -> DJIRSdkFrame? {
        guard frame.count >= 18, frame.first == 0xAA else {
            return nil
        }

        let verLength = UInt16(frame[1]) | (UInt16(frame[2]) << 8)
        let expectedLength = Int(verLength & 0x03FF)
        guard expectedLength == frame.count else {
            return nil
        }

        let receivedCRC16 = UInt16(frame[10]) | (UInt16(frame[11]) << 8)
        guard crc16(frame.prefix(10)) == receivedCRC16 else {
            return nil
        }

        let receivedCRC32 = UInt32(frame[frame.count - 4])
            | (UInt32(frame[frame.count - 3]) << 8)
            | (UInt32(frame[frame.count - 2]) << 16)
            | (UInt32(frame[frame.count - 1]) << 24)
        guard crc32(frame.prefix(frame.count - 4)) == receivedCRC32 else {
            return nil
        }

        let sequence = UInt16(frame[8]) | (UInt16(frame[9]) << 8)
        let payloadRange = 14..<(frame.count - 4)

        return DJIRSdkFrame(
            sequence: sequence,
            commandType: frame[3],
            commandSet: frame[12],
            commandID: frame[13],
            payload: Data(frame[payloadRange])
        )
    }

    static func hexString(for data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private static func crc16<T: DataProtocol>(_ data: T) -> UInt16 {
        var crc: UInt16 = 0x3AA3

        for byte in data {
            crc ^= UInt16(byte)
            for _ in 0..<8 {
                if crc & 0x0001 != 0 {
                    crc = (crc >> 1) ^ 0xA001
                } else {
                    crc >>= 1
                }
            }
        }

        return crc
    }

    private static func crc32<T: DataProtocol>(_ data: T) -> UInt32 {
        var crc: UInt32 = 0x00003AA3

        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                if crc & 0x00000001 != 0 {
                    crc = (crc >> 1) ^ 0xEDB88320
                } else {
                    crc >>= 1
                }
            }
        }

        return crc
    }
}

private extension Data {
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
}
