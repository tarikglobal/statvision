# statvision’ı açma ve paylaşma

## Açma

1. `statvision.app` simgesine çift tıklayın.
2. CPU ve RAM paneli açılır. Sonrasında pencerenin dışına tıklayarak kapatabilirsiniz.
3. Paneli tekrar açmak için ekranın üstündeki CPU/RAM yazısına tıklayın veya uygulama simgesine tekrar çift tıklayın.
4. Uygulamayı tamamen kapatmak için paneldeki **Çıkış** düğmesini kullanın.

Uygulama menü çubuğunda çalışır; Dock’ta ayrı bir simge tutmaz. Finder `.app` paketini tek bir uygulama simgesi olarak gösterir. İçindeki dosyaları ayrı ayrı açmanız gerekmez.

## Başka Mac’e gönderme

`statvision-macOS-universal.zip` dosyasını gönderin. Masaüstüne hazırlanan kopyanın adı `statvision-paylasim.zip` olabilir; içeriği aynıdır.

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
swift scripts/generate-icon.swift
iconutil -c icns build/AppIcon.iconset -o statvision/Resources/AppIcon.icns
```
