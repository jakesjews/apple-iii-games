/* Merge 2048 ///. Cells store exponents, not overflowing 16-bit tile values. */
#include "ui.h"
#include <string.h>

#define TITLE 0
#define PLAYING 1
#define WON 2
#define GAME_OVER 3
#define PAUSED 4

uint8_t state, board[16], working[16], undo_board[16], won, undo_won, undo_valid;
uint8_t painted[16];
uint8_t key, action_timer, changed, spawned, last_spawn, last_value;
uint16_t frame_counter, random_state, undo_random, moves, undo_moves;
uint32_t score,best,undo_score;
static const uint8_t tile_colors[16] = {2,7,14,13,9,11,1,3,6,12,4,14,13,9,11,15};
static const uint8_t fill[8] = {0,0,0,0,0,0,0,0};

static uint16_t random_word(void)
{
    random_state = (random_state >> 1) ^ ((random_state & 1) ? 0xB400U : 0);
    return random_state;
}

static void draw_tile(uint8_t index)
{
    uint8_t x,y,col,row,bg,fg,digits,i,a,b,bits,scale;
    uint16_t value;
    char s[6];
    x = 4+(index&3)*8; y = 34+(index>>2)*34;
    bg = tile_colors[board[index]];
    gfx_color = (bg<<4)|bg;
    for (row = 0; row < 4; ++row) for (col = 0; col < 7; ++col) {
        gfx_x = x+col; gfx_y = y+row*8; video_tile(fill);
    }
    if (!board[index]) return;
    value = (uint16_t)1 << board[index];
    /* Bound conversion to five characters, then trim the leading zeroes. */
    digits = 5;
    do { s[--digits] = '0'+value%10; value /= 10; } while (digits);
    while (digits < 4 && s[digits] == '0') ++digits;
    digits = 5-digits;
    scale = digits < 5 ? 2 : 1;
    x = x*7 + (49-(digits*6-1)*scale)/2;
    y += scale == 2 ? 9 : 12;
    fg = bg == 1 || bg == 3 || bg == 4 || bg == 6 ? 15 : 0;
    gfx_color = (fg<<4)|bg;
    for (i = digits; i; --i) {
        for (row = 0; row < 7; ++row) {
            bits = font_bitmap[s[5-i]&63][row];
            for (col = 0; col < 5; ++col) if (bits & (2<<col))
                for (a = 0; a < scale; ++a) for (b = 0; b < scale; ++b) {
                    gfx_x = x+col*scale+a; gfx_y = y+row*scale+b; video_pixel(1);
                }
        }
        x += 6*scale;
    }
}

static void status(void)
{
    ui_text(2,174,0,"                                     ");
    if (state == WON) ui_text(5,174,0xD0,"2048! ENTER TO KEEP PLAYING");
    else if (state == GAME_OVER) ui_text(5,174,0xB0,"NO MOVES. U UNDO OR N NEW");
    else if (state == PAUSED) ui_text(13,174,0xD0,"PAUSED - P");
    else ui_text(4,174,0x70,"ARROWS/WASD MOVE  U UNDO  N NEW");
}

static void draw_board(void)
{
    uint8_t i;
    for (i = 0; i < 16; ++i) if (painted[i] != board[i]) {
        draw_tile(i); painted[i] = board[i];
    }
    ui_number(19,14,score,6); ui_number(31,14,best,6); ui_number(7,14,moves,4);
    status();
}

static void spawn_tile(void)
{
    uint8_t empty[16],count,i;
    count = 0;
    for (i = 0; i < 16; ++i) if (!board[i]) empty[count++] = i;
    if (!count) return;
    last_spawn = empty[random_word()%count];
    last_value = random_word()%10 == 0 ? 2 : 1;
    board[last_spawn] = last_value; ++spawned;
}

static uint8_t can_move(void)
{
    uint8_t i;
    for (i = 0; i < 16; ++i) {
        if (!board[i]) return 1;
        if (board[i] == 15) continue;
        if ((i&3) != 3 && board[i] == board[i+1]) return 1;
        if (i < 12 && board[i] == board[i+4]) return 1;
    }
    return 0;
}

/* Read each row/column from the destination edge toward the opposite edge. */
static uint8_t position(uint8_t line, uint8_t offset, uint8_t direction)
{
    if (direction == 0) return line*4+offset;
    if (direction == 1) return line*4+3-offset;
    if (direction == 2) return offset*4+line;
    return (3-offset)*4+line;
}

