#ifndef SD_CARD_CONFIG_H
#define SD_CARD_CONFIG_H

#define TICKLEN   (0.5/28000000)

#define TB_NAME   Vzxspectrum

#include "Vzxspectrum.h"

#ifdef SD_CARD_CPP
const char *file_image[8] = {
  "../../taps/hello.tap",
  NULL, NULL, NULL, NULL, NULL, NULL, NULL            // unused
};
#else
extern char *file_image[8];
extern int file_image_len[8];
#endif

#define MAX_DRIVES   1  // one cartridge

// enable to test direct mapping bypassing the companion if possible
#define ENABLE_DIRECT_MAP

// enable writing of modified data back into image ... potentially corrupting it
// #define WRITE_BACK

// enable this to simulate a FPGA Companion constantly writing and reading data,
// potentially colliding with the Core's own accesses
// #define FC_RW_STORM

// interface to sd card simulation
void sd_init(void);
void sd_handle(void);
void sd_get_sector(int drive, int lba, uint8_t *data);

inline void sd_set_file(int i, char *name) { file_image[i] = name; };

void hexdump(void *data, int size);
void hexdiff(void *data1, void *data2, int size);

// clocks the SD card claims to be busy before read data is returned
#define READ_BUSY_COUNT 100

#endif
