/* Blockfall ///: an original falling-block game for the native Apple III.
 * Board cells align with the machine's seven-pixel color attributes. */
#include "apple3.h"
#include <string.h>

#define TITLE 0
#define PLAYING 1
#define PAUSED 2
#define GAME_OVER 3
#define CLEARING 4
#define WIDTH 10
#define HEIGHT 22
#define HIDDEN 2
#define WELL_COLUMN 14
#define WELL_TOP 24
#define EMPTY_HOLD 255
#define LOCK_DELAY 30
#define LOCK_RESETS 8

extern const uint8_t font_bitmap[64][8];

/* I, O, T, J, L, S, Z. Four occupied cells in a 4x4 box per rotation.
 * Cell index = y*4+x. Rotations use simple bounded wall/floor kicks. */
const uint8_t shapes[7][4][4] = {
    {{4,5,6,7}, {2,6,10,14}, {8,9,10,11}, {1,5,9,13}},
    {{1,2,5,6}, {1,2,5,6}, {1,2,5,6}, {1,2,5,6}},
    {{1,4,5,6}, {1,5,6,9}, {4,5,6,9}, {1,4,5,9}},
    {{0,4,5,6}, {1,2,5,9}, {4,5,6,10}, {1,5,8,9}},
    {{2,4,5,6}, {1,5,9,10}, {4,5,6,8}, {0,1,5,9}},
    {{1,2,4,5}, {1,5,6,10}, {5,6,8,9}, {0,4,5,9}},
    {{0,1,5,6}, {2,5,6,9}, {4,5,9,10}, {1,4,5,8}}
};
static const uint8_t colors[8] = {0x20,0xE0,0xD0,0xB0,0x60,0x90,0xC0,0x10};
static const uint8_t tile[8] = {0x3F,0x3D,0x3D,0x3D,0x3D,0x3D,0x3F,0};
static const uint8_t ghost_tile[8] = {0x3F,0x21,0x21,0x21,0x21,0x21,0x3F,0};
static const uint8_t empty_tile[8] = {0,0,0,0,0,0,0,0x40};
static const uint8_t blank_tile[8] = {0,0,0,0,0,0,0,0};
static const uint8_t vertical_border[8] = {2,2,2,2,2,2,2,2};
static const uint8_t horizontal_border[8] = {0x7F,0,0,0,0,0,0,0};
static const uint8_t gravity[20] = {48,43,38,33,28,23,18,13,8,6,5,5,4,4,3,3,2,2,2,2};
static const uint16_t line_points[5] = {0,100,300,500,800};
static const int8_t kick_x[7] = {0,-1,1,-2,2,0,0};
static const int8_t kick_y[7] = {0,0,0,0,0,-1,-2};

uint8_t state, board[HEIGHT][WIDTH], piece, next_piece, held_piece, rotation;
int8_t piece_x, piece_y, ghost_y;
uint8_t bag[7], bag_index, random_state;
uint8_t hold_used, fall_timer, lock_timer, lock_resets, ghost_dirty, falling_drawn;
uint8_t clear_rows[HEIGHT], clear_count, clear_timer;
uint8_t level, move_timer, action_timer, transition_timer, hud_dirty;
int8_t move_direction;
uint8_t key, modifiers, shift_was_down, hard_pressed, soft_hold;
uint16_t lines, pieces_locked, frame_counter;
uint32_t score, best;

static void text(uint8_t x, uint8_t y, uint8_t color, const char *s)
{
    gfx_x = x; gfx_y = y; gfx_color = color;
    video_text(s);
}

static void cell(uint8_t x, uint8_t y, uint8_t color, const uint8_t *pattern)
{
    gfx_x = x; gfx_y = y; gfx_color = color;
    video_tile(pattern);
}

static void number(uint8_t x, uint8_t y, uint32_t value, uint8_t digits)
{
    char s[7];
    uint8_t i;
    s[digits] = 0;
    i = digits;
    do { s[--i] = '0' + value % 10; value /= 10; } while (i);
    text(x,y,0xF0,s);
}

static void hud(void)
{
    number(2,42,score,6);
    number(2,72,best,6);
    number(2,102,lines,4);
    number(2,132,level,2);
    number(2,162,pieces_locked,4);
    hud_dirty = 0;
}

static void award(uint32_t points)
{
    score += points;
    if (score > 999999UL) score = 999999UL;
    if (score > best) best = score;
    hud_dirty = 1;
}

static uint8_t random_byte(void)
{
    uint8_t carry;
    carry = random_state & 128;
    random_state <<= 1;
    if (carry) random_state ^= 0x1D;
    return random_state;
}

