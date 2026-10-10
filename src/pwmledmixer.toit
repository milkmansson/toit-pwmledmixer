// Copyright (C) 2025 Milkmansson
// Use of this source code is governed by an MIT-style license that can be
// found in the package's LICENSE file.
import gpio
import gpio.pwm
import math
import log
import morse

/**
A driver for LEDs, expanded to include multiple channels.

This begun as a library to support a two-channel CCT Tunable White LED strip -
to control light 'temperature'.

See README.md.
*/

class PwmLedMixer:
  /**
  The default PWM frequency, in Hz.

  The PWM frequency also sets the duty resolution: a lower frequency gives more, finer duty steps
    (a faint LED can then go dimmer), a higher one gives fewer. See the `--pwm-frequency` argument
    of the constructors.
  */
  static DEFAULT-PWM-FREQUENCY           ::= 10_000
  static DEFAULT-GAMMA-CORRECTION-FACTOR ::= 2.2
  static DEFAULT-COOL-CHANNEL-TEMP       ::= 6000  // 100% Cool White Channel Temp in Kelvin
  static DEFAULT-WARM-CHANNEL-TEMP       ::= 3000  // 100% Warm White Channel Temp in Kelvin

  gamma-correction-factor_           := DEFAULT-GAMMA-CORRECTION-FACTOR
  channels_/Map                      := {:}  // contains each channel (a pwm.PwmChannel)
  gain-values_/Map                   := {:}  // contains gain value for each channel
  mix_/Map                           := {:}  // caches mix of channels (eg at 100%)
  brightness_/float                  := 0.0  // caches intended brightness
  temperature_/int                   := 0    // caches intended temperature
  pwm-frequency_/int                 := DEFAULT-PWM-FREQUENCY
  pwm-generator_                     := ?
  task_/Map                          := {:}
  logger_/log.Logger                 := ?

  // should be a static but vscode doesn't like it
  heartbeat-pattern_/List ::= [[1.0, 0.115],  // Up   1
                               [0.0, 0.115],  // Down 1
                               [0.0, 0.038],  // Wait (Short)
                               [1.0, 0.115],  // Up   1
                               [0.0, 0.231],  // Down 2
                               [0.0, 0.385]]  // Wait (little longer)

  // Constructor specifically for dual channel (CCT Strips)
  //
  // The $pwm-frequency (Hz) also sets the duty resolution, which is fixed when the PWM is created
  // (a lower frequency gives finer duty steps). The default is $DEFAULT-PWM-FREQUENCY.
  constructor
      --warm-pin
      --cool-pin
      --warm-temp=DEFAULT-WARM-CHANNEL-TEMP
      --cool-temp=DEFAULT-COOL-CHANNEL-TEMP
      --warm-gain=1.0
      --cool-gain=1.0
      --initial-brightness=1.0
      --pwm-frequency/int=DEFAULT-PWM-FREQUENCY
      --logger/log.Logger=log.default:

    logger_                   = logger.with-name "pwmledmixer2"
    pwm-frequency_            = pwm-frequency
    pwm-generator_            = pwm.Pwm --frequency=pwm-frequency
    channels_[warm-temp]      = pwm-generator_.start warm-pin
    channels_[cool-temp]      = pwm-generator_.start cool-pin
    gain-values_[warm-temp]   = warm-gain
    gain-values_[cool-temp]   = cool-gain
    normalise-gain_
    // Establish a valid mix (sum == 1.0) before applying brightness.  Seeding
    // both mixes with 1.0 would drive both channels at full duty.
    set-temperature_ --kelvin=((warm-temp + cool-temp) / 2)
    set-brightness_ initial-brightness

  // Constructor for other items like a LED on a Pin
  //
  // The $pwm-frequency (Hz) also sets the duty resolution, which is fixed when the PWM is created
  // (a lower frequency gives finer duty steps, so a faint LED can go dimmer). The default is
  // $DEFAULT-PWM-FREQUENCY.
  constructor
      --led-pin/int
      --colour/string="(undefined)"  // Not important for now, cosmetic only
      --initial-brightness=1.0
      --pwm-frequency/int=DEFAULT-PWM-FREQUENCY
      --logger/log.Logger=log.default:
    logger_                   = logger.with-name "pwmledmixer2"
    pwm-frequency_            = pwm-frequency
    pwm-generator_            = pwm.Pwm --frequency=pwm-frequency
    channels_[colour]         = pwm-generator_.start led-pin
    gain-values_[colour]      = 1.0
    mix_[colour]              = 1.0
    set-brightness_ initial-brightness

  /**
  Normalise Gain.

  Normalise makes a + b = 1.0.
  */
  normalise-gain_ -> none:
    if (channels_.size > 1):
      total-gain/float := 0.0
      channels_.keys.do:
        total-gain += gain-values_[it]
      if total-gain <= 0.0:
        equal := 1.0 / channels_.size.to-float
        channels_.keys.do:
          gain-values_[it] = equal
      else if total-gain != 1.0:
        channels_.keys.do:
          gain-values_[it] = (gain-values_[it])/total-gain
          logger_.debug "normalise-gain_: gains normalised" --tags={"$(it)": gain-values_[it]}

  /**
  Converts a perceptual brightness value (0.0-1.0) to a PWM duty factor.

  Applies gamma correction so that low perceptual values map to
    proportionally lower duty factors: duty = brightness ^ gamma.
  */
  gamma-correct-duty-factor percent/float --gamma-correction/float=gamma-correction-factor_ -> float:
    return math.pow percent gamma-correction

  /**
  Converts Kelvin to Mireds.

  Mireds are used in the internal maths. (Stands for 'micro reciprocal degree')
  Formula: `Mireds = 1000000 / Kelvin` Instead of describing light color in
  Kelvins (3000 K, 6000 K, etc.), it is flipped and scaled.  CCT blending
  (combining WW/CW in a single strip) is usually done in mired space: a linear
  mix in mireds gives smoother, more natural results to the human eye.  See
  [Wikipedia](https://en.wikipedia.org/wiki/Mired) to learn more
  about this topic.
  */
  to-mireds --kelvin/int -> float:
    return 1_000_000.0 / kelvin

  /**
  Sets LED colour temperature and brightness.

  Works by assigning duty factors (0.00 to 1.00) to two channel PWM MOSFETS. In
  TOIT, duty-factor is given in 0.00 through 1.00.  Bits and PWM values are not
  used in this fuction. In addition, brightness could also have been percent,
  but using 0.00 through 1.00 is essentially the same and is used everywhere for
  consistency with `duty-factor`.
  */
  set-temperature_ --kelvin/int -> none:
    // Two Channel scenario, assumes Kelvin Temperature
    if (channels_.size == 2):
      channel-keys := channels_.keys.sort
      warm-temp    := channel-keys[0]
      cool-temp    := channel-keys[1]

      kelvin = clamp-value_ kelvin --lower=warm-temp --upper=cool-temp
      temperature_ = kelvin

      miredsWarm    := to-mireds --kelvin=warm-temp
      miredsCool    := to-mireds --kelvin=cool-temp
      miredsTarget  := to-mireds --kelvin=kelvin

      baseWarm := clamp-value_ ((miredsTarget - miredsCool) / (miredsWarm - miredsCool)) --lower=0.0 --upper=1.0
      baseCool := 1.0 - baseWarm

      // apply gains
      w-raw := baseWarm * gain-values_[warm-temp]
      c-raw := baseCool * gain-values_[cool-temp]

      // IMPORTANT: re-normalize so w_mix + c_mix == 1.0
      sum-raw := w-raw + c-raw
      if sum-raw <= 0.0:
        mix_[warm-temp] = 0.5
        mix_[cool-temp] = 0.5
      else:
        mix_[warm-temp] = w-raw / sum-raw
        mix_[cool-temp] = c-raw / sum-raw

      // write with current brightness (gamma handled inside brightness())
      set-brightness_ brightness_

    else if (channels_.size == 1):
      // there is no temperature for a single channel - maybe we should throw here
      logger_.info "cctstrip.set: temperature - no temperature for 1 channel."

    else:
      // Should never happen, but for now:
      logger_.info "cctstrip.set: temperature - not currently built for $(channels_.size) channels."

  /**
  Sets LED colour temperature immediately.
  */
  set-temperature --kelvin/int?=null --add-kelvin/int?=null -> none:
    if kelvin:
      logger_.info "set temperature" --tags={"kelvin":kelvin}
      set-temperature_ --kelvin=kelvin
    else if add-kelvin:
      temperature_ += add-kelvin
      set-temperature_ --kelvin=temperature_
      logger_.info "set temperature" --tags={"add-kelvin":add-kelvin, "kelvin":temperature_}
    else:
      logger_.info "set temperature did not specify absolute or relative"

  /**
  Gets current brightness percent.
  */
  get-brightness -> float:
    return brightness_

  /**
  Sets brightness immediately.
  */
  set-brightness --percent/float?=null --add-percent/float?=null -> none:
    if percent:
      logger_.info "set brightness" --tags={"percent":percent}
      set-brightness_ percent
    else if add-percent:
      brightness_ += add-percent
      set-brightness_ brightness_
      logger_.info "set brightness" --tags={"add-percent":add-percent, "percent":"$(%0.2f brightness_)"}
    else:
      logger_.info "set brightness did not specify absolute or relative"

  /**
  Sets brightness immediately.
  */
  set-brightness_ percent/float -> none:
    brightness_ = clamp-value_ percent  --lower=0.0 --upper=1.0
    total-duty := gamma-correct-duty-factor brightness_

    channels_.keys.do:
      chan-mix := clamp-value_ mix_[it] --lower=0.0 --upper=1.0
      // keep sum of both channels == total-duty (up to rounding/clamp)
      channels_[it].set-duty-factor (chan-mix * total-duty)

  /**
  Fades brightness to the selected percent over x milliseconds.

  Expects existing brightness (0.0-1.0) cached in private var brightness_.
  If the target equals the current brightness, sleeps for the full $ms to
    preserve animation timing.
  */
  fade-brightness --to-percent/float --ms/int --tick-interval-ms/int=10 -> none:
    // Trivial/edge cases: do exact write and exit
    if to-percent == brightness_:
      sleep --ms=ms
    else if ms <= 0:
      set-brightness_ to-percent
    else:
      start-percent           := brightness_
      duration-us             := ms * 1000

      // To avoid first tick jump
      set-brightness_ start-percent

      // Time-based interpolation
      start-us                := Time.monotonic-us
      elapsed-us              := Time.monotonic-us - start-us
      current-brightness      := brightness_
      duration-percent/float  := 0.0

      while elapsed-us < duration-us:
        elapsed-us = Time.monotonic-us - start-us
        duration-percent   = elapsed-us.to-float / duration-us.to-float  // between 0.0 and 1.0
        current-brightness = start-percent + ((to-percent - start-percent) * duration-percent)
        set-brightness_ current-brightness
        sleep --ms=tick-interval-ms

      // fix a final finish
      set-brightness_ to-percent

  /**
  Whether any animation tasks are running.
  */
  animations-running -> bool:
    return task_.size > 0

  /**
  Stops currently running animation tasks.
  */
  stop-all -> none:
    task_.keys.do:
      task_[it].cancel
      task_.remove it
      logger_.info "stop-all: stopped task" --tags={"task":it}

  /**
  Heartbeat brightness effect.

  The pulses peak at $max-brightness (0.0 to 1.0), so the effect can be kept dim.
  The $bpm is beats per minute.
  - $heartbeat - sets task
  - $heartbeat_ - is the permanent loop + sleep
  - $heartbeat-one_ - is the repeated effect
  */
  heartbeat --bpm/int=60 --repeat/int=0 --max-brightness/float=1.0 -> none:
    if task_.contains "heartbeat":
      stop-all
      return
    stop-all
    task_["heartbeat"] = task::
      try:
        heartbeat_ --bpm=bpm --repeat=repeat --max-brightness=max-brightness
      finally:
        task_.remove "heartbeat"
    logger_.info "heartbeat: set task" --tags={"bpm":bpm, "max-brightness":max-brightness}

  heartbeat_ --bpm/int --repeat/int --max-brightness/float -> none:
    period-ms := 60000 / bpm
    set-brightness_ 0.0
    if repeat == 0:
      while true:
        heartbeat-one_ --period-ms=period-ms --max-brightness=max-brightness
        sleep --ms=10
    else:
      repeat.repeat:
        heartbeat-one_ --period-ms=period-ms --max-brightness=max-brightness
        sleep --ms=10

  heartbeat-one_ --period-ms/int --max-brightness/float -> none:
    heartbeat-pattern_.do:
      fade-brightness --ms=(it[1] * period-ms).round --to-percent=(it[0] * max-brightness)

  ppg-heartbeat --bpm/int=60 --repeat/int=0 --max-brightness/float=1.0 -> none:
    if task_.contains "ppg-heartbeat":
      stop-all
      return
    stop-all
    task_["ppg-heartbeat"] = task::
      try:
        ppg-heartbeat_ --bpm=bpm --repeat=repeat --max-brightness=max-brightness
      finally:
        task_.remove "ppg-heartbeat"
    logger_.info "ppg-heartbeat: set task" --tags={"bpm":bpm}

  ppg-heartbeat_ --bpm/int --repeat/int --max-brightness/float -> none:
    // TODO: implement PPG-style envelope
    heartbeat_ --bpm=bpm --repeat=repeat --max-brightness=max-brightness

  /**
  Wave Effect
  - $wave - sets task
  - $wave_ - is the task
  */
  wave --cycle-ms/int --repeat/int=0 -> none:
    if task_.contains "wave":
      stop-all
      return
    stop-all
    task_["wave"] = task::
      try:
        wave_ --cycle-ms=cycle-ms --repeat=repeat
      finally:
        task_.remove "wave"
    logger_.info "wave: set task" --tags={"cycle-ms":cycle-ms}

  wave_ --cycle-ms/int --repeat/int -> none:
    set-brightness_ 0.0
    half-cycle := cycle-ms / 2
    if repeat == 0:
      while true:
        wave-one_ --half-cycle=half-cycle
    else:
      repeat.repeat:
        wave-one_ --half-cycle=half-cycle
        sleep --ms=10

  wave-one_ --half-cycle/int -> none:
    fade-brightness --ms=half-cycle --to-percent=1.0
    fade-brightness --ms=half-cycle --to-percent=0.0

  /**
  Blink effect
  - $blink - sets task
  - $blink_ - is the task
  */
  blink --on-ms/int --off-ms/int --min/float=0.0 --max/float=1.0 --repeat/int=0 -> none:
    if task_.contains "blink":
      stop-all
      return
    stop-all
    task_["blink"] = task::
      try:
        blink_ --on-ms=on-ms --off-ms=off-ms --min=min --max=max --repeat=repeat
      finally:
        task_.remove "blink"
    logger_.info "blink: set task" --tags={"on-ms":on-ms, "off-ms":off-ms}

  blink_ --on-ms/int --off-ms/int --min/float=0.0 --max/float=1.0 --repeat/int -> none:
    set-brightness_ 0.0
    if repeat == 0:
      while true:
        set-brightness_ max
        sleep --ms=on-ms
        set-brightness_ min
        sleep --ms=off-ms
    else:
      repeat.repeat:
        set-brightness_ max
        sleep --ms=on-ms
        set-brightness_ min
        sleep --ms=off-ms

  /** Morse code: blinks out the morse encoded pattern. Lengths for dit's and dah's given by ITU. (See Morse code package docs.)
      - Dit (·) = 1 unit long (unit in this case given by '--dot-duration')
      - Dah (–) = 3 units long.
      - Gap between dits and dahs within a letter = 1 unit.
      - Gap between letters = 3 units.
      - Gap between words = 7 units.
      - $wait-duration - wait time between transmissions.
     Suggestions:
      - At 20 WPM (a common for amateur radio): 1 dit = 60 ms. Word gap would be 7 dits (420 ms).
      - At 12 WPM (a more relaxed learning speed): 1 dit = 100 ms. Word gap would be 7 dits (700 ms)
     Between sentences: There’s no official “sentence” rule in Morse.  Operators often insert a longer word gap to make it clear — often two word gaps (14 units).
       - 20 WPM = 0.8–1 second pause
       - 12 WPM = more like 1.5 seconds
     Code below is set for 12 WPM.
     Code below gives:
      - $morse-code - sets task
      - $morse-code_ - is the task
      - $morse-code-one_ - is the repeated sequence
  */
  morse-code --message/string --dot-duration/Duration=(Duration --ms=100) --wait-duration/Duration=(Duration --ms=1400) --repeat/int=0 -> none:
    if task_.contains "morse-code":
      stop-all
      return
    stop-all
    task_["morse-code"] = task::
      try:
        morse-code_ --message=message --dot-duration=dot-duration --wait-duration=wait-duration --repeat=repeat
      finally:
        task_.remove "morse-code"
    logger_.info "morse-code: set task" --tags={"message":message, "dot-duration-ms":dot-duration.in-ms}

  morse-code_ --message/string --dot-duration/Duration --wait-duration/Duration --repeat/int -> none:
    if repeat == 0:
      while true:
        morse-code-one_ --message=message --dot-duration=dot-duration
        sleep wait-duration
    else:
      repeat.repeat:
        morse-code-one_ --message=message --dot-duration=dot-duration
        sleep wait-duration

  morse-code-one_ --message/string --dot-duration/Duration -> none:
    morse.emit-string
      message
      --dot-duration=dot-duration
      --on=:   set-brightness_ 1.0
      --off=:  set-brightness_ 0.0

  /**
  Swipe effect - sways between two extremes on two channels.
  - extreme-dwell - factor by which we spend less time at the extremes (0 = nprmal)
  */
  swipe --cycle-ms/int --repeat/int=0 --extreme-dwell/float=0.0 --tick-interval-ms/int=10 -> none:
    if task_.contains "swipe":
      stop-all
      return
    stop-all
    if (channels_.size == 2):
      task_["swipe"] = task::
        try:
          swipe_ --cycle-ms=cycle-ms --repeat=repeat --extreme-dwell=extreme-dwell --tick-interval-ms=tick-interval-ms
        finally:
          task_.remove "swipe"
      logger_.info "swipe: started swipe task" --tags={"cycle-ms":cycle-ms}
    else:
      logger_.info "swipe: not supported for $(channels_.size) channels"

  swipe_ --cycle-ms/int --repeat/int --extreme-dwell/float=0.0 --tick-interval-ms/int -> none:
    //assert: cycle-ms <= 0

    if (channels_.size == 2):
      channel-keys     := channels_.keys.sort
      warm-temp        := channel-keys[0]  // low
      cool-temp        := channel-keys[1]  // high

      cycle-us := cycle-ms * 1000
      start-us := Time.monotonic-us

      // Clamp warp factor for stability.
      if extreme-dwell < 0.0: extreme-dwell = 0.0
      if extreme-dwell > 0.95: extreme-dwell = 0.95

      if repeat == 0:
        while true:
          swipe-one_ --cool-temp=cool-temp --warm-temp=warm-temp --start-us=start-us --cycle-us=cycle-us --extreme-dwell=extreme-dwell
          sleep --ms=tick-interval-ms
      else:
        repeat.repeat:
          swipe-one_ --cool-temp=cool-temp --warm-temp=warm-temp --start-us=start-us --cycle-us=cycle-us --extreme-dwell=extreme-dwell
          sleep --ms=tick-interval-ms

  swipe-one_ --cool-temp/int --warm-temp/int --start-us/int --cycle-us/int --extreme-dwell/float -> none:
    // Phase 0..2π based on elapsed microseconds within the cycle.
    phase-us := (Time.monotonic-us - start-us) % cycle-us
    theta := 2 * math.PI * phase-us / cycle-us
    // Phase warp: less dwell at extremes when b > 0.
    theta-w := theta - 0.5 * extreme-dwell * (math.sin (2 * theta))
    mid := (cool-temp + warm-temp) / 2.0
    amp := (cool-temp - warm-temp) / 2.0
    target-temp := mid + amp * (math.sin theta-w)
    // Send temperature to device
    set-temperature_ --kelvin=target-temp.round

  /**
  Clamps the supplied value to specified limit.
  */
  clamp-value_ value/any --upper/any?=null --lower/any?=null -> any:
    if (upper != null) and (lower != null):
      assert: upper >= lower
    if upper != null: if value > upper:  return upper
    if lower != null: if value < lower:  return lower
    return value
