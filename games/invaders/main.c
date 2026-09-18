/* Star Siege /// -- native Apple III arcade game. No SOS or Apple II mode.
 * The formation redraws only when it moves. XOR sprites preserve the terrain;
 * moving objects are erased before collision checks alter shield pixels. */
#include "apple3.h"
#include "assets.h"

#define TITLE 0
#define PLAYING 1
#define PAUSED 2
#define GAME_OVER 3
#define NEXT_WAVE 4
#define ALIEN_COUNT 32
#define SHIP_Y 172
#define SHIELD_Y 146
#define SHIELD_BOTTOM 161
#define NO_SHOT 255

extern const uint8_t font_bitmap[64][8];

uint8_t state, wave, lives, remaining, player_x;
uint16_t score, best, frame_counter;
uint8_t aliens[ALIEN_COUNT];
int16_t fleet_x;
uint8_t fleet_y, animation, fleet_timer, fleet_period;
int8_t direction;
uint8_t shot_x, shot_y, cooldown;
uint8_t bomb_x[3], bomb_y[3], bomb_timer;
uint8_t ufo_x, ufo_active, ufo_timer;
uint8_t burst_x, burst_y, burst_timer;
uint8_t invulnerable, ship_visible, transition_timer;
uint8_t control_lock, move_hold, move_key, key, modifiers;
uint8_t random_state = 0xA7;
uint8_t frame_phase, extra_life, hud_dirty;

static const uint8_t row_color[4] = {0xE0, 0xB0, 0xD0, 0xC0};
static const uint8_t row_sprite[4] = {SCOUT_A, CRAB_A, CRAB_A, BRUTE_A};
static const uint8_t row_score[4] = {30, 20, 20, 10};
static const uint8_t shield_x[4] = {28, 91, 154, 217};

static void text(uint8_t x, uint8_t y, uint8_t color, const char *s)
{
    gfx_x = x; gfx_y = y; gfx_color = color;
    video_text(s);
}

static void sprite(uint8_t id, uint8_t x, uint8_t y, uint8_t color)
{
    gfx_x = x; gfx_y = y; gfx_color = color;
    video_sprite(id);
}

static void pixel(uint8_t x, uint8_t y, uint8_t set)
{
    gfx_x = x; gfx_y = y;
    video_pixel(set);
}

static uint8_t random_byte(void)
{
    uint8_t bit;
    bit = random_state & 0x80;
    random_state <<= 1;
    if (bit) random_state ^= 0x1D;
    return random_state;
}

static void number(uint8_t x, uint8_t y, uint16_t value, uint8_t digits)
{
    char s[6];
    uint8_t i;
    s[digits] = 0;
    i = digits;
    do {
        s[--i] = '0' + value % 10;
        value /= 10;
    } while (i);
    text(x, y, 0xF0, s);
}

static void hud(void)
{
    number(2, 13, score, 5);
    number(15, 13, best, 5);
    number(33, 13, wave, 2);
    number(8, 184, lives, 1);
    hud_dirty = 0;
}

static void award(uint8_t points)
{
    /* Saturate instead of wrapping the scoreboard. */
    if (score > 65535U - points) score = 65535U;
    else score += points;
    if (score > best) best = score;
    if (!extra_life && score >= 1500) {
        extra_life = 1;
        if (lives < 9) ++lives;
        sound(SFX_BONUS);
    }
    hud_dirty = 1;
}

static void draw_alien(uint8_t index)
{
    uint8_t row;
    row = index >> 3;
    sprite(row_sprite[row] + animation,
           (uint8_t)(fleet_x + (index & 7) * 26),
           fleet_y + row * 18, row_color[row]);
}

static void draw_fleet(void)
{
    uint8_t i;
    for (i = 0; i < ALIEN_COUNT; ++i)
        if (aliens[i]) draw_alien(i);
}

static void shields(void)
{
    uint8_t s, x, y;
    gfx_color = 0xC0;
    for (s = 0; s < 4; ++s) {
        for (y = 0; y < 16; ++y) {
            for (x = 0; x < 28; ++x) {
                if (y < 4 && (x < 4 - y || x >= 24 + y)) continue;
                if (y >= 10 && x >= 9 && x < 19) continue;
                pixel(shield_x[s] + x, SHIELD_Y + y, 1);
            }
        }
    }
}

