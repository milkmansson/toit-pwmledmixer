// Copyright (C) 2025 Toit Contributors
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import gpio
import gpio.pwm
import ..src.pwmledmixer show *

WARM-WHITE-PIN := 4
COOL-WHITE-PIN := 5

main:
  warm-white-pin := gpio.Pin WARM-WHITE-PIN --output
  cool-white-pin := gpio.Pin COOL-WHITE-PIN --output

  cct-strip := PwmLedMixer --warm-pin=warm-white-pin --warm-temp=PwmLedMixer.DEFAULT-WARM-CHANNEL-TEMP --cool-pin=cool-white-pin --cool-temp=PwmLedMixer.DEFAULT-COOL-CHANNEL-TEMP

  // Set overall brightness
  cct-strip.set-brightness 1.0

  // Set one temperature and wait 2s
  cct-strip.temperature --kelvin=PwmLedMixer.DEFAULT-WARM-CHANNEL-TEMP
  sleep --ms=2000

  // Set the other and wait 2s
  cct-strip.temperature --kelvin=PwmLedMixer.DEFAULT-COOL-CHANNEL-TEMP
  sleep --ms=2000

  // Swipe between the two channels over 10 seconds with a weighting (extreme-dewell)
  // at each end
  cct-strip.swipe --cycle-ms=10_000 --extreme-dwell=0.25
