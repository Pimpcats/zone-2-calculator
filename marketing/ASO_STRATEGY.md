# App Store Optimization (ASO) — Zone Alert

> **Honest truth up front:** there is no trick to "get to the top." App Store ranking is
> driven by **(1) keyword relevance, (2) conversion rate (views → installs), (3) download
> velocity, and (4) ratings volume + rating.** You climb by nailing the listing and then
> getting a burst of downloads + reviews. This doc is how to do each.

## 1. Keywords (the #1 lever)
Apple ranks you for words in your **app name, subtitle, and the 100‑char keyword field**
(and, on the App Store, the in‑app purchase names). It does NOT index your description.

**App name (30 chars)** — put your strongest keyword *in the name*:
- `Zone Alert: Heart Rate Zones` (28) ← recommended
- alt: `Zone Alert — Zone 2 HR Coach`

**Subtitle (30 chars):**
- `Bluetooth HR zone training` (26)
- alt: `Stay in Zone 2 with alerts`

**Keyword field (100 chars, comma‑separated, NO spaces, don't repeat name/subtitle words):**
```
zone2,bpm,cardio,interval,running,cycling,vo2,hrv,resting,fitness,coach,strap,pulse,monitor,aerobic
```
Rules: singular only (Apple matches plurals), no spaces (wastes chars), don't repeat words
already in the name/subtitle, no competitor brand names (e.g., not "Polar"/"Strava" — can
get rejected and wastes space).

**Research tools (free/cheap):** AppFigures, Sensor Tower (free tier), Mobile Action,
TheTool, or just the App Store search bar autocomplete (type "heart rate" and see what
Apple suggests — those are real high‑volume queries).

## 2. Conversion rate (turn views into installs)
- **Icon:** the red heart is clean — test it small; make sure it pops on a busy results page.
- **First 2 screenshots matter most** (most users never scroll). Lead with the **alert**
  ("Buzzes when you leave your zone") and the **live dashboard**. Add bold caption text
  overlaid on each (use the Demo‑mode shots).
- **App Preview video (15–30s):** screen‑record the live dashboard reacting + an alert
  banner. Video lifts conversion a lot.
- **Subtitle + first line of description** should state the single benefit in plain words.

## 3. Ratings & reviews (huge for ranking + trust)
- Use **SKStoreReviewController** (`requestReview`) to prompt at a *happy moment* — e.g.,
  right after a user finishes a workout that stayed in zone. (I can add this to the app.)
- Never prompt on launch or after an error. Apple limits prompts to 3/year per user.
- Aim for **>50 ratings and a 4.5+ average** early — it compounds.

## 4. Download velocity (the launch spike)
A concentrated burst of installs in a few days ranks you in **category** charts:
- Line up friends, running/cycling subreddits, Discords, and your network to download on
  **day one**.
- Post in communities where Zone‑2 training is hot (r/running, r/cycling, r/Garmin,
  r/triathlon, r/heartrate, Slowtwitch) — value‑first, not spammy.

## 5. Category & freshness
- Category: **Health & Fitness** (huge but high‑intent). Secondary: **Sports**.
- Ship **regular updates** — Apple favors actively‑maintained apps, and each update is a
  chance to refresh screenshots/keywords.

## 6. Localization (cheap reach)
Even just localizing the **keyword field + subtitle** into Spanish, German, French,
Portuguese, Japanese can multiply impressions for near‑zero effort.

## 7. Pricing strategy for ranking
- **Free with a one‑time unlock or subscription** ranks/installs far faster than paid‑up‑front
  (more downloads → more velocity → higher rank). Consider **free core + paid pro** (e.g.,
  adaptive zones, OwnZone‑style threshold, trends/export behind a small subscription).

## Quick win checklist
- [ ] Keyword in app name + subtitle
- [ ] 100‑char keyword field filled (singular, no spaces, no brands)
- [ ] 2 strong captioned screenshots + a preview video
- [ ] `requestReview` at a happy moment
- [ ] Launch‑day download push lined up
- [ ] Free tier to maximize velocity
