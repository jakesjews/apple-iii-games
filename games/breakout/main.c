/* Brick Bash ///. Integer substeps prevent fast balls skipping thin bricks. */
#include "ui.h"
#include "assets.h"
#include <string.h>

#define TITLE 0
#define SERVE 1
#define PLAYING 2
#define PAUSED 3
#define GAME_OVER 4
#define NEXT_WAVE 5
#define NO_BRICK 255

uint8_t state, previous_state, bricks[60], remaining, lives, wave, paddle_x;
uint8_t ball_x, ball_y, x_phase, speed, drawn, transition_timer, action_timer;
uint8_t key, modifiers, shift_was_down, launch, hud_dirty;
int8_t dx,dy;
uint16_t frame_counter, hits;
uint32_t score,best;
static const uint8_t colors[6] = {0xE0,0xB0,0xD0,0x90,0xC0,0x70};
static const uint8_t brick_left[8] = {0x7E,0x7E,0x7E,0x7E,0x7E,0x7E,0x7E,0};
static const uint8_t brick_mid[8] = {0x7F,0x7F,0x7F,0x7F,0x7F,0x7F,0x7F,0};
static const uint8_t brick_right[8] = {0x3F,0x3F,0x3F,0x3F,0x3F,0x3F,0x3F,0};
static const uint8_t armor[8] = {0x7F,0x41,0x5D,0x55,0x5D,0x41,0x7F,0};
static const uint8_t blank[8] = {0,0,0,0,0,0,0,0};

static uint8_t row_color(uint8_t y)
{
    if (y >= 36 && y < 108) return colors[(y-36)/12];
    return 0xF0;
}

static void draw_brick(uint8_t index)
{
    uint8_t col;
    col = 4 + (index%10)*3;
    gfx_y = 36 + (index/10)*12; gfx_color = colors[index/10];
    gfx_x = col; video_tile(bricks[index] ? brick_left : blank);
    gfx_x = col+1; video_tile(bricks[index] > 1 ? armor : (bricks[index] ? brick_mid : blank));
    gfx_x = col+2; video_tile(bricks[index] ? brick_right : blank);
}

static void paddle(void)
{
    gfx_y = 170; gfx_color = 0xF0;
    gfx_x = paddle_x; video_sprite(PADDLE);
    gfx_x = paddle_x+14; video_sprite(PADDLE);
}

static void ball(uint8_t set)
{
    uint8_t x,y;
    for (y = 0; y < 4; ++y) {
        gfx_color = row_color(ball_y+y);
        for (x = 0; x < 4; ++x) {
            gfx_x = ball_x+x; gfx_y = ball_y+y; video_pixel(set);
        }
    }
}

static void erase_objects(void)
{
    if (!drawn) return;
    ball(0); paddle(); drawn = 0;
}

static void draw_objects(void)
{
    paddle(); ball(1); drawn = 1;
}

static void hud(void)
{
    ui_number(2,15,score,6); ui_number(16,15,best,6);
    ui_number(30,15,wave,2); ui_number(37,15,lives,1);
    hud_dirty = 0;
}

static void ready(void)
{
    state = SERVE; ball_x = paddle_x+12; ball_y = 164;
    dx = 1; dy = -1; x_phase = 0;
    ui_text(7,135,0xD0,"SPACE OR BUTTON TO LAUNCH");
}

static void start_wave(void)
{
    uint8_t i,y;
    video_clear(); drawn = 0; remaining = 60; paddle_x = 119;
    speed = wave < 7 ? 2+(wave-1)/2 : 5;
    for (i = 0; i < 60; ++i) { bricks[i] = wave > 1 && i < 10 ? 2 : 1; draw_brick(i); }
    ui_text(2,3,0x70,"SCORE"); ui_text(16,3,0x70,"BEST");
    ui_text(28,3,0x70,"STAGE"); ui_text(35,3,0x70,"LIVES");
    ui_text(3,184,0x70,"ARROWS MOVE  P PAUSE  M SOUND");
    for (y = 27; y < 181; ++y) {
        gfx_y = y; gfx_color = row_color(y);
        gfx_x = 12; video_pixel(1); gfx_x = 253; video_pixel(1);
    }
    hud(); ready(); draw_objects();
}

static void new_game(void)
{
    score = 0; hits = 0; wave = 1; lives = 3; start_wave();
}

static void title_screen(void)
{
    uint8_t i;
    video_clear(); drawn = 0; state = TITLE;
    ui_text(5,9,0x70,"A P P L E   / / /   A R C A D E");
    ui_title("BRICK BASH",40,30,0x90);
    ui_text(8,64,0xF0,"ONE BALL. SIXTY BRICKS.");
    for (i = 40; i < 60; ++i) { bricks[i] = 1; draw_brick(i); }
    ui_text(5,115,0xD0,"PRESS SPACE OR BUTTON TO START");
    ui_text(6,139,0xF0,"LEFT/RIGHT OR A/D MOVE PADDLE");
    ui_text(6,153,0xF0,"SPACE LAUNCH  P PAUSE  M SOUND");
    ui_text(3,174,0x70,"STICK MOVE  BUTTON SERVE  B2 PAUSE");
}

