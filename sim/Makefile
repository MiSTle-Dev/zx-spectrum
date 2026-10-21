N=zxspectrum
D=../src

#MISTLE=1

GHDL ?= ghdl
GHDL_FLAGS = --std=08 --latches --out=verilog -fsynopsys
GHDL_DIR = obj_dir/ghdl
PROJECT_ROOT := $(abspath ..)
VERILATOR_FLAGS = -Wno-fatal

T80PA_VHDL = $D/T80/T80pa.vhd $D/T80/T80_Pack.vhd
GHDL_SRCS = $(GHDL_DIR)/T80pa.v

T80_VHDL = $D/T80/T80.vhd $D/T80/T80_Pack.vhd
GHDL_SRCS += $(GHDL_DIR)/T80.v

T80MCODE_VHDL = $D/T80/T80_MCode.vhd $D/T80/T80_Pack.vhd
GHDL_SRCS += $(GHDL_DIR)/T80MCode.v

T80REG_VHDL = $D/T80/T80_Reg.vhd $D/T80/T80_Pack.vhd
GHDL_SRCS += $(GHDL_DIR)/T80Reg.v

T80ALU_VHDL = $D/T80/T80_ALU.vhd $D/T80/T80_Pack.vhd
GHDL_SRCS += $(GHDL_DIR)/T80ALU.v

# Setting neither of the following will run sim at 113MHz
# run the whole simulation at 28Mhz sys clock
EXTRA_CFLAGS = -DSYS_CLK_DIV=2
VERILATOR_FLAGS += -DSYS_CLK_28MHZ

# run the whole simulation at 56Mhz sys clock
#EXTRA_CFLAGS = -DSYS_CLK_DIV=1
#VERILATOR_FLAGS += -DSYS_CLK_56MHZ

SRCS = config.vh $D/zxspectrum.sv $D/ula.sv $D/keyboard.sv $D/sdram.sv $D/scandoubler.v $D/video_analyzer.v $(GHDL_SRCS)

# include mistle/FPGA companion related files
SRCS += $D/mistle/companion.v $D/mistle/mcu_spi.v $D/mistle/hid.v $D/mistle/sysctrl.v $D/mistle/osd_u8g2.v
SRCS += $D/mistle/sd_card.v $D/mistle/sd_rw.v $D/mistle/sdcmd_ctrl.v 

# Optional compile-time default; at runtime use: ./Vsnestang_top -r roms/game.hex
ifneq ($(ROM_FILE),)
VERILATOR_FLAGS += -DSIM_ROM_FILE=\"$(ROM_FILE)\"
endif

SRCS += sim.cpp
DEPS = Makefile

SRCS += sd_card.cpp
DEPS += sd_card_config.h

VERILATOR_FLAGS += --pins-inout-enables
INCLUDES=-I$D/verilator -I$D

CFLAGS_SDL=$(shell sdl2-config --cflags) -O2
LIBS_SDL=$(shell sdl2-config --libs)

.PHONY: build sim verilate clean gtkwave audio

build: ./obj_dir/V$N

verilate: ./obj_dir/V$N.cpp

$(GHDL_DIR):
	mkdir -p $@

$(GHDL_DIR)/T80pa.v: $(T80PA_VHDL) | $(GHDL_DIR)
	$(GHDL) synth $(GHDL_FLAGS) --vendor-library=work $(T80PA_VHDL) -e T80pa > $@.tmp
	mv $@.tmp $@
	patch -p0 < T80pa.patch

$(GHDL_DIR)/T80.v: $(T80_VHDL) | $(GHDL_DIR)
	$(GHDL) synth $(GHDL_FLAGS) --vendor-library=work $(T80_VHDL) -e T80 > $@.tmp
	mv $@.tmp $@
	patch -p0 < T80.patch

$(GHDL_DIR)/T80MCode.v: $(T80MCODE_VHDL) | $(GHDL_DIR)
	$(GHDL) synth $(GHDL_FLAGS) --vendor-library=work $(T80MCODE_VHDL) -e T80_MCode > $@.tmp
	mv $@.tmp $@

$(GHDL_DIR)/T80Reg.v: $(T80REG_VHDL) | $(GHDL_DIR)
	$(GHDL) synth $(GHDL_FLAGS) --vendor-library=work $(T80REG_VHDL) -e T80_Reg > $@.tmp
	mv $@.tmp $@

$(GHDL_DIR)/T80ALU.v: $(T80ALU_VHDL) | $(GHDL_DIR)
	$(GHDL) synth $(GHDL_FLAGS) --vendor-library=work $(T80ALU_VHDL) -e T80_ALU > $@.tmp
	mv $@.tmp $@

./obj_dir:
	mkdir -p obj_dir

./obj_dir/V$N.cpp: $(DEPS) $(SRCS)
	@echo
	@echo "### VERILATE ####"
	mkdir -p obj_dir
	verilator $(VERILATOR_FLAGS) --top-module $N --trace-fst -cc -O3 --exe -CFLAGS "$(CFLAGS_SDL) $(EXTRA_CFLAGS)" -LDFLAGS "$(LIBS_SDL)" $(INCLUDES) $(SRCS)

./obj_dir/V$N: verilate
	@echo
	@echo "### BUILDING SIM ###"
	$(MAKE) -C obj_dir -f V$N.mk V$N
	cp -a $D/roms obj_dir

sim: ./obj_dir/V$N
	@echo
	@echo "### SIMULATION (GUI) ###"
	@cd obj_dir && ./V$N -c 0

trace: ./obj_dir/V$N
	@echo
	@echo "### SIMULATION (trace) ###"
	@cd obj_dir && ./V$N -t -c 100 2> stderr.log

./obj_dir/waveform.fst: ./obj_dir/V$N Makefile
	@echo
	@echo "### SIMULATION (trace) ###"
	@cd obj_dir && ./V$N -t -s 3600 -c 3650
#	@cd obj_dir && ./V$N -t -s 15 -c 65

wave: obj_dir/waveform.fst
	gtkwave sim.gtkw

audio:
	ffmpeg -y -f s16le -ar 32k -ac 2 -i obj_dir/zxspectrum.aud zxspectrum.wav

clean:
	rm -rf obj_dir
