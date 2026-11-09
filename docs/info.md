## How it works

The background was already there so I decided to keep it, so I dont know how it works. The box moves by creating registers which store the top left of the boxes x and y coords as it falls. It falls due to the always block i made, which also controls whether or not it can fall (whether the adjacent 10x10 pixel block is free, or whether its reached the bottom of the playing well). The box is coloured as the pixels 10 to the right, and 10 down of the top left part of the box are coloured, and these pixels are constantly assesed (as the box is a wire). This colours is shared by the boxes that have settled at the bottom, so actually, the colour of the falling box is assigned under the wire cell_on. The boxes settle at the bottom, then clear when theres a complete row. I didnt really know how to do this so I needed some help from ai.

## How to test

play the game? make sure the vga output is watching the file with _vga

## External hardware

It needs the vga monitor, the up, left and right keys (forget about ui[7]) and on the clock pin a 25.175 MHz pixel clock
