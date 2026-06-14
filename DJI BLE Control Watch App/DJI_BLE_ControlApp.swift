//
//  DJI_BLE_ControlApp.swift
//  DJI BLE Control Watch App
//
//  Created by 张有宽 on 1/5/2026.
//

import SwiftUI

@main
struct DJI_BLE_Control_Watch_AppApp: App {
    @State private var bleManager = DJIActionBLEManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(bleManager)
        }
    }
}
