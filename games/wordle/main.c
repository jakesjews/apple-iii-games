/* Word Five ///. Offline dictionary, repeatable puzzles, two-pass feedback. */
#include "ui.h"
#include "dictionary.h"
#include <string.h>

#define TITLE 0
#define PLAYING 1
#define WON 2
#define LOST 3
#define REVEAL 4

uint8_t state, attempt, length, key, key_status[26], grades[6][5];
uint8_t reveal_column, reveal_timer, selection_digits, action_timer;
char answer[6], entry[6], guesses[6][6];
uint16_t frame_counter, puzzle, selection, played, wins, streak, best_streak;
uint16_t dict_cursor;
/* Last validation result is exposed for emulator diagnostics. */
uint8_t valid_word;
static const uint8_t blank[8] = {0,0,0,0,0,0,0,0};
static const uint8_t grade_colors[4] = {2,5,13,4};
static const char keyboard[] = "QWERTYUIOPASDFGHJKLZXCVBNM";

static void message(const char *s, uint8_t color)
{
    ui_text(2,148,0,"                                     "); ui_text(3,148,color,s);
}

static void draw_letter(uint8_t row, uint8_t col, char letter, uint8_t result)
{
    uint8_t x,y,i,j,a,b,bits,bg;
    x = 8+col*5; y = 30+row*20; bg = grade_colors[result];
    gfx_color = (bg<<4)|bg;
    for (j = 0; j < 2; ++j) for (i = 0; i < 4; ++i) {
        gfx_x = x+i; gfx_y = y+j*8; video_tile(blank);
    }
    if (!letter) return;
    gfx_color = (result == 2 ? 0 : 0xF0)|bg;
    x = x*7+9; ++y;
    for (j = 0; j < 7; ++j) {
        bits = font_bitmap[letter&63][j];
        for (i = 0; i < 5; ++i) if (bits & (2<<i))
            for (a = 0; a < 2; ++a) for (b = 0; b < 2; ++b) {
                gfx_x = x+i*2+a; gfx_y = y+j*2+b; video_pixel(1);
            }
    }
}

static void draw_entry(void)
{
    uint8_t i;
    for (i = 0; i < 5; ++i) draw_letter(attempt,i,entry[i],0);
}

static void draw_keyboard(void)
{
    uint8_t i,x,y,result,bg;
    char s[2];
    s[1] = 0;
    for (i = 0; i < 26; ++i) {
        if (i < 10) { x = 10+i*2; y = 160; }
        else if (i < 19) { x = 11+(i-10)*2; y = 170; }
        else { x = 13+(i-19)*2; y = 180; }
        s[0] = keyboard[i]; result = key_status[s[0]-'A']; bg = grade_colors[result];
        ui_text(x,y,(result == 2 ? 0 : 0xF0)|bg,s);
    }
}

static uint32_t read_delta(void)
{
    uint8_t part,shift;
    uint32_t delta;
    delta = 0; shift = 0;
    do {
        part = dictionary[dict_cursor++]; delta |= (uint32_t)(part&127)<<shift; shift += 7;
    } while (part&128);
    return delta;
}

static void load_answer(void)
{
    uint16_t index,count;
    uint32_t value;
    uint8_t i;
    /* 73 and ANSWER_COUNT are coprime; IDs permute the curated answer pool. */
    index = ((puzzle-1)*73U)%ANSWER_COUNT;
    index = answer_codes[index];
    answer[0] = 'A'+(index>>11); dict_cursor = dict_offsets[index>>11];
    count = (index&2047)+1; value = 0;
    while (count--) value += read_delta();
    answer[5] = 0;
    for (i = 4; i; --i) { answer[i] = 'A'+value%26; value /= 26; }
}

static uint8_t in_dictionary(const char *word)
{
    uint8_t i;
    uint16_t end;
    uint32_t target,value;
    target = 0;
    for (i = 1; i < 5; ++i) target = target*26 + word[i]-'A';
    i = word[0]-'A'; dict_cursor = dict_offsets[i]; end = dict_offsets[i+1]; value = 0;
    while (dict_cursor < end) {
        value += read_delta();
        if (value == target) return 1;
        if (value > target) return 0;
    }
    return 0;
}

static void evaluate(void)
{
    uint8_t counts[26],i,letter;
    memset(counts,0,sizeof(counts));
    /* Reserve exact matches before allocating any yellow copies. */
    for (i = 0; i < 5; ++i) {
        grades[attempt][i] = 0;
        if (entry[i] == answer[i]) grades[attempt][i] = 2;
        else ++counts[answer[i]-'A'];
    }
    for (i = 0; i < 5; ++i) if (grades[attempt][i] != 2) {
        letter = entry[i]-'A';
        if (counts[letter]) { grades[attempt][i] = 1; --counts[letter]; }
    }
}

