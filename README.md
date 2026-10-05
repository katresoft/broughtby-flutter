# broughtby_flutter

Referral tracking SDK for mobile apps.

*[Türkçe](#türkçe) aşağıda.*

## Install

```yaml
dependencies:
  broughtby_flutter: ^0.3.0
```

## Usage

Three calls are enough:

```dart
import 'package:broughtby_flutter/broughtby_flutter.dart';

// 1. On app start
await BroughtBy.initialize(publicKey: 'bt_pk_...');

// 2. When the user signs in (call again with jwt: null on sign-out)
await BroughtBy.identify(
  jwt: supabase.auth.currentSession?.accessToken,
  revenueCatUserId: await Purchases.appUserID,
);

// 3. Once, after sign-in
final result = await BroughtBy.captureAttribution();
```

`captureAttribution` is idempotent; it's safe to call on every launch.

**Pass `revenueCatUserId`.** Purchases reach Broughtby under RevenueCat's
user ID. Without it, a purchase only matches the user if you log RevenueCat
in with exactly the same ID as the session token's `sub` — and a purchase
that matches no user earns nobody anything, with no error anywhere.

### Setup that fills itself in

There is very little to type into the Broughtby console. The first time
the app runs, the SDK reports what the app already knows about itself:

| Reported | Used for |
|---|---|
| Bundle ID / package name | Sending invitees to the right store page |
| Android signing fingerprint | App Links |
| Who issued the session token, and how it's signed | Suggesting how to verify sign-in |

App details are applied as they arrive. The sign-in service is only
*suggested*: you confirm it with one click in the console, because that
setting decides who can speak for your users. Reports carry your public
key and nothing about the user, and they stop once the console has
everything.

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
      BroughtByErrorKind.windowExpired => 'Referral codes are for new users',
      _ => 'Not right now, try again later',
    });
}
```

### Affiliate info

```dart
final info = (await BroughtBy.getAffiliate()).valueOrNull;
// info.code      → 'AHMET34'
// info.shareUrl  → 'https://broughtby.vercel.app/r/vakitnakit/AHMET34'
```

The generated code can be replaced once with one the user chooses:

```dart
if (info.canCustomize) {
  final result = await BroughtBy.customizeCode('AHMET34');
  // error.kind: codeTaken, invalidCode, alreadyCustomized
}
```

The old code stops working, so offer this before the user starts sharing.

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
   the SDK reads it **once**, on the first `captureAttribution` after
   install. iOS shows the user a paste prompt that one time.
2. **Manual entry** — `submitCode`. This is the real, reliable path.

If you use Universal Links, add `applinks:broughtby.vercel.app` to
`Associated Domains` (this will move to `go.broughtby.io` once that domain
is registered). This only works while the app is **already installed**.

The domain is shared by every app on Broughtby, so each app is associated
with its own path only: `/r/<your-slug>/`. Use the same prefix in your
Android intent filter (`android:pathPrefix="/r/<your-slug>/"`), otherwise
another app's invite could open yours.

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

**The clipboard is read once, and narrowly.** It's looked at on the first
launch after install — the one moment it can plausibly hold an invite
code — and never again. Content that doesn't look exactly like a code is
ignored; we never scan it for a code hidden inside. Reading it on every
launch would prompt the user each time and would keep sending whatever
short text they last copied.

**Setup reports are suggestions, not authority.** They're sent with the
public key alone, which anyone can extract from the app, so the server
never trusts them: app details only fill fields that are still empty, and
the sign-in service waits for a human to confirm it.

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
  broughtby_flutter: ^0.3.0
```

### Kullanım

Üç çağrı yeterli:

```dart
import 'package:broughtby_flutter/broughtby_flutter.dart';

// 1. Uygulama başlarken
await BroughtBy.initialize(publicKey: 'bt_pk_...');

// 2. Kullanıcı giriş yaptığında (çıkışta jwt: null ile tekrar çağırın)
await BroughtBy.identify(
  jwt: supabase.auth.currentSession?.accessToken,
  revenueCatUserId: await Purchases.appUserID,
);

// 3. Kullanıcı giriş yaptıktan sonra, bir kez
final result = await BroughtBy.captureAttribution();
```

