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

// control registers

reg  [3:0] framenumber_r, framenumber_w // current frame number - can be from 1 to 10

reg [3:0] pixelnumber_r, pixelnumber_w // current reading pixel in 8*8 block 
reg [2:0] row_r, row_w // row of current reading pixel
reg [2:0] column_r, column_w //column of current reading pixel

// state control register=========================
always @(*) begin
	framenumber_w   = framenumber_r;
	pixelnumber_w   = pixelnumber_r;
	row_w     = row_r;
	column_w  = column_r;
	if (pixel_valid | (framenumber_r < 10)) begin	
		pixelnumber_w = pixelnumber_r + 1;
		if (pixelnumber_r ==7) begin
			row_w = row_r + 1;
			pixelnumber_r = 0;
			if (row_r == 7) begin
				row_w = 0;
				if(column_r <= 55) begin
					column_w = column_r +8;
			end
			if (column_r == 63 && row ==7)
				framenumber_w = framenumber_r +1;
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
			framenumber_r   <= 0;
			pixelnumber_r <= 0;
			row_r     <= 0;
			column_r <=0;
		end 
		else begin
			framenumber_r   <= frame_w;
			pixelnumber_r <= incount_w;
			row_r     <= row_w;
			column_r <= column_w;
		end
	end


endmodule