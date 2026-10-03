// Copyright (C) 2025 Toit Contributors
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import gpio
import gpio.pwm
import ..src.pwmledmixer show *

LED-GPIO-PIN := 4

main:
  led-pin  := gpio.Pin LED-GPIO-PIN --output

  pwmledmixer := PwmLedMixer --led-pin=led-pin --colour="white"
  generator := pwm.Pwm --frequency=400
  channel := generator.start led-pin
  duty-percent := 0
  step := 1
  factor := 0.0

  while true:
    // previous method, for comparison, commented out:
    //factor = duty-percent/100.0

    // gamma-corrected method:
    factor = (pwmledmixer.gamma-correct-duty-factor (duty-percent/100.0))
    channel.set-duty-factor factor
    duty-percent += step
    if duty-percent <= 0 or duty-percent >= 100:
      step = -step
    sleep --ms=10

    print "set duty factor to $(%0.2f factor)"
