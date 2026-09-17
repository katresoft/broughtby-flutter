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
