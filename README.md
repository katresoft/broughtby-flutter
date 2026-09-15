# broughtby_flutter

Referral tracking SDK for mobile apps.

*[Türkçe](#türkçe) aşağıda.*

## Install

```yaml
dependencies:
  broughtby_flutter: ^0.1.0
```

## Usage

Three calls are enough:

```dart
import 'package:broughtby_flutter/broughtby_flutter.dart';

// 1. On app start
await BroughtBy.initialize(publicKey: 'bt_pk_...');

// 2. When the user signs in (call again with jwt: null on sign-out)
await BroughtBy.identify(jwt: supabase.auth.currentSession?.accessToken);

// 3. Once, after sign-in
final result = await BroughtBy.captureAttribution();
```

`captureAttribution` is idempotent; it's safe to call on every launch.

### Letting the user enter a code by hand

On iOS this is the real channel — add a field to your onboarding flow:

```dart
final result = await BroughtBy.submitCode(controller.text);

switch (result) {
  case BroughtByOk(:final value):
    showMessage(value.isAttributed ? 'Code applied' : 'Code not found');
  case BroughtByFailure(:final error):
    showMessage(switch (error.kind) {
      BroughtByErrorKind.unknownCode => 'This code is not valid',
      BroughtByErrorKind.alreadyClaimed => 'You already have a referral code',
      BroughtByErrorKind.selfReferral => "You can't use your own code",
      _ => 'Not right now, try again later',
    });
}
```

### Affiliate info

```dart
final info = (await BroughtBy.getAffiliate()).valueOrNull;
// info.code      → 'AHMET34'
// info.shareUrl  → 'https://go.broughtby.io/r/vakitnakit/AHMET34'
```

### The earnings screen

```dart
await BroughtBy.openDashboard(context, title: 'Invite friends');
```

The screen is rendered on the server and opens in a webview inside your app,
so its design changes without an app release. It speaks Turkish, English,
German, Spanish and French.

`title` is yours to translate — the SDK ships no copy of its own, and the app
bar shows no title unless you pass one. The language follows the locale your
app is running in, which is not always the device language: someone with a
Turkish phone may be using your app in English. Override it when you need to:

```dart
await BroughtBy.openDashboard(context, locale: 'de');
```

## Platform setup

### Android

The Play Install Referrer plugin needs no extra setup. When a user arrives
from a Play Store link, the code is captured automatically.

### iOS

iOS has **no** deferred deep link mechanism. The code does not arrive
automatically when a user installs from the App Store. Two channels remain:

1. **Clipboard** — the landing page writes the code to the clipboard, and
   the SDK reads it on first launch. iOS shows the user a "pasted from
   clipboard" notice.
2. **Manual entry** — `submitCode`. This is the real, reliable path.

If you use Universal Links, add `applinks:go.broughtby.io` to
`Associated Domains`. This only works while the app is **already installed**.

## Design notes

**There is no method for reporting a purchase.** This isn't an oversight:
the only source of truth for money is the payment provider's webhook,
received by the server. The SDK only ever says "this user came from this
code."

**Attribution is never sent without a verified identity.** Requests made
before `identify` is called never reach the network; the server also
verifies the token on its own side.

**Errors are never thrown as exceptions.** Referral isn't the app's core
function — a network error shouldn't crash the app. Every result comes
back as a `BroughtByResult`.

**The clipboard channel is deliberately narrow.** If the clipboard content
doesn't look exactly like a code, it's ignored; we never scan it for a
code hidden inside. We never send whatever random text is on the user's
clipboard to the server.

## Development

```bash
flutter pub get
flutter analyze
flutter test
```

---

## Türkçe

Mobil uygulamalar için referral takip SDK'si.

### Kurulum

```yaml
dependencies:
  broughtby_flutter: ^0.1.0
```

### Kullanım

Üç çağrı yeterli:

```dart
import 'package:broughtby_flutter/broughtby_flutter.dart';

// 1. Uygulama başlarken
await BroughtBy.initialize(publicKey: 'bt_pk_...');

// 2. Kullanıcı giriş yaptığında (çıkışta jwt: null ile tekrar çağırın)
await BroughtBy.identify(jwt: supabase.auth.currentSession?.accessToken);

// 3. Kullanıcı giriş yaptıktan sonra, bir kez
final result = await BroughtBy.captureAttribution();
```

`captureAttribution` idempotenttir; her açılışta çağırmak güvenlidir.

#### Davet kodunu elle girdirmek

iOS'ta asıl kanal budur — onboarding'de bir alan koyun:

```dart
final result = await BroughtBy.submitCode(controller.text);

switch (result) {
  case BroughtByOk(:final value):
    showMessage(value.isAttributed ? 'Kod uygulandı' : 'Kod bulunamadı');
  case BroughtByFailure(:final error):
    showMessage(switch (error.kind) {
      BroughtByErrorKind.unknownCode => 'Bu kod geçerli değil',
      BroughtByErrorKind.alreadyClaimed => 'Zaten bir davet kodun var',
      BroughtByErrorKind.selfReferral => 'Kendi kodunu kullanamazsın',
      _ => 'Şimdi olmadı, sonra tekrar dene',
    });
}
```

#### Affiliate bilgisi

```dart
final info = (await BroughtBy.getAffiliate()).valueOrNull;
// info.code      → 'AHMET34'
// info.shareUrl  → 'https://go.broughtby.io/r/vakitnakit/AHMET34'
```

#### Kazanç ekranı

```dart
await BroughtBy.openDashboard(context, title: 'Arkadaşını davet et');
```

Ekran sunucuda çiziliyor ve uygulamanın içinde bir webview'da açılıyor; bu
yüzden tasarımı yeni sürüm gerektirmeden değişiyor. Türkçe, İngilizce,
Almanca, İspanyolca ve Fransızca biliyor.

`title` size ait — SDK kendi metnini taşımıyor ve siz vermezseniz başlık
çubuğu boş kalır. Dil, uygulamanızın o an çalıştığı dili izliyor; bu her
zaman cihaz dili değil: telefonu Türkçe olan biri uygulamanızı İngilizce
kullanıyor olabilir. Gerektiğinde açıkça verebilirsiniz:

```dart
await BroughtBy.openDashboard(context, locale: 'de');
```

### Platform kurulumu

#### Android

Play Install Referrer eklentisi başka bir kuruluma ihtiyaç duymaz. Kullanıcı Play Store linkinden geldiğinde kod otomatik yakalanır.

#### iOS

iOS'ta deferred deep link mekanizması **yoktur**. Kullanıcı App Store'dan kurduğunda kod otomatik gelmez. İki kanal kalır:

1. **Pano** — landing sayfası kodu panoya yazar, SDK ilk açılışta okur. iOS kullanıcıya "yapıştırdı" bildirimi gösterir.
2. **Elle giriş** — `submitCode`. Asıl güvenilir yol budur.

Universal Link kullanacaksanız `Associated Domains` içine `applinks:go.broughtby.io` ekleyin. Bu yalnızca uygulama **zaten yüklüyken** çalışır.

### Tasarım notları

**Satın alma bildiren bir metot yoktur.** Bu bir eksik değil: para ile ilgili tek gerçek kaynak sunucunun aldığı ödeme sağlayıcısı webhook'udur. SDK yalnızca "bu kullanıcı bu koddan geldi" der.

**Kimlik doğrulanmadan attribution gönderilmez.** `identify` çağrılmadan yapılan istekler ağa hiç çıkmaz; sunucu da token'ı kendi tarafında doğrular.

**Hatalar istisna olarak fırlatılmaz.** Referral, uygulamanın ana işlevi değil — ağ hatası uygulamayı çökertmemeli. Tüm sonuçlar `BroughtByResult` olarak döner.

**Pano kanalı bilerek dardır.** Panodaki içerik tam olarak bir koda benzemiyorsa yok sayılır; içinden kod aranmaz. Kullanıcının panosundaki rastgele metni sunucuya göndermeyiz.

### Geliştirme

```bash
flutter pub get
flutter analyze
flutter test
```
