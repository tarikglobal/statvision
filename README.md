# statvision

Apple Silicon ile uyumlu, Swift ve SwiftUI ile yazılmış hafif macOS menü çubuğu monitörü. Harici bağımlılık yoktur. Arayüz Türkçedir.

GitHub’ı ilk kez kullanıyorsanız [projeye özel kısa GitHub rehberini](docs/GITHUB_REHBERI.md) okuyabilirsiniz.

## Mimari

- **AppKit kabuğu:** `NSStatusItem` menü çubuğunda CPU yüzdesi ve kullanılan RAM’i gösterir. `NSPopover` içinde SwiftUI paneli açılır. Dock simgesi veya açılış penceresi oluşturulmaz (`LSUIElement`).
- **Ölçüm servisi:** Mach bellek/CPU çağrıları ve bellek baskısı okumaları tek bir `.utility` seri kuyrukta çalışır. Bir `DispatchSourceTimer`, varsayılan 2 saniyede bir ölçüm alır; 150 ms tolerans, sistemin uyanmaları birleştirmesine yardımcı olur.
- **Durum:** `MonitoringStore` değişmez ölçüm sonuçlarını ana kuyrukta yayımlar. Kullanıcı tercihleri `UserDefaults` içinde saklanır. Ölçümler diske kaydedilmez.
- **Grafikler:** SwiftUI `Canvas`, zaman damgalı son 60 saniyeyi çizer. Ayrı çizim zamanlayıcısı ve animasyon yoktur. Panel kapanınca hosting controller kaldırılır; grafik görünümleri yaşamaz, ölçümler ve menü çubuğu devam eder.
- **Saf hesaplamalar:** `Metrics` katmanı arayüzden ve Mach çağrılarından bağımsızdır; XCTest ve yerel Swift paketi ile test edilebilir.

## Dosya yapısı

```text
statvision.xcodeproj/
  project.pbxproj
  xcshareddata/xcschemes/statvision.xcscheme
statvision/
  App/
    StatvisionApp.swift
    AppDelegate.swift
    MonitoringStore.swift
  Metrics/
    MetricModels.swift
    MetricCalculations.swift
  System/
    SystemSampler.swift
  Views/
    MonitorPanel.swift
    HistoryChart.swift
    SettingsView.swift
  Resources/
    Info.plist
    statvision.entitlements
statvisionTests/
  MetricCalculationsTests.swift
scripts/
  validate_project.rb
Package.swift
README.md
```

## Gereksinimler ve Xcode ayarları

- Minimum **macOS 13.0 Ventura**.
- **Xcode 15 veya sonrası**, Swift 5.9 veya sonrası derleyici. Projenin Swift dil modu 5’tir; Swift 6 derleyicisinin Swift 5 modu da kullanılabilir.
- macOS SDK, standart mimariler. Debug mevcut Mac’in mimarisini derler. Release, standart `arm64` ve `x86_64` mimarilerini destekler; Apple Silicon’da Rosetta gerekmez.
- Bundle identifier: `com.statvision.mac`; ürün adı: `statvision`.
- App Sandbox ve Hardened Runtime açık. Sandbox dosyası yalnızca `com.apple.security.app-sandbox` içerir. Ağ, dosya erişimi veya diğer ek yetkiler yoktur.
- Yerel imzalama: `CODE_SIGN_STYLE = Manual`, `CODE_SIGN_IDENTITY = -` (**Sign to Run Locally / ad hoc**). Yerel çalıştırma için Apple Developer hesabı veya Team gerekmez.
- Info.plist açıkça projede tanımlıdır; otomatik üretilmez. Paylaşılan `statvision` şeması uygulamayı ve test hedefini içerir.

## Çalıştırma

1. Xcode’da **statvision.xcodeproj** dosyasını açın. Uygulamayı açmak için `Package.swift` yerine bu projeyi kullanın.
2. **statvision** şemasını ve **My Mac** hedefini seçin.
3. **⌘R** ile çalıştırın. Menü çubuğunda `CPU … RAM …` görünür. İlk CPU yüzdesi ikinci başarılı ölçümde gelir.
4. Menü çubuğuna tıklayın. Panelde CPU, RAM/kapasite, RAM yüzdesi, bellek baskısı ve iki grafik bulunur.
5. **Ayarlar** üzerinden 1, 2 veya 5 saniye ve Sistem/Açık/Koyu görünümü seçin. Seçim yeniden başlatmalar arasında korunur.

