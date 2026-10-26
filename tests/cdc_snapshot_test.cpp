#include "Vcdc_snapshot_top.h"
#include "verilated.h"
#include <cassert>
#include <cstdint>
#include <iostream>

double sc_time_stamp(){return 0;}

static void src_edge(Vcdc_snapshot_top &d, std::uint16_t data, bool valid) {
    d.src_data=data; d.src_valid=valid; d.src_clk=0; d.eval();
    d.src_clk=1; d.eval(); d.src_clk=0; d.eval();
}
static bool dst_edge(Vcdc_snapshot_top &d) {
    d.dst_clk=0; d.eval(); d.dst_clk=1; d.eval();
    const bool valid=d.dst_valid;
    d.dst_clk=0; d.eval(); return valid;
}
static void expect_snapshot(Vcdc_snapshot_top &d, std::uint16_t value) {
    int pulses=0;
    for(int i=0;i<6;++i) {
        if(dst_edge(d)) { ++pulses; assert(d.dst_data==value); }
    }
    assert(pulses==1);
}
int main(int argc,char **argv) {
    Verilated::commandArgs(argc,argv);
    Vcdc_snapshot_top d;
    d.src_clk=0; d.dst_clk=0; d.src_resetn=0; d.dst_resetn=0;
    src_edge(d,0,false); dst_edge(d);
    d.src_resetn=1; d.dst_resetn=1;

    src_edge(d,0x5a5,true);
    src_edge(d,0xa5a,false); // input may change; held snapshot must not.
    expect_snapshot(d,0x5a5);
    for(int i=0;i<4;++i) assert(!dst_edge(d));

    src_edge(d,0x123,true);
    expect_snapshot(d,0x123);
    src_edge(d,0xfff,true);
    expect_snapshot(d,0xfff);
    std::cout << "CDC snapshot test passed: coherent bus, one pulse per source update\n";
    return 0;
}
