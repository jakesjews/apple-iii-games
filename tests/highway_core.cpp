#include "Vcore_tb.h"
#include "verilated.h"
#include "symbols.h"
#include <cstdio>
#include <cstdlib>
#include <set>

int main(int argc,char**argv) {
    Verilated::commandArgs(argc,argv);
    Vcore_tb c;
    c.reset=1; c.serial_rx=c.serial_cts_n=c.serial_dsr_n=1;
    c.image_readonly=1; c.joy_a_x=c.joy_a_y=c.joy_b_x=c.joy_b_y=128;
    auto tick=[&](){ c.clk=0;c.eval();c.clk=1;c.eval(); };
    auto byte=[&](unsigned address)->unsigned {
        unsigned p=0x38000+(address<0x2000?address:address-0x8000);
        c.probe_addr=((p>>12)<<11)|((((p>>10)^(p>>11))&1)<<10)|(p&1023);
        c.eval();return(c.probe_word>>(((p>>11)&1)*8))&255;
    };
    auto word=[&](unsigned a){return byte(a)|(byte(a+1)<<8);};
    unsigned checks=0,failures=0;
    auto check=[&](bool ok,const char*msg){++checks; if(!ok)++failures;std::printf("%s %s\n",ok?"PASS":"FAIL",msg);std::fflush(stdout);};
    for(unsigned i=0;i<128;i++)tick();c.reset=0;
    constexpr unsigned hz=14318180;
    unsigned started=0,start_frames=0,frames_race=0,paused_time=0;
    unsigned visible_writes=0,banked_cycles=0,pages=0,peak_speed=0;
    bool rendering=false;
    bool ready=false,clock_checked=false,pause_checked=false,resume_checked=false,race_rate=false;
    std::set<unsigned> sound;
    for(unsigned cycles=0;cycles<hz*24;cycles++) {
        tick();
        if(rendering&&c.ram_write&&c.ram_byte_addr<0x8000) {
            unsigned visible=(c.video_mode&4)?0x4000:0;
            if((c.ram_byte_addr&0x4000)==visible) {
                if(visible_writes++<6) { std::printf("Visible write PC=%04x RAM=%05x VM=%x page=%02x state=%u\n",c.pc,c.ram_byte_addr,c.video_mode,byte(a_page),byte(a_state));std::fflush(stdout); }
            }
        }
        if(c.cpu_sync&&c.pc>=0x2000&&c.pc<0xA000)++banked_cycles;
        if(cycles%2048)continue;
        if(!ready) {
            if(cycles>hz*5) { std::printf("FAIL startup PC=%04x env=%02x bank=%02x zp=%02x frames=%u\n",c.pc,c.environment,c.bank,c.zero_page,word(a_frame_counter)); c.final(); return 1; }
            if(word(a_frame_counter)<4)continue;
            ready=true;started=cycles;start_frames=word(a_frame_counter);
            check(byte(a_state)==0,"core starts the game in native attract mode");
        }
        unsigned t=cycles-started;
        rendering=byte(a_state)==2&&!byte(a_redraw_scene);
        if(byte(a_speed)>peak_speed&&byte(a_state)==2)peak_speed=byte(a_speed);
        pages|=1<<((c.video_mode>>2)&1); sound.insert(c.test_audio);
        if(t>hz*3&&!clock_checked) {
            std::printf("CORE attract %.2f fps\n",(word(a_frame_counter)-start_frames)/3.0);
            check(word(a_irq_ticks)>6000,"real VIA IRQ clock advances");clock_checked=true;
        }
        c.joy_b_button=t>hz*3;
        if(t>hz*8&&t<hz*9)c.joy_b_x=0;
        else if(t>hz*9&&t<hz*10)c.joy_b_x=255;
        else c.joy_b_x=128;
        if(t>hz*8&&!frames_race) {
            frames_race=word(a_frame_counter);
            std::printf("At 8s state=%u speed=%u countdown=%u joy=%02x axes=%u,%u gas=%u brake=%u IRQ=%u\n",byte(a_state),byte(a_speed),byte(a_countdown),byte(a_joy),byte(a_joy_x),byte(a_joy_y),byte(a_throttle),byte(a_brake),word(a_irq_ticks));std::fflush(stdout);
        }
        if(t>hz*12&&!race_rate) { std::printf("CORE racing %.2f fps across steering and traffic\n",(word(a_frame_counter)-frames_race)/4.0);std::fflush(stdout);race_rate=true; }
        c.joy_b_switch=t>hz*12&&t<hz*14;
        if(t>hz*12+hz/2&&!paused_time) {
            check(byte(a_state)==3,"native latching switch pauses");paused_time=word(a_time_left);
        }
        if(t>hz*13+hz/2&&!pause_checked) {
            check(word(a_time_left)==paused_time,"pause freezes the real-core race clock");pause_checked=true;
        }
        if(t>hz*15&&!resume_checked) {
            check(byte(a_state)==2,"opposite switch transition resumes");
            check(peak_speed>60,"real joystick accelerates past 60 km/h");resume_checked=true;
            check(sound.size()>8,"native DAC produces changing engine and speech samples");
            check(pages==3,"both native graphics pages are presented");
            check(banked_cycles>1000,"compiled sprites execute from banked RAM");
            check(visible_writes==0,"rendering never writes the displayed framebuffer");
            std::printf("CORE completed %u rendered frames; %u visible-page writes; %u checks\n",word(a_frame_counter),visible_writes,checks);
            c.final();return failures?1:0;
        }
    }
    std::printf("FAIL core watchdog PC=%04x env=%02x bank=%02x zp=%02x frames=%u state=%u\n",c.pc,c.environment,c.bank,c.zero_page,word(a_frame_counter),byte(a_state));
    c.final();return 1;
}
