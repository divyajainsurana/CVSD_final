`define AVE_TRUNC

module Box(
    input                       clk,
    input                     rst_n,
    input                   start_i,
    input      [8*8-1 : 0] target_i,
    input      [8*8-1 : 0]    ref_i,
    output reg              valid_o,
    output reg       [7:0]     mv_o
);

integer i;
genvar ig;


reg  [1:0] start_i_buf;
wire [1:0] n_start_i_buf;
assign n_start_i_buf = {start_i_buf[0], start_i};

// stage 1
wire [8:0]  minus [7:0];
wire [7:0]    abs [7:0];
reg  [7:0] stage1 [7:0];

generate
    for (ig = 0; ig < 8; ig = ig+1) assign minus[ig] = {1'b0, target_i[ig*8 +: 8]} - {1'b0, ref_i[ig*8 +: 8]};
    for (ig = 0; ig < 8; ig = ig+1) assign abs[ig] = minus[ig][8] ? ~minus[ig][7:0] + 8'd1 : minus[ig][7:0];
endgenerate

//stage 2
wire [7:0] n_stage2 [1:0];
reg  [7:0]   stage2 [1:0];
generate
    for (ig = 0; ig < 2; ig = ig+1) AVE4 ave4_2 ( .in({stage1[4*ig], stage1[4*ig +1], stage1[4*ig+2], stage1[4*ig+3]}), .out(n_stage2[ig]) );
endgenerate

// stage 3
reg  [10:0] MAE;
wire [10:0] n_MAE;
wire [ 7:0] batch_final;
reg  [ 3:0] batch;
wire [ 3:0] n_batch;

AVE2 ave2_31 (.in({stage2[0], stage2[1]}), .out(batch_final) );
assign n_batch = batch[2:0] ? batch + 3'd1 : {3'b0, start_i_buf[1]};
assign n_MAE   = batch[2:0] ? MAE + {3'd0, batch_final} : 
                 start_i_buf[1] ? {3'd0, batch_final} : 11'd0;

reg  [7:0] best, n_best, n_mv_o;
reg  [3:0] mv_row, mv_col, n_mv_row, n_mv_col;
wire       n_valid_o;


assign n_valid_o   = batch[3] && mv_row == 4'd4 && mv_col == 4'd4;

always @(*) begin
    if(batch[3]) begin
        if (mv_row == 4'd4 && mv_col == 4'd4)n_best = 8'hff;
        else n_best = (MAE[10:3] < best) ? MAE[10:3] : best;

        n_mv_o = (MAE[10:3] < best) ? {mv_row, mv_col} : mv_o;

        n_mv_col = (mv_col == 4'd4) ? 4'b1101 : mv_col + 4'd1;
        if(mv_col == 4'd4)n_mv_row = (mv_row == 4'd4) ? 4'b1101 : mv_row + 4'd1;
        else n_mv_row = mv_row;

    end else begin
        n_best = best;
        n_mv_o = mv_o;
        n_mv_row = mv_row;
        n_mv_col = mv_col;
    end
end

always @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        for(i = 0; i <8; i = i+1)stage1[i] <= 0;
        for(i = 0; i <2; i = i+1)stage2[i] <= 11'h7ff;
        MAE   <= 0;
        batch <= 3'd0;

        start_i_buf <= 3'b0;
        batch       <= 3'b0;
        best        <= 8'hff;
        mv_row      <= 4'b1101;
        mv_col      <= 4'b1101;
        valid_o     <= 1'b0;
        mv_o        <= 8'b0;
    end else begin
        for(i = 0; i <8; i = i+1)stage1[i] <= abs[i];
        for(i = 0; i <2; i = i+1)stage2[i] <= n_stage2[i];
        MAE   <= n_MAE;
        batch <= n_batch;

        start_i_buf <= n_start_i_buf;
        batch       <= n_batch;
        best        <= n_best;
        mv_row      <= n_mv_row;
        mv_col      <= n_mv_col;
        mv_o        <= n_mv_o;
        valid_o     <= n_valid_o;
    end
end

endmodule


module AVE2 #(parameter WIDTH = 8)(
    input  [2*WIDTH-1 : 0] in,
    output   [WIDTH-1 : 0] out
);
    `ifdef AVE_TRUNC
    wire [WIDTH : 0] add;
    assign add = {1'b0, in[WIDTH-1 : 0]} + {1'b0, in[2*WIDTH-1 : WIDTH]};
    assign out = add[WIDTH:1];
    `else
    assign out = in[WIDTH-1 : 0] > in[2*WIDTH-1 : WIDTH] ? in[WIDTH-1 : 0] : in[2*WIDTH-1 : WIDTH];
    `endif
endmodule

module AVE4 #(parameter WIDTH = 8)(
    input  [4*WIDTH-1 : 0] in,
    output   [WIDTH-1 : 0] out
);
    wire [2*WIDTH-1 : 0] inner;

    AVE2 #(.WIDTH(WIDTH)) ave1 (.in(in[2*WIDTH-1 :       0]), .out(inner[  WIDTH-1 :     0]) );
    AVE2 #(.WIDTH(WIDTH)) ave2 (.in(in[4*WIDTH-1 : 2*WIDTH]), .out(inner[2*WIDTH-1 : WIDTH]) );
    AVE2 #(.WIDTH(WIDTH)) ave3 (.in(                  inner), .out(                     out) );
endmodule