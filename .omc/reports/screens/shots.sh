#!/bin/zsh
# Usage: shots.sh <device-udid> <prefix>  (run from the repo root after building)
set -e
D=$1; P=$2
xcrun simctl boot $D 2>/dev/null || true
xcrun simctl bootstatus $D -b >/dev/null
xcrun simctl install $D DerivedData/Build/Products/Debug-iphonesimulator/App.app
shot() {
  local name=$1; shift
  xcrun simctl terminate $D com.shinjunyeob.loopgame 2>/dev/null || true
  xcrun simctl launch $D com.shinjunyeob.loopgame "$@" -muted YES >/dev/null
  sleep 4
  xcrun simctl io $D screenshot .omc/reports/screens/$P-$name.png >/dev/null 2>&1
  xcrun simctl terminate $D com.shinjunyeob.loopgame 2>/dev/null || true  # don't leave the demo song playing
  echo "ok $P-$name"
}
shot home -screen none -keyboardMode NO
shot freeplay-drums -screen freePlay -role drums -keyboardMode NO
shot freeplay-melody -screen freePlay -role melody -keyboardMode NO
shot freeplay-chords -screen freePlay -role chords -keyboardMode NO
shot freeplay-keyboard -screen freePlay -role melody -keyboardMode YES
shot credits -screen credits -keyboardMode NO
shot loopstation -screen newSong -demoSong YES -keyboardMode NO
shot compare -screen newSong -demoSong YES -demoCompare YES -keyboardMode NO
shot arrange -screen newSong -demoSong YES -demoArrange YES -keyboardMode NO
shot mysongs -screen mySongs -keyboardMode NO
