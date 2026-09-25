# LockScreenGradientClock

A rootless / roothide jailbreak tweak for iOS 15–17. Adds a configurable gradient overlay to the Lock Screen clock and provides a Preferences page.

## Build

Install Theos and clone this repository:

```sh
make package FINALPACKAGE=1
# Rootless
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=rootless
# Roothide
make package FINALPACKAGE=1 THEOS_PACKAGE_SCHEME=roothide
```

GitHub Actions builds both schemes. The tweak targets SpringBoard and uses runtime class discovery so it can tolerate private class changes between iOS 15, 16 and 17.

## Settings

Open Settings → LockScreen Gradient Clock. Configure enable state, start/end colors, gradient direction, opacity and animation. Colors are entered as `#RRGGBB` or `#RRGGBBAA`.

## Notes

Private Lock Screen implementation details differ across point releases. The candidate class list is in `Tweak.xm`; add a class name there if a vendor build uses another date view class.
