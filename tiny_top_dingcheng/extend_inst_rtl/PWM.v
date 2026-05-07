`include "../../../../Reference/tinyriscv-master/rtl/core/defines.v"
module PWM
(
    input wire clk,
	input wire rst,

    input wire we_i,
    input wire[31:0] addr_i,
    input wire[31:0] data_i,

    output reg[31:0] data_o,

    output wire PWM_0_o,
    output wire PWM_1_o,
    output wire PWM_2_o,
    output wire PWM_3_o
);

localparam A0_ADDR = 24'h00_0000;
localparam A1_ADDR = 24'h01_0000;
localparam A2_ADDR = 24'h02_0000;
localparam A3_ADDR = 24'h03_0000;

localparam B0_ADDR = 24'h10_0000;
localparam B1_ADDR = 24'h11_0000;
localparam B2_ADDR = 24'h12_0000;
localparam B3_ADDR = 24'h13_0000;

localparam C_ADDR = 24'h04_0000;


reg [31:0] A0, A1, A2, A3;
reg [31:0] B0, B1, B2, B3;
reg [31:0] C;

reg [31:0] PWM0_count;
reg [31:0] PWM1_count;
reg [31:0] PWM2_count;
reg [31:0] PWM3_count;
wire PWM0_enable;
wire PWM1_enable;
wire PWM2_enable;
wire PWM3_enable;


always @ (posedge clk) begin
    if(rst == 1'b0) begin
        A0<=32'h0;
        A1<=32'h0;
        A2<=32'h0;
        A3<=32'h0;
        B0<=32'h0;
        B1<=32'h0;
        B2<=32'h0;
        B3<=32'h0;
        C<=32'h0;
    end
    else begin
        if (we_i == `True) begin
            case (addr_i[23:0]) 
                A0_ADDR: A0<=data_i;
                A1_ADDR: A1<=data_i;
                A2_ADDR: A2<=data_i;
                A3_ADDR: A3<=data_i;
                B0_ADDR: B0<=data_i;
                B1_ADDR: B1<=data_i;
                B2_ADDR: B2<=data_i;
                B3_ADDR: B3<=data_i;
                C_ADDR: C<=data_i;
            endcase
        end
    end
end


always @(*) begin
    if (rst == 1'b0) begin
        data_o =32'h0;
    end
    else begin
        case (addr_i[23:0])
            A0_ADDR: data_o=A0;
            A1_ADDR: data_o=A1;
            A2_ADDR: data_o=A2;
            A3_ADDR: data_o=A3;
            B0_ADDR: data_o=B0;
            B1_ADDR: data_o=B1;
            B2_ADDR: data_o=B2;
            B3_ADDR: data_o=B3;
            C_ADDR:  data_o=C ;
            default: data_o=32'h0;
        endcase
    end
end


assign PWM0_enable=C[0];
assign PWM1_enable=C[1];
assign PWM2_enable=C[2];
assign PWM3_enable=C[3];

assign PWM_0_o=PWM0_count<B0?(1'b1):(1'b0);
assign PWM_1_o=PWM1_count<B1?(1'b1):(1'b0);
assign PWM_2_o=PWM2_count<B2?(1'b1):(1'b0);
assign PWM_3_o=PWM3_count<B3?(1'b1):(1'b0);

always @ (posedge clk) begin
    if(rst == 1'b0) begin
        PWM0_count<=32'h0;
        PWM1_count<=32'h0;
        PWM2_count<=32'h0;
        PWM3_count<=32'h0;
    end
    else begin
        if(PWM0_enable) begin
            if(PWM0_count>=A0) begin
                PWM0_count<=32'h0;    
            end
            else begin
                PWM0_count<=PWM0_count+32'h1;
            end
        end

        if(PWM1_enable) begin
            if(PWM1_count>=A1) begin
                PWM1_count<=32'h0;    
            end
            else begin
                PWM1_count<=PWM1_count+32'h1;
            end
        end

        if(PWM2_enable) begin
            if(PWM2_count>=A2) begin
                PWM2_count<=32'h0;
            end
            else begin
                PWM2_count<=PWM2_count+32'h1;
            end
        end

        if(PWM3_enable) begin
            if(PWM3_count>=A3) begin
                PWM3_count<=32'h0;    
            end
            else begin
                PWM3_count<=PWM3_count+32'h1;
            end
        end
    end
end



endmodule