Komut satırı alternatifi, proje dizininde:

```sh
xcodebuild -project statvision.xcodeproj -scheme statvision \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build build
open build/Build/Products/Debug/statvision.app
```

Xcode yüklü olduğu halde geliştirici dizini seçili değilse Xcode → Settings → Locations → **Command Line Tools** alanından kurulu Xcode’u seçin.

## Ölçümler nasıl hesaplanıyor?

### CPU

`host_statistics(HOST_CPU_LOAD_INFO)` tüm mantıksal işlemcilerin user, system, nice ve idle sayaçlarını toplu olarak verir. İki başarılı okuma arasındaki farklar kullanılır:

```text
busy  = Δuser + Δsystem + Δnice
total = busy + Δidle
CPU % = 100 × busy / total
```

Sonuç toplam makine kapasitesine göre **0–100%** aralığındadır; çekirdek sayısına tekrar bölünmez. İlk okuma yalnızca tabandır. Toplam fark sıfırsa gerçek sıfır kullanıma eşit kabul edilmez; yüzde yerine `—` gösterilir. Bir sayaç gerilerse (32 bit taşma dahil) o aralık atılır ve güncel sayaçlar yeni taban olur. Başarısız Mach çağrısı tabanı sıfırlar. 15 saniyeyi aşan örnek boşlukları da atılır.

### RAM

`host_statistics64(HOST_VM_INFO64)` ve `host_page_size` kullanılır. Toplam kapasite `ProcessInfo.physicalMemory` değeridir. Sayfa boyutu çalışma zamanında okunur; 4 KB veya 16 KB varsayılmaz.

```text
appPages     = max(internal_page_count − purgeable_count, 0)
usedBytes    = (appPages + wire_count + compressor_page_count) × pageSize
cachedBytes  = (external_page_count + purgeable_count) × pageSize
compressed   = compressor_page_count × pageSize
RAM %        = 100 × usedBytes / physicalMemory
```

Anonim sayfalar içindeki geri kazanılabilir purgeable bellek, app belleğinden çıkarılır. Dosya destekli sayfalar kullanılan RAM’e eklenmez. Sıkıştırıcı için fiziksel sayfalar bir kez sayılır; `total_uncompressed_pages_in_compressor` ile temsil edilen mantıksal boyut veya diskteki swap RAM’e eklenmez. `cachedBytes` tanılama için tutulan bir önbellek tahminidir; ayrı bir kapasite bölümü olarak sunulmaz ve kullanılan RAM’e eklenmez. Speculative sayfalar da ayrıca eklenmez. Taşan veya fiziksel kapasiteyi aşan tutarsız örnekler `—` olarak gösterilir.

Tüm arayüzde **ondalık GB** kullanılır: 1 GB = 1.000.000.000 bayt. GiB kullanan araçlarla karşılaştırırken birimleri eşitleyin. Apple Silicon birleşik belleği, GPU ve kernel tahsislerinin sınıflandırılması nedeniyle bire bir uygulama belleği toplamı değildir.

### Bellek baskısı

RAM doluluğu üzerinden eşik veya tahmin **yapılmaz**. Önce salt okunur `sysctlbyname("kern.memorystatus_vm_pressure_level")` sorgulanır. XNU’nun döndürdüğü dispatch bayrakları 1/2/4, Normal/Yükselmiş/Kritik olarak eşlenir. Bu sysctl belgelenmiş, kararlı bir public API değildir; macOS sürümüne veya sandbox kısıtlarına göre bulunmayabilir ya da reddedilebilir.

İkinci kaynak belgelenmiş `DispatchSourceMemoryPressure` bildirimleridir. Anlık sorgu yokken bir bildirim alınmışsa **“Son sistem bildirimi; anlık sorgu kullanılamıyor”** yazılır. Bu kaynak sürekli bir anlık ölçüm değildir; bildirimler birleştirilebilir veya gecikebilir. Başlangıçta normal varsayılmaz. İki kaynaktan da veri alınamazsa **“Kullanılamıyor”** gösterilir. Bilinmeyen sysctl değerleri tahmin edilmez; yönetici izni istenmez.

