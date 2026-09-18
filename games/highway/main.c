/* Highway ///: deterministic 50 Hz driving, independent of drawing speed. */
#include "engine.h"
#include "perspective.h"
#include <string.h>

#define TITLE 0
#define READY 1
#define RACING 2
#define PAUSED 3
#define TIME_UP 4
#define FINISHED 5
#define OBJECTS 9

uint8_t hill, tunnel, state, stage, speed, crash_timer, key, modifiers, throttle, brake;
uint8_t steer_left, steer_right, countdown, passed, previous_state;
uint8_t curve, tick_divider, action_timer, redraw_scene, voice_pending;
int16_t player;
uint16_t frame_counter, stage_distance, time_left, score, best;
uint16_t traffic_depth[4], simulation_ticks, last_clock, accumulator;
uint8_t traffic_lane[4], traffic_color[4], car_hit[4];
static uint8_t old_x[2*OBJECTS],old_y[2*OBJECTS],old_w[2*OBJECTS],old_h[2*OBJECTS];
static uint8_t draw_depth[3], draw_used[3];
static uint8_t old_id[2*OBJECTS], old_visible[2*OBJECTS], old_rank[2*OBJECTS];
static uint8_t new_x[OBJECTS],new_y[OBJECTS],new_w[OBJECTS],new_h[OBJECTS],new_id[OBJECTS],new_visible[OBJECTS],order[OBJECTS],slot,changed[OBJECTS];
static uint8_t drawn_count, buffer_index, pose_was, hill_was, scene_dark;
static uint8_t hud_state[2], hud_speed[2], hud_seconds[2], hud_message[2];
static uint16_t hud_score[2];
static uint8_t hud_digits[2][10],hud_time_color[2];
static const uint8_t radii[16]={1,1,1,1,2,2,3,4,5,6,7,9,10,12,14,16};
static const int8_t lane_centers[3]={-36,0,36};
static const uint8_t stage_bends[3]={0,7,14};
static const uint8_t scenery_kind[3]={64,80,96};
static const uint16_t decimal_places[5]={10000,1000,100,10,1};
uint16_t road_cost, object_cost, hud_cost, render_start;
static uint16_t rng;
static char digits[6];
static const char *const names[3] = {"SUNSET COAST", "AMBER CANYON", "MIDNIGHT CITY"};
static const int8_t bends[32] = {0,0,1,2,3,4,4,3,2,1,0,-1,-2,-3,-4,-4,-3,-2,-1,0,0,1,2,2,1,0,-1,-2,-1,0,0,0};

static void label(uint8_t x,uint8_t y,uint8_t color,const char *s)
{
    gfx_x=x; gfx_y=y; gfx_color=color; text(s);
}
static void number(uint8_t x,uint8_t y,uint16_t n,uint8_t length,uint8_t color)
{
    uint8_t i;
    digits[length]=0;
    for(i=length;i;i--) { digits[i-1]='0'+n%10; n/=10; }
    label(x,y,color,digits);
}
/* Subtraction avoids cc65's general 16-bit divide/modulo helpers. Only
   changed digits touch the hidden page; a warning-color change invalidates
   both time digits even when the rounded seconds have not changed. */
