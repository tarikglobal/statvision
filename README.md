# statvision

Apple Silicon ile uyumlu, Swift ve SwiftUI ile yazılmış hafif macOS menü çubuğu monitörü. Harici bağımlılık yoktur. Arayüz Türkçedir.

GitHub’ı ilk kez kullanıyorsanız [projeye özel kısa GitHub rehberini](docs/GITHUB_REHBERI.md) okuyabilirsiniz.

Hazır uygulamayı açmak ve başka Mac’lere göndermek için [kullanım ve paylaşım rehberine](docs/KULLANIM.md) bakın. Uygulama simgesine çift tıklanınca panel doğrudan açılır; uygulama zaten çalışıyorsa aynı panel yeniden gösterilir.

## Mimari

- **AppKit kabuğu:** `NSStatusItem` menü çubuğunda CPU yüzdesi, kullanılan RAM ve sıcaklığı °C olarak gösterir. `NSPopover` içinde SwiftUI paneli açılır. Dock simgesi veya açılış penceresi oluşturulmaz (`LSUIElement`).
- **Ölçüm servisi:** Mach bellek/CPU çağrıları ve bellek baskısı okumaları tek bir `.utility` seri kuyrukta çalışır. Bir `DispatchSourceTimer`, varsayılan 2 saniyede bir ölçüm alır; 150 ms tolerans, sistemin uyanmaları birleştirmesine yardımcı olur.
- **Durum:** `MonitoringStore` değişmez ölçüm sonuçlarını ana kuyrukta yayımlar. Kullanıcı tercihleri `UserDefaults` içinde saklanır. Ölçümler diske kaydedilmez.
- **Grafikler:** SwiftUI `Canvas`, zaman damgalı son 60 saniyeyi çizer. Ayrı çizim zamanlayıcısı ve animasyon yoktur. Panel kapanınca hosting controller kaldırılır; grafik görünümleri yaşamaz, ölçümler ve menü çubuğu devam eder.
- **Saf hesaplamalar:** `Metrics` katmanı arayüzden ve Mach çağrılarından bağımsızdır; XCTest ve yerel Swift paketi ile test edilebilir.
- **Uygulama sıralaması:** Panelin altındaki ok düğmesi ilk 5 uygulama bölümünü açar/kapatır; CPU/RAM sekmeleri ayrı sıralamaları gösterir. Bölüm başlangıçta kapalıdır ve son seçimi hatırlar. `libproc` okumaları yalnızca panel ve bu bölüm açıkken yapılır. Panel içerik boyuna göre küçülür/büyür; küçük ekranlarda kaydırılabilir.
- **Menü çubuğu ayarları:** Ayarlar'da CPU, RAM ve sıcaklık bağımsız gösterilip gizlenir. Seçimler anında uygulanır ve `UserDefaults` ile saklanır. Üçü de gizlenirse panelin erişilebilir kalması için statvision simgesi gösterilir. Ana paneldeki ölçümler bu tercihlerden etkilenmez.

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
    ApplicationMetrics.swift
    TemperatureMetrics.swift
  System/
    SystemSampler.swift
    ApplicationSampler.swift
    TemperatureReader.swift
  Views/
    MonitorPanel.swift
    HistoryChart.swift
    SettingsView.swift
    ApplicationUsageView.swift
  Resources/
    Info.plist
    AppIcon.icns
    statvision.entitlements
statvisionTests/
  MetricCalculationsTests.swift
scripts/
  validate_project.rb
  generate-icon.swift
  package-release.sh
  install-desktop.sh
