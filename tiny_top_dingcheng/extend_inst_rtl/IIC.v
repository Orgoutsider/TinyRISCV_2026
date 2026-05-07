//`include "defines.v"
`include "../../../../Reference/tinyriscv-master/rtl/core/defines.v"

module IIC
#(parameter [31:0] clk_interval=200)//original 3200 800*20ns=16us/SCL LM75 min SCL 2.5us
(
	input wire clk,
	input wire rst,

    input wire we_i,
	input wire[31:0] addr_i,
    input wire[31:0] data_i,

    output reg[31:0] data_o,

	inout i2c_sda,
	output reg i2c_scl
);

localparam IIC_STATE_ADDR= 24'h0_0000;
localparam DEVICE_ADDR 	 = 24'h1_0000;
localparam DATA_OUT_ADDR = 24'h2_0000;
localparam DATA_IN_ADDR  = 24'h3_0000;

localparam [4:0] S_IDLE		 	 	= 4'b0000;
localparam [4:0] S_W_START		 	= 4'b0001;
localparam [4:0] S_W_ADDR_SET		= 4'b0010;
localparam [4:0] S_W_ADDR_ACK 		= 4'b0011;
localparam [4:0] S_W_DATA_SET 	 	= 4'b0100;
localparam [4:0] S_W_DATA_ACK 		= 4'b0101;
localparam [4:0] S_W_END	 		= 4'b0110;
localparam [4:0] S_R_START		 	= 4'b0111;
localparam [4:0] S_R_ADDR_SET 	 	= 4'b1000;
localparam [4:0] S_R_ADDR_ACK 		= 4'b1001;
localparam [4:0] S_R_DATA_SET1 	 	= 4'b1010;
localparam [4:0] S_R_DATA_ACK1  	= 4'b1011;
localparam [4:0] S_R_DATA_SET2 	 	= 4'b1100;
localparam [4:0] S_R_DATA_ACK2  	= 4'b1101;
localparam [4:0] S_R_END		 	= 4'b1110;

reg [31:0] IIC_STATE;
reg [31:0] IIC_DEVICE_ADDR;
reg [31:0] IIC_DATA_OUT;
reg [31:0] IIC_DATA_IN;

reg [4:0] state;
reg [31:0] clk_count;
reg [7:0] send_data;
reg [3:0] shift_count;

reg [2:0] i2c_scl_inner;
wire i2c_sda_i;
reg i2c_sda_t;
reg i2c_sda_o;


assign i2c_sda_i=i2c_sda;
assign i2c_sda=(i2c_sda_t)?(i2c_sda_o):(1'bz);


always @ (*) begin
	if(clk_count==32'd0) begin
		i2c_scl_inner=3'd0;
	end
	else if(clk_count==(clk_interval>>2)) begin
		i2c_scl_inner=3'd1;
	end
	else if(clk_count==(clk_interval>>1)) begin
		i2c_scl_inner=3'd2;
	end
	else if(clk_count==( (clk_interval>>2)+(clk_interval>>1) )) begin
		i2c_scl_inner=3'd3;
	end
	else begin
		i2c_scl_inner=3'd4;
	end
end

always @ (posedge clk) begin
    if(rst == 1'b0) begin
		clk_count<=32'd0;
	end
	else begin
//		if(state==S_IDLE) begin
//			clk_count<=32'd0;
//		end
//		else begin
			if(clk_count>=clk_interval-1) begin
				clk_count<=32'd0;
			end
			else begin
				clk_count<=clk_count+32'd1;
			end
//		end
	end
end

always @ (posedge clk) begin
    if(rst == 1'b0) begin
		i2c_scl<=1'b1;
	end
	else begin
//		if(state==S_IDLE) begin
//			i2c_scl<=1'b1;
//		end
//		else begin
			if(clk_count>=	(clk_interval>>1)) begin
				i2c_scl<=1'b0;
			end
			else begin
				i2c_scl<=1'b1;
			end
//		end
	end
end


always @ (posedge clk) begin
    if(rst == 1'b0) begin
		state<=S_IDLE;	
		shift_count<=4'd0;
		i2c_sda_t<=1'b1;
		i2c_sda_o<=1'b1;
		send_data<=8'd0;
	end
	else begin
		case(state)
		S_IDLE:begin
			if(we_i == `True) begin
				if(addr_i[23:0] == DATA_OUT_ADDR) begin
					state<=S_W_START;
					shift_count<=4'd0;
					i2c_sda_t<=1'b1;
					i2c_sda_o<=1'b1;
					send_data<=IIC_DEVICE_ADDR[7:0] | 1'b0;
				end
				else if(addr_i[23:0] == DATA_IN_ADDR) begin
					state<=S_R_START;
					shift_count<=4'd0;
					i2c_sda_t<=1'b1;
					i2c_sda_o<=1'b1;
					send_data<=IIC_DEVICE_ADDR[7:0] | 1'b1;
				end
			end
			else begin
				state<=S_IDLE;	
				shift_count<=4'd0;
				i2c_sda_t<=1'b1;
				i2c_sda_o<=1'b1;
				send_data<=8'd0;
			end
		end
		S_W_START:begin
			if(i2c_scl_inner==3'd1) begin
				state<=S_W_ADDR_SET;
				i2c_sda_o<=1'b0;
			end
		end
		S_W_ADDR_SET:begin
			if(i2c_scl_inner==3'd3) begin
				if(shift_count<4'd8) begin
					state<=S_W_ADDR_SET;
					i2c_sda_t<=1'b1;
					i2c_sda_o<=send_data[7];
					shift_count<=shift_count+4'd1;
					send_data<={send_data[6:0],1'b0};
				end
				else begin
					state<=S_W_ADDR_ACK;
					shift_count<=4'd0;
					i2c_sda_t<=1'b0;
					i2c_sda_o<=1'b0;
				end				
			end	
		end
		S_W_ADDR_ACK:begin
			if(i2c_scl_inner==3'd1) begin
				state<=S_W_DATA_SET;
				send_data<=IIC_DATA_OUT[7:0];
			end
		end
		S_W_DATA_SET:begin
			if(i2c_scl_inner==3'd3) begin
				if(shift_count<4'd8) begin
					state<=S_W_DATA_SET;
					i2c_sda_t<=1'b1;
					i2c_sda_o<=send_data[7];
					shift_count<=shift_count+4'd1;
					send_data<={send_data[6:0],1'b0};
				end
				else begin
					state<=S_W_DATA_ACK;
					shift_count<=4'd0;
					i2c_sda_t<=1'b0;
					i2c_sda_o<=1'b0;
				end
			end	
		end
		S_W_DATA_ACK:begin
			if(i2c_scl_inner==3'd3) begin
				state<=S_W_END;
				i2c_sda_t<=1'b1;
				i2c_sda_o<=1'b0;
			end
		end
		S_W_END:begin
			if(i2c_scl_inner==3'd1) begin
				state<=S_IDLE;
				shift_count<=4'd0;
				i2c_sda_t<=1'b1;
				i2c_sda_o<=1'b1;
				send_data<=8'd0;
			end
		end



		S_R_START:begin
			if(i2c_scl_inner==3'd1) begin
				state<=S_R_ADDR_SET;
				i2c_sda_o<=1'b0;
			end
		end
		S_R_ADDR_SET:begin
			if(i2c_scl_inner==3'd3) begin
				if(shift_count<4'd8) begin
					state<=S_R_ADDR_SET;
					i2c_sda_t<=1'b1;
					i2c_sda_o<=send_data[7];
					shift_count<=shift_count+4'd1;
					send_data<={send_data[6:0],1'b0};
				end
				else begin
					state<=S_R_ADDR_ACK;
					shift_count<=4'd0;
					i2c_sda_t<=1'b0;
					i2c_sda_o<=1'b0;
				end	
			end
		end
		S_R_ADDR_ACK:begin
			if(i2c_scl_inner==3'd1) begin
				state<=S_R_DATA_SET1;
			end
		end
		S_R_DATA_SET1:begin
			if(i2c_scl_inner==3'd3) begin
				if(shift_count<4'd8) begin
					i2c_sda_t<=1'b0;
					i2c_sda_o<=1'b0;
					state<=S_R_DATA_SET1;
					shift_count<=shift_count+4'd1;
				end
				else begin
					i2c_sda_t<=1'b1;
					i2c_sda_o<=1'b0;
					state<=S_R_DATA_ACK1;
					shift_count<=4'd0;
				end	
			end
		end
		S_R_DATA_ACK1:begin
			if(i2c_scl_inner==3'd1) begin
				state<=S_R_DATA_SET2;
			end
		end
		S_R_DATA_SET2:begin
			if(i2c_scl_inner==3'd3) begin
				if(shift_count<4'd8) begin
					i2c_sda_t<=1'b0;
					i2c_sda_o<=1'b0;
					state<=S_R_DATA_SET2;
					shift_count<=shift_count+4'd1;
				end
				else begin
					i2c_sda_t<=1'b1;
					i2c_sda_o<=1'b1;
					state<=S_R_DATA_ACK2;
					shift_count<=4'd0;
				end	
			end
		end
		S_R_DATA_ACK2:begin
			if(i2c_scl_inner==3'd3) begin
				state<=S_R_END;
				i2c_sda_t<=1'b1;
				i2c_sda_o<=1'b0;
			end
		end
		S_R_END:begin
			if(i2c_scl_inner==3'd1) begin
				state<=S_IDLE;
				shift_count<=4'd0;
				i2c_sda_t<=1'b1;
				i2c_sda_o<=1'b1;
				send_data<=8'd0;
			end
		end

		default:begin
			state<=S_IDLE;	
			shift_count<=4'd0;
			i2c_sda_t<=1'b1;
			i2c_sda_o<=1'b1;
			send_data<=8'd0;
		end
		endcase
	end
end


always @ (posedge clk) begin
    if(rst == 1'b0) begin
		IIC_STATE<=`IIC_IDLE;
		IIC_DEVICE_ADDR<=32'h0;
		IIC_DATA_OUT<=32'h0;
		IIC_DATA_IN<=32'h0;
	end
	else begin
		if(we_i == `True) begin
			case(addr_i[23:0])
			IIC_STATE_ADDR: IIC_STATE<=data_i;
			DEVICE_ADDR   : IIC_DEVICE_ADDR<=data_i;
			DATA_OUT_ADDR : begin 
				IIC_DATA_OUT<=data_i;
				IIC_STATE<=`IIC_WRITE;
			end
			DATA_IN_ADDR  : begin 
				IIC_DATA_IN<=data_i;
				IIC_STATE<=`IIC_READ;
			end
			endcase
		end
		else begin
			if(state==S_W_END || state==S_R_END) begin
				if(i2c_scl_inner==3'd1) begin
					IIC_STATE<=`IIC_IDLE;
				end
			end
			else if( state==S_R_DATA_SET1 || state==S_R_DATA_SET2 ) begin
				if(i2c_scl_inner==3'd1) begin
					IIC_DATA_IN<={IIC_DATA_IN[30:0],i2c_sda_i};
				end
			end
		end
	end
end



always @(*) begin
	if (rst == 1'b0) begin
        data_o =32'h0;
    end
	else begin
		case(addr_i[23:0])
		IIC_STATE_ADDR: data_o=IIC_STATE;
		DEVICE_ADDR   : data_o=IIC_DEVICE_ADDR;
		DATA_OUT_ADDR : data_o=IIC_DATA_OUT;
		DATA_IN_ADDR  : data_o=IIC_DATA_IN;
		default:data_o=32'h0;
		endcase
	end
end



endmodule

