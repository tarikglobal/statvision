import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: MonitoringStore
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                EyeMark().frame(width: 42, height: 27)
                VStack(alignment: .leading, spacing: 2) {
                    Text("statvision").font(.system(size: 21, weight: .heavy, design: .rounded))
                    Text("Kontrol sende.").font(.caption).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 9) {
                Text("Menü çubuğu modu").font(.headline)
                Picker("Menü çubuğu modu", selection: $store.menuBarMode) {
                    ForEach(MenuBarMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                .pickerStyle(.segmented).labelsHidden()
                Text("Göz modunda simge göz kırpar. Üzerine gelince CPU, RAM, sıcaklık ve güç küçük bir cam panelde görünür. Tıklamak tam paneli açar.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .monitorCard()
            VStack(alignment: .leading, spacing: 10) {
                Text("Menü çubuğunda göster").font(.headline)
                Toggle("CPU kullanımı", isOn: $store.menuBarVisibility.showCPU)
                Toggle("RAM kullanımı", isOn: $store.menuBarVisibility.showMemory)
                Toggle("Sıcaklık", isOn: $store.menuBarVisibility.showTemperature)
                Text(store.menuBarMode == .eye ? "Bu seçimler Göstergeler modunda kullanılır." : "Tümünü kapatırsan menü çubuğunda yalnızca statvision simgesi görünür.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .toggleStyle(.switch)
            .disabled(store.menuBarMode == .eye)
            Divider()
            Form {
                Picker("Yenileme aralığı", selection: $store.refreshInterval) {
                    Text("1 saniye").tag(1)
                    Text("2 saniye").tag(2)
                    Text("5 saniye").tag(5)
                }
                .pickerStyle(.segmented)
                .accessibilityHint("Daha uzun aralık, daha az ölçüm ve uyanma demektir")
                Picker("Görünüm", selection: $store.appearance) {
                    ForEach(AppearancePreference.allCases) { value in
                        Text(value.title).tag(value)
                    }
                }.pickerStyle(.segmented)
            }
            Text("Varsayılan: 2 saniye. Grafikler her aralıkta son 60 saniyeyi gösterir. Panel kapalıyken yalnızca ölçümler ve menü çubuğu güncellenir.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            Text("Sistem API’leriyle yerel ölçüm. Ağ bağlantısı, yönetici yetkisi veya ek izin gerekmez.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 410)
        .background(MonitorBackdrop())
        .tint(StatvisionPalette.accent(scheme))
        .preferredColorScheme(store.appearance.colorScheme)
        .onExitCommand { NSApplication.shared.keyWindow?.performClose(nil) }
    }
}

