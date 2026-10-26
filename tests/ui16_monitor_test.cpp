#include "Vui16_monitor_top.h"
#include "verilated.h"
#include <cassert>
#include <cstdio>
#include <vector>
double sc_time_stamp(){return 0;}
struct Sim {
    Vui16_monitor_top t;
    unsigned long long time=0;
    void step(){++time;t.clk=time%10>=5;t.hclk=time%6>=3;t.eval();}
    void cycles(unsigned n){unsigned i=0;while(i<n){bool old=t.clk;step();if(!old&&t.clk)++i;}}
    void byte(unsigned b){t.rx=0;cycles(25);for(int i=0;i<8;++i){t.rx=(b>>i)&1;cycles(25);}t.rx=1;cycles(25);}
    void frame(const std::vector<unsigned>& v){for(auto b:v)byte(b);cycles(100);}
};
int main(int argc,char**argv){
    Verilated::commandArgs(argc,argv);Sim s;s.t.clk=s.t.hclk=s.t.resetn=0;
    s.t.rx=1;s.t.x=s.t.y=0;s.cycles(20);s.t.resetn=1;s.cycles(20);
    assert(s.t.color==0x1234);
    s.frame({0xAA,0,6,15,0,0,1,0,0});assert(s.t.color==0); // valid empty row selects new renderer
    s.frame({0xAA,0,3,4,0,0});s.frame({0xAA,0,2,5,'A'});assert(s.t.color==0x1234);
    s.frame({0xAA,0,6,15,0,0,1,0,0});assert(s.t.color==0);
    s.frame({0xAA,0,6,15,0,0,1,0});s.cycles(500100); // missing attr; both parsers must reset
    s.frame({0xAA,0,3,4,0,0});s.frame({0xAA,0,2,5,'A'});assert(s.t.color==0x1234);
    // A valid BLANK must cover the complete overlay mux even before the first
    // protected row selects the UI16 renderer.
    s.frame({0xAA,0,3,0x13,0,0});assert(s.t.color==0);
    std::puts("monitor integration passed: real UART, new/legacy switching, global BLANK gate, timeout resets both parsers; legacy display uses test stub");
}