static uint8_t hit_shield(uint8_t x, uint8_t y)
{
    uint8_t dx, dy, px, py;
    if (y < SHIELD_Y || y > SHIELD_BOTTOM) return 0;
    gfx_x = x; gfx_y = y;
    if (!video_read_pixel()) return 0;
    gfx_color = 0xC0;
    for (dy = 0; dy < 5; ++dy) {
        py = y + dy - 2;
        if (py < SHIELD_Y || py > SHIELD_BOTTOM) continue;
        for (dx = 0; dx < 5; ++dx) {
            if ((dy == 0 || dy == 4) && (dx == 0 || dx == 4)) continue;
            px = x + dx - 2;
            pixel(px, py, 0);
        }
    }
    return 1;
}

static void reset_objects(void)
{
    uint8_t i;
    shot_y = NO_SHOT;
    for (i = 0; i < 3; ++i) bomb_y[i] = NO_SHOT;
    burst_timer = 0;
    ufo_active = 0;
    ufo_timer = 220;
    bomb_timer = 70;
    cooldown = 0;
    player_x = 126;
    invulnerable = 90;
    ship_visible = 0;
}

static void start_wave(void)
{
    uint8_t i, yoffset;
    video_clear();
    reset_objects();
    gfx_band_y = SHIELD_Y;
    gfx_band_color = 0xC0;
    text(2, 3, 0xE0, "SCORE");
    text(15, 3, 0xE0, "BEST");
    text(31, 3, 0xE0, "WAVE");
    text(2, 184, 0xC0, "LIVES");
    text(13, 184, 0x70, "P PAUSE  M SOUND  ESC EXIT");
    hud();
    shields();
    fleet_x = 32;
    yoffset = wave < 7 ? (wave - 1) * 2 : 12;
    fleet_y = 44 + yoffset;
    direction = 1;
    remaining = ALIEN_COUNT;
    animation = 0;
    fleet_timer = 28;
    for (i = 0; i < ALIEN_COUNT; ++i) aliens[i] = 1;
    draw_fleet();
    state = PLAYING;
}

static void new_game(void)
{
    score = 0;
    wave = 1;
    lives = 3;
    extra_life = 0;
    move_hold = 0;
    start_wave();
}

static void big_title(void)
{
    const char *s;
    uint8_t x, row, col, a, b, bits;
    s = "STAR SIEGE";
    x = 49;
    while (*s) {
        for (row = 0; row < 7; ++row) {
            bits = font_bitmap[*s & 63][row];
            for (col = 0; col < 5; ++col) {
                if (!(bits & (2 << col))) continue;
                gfx_color = row < 3 ? 0xE0 : 0x60;
                for (a = 0; a < 3; ++a)
                    for (b = 0; b < 3; ++b)
                        pixel(x + col * 3 + a, 27 + row * 3 + b, 1);
            }
        }
        x += 20;
        ++s;
    }
}

static void title_screen(void)
{
    uint8_t i, x, y;
    video_clear();
    state = TITLE;
    gfx_band_y = 192;
    gfx_color = 0x50;
    for (i = 0; i < 38; ++i) {
        x = random_byte();
        y = random_byte() % 174 + 8;
        pixel(x, y, 1);
    }
    text(5, 9, 0x70, "A P P L E   / / /   A R C A D E");
    big_title();
    text(8, 57, 0xF0, "THEY CAME FOR YOUR APPLE.");
    sprite(SCOUT_A, 67, 79, 0xE0);
    text(13, 79, 0xF0, "SCOUT   30");
    sprite(CRAB_A, 67, 93, 0xB0);
    text(13, 93, 0xF0, "RAIDER  20");
    sprite(BRUTE_A, 67, 107, 0xD0);
    text(13, 107, 0xF0, "BRUTE   10");
    sprite(UFO, 67, 121, 0x90);
    text(13, 121, 0xF0, "MYSTERY SHIP  100");
    text(9, 142, 0xD0, "PRESS SPACE TO DEFEND");
    text(6, 159, 0xF0, "ARROWS / A D MOVE   SPACE FIRE");
    text(5, 171, 0x70, "NATIVE: APPLE KEYS + SHIFT FIRE");
    text(8, 184, 0x60, "32 INVADERS. ONE APPLE III.");
}

static void moving_objects(void)
{
    uint8_t i;
    if (ship_visible) sprite(SHIP, player_x, SHIP_Y, 0xC0);
    if (shot_y != NO_SHOT) sprite(LASER, shot_x, shot_y, 0xF0);
    for (i = 0; i < 3; ++i)
        if (bomb_y[i] != NO_SHOT)
            sprite(BOMB_A + frame_phase, bomb_x[i], bomb_y[i], 0x90);
    if (ufo_active) sprite(UFO, ufo_x, 27, 0x90);
    if (burst_timer) sprite(BURST, burst_x, burst_y, 0xF0);
}

