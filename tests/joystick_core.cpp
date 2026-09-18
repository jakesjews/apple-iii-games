#include "Vcore_tb.h"
#include "verilated.h"
#include <algorithm>
#include <cstdio>
#include <cstdlib>

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Vcore_tb core;
    core.reset = 1;
    core.serial_rx = core.serial_cts_n = core.serial_dsr_n = 1;
    core.image_readonly = 1;
    core.joy_a_x = core.joy_a_y = 128;
    auto set_inputs = [&](unsigned n) {
        core.joy_b_x = n / 4;
        core.joy_b_y = 255 - n / 4;
        core.joy_b_button = (n & 4) != 0;
        core.joy_b_switch = (n & 8) != 0;
    };
    auto tick = [&]() {
        core.clk = 0; core.eval();
        core.clk = 1; core.eval();
    };
    // System bank, including the Apple III's paired-byte RAM arrangement.
    auto read = [&](unsigned address) -> unsigned {
        unsigned physical = 0x38000 + address;
        core.probe_addr = ((physical >> 12) << 11) |
            ((((physical >> 10) ^ (physical >> 11)) & 1) << 10) | (physical & 0x3ff);
        core.eval();
        return (core.probe_word >> (((physical >> 11) & 1) * 8)) & 255;
    };
    set_inputs(0);
    for (int i = 0; i < 128; ++i) tick();
    core.reset = 0;
    unsigned done = 0, previous = 0, failures = 0, worst = 0;
    auto check = [&](bool passed, const char *what, unsigned got, unsigned want) {
        if (!passed && ++failures <= 20)
            std::printf("FAIL sample %u %s: got %u, expected %u\n", done, what, got, want);
    };
    for (unsigned cycles = 0; cycles < 150000000 && done < 1024; ++cycles) {
        tick();
        if (cycles % 16 || read(0x0410) == (done & 255)) continue;
        unsigned x = read(0x0400), y = read(0x0401), joy = read(0x0402);
        unsigned wanted_x = done / 4, wanted_y = 255 - wanted_x;
        unsigned dx = std::abs(int(x) - int(wanted_x)), dy = std::abs(int(y) - int(wanted_y));
        worst = std::max({worst, dx, dy});
        check(dx <= 4, "X converter accuracy", x, wanted_x);
        check(dy <= 4, "Y converter accuracy", y, wanted_y);
        unsigned wanted_joy = (x < 96 ? 1 : x > 160 ? 2 : 0) |
            (y < 96 ? 8 : y > 160 ? 4 : 0) | ((done & 4) ? 16 : 0) | ((done & 8) ? 32 : 0);
        check(joy == wanted_joy, "directions and physical buttons", joy, wanted_joy);
        check(read(0x0403) == (joy & ~previous), "press edges", read(0x0403), joy & ~previous);
        check(read(0x0404) == ((joy ^ previous) & 32), "switch edges", read(0x0404), (joy ^ previous) & 32);
        previous = joy;
        ++done;
        if (done < 1024) set_inputs(done);
    }
    core.final();
    if (done != 1024 || failures) {
        std::printf("FAIL: %u/1024 samples completed, %u failures\n", done, failures);
        return 1;
    }
    std::printf("PASS: 1024 samples, 5120 checks; all 256 positions at 1/2 MHz, video on/off; largest error %u/255\n", worst);
}
