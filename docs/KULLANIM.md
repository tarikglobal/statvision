# statvision’ı açma ve paylaşma

## Açma

1. `statvision.app` simgesine çift tıklayın.
2. CPU ve RAM paneli açılır. Sonrasında pencerenin dışına tıklayarak kapatabilirsiniz.
3. Paneli tekrar açmak için ekranın üstündeki CPU/RAM yazısına tıklayın veya uygulama simgesine tekrar çift tıklayın.
4. Uygulamayı tamamen kapatmak için paneldeki **Çıkış** düğmesini kullanın.

Panelin altındaki **En çok tüketen 5 uygulama** başlığının yanındaki oka tıklayarak listeyi açın veya kapatın. Liste başlangıçta kapalıdır; son seçiminiz hatırlanır. Açıkken **CPU** veya **RAM** sekmesine tıklayın. CPU yüzdesi toplam işlemci kapasitesinin payını, RAM değeri uygulamanın bellek ayak izini gösterir. İlk CPU sıralaması bir yenileme aralığı sonra gelir. Küçük ekranlarda aşağı kaydırarak bu bölüme ulaşabilirsiniz. Liste ya da panel kapandığında uygulama taraması durur.

Panelin altındaki **Ayarlar** düğmesinden **Menü çubuğunda göster** seçeneklerine ulaşabilirsiniz. **CPU kullanımı**, **RAM kullanımı** ve **Sıcaklık** bağımsız olarak açılıp kapatılır; seçim anında uygulanır ve sonraki açılışta korunur. Üçünü de kapatırsanız paneli açabilmeniz için menü çubuğunda statvision simgesi kalır. Bu seçenekler ana paneldeki ölçümleri gizlemez.

**Toplam CPU**, bütün bilgisayarın yüküdür; ilk 5 uygulamanın toplamına eşit olmak zorunda değildir. CPU listesinin altındaki **Bu 5 satırda ölçülen** ve **Diğer / ölçülemeyen** satırları farkı gösterir. Sistem servisleri, arka plan işleri ve listede olmayan uygulamalar da CPU kullanır. **≥** işareti görünen uygulamada bazı yardımcı işlemler için yeni ölçüm bekleniyordur; o anda ölçülebilen pay gösterilmeye devam eder.

Listedeki bir uygulamayı kapatmak için satırın sağındaki **×** düğmesine tıklayın. Uygulamaya normal kapatma isteği gönderilir; kaydetme uyarısı varsa uygulamanın kendi penceresinde yanıtlayın. Kapatmayı iptal ederseniz uygulama açık kalır. Yanıt vermeyen uygulamalar otomatik olarak zorla kapatılmaz. Finder gibi sistem uygulamalarında ve statvision'ın kendi satırında × pasiftir; üzerine gelince açıklaması görünür.

Uygulama menü çubuğunda çalışır; Dock’ta ayrı bir simge tutmaz. Finder `.app` paketini tek bir uygulama simgesi olarak gösterir. İçindeki dosyaları ayrı ayrı açmanız gerekmez.

Menü çubuğunda CPU ve RAM'in yanındaki **°C** değeri sıcaklığı gösterir. Panelde **Sıcaklık** satırında ölçüm kaynağı belirtilir. Bu Mac'te en sıcak geçerli çip sensörü kullanılır; kasa yüzeyi veya ortam sıcaklığı değildir. Desteklenen sensör okunamıyorsa **— °C** görünür. Değer, Ayarlar'da seçilen 1/2/5 saniyelik ölçüm aralığıyla yenilenir.

Paneldeki **Güç tüketimi** kartı, Mac'in bildirdiği son tüketimi **W** olarak gösterir. Sensörün kendi yenileme hızı uygulamadan daha yavaş olabilir. Bu değer priz ölçümü veya adaptörün üzerinde yazan maksimum güç değildir. Desteklenen sistem yükü verisi yoksa yalnızca pille çalışırken **Pil deşarjı** kaynağı kullanılabilir; güvenilir veri yoksa **— W** görünür.

## Göz modu

**Ayarlar → Menü çubuğu modu → Göz modu** seçin. Menüdeki yazılar tek bir göz simgesine dönüşür. **Göz kırpma aralığı** satırındaki yukarı/aşağı oklarla süreyi **1–30 saniye** arasında seçebilirsiniz. Varsayılan **3 saniye**dir. Seçtiğiniz süre anında uygulanır ve sonraki açılışta hatırlanır. Göz seçtiğiniz aralıkta kırpılır; fareyi üzerine götürdüğünüzde CPU, RAM, sıcaklık ve watt küçük, saydam bir panelde görünür. Fareyi uzaklaştırınca kapanır. Göze tıklamak ana ekranı açar. Normal yazılara dönmek için aynı yerden **Göstergeler** seçin. Mod tercihiniz hatırlanır.

Sistemde **Hareketi azalt** açıksa göz kırpmaz; üzerine gelince değerleri yine gösterir. **Saydamlığı azalt** açıksa küçük panel opak görünür. Ana ekranın **Ayarlar** ve **Çıkış** düğmeleri aşağı kaydırmadan da erişilebilir.

## Başka Mac’e gönderme

`statvision-macOS-universal.zip` dosyasını gönderin. Proje klasöründeki paylaşım kopyasının adı `statvision-paylasim.zip`tir; içeriği aynıdır.

Alıcı ZIP’e çift tıklayıp `statvision.app` dosyasını çıkarır. Uygulamayı Uygulamalar klasörüne taşıyabilir, ardından çift tıklayarak açabilir. Xcode veya Swift kurulması gerekmez. Paket hem Apple Silicon hem Intel mimarisini içerir; minimum sürüm macOS 13’tür. Intel donanımında ve macOS 13 üzerinde çalışma ayrıca denenmemiştir.

Bu sürüm yerel (ad hoc) imzalıdır; Developer ID ile imzalanmış ve Apple tarafından noter onayı verilmiş genel dağıtım sürümü değildir. Başka Mac’lerde Gatekeeper uygulamanın açılmasını engelleyebilir. ZIP’e dönüştürmek bu durumu değiştirmez. Genel dağıtım için geliştiricinin Developer ID imzası ve Apple noter onayını tamamlaması gerekir.

[Apple’ın Mac uygulamalarını dağıtma açıklaması](https://developer.apple.com/macos/distribution/)

## Geliştirici için yeniden paketleme

Proje klasöründe:

```sh
bash scripts/package-release.sh
```

Çıktılar:

- `build/Build/Products/Release/statvision.app`
- `build/Distribution/statvision-macOS-universal.zip`

Masaüstüne ilk kurulum için `bash scripts/install-desktop.sh` çalıştırılabilir. Bu işlem uygulamayı ve ZIP’i masaüstüne kopyalar, önceki çalışan statvision sürecini kapatıp yeni uygulamayı açar. Var olan masaüstü dosyalarını değiştirmez.

Simgeyi yeniden üretmek için:

```sh
bash scripts/generate-icon.sh
```
