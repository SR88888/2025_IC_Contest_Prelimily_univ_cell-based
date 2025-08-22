module CONVEX(
input               CLK,
input               RST,
input       [4:0]   PT_XY,
output              READ_PT,
output reg  [9:0]   DROP_X,
output reg  [9:0]   DROP_Y,
output reg          DROP_V);

localparam IDLE     = 3'd0;
localparam INIT     = 3'd1;
localparam DELAY    = 3'd2;
localparam READ     = 3'd3;
localparam PROC     = 3'd4;
localparam WAIT     = 3'd5;

reg  [2:0]  state, state_w;
reg  [3:0]  cnt, cnt_w;
reg  [9:0]  PT_NEW_x, PT_NEW_y;
reg  [9:0]  PT_x [0:11], PT_x_w [0:11];
reg  [9:0]  PT_y [0:11], PT_y_w [0:11];
reg  [3:0]  PT_cnt;
reg  [9:0]  PT_IN_x, PT_IN_y, PT_LEFT_x, PT_LEFT_y, PT_RIGHT_x, PT_RIGHT_y;
wire [1:0]  PT_TYPE;
reg         CUT_TYPE_last;
reg  [3:0]  preserve_cnt, preserve_cnt_w;
wire [3:0]  preserve_cnt_add_one, preserve_cnt_minus_one;
reg         add_new, dropped, type_valid;

