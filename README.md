# SunSpan

An iOS and iPadOS app that renders an entire year of sunrise, sunset, and twilight as a single chart. Each day is drawn as a band shaded from astronomical night through nautical and civil twilight into full daylight, so the seasonal curve, the solstices, the equinoxes, and effects like white nights and polar day are visible at a glance.

## Features

- Full-year daylight chart for any location, any year from 1900 to 2100
- Eight-stop twilight gradient: night, astronomical, nautical, civil, day
- Tap or drag any day on the chart to inspect sunrise, sunset, daylight length, and twilight phase times in a detail bubble
- Year stats page with totals, earliest/latest sunrise and sunset, longest/shortest day, average day length, equinoxes, and polar-aware metrics for midnight-sun locations
- Daylight Saving Time transitions marked on the chart, with a toggle to view in standard time
- Coordinates displayed on the chart
- Yellow highlight on the selected day, preserved as you pan and step through years
- Location picker via hybrid map with place names, or automatic from device GPS on first launch
- "My Location" button to jump to the device location
- Inline year stepper (1900–2100) that keeps your selected day across year changes
- Time zone resolved automatically from the selected coordinates
- All settings persist between launches
- Page-flip transition between the chart and settings
- Orientation-aware layout for portrait and landscape
- Localized in 18 languages: English, Czech, Danish, German, Spanish, Finnish, French, Icelandic, Italian, Japanese, Korean, Norwegian Bokmål, Polish, Brazilian Portuguese, Slovak, Swedish, Ukrainian, and Simplified Chinese
- Solar calculations based on the NOAA solar position algorithm

## Privacy

SunSpan does not collect, track, or transmit any personal data. Your location is used only on-device to compute solar geometry, and never leaves the device. There are no accounts, no analytics, and no ads. See `SunSpan/PrivacyInfo.xcprivacy` for the App Store privacy manifest.

## Requirements

- iOS or iPadOS 16.0+
- Xcode 15+
- Swift 5.0+

## Building

1. Open `SunSpan.xcodeproj` in Xcode.
2. Select your development team in the *Signing & Capabilities* tab of the `SunSpan` target (the project ships with an empty team field).
3. Build and run on a simulator or device.

## Support

Questions, bug reports, and feature requests are welcome on the [GitHub issue tracker](https://github.com/mchelnokov/SunSpan/issues).

## License

MIT — see `LICENSE`.
