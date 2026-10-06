## 0.4.0

Fixes for codes that were lost or read from the wrong place. Several of
them change behaviour; read **Changed** before upgrading.

### Fixed

- **A code is no longer lost to a dropped connection.** The clipboard is
  read once and a launch link is gone on the next launch, yet a code found
  there was only ever held in memory: if the request failed, or the token
  had expired, the referral was gone. A code is now written down before
  it's sent and retried by the next `captureAttribution` until the server
  actually answers.
- **Links are only read when Broughtby wrote them.** A `?code=` parameter
  on *any* link that opened the app was treated as a referral code and
  sent to the server. That name belongs to OAuth redirects and email
  verification links; a short one-time code would have been sent to
  Broughtby, or matched a real code and attributed the user to a stranger.
  Only `https://<share host>/r/<slug>/<code>` is read now.
- The once-per-install rule for the clipboard follows the source's `name`,
  not its class. A source of your own that wraps the clipboard and reports
  `clipboard` is read once, as intended.

### Changed

- `captureAttribution` called before `identify` returns `notIdentified`
  and **reads nothing**. It used to read every source first, spending the
  clipboard's single read on a code it couldn't send.
- **"Already attributed" is remembered per user, not per device.** A
  second account on the same phone used to be told it was attributed and
  never looked at again. It now gets `noCodeFound`, and manual entry and
  new invite links work for it. The install referrer's code and a link's
  code are still used once per install: one install is one referral.
- New error kinds `unauthorized` (401/403 — usually an expired session
  token), `rateLimited` (429, with `BroughtByError.retryAfter`) and
  `serverError` (5xx, or a success status whose body isn't ours). All
  three used to be `rejected`; exhaustive `switch`es over
  `BroughtByErrorKind` need the new cases. `BroughtByError.isTransient`
  says whether trying again later can help.
- `extractCodeFromLink` takes a required `shareUrlBase` and no longer
  reads `?code=`. If you relied on `?code=` on a domain of your own, read
  the code yourself and pass it to `submitCode`.

### Added

- `BroughtBy.handleLink(Uri)` — for links that arrive while the app is
  already running, which `captureAttribution` never saw. Anything that
  isn't a Broughtby invite is ignored without a network call.
- The earnings screen shows a retry button when the page fails to load,
  and retries with a fresh address.

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
