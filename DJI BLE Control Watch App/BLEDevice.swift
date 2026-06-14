//
//  BLEDevice.swift
//  DJI BLE Control Watch App
//
//  Created by Codex on 2026/5/1.
//

import Foundation

struct BLEDevice: Identifiable, Equatable {
    let id: UUID
    let name: String?
    let rssi: Int

    var displayName: String {
        if let name, !name.isEmpty {
            return name
        }

        return "未命名设备"
    }

    var subtitle: String {
        "RSSI \(rssi) dBm"
    }
}
