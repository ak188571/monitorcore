// Stop-and-wait transport for the optional microSD font path. The original
// UI16 commands remain accepted by their existing decoders. A wrapped command
// is replayed only after its complete CRC32 has passed. The response contains
// protocol, status, sequence, request CRC32 and its own CRC32 (little endian).
module ui_reliable_link #(
    parameter integer FREQ=50_000_000,
    parameter integer TIMEOUT_MS=10
) (
    input logic clk, resetn,
    input logic [7:0] rx_data,
    input logic rx_valid,
    input logic row_error, font_error,
    output logic [7:0] replay_data,
    output logic replay_valid,
    output logic live_update,
    output logic ack_pending,
    output logic [111:0] ack_data,
    input logic ack_done
);
    localparam integer TIMEOUT_CYCLES=(FREQ/1000)*TIMEOUT_MS;
    localparam integer TIMER_BITS=$clog2(TIMEOUT_CYCLES+1);
    localparam logic [2:0] IDLE=0,LEN_HI=1,LEN_LO=2,CMD=3,BODY=4,SKIP=5,CHECK=6,REPLAY=7;
    logic [2:0] state;
    logic [15:0] length, pos, skip_left;
    logic [7:0] length_hi, body [0:77];
    logic [31:0] crc, last_seq, last_digest;
    logic [31:0] received_digest;
    logic session_valid;
    logic [6:0] replay_idx;
    logic [6:0] settle_left;
    logic settling;
    logic error_seen;
    logic [31:0] ack_seq, ack_digest;
    logic [7:0] ack_status;
    logic [TIMER_BITS-1:0] idle_cycles;

    function automatic [31:0] crc_byte(input [31:0] previous,input [7:0] value);
        reg [31:0] c;
        begin
            c=previous^{24'd0,value};
            for(integer i=0;i<8;i=i+1)
                c=c[0] ? ((c>>1)^32'hedb88320) : (c>>1);
            crc_byte=c;
        end
    endfunction
    wire [31:0] request_seq={body[0],body[1],body[2],body[3]};
    wire [31:0] request_digest=crc^32'hffffffff;
    wire hello_ok=length==22 && body[4]==0 &&
        body[5]==8'h55 && body[6]==8'h49 && body[7]==8'h31 && body[8]==8'h36 &&
        body[9]==2 && body[10]==8'h10 && body[11]==8'h3f && body[12]==8'h01;
    wire inner_ok=(body[4]==8'h12 && length==45) ||
                  (body[4]==8'h13 && length==12) ||
                  (body[4]==8'h14 && length==78);
    // Validated version-2 font/row replays may update hidden slots and rows
    // while the overlay is visible. Keep authorization through decoder commit.
    assign live_update=(state==REPLAY || settling) && session_valid &&
                       (body[4]==8'h12 || body[4]==8'h14);
    reg [31:0] reply_crc;
    always_comb begin
        reply_crc=32'hffffffff;
        reply_crc=crc_byte(reply_crc,8'h00);
        reply_crc=crc_byte(reply_crc,8'h0f);
        reply_crc=crc_byte(reply_crc,8'h16);
        reply_crc=crc_byte(reply_crc,8'h02);
        reply_crc=crc_byte(reply_crc,ack_status);
        reply_crc=crc_byte(reply_crc,ack_seq[31:24]);
        reply_crc=crc_byte(reply_crc,ack_seq[23:16]);
        reply_crc=crc_byte(reply_crc,ack_seq[15:8]);
        reply_crc=crc_byte(reply_crc,ack_seq[7:0]);
        reply_crc=crc_byte(reply_crc,ack_digest[31:24]);
        reply_crc=crc_byte(reply_crc,ack_digest[23:16]);
        reply_crc=crc_byte(reply_crc,ack_digest[15:8]);
        reply_crc=crc_byte(reply_crc,ack_digest[7:0]);
        reply_crc=reply_crc^32'hffffffff;
        ack_data={8'h02,ack_status,ack_seq,ack_digest,
                  reply_crc[7:0],reply_crc[15:8],reply_crc[23:16],reply_crc[31:24]};
    end
    always_ff @(posedge clk) begin
        if(!resetn) begin
            state<=IDLE;length<=0;length_hi<=0;pos<=0;skip_left<=0;
            crc<=0;received_digest<=0;
            last_seq<=0;last_digest<=0;session_valid<=0;
            replay_idx<=0;replay_data<=0;replay_valid<=0;
            settle_left<=0;settling<=0;error_seen<=0;
            ack_pending<=0;ack_seq<=0;ack_digest<=0;ack_status<=0;idle_cycles<=0;
        end else begin
            replay_valid<=0;
            if(ack_done)ack_pending<=0;
            if(state==IDLE || state==REPLAY || settling || rx_valid)idle_cycles<=0;
            else if(idle_cycles==TIMER_BITS'(TIMEOUT_CYCLES-1)) begin
                idle_cycles<=0;state<=IDLE;
            end else idle_cycles<=idle_cycles+1'b1;

            if(row_error || font_error)error_seen<=1;
            if(state==REPLAY) begin
                replay_valid<=1;
                case(replay_idx)
                    0: replay_data<=8'haa;
                    1: replay_data<=0;
                    2: replay_data<=8'(length-9);
                    3: replay_data<=body[4];
                    default: replay_data<=body[replay_idx+1];
                endcase
                if(replay_idx==7'(length-7))begin
                    state<=IDLE;settling<=1;settle_left<=80;
                end else replay_idx<=replay_idx+1'b1;
            end else if(settling) begin
                if(settle_left==0)begin
                    settling<=0;
                    ack_pending<=1;ack_seq<=request_seq;ack_digest<=request_digest;
                    if(error_seen || row_error || font_error)ack_status<=1;
                    else begin
                        ack_status<=0;last_seq<=request_seq;last_digest<=request_digest;
                    end
                end else settle_left<=settle_left-1'b1;
            end else if(rx_valid) begin
                case(state)
                IDLE: if(rx_data==8'haa)state<=LEN_HI;
                LEN_HI: begin length_hi<=rx_data;state<=LEN_LO;end
                LEN_LO: begin
                    length<={length_hi,rx_data};
                    crc<=crc_byte(crc_byte(32'hffffffff,length_hi),rx_data);
                    if({length_hi,rx_data}==0 || {length_hi,rx_data}>16'd2047)state<=IDLE;
                    else state<=CMD;
                end
                CMD: begin
                    pos<=0;
                    received_digest<=0;
                    if(rx_data==8'h15 && length>=12 && length<=78)begin
                        crc<=crc_byte(crc,rx_data);state<=BODY;
                    end else if(length==1)state<=IDLE;
                    else begin skip_left<=length-1'b1;state<=SKIP;end
                end
                SKIP: if(skip_left==1)state<=IDLE;
                      else skip_left<=skip_left-1'b1;
                BODY: begin
                    body[pos[6:0]]<=rx_data;
                    if(pos<length-5)crc<=crc_byte(crc,rx_data);
                    else received_digest<={rx_data,received_digest[31:8]};
                    if(pos==length-2)state<=CHECK;
                    else pos<=pos+1'b1;
                end
                default: state<=IDLE;
                endcase
            end
            if(state==CHECK)begin
                state<=IDLE;
                if(request_digest==received_digest)begin
                    ack_seq<=request_seq;ack_digest<=request_digest;
                    if(hello_ok)begin
                        if(session_valid && request_seq==last_seq && request_digest==last_digest)begin
                            ack_status<=0;ack_pending<=1;
                        end else begin
                            session_valid<=1;last_seq<=request_seq;last_digest<=request_digest;
                            ack_status<=0;ack_pending<=1;
                        end
                    end else if(body[4]==0)begin ack_status<=5;ack_pending<=1;end
                    else if(!session_valid)begin ack_status<=3;ack_pending<=1;end
                    else if(request_seq==last_seq && request_digest==last_digest)begin
                        ack_status<=0;ack_pending<=1;
                    end else if(request_seq!=last_seq+1'b1)begin ack_status<=4;ack_pending<=1;end
                    else if(!inner_ok)begin ack_status<=2;ack_pending<=1;end
                    else begin replay_idx<=0;error_seen<=0;state<=REPLAY;end
                end
            end
        end
    end
endmodule
