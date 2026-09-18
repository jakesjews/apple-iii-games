#ifndef APPLE3_UI_H
#define APPLE3_UI_H
/* Small shared screen helpers; game rules stay in each game's directory. */
#include "apple3.h"
extern const uint8_t font_bitmap[64][8];

static void ui_text(uint8_t x, uint8_t y, uint8_t color, const char *s)
{
    gfx_x = x; gfx_y = y; gfx_color = color; video_text(s);
}

static void ui_number(uint8_t x, uint8_t y, uint32_t n, uint8_t digits)
{
    char s[11];
    uint8_t i;
    s[digits] = 0; i = digits;
    do { s[--i] = '0' + n % 10; n /= 10; } while (i);
    ui_text(x,y,0xF0,s);
}

static void ui_title(const char *s, uint8_t x, uint8_t y, uint8_t color)
{
    uint8_t row,col,a,b,bits;
    gfx_color = color;
    while (*s) {
        for (row = 0; row < 7; ++row) {
            bits = font_bitmap[*s & 63][row];
            for (col = 0; col < 5; ++col) {
                if (!(bits & (2 << col))) continue;
                for (a = 0; a < 3; ++a) for (b = 0; b < 3; ++b) {
                    gfx_x = x+col*3+a; gfx_y = y+row*3+b; video_pixel(1);
                }
            }
        }
        x += 20; ++s;
    }
}

static uint8_t ui_key(void)
{
    uint8_t key;
    if (!(KEYBOARD & 128)) return 0;
    key = KEYBOARD & 127; KEY_STROBE = 0;
    if (key >= 'a' && key <= 'z') key -= 32;
    return key;
}
#endif
