# mBlock for Raspberry Pi

These scripts build a version of the [mBlock](https://mblock.cc/pages/downloads) programming environment for the Raspberry Pi (arm64 Linux).

## Installing mBlock on a Raspberry Pi

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

## Building mBlock for Raspberry Pi

> [!NOTE]
> These instructions are only required to **create a new mBlock package** for installation on Raspberry Pis. Pre-built packages are available on the [releases](https://github.com/jwbonner/mBlockRaspberryPi/releases/latest) page.
>
> mBlock extensions can be also updated without rebuilding the mBlock package. See the [instructions](#editing-the-mblock-extension) on editing extensions for more details.\*\*

1. Install [Node.js](https://nodejs.org).
2. Clone this repository using [Git](https://git-scm.com/).
3. Navigate to the cloned repository and run `npm install`
4. Check the version of mBlock specified in `versions.json` and download the corresponding **Windows installer** from the [mBlock download page](https://mblock.cc/pages/downloads).
5. Place the installer in the root of the cloned repository. It should be named `VX.X.X.exe` (for example, the installer for mBlock 5.6.0 should be named `V5.6.0.exe`).
6. Run `npm run build` and wait for the process to complete. The correct version of Arduino will be downloaded automatically.
7. Find the complete Linux package under `dist/mblock_X.X.X_arm64.deb`.

To update mBlock or the Arduino version, simply change the version in `versions.json` and rebuild the Linux package using the instructions above. Note that non-trivial changes to mBlock may require additional changes to the build sequence. To support any future changes required, the steps used by the current build process are described in the dropdown below.

<details>
<summary>Detailed Build Process</summary>

mBlock is built using [Electron](https://www.electronjs.org/), which packages a web interface (built with HTML, CSS, and JS) into a native application. The mBlock application is available on macOS (arm64 and x64) and Windows (x64), but the goal of this project is to create a version for Linux using the arm64 architecture. There are a few components to the mBlock application which must be accounted for when porting to Linux:

- **The Electron wrapper**, which uses Electron 21.4.4 as of mBlock 5.6.0. Electron has full support for Linux on arm64, so rebuilding the Electron wrapper for a new platform is trivial. The full configuration for this can be found in `package.json`.
- **The web app**, which is contained in an archive called `app.asar` in the resources folder of any Electron application. This format ([asar](https://www.npmjs.com/package/@electron/asar)) is similar to a `tar` archive and can be easily manipulated if necessary ([docs](https://www.npmjs.com/package/@electron/asar)). In our case, the _entire_ `app.asar` file can be copied directly from the original mBlock application to the new Linux application.
- **The Arduino toolchain**, which is a set of native tools for building on the AVR platform. This toolchain is contained in the resources folder of the mBlock application (all resources outside of `app.asar` are contained in a folder called `ml`). The native Arduino toolchain (e.g. for macOS or Windows) must be replaced by a version built for Linux. This toolchain is readily available for Linux on arm64 (it is packaged with the Arduino IDE, which is available for that platform).

**Build Sequence**

1. The `electron-builder` package is invoked to build the Electron wrapper. The full configuration, including the app icon and the file assocation for `.mblock` files are configured in `package.json`.
2. Before building the full application, the `beforePack.js` script is invoked to download and prepare all of the additional resources that will be incorporated into the final application. This scripts runs the following steps:
   1. Extract the mBlock installer provided before the build. This is a 7-zip file that will be extracted to the folder `build/mblock`. The resources folder for the original mBlock application is found under `build/mblock/resources`.
   2. Download and extract the Linux arm64 version of the Arduino IDE based on the version in `versions.json`. The contents of the Arduino IDE are found under `build/arduino/arduino-X.X.X` and the toolchain is found under `build/arduino/arduino-X.X.X/hardware/tools/avr`.
   3. Copy the `ml` resources folder from the mBlock application (`build/mblock/resources/ml`) to a temporary location (`build/ml`).
   4. Delete the Arduino toolchain that was packaged with mBlock from the temporary `ml` folder (`build/ml/v1/external/arduino/avr-toolchain`), since it's built for Windows and is not compatible with Linux arm64.
   5. Copy the Arduino toolchain from the Linux arm64 Arduino IDE (`build/arduino/arduino-X.X.X/hardware/tools/avr`) to the temporary `ml` folder (`build/ml/v1/external/arduino/avr-toolchain`).
   6. Recreate several symlinks in the new Linux toolchain. These symlinks are broken while downloading the copying the toolchain, so they are recreated using relative paths. The full list of symlinks can be found in `beforePack.js`.
3. The output of the `beforePack.js` script are the two key resources that must be incorporated into the final Electron application:
   - The `app.asar` archive, which will be copied directly from the extracted mBlock application (`build/mblock/resources/app.asar`).
   - The `ml` resources folder, which was modified with a Linux-compatible Arduino toolchain and is available under `build/ml`.
4. The Electron build configuration includes the list of "extra" resources to copy directly to the resources folder in the new application. These are specified under `package.json` > `build` > `extraResources`. The two resources described above are included in this list and copied directly to the final application.
5. The Electron build process requires an entrypoint script that is part of the `app.asar` archive. This is specified as `packages/main/dist/index.cjs` under `package.json` > `main` based on the configuration of the original mBlock application.
6. The rest of the Electron build proceeds as normal, producing a `.deb` package under `dist/mblock_X.X.X_arm64.deb`.

</details>

## Editing the mBlock Extension

TODO
