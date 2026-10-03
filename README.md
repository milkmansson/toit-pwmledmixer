
# Introduction
A small library implementing a class to drive a CCT White LED Strip.  MOSFETs can be use to drive these, and a class is essentially not needed. However This class is special because:
- sets both cool-white and warm-white PWM channels using given temperature (K) & brightness values
- implements gamma correction for brightness
- implements a gain factor to either channel to account for percieved brightness of one channel over the other

# Background

## What is a CCT Strip?
CCT means 'Correlated Color Temperature'.  A CCT LED strip has two different kinds of white LEDs mounted side-by-side:
- WW (warm white) → typically ~2700–3000 K
- CW (cool white) → typically ~6000–6500 K
The strip has three pads: +12 V (common anode), WW–, and CW–. By dimming each channel with PWM, you can “blend” the two whites together.

The term correlated comes from lighting science.  A real black-body radiator at 3000 K glows warm yellowish, at 6000 K bluish white. LEDs don’t follow that curve exactly, so instead of a true physical “color temperature,” we say they have a correlated color temperature — i.e. “combined, this looks like a 3000 K source.”

## Strip types and differences:
The Following table shows the different strip types, and shows strengths and weaknesses:
| Type       | Channels | What you can adjust              | Strengths                           | Weaknesses                       |
| ---------- | -------- | -------------------------------- | ----------------------------------- | -------------------------------- |
| **SC**     | 1        | Brightness only (**S**ingle **C**olour)  | Simple, cheap                       | No color/temp control            |
| **CCT**    | 2        | Brightness + white temp          | Natural tunable whites              | No colors                        |
| **RGB**    | 3        | Brightness + **R**ed/**G**reen/**B**lue color mix       | Full-color output                   | Poor whites                      |
| **RGBW**   | 4        | Brightness + RGB + true white    | Good whites _and_ colors            | Slightly more cost/complex       |
| **RGBCCT** | 5        | Brightness + RGB + tunable white | Everything (best whites + full RGB) | Expensive, controller complexity |

## What is an FCOB strip?
Traditional LED strips use SMD packages (e.g. 5050, 2835) soldered onto copper pads. There are small gaps between each LED.  In FCOB, the LED flip chips (tiny bare LED dies flipped and bonded directly) are mounted directly onto the flexible PCB.  Then the whole surface is coated with a continuous layer of phosphor + silicone.  This is useful because:
- gives a continuous light line with less/no visible “dotting” — even without an aluminum channel or diffuser, there is a much a smoother, unbroken line of light.
- looks more like a neon strip.
- higher packing density - hundreds of LEDs per meter (e.g. 480–840), with uniform visual output.
- better heat dissipation - lower thermal resistance than SMD packages.
- Still on a flexible PCB. Can be bent/curved like normal strips.

## What is Gamma Correction?
LED strips respond linearly to PWM:
- 50% duty cycle ≈ 50% of the light output.
But the human eye is not linear — human perception of brightness follows a power law curve (roughly exponent γ ≈ 2.2).
- Without correction: a 50% duty looks much dimmer than “half brightness.”
- With correction: you map the desired perceived brightness through
> duty=(brightness)^γ
Using this function, the steps feel visually even.  Especially for CCT strips, gamma correction helps ensure smooth blending between warm and cool channels, avoiding jumps or dips in perceived brightness.

#### Note: Gamma correction on two channels:
Applying gamma correction to both CW & WW channels separately creates the following situation:
- At 50/50 and γ≈2.2: (0.5^γ + 0.5^γ) ≈ 0.217 + 0.217 = 0.434 — which is visibly dimmer than a single channel at 1.0 (1^γ = 1).
- mixes will look darker than endpoints.

Applying gamma correction to the brightness multiplier instead:
- or any brightness B, pure WW = B^g, pure CW = B^g.
- or a 50/50 mix, warm = 0.5 * B^γ, cool = 0.5 * B^γ, so the sum is still B^γ.
- mixes no longer look dimmer than endpoints at the same requested brightness.

## What are Mireds?
[Mireds](https://en.wikipedia.org/wiki/Mired) (MIcro REciprocal Degrees) is a unit of measurement used to express color temperature. Values in mireds are calculated by the formula:
    M = 1 000 000 K T , {\displaystyle M={\frac {1\,000\,000\,{\text{K}}}{T}},}
where T is the colour temperature in units of kelvins and M denotes the resulting mired dimensionless number. The constant 1000000 K is one million kelvins.  So instead of expressing temperature in Kelvin, like “3000 K” or “6000 K,” the values are converted to 333 mireds and 167 mireds, respectively.

## Why use Mireds in these formulas?
The Kelvin scale is nonlinear to our perception:
- The step from 2000 K → 3000 K looks bigger than 6000 K → 7000 K, even though both are +1000 K.
- In the 'mired space', equal steps correspond better to the perceptual changes in color temperature.
For this reason, formulas for CCT blending (eg, when mixing warm-white and cool-white channels) use mireds — the interpolation gives smoother, more natural transitions.  [Apple's HomeKit](https://en.wikipedia.org/wiki/HomeKit) also uses the mired unit.

## Why create this library?
I started a project to create the mother of all alarm clocks.  I especially wanted a light on it, to use to assist waking up.  It needed to be able to be used as a night light that wouldn't somoene sleeping, and could also be used to help wake someone up, in parts of the world where there is little to no daylight when its time to wake in the morning.  I wanted to avoid problems like those associated with difficulties sleeping due to cellphone use in the evening.
There are models available from some brands like Philips - these are often quite expensive, and in many cases, lack features and usability that I would like to see.  The build quality from the most recent offerings that my friends have did not inspire me.  Therefore this project was born.
There were many things I didn't know how to do when I started, as is indicated by the information here.  This library attempts to condense the maths of this together to drive a CCT strip, and have colour selection and dimming well (eg. incorporating the concepts above).  It is presented here for your use.  (Code I have created for other modules in this project can be found on [my Github](https://github.com/milkmansson), or for the Toit system packages etc, see the [Toit Package Repository](https://pkg.toit.io/).

## Final Tuning
**But - the cool white (at its maximum) looks brighter than warm white!**
It is still possible - to my eye, on this specific strip, the cool white at 100% looks much brighter than the warm white at 100%.  For this reason, the code implements a gain value.  If there is still an imbalance at mid CCT, tweak the class `cctstrip.gain-warm` / `cctstrip.gain-cool` values to something (e.g., 0.95 / 1.05) until the balance looks right to you.

# Examples

## Gamma Correction on a power LED  (single channel example)
To get the maths thought through, the [Toit PWM LED Example](https://docs.toit.io/tutorials/hardware/pwm-led) can be expanded to include gamma correction.  The code at the bottom of this article (using 'duty-factor') can be adjusted using this library, as shown below.  Try it out
- the previous version scales linearly, so the led seems to change slowly, then accelerate towards the end
- gamma corrected version appears to have a steady brightness decrease.
- note that inputs and outputs for '.set-duty-factor' are a percentage expressed in 0.00(0%) through 1.00 (100%).  See [Toit PWM Library for details](https://libs.toit.io/gpio/pwm/class-PwmChannel).

```toit
// Credit to Toit maintainers for the original code: https://docs.toit.io/tutorials/hardware/pwm-led
// See this article for the wiring diagram and related instructions.
//
import gpio
import gpio.pwm
import cctstrip              // this library

main:
  led := gpio.Pin 15         // My DFRobot ESP32-C6 Pwr LED pin, change to yours
  generator := pwm.Pwm --frequency=400
  channel := generator.start led
  duty-percent     := 0
  step := 1
  while true:
    // previous method, for comparison:
    // channel.set-duty-factor duty-percent/100.0

    // gamma-corrected method:
    channel.set-duty-factor (cctstrip.gamma-corrected-duty-factor --percent=(duty-percent/100.0))
    duty-percent += step
    if duty-percent == 0 or duty-percent == 100:
      step = -step
    sleep --ms=10
```

## Gamma Correction on a power LED  (single channel example)
To-do:

#### Parts
There is likely many ways to do this - but in my example, I used the following parts.:
- DFRobot ESP32-C6 Beetle Microcontroller [already configured for Toit](https://docs.toit.io/getstarted/device/#3-flash-your-device)
- Operational environment with [jaguar installed](https://docs.toit.io/getstarted/device/#2-install-jaguar), and able to run and send code to your ESP32.
- BTF CCT Led strip: CRI>90, DC12V 5M, 640LEDs/m CCT
- USB-C PD Trigger Module - configured for 12v
- USB-C 65W PD-capable power supply/phone charger, as the power source
- 12v -> 5v Step-down buck converter module
- 2x DC 5V-36V 400W FET trigger switch drive module (Dual Mosfet type)
- Breadboard and other connectors to build the circuit

#### IMPORTANT NOTES:
- The **PD Trigger** module I have has a dip switch allowing the selection of 5v, 9, 12v, 15v, and 20v.  Orientation is important - setting the dip switches the right way, but with the device upside down, will result in too many volts surging through your modules, potentially frying them.  Check everything with your trusty voltmeter.  [Measure twice, cut once](https://en.wiktionary.org/wiki/measure_twice_and_cut_once).
- This circuit will have two USB ports when completed.  **The 65w PSU and a computer should not be connected at the same time**.  I'm not an electrical engineer, but this certainly doesn't feel like a good idea.  The circuit could be improved to help prevent risks of return currents etc, but at another time. Please see the disclaimer.
- That said, code updates can be pushed to the device despite (via Wifi, using the normal setup) - just the `jag monitor` feature is not possible without some other method.  Without this, the `print` statements can't be seen.

#### Wiring diagram:


#### Code:
See the Code Examples directory.

# A note on Toit
[Toit Architecture](https://docs.toit.io/getstarted/#architecture) solves an incredible amount of hurdles which I found personally delayed my progress on embedded platforms.  I studied coding years ago, but am not a professional developer or an electrical engineer by any means - so simply using this platform made my life so much better.  The community might be small, but the people behind it are amazing.  If you haven't already, give it a shot!

# Disclaimers
- This code works on my bench, with my hardware, under the right phase of the moon and after just enough coffee. If it fries your MOSFETs, melts your LED strip, incites a divorce, race war, or otherwise misbehaves — there are no warranties, expressed or implied.