Bu üç seviyeli gösterge, Etkinlik Monitörü’nün sürekli bellek baskısı grafiğinin yeniden üretimi değildir.

### Uyku, kesintiler ve zaman

`NSWorkspace.willSleepNotification` zamanlayıcıyı ve baskı kaynağını kapatır; CPU tabanı sıfırlanır. Uyanışta kaynaklar yeniden oluşturulur. İlk CPU okuması tabandır; uyku boyunca ortalama üretilmez. Bildirim kaçarsa uzun örnek aralığı kontrolü CPU’yu korur.

Örneklerin zaman damgası `CLOCK_MONOTONIC_RAW` ile alınır; uyku süresini kapsar ve saat/tarih değişikliklerinden etkilenmez. Grafik x konumu `(timestamp − (now − 60)) / 60` ile hesaplanır. Bu yüzden 1/2/5 saniyelik aralıkların hepsi aynı 60 saniyeyi gösterir. Eski örnekler budanır, başarısız ölçümler ve 7,5 saniyeden uzun boşluklar çizgiyle birleştirilmez. Henüz 60 saniye dolmadığında geçmiş uydurulmaz; grafiğin sol tarafı boş kalır.

### Etkinlik Monitörü ile neden farklı olabilir?

- CPU yüzdeleri son örnek aralığının ortalamasıdır. İki uygulamanın zamanlayıcıları, yenileme hızları ve yuvarlaması farklı olduğunda kısa sıçramalar farklı görünür.
- İşlem başına CPU değerleri birden fazla çekirdekte 100%’ü aşabilir. statvision tüm makineyi 100% kabul eder; işlem yüzdelerinin ham toplamıyla karşılaştırmayın.
- RAM, açıkça belirtilen fiziksel sayfa formülüdür. Etkinlik Monitörü sürüme göre başka özel muhasebe, kernel/GPU sınıflandırması veya örnekleme anı kullanabilir. Bire bir eşitlik garanti edilmez.
- Önbellek, purgeable, sıkıştırılmış mantıksal boyut, fiziksel sıkıştırıcı ve swap aynı kavram değildir. “Toplam − boş” hesabı, burada gösterilenden daha yüksek çıkabilir.
- Bellek baskısı sistem seviyesidir; RAM %’si yüksekken normal olabilir. Üç seviyeli olay göstergesi ile Etkinlik Monitörü’nün grafiği aynı ölçek değildir.

## Erişilebilirlik ve kaynak kullanımı

- Yerel AppKit düğmesi ve SwiftUI kontrolleri, VoiceOver etiketleri ve okunabilir değerler içerir. Grafikler son/en düşük/en yüksek yüzde özeti sunar.
- Panel açıkken **⌘,** ayarları açar, **⌘Q** çıkar, **Escape** paneli kapatır. Ayarlar penceresinde Escape pencereyi kapatır. macOS Klavye ile Gezinme açıkken Tab/Shift-Tab, odaklanmış düğmede Space/Return kullanılabilir. Menü çubuğuna macOS’un Control-F8 kısayoluyla ulaşılabilir; klavyeye göre Fn gerekebilir.
- Baskı durumları hem yazı hem simgeyle belirtilir. Yerel renkler açık/koyu görünümü izler; grafik çizgileri yüksek kontrast tercihinde kalınlaşır.
- Ağ bağlantısı, alt süreç, işlem taraması veya işlem sonlandırma yoktur. Yönetici yetkisi istenmez. Uygulama başlangıç öğesi kaydetmez.
- Geçmiş varsayılan aralıkta yaklaşık 31, 1 saniyede en fazla 61 örnektir. CPU ve RAM sürekli ölçülür; panel kapalıyken grafik çizimi yoktur. Sabit bir pil/CPU tüketimi iddiası yapılmaz; donanım üzerinde Instruments ile ölçülmelidir.

## Testler ve doğrulama

20 XCTest, gerçek sistemden bağımsız kontrollü sayaç girdileriyle hesaplamaları denetler. Uygulama çalışma zamanında bu test girdilerini veya rastgele veri kullanmaz.