static void move_board(uint8_t direction)
{
    uint8_t line,i,count,out,value,index,packed[4];
    uint32_t gain;
    memset(working,0,sizeof(working)); gain = 0;
    for (line = 0; line < 4; ++line) {
        count = 0;
        for (i = 0; i < 4; ++i) {
            value = board[position(line,i,direction)];
            if (value) packed[count++] = value;
        }
        out = 0;
        for (i = 0; i < count; ++i) {
            value = packed[i];
            if (i+1 < count && packed[i+1] == value && value < 15) {
                ++value; ++i; gain += 1UL << value;
            }
            working[position(line,out++,direction)] = value;
        }
    }
    changed = memcmp(board,working,sizeof(board)) != 0;
    if (!changed) {
        if (!can_move()) { state = GAME_OVER; status(); sound(SFX_EXPLOSION); }
        return;
    }
    memcpy(undo_board,board,sizeof(board)); undo_score = score;
    undo_random = random_state; undo_moves = moves; undo_won = won; undo_valid = 1;
    memcpy(board,working,sizeof(board));
    score += gain; if (score > 999999UL) score = 999999UL;
    if (score > best) best = score;
    if (moves < 9999) ++moves;
    spawn_tile();
    if (!won) for (index = 0; index < 16; ++index) if (board[index] >= 11) {
        won = 1; state = WON; break;
    }
    if (state != WON && !can_move()) state = GAME_OVER;
    sound(state == WON ? SFX_BONUS : (gain ? SFX_HIT : SFX_STEP));
    draw_board();
}

static void undo(void)
{
    if (!undo_valid) return;
    memcpy(board,undo_board,sizeof(board)); score = undo_score; random_state = undo_random;
    moves = undo_moves; won = undo_won; undo_valid = 0; state = PLAYING;
    draw_board();
}

static void new_game(void)
{
    video_clear(); memset(board,0,sizeof(board)); memset(painted,255,sizeof(painted));
    score = 0; moves = 0; won = 0; undo_valid = 0; spawned = 0; state = PLAYING;
    random_state = frame_counter | 1;
    spawn_tile(); spawn_tile();
    ui_text(2,3,0xE0,"MERGE 2048"); ui_text(19,3,0x70,"SCORE"); ui_text(31,3,0x70,"BEST");
    ui_text(2,14,0x70,"MOVE");
    ui_text(6,184,0x70,"P PAUSE  M SOUND  ESC TITLE");
    draw_board();
}

static void title_screen(void)
{
    video_clear(); state = TITLE;
    ui_text(5,9,0x70,"A P P L E   / / /   A R C A D E");
    ui_title("MERGE 2048",40,32,0xD0);
    ui_text(9,70,0xF0,"SLIDE. JOIN. REPEAT.");
    ui_title("2 + 2 = 4",49,89,0x90);
    ui_text(9,126,0xD0,"PRESS SPACE TO START");
    ui_text(5,149,0xF0,"ARROWS OR WASD SLIDE THE BOARD");
    ui_text(7,163,0x70,"U UNDO  N NEW  P PAUSE");
    ui_text(7,181,0x70,"MAKE THE 2048 TILE. KEEP GOING.");
}

void main(void)
{
    video_init(); title_screen();
    for (;;) {
        wait_frame(); ++frame_counter; key = ui_key();
        if (action_timer) --action_timer;
        if (state == TITLE) { if (key == ' ' || key == 13) new_game(); continue; }
        if (key == 27) { title_screen(); continue; }
        if (key == 'M' && !action_timer) { muted ^= 1; action_timer = 12; }
        if (key == 'P' && !action_timer && (state == PLAYING || state == PAUSED)) {
            state = state == PLAYING ? PAUSED : PLAYING; action_timer = 12; status();
        }
        if (state == PAUSED) continue;
        if (key == 'N') { new_game(); continue; }
        if (key == 'U') { undo(); continue; }
        if (state == WON && key == 13) { state = can_move() ? PLAYING : GAME_OVER; status(); }
        if (state != PLAYING) continue;
        if (key == 8 || key == 'A') move_board(0);
        if (key == 21 || key == 'D') move_board(1);
        if (key == 11 || key == 'W') move_board(2);
        if (key == 10 || key == 'S') move_board(3);
    }
}
