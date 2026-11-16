# Porting this fork to iOS

Status: planning. Nothing here has been built or tested on iOS yet.

This document collects what an iPhone version of this fork needs, so the work can be picked up on a Mac.
KDE Itinerary itself has no iOS version, and KDE's build infrastructure (Craft CI) has no iOS target.

## Prerequisites

- A Mac with a current Xcode. iOS apps cannot be built, signed or uploaded from Linux.
- Qt 6.11 for iOS (Qt online installer or self-built). Qt Positioning, Qt Location, Qt Multimedia (barcode scanner) are needed.
- An Apple Developer Program membership for signing and App Store distribution. Uploading happens from the
  account that owns the App Store listing; see "Publishing" below.
- A real iPhone for testing (camera, location, file import), the simulator is not enough.

## Building the dependency stack

Everything Itinerary depends on has to be cross-compiled for iOS (arm64, and the simulator architecture for development).
This is the largest part of the work. Order roughly as the Android build log shows, see `tools/android/build-apk.sh deps`:

| Group | Packages | Notes |
|---|---|---|
| Base libraries | zlib, libxml2, libical, openssl (or Apple's Security framework via Qt), zxing-cpp, qrencode, libdmtx, olm | plain CMake/autotools builds with the iOS toolchain |
| KDE Frameworks | extra-cmake-modules, kcoreaddons, ki18n, kconfig, kirigami, kitemmodels, kholidays, karchive, prison, kunitconversion, kcontacts, kcalendarcore, kmime, kcodecs, kcolorscheme, kguiaddons, kiconthemes, knotifications, kcrash | Kirigami has worked on iOS before; knotifications needs an iOS backend (see below) |
| KDE libraries | kirigami-addons, kpublictransport, kosmindoormap, kpkpass, kitinerary, khealthcertificate, kopeninghours | kitinerary can be built without Poppler, see "Licensing" |
| Third party | qtkeychain, qcoro, libquotient, maplibre-native-qt | qtkeychain supports iOS; Matrix integration (libquotient, olm) could be disabled for a first version |
| ki18n | needs libintl | use [libintl-lite with plural form support](https://github.com/j-jorge/libintl-lite/pull/13), like the Android build |

Options worth evaluating before doing this by hand:
- KDE Craft has macOS support; check its current state for iOS targets.
- A single CMake superbuild with `CMAKE_SYSTEM_NAME=iOS` using Qt's `qt-cmake` toolchain.

## Platform specific code

Android specific code is behind `Q_OS_ANDROID`. Each of these needs an iOS counterpart, or has to be disabled:

| Area | Android implementation | iOS counterpart |
|---|---|---|
| Opening files from other apps (pkpass, PDF, ics, json) | `src/app/android/Activity.java`, `intenthandler.cpp`, `importcontroller.cpp` | `CFBundleDocumentTypes` / UTIs in Info.plist, handle `QFileOpenEvent` or `QDesktopServices::setUrlHandler` in `ImportController` |
| File names of shared files | `filehelper.cpp` (content:// URIs) | security-scoped bookmark URLs |
| Calendar import | `src/calendarextras/` Android plugin | EventKit plugin (new), or disable |
| Screen brightness for barcode scanning | `solidextras/androidbrightnessbackend` | `UIScreen.mainScreen.brightness` (small Objective-C++ backend) |
| Keeping the screen on | KGuiAddons `SystemInhibitor` | `UIApplication.idleTimerDisabled` |
| Notifications (delays, platform changes) | KNotifications Android backend | `UNUserNotificationCenter` backend for KNotifications (new) |
| Walking directions to a stop | `NavigationController::walkTo()`: Organic Maps `om://`, Google Maps `google.navigation:`, `geo:` | Organic Maps `om://route?...`, Google Maps `comgooglemaps://?daddr=LAT,LON&directionsmode=walking`, Apple Maps `maps://?daddr=LAT,LON&dirflg=w`; needs `LSApplicationQueriesSchemes` |
| Time zones | `localizer.cpp` Java fallback | not needed, Qt uses CoreFoundation on Apple platforms |
| Location permission | `QLocationPermission` (Qt, cross-platform) | works, needs `NSLocationWhenInUseUsageDescription` |
| Back navigation | Android back gesture fix in the manifest | not applicable, iOS uses the header back button and edge swipe |
| Apple Wallet passes | pkpass files open in Itinerary | on iOS they open in Apple Wallet by default; Itinerary can be offered via the share sheet ("Open in") |

## App metadata

A first draft of the required Info.plist entries is in [`Info.plist.in`](Info.plist.in). Besides those:

- Bundle identifier and app name: must belong to the publishing developer account. The name must not be
  "KDE Itinerary" (KDE trademark), and it should be clear the app is based on, but not made by, KDE.
- App icon set and launch screen storyboard.
- Privacy manifest (`PrivacyInfo.xcprivacy`) and App Store privacy labels: location (only when used),
  camera (barcode scanning), network requests to public transport data providers, no tracking.
- Public transport data providers: check the terms of the APIs used by KPublicTransport, some require keys
  that are registered to KDE.

## Licensing (needs to be resolved before publishing)

- Itinerary and the KDE libraries are LGPL. LGPL code in an App Store app requires that users can relink the
  app with modified libraries, e.g. by building the libraries as dynamic frameworks or providing object files.
- Qt is used under LGPLv3 with the same requirement.
- Poppler (PDF ticket extraction in kitinerary) is GPL. Distributing GPL code through the App Store is widely
  considered incompatible with the App Store terms. Options: build kitinerary without Poppler (loses PDF ticket
  import, Apple Wallet passes and barcodes still work), or get this checked properly.
- KDE e.V. publishes some apps in Apple's App Store (e.g. KDE Connect), they may be able to advise.

## Publishing

App Store uploads have to be signed with a distribution certificate and provisioning profile of the account
that publishes the app, so a finished binary can't be signed by someone else in advance. Workable setups:

1. The account holder adds the developer to their team in App Store Connect (role "Developer" or "App Manager"),
   who then builds, signs and uploads from Xcode under that team.
2. The developer provides an Xcode archive, the account holder signs and uploads it from Xcode's Organizer.

TestFlight should be used for testing on real devices before submitting for review.
