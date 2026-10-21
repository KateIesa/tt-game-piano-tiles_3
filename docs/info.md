## How it works

A VGA timing block says which pixel is being drawn. A button press shows up once per picture, and the four rows of tiles fall at differing speeds. The system registers a successful hit when the button is pressed when the tile is on the input displaying line. All buttons are synchronised and debounced.

## How to test

Connect a TinyVGA PMOD, sound output and a monitor, run the clock at 25.175 MHz, and press the four buttons when the falling blocks reach the line at the bottom of the screen. When the buttons are pressed on time, the progress bar ticks up, progress bar reaches a differently colored segment every 1/5th of the way, which increases the speed. When pressing the wrong button, the progress bar goes back a step, and when missing a tile, the progress bar falls to the previous colour and speed. If the tile is missed on the green bar, the red game over screen and tune plays. If successful until the end of the progress bar, the green victory screen and tune plays. There are also sound effects on each press of the button.

## External hardware

TinyVGA PMOD and a VGA monitor, a sound output, four push buttons.