static uint8_t take_piece(void)
{
    uint8_t i,j,temp;
    if (bag_index == 7) {
        for (i = 0; i < 7; ++i) bag[i] = i;
        for (i = 6; i; --i) {
            j = random_byte() % (i+1);
            temp = bag[i]; bag[i] = bag[j]; bag[j] = temp;
        }
        bag_index = 0;
    }
    return bag[bag_index++];
}

static uint8_t fits(int8_t x, int8_t y, uint8_t turn)
{
    uint8_t i,offset;
    int8_t bx,by;
    for (i = 0; i < 4; ++i) {
        offset = shapes[piece][turn][i];
        bx = x + (offset & 3);
        by = y + (offset >> 2);
        if (bx < 0 || bx >= WIDTH || by < 0 || by >= HEIGHT) return 0;
        if (board[(uint8_t)by][(uint8_t)bx]) return 0;
    }
    return 1;
}

static void board_cell(uint8_t x, uint8_t y)
{
    uint8_t value;
    if (y < HIDDEN) return;
    value = board[y][x];
    cell(WELL_COLUMN+x, WELL_TOP+(y-HIDDEN)*8, colors[value], value ? tile : empty_tile);
}

static void draw_board(void)
{
    uint8_t x,y;
    for (y = HIDDEN; y < HEIGHT; ++y)
        for (x = 0; x < WIDTH; ++x) board_cell(x,y);
}

static void draw_piece(int8_t y, uint8_t erase, uint8_t ghost)
{
    uint8_t i,offset;
    int8_t bx,by;
    for (i = 0; i < 4; ++i) {
        offset = shapes[piece][rotation][i];
        bx = piece_x + (offset & 3);
        by = y + (offset >> 2);
        if (by < HIDDEN || by >= HEIGHT || bx < 0 || bx >= WIDTH) continue;
        if (erase) board_cell((uint8_t)bx,(uint8_t)by);
        else cell(WELL_COLUMN+bx,WELL_TOP+(by-HIDDEN)*8,
                  ghost ? 0x50 : colors[piece+1], ghost ? ghost_tile : tile);
    }
}

static void erase_falling(void)
{
    if (!falling_drawn) return;
    if (ghost_y > piece_y) draw_piece(ghost_y,1,1);
    draw_piece(piece_y,1,0);
    falling_drawn = 0;
}

static void find_ghost(void)
{
    if (!ghost_dirty) return;
    ghost_y = piece_y;
    while (fits(piece_x,ghost_y+1,rotation)) ++ghost_y;
    ghost_dirty = 0;
}

static void draw_falling(void)
{
    find_ghost();
    if (ghost_y > piece_y) draw_piece(ghost_y,0,1);
    draw_piece(piece_y,0,0);
    falling_drawn = 1;
}

static void preview(uint8_t which, uint8_t y)
{
    uint8_t x,row,i,offset;
    for (row = 0; row < 4; ++row)
        for (x = 0; x < 5; ++x) cell(28+x,y+row*8,0,blank_tile);
    if (which == EMPTY_HOLD) return;
    for (i = 0; i < 4; ++i) {
        offset = shapes[which][0][i];
        cell(28+(offset&3),y+(offset>>2)*8,colors[which+1],tile);
    }
}

static void game_over(void)
{
    state = GAME_OVER;
    transition_timer = 45;
    text(2,176,0xB0,"GAME OVER");
    text(27,184,0xD0,"SPACE RETRY");
    sound(SFX_EXPLOSION);
}

static void reset_position(void)
{
    piece_x = 3; piece_y = HIDDEN; rotation = 0;
    fall_timer = 0; lock_timer = 0; lock_resets = 0;
    ghost_dirty = 1; falling_drawn = 0;
    if (!fits(piece_x,piece_y,rotation)) game_over();
}

static void spawn_piece(void)
{
    piece = next_piece;
    next_piece = take_piece();
    hold_used = 0;
    reset_position();
    preview(next_piece,42);
}

static void hold_piece(void)
{
    uint8_t temp;
    if (hold_used) return;
    temp = held_piece;
    held_piece = piece;
    if (temp == EMPTY_HOLD) spawn_piece();
    else { piece = temp; reset_position(); }
    hold_used = 1;
    preview(held_piece,92);
    sound(SFX_HIT);
}

static void reset_lock(void)
{
    if (lock_timer && lock_resets < LOCK_RESETS) {
        lock_timer = 0;
        ++lock_resets;
    }
}

static void move_piece(int8_t dx)
{
    if (fits(piece_x+dx,piece_y,rotation)) {
        piece_x += dx;
        ghost_dirty = 1;
        reset_lock();
    }
}

static void rotate_piece(int8_t direction)
{
    uint8_t turn,i;
    if (piece == 1) return; /* The square does not move when rotated. */
    turn = (rotation + direction) & 3;
    for (i = 0; i < 7; ++i) {
        if (fits(piece_x+kick_x[i],piece_y+kick_y[i],turn)) {
            piece_x += kick_x[i]; piece_y += kick_y[i]; rotation = turn;
            ghost_dirty = 1;
            reset_lock();
            sound(SFX_STEP);
            return;
        }
    }
}

