# Android summon QA checklist

This is a local development test, not a release build or production payment test.
The client currently uses http://127.0.0.1:8787. A USB-connected Android phone
must use ADB reverse for the local API; do not enter real payment credentials.

## Prerequisites

- ARM64 Android test phone; developer options and USB debugging enabled.
- Authorize the PC on the phone. Verify exactly one authorized test device.
- Verify the local backend health at http://127.0.0.1:8787/health.
- A signed debug APK in exports/android. Do not uninstall an existing app to
  resolve signature differences without confirming backup and data-loss risks.

## PowerShell commands (run from project root)

```powershell
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
& $adb devices -l
& $adb reverse tcp:8787 tcp:8787
& $adb reverse --list
& $adb install -r "exports/android/Reverie-summon-QA-20261126-debug.apk"
& $adb shell monkey -p com.projectfantasy.game -c android.intent.category.LAUNCHER 1
```

If launching fails, inspect the installed launcher activity. If installation fails with a certificate mismatch, stop.

## Test on device with a disposable account

- Log in over USB forwarding. Confirm server wallet and pity values.
- Rotate before a pull, during reveal, while viewing reward cards, and with
  history open. Confirm all buttons remain visible and respond to touch.
- Battery Saver, Balanced, High: confirm expected cinematic counts, same
  authored portraits, correct rarity tags and unchanged server results.
- Exercise paid x10 at 90/100 with sandbox-funded stones, skip reveal, inspect
  featured marker and zero reset. Free crystals must not be spent.
- Simulate an interrupted response in the fixture environment; reconnect and
  recover the original result. Do not repeat payments or alter a real account.
- Capture FPS, memory and thermal behavior per preset using the built-in
  monitor and adb shell dumpsys meminfo com.projectfantasy.game.
- Test background/resume and repeat after app relaunch. Remove forwarding
  when finished: adb reverse --remove tcp:8787.

Public online distribution requires an approved HTTPS endpoint and release
signing; the local debug APK is not a production-ready build.

## Verified export (2026-11-26)
- 382017205 bytes, package com.projectfantasy.game, version 0.2.1 (3), ARM64, min SDK 24, target SDK 36.
- APK v2/v3 signatures and ZIP alignment passed. SHA256 B1FC8BF3670359E7191E9C7639A6BD1AAE47BE251C50FAAF1690839341AF7E11.
- Android manifest requests landscape orientation; portrait UI was tested in Godot viewports only. Do not change the game-wide orientation without a separate review.
- Export used available build tools 34.0.0 and reported Godot exit cleanup warnings. No Android hardware attached; install, API connectivity, runtime and memory not verified.
