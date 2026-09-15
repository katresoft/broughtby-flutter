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
