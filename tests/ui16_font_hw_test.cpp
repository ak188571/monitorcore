#include "Vui16_hw_top.h"
#include "verilated.h"
#include <cassert>
#include <cstdint>
#include <cstdio>
#include <fstream>
#include <iterator>
#include <vector>

double sc_time_stamp(){return 0;}
struct Device {
    Vui16_hw_top t;
    unsigned long long time=0;
    unsigned errors=0,font_errors=0;
    void step(){
        bool old=t.clk;
        ++time;t.clk=(time%10)>=5;t.hclk=(time%6)>=3;t.eval();
        if(!old && t.clk){errors+=t.error;font_errors+=t.font_error_o;}
    }
    void cycles(unsigned n){
        unsigned edges=0;
        while(edges<n){bool was=t.clk;step();if(!was&&t.clk)++edges;}
    }
    void byte(unsigned b){
        t.byte_data=b;t.byte_valid=1;cycles(1);t.byte_valid=0;
        cycles(275); // model physical 2-Mbaud byte time: 250 FPGA clocks
    }
    void bytes(const std::vector<unsigned>& packet){for(auto b:packet)byte(b);}
    unsigned pixel(unsigned x,unsigned y){t.x=x;t.y=y;cycles(8);return t.color;}
};
static std::uint8_t crc(const std::vector<unsigned>& v){
    unsigned c=0;
    for(auto b:v){c^=b;for(int i=0;i<8;++i)c=(c&128)?((c<<1)^7)&255:(c<<1)&255;}
    return std::uint8_t(c);
}
static std::vector<unsigned> control(unsigned op){return {0xaa,0,3,0x13,op,crc({op})};}
static std::vector<unsigned> bad_control(unsigned op) {
    auto p=control(op);p.back()^=1;return p;
}
static std::vector<unsigned> bitmap(unsigned slot,bool corrupt=false){
    std::vector<unsigned> payload={slot&255,slot>>8};
    for(int n=0;n<16;++n){payload.push_back(n==0?0x80:0);payload.push_back(0);}
    std::vector<unsigned> p={0xaa,0,36,0x12};p.insert(p.end(),payload.begin(),payload.end());
    p.push_back(crc(payload)^(corrupt?1:0));return p;
}
static std::vector<unsigned> row(unsigned y,unsigned id,bool corrupt=false){
    std::vector<unsigned> v={0xaa,0,69,0x14,y,0,32};
    for(int x=0;x<32;++x){
        const unsigned cell=(x==0 && y==0)?id:0;
        v.push_back(cell&255);
        v.push_back(((cell>>8)&15)<<2);
    }
    std::vector<unsigned> payload(v.begin()+4,v.end());
    v.push_back(crc(payload)^(corrupt?1:0));
    return v;
}
static std::vector<unsigned> partial_row(unsigned y){
    // Valid CRC but only column 31: it must not count as a full-screen row.
    std::vector<unsigned> p={y,31,1,0,0};
    std::vector<unsigned> v={0xaa,0,7,0x14};
    v.insert(v.end(),p.begin(),p.end());v.push_back(crc(p));
    return v;
}
static void screen(Device& d,int rows=28){for(int y=0;y<rows;++y)d.bytes(row(y,900));}
int main(int argc,char**argv){
    Verilated::commandArgs(argc,argv);
    Device d;
    d.t.clk=d.t.hclk=d.t.resetn=d.t.byte_valid=d.t.use_serial=0;
    d.t.serial_rx=1;d.t.x=d.t.y=d.t.byte_data=0;
    d.cycles(20);d.t.resetn=1;d.cycles(30);
    d.bytes(control(0));
    d.bytes(bitmap(900));
    screen(d);
    assert(d.pixel(0,0)==0); // No visible glyph until the full frame is written.
    d.bytes(control(1));
    assert(d.errors==0 && d.font_errors==0 && d.t.font_visible);
    assert(d.pixel(0,0)!=0);
    assert(d.pixel(1,0)==0);
    // If BLANK was damaged, CRC-row writes must be ignored while visible.
    d.bytes(bad_control(0));d.bytes(row(0,0));
    assert(d.font_errors>=1 && d.t.font_visible);
    assert(d.pixel(0,0)!=0);
    d.bytes(control(0));d.bytes(bitmap(900,true));screen(d);d.bytes(control(1));
    assert(d.pixel(0,0)==0 && !d.t.font_visible); // CRC failure keeps display gated.
    d.bytes(control(0));d.bytes(bitmap(900));screen(d,27);d.bytes(control(1));
    assert(d.pixel(0,0)==0); // Incomplete frame cannot be shown.
    d.bytes(control(0));d.bytes(bitmap(900));screen(d,27);d.bytes(partial_row(27));d.bytes(control(1));
    assert(d.pixel(0,0)==0); // A CRC-correct partial row is not a complete row.
    d.bytes(control(0));d.bytes(bitmap(900));screen(d,27);d.bytes(row(27,900,true));d.bytes(control(1));
    assert(d.pixel(0,0)==0); // CRC failure in cell data blocks SHOW.
    d.bytes(control(0));d.bytes(bitmap(900));screen(d);d.bytes(control(1));
    assert(d.pixel(0,0)!=0 && d.t.font_visible); // Retry can recover without changing FPGA firmware.
    if(argc >= 2) {
        std::ifstream in(argv[1],std::ios::binary);
        assert(in);
        const std::vector<unsigned char> sender_bytes{
            std::istreambuf_iterator<char>(in),std::istreambuf_iterator<char>()};
        assert(!sender_bytes.empty());
        Device boundary;
        boundary.t.clk=boundary.t.hclk=boundary.t.resetn=boundary.t.byte_valid=boundary.t.use_serial=0;
        boundary.t.serial_rx=1;boundary.t.x=boundary.t.y=boundary.t.byte_data=0;
        boundary.cycles(20);boundary.t.resetn=1;boundary.cycles(30);
        for(auto b:sender_bytes) boundary.byte(b);
        assert(boundary.errors==0 && boundary.font_errors==0);
        assert(boundary.t.font_visible && boundary.t.writes==28u*32u);
    }
    std::puts("UI16 FPGA font transfer: glyph CRC, row CRC, gate, full-frame, recovery and BL616 wire boundary OK");
}
