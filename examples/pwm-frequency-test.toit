// Copyright (C) 2025 Toit Contributors
// Use of this source code is governed by a Zero-Clause BSD license that can
// be found in the EXAMPLES_LICENSE file.

import gpio.pwm
import math
import ..src.pwmledmixer show *

/**
Bench test for the `--pwm-frequency` argument of $PwmLedMixer.

Run it in a dark room on a board with an LED on $LED-GPIO-PIN (GPIO 15 is the onboard LED of the
  DFRobot Beetle ESP32-C6, which is assumed to light when the pin is high; if it looks inverted,
  use another pin with an LED and a resistor):

```
jag run -d <device> examples/pwm-frequency-test.toit
```

It has four parts:
1. Measures the real duty resolution of the PWM at several frequencies, with the plain `Pwm` API
   (no driver involved), so the estimates in the README can be checked.
2. Drives the LED through $PwmLedMixer at $PWM-HZ and steps the duty down (the "dim ladder"). The
   console says how many PWM steps each level should be, and where it should go dark.
3. Holds a faint steady level, to judge flicker.
4. Runs the heartbeat effect, to check that effects work at the new frequency.

The mixer has no close, so it cannot be recreated on the same pin in one run: change $PWM-HZ and
  run again for each frequency you want to compare. Part 1 always covers all of $PROBE-HZ.
*/

LED-GPIO-PIN ::= 15

/** The PWM frequency under test, in Hz. Try 10_000 (the default), 2_000, 1_500, 800, 400 and 200. */
PWM-HZ ::= 1_500

/** The frequencies whose real resolution is measured in part 1. */
PROBE-HZ ::= [10_000, 2_000, 1_500, 800, 400, 200]

/** The dim ladder, in parts per million of full duty: from 1 % down to 0.003 %. */
LADDER-PPM ::= [10_000, 5_000, 2_000, 1_000, 500, 250, 125, 60, 30]
LADDER-HOLD-MS ::= 4_000

/** The steady level for the flicker check: 0.5 % duty. */
FLICKER-PPM ::= 5_000
FLICKER-HOLD-MS ::= 15_000

HEARTBEAT-HOLD-MS ::= 8_000

/**
Measures how many duty steps the PWM has at $hz, by setting a duty factor of 0.5 and reading it back.

The duty is floor(0.5 * max), where max is 2^bits - 1, so the factor read back is
  (max - 1) / (2 * max), and max = 1 / (1 - 2 * factor). Returns 0 if it cannot be worked out.
*/
measure-steps hz/int -> int:
  generator := pwm.Pwm --frequency=hz
  channel := generator.start LED-GPIO-PIN
  channel.set-duty-factor 0.5
  sleep --ms=50  // A new duty takes effect on the next PWM cycle (5 ms at the slowest frequency here).
  factor := channel.duty-factor
  generator.close  // Closes the channel too, which releases the pin.
  sleep --ms=20
  if factor <= 0.0 or factor >= 0.5: return 0
  return (1.0 / (1.0 - 2.0 * factor)).round

/** The driver brightness level that gives a duty of $ppm parts per million (the driver applies duty = level ^ gamma). */
level-for ppm/int -> float:
  return math.pow (ppm / 1_000_000.0) (1.0 / PwmLedMixer.DEFAULT-GAMMA-CORRECTION-FACTOR)

print-resolution hz/int steps/int -> none:
  if steps < 2:
    print "  $hz Hz: could not be measured"
    return
  bits := ((math.log (steps + 1).to-float) / (math.log 2.0)).round
  step-ppm := 1_000_000.0 / steps
  step-percent := step-ppm / 10_000.0
  lowest-level := level-for step-ppm.round
  print "  $hz Hz: $steps steps (about $bits bits), one step = $(%0.1f step-ppm) ppm = $(%0.4f step-percent) % duty, lowest lit level $(%0.4f lowest-level)"

main:
  print "pwmledmixer PWM frequency test: LED on GPIO $LED-GPIO-PIN, frequency under test $PWM-HZ Hz"
  default-hz := PwmLedMixer.DEFAULT-PWM-FREQUENCY
  print "The default frequency is $default-hz Hz."
  if default-hz != 10_000: print "WARNING: the default is not 10000 Hz, so existing code would change."

  print ""
  print "1. Measured duty resolution (plain Pwm, no driver):"
  steps-at := {:}
  PROBE-HZ.do: | hz/int |
    measured := measure-steps hz
    steps-at[hz] = measured
    print-resolution hz measured
  if not steps-at.contains PWM-HZ:
    steps-at[PWM-HZ] = measure-steps PWM-HZ
    print-resolution PWM-HZ steps-at[PWM-HZ]
  steps := steps-at[PWM-HZ]

  led := PwmLedMixer
      --led-pin=LED-GPIO-PIN
      --colour="test"
      --pwm-frequency=PWM-HZ
      --initial-brightness=0.0

  print ""
  print "2. Dim ladder at $PWM-HZ Hz, $(LADDER-HOLD-MS / 1000) s per level."
  print "   Note the last level you can still see, and compare it between frequencies."
  LADDER-PPM.do: | ppm/int |
    percent := ppm / 10_000.0
    level := level-for ppm
    expected := (ppm / 1_000_000.0 * steps).to-int
    note := expected == 0 ? "expect OFF: below one step" : ""
    led.set-brightness --percent=level
    print "  duty $(%0.4f percent) % ($ppm ppm), driver level $(%0.4f level): $expected of $steps steps $note"
    sleep --ms=LADDER-HOLD-MS

  print ""
  print "3. Flicker check at $FLICKER-PPM ppm, steady for $(FLICKER-HOLD-MS / 1000) s."
  print "   Flick your eyes quickly past the LED, wave a pencil in front of it, and film it with a phone."
  print "   Dotted trails or bands mean visible flicker at $PWM-HZ Hz."
  led.set-brightness --percent=(level-for FLICKER-PPM)
  sleep --ms=FLICKER-HOLD-MS

  print ""
  print "4. Heartbeat effect for $(HEARTBEAT-HOLD-MS / 1000) s: it should pulse normally at $PWM-HZ Hz."
  led.heartbeat --bpm=60 --max-brightness=0.5
  sleep --ms=HEARTBEAT-HOLD-MS
  led.stop-all
  sleep --ms=50  // A cancelled effect's task entry is removed when it next runs.
  led.set-brightness --percent=0.0

  print ""
  print "Done. The LED is off. Change PWM-HZ and run again to compare another frequency."
