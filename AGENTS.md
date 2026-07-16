# SunSpan contributor guide

## Project overview

SunSpan is a native SwiftUI app for iOS and iPadOS 16+. It renders a full year of sunrise, sunset, twilight, moon-phase, and daylight statistics for a selected location. The app is offline-first: location and preferences stay on device, and there are no analytics, accounts, ads, or network services in the project.

Open `SunSpan.xcodeproj` and use the shared `SunSpan` scheme. The project has one application target and no third-party dependencies.

## Code map

- `SunSpan/SunSpanApp.swift`: app entry point and splash screen.
- `SunSpan/ContentView.swift`: persisted `AppState`, location/time-zone coordination, and the chart/settings/stats navigation shell.
- `SunSpan/SolarCalculator.swift`: NOAA-based solar calculations and the `DayLightInfo` model.
- `SunSpan/DaylightChartView.swift`: portrait/landscape chart drawing, gestures, detail bubbles, moon phase, and current-moment display.
- `SunSpan/SettingsView.swift`: location, map, year, and DST settings.
- `SunSpan/YearStatsView.swift`: yearly summary metrics, including polar-day and polar-night cases.
- `SunSpan/Localizable.xcstrings` and `SunSpan/InfoPlist.xcstrings`: localized UI and permission text.
- `SunSpan/PrivacyInfo.xcprivacy`: App Store privacy manifest.

## Implementation expectations

- Keep the minimum deployment target at iOS 16 unless the task explicitly changes it.
- Preserve both iPhone and iPad layouts and both portrait and landscape behavior.
- Treat dates, calendars, time zones, DST, leap years, and polar day/night as correctness-sensitive. Do not replace nil sunrise or sunset values with ordinary clock times.
- Keep solar-calculation code deterministic and independent of UI state.
- Use SwiftUI for app UI. Keep UIKit bridges limited to APIs that do not have an adequate SwiftUI equivalent for the deployment target.
- Persist user-facing settings through `AppState`; keep related `UserDefaults` keys compatible unless a migration is included.
- Use `String(localized:)` for new user-visible text and add translations to the string catalog. Do not edit generated build localization output.
- Preserve the privacy promise: no location transmission, tracking, analytics, advertising, or accounts without an explicit product decision and corresponding privacy updates.
- Follow the existing file header and four-space Swift indentation. Prefer focused changes over unrelated cleanup.

## Verification

For a compile check that does not require a specific simulator, run:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild \
  -project SunSpan.xcodeproj \
  -scheme SunSpan \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  build
```

There is currently no test target. For changes to solar calculations or yearly statistics, add focused XCTest coverage when practical; at minimum, exercise an ordinary mid-latitude location, a leap year, and a high-latitude polar-day/polar-night location.

For visual changes, inspect iPhone and iPad layouts in portrait and landscape. Also check long localized strings, 12/24-hour time formatting, the settings/chart flip, selection gestures, and the current-moment marker where relevant.

Before handing off a change, review `git diff`, report the exact verification performed, and call out anything that could not be run.
