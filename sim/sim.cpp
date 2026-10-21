/*
 * zxspectrum sim.cpp
 *
 *
 *
 */

  

#include <cstdio>
#include <iostream>
#include <SDL.h>
#include <cstdlib>
#include <climits>
#include <cstring>
#include <vector>
#include <cctype>
#include <chrono>
#include <thread>

#include "Vzxspectrum.h"
#include "Vzxspectrum_zxspectrum.h"
#include "verilated.h"
#include <verilated_fst_c.h>

#include "sd_card_config.h"

#ifndef SYS_CLK_DIV
#define SYS_CLK_DIV  0
#endif

#define SYS_CLK (113.5/(1<<SYS_CLK_DIV))

#define TRACE_ON

using namespace std;

// See: https://projectf.io/posts/verilog-sim-verilator-sdl/
const int H_RES = 2*448;
const int V_RES = 2*312;

typedef struct Pixel {  // for SDL texture
    uint8_t a;  // transparency
    uint8_t b;  // blue
    uint8_t g;  // green
    uint8_t r;  // red
} Pixel;

Pixel screenbuffer[H_RES*V_RES];

bool trace = false;

void usage() {
	printf("Usage: sim [-r ROM."
#ifdef MISTLE	       
	       "sfc/smc"
#else
	       "hex"
#endif
	       "] [-t] [-c T]\n");
	printf("  -r FILE load FILE as the SNES ROM (maximum 4 MiB)\n");
	printf("  -t     output trace file waveform.fst\n");
	printf("  -s T0  start tracing from time T0 milliseconds\n");
	printf("  -c T   limit simulate length to T milliseconds. T=0 means infinite.\n");
}

VerilatedFstC *m_trace;
Vzxspectrum* tb;

// split by spaces
vector<string> tokenize(string s);
void trace_on();
void trace_off();

// optionally parse a sector address into track/side/sector
char *sector_string(int drive, uint32_t lba) {
  static char str[32];
  strcpy(str, "");
  return str;
}

double simulation_time = 0.0;
// Default 50ms
double max_sim_time = 0.05;
double start_trace_time = 0.0;

extern "C" void display_simtime(void) {
  printf("%.3fms ",  simulation_time*1000);
}

#if 0
#define EVT_SDC_MOUNT  0.01
#else
#define EVT_KBD_LOAD   1.7
#define EVT_SDC_MOUNT  2.5
#define EVT_KBD_RUN    10.0
#endif