assign preserve_cnt_add_one = preserve_cnt + 1'b1;
assign preserve_cnt_minus_one = preserve_cnt - 1'b1;
assign READ_PT = (state_w == READ) || (state_w == INIT);
//========================================
// FSM
//========================================
always @(*) begin
    state_w = state;
    case (state)
        IDLE:   state_w = INIT;
        INIT:   state_w = (cnt == 4'd11) ? DELAY : INIT;
        DELAY:  state_w = READ;
        READ:   state_w = (cnt[1:0] == 2'd3) ? PROC : READ;
        PROC:   state_w = (cnt == PT_cnt) ? WAIT : PROC;
        WAIT:   state_w = READ;
    endcase
end
always @(posedge CLK or posedge RST) begin
    if (RST)    state <= IDLE;
    else        state <= state_w;
end
//========================================
// cnt
//========================================
always @(*) begin
    cnt_w = cnt;
    case (state)
        INIT:   cnt_w = (cnt == 4'd11) ? 4'd0 : cnt + 1'b1;
        READ:   cnt_w = (cnt[1:0] == 2'd3) ? 4'd0 : cnt + 1'b1;
        PROC:   cnt_w = cnt + 1'b1;
        WAIT:   cnt_w = 4'd0;
    endcase
end
always @(posedge CLK or posedge RST) begin
    if (RST)    cnt <= 4'd0;
    else        cnt <= cnt_w;
end
//========================================
// PT_NEW_x, PT_NEW_y
//========================================
always @(posedge CLK) begin
    if (state == INIT || state == READ) begin
        PT_NEW_x <= cnt[1] ? PT_NEW_x : {PT_NEW_x[4:0], PT_XY};
        PT_NEW_y <= cnt[1] ? {PT_NEW_y[4:0], PT_XY} : PT_NEW_y;
    end
end
//========================================
// PT_cnt
//========================================
always @(posedge CLK) begin
    if (state == READ) PT_cnt <= preserve_cnt;
end
//========================================
// PT
//========================================
integer i;
always @(*) begin
    for (i = 0; i < 12; i = i + 1) begin
        PT_x_w[i] = PT_x[i];
        PT_y_w[i] = PT_y[i];
    end
    case (state)
        INIT, DELAY: begin
            for (i = 0; i < 12; i = i + 1) begin
                PT_x_w[preserve_cnt] = PT_NEW_x;
                PT_y_w[preserve_cnt] = PT_NEW_y;
            end
        end
        PROC, WAIT: begin
            for (i = 0; i < 11; i = i + 1) begin
                PT_x_w[i] = PT_x[i+1];
                PT_y_w[i] = PT_y[i+1];
            end
            if (!type_valid) begin
                PT_x_w[preserve_cnt] = PT_x[0];
                PT_y_w[preserve_cnt] = PT_y[0];
            end
            else if (PT_TYPE[1]) begin
                if (CUT_TYPE_last && !dropped) begin
                    PT_x_w[preserve_cnt] = PT_NEW_x;
                    PT_y_w[preserve_cnt] = PT_NEW_y;
                    PT_x_w[preserve_cnt_add_one] = PT_LEFT_x;
                    PT_y_w[preserve_cnt_add_one] = PT_LEFT_y;
                end
                else begin
                    PT_x_w[preserve_cnt] = PT_LEFT_x;
                    PT_y_w[preserve_cnt] = PT_LEFT_y;
                    if (!add_new && state[0]) begin
                        PT_x_w[preserve_cnt_add_one] = PT_NEW_x;
                        PT_y_w[preserve_cnt_add_one] = PT_NEW_y;
                    end
                end
            end
            else if (!PT_TYPE[0]) begin
                PT_x_w[preserve_cnt] = PT_LEFT_x;
                PT_y_w[preserve_cnt] = PT_LEFT_y;
            end
            else if (!add_new) begin
                PT_x_w[preserve_cnt] = PT_NEW_x;
                PT_y_w[preserve_cnt] = PT_NEW_y;
            end
        end
    endcase
end
always @(posedge CLK) begin
    for (i = 0; i < 12; i = i + 1) begin
        PT_x[i] <= PT_x_w[i];
        PT_y[i] <= PT_y_w[i];
    end
end
//========================================
always @(posedge CLK) begin
    if (state == READ) begin
        PT_LEFT_x <= PT_x[preserve_cnt];
        PT_LEFT_y <= PT_y[preserve_cnt];
        PT_IN_x <= PT_x[0];
        PT_IN_y <= PT_y[0];
        PT_RIGHT_x <= PT_x[1];
        PT_RIGHT_y <= PT_y[1];
    end
    else begin
        PT_LEFT_x <= PT_IN_x;
        PT_LEFT_y <= PT_IN_y;
        PT_IN_x <= PT_RIGHT_x;
        PT_IN_y <= PT_RIGHT_y;
        PT_RIGHT_x <= PT_x[2];
        PT_RIGHT_y <= PT_y[2];
    end
end
TYPE t0(.clk(CLK), .IN_x(PT_IN_x), .IN_y(PT_IN_y), .LEFT_x(PT_LEFT_x), .LEFT_y(PT_LEFT_y), 
        .RIGHT_x(PT_RIGHT_x), .RIGHT_y(PT_RIGHT_y), .NEW_x(PT_NEW_x), .NEW_y(PT_NEW_y), .TYPE(PT_TYPE));
//========================================
// type_valid
//========================================
always @(posedge CLK or posedge RST) begin
    if (RST)                type_valid <= 1'b0;
    else if (state == PROC) type_valid <= 1'b1;
    else                    type_valid <= 1'b0;
end
//========================================
// preserve_cnt
//========================================
always @(*) begin
    preserve_cnt_w = preserve_cnt;
    case(state)
        INIT: preserve_cnt_w = cnt[3:2];
        PROC, WAIT: begin
            case(PT_TYPE)
                2'd1:   preserve_cnt_w = add_new ? preserve_cnt_minus_one : preserve_cnt;
                2'd2:   preserve_cnt_w = ((CUT_TYPE_last && !dropped) || (!add_new && state[0])) ? preserve_cnt_add_one : preserve_cnt;
            endcase
        end
    endcase
end
always @(posedge CLK) begin
    if (RST)    preserve_cnt <= 3'd0;
    else        preserve_cnt <= preserve_cnt_w;
end
//========================================
// CUT_TYPE_last
//========================================
always @(posedge CLK or posedge RST) begin
    if (RST)                CUT_TYPE_last <= 1'b0;
    else if (type_valid)    CUT_TYPE_last <= PT_TYPE[1];
    else                    CUT_TYPE_last <= 1'b0;
end
//========================================
// add_new
//========================================
always @(posedge CLK or posedge RST) begin
    if (RST)                add_new <= 1'b0;
    else if (type_valid)    add_new <= PT_TYPE[0] || (CUT_TYPE_last && PT_TYPE[1]) || add_new;
    else                    add_new <= 1'b0;
end
//========================================
// dropped
//========================================
always @(posedge CLK or posedge RST) begin
    if (RST)                dropped <= 1'b0;
    else if (type_valid)    dropped <= PT_TYPE[0] || dropped;
    else                    dropped <= 1'b0;
end
//========================================
// DROP_V, DROP_X, DROP_Y
//========================================
always @(posedge CLK or posedge RST) begin
    if (RST) begin
        DROP_V <= 1'b0;
        DROP_X <= 10'd0;
        DROP_Y <= 10'd0;
    end
    else if (type_valid) begin
        if (PT_TYPE[0]) begin
            DROP_V <= 1'b1;
            DROP_X <= PT_LEFT_x;
            DROP_Y <= PT_LEFT_y;
        end
        else if (state[0] && !add_new && !PT_TYPE[1]) begin
            DROP_V <= 1'b1;
            DROP_X <= PT_NEW_x;
            DROP_Y <= PT_NEW_y;
        end
        else begin
            DROP_V <= 1'b0;
            DROP_X <= 10'd0;
            DROP_Y <= 10'd0;
        end
    end
    else begin
        DROP_V <= 1'b0;
        DROP_X <= 10'd0;
        DROP_Y <= 10'd0;
    end
end

endmodule

module TYPE(
    input               clk,
    input       [9:0]   IN_x,
    input       [9:0]   IN_y,
    input       [9:0]   LEFT_x,
    input       [9:0]   LEFT_y,
    input       [9:0]   RIGHT_x,
    input       [9:0]   RIGHT_y,
    input       [9:0]   NEW_x,
    input       [9:0]   NEW_y,
    output reg  [1:0]   TYPE
);

wire signed [10:0]  tmp1, tmp2, tmp3, tmp4, tmp5, tmp6;
reg  signed [20:0]  xl_yn_w, xl_yr_w, xn_yl_w, xn_yr_w, xr_yl_w, xr_yn_w;
reg  signed [20:0]  xl_yn, xl_yr, xn_yl, xn_yr, xr_yl, xr_yn;
wire                l_r;
wire        [1:0]   l_n, n_r;

assign tmp1 = (LEFT_x - IN_x);
assign tmp2 = (NEW_x - IN_x);
assign tmp3 = (RIGHT_x - IN_x);
assign tmp4 = (LEFT_y - IN_y);
assign tmp5 = (NEW_y - IN_y);
assign tmp6 = (RIGHT_y - IN_y);

always @(*) begin
    xl_yn_w = (tmp1 * tmp5);
    xl_yr_w = (tmp1 * tmp6);
    xn_yl_w = (tmp2 * tmp4);
    xn_yr_w = (tmp2 * tmp6);
    xr_yl_w = (tmp3 * tmp4);
    xr_yn_w = (tmp3 * tmp5);
end

always @(posedge clk) begin
    xl_yn <= xl_yn_w;
    xl_yr <= xl_yr_w;
    xn_yl <= xn_yl_w;
    xn_yr <= xn_yr_w;
    xr_yl <= xr_yl_w;
    xr_yn <= xr_yn_w;
end

assign l_r = (xl_yr < xr_yl) ? 1'b0 : 1'b1;
assign l_n = (xl_yn < xn_yl) ? 2'd0 : (xl_yn > xn_yl) ? 2'd1 : 2'd2;
assign n_r = (xn_yr < xr_yn) ? 2'd0 : (xn_yr > xr_yn) ? 2'd1 : 2'd2;

always @(*) begin
    TYPE = 2'd0;
    case({l_n[1], n_r[1]})
        2'b00: begin
            if (l_r == l_n[0] && l_r == n_r[0])         TYPE = 2'd0; // Continue
            else if (l_r != l_n[0] && l_r != n_r[0])    TYPE = 2'd1; // Concave
            else                                        TYPE = 2'd2; // Cut
        end
        2'b01: begin
            if (l_r == l_n[0])  TYPE = 2'd0;
            else                TYPE = 2'd1;
        end
        2'b10: begin
            if (l_r == n_r[0])  TYPE = 2'd0;
            else                TYPE = 2'd1;
        end
    endcase
end

endmodule