static void explode(uint8_t x, uint8_t y)
{
    burst_x = x; burst_y = y; burst_timer = 9;
}

static void game_over(void)
{
    state = GAME_OVER;
    transition_timer = 90;
    text(11, 120, 0xB0, "SECTOR OVERRUN");
    text(8, 133, 0xF0, "SPACE TO DEFEND AGAIN");
    sound(SFX_EXPLOSION);
}

static void hit_player(void)
{
    uint8_t i;
    if (invulnerable) return;
    --lives;
    hud_dirty = 1;
    explode(player_x, SHIP_Y);
    sound(SFX_EXPLOSION);
    for (i = 0; i < 3; ++i) bomb_y[i] = NO_SHOT;
    if (!lives) {
        ship_visible = 0;
        game_over();
    } else {
        invulnerable = 120;
        player_x = 126;
    }
}

static void move_fleet(void)
{
    uint8_t i, row, left, right, bottom;
    int16_t x;
    if (fleet_timer) { --fleet_timer; return; }
    fleet_period = 3 + remaining;
    i = wave < 12 ? wave : 11;
    if (fleet_period > i + 3) fleet_period -= i;
    else fleet_period = 3;
    fleet_timer = fleet_period;
    left = 255; right = 0; bottom = 0;
    for (i = 0; i < ALIEN_COUNT; ++i) {
        if (!aliens[i]) continue;
        x = fleet_x + (i & 7) * 26;
        if (x < left) left = (uint8_t)x;
        if (x > right) right = (uint8_t)x;
        row = i >> 3;
        if (row > bottom) bottom = row;
    }
    draw_fleet();
    if ((direction > 0 && right >= 244) || (direction < 0 && left <= 12)) {
        direction = -direction;
        fleet_y += 5;
    } else fleet_x += direction * 3;
    animation ^= 1;
    draw_fleet();
    sound(SFX_STEP);
    if (fleet_y + bottom * 18 + 8 >= SHIELD_Y) game_over();
}

static void fire_bomb(void)
{
    uint8_t slot, column, tries;
    int8_t i;
    if (bomb_timer) { --bomb_timer; return; }
    bomb_timer = wave < 12 ? 56 - wave * 3 : 20;
    for (slot = 0; slot < 3 && bomb_y[slot] != NO_SHOT; ++slot) {}
    if (slot == 3) return;
    column = random_byte() & 7;
    for (tries = 0; tries < 8; ++tries) {
        for (i = 3; i >= 0; --i) {
            if (aliens[(uint8_t)i * 8 + column]) {
                bomb_x[slot] = (uint8_t)(fleet_x + column * 26 + 5);
                bomb_y[slot] = fleet_y + (uint8_t)i * 18 + 8;
                return;
            }
        }
        column = (column + 1) & 7;
    }
}

static void update_shot(void)
{
    uint8_t step, i, x, y, row, column, dy;
    int16_t dx;
    if (shot_y == NO_SHOT) return;
    /* Test every crossed scanline so shots cannot tunnel through shields. */
    for (step = 0; step < 3; ++step) {
        if (shot_y <= 23) { shot_y = NO_SHOT; return; }
        --shot_y;
        if (hit_shield(shot_x, shot_y)) { shot_y = NO_SHOT; return; }
        if (ufo_active && shot_y >= 27 && shot_y < 35 &&
            shot_x >= ufo_x && shot_x < ufo_x + 14) {
            explode(ufo_x, 27);
            ufo_active = 0; ufo_timer = 240; shot_y = NO_SHOT;
            award(100); sound(SFX_HIT);
            return;
        }
        /* The formation is a grid: check one cell, not all 32 invaders on
         * every crossed scanline. This keeps movement responsive at 2 MHz. */
        if (shot_y < fleet_y || shot_y >= fleet_y + 62) continue;
        dy = shot_y - fleet_y;
        row = 0;
        while (dy >= 18) { dy -= 18; ++row; }
        if (dy >= 8) continue;
        dx = (int16_t)shot_x - fleet_x;
        if (dx < 0 || dx >= 196) continue;
        column = 0;
        while (dx >= 26) { dx -= 26; ++column; }
        if (dx >= 14) continue;
        i = row * 8 + column;
        if (aliens[i]) {
            x = (uint8_t)(fleet_x + column * 26);
            y = fleet_y + row * 18;
            draw_alien(i);
            aliens[i] = 0;
            --remaining;
            shot_y = NO_SHOT;
            explode(x, y);
            award(row_score[i >> 3]);
            sound(SFX_HIT);
            return;
        }
    }
}

