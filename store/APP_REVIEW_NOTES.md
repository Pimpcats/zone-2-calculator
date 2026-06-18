# App Review notes & submission checklist — Zone Alert

## Notes to paste into "App Review Information → Notes"
> Zone Alert connects to a Bluetooth heart‑rate strap, which the review device may not have.
> **To test without hardware, open the Settings tab and tap "Demo mode (no strap needed)."**
> This streams a simulated heart rate so every screen (live dashboard, zone alerts, resting
> test, threshold test, progress) is fully testable. Tap "Stop demo" to end it.
>
> No account or login is required. All data is stored locally on the device; nothing is
> transmitted to any server. Location is used only to compute workout distance/pace on‑device.

## App Privacy ("nutrition label") answers in App Store Connect
Because nothing is transmitted off the device, you can answer:
- **Data collection: "No, we do not collect data from this app."**
  (Apple defines "collect" as transmitting off device. Zone Alert does not. Health, location,
  and identifiers all stay on device; the only export is user‑initiated via the share sheet.)
- If you later add analytics or any network feature, you must update this.

## Export compliance
- `ITSAppUsesNonExemptEncryption = false` is set in Info.plist (no custom encryption), so you
  can answer "No" to the encryption question and skip extra paperwork.

## Permission usage strings (already in Info.plist)
- `NSBluetoothAlwaysUsageDescription` — connect to your heart‑rate strap.
- `NSLocationWhenInUseUsageDescription` / `NSLocationAlwaysAndWhenInUseUsageDescription` —
  measure distance/pace during a workout.
- Background modes: `bluetooth-central` (keep reading HR for alerts), `location` (keep
  recording distance while screen is locked).

## Likely review questions & how we've addressed them
1. **"How do we test the Bluetooth feature?"** → Demo mode (above).
2. **Background location justification** → Used to record workout distance/pace while the
   screen is locked; clearly tied to an active, user‑started workout.
   - *Optional de‑risk:* switch the request from "Always" to "When In Use" (still allows
     background updates for a foreground‑started session, with the blue status bar) to reduce
     scrutiny. Say the word and I'll change it.
3. **Health claims (Guideline 1.4.1 / medical)** → The app is positioned as a fitness aid;
   a Health & Safety disclaimer is shown in Settings, and VO₂/threshold/calorie values are
   labeled as estimates. No diagnosis/treatment claims.
4. **Privacy policy** → Required for health‑data apps; host `PRIVACY_POLICY.md` and link it.
5. **Min functionality** → Native app with real, substantial features (not a web wrapper).

## Pre‑submission checklist
- [ ] Paid **Apple Developer Program** account active.
- [ ] App icon present (✓ heart icon).
- [ ] Screenshots for 6.7", 6.5", 5.5" (use Demo mode).
- [ ] Privacy Policy URL live and linked.
- [ ] Support URL live.
- [ ] App Privacy = "Data not collected."
- [ ] Export compliance = No (flag set).
- [ ] Build uploaded via Xcode/Transporter with a **distribution** signing cert (App Store),
      not the sideload‑unsigned build.
- [ ] Remove/raise the 7‑day sideload constraints — App Store builds are properly signed.
- [ ] Bump `MARKETING_VERSION` to a clean public version (e.g., 1.0) for the first release.

## Trademark hygiene (done)
- Removed "OwnZone" (Polar trademark) → renamed to "Adaptive Threshold."
- "Polar" appears only as nominative compatibility ("works with Polar H9"); avoid logos or
  any wording implying Polar endorsement/affiliation in the listing.
