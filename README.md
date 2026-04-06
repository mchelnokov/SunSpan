# SunSpan

An iOS and iPadOS app that renders an entire year of sunrise, sunset, and twilight as a single chart. Each day is drawn as a band shaded from astronomical night through nautical and civil twilight into full daylight, so the seasonal curve, the solstices, the equinoxes, and effects like white nights and polar day are visible at a glance.

## Features

- Full-year daylight chart for any location, any year from 1900 to 2100
- Eight-stop twilight gradient: night, astronomical, nautical, civil, day
- Tap or drag any day on the chart to inspect sunrise, sunset, daylight length, and twilight phase times in a detail bubble
- Daylight Saving Time transitions marked on the chart
- Yellow highlight on the selected day
- Location picker via satellite map, or automatic from device GPS on first launch
- Year picker (1900–2100)
- Time zone resolved automatically from the selected coordinates
- Page-flip transition between the chart and settings
- Orientation-aware layout for portrait and landscape
- Localized in English, Spanish, German, and Ukrainian
- Solar calculations based on the NOAA solar position algorithm

## Privacy

SunSpan does not collect, track, or transmit any personal data. Your location is used only on-device to compute solar geometry, and never leaves the device. There are no accounts, no analytics, and no ads. See `SunSpan/PrivacyInfo.xcprivacy` for the App Store privacy manifest.

## Requirements

- iOS or iPadOS 17.0+
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