static uint8_t brick_at(uint8_t x, uint8_t y)
{
    uint8_t col,row,index;
    if (x < 28 || x >= 238 || y < 36 || y >= 108) return NO_BRICK;
    col = x-28; row = y-36;
    if (!(col%21) || col%21 >= 20 || row%12 >= 7) return NO_BRICK;
    index = (row/12)*10 + col/21;
    return bricks[index] ? index : NO_BRICK;
}

static uint8_t contact(uint8_t x, uint8_t y)
{
    uint8_t index;
    index = brick_at(x,y); if (index != NO_BRICK) return index;
    index = brick_at(x+3,y); if (index != NO_BRICK) return index;
    index = brick_at(x,y+3); if (index != NO_BRICK) return index;
    return brick_at(x+3,y+3);
}

static void hit_brick(uint8_t index)
{
    --bricks[index]; ++hits;
    if (!bricks[index]) {
        --remaining;
        score += (uint32_t)(6-index/10)*10;
        if (score > 999999UL) score = 999999UL;
        if (score > best) best = score;
        hud_dirty = 1;
    }
    draw_brick(index); sound(SFX_HIT);
    if (!remaining) {
        state = NEXT_WAVE; transition_timer = 90;
        ui_text(12,127,0xD0,"WALL COMPLETE!"); sound(SFX_BONUS);
    }
}

static void lose_ball(void)
{
    --lives; hud_dirty = 1; sound(SFX_EXPLOSION);
    if (lives) ready();
    else {
        state = GAME_OVER; transition_timer = 45;
        ui_text(15,125,0xB0,"GAME OVER");
        ui_text(10,141,0xD0,"SPACE TO PLAY AGAIN");
    }
}

static void step_ball(void)
{
    uint8_t nx,ny,index,amount;
    int8_t impact;
    nx = ball_x; amount = dx < 0 ? -dx : dx;
    x_phase += amount;
    if (x_phase >= 3) {
        x_phase -= 3;
        if ((ball_x == 14 && dx < 0) || (ball_x == 248 && dx > 0)) dx = -dx;
        nx = ball_x + (dx < 0 ? -1 : 1);
    }
    if (nx != ball_x) {
        index = contact(nx,ball_y);
        if (index != NO_BRICK) { hit_brick(index); dx = -dx; }
        else ball_x = nx;
    }
    if (state != PLAYING) return;
    if (ball_y == 28 && dy < 0) dy = 1;
    ny = ball_y+dy;
    if (dy > 0 && ny+3 >= 170 && ball_y+3 < 170
        && ball_x+3 >= paddle_x && ball_x < paddle_x+28) {
        impact = ball_x+2-paddle_x;
        dx = impact < 6 ? -3 : impact < 12 ? -1 : impact < 18 ? 1 : 3;
        dy = -1; x_phase = 0; sound(SFX_STEP); return;
    }
    index = contact(ball_x,ny);
    if (index != NO_BRICK) { hit_brick(index); dy = -dy; }
    else ball_y = ny;
    if (ball_y >= 181) lose_ball();
}

static void play_frame(void)
{
    uint8_t i;
    int8_t movement;
    erase_objects();
    movement = 0;
    if (!(modifiers & 0x10) || (joy & JOY_LEFT)) movement -= 4;
    if (!(modifiers & 0x20) || (joy & JOY_RIGHT)) movement += 4;
    if (!movement) {
        if (key == 'A' || key == 8) movement = -4;
        if (key == 'D' || key == 21) movement = 4;
    }
    if (movement < 0) paddle_x = paddle_x < 18 ? 14 : paddle_x-4;
    if (movement > 0) paddle_x = paddle_x > 220 ? 224 : paddle_x+4;
    if (state == SERVE) {
        ball_x = paddle_x+12;
        if (launch || key == 13) {
            state = PLAYING; ui_text(7,135,0,"                        "); sound(SFX_LASER);
        }
    } else for (i = 0; i < speed && state == PLAYING; ++i) step_ball();
    if (hud_dirty) hud();
    if (state == PLAYING || state == SERVE) draw_objects();
}

void main(void)
{
    uint8_t shift;
    video_init(); joystick_init(); title_screen();
    for (;;) {
        wait_frame(); ++frame_counter;
        joystick_poll();
        key = ui_key(); modifiers = MODIFIERS; shift = (modifiers & 2) != 0;
        launch = (shift && !shift_was_down) || (key == ' ' && !shift && !shift_was_down);
        launch |= (joy_pressed & JOY_BUTTON) != 0;
        shift_was_down = shift;
        if (action_timer) --action_timer;
        if (key == 'M' && !action_timer) { muted ^= 1; action_timer = 12; }
        if (state == TITLE) { if (launch || key == 13) new_game(); continue; }
        if (key == 27) { title_screen(); continue; }
        if (((key == 'P' && !action_timer) || joy_switch_changed) && (state == SERVE || state == PLAYING || state == PAUSED)) {
            action_timer = 12;
            if (state == PAUSED) { state = previous_state; ui_text(15,151,0,"      "); }
            else { previous_state = state; state = PAUSED; ui_text(15,151,0xD0,"PAUSED"); }
        }
        if (state == SERVE || state == PLAYING) play_frame();
        else if (state == NEXT_WAVE) {
            if (transition_timer) --transition_timer;
            else { if (wave < 99) ++wave; start_wave(); }
        } else if (state == GAME_OVER) {
            if (transition_timer) --transition_timer;
            else if (launch || key == 13) new_game();
        }
    }
}
