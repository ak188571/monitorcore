`timescale 1ns/1ps
module ui16_reliable_link_test;
    logic clk=0;
    always #5 clk=~clk;
    logic resetn=0,rx_valid=0,ack_done=0;
    logic [7:0] rx_data=0;
    wire [7:0] replay_data;
    wire replay_valid,ack_pending,live_update;
    wire [111:0] ack_data;
    wire row_error,font_error,row_we,verified_we,full_row_we,font_we,display_enabled;
    wire [7:0] row_x,row_y;
    wire [13:0] font_addr;
    wire [15:0] font_data;
    wire [7:0] data_in=replay_valid?replay_data:rx_data;
    wire valid_in=replay_valid||rx_valid;
    wire row_abort;
    wire cell_we=row_we && (!verified_we || !display_enabled || live_update);
    integer replay_count=0,font_write_count=0,visible_row_writes=0,pre_live_writes;
    logic prev_replay=0;
    ui_reliable_link #(.FREQ(1_000_000)) dut(
        .clk(clk),.resetn(resetn),.rx_data(rx_data),.rx_valid(rx_valid),
        .row_error(row_error),.font_error(font_error),
        .replay_data(replay_data),.replay_valid(replay_valid),.live_update(live_update),
        .ack_pending(ack_pending),.ack_data(ack_data),.ack_done(ack_done));
    ui16_transport #(.FREQ(1_000_000)) rows(
        .clk(clk),.resetn(resetn),.rx_data(data_in),.rx_valid(valid_in),
        .abort_frame(row_abort),.busy(),.error(row_error),.we(row_we),
        .verified_we(verified_we),.full_row_we(full_row_we),.x(row_x),.y(row_y),
        .glyph(),.selected(),.half(),.vertical_half());
    ui_font_transport #(.FREQ(1_000_000)) font(
        .clk(clk),.resetn(resetn),.rx_data(data_in),.rx_valid(valid_in),.live_update(live_update),
        .row_error(row_error),.row_we(full_row_we),.row_x(row_x),.row_y(row_y),
        .font_we(font_we),.font_addr(font_addr),.font_data(font_data),
        .display_enabled(display_enabled),.error(font_error));
    always @(posedge clk)begin
        if(resetn)begin
            if(replay_valid&&!prev_replay)replay_count<=replay_count+1;
            if(font_we)font_write_count<=font_write_count+1;
            if(cell_we)visible_row_writes<=visible_row_writes+1;
        end
        prev_replay<=replay_valid;
    end
    function automatic [31:0] crc32_byte(input [31:0] old,input [7:0] b);
        reg [31:0] c;
        begin
            c=old^{24'd0,b};
            for(integer i=0;i<8;i=i+1)c=c[0]?(c>>1)^32'hedb88320:c>>1;
            crc32_byte=c;
        end
    endfunction
    function automatic [7:0] crc8_byte(input [7:0] old,input [7:0] b);
        reg [7:0] c;
        begin
            c=old^b;
            for(integer i=0;i<8;i=i+1)c=c[7]?(c<<1)^8'h07:c<<1;
            crc8_byte=c;
        end
    endfunction
    task automatic byte_on_wire(input [7:0] b);
        @(negedge clk);rx_data=b;rx_valid=1;
        @(negedge clk);rx_valid=0;
    endtask
    logic [7:0] payload [0:67];
    task automatic packet(input [31:0] seq,input [7:0] inner,
                          input integer n,input bit corrupt,input integer status);
        reg [15:0] len;
        reg [31:0] crc;
        reg [31:0] reply_crc;
        integer waited;
        begin
            len=16'(n+10);
            crc=crc32_byte(crc32_byte(crc32_byte(32'hffffffff,len[15:8]),len[7:0]),8'h15);
            for(integer i=3;i>=0;i=i-1)crc=crc32_byte(crc,8'(seq>>(8*i)));
            crc=crc32_byte(crc,inner);
            for(integer i=0;i<n;i=i+1)crc=crc32_byte(crc,payload[i]);
            crc=crc^32'hffffffff;
            byte_on_wire(8'haa);byte_on_wire(len[15:8]);byte_on_wire(len[7:0]);
            byte_on_wire(8'h15);
            for(integer i=3;i>=0;i=i-1)byte_on_wire(8'(seq>>(8*i)));
            byte_on_wire(inner);
            for(integer i=0;i<n;i=i+1)byte_on_wire(payload[i]);
            for(integer i=0;i<4;i=i+1)
                byte_on_wire(8'(crc>>(8*i))^(corrupt && i==0 ? 8'h01 : 8'h00));
            waited=0;
            while(!ack_pending && waited<300)begin @(negedge clk);waited=waited+1;end
            if(status<0)begin
                if(ack_pending)$fatal(1,"corrupt packet acknowledged");
            end else begin
                if(!ack_pending)$fatal(1,"missing ACK seq=%x",seq);
                if(ack_data[111:104]!=2 || ack_data[103:96]!=8'(status) ||
                   ack_data[95:64]!=seq || ack_data[63:32]!=crc)
                    $fatal(1,"wrong ACK seq=%x status=%d data=%x",seq,status,ack_data);
                reply_crc=crc32_byte(crc32_byte(crc32_byte(32'hffffffff,0),15),8'h16);
                for(integer j=0;j<10;j=j+1)
                    reply_crc=crc32_byte(reply_crc,8'(ack_data>>(8*(13-j))));
                reply_crc=reply_crc^32'hffffffff;
                if(ack_data[31:24]!=reply_crc[7:0] ||
                   ack_data[23:16]!=reply_crc[15:8] ||
                   ack_data[15:8]!=reply_crc[23:16] ||
                   ack_data[7:0]!=reply_crc[31:24])
                    $fatal(1,"ACK CRC32 mismatch");
                @(negedge clk);ack_done=1;
                @(negedge clk);ack_done=0;
            end
        end
    endtask
    task automatic row_payload(input integer y);
        reg [7:0] c;
        begin
            payload[0]=8'(y);payload[1]=0;payload[2]=32;
            for(integer i=3;i<67;i=i+1)payload[i]=0;
            c=0;for(integer i=0;i<67;i=i+1)c=crc8_byte(c,payload[i]);
            payload[67]=c;
        end
    endtask
    localparam [31:0] START=32'h10203040;
    initial begin
        repeat(5)@(negedge clk);resetn=1;
        payload[0]=8'h55;payload[1]=8'h49;payload[2]=8'h31;payload[3]=8'h36;
        payload[4]=2;payload[5]=8'h10;payload[6]=8'h3f;payload[7]=1;
        payload[8]=8'hac;payload[9]=8'hbd;payload[10]=8'hce;payload[11]=8'hdf;
        packet(START,0,12,0,0);
        if(replay_count!=0)$fatal(1,"HELLO replayed");
        payload[0]=0;payload[1]=0; // CRC8(0)=0
        packet(START+1,8'h13,2,0,0);
        if(display_enabled || replay_count!=1)$fatal(1,"BLANK failed");
        packet(START+1,8'h13,2,0,0); // ACK was lost to the sender
        if(replay_count!=1)$fatal(1,"duplicate BLANK replayed");
        payload[0]=8'h3f;payload[1]=8'h01;
        for(integer i=2;i<34;i=i+1)payload[i]=8'(i);
        payload[34]=0;
        for(integer i=0;i<34;i=i+1)payload[34]=crc8_byte(payload[34],payload[i]);
        packet(START+2,8'h12,35,1,-1);
        if(font_write_count!=0)$fatal(1,"bad CRC changed font RAM");
        packet(START+2,8'h12,35,0,0);
        repeat(20)@(negedge clk);
        if(font_write_count!=16 || replay_count!=2)$fatal(1,"font upload failed");
        row_payload(0);
        packet(START+4,8'h14,68,0,4); // missing preceding packet
        if(replay_count!=2)$fatal(1,"out-of-order row replayed");
        packet(START+3,8'h14,68,0,0);
        packet(START+3,8'h14,68,0,0);
        if(replay_count!=3)$fatal(1,"duplicate row replayed");
        for(integer y=1;y<28;y=y+1)begin
            row_payload(y);
            packet(START+3+32'(y),8'h14,68,0,0);
        end
        payload[0]=1;payload[1]=crc8_byte(0,1);
        packet(START+31,8'h13,2,0,0);
        if(!display_enabled || replay_count!=31)$fatal(1,"SHOW before complete rows");
        pre_live_writes=visible_row_writes;
        payload[0]=8'h40;payload[1]=8'h01; // hidden slot 320
        for(integer i=2;i<34;i=i+1)payload[i]=8'(i+4);
        payload[34]=0;
        for(integer i=0;i<34;i=i+1)payload[34]=crc8_byte(payload[34],payload[i]);
        packet(START+32,8'h12,35,0,0);
        if(!display_enabled || font_write_count!=32)
            $fatal(1,"live font upload failed or blanked display");
        row_payload(0);
        packet(START+33,8'h14,68,0,0);
        if(!display_enabled || visible_row_writes!=pre_live_writes+32)
            $fatal(1,"live protected row was not committed");
        // The same packets without the validated wrapper remain forbidden
        // while the overlay is visible.
        payload[0]=8'h41;payload[1]=8'h01;
        for(integer i=2;i<34;i=i+1)payload[i]=8'(i+8);
        payload[34]=0;
        for(integer i=0;i<34;i=i+1)payload[34]=crc8_byte(payload[34],payload[i]);
        byte_on_wire(8'haa);byte_on_wire(0);byte_on_wire(36);byte_on_wire(8'h12);
        for(integer i=0;i<35;i=i+1)byte_on_wire(payload[i]);
        repeat(20)@(negedge clk);
        if(font_write_count!=32)$fatal(1,"unwrapped live font write accepted");
        row_payload(0);
        byte_on_wire(8'haa);byte_on_wire(0);byte_on_wire(69);byte_on_wire(8'h14);
        for(integer i=0;i<68;i=i+1)byte_on_wire(payload[i]);
        repeat(40)@(negedge clk);
        if(visible_row_writes!=pre_live_writes+32)
            $fatal(1,"unwrapped live row accepted");
        payload[0]=8'h55;payload[1]=8'h49;payload[2]=8'h31;payload[3]=8'h36;
        payload[4]=1;payload[5]=8'h10;payload[6]=8'h3f;payload[7]=1;
        payload[8]=0;payload[9]=0;payload[10]=0;payload[11]=1;
        packet(START+34,0,12,0,5);
        if(replay_count!=33)$fatal(1,"incompatible HELLO replayed");
        $display("UI16 reliable link v2: CRC32, retries, ordering, BLANK/SHOW, live hidden-slot upload and row passed");
        $finish;
    end
endmodule
