`timescale 1ns/1ps
module ui16_sender_boundary_test;
    logic clk=0;
    always #5 clk=~clk;
    logic resetn=0,rx_valid=0,ack_done=0;
    logic [7:0] rx_data=0;
    wire [7:0] replay_data;
    wire replay_valid,ack_pending,row_error,font_error,live_update;
    wire [111:0] ack_data;
    wire [7:0] data_in=replay_valid?replay_data:rx_data;
    wire valid_in=replay_valid||rx_valid;
    wire full_row_we,font_we,display_enabled;
    wire [7:0] row_x,row_y;
    wire [13:0] font_addr;
    wire [15:0] font_data;
    logic [7:0] stream[0:256];
    integer replay_count=0,font_writes=0,row_writes=0;
    logic prev_replay=0;
    ui_reliable_link #(.FREQ(1_000_000)) link(
        .clk(clk),.resetn(resetn),.rx_data(rx_data),.rx_valid(rx_valid),
        .row_error(row_error),.font_error(font_error),
        .replay_data(replay_data),.replay_valid(replay_valid),.live_update(live_update),
        .ack_pending(ack_pending),.ack_data(ack_data),.ack_done(ack_done));
    ui16_transport #(.FREQ(1_000_000)) rows(
        .clk(clk),.resetn(resetn),.rx_data(data_in),.rx_valid(valid_in),
        .abort_frame(),.busy(),.error(row_error),.we(),.verified_we(),
        .full_row_we(full_row_we),.x(row_x),.y(row_y),
        .glyph(),.selected(),.half(),.vertical_half());
    ui_font_transport #(.FREQ(1_000_000)) font(
        .clk(clk),.resetn(resetn),.rx_data(data_in),.rx_valid(valid_in),.live_update(live_update),
        .row_error(row_error),.row_we(full_row_we),.row_x(row_x),.row_y(row_y),
        .font_we(font_we),.font_addr(font_addr),.font_data(font_data),
        .display_enabled(display_enabled),.error(font_error));
    always @(posedge clk)begin
        if(resetn)begin
            if(replay_valid&&!prev_replay)replay_count<=replay_count+1;
            if(font_we)font_writes<=font_writes+1;
            if(full_row_we)row_writes<=row_writes+1;
        end
        prev_replay<=replay_valid;
    end
    task automatic send_byte(input [7:0] b);
        @(negedge clk);rx_data=b;rx_valid=1;
        @(negedge clk);rx_valid=0;
    endtask
    integer offset,frame_len,waited;
    logic [31:0] expected_seq,expected_crc;
    initial begin
        $readmemh("../firmware-bl616/build-ui16-host/reliable_link_wire.hex",stream);
        repeat(5)@(negedge clk);resetn=1;
        offset=0;
        for(integer frame=0;frame<7;frame=frame+1)begin
            if(stream[offset]!=8'haa)$fatal(1,"BL616 frame header lost");
            frame_len=(integer'(stream[offset+1])<<8)|stream[offset+2];
            expected_seq={stream[offset+4],stream[offset+5],stream[offset+6],stream[offset+7]};
            expected_crc={stream[offset+frame_len+2],stream[offset+frame_len+1],
                          stream[offset+frame_len],stream[offset+frame_len-1]};
            for(integer i=0;i<frame_len+3;i=i+1)send_byte(stream[offset+i]);
            waited=0;
            while(!ack_pending&&waited<300)begin @(negedge clk);waited=waited+1;end
            if(!ack_pending || ack_data[103:96]!=0 || ack_data[95:64]!=expected_seq ||
               ack_data[63:32]!=expected_crc)
                $fatal(1,"BL616 packet %0d not accepted",frame);
            @(negedge clk);ack_done=1;
            @(negedge clk);ack_done=0;
            offset=offset+frame_len+3;
        end
        repeat(40)@(negedge clk);
        if(offset!=257 || replay_count!=3 || font_writes!=16 || row_writes!=32 || display_enabled)
            $fatal(1,"boundary mismatch bytes=%0d replay=%0d font=%0d row=%0d blank=%b",
                offset,replay_count,font_writes,row_writes,!display_enabled);
        $display("UI16 BL616-to-RTL boundary: 257 actual bytes, retries, CRC32, font RAM and protected row passed");
        $finish;
    end
endmodule