// simulate companion io
void companion(void) {
  //                           HID   KBD   code
  static struct {
    float time;
    const char *data;
    const char *desc;
  } cmds[] = {
    { 0.0001, "\x00\x04R\x00\xff", "Release reset" },

#ifdef EVT_KBD_LOAD 
    { EVT_KBD_LOAD+0.0, "\x01\x01\x0d\xff", "Press J" },
    { EVT_KBD_LOAD+0.1, "\x01\x01\x8d\xff", "Release J" },
    { EVT_KBD_LOAD+0.2, "\x01\x01\x68\xff", "Press Ctrl" },
    { EVT_KBD_LOAD+0.3, "\x01\x01\x13\xff", "Press P" },
    { EVT_KBD_LOAD+0.4, "\x01\x01\x93\xff", "Release P" },
    { EVT_KBD_LOAD+0.5, "\x01\x01\x13\xff", "Press P" },
    { EVT_KBD_LOAD+0.6, "\x01\x01\x93\xff", "Release P" },
    { EVT_KBD_LOAD+0.7, "\x01\x01\xe8\xff", "Release Ctrl" },
    { EVT_KBD_LOAD+0.8, "\x01\x01\x28\xff", "Press Enter" },
    { EVT_KBD_LOAD+0.9, "\x01\x01\xa8\xff", "Release Enter" },
#endif
    
#ifdef EVT_SDC_MOUNT 
    //                       SDC  INS DRV <-    LEN    ->
    { EVT_SDC_MOUNT+0.0003, "\x03\x04\x00\x00\x00\x00\x00\xff", "Insert TAP" },    
    //                       SDC  DIR DRV <-    START  ->
    { EVT_SDC_MOUNT+0.00032,"\x03\x06\x00\x01\x00\x00\x00\xff", "Direct map" },
#endif
    
#ifdef EVT_KBD_RUN
    { EVT_KBD_RUN+0.0, "\x01\x01\x15\xff", "Press R" },
    { EVT_KBD_RUN+0.1, "\x01\x01\x95\xff", "Release R" },
    { EVT_KBD_RUN+0.2, "\x01\x01\x28\xff", "Press Enter" },
    { EVT_KBD_RUN+0.3, "\x01\x01\xa8\xff", "Release Enter" },
#endif

    { 0.0,   NULL, NULL }
  };
  static int cur = 0;  
  static int cnt = -1;

  // not at end of command list?
  if(cmds[cur].data) {
    if(cnt < 0) {
      // is the next command due?
      if(cmds[cur].time < simulation_time) {
	printf("%.3fms MCU CMD %d: %s\n", simulation_time*1000, cur, cmds[cur].desc);

	// adjust embedded tap length in insert command
	if(cmds[cur].data[0] == 0x03 && cmds[cur].data[1] == 0x04) {
	  static char cmd[10];
	  memcpy(cmd, cmds[cur].data, 10);
	  cmd[3] = (file_image_len[0] >> 24)&0xff;
	  cmd[4] = (file_image_len[0] >> 16)&0xff;
	  cmd[5] = (file_image_len[0] >> 8)&0xff;
	  cmd[6] = (file_image_len[0] >> 0)&0xff;
	  cmds[cur].data = cmd;
	}
	
	cnt = 0;  // start transmitting
	tb->mcu_ss = 0;
      }
    } else {
      int index = cnt/10;     // adjust tx speed
      int clk   = (cnt%10)<5;
      int byte  = index/8;
      int bit   = index%8;      

      // reached end of this command sequence?
      if(cmds[cur].data[byte] == -1) {
	tb->mcu_clk = 0;
	tb->mcu_ss = 1;
	cnt = -1;
	cur++;
      } else {
	// MODE 1: clock is idle low and data is sampled on the falling edge
	tb->mcu_clk = clk;
	tb->mcu_din = (cmds[cur].data[byte] & (0x80>>bit))?1:0;
	cnt++;
      }
    }
  }  
}

