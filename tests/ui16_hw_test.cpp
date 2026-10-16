#include "Vui16_hw_top.h"
#include "verilated.h"
#include <cassert>
#include <cstdint>
#include <cstdio>
#include <fstream>
#include <string>
#include <vector>

static std::vector<unsigned> hex(const char* name) {
    std::ifstream f(name);assert(f);std::vector<unsigned> words;std::string s;
    while(f>>s)words.push_back(std::stoul(s,nullptr,16));return words;
}
struct Simulation {
    Vui16_hw_top t;
    unsigned long long time=0;
    unsigned errors=0,aborts=0,received=0;
    // Independent clocks with different periods: clk period 10, hclk period 6.
    void step() {
        ++time;bool old_clk=t.clk;
        t.clk=(time%10)>=5;t.hclk=(time%6)>=3;t.eval();
        if(!old_clk&&t.clk){errors+=t.error;aborts+=t.abort_frame;received+=t.serial_valid;}
    }
    void cycles(unsigned n) {unsigned hits=0;while(hits<n){bool old=t.clk;step();if(!old&&t.clk)++hits;}}
    void hcycles(unsigned n) {unsigned hits=0;while(hits<n){bool old=t.hclk;step();if(!old&&t.hclk)++hits;}}
    void byte(unsigned b) {
        t.byte_data=b;t.byte_valid=1;cycles(1);t.byte_valid=0;cycles(1);
        while(t.busy)cycles(1);cycles(2);
    }
    void serial(unsigned b) {
        t.serial_rx=0;cycles(25);
        for(int bit=0;bit<8;++bit){t.serial_rx=(b>>bit)&1;cycles(25);}
        t.serial_rx=1;cycles(25);
    }
};
static unsigned expected(const std::vector<unsigned>& cells,const std::vector<unsigned>& font,int x,int y) {
    if(y>=224)return 0;
    auto c=cells[(y/16)*32+x/8];auto row=font[(c&255)*16+y%16];
    int offset=((c>>9)&1)*8+x%8;
    if(!(row&(1u<<(15-offset))))return 0;
    // Selected RGB (30,28,8) -> BGR (8,28,30); ordinary text is (26,26,26).
    return (c&256)?((8<<10)|(28<<5)|30):((26<<10)|(26<<5)|26);
}
static std::vector<unsigned> frame(const std::vector<unsigned>& cells) {
    std::vector<unsigned> out;
    for(int y=0;y<14;++y){out.insert(out.end(),{0xAA,0,68,14,unsigned(y),0,32});
        for(int x=0;x<32;++x){auto c=cells[y*32+x];out.push_back(c&255);out.push_back((c>>8)&3);}}
    return out;
}
int main(int argc,char**argv) {
    Verilated::commandArgs(argc,argv);Simulation sim;
    sim.t.clk=sim.t.hclk=sim.t.resetn=sim.t.byte_valid=sim.t.use_serial=0;
    sim.t.serial_rx=1;sim.t.byte_data=sim.t.x=sim.t.y=0;sim.cycles(20);
    sim.t.resetn=1;sim.cycles(20);
    auto font=hex("src/iosys/ui16/font16_full.hex"),cells=hex("src/iosys/ui16/cells_selftest.hex");
    assert(font.size()==4096&&cells.size()==512);
    for(int y=0;y<256;++y)for(int x=0;x<256;++x){
        sim.t.x=x;sim.t.y=y;sim.hcycles(3);
        assert(sim.t.selftest_color==expected(cells,font,x,y));assert(sim.t.color==0);
    }
    // Real 8N1 waveform through the unchanged TangCore UART receiver.
    sim.t.use_serial=1;auto bytes=frame(cells);for(auto b:bytes)sim.serial(b);sim.cycles(100);
    assert(sim.received==bytes.size());assert(sim.errors==0&&sim.aborts==0);
    for(int y=0;y<256;++y)for(int x=0;x<256;++x){
        sim.t.x=x;sim.t.y=y;sim.hcycles(3);assert(sim.t.color==expected(cells,font,x,y));
    }
    // Raster with a different coordinate on every hclk edge: metadata and font latency align.
    std::vector<unsigned> queue;
    for(int n=0;n<1000;++n){sim.t.x=(n*17)%256;sim.t.y=(n*29)%256;
        queue.push_back(expected(cells,font,sim.t.x,sim.t.y));sim.hcycles(1);
        if(n>=2)assert(sim.t.color==queue[n-2]);}
    sim.t.use_serial=0;
    for(auto b:std::vector<unsigned>{0xAA,0,6,14,0,0,1,1})sim.byte(b); // missing attribute
    sim.cycles(499900);assert(sim.aborts==0);
    sim.cycles(200);assert(sim.aborts==1&&sim.errors==1);
    // Recovery frame clears the whole screen; old glyphs disappear.
    auto zeros=std::vector<unsigned>(448,0);for(auto b:frame(zeros))sim.byte(b);
    for(int y=0;y<224;++y)for(int x=0;x<256;++x){sim.t.x=x;sim.t.y=y;sim.hcycles(3);assert(sim.t.color==0);}
    std::puts("hardware UI tests passed: selftest, 994 serial bytes, full pixel comparison, 3-edge pipeline, independent clocks, 10ms timeout, recovery/clear");
}
