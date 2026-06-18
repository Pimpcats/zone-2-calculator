# Zone Alert — native iPhone app

A small SwiftUI + CoreBluetooth app that connects to a standard Bluetooth heart-rate
strap (e.g. **Polar H9**, service `0x180D`) and **alerts you when you drop below your
target training zone — in the background, with the screen locked**.

This is the thing a web app *can't* do on iPhone: it keeps reading your strap while you
work/do other things, and fires a notification (sound + banner) the moment your heart
rate falls out of zone.

## Workout dashboard
A Polar-style live dashboard shows:
- **Heart rate**, **live HR-zone graph**, and **time-in-zone** breakdown — from the strap.
- **Distance** and **Pace** — from the iPhone's GPS (a chest strap has no GPS).
- **Calories** — HR-based estimate (uses age/sex/weight from Settings).
- **Duration** — workout timer with Start/Pause/Reset.

Set your age, sex, weight and target zone in **Settings (gear icon)**.

## How it works
- `bluetooth-central` background mode + CoreBluetooth **state restoration** keep the BLE
  connection alive while backgrounded and across relaunches.
- When BPM drops below your target zone's lower bound, it posts a **local notification**
  (re-fires every ~25 s while you stay below). Zones use the % of Max HR method (`220 − age`).

## Build it for free (no Mac, no $99 Apple fee)

The Swift is compiled **free in the cloud** by GitHub Actions, then **signed + installed
free** on your phone with AltStore using your ordinary Apple ID.

### 1. Get the `.ipa` (cloud build)
- Every push to `main` that touches `ios/` runs the **“Build iOS app (.ipa)”** workflow
  (`.github/workflows/ios-build.yml`). You can also run it manually from the **Actions** tab.
- Open the finished run → **Artifacts** → download **`ZoneAlert-unsigned-ipa`** and unzip
  it to get `ZoneAlert-unsigned.ipa`.

### 2. Install with AltStore (free Apple ID, auto-refreshes every 7 days)
1. Install **AltServer** on a Mac or **Windows PC**: <https://altstore.io>
2. Plug your iPhone in once; in AltServer choose **Install AltStore** to your device
   (sign in with your free Apple ID).
3. On the iPhone, open **AltStore → My Apps → ➕ → ZoneAlert-unsigned.ipa**.
4. AltStore signs it with your Apple ID and installs it. It **auto-re-signs every 7 days**
   while AltServer is reachable on the same Wi-Fi, so it keeps working.
   - Free Apple ID limits: 3 sideloaded apps, 7-day signing (AltStore renews automatically).

> Prefer a one-shot install? **Sideloadly** (<https://sideloadly.io>) installs the same
> `.ipa` with a free Apple ID, but you refresh manually every 7 days.

### One-tap updates over Wi-Fi (AltStore Source) ⭐
Every push to `main` auto-builds a new `.ipa`, publishes it to the repo's rolling
**`latest`** GitHub Release, and updates an AltStore **source feed**. Add the source once
and future updates are a single tap in AltStore — no cable:

1. In **AltStore** on your iPhone → **Browse** tab → **+** (top-left) → paste:
   `https://github.com/Pimpcats/zone-2-calculator/releases/download/latest/apps.json`
2. Open **Zone Alert** from that source and install it (replaces a Sideloadly copy as long
   as you use the **same Apple ID**; otherwise delete the old copy first).
3. After that, whenever a new build ships, AltStore shows an **Update** button — tap it.
   (Your PC running AltServer must be reachable on Wi-Fi for the 7-day re-sign, as usual.)

### Alternative paths
- **Have a Mac?** Run `xcodegen generate` in `ios/`, open `ZoneAlert.xcodeproj`, set your
  free Apple ID team, and run on your device (7-day signing).
- **Willing to pay $99/yr?** The same project can ship to **TestFlight** (tap-to-install,
  no PC, no 7-day refresh) — ask and a TestFlight CI workflow can be added.

## First-run on the phone
1. Open **Zone Alert**, allow **Bluetooth** and **Notifications** when asked.
2. Set your **age** and **target zone**.
3. Wake your Polar H9 (moisten the electrodes, strap on), tap **Connect strap**.
4. Lock your phone and go — you'll get a sound/banner alert whenever you fall below zone.
   Tap **Test alert** first to confirm notifications come through.

*Training aid, not a medical device.*
