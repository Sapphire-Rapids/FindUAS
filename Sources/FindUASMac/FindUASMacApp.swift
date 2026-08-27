import SwiftUI

@main
struct FindUASApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(appState.bluetooth)
                .environmentObject(appState.records)
                .environmentObject(appState.ridLab)
                .environmentObject(appState.djiUSB)
                .frame(minWidth: 1050, minHeight: 680)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandMenu("设备") {
                if appState.bluetooth.state == .connected {
                    Button("断开接收器") { appState.bluetooth.disconnect() }
                        .keyboardShortcut("r", modifiers: [.command])
                } else if appState.bluetooth.state == .connecting {
                    Button("正在连接接收器…") {}
                        .disabled(true)
                } else {
                    Button(appState.bluetooth.state == .scanning ? "停止查找接收器" : "查找蓝牙接收器") {
                        if appState.bluetooth.state == .scanning {
                            appState.bluetooth.stopScan()
                        } else {
                            appState.bluetooth.startScan()
                        }
                    }
                    .disabled(appState.bluetooth.state == .unavailable)
                    .keyboardShortcut("r", modifiers: [.command])
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(appState.bluetooth)
                .frame(width: 520, height: 360)
        }
    }
}
