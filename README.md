# mBlock for Raspberry Pi

These scripts build a version of the [mBlock](https://mblock.cc/pages/downloads) programming environment for the Raspberry Pi (arm64 Linux).

## Installation

1. Navigate to the [releases](https://github.com/jwbonner/mBlockRaspberryPi/releases/latest) page.
2. Download the 3 files attached to the release:
   - `mblock_X.X.X_arm64.deb`: mBlock package
   - `arduino_uno.mext`: Offline version of Arduino Uno extension
   - `olenepal_arduino.mext`: Extension for YAK robot control
3. On the Raspberry Pi, run `sudo apt install ./mblock_X.X.X_arm64.deb`.
4. Open the mBlock application (find it under the "Programming" category).
   - Note that mBlock may take 30+ seconds to start when launching for the first time (subsequent launches will be faster).
5. Drag the `arduino_uno.mext` and `olenepal_arduino.mext` files from a file browser to the mBlock window.
   - This step is only required once. After the initial install, add the "Arduino Uno" device using the panel on the left and click the "Extension" button to activate the OLE Nepal extension.

## Building mBlock

TODO

## Editing the mBlock Extension

TODO
