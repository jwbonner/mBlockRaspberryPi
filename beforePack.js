const fs = require("fs");
const download = require("download");
const lzma = require("lzma-native");
const tar = require("tar");
const { pipeline } = require("stream");
const { extractFull } = require("node-7z");
const sevenBin = require("7zip-bin");

const MBLOCK_VERSION = "5.6.0";
const ARDUINO_VERSION = "1.8.19";

exports.default = async function () {
  // Create build directory if necessary
  if (!fs.existsSync("build")) {
    fs.mkdirSync("build");
  }

  // Extract mBlock
  if (!fs.existsSync("build/mBlock")) {
    await extractMblock();
  } else {
    console.log("Skipped mBlock extraction");
  }

  // Download Arduino
  if (!fs.existsSync(`build/arduino/arduino-${ARDUINO_VERSION}`)) {
    await downloadArduino();
  } else {
    console.log("Skipped Arduino download");
  }

  // Create resources
  createResources();
};

/** Extract mBlock application (Windows). */
async function extractMblock() {
  if (!fs.existsSync(`V${MBLOCK_VERSION}.exe`)) {
    console.error(
      `\n************** ERROR: DOWNLOAD MBLOCK *************\n* mBlock installer not found! Please download the *\n* Windows installer for mBlock ${MBLOCK_VERSION} and place it *\n* in the project root folder as V${MBLOCK_VERSION}.exe.       *\n***************************************************\n`
    );
    throw new Error("mBlock installer not found, see above.");
  }

  console.log("Extracting mBlock...");
  await decompress7z(`V${MBLOCK_VERSION}.exe`, "build/mBlock/");

  console.log("Finished mBlock extraction");
}

/** Download and extract the Arduino application, which includes the AVR toolchain. */
async function downloadArduino() {
  console.log("Downloading Arduino...");
  fs.rmSync("build/arduino", { recursive: true, force: true });
  const url = `https://downloads.arduino.cc/arduino-${ARDUINO_VERSION}-linuxaarch64.tar.xz`;
  await download(url, "build/arduino");

  console.log("Extracting Arduino...");
  await decompressTarXz(
    `build/arduino/arduino-${ARDUINO_VERSION}-linuxaarch64.tar.xz`,
    "build/arduino/"
  );

  console.log("Finished Arduino download");
}

/** Create "ml" resources folder for a specific architecture. */
function createResources() {
  console.log("Creating mBlock resources...");

  // Delete destination if exists
  if (fs.existsSync("build/ml")) {
    fs.rmSync("build/ml", { recursive: true, force: true });
  }

  // Copy base resources folder
  console.log("Copying resources folder...");
  fs.cpSync("build/mblock/resources/ml", "build/ml", {
    recursive: true,
  });

  // Delete existing AVR toolchain
  fs.rmSync("build/ml/v1/external/arduino/avr-toolchain", {
    recursive: true,
    force: true,
  });

  // Copy AVR toolchain for Raspberry Pi
  console.log("Copying AVR toolchain...");
  fs.cpSync(
    `build/arduino/arduino-${ARDUINO_VERSION}/hardware/tools/avr`,
    "build/ml/v1/external/arduino/avr-toolchain",
    { recursive: true }
  );

  // Fix AVR toolchain symlinks
  console.log("Updating AVR toolchain symlinks...");
  const initcwd = process.cwd();
  process.chdir("build/ml/v1/external/arduino/avr-toolchain/avr/bin");
  const binFiles = fs.readdirSync(".");
  for (let i = 0; i < binFiles.length; i++) {
    fs.rmSync(binFiles[i]);
    fs.symlinkSync("../../bin/avr-" + binFiles[i], binFiles[i]);
  }
  process.chdir("../../bin");
  fs.rmSync("avr-c++");
  fs.rmSync("avr-gcc-7.3.0");
  fs.rmSync("avr-ld");
  fs.symlinkSync("avr-g++", "avr-c++");
  fs.symlinkSync("avr-gcc", "avr-gcc-7.3.0");
  fs.symlinkSync("avr-ld.bfd", "avr-ld");
  process.chdir("../lib");
  fs.rmSync("libcc1.so");
  fs.rmSync("libcc1.so.0");
  fs.symlinkSync("libcc1.so.0.0.0", "libcc1.so");
  fs.symlinkSync("libcc1.so.0.0.0", "libcc1.so.0");
  process.chdir("../libexec/gcc/avr/7.3.0");
  fs.rmSync("liblto_plugin.so");
  fs.rmSync("liblto_plugin.so.0");
  fs.symlinkSync("liblto_plugin.so.0.0.0", "liblto_plugin.so");
  fs.symlinkSync("liblto_plugin.so.0.0.0", "liblto_plugin.so.0");
  process.chdir(initcwd);

  console.log("Finished creating mBlock resources");
}

/**
 * Decompresses a 7-zip file.
 * @param {string} sourceArchive - Path to the source .7z file.
 * @param {string} outputDir - Directory to extract files into.
 */
async function decompress7z(sourceArchive, outputDir) {
  return new Promise((resolve, reject) => {
    try {
      fs.chmodSync(sevenBin.path7za, 0o755);
    } catch (chmodError) {
      reject();
      return;
    }

    const fullOptions = {
      $bin: sevenBin.path7za,
    };
    const stream = extractFull(sourceArchive, outputDir, fullOptions);

    stream.on("end", () => {
      resolve();
    });
    stream.on("error", (err) => {
      reject(err);
    });
  });
}

/**
 * Decompresses a .tar.xz file.
 * @param {string} sourceFile - The path to the .tar.xz file.
 * @param {string} destinationDir - The directory to extract contents to.
 */
async function decompressTarXz(sourceFile, destinationDir) {
  const sourceStream = fs.createReadStream(sourceFile);
  const decompressor = lzma.createDecompressor();
  const extractor = tar.extract({
    cwd: destinationDir,
  });
  return new Promise((resolve, reject) => {
    pipeline(sourceStream, decompressor, extractor, (err) => {
      if (err) {
        reject(err);
      } else {
        resolve();
      }
    });
  });
}
