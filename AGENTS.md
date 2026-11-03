# Repository Guidelines

## Project Structure & Module Organization

- `src/zxspectrum.sv` is the shared SystemVerilog top for Nano20K and MiSTle GW5A-25.
- `src/nano20k/` and `src/gw5a_25/` contain board configuration, pin/timing constraints, and PLL artifacts.
- `src/T80/` contains the VHDL CPU; `src/mistle/` implements companion interfaces; `src/hdmi/` contains HDMI logic.
- `src/roms/` stores ROM data; `taps/` contains sample tapes; `sim/` contains simulation and regressions.
- Generated outputs belong in ignored `impl/` and `sim/obj_dir/`.

## Build, Test, and Development Commands

Use **Gowin V1.9.12.03** if available. V1.9.12.04 built successfully but produced a black Spectrum screen on hardware. Run from the repository root:

```sh
gw_sh build.tcl nano20k
gw_sh build.tcl gw5a_25
```

Bitstreams appear at `impl/pnr/zxspectrum_<board>.fs`. `./build.sh <board>` requires the working `gw_sh` and `grc` on PATH.

- `make -C sim build`: build the simulator with GHDL, Verilator, C++, and SDL2.
- `make -C sim sim`: launch graphical simulation.
- `make -C sim trace`: generate a finite trace.
- `make -C sim boot-check`: check ROM boot, timed RAM accesses, video, and resets without a GUI.

## Coding Style & Architecture

Follow surrounding indentation and naming. Preserve **CRLF** in `src/zxspectrum.sv`; avoid unrelated formatting. Use explicit widths and nonblocking sequential assignments. No repository-wide formatter is configured.

Keep board macros in the top/configuration files. `sdram.sv` uses parameters for row width, column width, and RAS-to-CAS delay; do not introduce board `ifdef`s there. The controller remains 16-bit, using Nano20K's lower data half.

SDRAM reset depends only on PLL lock. System reset also waits for synchronized SDRAM ready. Button/OSD resets must preserve SDRAM initialization. Registered CKE is low during SDRAM reset and high after clocked release.

Keep the generated PLL wrapper, primitive module, and startup sequencer together. Regenerate matching files rather than editing parameters independently; the generator's validated tool version is documented in README.

## Testing Guidelines

For SDRAM changes:

```sh
iverilog -g2012 -DSDRAM_ROW_WIDTH=12 -s gw5a_sdram_tb \
  -o /tmp/zx-sdram-test sim/gw5a_sdram_tb.sv src/sdram.sv
vvp /tmp/zx-sdram-test
```

Repeat with `-DSDRAM_ROW_WIDTH=11 -DNANO` for Nano20K. Name testbenches `*_tb.sv`. Rebuild both boards after shared RTL changes. Inspect timing reports separately; record serializer reset findings and hardware-validation limits. No coverage threshold is configured.

## Commit & Pull Request Guidelines

Use short imperative subjects, such as `Fix M key`. Keep commits focused. PRs should describe behavior, affected boards, validation, remaining warnings, and relevant issues. Include screenshots for video/OSD changes. Report newly discovered issues before expanding scope to fix them.
