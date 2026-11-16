# Itinerary (Android fork)

This is a personal fork of [KDE Itinerary](https://apps.kde.org/itinerary), a digital travel assistant
that supports you while traveling without compromising your privacy. The fork focuses on Android and on
getting to your ticket quickly.

It is not affiliated with or endorsed by KDE. For the original application, its official releases for all
platforms and its documentation, see the [upstream repository](https://invent.kde.org/pim/itinerary).

## Differences to upstream

- The Android Back gesture navigates back inside the application instead of closing it.
- A *Tickets* tab gives direct access to your currently valid tickets and passes, ready to be shown
  for inspection.

## Download

**[Download the latest APK](https://github.com/jblechert/itinerary/releases/latest/download/itinerary-arm64-v8a.apk)**
(Android 9 or later, 64-bit ARM), or pick a specific build from the
[releases page](https://github.com/jblechert/itinerary/releases).

Things to know before installing:

- These are development builds, provided as-is and without any warranty. Whether you run them is up to you.
- They use the same application ID as the official KDE Itinerary but a different signing key, so they
  cannot be installed alongside or on top of it. Uninstalling the official version deletes its data,
  export it first.
- There is no automatic update, you get a new version by downloading and installing it again.

## Building

`tools/android/build-apk.sh` builds the APK the same way KDE's CI does, using KDE Craft in a container.
It needs Docker and a few gigabytes of disk space.

```
tools/android/build-apk.sh arm64 all      # dependencies, application, APK
tools/android/build-apk.sh arm64 install  # sign with the Android debug key and install via adb
```

## Contributing

Changes that are useful beyond this fork should go to KDE Itinerary itself, see
https://community.kde.org/Get_Involved for how to get started there.

Important external components:
- Travel document extractor engine: https://invent.kde.org/pim/kitinerary
- Public transport data access: https://invent.kde.org/libraries/kpublictransport
- Indoor map renderer: https://invent.kde.org/libraries/kosmindoormap