static void finish_guess(void)
{
    uint8_t i,correct,letter;
    char notice[36];
    correct = 0;
    for (i = 0; i < 5; ++i) {
        if (grades[attempt][i] == 2) ++correct;
        letter = guesses[attempt][i]-'A';
        if (grades[attempt][i]+1 > key_status[letter]) key_status[letter] = grades[attempt][i]+1;
    }
    draw_keyboard();
    ++attempt; length = 0; memset(entry,0,sizeof(entry));
    if (correct == 5) {
        state = WON; if (played < 999) ++played; if (wins < 999) ++wins;
        if (streak < 999) ++streak;
        if (streak > best_streak) best_streak = streak;
        message("SOLVED! ENTER FOR NEXT PUZZLE",0xC0); sound(SFX_BONUS);
    } else if (attempt == 6) {
        state = LOST; if (played < 999) ++played; streak = 0;
        strcpy(notice,"ANSWER: "); strcat(notice,answer); strcat(notice,"  ENTER FOR NEXT");
        message(notice,0xD0); sound(SFX_EXPLOSION);
    } else {
        state = PLAYING; message("TYPE A WORD, THEN ENTER",0x70);
        ui_number(32,15,attempt+1,1);
    }
}

static void new_game(void)
{
    uint8_t row,col;
    video_clear(); load_answer(); state = PLAYING; attempt = 0; length = 0;
    memset(entry,0,sizeof(entry)); memset(guesses,0,sizeof(guesses));
    memset(grades,0,sizeof(grades)); memset(key_status,0,sizeof(key_status));
    ui_text(2,3,0xC0,"WORD FIVE"); ui_text(22,3,0x70,"PUZZLE"); ui_number(30,3,puzzle,3);
    ui_text(2,15,0x70,"WINS"); ui_number(8,15,wins,3);
    ui_text(25,15,0x70,"TRY"); ui_number(32,15,1,1);
    for (row = 0; row < 6; ++row) for (col = 0; col < 5; ++col) draw_letter(row,col,0,0);
    draw_keyboard(); message("TYPE A WORD, THEN ENTER",0x70);
}

static void selection_display(void)
{
    ui_number(17,88,selection,3);
}

static void title_screen(void)
{
    video_clear(); state = TITLE; selection = puzzle; selection_digits = 0;
    ui_text(5,9,0x70,"A P P L E   / / /   A R C A D E");
    ui_title("WORD FIVE",50,32,0xC0);
    ui_text(7,65,0xF0,"FIVE LETTERS. SIX CHANCES.");
    ui_text(9,88,0x70,"PUZZLE"); selection_display();
    ui_text(22,88,0x70,"OF"); ui_number(26,88,ANSWER_COUNT,3);
    ui_text(5,109,0xF0,"TYPE A NUMBER, ENTER TO PLAY");
    ui_text(7,123,0xD0,"SPACE FOR A RANDOM PUZZLE");
    ui_text(3,144,0xC0,"GREEN: RIGHT"); ui_text(18,144,0xD0,"YELLOW: ELSEWHERE");
    ui_text(3,163,0x70,"PLAYED"); ui_number(10,163,played,3);
    ui_text(16,163,0x70,"WINS"); ui_number(21,163,wins,3);
    ui_text(27,163,0x70,"STREAK"); ui_number(34,163,streak,3);
    ui_text(4,184,0x70,"BACKSPACE EDIT  TAB SOUND  ESC EXIT");
}

static void play_frame(void)
{
    if (key >= 'A' && key <= 'Z' && length < 5) {
        entry[length++] = key; entry[length] = 0; draw_entry();
        message("TYPE A WORD, THEN ENTER",0x70);
    } else if ((key == 8 || key == 127) && length) {
        entry[--length] = 0; draw_entry(); message("TYPE A WORD, THEN ENTER",0x70);
    } else if (key == 13) {
        if (length != 5) { message("FIVE LETTERS NEEDED",0xD0); return; }
        valid_word = in_dictionary(entry);
        if (!valid_word) { message("NOT IN WORD LIST",0xB0); return; }
        memcpy(guesses[attempt],entry,6); evaluate();
        state = REVEAL; reveal_column = 0; reveal_timer = 4;
    }
}

void main(void)
{
    video_init(); puzzle = 1; title_screen();
    for (;;) {
        wait_frame(); ++frame_counter; key = ui_key();
        if (action_timer) --action_timer;
        if (key == 9 && !action_timer) {
            muted ^= 1; action_timer = 12;
            if (state != TITLE) message(muted ? "SOUND OFF" : "SOUND ON",0x70);
        }
        if (state == TITLE) {
            if (key >= '0' && key <= '9' && selection_digits < 3) {
                if (!selection_digits) selection = 0;
                selection = selection*10 + key-'0'; ++selection_digits; selection_display();
            } else if (key == 8 || key == 127) {
                selection /= 10; if (selection_digits) --selection_digits; selection_display();
            } else if (key == ' ') { puzzle = frame_counter%ANSWER_COUNT+1; new_game(); }
            else if (key == 13) {
                if (selection >= 1 && selection <= ANSWER_COUNT) { puzzle = selection; new_game(); }
                else ui_text(7,101,0xB0,"CHOOSE A NUMBER IN RANGE");
            }
            continue;
        }
        if (key == 27) { title_screen(); continue; }
        if (state == PLAYING) play_frame();
        else if (state == REVEAL) {
            if (reveal_timer) --reveal_timer;
            else {
                draw_letter(attempt,reveal_column,guesses[attempt][reveal_column],grades[attempt][reveal_column]+1);
                sound(SFX_STEP); reveal_timer = 4;
                if (++reveal_column == 5) finish_guess();
            }
        } else if (key == 13) {
            puzzle = puzzle%ANSWER_COUNT+1; new_game();
        } else if (key == ' ') { puzzle = frame_counter%ANSWER_COUNT+1; new_game(); }
    }
}
