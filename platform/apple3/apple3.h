#ifndef APPLE3_H
#define APPLE3_H
#include <stdint.h>

#define HW(address) (*(volatile uint8_t *)(address))
#define KEYBOARD HW(0xC000)
#define KEY_STROBE HW(0xC010)
#define MODIFIERS HW(0xC008)

/* Native 280x192 color graphics. Sprites are 14x8, XOR drawn, x <= 255.
 * Text x is a character column (0..39); other operations use pixel x.
 * Color is an Apple III foreground nibble with a black background. */
extern uint8_t gfx_x, gfx_y, gfx_color;
/* Optional fixed-color lower band, useful for classic arcade screen overlays.
 * Set gfx_band_y to 192 to disable it. Only sprite colors are affected. */
extern uint8_t gfx_band_y, gfx_band_color;
void video_init(void);
void video_clear(void);
void wait_frame(void);
void __fastcall__ video_sprite(uint8_t sprite);
void __fastcall__ video_text(const char *text);
/* Overwrite one 7x8 cell from eight row bytes (bit 0 is the left pixel).
 * gfx_x is a character column, like video_text. */
void __fastcall__ video_tile(const uint8_t *pattern);
void __fastcall__ video_pixel(uint8_t set);
uint8_t video_read_pixel(void);
void __fastcall__ sound(uint8_t effect);
enum { SFX_LASER, SFX_HIT, SFX_EXPLOSION, SFX_STEP, SFX_BONUS };
extern uint8_t muted;
#endif