Package.swift
README.md
```

## Gereksinimler ve Xcode ayarları

- Minimum **macOS 13.0 Ventura**.
- **Xcode 15 veya sonrası**, Swift 5.9 veya sonrası derleyici. Projenin Swift dil modu 5’tir; Swift 6 derleyicisinin Swift 5 modu da kullanılabilir.
- macOS SDK, standart mimariler. Debug mevcut Mac’in mimarisini derler. Release, standart `arm64` ve `x86_64` mimarilerini destekler; Apple Silicon’da Rosetta gerekmez.
- Bundle identifier: `com.statvision.mac`; ürün adı: `statvision`.
- Hardened Runtime açık. Başka uygulamaların işlem ölçümlerini okuyabilmek için App Sandbox kapalıdır; entitlement dosyası boştur. Yönetici yetkisi, Erişilebilirlik, Tam Disk Erişimi veya ağ bağlantısı istenmez.
- Yerel imzalama: `CODE_SIGN_STYLE = Manual`, `CODE_SIGN_IDENTITY = -` (**Sign to Run Locally / ad hoc**). Yerel çalıştırma için Apple Developer hesabı veya Team gerekmez.
- Info.plist açıkça projede tanımlıdır; otomatik üretilmez. Paylaşılan `statvision` şeması uygulamayı ve test hedefini içerir.

## Çalıştırma

1. Xcode’da **statvision.xcodeproj** dosyasını açın. Uygulamayı açmak için `Package.swift` yerine bu projeyi kullanın.
2. **statvision** şemasını ve **My Mac** hedefini seçin.
3. **⌘R** ile çalıştırın. Menü çubuğunda `CPU … RAM …` görünür. İlk CPU yüzdesi ikinci başarılı ölçümde gelir.
4. Menü çubuğuna tıklayın. Panelde CPU, RAM/kapasite, RAM yüzdesi, bellek baskısı ve iki grafik bulunur. En alttaki **En çok tüketen 5 uygulama** bölümünde CPU/RAM sekmeleriyle sıralamayı değiştirin.
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

RAM kapasitesi tüm arayüzde **ikilik ölçekte** gösterilir: arayüzdeki GB etiketi 1.073.741.824 baytı (1024³, teknik olarak GiB) ifade eder. Böylece 16 GB fiziksel RAM, 17,2 yerine 16,0 GB görünür. Kullanılan RAM ve toplam RAM aynı bölenle dönüştürülür; kullanım yüzdesi doğrudan bayt değerlerinden hesaplanır ve bu gösterim tercihinden etkilenmez. Ondalık GB kullanan araçlarla karşılaştırırken birimleri eşitleyin. Apple Silicon birleşik belleği, GPU ve kernel tahsislerinin sınıflandırılması nedeniyle bire bir uygulama belleği toplamı değildir.

### Bellek baskısı

RAM doluluğu üzerinden eşik veya tahmin **yapılmaz**. Önce salt okunur `sysctlbyname("kern.memorystatus_vm_pressure_level")` sorgulanır. XNU’nun döndürdüğü dispatch bayrakları 1/2/4, Normal/Yükselmiş/Kritik olarak eşlenir. Bu sysctl belgelenmiş, kararlı bir public API değildir; macOS sürümüne veya sandbox kısıtlarına göre bulunmayabilir ya da reddedilebilir.

İkinci kaynak belgelenmiş `DispatchSourceMemoryPressure` bildirimleridir. Anlık sorgu yokken bir bildirim alınmışsa **“Son sistem bildirimi; anlık sorgu kullanılamıyor”** yazılır. Bu kaynak sürekli bir anlık ölçüm değildir; bildirimler birleştirilebilir veya gecikebilir. Başlangıçta normal varsayılmaz. İki kaynaktan da veri alınamazsa **“Kullanılamıyor”** gösterilir. Bilinmeyen sysctl değerleri tahmin edilmez; yönetici izni istenmez.

Bu üç seviyeli gösterge, Etkinlik Monitörü’nün sürekli bellek baskısı grafiğinin yeniden üretimi değildir.

### Sıcaklık

Menü çubuğunda CPU ve RAM'in yanında **°C**, panelde **Sıcaklık** satırı bulunur. Apple Silicon'da IOKit'in IOHID sıcaklık servisleri salt okunur biçimde sorgulanır. `PMU… tdie…` adlarıyla sunulan geçerli çip sensörlerinin en yükseği gösterilir: bu tek bir CPU çekirdeğinin ortalaması, kasa yüzeyi veya ortam sıcaklığı değildir. Çip sensörü yoksa `PMU… tcal` sensörü kullanılır ve panelde **PMU sıcaklık sensörü** olarak ayrıca belirtilir. Pil, `tdev` veya kaynağı belirlenemeyen sensörler çip sıcaklığı diye gösterilmez.

0 °C ve altı, 150 °C ve üstü, sonsuz/NaN değerleri geçersiz sayılır. Okuma hatasında önceki değer korunmaz; menüde **— °C**, panelde açıklama görünür. Uykuda bağlantı ve değer temizlenir; uyanınca yeniden keşif yapılır. Sensör yoksa yeniden keşif denemeleri 30 saniye aralıklıdır. Başarılı ölçümde servisler yeniden kullanılır; sıcaklık sistem CPU/RAM ölçümüyle aynı 1/2/5 saniyelik aralıkta ve aynı arka plan kuyruğunda okunur, ek zamanlayıcı yoktur.

IOHID sıcaklık giriş noktaları belgelenmemiş sistem arayüzleridir; semboller çalışma zamanında `dlsym` ile denetlenir. Model/macOS sürümüne göre değişebilir ve tüm Mac'lerde sıcaklık erişimi garanti edilmez. Özellikle Intel sensörleri bu sürümde desteklenmez; uygulamanın diğer ölçümleri çalışmaya devam eder. Yönetici yardımcısı, sudo, ek izin veya üçüncü taraf bağımlılık kullanılmaz. Termal durum sınıfları dereceye çevrilerek tahmin üretilmez. [IOHID sıcaklık servislerine erişim örneği](https://github.com/zackwag/mac-temp/blob/main/mac-temp.m).

### En çok tüketen uygulamalar

`NSWorkspace.runningApplications` uygulama adlarını ve paket yollarını verir. `proc_listallpids` ve `proc_pidpath` ile bu uygulamaların ana işlemleri ve kendi paketleri içindeki yardımcı işlemleri eşleştirilir; aynı paket için tek satır üretilir. Komut satırı araçları ve bağımsız sistem servisleri bu uygulama listesine dahil değildir. Paket dışında çalışan, sorumluluğu güvenilir biçimde belirlenemeyen WebKit/XPC servisleri uygulamaya eklenmez; bu nedenle bazı uygulama toplamları Etkinlik Monitörü'nden düşük olabilir.

`proc_pid_rusage(RUSAGE_INFO_V2)` içindeki `ri_user_time + ri_system_time` sayaçlarının farkı, `mach_timebase_info` ile saniyeye çevrilir. CPU yüzdesi `deltaCPU / deltaZaman / mantıksalÇekirdekSayısı × 100` olur; üstteki toplam CPU ile aynı, tüm makinenin %100 olduğu ölçek kullanılır. Apple Silicon'da Mach zaman birimi nanosaniye varsayılmaz. İlk okuma, yeni yardımcı işlem, PID yeniden kullanımı (`ri_proc_start_abstime`), sayaç gerilemesi, hata ve uzun kesintilerde CPU için yeni taban beklenir.

RAM sıralaması `ri_phys_footprint` değerlerinin toplamıdır; GB/MB etiketleri 1024 tabanlıdır. Bu, uygulamaya yüklenen bellek ayak izidir; üstteki sistem fiziksel sayfa formülünden farklıdır. Sıkıştırılmış bellek muhasebesi ve paylaşılan kaynakların yüklenmesi nedeniyle satırları toplamak sistemin kullanılan RAM değerini vermez. Çıkmış veya okunamayan işlemler atlanır; eksik okuma varsa panel bunu belirtir. RAM ilk okumada, CPU ikinci geçerli okumada gösterilir. CPU ve RAM için ayrı ayrı en yüksek beş uygulama seçilir; beşten az uygulama ölçülebiliyorsa yalnızca mevcut olanlar gösterilir.

Bu API'lerin alanları için [Apple rusage_info_v2 tanımı](https://developer.apple.com/documentation/kernel/rusage_info_v2) ve [XNU ölçüm uygulaması](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/bsd_kern.c) incelenebilir.

Panel veya ilk 5 uygulama bölümü kapandığında uygulama taraması ve işlem sayaç geçmişi bırakılır; sistem CPU/RAM/sıcaklık ölçümü devam eder. Liste yeniden açılınca yeni CPU tabanı alınır. Ölçümler veya uygulama adları diske yazılmaz ve ağa gönderilmez.

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
- Ağ bağlantısı, alt süreç başlatma veya işlem sonlandırma yoktur. İşlem taraması yalnızca panel ve uygulama bölümü açıkken çalışır. Yönetici yetkisi istenmez. Uygulama başlangıç öğesi kaydetmez.
- Geçmiş varsayılan aralıkta yaklaşık 31, 1 saniyede en fazla 61 örnektir. CPU ve RAM sürekli ölçülür; panel kapalıyken grafik çizimi yoktur. Sabit bir pil/CPU tüketimi iddiası yapılmaz; donanım üzerinde Instruments ile ölçülmelidir.

## Testler ve doğrulama

39 XCTest, gerçek sistemden bağımsız kontrollü sayaç girdileriyle hesaplamaları denetler. Uygulama çalışma zamanında bu test girdilerini veya rastgele veri kullanmaz. Uygulama sıralaması testleri yardımcı işlem toplamlarını, Apple Silicon zaman dönüşümünü, PID yeniden kullanımını, panel kapanışındaki taban sıfırlamayı ve iki ayrı ilk 5 sıralamasını da kapsar. Sıcaklık testleri çip sensörü önceliğini, PMU yedeğini, pil/ortam ayrımını, geçersiz değerleri ve eksik ölçümleri denetler. Menü çubuğu testleri sekiz gösterge kombinasyonunu, tüm değerler gizliyken erişilebilir kimliği ve eksik ölçüm gösterimini kapsar.

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

**Son doğrulama — 15 Kasım 2026:** Apple Silicon üzerinde Xcode 27.2 ile Debug ve Apple Silicon + Intel Release uygulama derlemeleri başarılı. `swift test` ve Xcode test hedefinde ayrı ayrı **39 test, 0 hata**. Proje başvuruları, hedef üyelikleri, paylaşılan şema ve plist denetimleri geçti. Release paketinin iki mimarisi ve yerel imza bütünlüğü doğrulandı. Masaüstüne kurulan sürümde ok düğmesiyle uygulama listesini açma/kapatma ve CPU/RAM/sıcaklık anahtarlarını bağımsız değiştirme denendi. Sıcaklık normal kullanıcı yetkileriyle gerçek çip sensöründen okundu; bağlantı sıfırlanıp yeniden okuma denendi ve masaüstüne kurulan uygulamanın sıcaklık satırında gerçek °C değeri görüldü. Önceki doğrulamada iki ayrı ilk 5 uygulama listesi, yardımcı işlem toplamları, açık/koyu panel çizimi ve panel kapanınca sonuçların bırakılması kontrol edildi; tek çekirdekte kontrollü yoğun iş yüküyle Mach zaman dönüşümü doğrulandı (bir çekirdek ölçeğinde yaklaşık %100). VoiceOver, pil tüketimi ve gerçek cihaz uyku/uyanma davranışı ayrıca doğrulanmalıdır. Intel donanımında ve minimum macOS 13 üzerinde çalışma ayrıca denenmedi.

Önerilen kısa cihaz kontrolü: önce boşta CPU/RAM’i gözleyin; ardından normal bir iş yüküyle Etkinlik Monitörü’nün toplam CPU değerini karşılaştırın. Yenileme aralığını değiştirin, paneli kapatıp menü değerlerinin devam ettiğini kontrol edin, Mac’i uyutup uyandırın. İlk CPU değerinin yeniden beklendiğini ve uyku boşluğunun çizilmediğini doğrulayın. Sistem/Açık/Koyu görünümü ve klavye kısayollarını deneyin.

## .app oluşturma ve dışa aktarma

Tek adımda Apple Silicon + Intel Release uygulaması ve paylaşılabilir ZIP oluşturmak için:

```sh
bash scripts/package-release.sh
```

ZIP çıktısı `build/Distribution/statvision-macOS-universal.zip` konumundadır; içinde tek bir `statvision.app` paketi vardır. Betik iki mimarinin bulunduğunu ve uygulama imzasının bütünlüğünü denetler. Yerel imza, Developer ID veya Apple noter onayı anlamına gelmez.

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