`captureAttribution` idempotenttir; her açılışta çağırmak güvenlidir.

**`revenueCatUserId` verin.** Satın almalar Broughtby'a RevenueCat'in kullanıcı kimliğiyle ulaşır. Verilmezse satın alma, ancak RevenueCat'e oturum token'ındaki `sub` ile birebir aynı kimlikle giriş yaptırıyorsanız kullanıcıyla eşleşir; eşleşmeyen satın alma kimseye bir şey kazandırmaz ve hiçbir yerde hata görünmez.

#### Kendini dolduran kurulum

Broughtby paneline elle yazılacak çok az şey var. Uygulama ilk çalıştığında SDK, uygulamanın kendisi hakkında zaten bildiklerini bildirir: bundle kimliği ya da paket adı, Android imza parmak izi, oturum token'ını kimin ürettiği ve nasıl imzalandığı.

Uygulama bilgileri geldikçe yazılır. Giriş servisi ise yalnızca *önerilir*; panelde tek tıkla onaylarsınız, çünkü o ayar kullanıcılarınız adına kimin konuşabileceğini belirler. Bildirimler public anahtarınızı taşır, kullanıcı hakkında hiçbir şey taşımaz ve panel her şeyi öğrendiğinde durur.

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
// info.shareUrl  → 'https://broughtby.vercel.app/r/vakitnakit/AHMET34'
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

1. **Pano** — landing sayfası kodu panoya yazar, SDK kurulumdan sonraki ilk `captureAttribution` çağrısında **bir kez** okur. iOS yapıştırma iznini yalnızca o an sorar.
2. **Elle giriş** — `submitCode`. Asıl güvenilir yol budur.

Universal Link kullanacaksanız `Associated Domains` içine `applinks:broughtby.vercel.app` ekleyin (`broughtby.io` alan adı alınınca `go.broughtby.io` olacak). Bu yalnızca uygulama **zaten yüklüyken** çalışır.

Alan adı Broughtby'daki bütün uygulamalar için ortaktır; her uygulama yalnızca kendi yoluyla ilişkilendirilir: `/r/<kısa-adınız>/`. Android intent filter'ında da aynı öneki kullanın (`android:pathPrefix="/r/<kısa-adınız>/"`), yoksa başka bir uygulamanın daveti sizinkini açabilir.

### Tasarım notları

**Satın alma bildiren bir metot yoktur.** Bu bir eksik değil: para ile ilgili tek gerçek kaynak sunucunun aldığı ödeme sağlayıcısı webhook'udur. SDK yalnızca "bu kullanıcı bu koddan geldi" der.

**Kimlik doğrulanmadan attribution gönderilmez.** `identify` çağrılmadan yapılan istekler ağa hiç çıkmaz; sunucu da token'ı kendi tarafında doğrular.

**Hatalar istisna olarak fırlatılmaz.** Referral, uygulamanın ana işlevi değil — ağ hatası uygulamayı çökertmemeli. Tüm sonuçlar `BroughtByResult` olarak döner.

**Pano bir kez ve dar okunur.** Kurulumdan sonraki ilk açılışta bakılır — davet kodu taşıyabileceği tek an — ve bir daha bakılmaz. İçerik tam olarak bir koda benzemiyorsa yok sayılır; içinden kod aranmaz. Her açılışta okumak kullanıcıya her seferinde izin sordurur ve en son kopyaladığı kısa metni göndermeye devam ederdi.

**Kurulum bildirimleri öneridir, yetki değil.** Yalnızca public anahtarla gönderilirler ve o anahtarı uygulamadan herkes çıkarabilir; bu yüzden sunucu onlara güvenmez: uygulama bilgileri yalnızca boş alanları doldurur, giriş servisi bir insanın onayını bekler.

### Geliştirme

```bash
flutter pub get
flutter analyze
flutter test
```