static void hud_number(uint8_t column,uint16_t value,uint8_t length,uint8_t offset,uint8_t color)
{
    uint8_t i,digit;
    uint16_t place;
    for(i=5-length;i<5;++i) {
        place=decimal_places[i]; digit=0;
        while(value>=place) { value-=place; ++digit; }
        if(hud_digits[buffer_index][offset]!=digit) {
            hud_digits[buffer_index][offset]=digit;
            gfx_x=column; gfx_color=color; digit_draw(digit);
        }
        ++column; ++offset;
    }
}
static uint8_t random_byte(void)
{
    rng ^= rng<<7; rng ^= rng>>9; rng ^= rng<<8;
    return (uint8_t)rng;
}
static void add_score(uint16_t amount)
{
    if(score > 60000U-amount) score=60000U; else score+=amount;
    if(score>best) best=score;
}
static void backgrounds(void)
{
    uint8_t p;
    HW(0xFFDF)=0x56; scene_dark=1;
    for(p=0;p<2;p++) {
        page=p?64:0; scene_init();
        label(1,0,0x70,"KM/H      TIME      SCORE");
        label(1,184,0x70,"CTRL/DOWN BRAKE . P/B2 PAUSE . M SOUND");
        if(state==TITLE) {
            label(5,27,0xF6,"H I G H W A Y   / / /");
            label(7,40,0xE3,"T H E   G R A N D   T O U R");
            label(7,53,0xF8,"COAST . CANYON . MIDNIGHT");
        }
    }
    memset(old_visible,0,sizeof(old_visible));
    pose_was=255; hill_was=255; page=64;
    hud_state[0]=hud_state[1]=255;
    hud_message[0]=hud_message[1]=255;
    hud_speed[0]=hud_speed[1]=255;
    hud_seconds[0]=hud_seconds[1]=255;
    hud_score[0]=hud_score[1]=65535U;
    memset(hud_digits,255,sizeof(hud_digits));
    hud_time_color[0]=hud_time_color[1]=255;
    redraw_scene=0;
}
static void title(void)
{
    hill=4; tunnel=0; state=TITLE; scene=0; stage=0; player=0; speed=100; curve=4;
    stage_distance=0; engine_on=0; redraw_scene=1;
}
static void start_game(void)
{
    uint8_t i;
    hill=4; tunnel=0; state=READY; stage=0; scene=0; player=0; speed=0; curve=4;
    score=0; passed=0; stage_distance=0;
    time_left=45*50; countdown=150; crash_timer=0;
    tick_divider=0; simulation_ticks=0; engine_on=0;
    for(i=0;i<4;i++) {
        traffic_depth[i]=i*3500; traffic_lane[i]=i%3;
        traffic_color[i]=1+i%3; car_hit[i]=0;
    }
    redraw_scene=1; voice_pending=1;
}
static void controls(void)
{
    joystick_poll(); key=0;
    if(KEYBOARD&128) { key=KEYBOARD&127; KEY_STROBE=0; }
    if(key>='a'&&key<='z') key-=32;
    modifiers=MODIFIERS;
    throttle=(modifiers&2)||(joy&JOY_BUTTON);
    brake=!(modifiers&4)||(joy&JOY_DOWN);
    steer_left=!(modifiers&16)||(joy&JOY_LEFT);
    steer_right=!(modifiers&32)||(joy&JOY_RIGHT);
    /* Ordinary native letter keys remain useful through keyboard repeat. */
    if(key=='A'||key==8) steer_left=1;
    if(key=='D'||key==21) steer_right=1;
    if(key==' '||key=='W'||key==11) throttle=1;
    if(key=='S'||key==10) brake=1;
    if(key=='M'&&!action_timer) { muted^=1; action_timer=10; }
    if(key==27) { title(); return; }
    if(state==TITLE||state==TIME_UP||state==FINISHED) {
        if((key==' '||key==13||(joy_pressed&JOY_BUTTON))&&!action_timer) {
            start_game(); action_timer=15;
        }
        return;
    }
    if((key=='P'&&!action_timer)||joy_switch_changed) {
        action_timer=10;
        if(state==PAUSED) state=previous_state;
        else if(state==RACING||state==READY) { previous_state=state; state=PAUSED; }
    }
}
static void physics(void)
{
    uint8_t i,was_tunnel;
    int16_t delta, target;
    if(action_timer) --action_timer;
    if(state==TITLE) {
        stage_distance+=12; road_phase=(uint8_t)(stage_distance>>5);
        curve=4+bends[(stage_distance>>10)&31]; return;
    }
    if(state==PAUSED||state==TIME_UP||state==FINISHED) return;
    ++simulation_ticks; ++tick_divider;
    if(state==READY) {
        if(countdown) --countdown; else state=RACING;
        return;
    }
    if(!time_left) { state=TIME_UP; engine_on=0; return; }
    --time_left;
    if(crash_timer) --crash_timer;
    if(throttle && !brake && !crash_timer) { if(speed<200) ++speed; }
    else if(brake) speed=speed>4?speed-4:0;
    else if(!(tick_divider&3) && speed) --speed;
    if(speed) {
        if(steer_left) player-=2;
        if(steer_right) player+=2;
        if(!(tick_divider&3)&&speed>80) player+=(int8_t)curve-4;
    }
    if(player<-80) player=-80;
    if(player>80) player=80;
    if((player<-58||player>58)&&speed>65) speed-=3;
    if(speed>0) stage_distance+=speed>>3;
    road_phase=(uint8_t)(stage_distance>>5);
    curve=4+bends[((stage_distance>>10)+stage_bends[stage])&31];
    hill=4+bends[((stage_distance>>11)+8)&31];
    was_tunnel=tunnel;
    tunnel=stage==0&&stage_distance>=14000&&stage_distance<19000;
    if(tunnel!=was_tunnel) { scene=tunnel?3:stage; redraw_scene=1; }
    for(i=0;i<3;i++) {
        delta=(int16_t)speed-65;
        if(delta<0 && traffic_depth[i]<(uint16_t)-delta) traffic_depth[i]=0;
        else traffic_depth[i]+=delta;
        if(traffic_depth[i]>=14000 && !car_hit[i]) {
            target=lane_centers[traffic_lane[i]];
            delta=player-target;
            if(delta>-16&&delta<16&&!crash_timer) {
                speed=25; crash_timer=65; car_hit[i]=1;
                time_left=time_left>100?time_left-100:0;
                player+=delta<0?-8:8;
            }
        }
        if(traffic_depth[i]>=16384) {
            if(!car_hit[i]) { add_score(100); if(passed<255) ++passed; }
            traffic_depth[i]=random_byte()*4;
            traffic_lane[i]=random_byte()%3;
            traffic_color[i]=1+random_byte()%3; car_hit[i]=0;
        }
    }
    if(stage_distance>=25000) {
        add_score(1000); stage_distance-=25000;
        if(stage==2) { add_score(time_left/5); state=FINISHED; engine_on=0; }
        else {
            ++stage; scene=stage;
            time_left+=35*50; if(time_left>99*50) time_left=99*50;
            redraw_scene=1;
        }
    }
}
static void paint_object(uint8_t id,int16_t x,uint8_t y)
{
    uint8_t w,h;
    w=asset_w[id]; h=asset_h[id];
    if(x<0||x+w>40||y<64||y+h>176||drawn_count>=OBJECTS) return;
    new_id[slot]=id; new_x[slot]=(uint8_t)x; new_y[slot]=y;
    new_w[slot]=w; new_h[slot]=h; new_visible[slot]=1;
    order[drawn_count++]=slot;
}
static void project(uint8_t kind,uint8_t scale,uint8_t lane)
{
    uint8_t bottom,band,height;
    int8_t x;
    uint8_t radius,id;
    bottom=hill_bottoms[hill][scale]; band=(bottom-64)/2;
    radius=radii[scale]; x=geom[336+band];
    if(lane==0) x-=radius/2;
    else if(lane==2) x+=radius/2;
    else if(lane==3) x-=radius+3;
    else if(lane==4) x+=radius+3;
    id=kind+scale;
    x-=asset_w[id]>>1;
    height=asset_h[id];
    paint_object(id,x,bottom-height);
}
static void objects(void)
{
    uint8_t i,j,k,min,depth;
    /* Roadside objects are outside the traffic lanes. Paint them first, then
       sort only the three cars that can actually overlap one another. */
    for(i=0;i<4;i++) {
        slot=i+3;
        depth=((uint8_t)(stage_distance>>10)+(i<<2))&15;
        project(i<2?(tunnel?96:scenery_kind[stage]):112,depth,3+(i&1));
    }
    for(i=0;i<3;i++) {
        draw_depth[i]=state==TITLE?(uint8_t)((i*5+(stage_distance>>9))&15):(uint8_t)(traffic_depth[i]>>10);
        draw_used[i]=0;
    }
    for(j=0;j<3;j++) {
        min=255; k=0;
        for(i=0;i<3;i++) if(!draw_used[i]&&draw_depth[i]<min) { min=draw_depth[i]; k=i; }
        draw_used[k]=1; slot=k;
        project(state==TITLE?16+(k<<4):traffic_color[k]*16,draw_depth[k],state==TITLE?k:traffic_lane[k]);
    }
    if((state==RACING&&stage_distance>=23000)||state==FINISHED) {
        slot=8; depth=state==FINISHED?3:stage_distance<23500?0:stage_distance<24000?1:stage_distance<24500?2:3;
        if(depth>3) depth=3;
        paint_object(128+depth,depth==0?16:depth==1?13:depth==2?9:5,70+depth*20);
    }
    /* A full-size car remains anchored at the bottom of the viewport. */
    slot=7;
    if(!crash_timer||(tick_divider&4)) paint_object(15,17+(steer_right?1:0)-(steer_left?1:0),140);
}
static void hud(void)
{
    uint8_t seconds,message,b;
    b=buffer_index; seconds=(time_left+49)/50;
    if(state!=TITLE) {
        if(hud_speed[b]!=speed) { hud_number(6,speed,3,0,0xF0); hud_speed[b]=speed; }
        if(hud_time_color[b]!=(time_left<500)) {
            hud_time_color[b]=time_left<500; hud_seconds[b]=255;
            hud_digits[b][3]=hud_digits[b][4]=255;
        }
        if(hud_seconds[b]!=seconds) { hud_number(16,seconds,2,3,time_left<500?0x90:0xD0); hud_seconds[b]=seconds; }
        if(hud_score[b]!=score) { hud_number(26,score,5,5,0xF0); hud_score[b]=score; }
    }
    message=state==RACING?(crash_timer?10:12+stage):state;
    if(state==READY) message=20+countdown/50;
    if(muted) message+=32;
    if(hud_message[b]!=message) {
        hud_message[b]=message;
        label(1,12,0xB0,"                                      ");
        if(state==TITLE) { label(8,12,0xD0,"BEST"); number(14,12,best,5,0xF0); }
        else if(state==READY) { label(14,12,0xD0,"GET READY"); number(25,12,countdown/50+1,1,0xF0); }
        else if(state==PAUSED) label(9,12,0xD0,"PAUSED - P / BUTTON 2");
        else if(state==TIME_UP) label(7,12,0x90,"TIME UP - RETURN TO RETRY");
        else if(state==FINISHED) label(4,12,0xC0,"TOUR COMPLETE! RETURN TO RETRY");
        else if(crash_timer) label(12,12,0x90,"CONTACT!  -2 SEC");
        else label(1,12,0xB0,tunnel?(const char *)"LIGHTHOUSE TUNNEL":names[stage]);
        if(muted) label(35,12,0x70,"MUTE");
    }
    if(hud_state[b]!=state) {
        hud_state[b]=state;
        if(state==TITLE) {
            label(1,0,0x70,"APPLE ///  256K  NATIVE RGB + DAC       ");
            label(2,176,0xF0,"SPACE / RETURN / BUTTON TO START     ");
        } else if(state==FINISHED) label(5,176,0xD0,"THREE STAGES. ONE GRAND TOUR.       ");
        else label(1,176,0x70,"APPLE/STICK STEER . SHIFT/B1 GAS        ");
    }
}
static void render(void)
{
    uint8_t i,j;
    int16_t camera;
    if(redraw_scene) backgrounds();
    buffer_index=page?1:0;
    camera=player/16; if(camera<-4) camera=-4; if(camera>4) camera=4;
    road_pose=curve*9+camera+4;
    if(road_pose!=pose_was||hill!=hill_was) { road_load(); pose_was=road_pose; hill_was=hill; }
    drawn_count=0; memset(new_visible,0,sizeof(new_visible));
    render_start=clock_read(); objects(); object_cost=clock_read()-render_start;
    road_prepare();
    for(i=0,j=buffer_index?OBJECTS:0;i<OBJECTS;i++,j++) {
        changed[i]=!old_visible[j]||old_id[j]!=new_id[i]||old_x[j]!=new_x[i]||old_y[j]!=new_y[i];
        if(old_visible[j]&&(!new_visible[i]||changed[i])) {
            object_x=old_x[j]; object_y=old_y[j];
            object_w=old_w[j]; object_h=old_h[j]; object_erase();
        }
        old_visible[j]=new_visible[i];
    }
    render_start=clock_read(); road_draw(); road_cost=clock_read()-render_start;
    render_start=clock_read();
    for(i=0;i<drawn_count;i++) {
        slot=order[i]; j=(buffer_index?OBJECTS:0)+slot;
        object_id=new_id[slot]; object_x=new_x[slot]; object_y=new_y[slot];
        object_w=new_w[slot]; object_h=new_h[slot]; object_slot=j;
        object_full=changed[slot]||old_rank[j]!=i;
        if(object_damaged()) { object_draw(); object_damage(); }
        old_rank[j]=i;
        old_id[j]=object_id; old_x[j]=object_x; old_y[j]=object_y;
        old_w[j]=object_w; old_h[j]=object_h;
    }
    object_cost+=clock_read()-render_start;
    render_start=clock_read(); hud(); hud_cost=clock_read()-render_start; present();
    if(scene_dark) { HW(0xFFDF)=0x76; scene_dark=0; }
    ++frame_counter;
}
void main(void)
{
    uint16_t now,elapsed;
    uint8_t steps,loading;
    rng=0xB37D; engine_init(); joystick_init(); title();
    last_clock=clock_read();
    for(;;) {
        controls(); now=clock_read(); elapsed=now-last_clock; last_clock=now;
        /* Transition loading and the spoken countdown do not consume race time. */
        if(elapsed>400) elapsed=400;
        accumulator+=elapsed; steps=0;
        while(accumulator>=40&&steps<10) { accumulator-=40; physics(); ++steps; }
        engine_on=state==RACING; engine_pitch=8+speed/4;
        if(crash_timer) engine_pitch=90+(tick_divider&31);
        loading=redraw_scene; render();
        if(loading) { last_clock=clock_read(); accumulator=0; }
        if(voice_pending) { voice_pending=0; say_ready(); last_clock=clock_read(); accumulator=0; }
    }
}
