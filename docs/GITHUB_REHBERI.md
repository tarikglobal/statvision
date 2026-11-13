# statvision ile GitHub’a başlangıç

Git, kodun değişiklik geçmişini bilgisayarınızda tutar. GitHub bu geçmişi çevrim içi saklar ve paylaşmayı kolaylaştırır. Proje dosyaları Mac’inizde kalır; GitHub’a gönderdiğiniz sürümler ayrıca hesabınızda saklanır.

## Size ne kazandırır?

- **Geçmiş:** Hangi dosyada, ne zaman, neden değişiklik yapıldığını görebilirsiniz.
- **Geri dönüş:** Bir değişiklik hata oluşturursa önceki kayıtlı sürüme dönebilirsiniz.
- **Başka bilgisayarda devam:** Depoyu diğer Mac’inize indirip geliştirmeyi sürdürebilirsiniz.
- **Düzen:** Hataları ve fikirleri Issues bölümünde takip edebilirsiniz.
- **Birlikte çalışma:** Başka biri, değişiklik önerisini ana sürümle birleştirmeden önce incelemenize sunabilir.

GitHub’a gönderilmemiş değişiklikler yalnızca bilgisayarınızdadır. GitHub, Mac’inizin tamamının yedeği değildir. Kaynak kodun yüklenmesi, uygulamanın derlendiği veya çalışmasının doğrulandığı anlamına gelmez.

## Karşınıza çıkacak kelimeler

| Terim | statvision için anlamı |
| --- | --- |
| Repository / repo | Kod, testler, açıklamalar ve değişiklik geçmişini içeren proje deposu. |
| Commit | “Yenileme ayarları eklendi” gibi bir açıklamayla oluşturulan sürüm kaydı. |
| Push | Bilgisayardaki commit’leri GitHub’a gönderme. |
| Pull | GitHub’daki yeni kayıtları bilgisayara alma. |
| Clone | Depoyu geçmişiyle birlikte bir bilgisayara ilk kez indirme. |
| Branch | Örneğin yeni bir tasarımı ana sürüme hemen dokunmadan geliştirdiğimiz dal. |
| main | Projenin ana geliştirme dalı. |
| Pull request / PR | Bir daldaki değişiklikleri inceleyip ana dala ekleme önerisi. |
| Merge | İncelenen değişiklikleri birleştirme. |
| Issue | Hata, fikir veya yapılacak iş kaydı. |
| Private | Depoya yalnızca yetki verilen hesapların erişebilmesi. |
| Public | Deponun herkes tarafından görülebilmesi. |

## Biz nasıl ilerleyeceğiz?

1. Yapılacak değişikliği belirleyeceğiz: örneğin panelin yazılarını büyütmek.
2. Kodu Mac’te değiştireceğiz; gerektiğinde ayrı bir dal kullanacağız.
3. İlgili kontrolleri ve testleri çalıştıracağız. Çalıştıramadığımız kontrolleri açıkça belirteceğiz.
4. Değişikliği açıklayan bir commit oluşturacağız.
5. GitHub’a göndereceğiz. Ayrı dal kullanıyorsak PR ile inceleyip birleştireceğiz.

Commit, açık dosyayı kaydetmekten farklıdır: birbiriyle ilgili dosya değişikliklerini birlikte kayıt altına alır. Commit’ten sonra yapılan yeni düzenlemeler otomatik olarak önceki commit’e eklenmez.

## Depoda hangi dosyalar bulunur?

Swift kaynakları, Xcode proje ayarları, testler, README ve doğrulama betiği bulunur. README, GitHub’da projenin açıklaması olarak görüntülenir.

`.gitignore`, derleme çıktıları ve kişisel Xcode ayarları gibi takip edilmeyecek dosyaları belirtir. Bu dosyalar Mac’inizde kalabilir; Git’e otomatik eklenmez. Daha önce Git’e eklenmiş bir dosyayı `.gitignore` içine yazmak geçmişten silmez.

Kod deposu ile kurulabilir uygulama farklı şeylerdir. Uygulamayı çalıştırmak için kaynak kodu Xcode’da derlemek gerekir. Daha sonra derlenmiş `.app` paketini GitHub Releases bölümünde ayrıca paylaşabiliriz.

## Resmî kaynaklar

- [GitHub hesabıyla başlangıç](https://docs.github.com/en/get-started/onboarding/getting-started-with-your-github-account)
- [GitHub’a bağlanma yolları](https://docs.github.com/en/get-started/using-github/connecting-to-github)
- [Bilgisayardaki mevcut projeyi yükleme](https://docs.github.com/en/migrations/importing-source-code/using-the-command-line-to-import-source-code/adding-locally-hosted-code-to-github)
