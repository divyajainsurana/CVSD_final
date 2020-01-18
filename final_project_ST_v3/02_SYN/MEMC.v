module MEMC(
    clk,
    rst_n,
    pixel_valid,
    pixel,
    busy,
    mv_valid,
    mv,
    mv_addr
);

	input clk;
	input rst_n;
	input pixel_valid;
	input [7:0] pixel;
	output busy;
	output mv_valid;
	output [7:0] mv;
	output [5:0] mv_addr;

	// state control register
	reg [3:0] current_frame_r, current_frame_w;       // # of current reading frame
	reg [8:0] current_pixel_r, current_pixel_w;   // current reading pixel idx 
	reg [2:0] current_row_r, current_row_w;           // row # of current reading pixels

	// buffer register
	reg [7:0] target_frame_r[0:15][0:63];
	reg [7:0] target_frame_w[0:15][0:63];
	reg [7:0] reference_frame_r[0:16][0:63];
	reg [7:0] reference_frame_w[0:16][0:63];

	// SRAM interface
	reg [8:0] addr_r, addr_w;
	reg       wen_r, wen_w;
	reg       cen_r, cen_w;
	reg [7:0] write_r[0:3];
	reg [7:0] write_w[0:3];
	wire [7:0] read[0:3];

	// BOX interface
	reg [7:0] box_ref_r[0:7][0:31];
	reg [7:0] box_ref_w[0:7][0:31];
	reg [7:0] box_tar_r[0:7][0:31];
	reg [7:0] box_tar_w[0:7][0:31];
	reg       start_r, start_w;

	wire [63:0]       box_mv;
	wire [ 7:0]       box_valid;
	wire [32*8-1 : 0] box_ref[0:7];
	wire [32*8-1 : 0] box_tar[0:7];

	integer i, j, k, l, m;
	genvar idx, idx2;

	assign busy = 0;
	generate
		for (idx = 0; idx < 8; idx = idx+1) begin
			for (idx2 = 0; idx2 < 32; idx2 = idx2+1) begin
				assign box_ref[idx][idx2*8 +: 8] = box_ref_r[idx][idx2];
				assign box_tar[idx][idx2*8 +: 8] = box_tar_r[idx][idx2];
			end
		end
	endgenerate

//======================================================================
//================= Module instantitation===============================
//======================================================================

	generate
    	for(idx = 0; idx < 8; idx = idx +1) begin
        	Box box(.clk(clk), .rst_n(rst_n), 
                	.start_i(start_r), .target_i(box_tar[idx]), .ref_i(box_ref[idx]),
                	.valid_o(box_valid[idx]), .mv_o(box_mv[8*idx +: 8]));
    	end
	endgenerate

	Output out(.clk(clk), .rst_n(rst_n), .valid_i(box_valid[0]), .mv_i(box_mv), .valid_o(mv_valid), .mv_o(mv), .mv_addr_o(mv_addr));

	sram_512x8 sram0(
   		.Q(read[0]),
   		.CLK(clk),
   		.CEN(cen_r),
   		.WEN(wen_r),
   		.A(addr_r),
   		.D(write_r[0])
	);

	sram_512x8 sram1(
   		.Q(read[1]),
   		.CLK(clk),
   		.CEN(cen_r),
   		.WEN(wen_r),
   		.A(addr_r),
   		.D(write_r[1])
	);

	sram_512x8 sram2(
   		.Q(read[2]),
   		.CLK(clk),
   		.CEN(cen_r),
   		.WEN(wen_r),
   		.A(addr_r),
   		.D(write_r[2])
	);

	sram_512x8 sram3(
   		.Q(read[3]),
   		.CLK(clk),
   		.CEN(cen_r),
   		.WEN(wen_r),
   		.A(addr_r),
   		.D(write_r[3])
	);