static void lock_piece(void)
{
    uint8_t i,x,y,offset,above;
    above = 0;
    for (i = 0; i < 4; ++i) {
        offset = shapes[piece][rotation][i];
        x = piece_x + (offset & 3); y = piece_y + (offset >> 2);
        board[y][x] = piece+1;
        if (y < HIDDEN) above = 1;
        else board_cell(x,y);
    }
    if (pieces_locked < 9999) ++pieces_locked;
    hud_dirty = 1;
    falling_drawn = 0;
    if (above) { game_over(); return; }
    clear_count = 0;
    memset(clear_rows,0,sizeof(clear_rows));
    for (y = HIDDEN; y < HEIGHT; ++y) {
        for (x = 0; x < WIDTH && board[y][x]; ++x) {}
        if (x == WIDTH) { clear_rows[y] = 1; ++clear_count; }
    }
    if (clear_count) {
        state = CLEARING;
        clear_timer = 12;
        sound(SFX_BONUS);
    } else {
        sound(SFX_STEP);
        spawn_piece();
    }
}

static void clear_frame(void)
{
    uint8_t x,y;
    int8_t source,destination;
    --clear_timer;
    if (clear_timer == 10 || clear_timer == 5) {
        for (y = HIDDEN; y < HEIGHT; ++y)
            if (clear_rows[y])
                for (x = 0; x < WIDTH; ++x)
                    cell(WELL_COLUMN+x,WELL_TOP+(y-HIDDEN)*8,0xF0,
                         clear_timer == 10 ? tile : blank_tile);
    }
    if (clear_timer) return;
    destination = HEIGHT-1;
    for (source = HEIGHT-1; source >= 0; --source) {
        if (clear_rows[(uint8_t)source]) continue;
        for (x = 0; x < WIDTH; ++x) board[(uint8_t)destination][x] = board[(uint8_t)source][x];
        --destination;
    }
    while (destination >= 0) {
        for (x = 0; x < WIDTH; ++x) board[(uint8_t)destination][x] = 0;
        --destination;
    }
    award((uint32_t)line_points[clear_count] * level);
    lines += clear_count;
    if (lines > 9999) lines = 9999;
    level = lines >= 190 ? 20 : 1 + lines/10;
    draw_board();
    state = PLAYING;
    spawn_piece();
    hud();
    if (state == PLAYING) draw_falling();
}

static void new_game(void)
{
    uint8_t x,y;
    video_clear();
    memset(board,0,sizeof(board));
    memset(clear_rows,0,sizeof(clear_rows));
    state = PLAYING; score = 0; lines = 0; pieces_locked = 0; level = 1;
    clear_count = 0; held_piece = EMPTY_HOLD; hold_used = 0;
    move_direction = 0; move_timer = 0; soft_hold = 0;
    bag_index = 7;
    random_state = (uint8_t)frame_counter | 1;
    text(2,5,0xE0,"BLOCKFALL");
    text(27,5,0x70,"APPLE ///");
    text(2,30,0x70,"SCORE");
    text(2,60,0x70,"BEST");
    text(2,90,0x70,"LINES");
    text(2,120,0x70,"LEVEL");
    text(2,150,0x70,"PLACED");
    text(27,30,0x70,"NEXT");
    text(27,80,0x70,"HOLD");
    text(27,128,0x70,"X/UP ROTATE");
    text(27,139,0x70,"Z REVERSE");
    text(27,150,0x70,"C HOLD");
    text(27,161,0x70,"SPACE DROP");
    text(27,173,0x70,"P PAUSE");
    text(27,184,0x70,"M SOUND");
    for (x = WELL_COLUMN-1; x <= WELL_COLUMN+WIDTH; ++x) {
        cell(x,22,0x60,horizontal_border);
        cell(x,184,0x60,horizontal_border);
    }
    for (y = 0; y < 20; ++y) {
        cell(WELL_COLUMN-1,WELL_TOP+y*8,0x60,vertical_border);
        cell(WELL_COLUMN+WIDTH,WELL_TOP+y*8,0x60,vertical_border);
    }
    draw_board();
    next_piece = take_piece();
    spawn_piece();
    preview(held_piece,92);
    draw_falling();
    hud();
}

static void big_title(void)
{
    const char *s;
    uint8_t x,row,col,a,b,bits;
    s = "BLOCKFALL"; x = 49;
    while (*s) {
        for (row = 0; row < 7; ++row) {
            bits = font_bitmap[*s & 63][row];
            gfx_color = row < 3 ? 0xD0 : 0x90;
            for (col = 0; col < 5; ++col) {
                if (!(bits & (2 << col))) continue;
                for (a = 0; a < 3; ++a)
                    for (b = 0; b < 3; ++b) {
                        gfx_x = x+col*3+a; gfx_y = 27+row*3+b;
                        video_pixel(1);
                    }
            }
        }
        x += 20; ++s;
    }
}

