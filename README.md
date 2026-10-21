# MiSTle - ZX Spectrum

This is a port of the [ZX Spectrum core for MiST](https://github.com/sorgelig/zx_spectrum-128k_mist).

## Current state

  - Implements a standard ZX Spectrum 48k
  - Implements a TAP tape loader (no TZX yet)
  - Fully integrated into the MiSTle framework

## Usage

To load a game from a TAP file do the following:

  - Copy a TAP file like [hello.tap](taps/hello.tap) onto sd card and insert it
  - Flash/load the core, no seperate ROM flashing needed
  - At the prompt type ```J```, ```Ctrl-P``` twice and then hit ```Return```
  - The screen will go blank
  - Hit ```F12``` to open the OSD and select the previusly installed ```TAP``` file
  - The file should load
  - If needed, type ```R``` to run the program

