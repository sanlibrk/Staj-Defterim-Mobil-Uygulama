# Staj Defteri

Staj Defteri, öğrencilerin staj bilgilerini ve günlük çalışmalarını kaydedip düzenlenebilir bir Word raporuna dönüştürdüğü ücretsiz bir iOS uygulamasıdır. SwiftUI ile geliştirilmiştir ve iOS 17 ve üzerini hedefler. Kayıt, fotoğraf işleme ve DOCX üretimi cihazda gerçekleşir.

## Kullanım

1. Öğrenci bilgilerini, staj yerini ve staj tarihlerini girin.
2. Tarihli bir günlük açın ve **Ne yaptım**, **Nasıl yaptım**, **Sonuç** ve **Öğrendiklerim** alanlarını doldurun. Fotoğraf seçebilir veya kamerayla çekebilir, her fotoğrafa açıklama ekleyebilirsiniz.
3. Kaydedilen stajları ve günlükleri yeniden açın, düzenleyin veya silin.
4. Stajın içinden **Word belgesi oluştur** seçeneğini kullanın. Kapakta staj bilgileri yer alır ve her günlük yeni bir sayfada başlar. Öğrencinin girdiği metin, fotoğraflar ve açıklamalar rapora aktarılır. Word'de metni ve açıklamaları düzenleyebilirsiniz.

<img src="docs/media/docx-preview.png" alt="Word'de açılan örnek DOCX'in tarihli günlük sayfası, çalışma alanları ve açıklamalı gömülü görseli" width="500">

*Test verileriyle üretilen bir günlük sayfası. Görüntü Microsoft Word çıktısından alınmıştır.*

## Mimari

- **iOS uygulaması.** SwiftUI staj ve günlük ekranlarını, UIKit ve AVFoundation kamera akışını, PhotosPicker ise seçilen fotoğrafların içe aktarımını yönetir. Belge, iOS paylaşım ekranından kullanıcının seçtiği konuma veya uygulamaya gönderilir. [Uygulama kaynakları](Sources/StajDefteriApp)
- **Yerel veri bütünlüğü.** Foundation tabanlı Swift paketindeki `JournalStore` actor'ı okuma ve yazmaları sıraya alır. Uygulamanın özel alanında sürümlü bir JSON dosyası ve ayrı JPEG dosyaları saklanır. Yeni fotoğraflar yazıldıktan sonra JSON atomik olarak değiştirilir. Başarısız yazımda önceki kayıt korunur, kullanım dışı kalan fotoğraflar başarılı işlemden sonra temizlenir. Günlük tarihleri saat dilimi değişse de aynı takvim gününü temsil eder. [Veri katmanı](Sources/StajDefteriCore/JournalStore.swift) · [Veri modelleri](Sources/StajDefteriCore/Models.swift)
- **DOCX üretimi.** Dışa aktarım, güncel kayıtlar ve onlara bağlı fotoğrafların birlikte okunmasıyla başlar. Üretici, öğrencinin metnini düzenlenebilir WordprocessingML paragraflarına yerleştirir, JPEG dosyalarını pakete gömer ve her günlük başlığına sayfa başlangıcı kuralı uygular. DOCX yerel olarak oluşturulur ve üçüncü taraf kütüphane gerektirmez. [DOCX üreticisi](Sources/StajDefteriCore/DOCXExporter.swift)

## Doğrulama

| Kapsam | Sonuç |
| --- | --- |
| Swift paket testleri | Linux ve GitHub'ın macOS çalıştırıcısında **7/7 geçti**. Kayıtları yeniden açma, düzenleme, silme, yazma hatasından sonra tekrar deneme, takvim tarihi, DOCX yapısı ve güncel kayıtlardan dışa aktarım sınandı. |
| Microsoft Word | Swift'in ürettiği örnek DOCX Windows'ta Word ile açıldı. Kapak ve iki günlük üç sayfada görüntülendi. Gömülü fotoğraflar ve açıklamalar incelendi. Günlük metni düzenlendi ve yeniden açıldığında değişikliğin korunduğu doğrulandı. |
| iOS arşiv derlemesi | Xcode ile imzasız iOS Release arşivi oluşturuldu. Arşivdeki uygulama bilgileri ve varlık kataloğu kontrol edildi. |
| iPhone simülatörü | iPhone 17 simülatöründe Debug derlemesi kuruldu, başlatıldı ve açılışın ardından çalıştığı doğrulandı. Fiziksel cihaz kontrolleri aşağıdadır. |

[Swift testleri](Tests/StajDefteriCoreTests) · [iOS CI sonuçları](https://github.com/sanlibrk/Staj-Defterim-Mobil-Uygulama/actions/workflows/ios.yml)

## Yerelde çalıştırma

iOS uygulamasını çalıştırmak için macOS üzerinde Xcode 15 veya üzeri gerekir.

```sh
git clone https://github.com/sanlibrk/Staj-Defterim-Mobil-Uygulama.git
cd Staj-Defterim-Mobil-Uygulama
open StajDefteri.xcodeproj
```

Xcode'da **StajDefteri** şemasını ve iOS 17 veya üzeri bir iPhone ya da iPad simülatörünü seçin. Gerçek cihaz için **Signing & Capabilities** altında geliştirme ekibinizi belirleyin. Kamera çekimini gerçek cihazda deneyin.

Platformdan bağımsız çekirdek testlerini depo kökünden çalıştırın.

```sh
swift test
```

## Sürüm öncesi cihaz kontrolü

- [ ] Uçak modunda bir staj ve iki farklı tarihte günlük oluşturun. Dört metin alanını doldurun, fotoğraf ve açıklama ekleyin. Uygulamayı tamamen kapatıp açtıktan sonra kayıtları yeniden açın.
- [ ] Bir günlük ve fotoğraf açıklamasını düzenleyin. Bir fotoğrafı, bir günlüğü ve ayrı bir deneme stajını silin. Uygulamayı yeniden açıp değişikliklerin korunduğunu kontrol edin.
- [ ] Fotoğraf seçicide birden çok görsel seçin ve ayrı bir denemede seçimi iptal edin. Eklerin seçiminizle eşleştiğini doğrulayın.
- [ ] Gerçek iPhone'da ilk kamera isteğini reddedin. Günlük kaydının ve fotoğraf seçicinin kullanılabildiğini kontrol edin. Ardından Ayarlar'dan izin verip bir fotoğraf çekin ve günlüğe kaydedin.
- [ ] İki günlük içeren bir DOCX'i iOS paylaşım ekranından Dosyalar'a kaydedin. Word'de tarihlerin yeni sayfalardan başladığını, görsellerin ve açıklamaların doğru güne ait olduğunu ve metnin düzenlenip yeniden kaydedilebildiğini kontrol edin.
- [ ] iPad'de dikey ve yatay görünümü, desteklenen iOS sürümlerinde temel akışları, büyük metin boyutunu ve VoiceOver'ı kontrol edin.

## English summary

Staj Defteri is a free, offline SwiftUI internship journal for iOS 17 and later. Students can log their daily work, attach captioned photos, and export an editable Word document with a cover and a new page for each day. A Foundation-only Swift package handles local storage and DOCX generation. The core passed seven automated tests, and a generated report was opened, visually checked, edited, and saved in Microsoft Word.