int main(int argc, char** argv, char** env) {
	// Accept a conventional option and translate it to the Verilog plusarg
	// consumed by test_loader. Direct +ROM=... remains supported as well.
	vector<string> command_strings;
	vector<char*> command_args;
	command_strings.reserve(argc + 1);
	command_args.reserve(argc + 1);
	for (int i = 0; i < argc; i++) {
	  if (strcmp(argv[i], "-r") == 0 && i + 1 < argc) {
	    sd_set_file(0, argv[++i]);
	  } else {
	    command_strings.emplace_back(argv[i]);
	  }
	}
	for (string& arg : command_strings)
	  command_args.push_back(arg.data());
	Verilated::commandArgs(command_args.size(), command_args.data());
	tb = new Vzxspectrum;

	printf("Running at sys clock = %.2f MHz\n", SYS_CLK);

	bool frame_updated = false;
	uint64_t start_ticks = SDL_GetPerformanceCounter();
	int frame_count = 0;

	// parse options
	for (int i = 1; i < argc; i++) {
		char *eptr;
		if (strcmp(argv[i], "-t") == 0) {
			trace = true;
			printf("Tracing ON\n");
		} else if (strcmp(argv[i], "-c") == 0 && i+1 < argc) {
			max_sim_time = strtof(argv[++i], &eptr) / 1000.0;
			if (max_sim_time == 0)
				printf("Simulating forever.\n");
			else
				printf("Simulating %.3f ms\n", max_sim_time*1000.0);
		} else if (strcmp(argv[i], "-r") == 0 && i+1 < argc) {
			i++;
			printf("Loading ROM %s\n", argv[i]);
		} else if (strncmp(argv[i], "+ROM=", 5) == 0) {
			printf("Loading ROM %s\n", argv[i] + 5);
		} else if (strcmp(argv[i], "-s") == 0 && i+1 < argc) {
			start_trace_time = strtof(argv[++i], &eptr) / 1000.0;
			printf("Start tracing from %.3f ms\n", start_trace_time*1000.0);
		} else {
			printf("Unrecognized option: %s\n", argv[i]);
			usage();
			exit(1);
		}
	}

    if (SDL_Init(SDL_INIT_VIDEO) < 0) {
        printf("SDL init failed.\n");
        return 1;
    }

    SDL_Window*   sdl_window   = NULL;
    SDL_Renderer* sdl_renderer = NULL;
    SDL_Texture*  sdl_texture  = NULL;

    sdl_window = SDL_CreateWindow("zxspectrum", SDL_WINDOWPOS_CENTERED,
        SDL_WINDOWPOS_CENTERED, H_RES, V_RES, SDL_WINDOW_SHOWN);
    if (!sdl_window) {
        printf("Window creation failed: %s\n", SDL_GetError());
        return 1;
    }
    sdl_renderer = SDL_CreateRenderer(sdl_window, -1,
        SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC);
    if (!sdl_renderer) {
        printf("Renderer creation failed: %s\n", SDL_GetError());
        return 1;
    }

    sdl_texture = SDL_CreateTexture(sdl_renderer, SDL_PIXELFORMAT_RGBA8888,
        SDL_TEXTUREACCESS_STREAMING, H_RES, V_RES);
    if (!sdl_texture) {
        printf("Texture creation failed: %s\n", SDL_GetError());
        return 1;
    }

    sd_init();
    
	if (trace)
		trace_on();

	int audio_ready_r = 0;
	FILE *f = fopen("zxspectrum.aud", "w");
	long long samples = 0;

	// init
	tb->mcu_ss = 1;
	
	while (max_sim_time == 0 || simulation_time < max_sim_time) {
		tb->CLOCK_27 ^= 1;

		sd_handle();

		companion();
		
		// ------------ simulate sdram ---------------
		static uint16_t next_rd_data;
		static uint16_t next_rd_data_delay = 0;
		if(next_rd_data_delay) {
		  next_rd_data_delay--;
		  if(!next_rd_data_delay)
		    tb->SDRAM_DQ = next_rd_data;
		}
		      
		if(!tb->SDRAM_CLK && !tb->SDRAM_nCS) {
		  // 8M*16
		  static unsigned short ram[8*1024*1024];

		  static int ram_addr = 0;
		  if(!tb->SDRAM_nRAS && tb->SDRAM_nCAS) {
		    ram_addr =  tb->SDRAM_A  <<  9;  // A 22:10
		    ram_addr |= tb->SDRAM_BA << 22;  // A 24:23
		  }
		  
		  if(!tb->SDRAM_nCAS && tb->SDRAM_nRAS) {
		    ram_addr |= (tb->SDRAM_A & 0x1ff); // A 9:1

		    if(!tb->SDRAM_nWE) {
		      // the data line must be driven
		      if(!tb->SDRAM_DQ__en)
			printf("ERROR: SDRAM_DQ not driven during write\n");

		      if(tb->SDRAM_DQML == tb->SDRAM_DQMH)
			printf("ERROR: not a byte write\n");
		      
		      if(tb->SDRAM_DQMH) {
			ram[ram_addr] &= 0xff00;
			ram[ram_addr] |= (tb->SDRAM_DQ__out & 0xff);
		      }

		      if(tb->SDRAM_DQML) {
			ram[ram_addr] &= 0x00ff;
			ram[ram_addr] |= (tb->SDRAM_DQ__out & 0xff00);
		      }
			
		    } else {
		      if(tb->SDRAM_DQ__en)
			printf("ERROR: SDRAM_DQ driven during read\n");
		      
		      // tb->SDRAM_DQ = ram[ram_addr];
		      // delay output of ram data to verify how many spare cycles there are
		      next_rd_data = ram[ram_addr];
		      next_rd_data_delay = 2;
		    }

		  }
		}		
		
		tb->eval();
		
		// tracing happens in picoseconds
		if (trace && simulation_time >= start_trace_time)
			m_trace->dump(1000000000000 * simulation_time);

#if 0
		// collect audio sample
		if (snes->audio_ready && audio_ready_r == 0) {
			short ar, al;
			ar = snes->audio_r;
			al = snes->audio_l;
			fwrite(&ar, sizeof(ar), 1, f);
			fwrite(&al, sizeof(al), 1, f);
			samples ++;
			if (samples % 1000 == 0)
			  printf("%.3fms %lld samples\n", simulation_time*1000, samples);
		}
		audio_ready_r = snes->audio_ready;
#endif

		// check for quit event
		static int poll_cnt = 0;
		if(poll_cnt++ == 10000) {
			SDL_Event e;
			if ((SDL_PollEvent(&e)) && (e.type == SDL_QUIT))
					break;
			poll_cnt = 0;
		}

		static int x_out = 0;
		static int y_out = 0;

		static int last_hs = 0;
		if(tb->zxspectrum->sd_out_hs || (tb->zxspectrum->sd_out_hs == last_hs)) 
		  x_out++;
		else {
		  x_out=0;
		  
		  static int last_vs = 0;
		  if(tb->zxspectrum->sd_out_vs || (tb->zxspectrum->sd_out_vs == last_vs)) 
		    y_out++;
		  else
		    y_out = 0;

		  last_vs = tb->zxspectrum->sd_out_vs;
		}
		last_hs = tb->zxspectrum->sd_out_hs;
		
		const unsigned y = y_out;

		// if the screen is black consider using !field
		if (y < V_RES && (x_out >> (3-SYS_CLK_DIV)) < H_RES) {
			Pixel* p = &screenbuffer[y*H_RES + (x_out >> (3-SYS_CLK_DIV))];
			p->a = 0xFF;  // transparency
			p->b = tb->zxspectrum->osd_out_b<<3;
			p->g = tb->zxspectrum->osd_out_g<<3;
			p->r = tb->zxspectrum->osd_out_r<<3;
		}
		
		// update texture once per frame (in blanking)
		if (y == V_RES-1) {
			if (!frame_updated) {
				frame_updated = true;
				if (SDL_UpdateTexture(sdl_texture, NULL, screenbuffer, H_RES*sizeof(Pixel)) < 0) {
					fprintf(stderr, "Texture update failed: %s\n", SDL_GetError());
					break;
				}
				SDL_RenderClear(sdl_renderer);
				if (SDL_RenderCopy(sdl_renderer, sdl_texture, NULL, NULL) < 0) {
					fprintf(stderr, "Frame render failed: %s\n", SDL_GetError());
					break;
				}
				SDL_RenderPresent(sdl_renderer);
				frame_count++;

				if (frame_count % 10 == 0)
				  printf("%.3fms Frame #%d\n", simulation_time*1000, frame_count);
			}
		} else
			frame_updated = false;


		simulation_time += 0.5/1000000/SYS_CLK;
	}


	printf("Simulation done, time=%.3f ms\n", simulation_time*1000.0);

	fclose(f);
	printf("Audio output to zxspectrum.aud done.\n");

	if (m_trace)
		m_trace->close();
	delete tb;

    // calculate frame rate
    uint64_t end_ticks = SDL_GetPerformanceCounter();
    double duration = ((double)(end_ticks-start_ticks))/SDL_GetPerformanceFrequency();
    double fps = (double)frame_count/duration;
    printf("Frames per second: %.1f. Total frames=%d\n", fps, frame_count);

    // std::this_thread::sleep_for(std::chrono::seconds(5));

    SDL_DestroyTexture(sdl_texture);
    SDL_DestroyRenderer(sdl_renderer);
    SDL_DestroyWindow(sdl_window);
    SDL_Quit();

	return 0;
}

bool is_space(char c) {
	return c == ' ' || c == '\t';
}

vector<string> tokenize(string s) {
	string w;
	vector<string> r;

	for (int i = 0; i < s.size(); i++) {
		char c = s[i];
		if (is_space(c) && w.size() > 0) {
			r.push_back(w);
			w = "";
		}
		if (!is_space(c))
			w += c;
	}
	if (w.size() > 0)
		r.push_back(w);
	return r;
}

void trace_on() {
	if (!m_trace) {
		m_trace = new VerilatedFstC;
		tb->trace(m_trace, 5);
		Verilated::traceEverOn(true);
		m_trace->open("waveform.fst");
	}
}

void trace_off() {
	if (m_trace) {
		tb->trace(m_trace, 0);
	}
}