static void update_bombs(void)
{
    uint8_t i, step;
    for (i = 0; i < 3; ++i) {
        if (bomb_y[i] == NO_SHOT) continue;
        for (step = 0; step < 2; ++step) {
            ++bomb_y[i];
            if (bomb_y[i] >= 177 || hit_shield(bomb_x[i] + 1, bomb_y[i] + 6)) {
                bomb_y[i] = NO_SHOT;
                break;
            }
            if (bomb_y[i] + 6 >= SHIP_Y && bomb_x[i] + 2 >= player_x &&
                bomb_x[i] < player_x + 13 && !invulnerable) {
                hit_player();
                break;
            }
            if (shot_y != NO_SHOT && bomb_y[i] + 6 >= shot_y &&
                bomb_y[i] <= shot_y + 4 && shot_x >= bomb_x[i] && shot_x <= bomb_x[i] + 2) {
                bomb_y[i] = NO_SHOT; shot_y = NO_SHOT;
                break;
            }
        }
    }
}

static void inputs(void)
{
    key = 0;
    modifiers = MODIFIERS;
    if (KEYBOARD & 0x80) {
        key = KEYBOARD & 0x7F;
        KEY_STROBE = 0;  /* A write always emits the acknowledge bus access. */
        if (key >= 'a' && key <= 'z') key -= 32;
    }
    if (control_lock) --control_lock;
    if (key == 'M' && !control_lock) {
        muted ^= 1; control_lock = 20;
    }
}

static void play_frame(void)
{
    uint8_t left, right, fire;
    moving_objects();
    if (invulnerable) --invulnerable;
    if (burst_timer) --burst_timer;
    if (cooldown) --cooldown;
    frame_phase = (frame_counter >> 2) & 1;
    left = !(modifiers & 0x10);
    right = !(modifiers & 0x20);
    fire = (modifiers & 2) || key == ' ';
    /* Unmodified hardware keys also work, using native keyboard repeat. */
    if (key == 'A' || key == 8) { move_key = 1; move_hold = 5; }
    if (key == 'D' || key == 21) { move_key = 2; move_hold = 5; }
    if (move_hold) {
        --move_hold;
        if (!left && !right) {
            left = move_key == 1; right = move_key == 2;
        }
    }
    if (left && !right && player_x > 9) player_x -= 2;
    if (right && !left && player_x < 247) player_x += 2;
    if (fire && !cooldown && shot_y == NO_SHOT) {
        shot_x = player_x + 6; shot_y = SHIP_Y - 5; cooldown = 14;
        sound(SFX_LASER);
    }
    update_shot();
    update_bombs();
    if (state == PLAYING) { move_fleet(); fire_bomb(); }
    if (ufo_active) {
        if ((frame_counter & 1) == 0) ++ufo_x;
        if (ufo_x >= 246) { ufo_active = 0; ufo_timer = 240; }
    } else if ((frame_counter & 3) == 0) {
        if (ufo_timer) --ufo_timer;
        else { ufo_x = 8; ufo_active = 1; }
    }
    ship_visible = lives && (!invulnerable || (invulnerable & 4));
    moving_objects();
    if (hud_dirty) hud();
    if (!remaining && state == PLAYING) {
        state = NEXT_WAVE; transition_timer = 90;
        text(10, 119, 0xE0, "SECTOR SECURED");
        text(8, 132, 0xF0, "REPAIRING THE SHIELDS");
        sound(SFX_BONUS);
    }
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
            if (key == ' ' || key == 13 || (modifiers & 2)) new_game();
            continue;
        }
        if (key == 27) { title_screen(); continue; }
        if (key == 'P' && !control_lock && (state == PLAYING || state == PAUSED)) {
            control_lock = 20;
            if (state == PLAYING) {
                state = PAUSED;
                text(23, 3, 0xD0, "PAUSED");
            } else {
                text(23, 3, 0xF0, "      ");
                state = PLAYING;
            }
        }
        if (state == PLAYING) play_frame();
        else if (state == NEXT_WAVE) {
            if (transition_timer) --transition_timer;
            else { if (wave < 99) ++wave; start_wave(); }
        } else if (state == GAME_OVER) {
            if (transition_timer) --transition_timer;
            else if (key == ' ' || key == 13 || (modifiers & 2)) new_game();
        }
    }
}