static void title_screen(void)
{
    uint8_t type,i,offset;
    video_clear();
    state = TITLE;
    text(5,9,0x70,"A P P L E   / / /   A R C A D E");
    big_title();
    text(8,59,0xF0,"MAKE ROOM FOR ONE MORE.");
    for (type = 0; type < 7; ++type)
        for (i = 0; i < 4; ++i) {
            offset = shapes[type][0][i];
            cell(3+type*5+(offset&3),80+(offset>>2)*8,colors[type+1],tile);
        }
    text(9,111,0xD0,"PRESS SPACE TO START");
    text(5,133,0xF0,"ARROWS MOVE  UP/X ROTATE  Z BACK");
    text(6,145,0xF0,"DOWN SOFT DROP   SPACE DROP");
    text(7,157,0x70,"C HOLD  P PAUSE  M SOUND");
    text(3,172,0x70,"SEVEN SHAPES. ENDLESS POSSIBILITIES.");
    text(5,184,0x70,"APPLE KEYS MOVE - CTRL SOFTDROP");
}

static void inputs(void)
{
    uint8_t shift;
    key = 0; modifiers = MODIFIERS;
    if (KEYBOARD & 128) {
        key = KEYBOARD & 127;
        KEY_STROBE = 0;
        if (key >= 'a' && key <= 'z') key -= 32;
    }
    shift = (modifiers & 2) != 0;
    /* Mapped Space also reaches the keyboard encoder. Its character can arrive
     * on the Shift release tick; do not interpret that as a second drop. */
    hard_pressed = (shift && !shift_was_down) || (key == ' ' && !shift && !shift_was_down);
    shift_was_down = shift;
    if (action_timer) --action_timer;
    if (key == 'M' && !action_timer) { muted ^= 1; action_timer = 12; }
}

static void play_frame(void)
{
    int8_t movement;
    uint8_t soft,interval,distance;
    erase_falling();
    movement = 0;
    if (!(modifiers & 0x10)) --movement;
    if (!(modifiers & 0x20)) ++movement;
    if (movement) {
        if (movement != move_direction) { move_piece(movement); move_timer = 12; }
        else if (move_timer) --move_timer;
        else { move_piece(movement); move_timer = 4; }
    } else {
        if (key == 'A' || key == 8) move_piece(-1);
        if (key == 'D' || key == 21) move_piece(1);
    }
    move_direction = movement;
    if (!action_timer) {
        if (key == 'X' || key == 24 || key == 11) { rotate_piece(1); action_timer = 6; }
        if (key == 'Z' || key == 26) { rotate_piece(-1); action_timer = 6; }
        if (key == 'C' || key == 3) { hold_piece(); action_timer = 6; }
    }
    if (state != PLAYING) return;
    if (hard_pressed) {
        find_ghost();
        distance = ghost_y-piece_y;
        piece_y = ghost_y;
        award((uint32_t)distance*2);
        lock_piece();
    } else {
        if (key == 'S' || key == 19 || key == 10) soft_hold = 5;
        if (soft_hold) --soft_hold;
        soft = !(modifiers & 4) || soft_hold;
        interval = soft ? 2 : gravity[level-1];
        if (++fall_timer >= interval) {
            fall_timer = 0;
            if (fits(piece_x,piece_y+1,rotation)) {
                ++piece_y;
                lock_timer = 0;
                if (soft) award(1);
            }
        }
        if (!fits(piece_x,piece_y+1,rotation)) {
            if (++lock_timer >= LOCK_DELAY) lock_piece();
        } else lock_timer = 0;
    }
    if (state == PLAYING) draw_falling();
    if (hud_dirty) hud();
}

void main(void)
{
    video_init();
    title_screen();
    for (;;) {
        wait_frame();
        ++frame_counter;
        inputs();
        if (state == TITLE) {
            if (key == ' ' || key == 13 || hard_pressed) new_game();
            continue;
        }
        if (key == 27) { title_screen(); continue; }
        if (key == 'P' && !action_timer && (state == PLAYING || state == PAUSED)) {
            action_timer = 12;
            state = state == PLAYING ? PAUSED : PLAYING;
            text(2,176,0xD0,state == PAUSED ? "PAUSED" : "      ");
        }
        if (state == PLAYING) play_frame();
        else if (state == CLEARING) clear_frame();
        else if (state == GAME_OVER) {
            if (transition_timer) --transition_timer;
            else if (key == ' ' || key == 13 || hard_pressed) new_game();
        }
    }
}