//======================================================================
//================= Combinational part==================================
//======================================================================

	// state control register=========================
	always @(*) begin
		current_frame_w   = current_frame_r;
		current_pixel_w = current_pixel_r;
		current_row_w     = current_row_r;
		if (pixel_valid | (current_frame_r==10 & current_row_r==0) ) begin
			current_pixel_w = current_pixel_r + 1;
			if (current_pixel_r == 511) begin
				current_row_w = current_row_r + 1;
				if (current_row_r == 5) begin
					current_row_w = 0;
					current_frame_w = current_frame_r + 1;
				end
			end
		end
	end

	// buffer register================================
	always @(*) begin
		for (i = 0; i < 16; i = i+1) begin
			for (j = 0; j < 64; j = j+1) begin
				target_frame_w[i][j]    = target_frame_r[i][j];
			end
		end
		for (i = 0; i < 17; i = i+1) begin
			for (j = 0; j < 64; j = j+1) begin
				reference_frame_w[i][j] = reference_frame_r[i][j];
			end
		end
		if (pixel_valid | (current_frame_r==10 & current_row_r==0) ) begin
			for (j = 0; j < 64; j = j+1) begin
				if (current_pixel_r[5:0] == j & ~(current_frame_r==10 & current_row_r==0) ) begin
					reference_frame_w[16][j] = pixel;
				end
			end
			if (current_pixel_r[5:0] == 63) begin
				for (i = 0; i < 16; i = i+1) begin
					for (j = 0; j < 64; j = j+1) begin
						reference_frame_w[i][j] = reference_frame_r[i+1][j];
					end
				end
				if (~(current_frame_r==10 & current_row_r==0)) begin
					reference_frame_w[15][63] = pixel;
				end
			end
			if (current_frame_r) begin
				if (current_pixel_r[0] & ~current_pixel_r[5]) begin
					for (i = 0; i < 4; i = i+1) begin
						for (j = 0; j < 16; j = j+1) begin
							if (current_pixel_r[4:1] == j) begin
								target_frame_w[15][i*16+j] = read[i];
							end
						end
					end
				end
				if (~current_pixel_r[5] & current_pixel_r[4:0]==5'b11111) begin
					for (i = 0; i < 15; i = i+1) begin
						for (j = 0; j < 64; j = j+1) begin
							target_frame_w[i][j] = target_frame_r[i+1][j];
						end
					end
					for (i = 0; i < 4; i = i+1) begin
						target_frame_w[14][i*16+15] = read[i];
					end
				end
			end
		end
	end

	// SRAM interface================================
	always @(*) begin
		addr_w = addr_r;
		cen_w = 1;
		wen_w = 1;
		for (i = 0; i < 3; i = i+1) begin
			write_w[i] = write_r[i];
		end
		if ( (pixel_valid & ~(current_frame_w==0 & current_row_w<2) ) | (current_frame_w==10 & current_row_w==0) ) begin
			cen_w = current_pixel_w[5];
		end
		wen_w = ~current_pixel_w[0];
		if (pixel_valid | (current_frame_r==10 & current_row_r==0)) begin
			if (~current_pixel_r[5] & current_pixel_r[0]) addr_w = addr_r + 1;
		end
		for (i = 0; i < 4; i = i+1) begin
			for (j = 0; j < 16; j = j+1) begin
				if (current_pixel_w[4:1] == j) begin
					write_w[i] = reference_frame_r[0][i*16+j];
				end
			end
		end
	end

	// box interface=================================
	always @(*) begin
		start_w = 0;
		for (i = 0; i < 8; i = i+1) begin
			for (j = 0; j < 32; j = j+1) begin
				box_ref_w[i][j] = box_ref_r[i][j];
				box_tar_w[i][j] = box_tar_r[i][j];
			end
		end
		// start
		if ( (pixel_valid && current_frame_r) | (current_frame_r==10 & current_row_r==0) ) begin
			if (~(current_frame_r==1 & current_row_r==0) ) begin
				if (current_pixel_r[4:1]!=4'b1111 & current_pixel_r[8:5]!=4'b1111) begin
					start_w = ~current_pixel_r[0];
				end
			end
		end
		// box_ref
		for (i = 0; i < 8; i = i+1) begin // core idx
			for (j = 0; j < 4; j = j+1) begin // row idx of 4x8 input
				for (k = 0; k < 8; k = k+1) begin // column idx of 4x8 input
					for (l = 0; l < 8; l = l+1) begin // vertical mv
						if (current_pixel_r[8:6] == l) begin
							if (current_pixel_r[0]) begin
								box_ref_w[i][j*8+k] = reference_frame_r[8-l+j+4][i*8+k];
							end
							else begin 
								box_ref_w[i][j*8+k] = reference_frame_r[8-l+j][i*8+k];
							end
						end
					end
				end
			end
		end
		// box_tar
		for (i = 0; i < 8; i = i+1) begin // box idx
			for (j = 0; j < 4; j = j+1) begin // row idx of 4x8 input
				for (k = 0; k < 8; k = k+1) begin // column idx of 4x8 input
					for (m = 0; m < 15; m = m+1) begin // horizontal mv
						for (l = 0; l < 15; l = l+1) begin // vertical mv
							if (current_pixel_r[8:5] == l) begin
								if (current_pixel_r[4:1] == m) begin
									if (current_pixel_r[0]) begin
										if ( (m-7+i*8+k < 0) | (m-7+i*8+k > 63) ) begin
											box_tar_w[i][j*8+k] = 0;
										end
										else if (current_row_r==1 & (j+4+l-7 < 0) ) begin
											box_tar_w[i][j*8+k] = 0;
										end
										else if (current_row_r==0 & (j+4+l-7 > 7 ) ) begin
											box_tar_w[i][j*8+k] = 0;
										end
										else box_tar_w[i][j*8+k] = target_frame_r[l[31:1]+j+4][m-7+i*8+k];
									end
									else begin
										if ( (m-7+i*8+k < 0) | (m-7+i*8+k > 63) ) begin
											box_tar_w[i][j*8+k] = 0;
										end
										else if (current_row_r==1 & (j+l-7 < 0) ) begin
											box_tar_w[i][j*8+k] = 0;
										end
										else if (current_row_r==1 & (j+l-7 > 7) ) begin
											box_tar_w[i][j*8+k] = 0;
										end
										else box_tar_w[i][j*8+k] = target_frame_r[l[31:1]+j][m-7+i*8+k];
									end
								end
							end
						end
					end
				end
			end
		end
	end

//======================================================================
//================= Sequential part=====================================
//======================================================================

	// state control register=========================
	always @(posedge clk or negedge rst_n) begin
		if(~rst_n) begin
			current_frame_r   <= 0;
			current_pixel_r <= 0;
			current_row_r     <= 0;
		end 
		else begin
			current_frame_r   <= current_frame_w;
			current_pixel_r <= current_pixel_w;
			current_row_r     <= current_row_w;
		end
	end

	// buffer register=================================
	always @(posedge clk or negedge rst_n) begin
		if(~rst_n) begin
			for (i = 0; i < 16; i = i+1) begin
				for (j = 0; j < 64; j = j+1) begin
					target_frame_r[i][j]    <= 0;
				end
			end
			for (i = 0; i < 17; i = i+1) begin
				for (j = 0; j < 64; j = j+1) begin
					reference_frame_r[i][j] <= 0;
				end
			end
		end 
		else begin
			for (i = 0; i < 16; i = i+1) begin
				for (j = 0; j < 64; j = j+1) begin
					target_frame_r[i][j]    <= target_frame_w[i][j];
				end
			end
			for (i = 0; i < 17; i = i+1) begin
				for (j = 0; j < 64; j = j+1) begin
					reference_frame_r[i][j] <= reference_frame_w[i][j];
				end
			end
		end
	end

	// SRAM interface=================================
	always @(posedge clk or negedge rst_n) begin
		if(~rst_n) begin
			addr_r <= 0;
			wen_r  <= 1;
			cen_r  <= 1;
			for (i = 0; i < 4; i = i+1) begin
				write_r[i] <= 0;
			end
		end 
		else begin
			addr_r <= addr_w;
			wen_r  <= wen_w;
			cen_r  <= cen_w;
			for (i = 0; i < 4; i = i+1) begin
				write_r[i] <= write_w[i];
			end
		end
	end

	// box interface================================
	always @(posedge clk or negedge rst_n) begin
		if(~rst_n) begin
			start_r <= 0;
			for (i = 0; i < 8; i = i+1) begin
				for (j = 0; j < 32; j = j+1) begin
					box_tar_r[i][j] <= 0;
					box_ref_r[i][j] <= 0;
				end
			end
		end 
		else begin
			start_r <= start_w;
			for (i = 0; i < 8; i = i+1) begin
				for (j = 0; j < 32; j = j+1) begin
					box_tar_r[i][j] <= box_tar_w[i][j];
					box_ref_r[i][j] <= box_ref_w[i][j];
				end
			end
		end
	end

endmodule


`define AVE_TRUNC

module Box(
    input                       clk,
    input                     rst_n,
    input                   start_i,
    input      [32*8-1 : 0] target_i,
    input      [32*8-1 : 0]    ref_i,
    output reg               valid_o,
    output reg        [7:0]     mv_o
);

integer i;
genvar ig;

// stage 1
wire [8:0]  minus [31:0];
wire [7:0]    abs [31:0];

`ifdef AVE
reg  [8:0]    stage1 [15:0];
wire [8:0]  n_stage1 [15:0];
`else
reg  [7:0]    stage1 [15:0];
wire [7:0]  n_stage1 [15:0];
`endif
generate
    for (ig = 0; ig < 32; ig = ig+1) assign minus[ig] = {1'b0, target_i[ig*8 +: 8]} - {1'b0, ref_i[ig*8 +: 8]};
    for (ig = 0; ig < 32; ig = ig+1) assign abs[ig] = minus[ig][8] ? ~minus[ig][7:0] + 8'd1 : minus[ig][7:0];
    `ifdef AVE
    for (ig = 0; ig < 16; ig = ig+1) assign n_stage1[ig] = {1'b0, abs[2*ig]} + {1'b0, abs[2*ig+1]};
    `else
    for (ig = 0; ig < 16; ig = ig+1) MAX2 max2_1 ( .in({abs[2*ig], abs[2*ig+1]}), .out(n_stage1[ig]) );
    `endif
endgenerate

//stage 2
`ifdef AVE
wire [10:0]   n_stage2 [3:0];
reg  [10:0]     stage2 [3:0];
`else
wire [ 7:0]   n_stage2 [3:0];
reg  [ 7:0]     stage2 [3:0];
`endif
generate
    `ifdef AVE
    for (ig = 0; ig < 4; ig = ig+1) assign n_stage2[ig] = {1'b0, {1'b0, stage1[4*ig]} + {1'b0, stage1[4*ig+1]}} + {1'b0, {1'b0, stage1[4*ig+2]} + {1'b0, stage1[4*ig+3]}};
    `else
    for (ig = 0; ig < 4; ig = ig+1) MAX4 max4_2 ( .in({stage1[4*ig], stage1[4*ig +1], stage1[4*ig+2], stage1[4*ig+3]}), .out(n_stage2[ig]) );
    `endif
endgenerate

// stage 3
`ifdef AVE
wire [12:0] n_MAE2;
reg  [12:0] MAE1, MAE2;
assign n_MAE2 = {1'b0, {1'b0, stage2[0]} + {1'b0, stage2[1]}} + {1'b0, {1'b0, stage1[2]} + {1'b0, stage1[3]}};
`else
wire [ 7:0] n_MAE2;
reg  [ 7:0] MAE1, MAE2;
MAX4 max4_3 ( .in({stage2[0], stage2[1], stage2[2], stage2[3]}), .out(n_MAE2) );
`endif

// stage 4
reg  [3:0] start_i_buf;
wire [3:0] n_start_i_buf;
wire [7:0] MAE;
reg  [7:0] best, n_best, n_mv_o;
reg  [3:0] mv_row, mv_col, n_mv_row, n_mv_col;
wire       n_valid_o;

`ifdef AVE
wire [13:0] MAE_total;
assign MAE_total = {1'b0, MAE1} + {1'b0, MAE2};
assign MAE = MAE_total[13:6] + {7'b0, MAE_total[5]};
`else
MAX2 max2_4 (.in({MAE1, MAE2}), .out(MAE) );
`endif

assign n_start_i_buf = {start_i_buf[2:0], start_i};
assign n_valid_o   = start_i_buf[3] && mv_row == 4'd7 && mv_col == 4'd7;

always @(*) begin
    if(start_i_buf[3]) begin
        if (mv_row == 4'd7 && mv_col == 4'd7)n_best = 8'hff;
        else n_best = (MAE < best) ? MAE : best;

        n_mv_o = (MAE < best) ? {mv_row, mv_col} : mv_o;

        n_mv_col = (mv_col == 4'd7) ? 4'd9 : mv_col + 4'd1;
        if(mv_col == 4'd7)n_mv_row = (mv_row == 4'd7) ? 4'd9 : mv_row + 4'd1;
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
        `ifdef AVE
        for(i = 0; i <16; i = i+1)stage1[i] <= 9'h1ff;
        for(i = 0; i < 4; i = i+1)stage2[i] <= 11'h7ff;

        MAE1 <= 13'h1fff;
        MAE2 <= 13'h1fff;

        `else
        for(i = 0; i <16; i = i+1)stage1[i] <= 8'hff;
        for(i = 0; i < 4; i = i+1)stage2[i] <= 8'hff;

        MAE1 <= 8'hff;
        MAE2 <= 8'hff;
        `endif

        start_i_buf <= 4'b0;
        best        <= 8'hff;
        mv_row      <= 4'd9;
        mv_col      <= 4'd9;
        valid_o <= 1'b0;
        mv_o    <= 8'b0;
    end else begin
        for(i = 0; i <16; i = i+1)stage1[i] <= n_stage1[i];
        for(i = 0; i < 4; i = i+1)stage2[i] <= n_stage2[i];

        MAE1 <= MAE2;
        MAE2 <= n_MAE2;

        start_i_buf <= n_start_i_buf;
        best        <= n_best;
        mv_row      <= n_mv_row;
        mv_col      <= n_mv_col;
        mv_o        <= n_mv_o;
        valid_o     <= n_valid_o;
    end
end

endmodule


module MAX2 #(parameter WIDTH = 8)(
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

module MAX4 #(parameter WIDTH = 8)(
    input  [4*WIDTH-1 : 0] in,
    output   [WIDTH-1 : 0] out
);
    wire [2*WIDTH-1 : 0] inner;

    MAX2 #(.WIDTH(WIDTH)) max1 (.in(in[2*WIDTH-1 :       0]), .out(inner[  WIDTH-1 :     0]) );
    MAX2 #(.WIDTH(WIDTH)) max2 (.in(in[4*WIDTH-1 : 2*WIDTH]), .out(inner[2*WIDTH-1 : WIDTH]) );
    MAX2 #(.WIDTH(WIDTH)) max3 (.in(                  inner), .out(                     out) );
