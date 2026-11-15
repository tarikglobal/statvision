import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: MonitoringStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "slider.horizontal.3").foregroundStyle(.tint)
                Text("statvision Ayarları").font(.headline)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Menü çubuğunda göster").font(.headline)
                Toggle("CPU kullanımı", isOn: $store.menuBarVisibility.showCPU)
                Toggle("RAM kullanımı", isOn: $store.menuBarVisibility.showMemory)
                Toggle("Sıcaklık", isOn: $store.menuBarVisibility.showTemperature)
                Text("Tümünü kapatırsan menü çubuğunda yalnızca statvision simgesi görünür.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .toggleStyle(.switch)
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
        .tint(.teal)
        .preferredColorScheme(store.appearance.colorScheme)
        .onExitCommand { NSApplication.shared.keyWindow?.performClose(nil) }
    }
}