Kapsam: ilk CPU örneği; lifetime yerine delta; nice sayacı; 0/100 sınırları; çok çekirdek normalizasyonu; sıfır fark; sayaç sıfırlanması/32 bit taşma; uzun boşluk/uyku; geçersiz zaman; fiziksel sıkıştırma; dosya önbelleği ayrımı; çalışma zamanı sayfa boyutu; çıkarma/çarpma/toplama taşmaları; GB birimi; 1/2/5 saniyede ve değişen aralıklarda gerçek 60 saniye; eksik geçmiş; bildirilmemiş baskı değerleri.

Xcode’da **⌘U** veya:

```sh
xcodebuild -project statvision.xcodeproj -scheme statvision \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath build test
```

Yalnızca hesaplama testlerini uygulamayı başlatmadan çalıştırmak için:

```sh
swift test
```

Proje dosya başvurularını, kaynak hedef üyeliklerini, paylaşılan şemayı ve plist dosyalarını kontrol etmek için:

```sh
ruby scripts/validate_project.rb
```

**Son doğrulama — 14 Kasım 2026:** Apple Silicon üzerinde Xcode 27.2 ile Debug uygulama derlemesi başarılı; `swift test` ile **20 test, 0 hata**. Proje başvuruları, hedef üyelikleri, paylaşılan şema ve plist denetimleri de geçti. Testler saf ölçüm hesaplamalarını kapsar; kullanıcı arayüzü, VoiceOver, pil tüketimi ve gerçek cihaz uyku/uyanma davranışı ayrıca doğrulanmalıdır. Minimum macOS 13 uyumluluğu ayrı bir macOS 13 cihazında çalıştırılarak doğrulanmadı.

Önerilen kısa cihaz kontrolü: önce boşta CPU/RAM’i gözleyin; ardından normal bir iş yüküyle Etkinlik Monitörü’nün toplam CPU değerini karşılaştırın. Yenileme aralığını değiştirin, paneli kapatıp menü değerlerinin devam ettiğini kontrol edin, Mac’i uyutup uyandırın. İlk CPU değerinin yeniden beklendiğini ve uyku boşluğunun çizilmediğini doğrulayın. Sistem/Açık/Koyu görünümü ve klavye kısayollarını deneyin.

## .app oluşturma ve dışa aktarma

Kendi Mac’inizde kullanılacak Release `.app` için:

```sh
xcodebuild -project statvision.xcodeproj -scheme statvision \
  -configuration Release -destination 'generic/platform=macOS' \
  -derivedDataPath build ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO build
```

Çıktı **build/Build/Products/Release/statvision.app** dosyasıdır. Finder ile Applications klasörüne kopyalayıp açabilirsiniz. Yalnızca Apple Silicon çıktısı için aynı komutta `ARCHS=arm64` kullanın. Xcode’da Products → statvision.app → Show in Finder da aynı ürünü bulur.

Arşiv oluşturmak için Xcode → Product → Archive veya:

```sh
xcodebuild -project statvision.xcodeproj -scheme statvision \
  -configuration Release -destination 'generic/platform=macOS' \
  -archivePath build/statvision.xcarchive archive
```

Arşivdeki uygulama **build/statvision.xcarchive/Products/Applications/statvision.app** konumundadır. Yerel ad hoc imza yalnızca yerel geliştirme içindir. Başka Mac’lere dağıtımda kendi Apple Developer Team’inizi/bundle identifier’ınızı seçin; Developer ID imzası ve noter onayı için Xcode Organizer’ın dağıtım akışını kullanın. Bu dağıtım işlemi geliştirici hesabı ve ağ gerektirebilir; uygulamanın çalışması gerektirmez. Gatekeeper’ı kapatmak gerekmez.

## Sistem API kaynakları

- [Apple XNU: VM sayaçlarının tanımları](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/mach/vm_statistics.h)
- [Apple XNU: baskı seviyesinin dispatch bayraklarına dönüşümü ve sysctl](https://github.com/apple-oss-distributions/xnu/blob/main/bsd/kern/kern_memorystatus_notify.c)
- [Apple: DispatchSourceMemoryPressure](https://developer.apple.com/documentation/dispatch/dispatchsourcememorypressure)
- [Apple Libc: monotonik saat ve uyku davranışı](https://github.com/apple-oss-distributions/Libc/blob/main/gen/clock_gettime.3)

