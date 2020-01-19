`include "Box.v"
`include "Output.v"

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

	// input buffer
	reg pixel_valid_r;
	reg [7:0] pixel_r;

	// state control register
	reg [3:0] current_frame_r, current_frame_w;       // # of current reading frame
	reg [8:0] current_pixel_r, current_pixel_w;   // current reading pixel idx in 8x64 block
	reg [2:0] current_row_r, current_row_w;           // row # of current reading pixels

	// buffer register
	reg [7:0] target_frame_r[4:15][0:63];
	reg [7:0] target_frame_w[4:15][0:63];
	reg [7:0] reference_frame_r[0:16][0:63];
	reg [7:0] reference_frame_w[0:16][0:63];

	// SRAM interface
	reg [8:0] addr_r, addr_w;
	reg       wen_r, wen_w;
	reg       cen_r, cen_w;
	reg [7:0] write_r[0:3];
	reg [7:0] write_w[0:3];
	reg [7:0] read_r[0:3];
	wire [7:0] read[0:3];

	// BOX interface
	reg [7:0] box_ref_r[0:7][0:7];
	reg [7:0] box_ref_w[0:7][0:7];
	reg [7:0] box_tar_r[0:7][0:7];
	reg [7:0] box_tar_w[0:7][0:7];
	reg       start_r, start_w;

	wire [63:0]       box_mv;
	wire [ 7:0]       box_valid;
	wire [8*8-1 : 0] box_ref[0:7];
	wire [8*8-1 : 0] box_tar[0:7];

	integer i, j, k, l, m;
	genvar idx, idx2;

	assign busy = 0;
	generate
		for (idx = 0; idx < 8; idx = idx+1) begin
			for (idx2 = 0; idx2 < 8; idx2 = idx2+1) begin
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
		if (pixel_valid_r | (current_frame_r==10 & current_row_r==0) ) begin
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
		if (pixel_valid_r | (current_frame_r==10 & current_row_r==0) ) begin
			if(!(current_frame_r == 10 && current_row_r == 0))reference_frame_w[16][current_pixel_r[5:0]] = pixel_r;
			if (current_pixel_r[5:0] == 63) begin
				for (i = 0; i < 16; i = i+1) begin
					for (j = 0; j < 64; j = j+1) begin
						reference_frame_w[i][j] = reference_frame_r[i+1][j];
					end
				end
				if (~(current_frame_r==10 & current_row_r==0)) begin
					reference_frame_w[15][63] = pixel_r;
				end
			end
			if (current_frame_r) begin
				if (current_pixel_r[2:0]==3'b111) begin
					for (i = 4; i < 16; i = i+1) begin
						for (j = 0; j < 64; j = j+1) begin
							target_frame_w[i][j] = target_frame_r[i][j[5:0]+6'd1];
						end
					end
				end
				//if (current_pixel_r[0] & ~current_pixel_r[1]) begin
				if (~current_pixel_r[0] & current_pixel_r[1]) begin
					for (i = 0; i < 4; i = i+1) begin
						target_frame_w[15][i*16+3+{27'b0,(current_pixel_r[5:2]+1)>>1}] = read_r[i];
					end
				end
				if (current_pixel_r[5:0]==6'b111111) begin
					for (i = 4; i < 15; i = i+1) begin
						for (j = 0; j < 64; j = j+1) begin
							target_frame_w[i][j] = target_frame_r[i+1][j[5:0]-6'd7];
						end
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
		if ( (pixel_valid_r & ~(current_frame_w==0 & current_row_w<2) ) | (current_frame_w==10 & current_row_w==0) ) begin
			cen_w = current_pixel_w[1];
		end
		wen_w = ~current_pixel_w[0];
		if (pixel_valid_r | (current_frame_r==10 & current_row_r==0)) begin
			if (~current_pixel_r[1] & current_pixel_r[0]) addr_w = addr_r + 1;
		end
		for (i = 0; i < 4; i = i+1) begin
			write_w[i] = reference_frame_r[0][i*16+$signed({28'b0, current_pixel_r[5:2]})];
		end
	end

	// box interface=================================
	always @(*) begin
		start_w = 0;
		for (i = 0; i < 8; i = i+1) begin
			for (j = 0; j < 8; j = j+1) begin
				box_ref_w[i][j] = box_ref_r[i][j];
				box_tar_w[i][j] = box_tar_r[i][j];
			end
		end
		// start
		if ( (pixel_valid_r && current_frame_r) | (current_frame_r==10 & current_row_r==0) ) begin
			if (~(current_frame_r==1 & current_row_r==0) ) begin
				if (current_pixel_r[2:0]==0) begin
					start_w = ~current_pixel_r[0];
				end
			end
		end
		// box_ref
		for (i = 0; i < 8; i = i+1) begin // box idx
			for (k = 0; k < 8; k = k+1) begin // column idx of 8 input
				box_ref_w[i][k] = reference_frame_r[8-{1'b0,current_pixel_r[8:6]}+{1'b0,current_pixel_r[2:0]}][i*8+k];
			end
		end
		// box_tar
		for (i = 0; i < 8; i = i+1) begin // box idx
				for (k = 0; k < 8; k = k+1) begin // column idx of 8 input
					if (     ($signed({29'd0, current_pixel_r[5:3]}) < 3-k-i*8) 
						  || ($signed({29'd0, current_pixel_r[5:3]}) > 63 +3 -k -i*8) 
					      || (current_row_r==1 & ($signed({29'd0, current_pixel_r[8:6]}) +$signed({29'd0, current_pixel_r[2:0]}) < 3 )) 
						  || (current_row_r==0 & ($signed({29'd0, current_pixel_r[8:6]}) +$signed({29'd0, current_pixel_r[2:0]}) > 3 +7 )) ) begin
						box_tar_w[i][k] = 0;
					end 
					else box_tar_w[i][k] = target_frame_r[$signed({29'd0, current_pixel_r[2:0]})+4][i*8+k];
				end
		end
	end

//======================================================================
//================= Sequential part=====================================
//======================================================================

	// state control register=========================
	always @(posedge clk or negedge rst_n) begin
		if(~rst_n) begin
			current_frame_r       <= 0;
			current_pixel_r     <= 0;
			current_row_r         <= 0;
			pixel_valid_r <= 0;
			pixel_r       <= 0;
		end 
		else begin
			current_frame_r       <= current_frame_w;
			current_pixel_r     <= current_pixel_w;
			current_row_r         <= current_row_w;
			pixel_valid_r <= pixel_valid;
			pixel_r       <= pixel;
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
				read_r[i]  <= 0;
			end
		end 
		else begin
			addr_r <= addr_w;
			wen_r  <= wen_w;
			cen_r  <= cen_w;
			for (i = 0; i < 4; i = i+1) begin
				write_r[i] <= write_w[i];
				read_r[i]  <= read[i];
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