endmodule

module Output(
    input clk, 
    input rst_n,

    input             valid_i,
    input      [63:0] mv_i,
    output reg        valid_o,
    output     [ 5:0] mv_addr_o,
    output     [ 7:0] mv_o
);

reg  [63:0] buffer;
wire [63:0] n_buffer;

reg  [2:0] mv_row, mv_col;
wire [2:0] n_mv_row, n_mv_col;
wire       n_valid_o;

assign mv_addr_o = {mv_row, mv_col};
assign mv_o      = buffer[7:0];

assign n_valid_o = valid_o        ? mv_col != 3'd7 : valid_i;
assign n_buffer  = valid_o        ? {8'b0, buffer[63:8]} : mv_i;
assign n_mv_col  = valid_o        ? mv_col + 3'd1 : 3'd0;
assign n_mv_row  = mv_col != 3'd7 ? mv_row :
                   mv_row == 3'd5 ? 3'd0 : mv_row + 3'd1;

always @(posedge clk or negedge rst_n) begin
    if(~rst_n) begin
        valid_o <=  1'b0;
        buffer  <= 64'd0;
        mv_row  <=  3'd0;
        mv_col  <=  3'd0;
    end else begin
        valid_o <= n_valid_o;
        buffer  <= n_buffer;
        mv_row  <= n_mv_row;
        mv_col  <= n_mv_col;
    end
end
endmodule

