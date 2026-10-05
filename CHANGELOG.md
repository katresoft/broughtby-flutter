## 0.3.0

Requires a Broughtby server with the `setup`, `identity` and
`affiliate/code` endpoints. Against an older server the new calls fail
quietly and everything else behaves as before.

- **Setup that fills itself in.** On first run the SDK reports what the app
  already knows about itself — bundle ID or package name, Android signing
  fingerprint, and who issued the session token — so the console no longer
  asks you to copy them in. App details are applied as they arrive; the
  sign-in service is suggested and waits for one click of confirmation.
  Reports carry the public key only and stop once the console is complete.
- **`identify` takes `revenueCatUserId`.** Pass `await Purchases.appUserID`.
  Purchases then match the user without having to log RevenueCat in under
  the same ID as the session token's `sub` — a requirement that failed
  silently when missed.
- **The clipboard is read once per install** instead of on every
  `captureAttribution`. Previously an unattributed user was prompted to
  allow pasting on each launch, and any short alphanumeric text on their
  clipboard was sent to the server each time.
- Added `BroughtBy.customizeCode` — replaces the generated code with one
  the user chooses, once.
- New error kinds: `windowExpired` (referrals only count for new users),
  `codeTaken`, `invalidCode`, `alreadyCustomized`. These were previously
  reported as `rejected`; exhaustive `switch`es over `BroughtByErrorKind`
  need the new cases.
- New dependency: `package_info_plus`.

## 0.2.2

- Widened the `app_links` constraint from `^6.3.2` to `>=6.3.2 <8.0.0`.
  It pinned below app_links 7.x, which conflicted with any app that
  already resolves app_links 7 through another dependency. Only
  `getInitialLink()` is used, and that call is unchanged across 6.x
  and 7.x, so both majors work.

## 0.2.1

- Fixed the default `baseUrl` and `shareUrlBase`: they pointed at
  `api.broughtby.io` / `go.broughtby.io`, domains that are not registered
  yet, so every call failed unless you passed both explicitly. They now
  default to the live `broughtby.vercel.app` deployment and will move to
  the `broughtby.io` subdomains once that domain is registered.

## 0.2.0

- `openDashboard` now takes `title` and `locale`. The language follows the
  locale your app runs in, which is not always the device language.
- The dashboard app bar shows no title unless you pass one.

## 0.1.1

- Moved the repository to https://github.com/katresoft/broughtby-flutter.

## 0.1.0

Initial release.

- Three core calls: `initialize`, `identify`, `captureAttribution`.
- `submitCode` for manual code entry on iOS.
- `getAffiliate` to read the user's code and share link.
- `openDashboard` to open the user's own earnings screen inside the app.
- Automatic install-source capture on Android (`play_install_referrer`).
