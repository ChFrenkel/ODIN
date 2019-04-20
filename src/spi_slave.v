// Copyright (C) 2016-2019 Université catholique de Louvain (UCLouvain), Belgium.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 2.0 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-2.0/. The software, hardware and materials
// distributed under this License are provided in the hope that it will be useful
// on an as is basis, without warranties or conditions of any kind, either
// expressed or implied; without even the implied warranty of merchantability or
// fitness for a particular purpose. See the Solderpad Hardware License for more
// detailed permissions and limitations.
//------------------------------------------------------------------------------
//
// "spi_slave.v" - ODIN SPI slave module
// 
// Project: ODIN - An online-learning digital spiking neuromorphic processor
//
// Author:  C. Frenkel, Université catholique de Louvain (UCLouvain), 04/2017
//
// Cite/paper: C. Frenkel, M. Lefebvre, J.-D. Legat and D. Bol, "A 0.086-mm² 12.7-pJ/SOP 64k-Synapse 256-Neuron Online-Learning
//             Digital Spiking Neuromorphic Processor in 28-nm CMOS," IEEE Transactions on Biomedical Circuits and Systems,
//             vol. 13, no. 1, pp. 145-158, 2019.
//
//------------------------------------------------------------------------------


module spi_slave #(
    parameter N = 256,
    parameter M = 8
)(

    // Global inputs -----------------------------------------
    input  wire                 RST_async,

    // SPI slave interface ------------------------------------
    input  wire                 SCK,
    output wire                 MISO,
    input  wire                 MOSI,

    // Control interface for readback -------------------------
    output reg                  CTRL_READBACK_EVENT,
    output reg                  CTRL_PROG_EVENT,
    output reg  [      2*M-1:0] CTRL_SPI_ADDR,
    output reg  [          1:0] CTRL_OP_CODE,
    output reg  [      2*M-1:0] CTRL_PROG_DATA,
    input  wire [         31:0] SYNARRAY_RDATA,
    input  wire [        127:0] NEUR_STATE,

    // Configuration registers output -------------------------
    output reg                  SPI_GATE_ACTIVITY,
    output reg                  SPI_OPEN_LOOP,
    output reg  [        N-1:0] SPI_SYN_SIGN,
    output reg  [         19:0] SPI_BURST_TIMEREF,
    output reg                  SPI_OUT_AER_MONITOR_EN,
    output reg                  SPI_AER_SRC_CTRL_nNEUR,
    output reg  [        M-1:0] SPI_MONITOR_NEUR_ADDR,
    output reg  [        M-1:0] SPI_MONITOR_SYN_ADDR,
    output reg                  SPI_UPDATE_UNMAPPED_SYN,
	output reg                  SPI_PROPAGATE_UNMAPPED_SYN,
	output reg                  SPI_SDSP_ON_SYN_STIM
); 

	//----------------------------------------------------------------------------------
	//	REG & WIRES :
	//----------------------------------------------------------------------------------
    
	reg  [5:0]     spi_cnt;
    
    wire [   31:0] readback_weight;
    wire [  127:0] readback_neuron;
	
	reg  [19:0]    spi_shift_reg_out, spi_shift_reg_in;
    reg  [19:0]    spi_data, spi_addr;
    
    genvar i;
    

	//----------------------------------------------------------------------------------
	//	SPI circuitry
	//----------------------------------------------------------------------------------

	// SPI counter
	always @(negedge SCK, posedge RST_async)
		if      (RST_async)        spi_cnt <= 6'd0;
        else if (spi_cnt == 6'd39) spi_cnt <= 6'd0;
		else                       spi_cnt <= spi_cnt + 6'd1;
        
    always @(negedge SCK, posedge RST_async)
		if      (RST_async)        spi_addr <= 20'd0;
		else if (spi_cnt == 6'd19) spi_addr <= spi_shift_reg_in[19:0];
        else                       spi_addr <= spi_addr;
	
    always @(posedge SCK)
        spi_shift_reg_in <= {spi_shift_reg_in[18:0], MOSI};
        
	
	// SPI shift register
	always @(negedge SCK, posedge RST_async)
        if (RST_async) begin
            spi_shift_reg_out   <= 20'b0;
            CTRL_READBACK_EVENT <= 1'b0;
            CTRL_PROG_EVENT     <= 1'b0;
            CTRL_SPI_ADDR       <= {(2*M){1'b0}};
            CTRL_OP_CODE        <= 2'b0;
            CTRL_PROG_DATA      <= {(2*M){1'b0}};
		end else if (spi_shift_reg_in[19] && (spi_cnt == 6'd19)) begin
            spi_shift_reg_out   <= {spi_shift_reg_out[18:0], 1'b0};
            CTRL_READBACK_EVENT <= (spi_shift_reg_in[2*M+1:2*M] != 2'b0);
            CTRL_PROG_EVENT     <= 1'b0;
            CTRL_SPI_ADDR       <= spi_shift_reg_in[2*M-1:  0];
            CTRL_OP_CODE        <= spi_shift_reg_in[2*M+1:2*M];
            CTRL_PROG_DATA      <= {(2*M){1'b0}};
		end else if (spi_shift_reg_in[18] && (spi_cnt == 6'd19)) begin
            spi_shift_reg_out   <= 20'b0;
            CTRL_READBACK_EVENT <= 1'b0;
            CTRL_PROG_EVENT     <= 1'b0;
            CTRL_SPI_ADDR       <= spi_shift_reg_in[2*M-1:  0];
            CTRL_OP_CODE        <= spi_shift_reg_in[2*M+1:2*M];
            CTRL_PROG_DATA      <= {(2*M){1'b0}};
		end else if (spi_addr[19] && (spi_cnt == 6'd31)) begin
            spi_shift_reg_out   <= (CTRL_OP_CODE == 2'b10) ? {readback_weight[7:0],12'b0} : ((CTRL_OP_CODE == 2'b01) ? {readback_neuron[7:0],12'b0} : {spi_shift_reg_out[18:0], 1'b0}); 
            CTRL_READBACK_EVENT <= 1'b0;
            CTRL_PROG_EVENT     <= 1'b0;
            CTRL_SPI_ADDR       <= CTRL_SPI_ADDR;
            CTRL_OP_CODE        <= CTRL_OP_CODE;
            CTRL_PROG_DATA      <= {(2*M){1'b0}};
		end else if (spi_addr[18] && (spi_cnt == 6'd39)) begin
            spi_shift_reg_out   <= {spi_shift_reg_out[18:0], 1'b0};
            CTRL_READBACK_EVENT <= 1'b0;
            CTRL_PROG_EVENT     <= (CTRL_OP_CODE != 2'b0);
            CTRL_SPI_ADDR       <= CTRL_SPI_ADDR;
            CTRL_OP_CODE        <= CTRL_OP_CODE;
            CTRL_PROG_DATA      <= spi_shift_reg_in[2*M-1:0];
		end else begin
            spi_shift_reg_out   <= {spi_shift_reg_out[18:0], 1'b0};
            CTRL_READBACK_EVENT <= CTRL_READBACK_EVENT;
            CTRL_PROG_EVENT     <= 1'b0;
            CTRL_SPI_ADDR       <= CTRL_SPI_ADDR;
            CTRL_OP_CODE        <= CTRL_OP_CODE;
            CTRL_PROG_DATA      <= CTRL_PROG_DATA;
        end
         
    assign readback_weight = SYNARRAY_RDATA >> (({3'b0,CTRL_SPI_ADDR[2*M-2:2*M-3]} << 3));
    assign readback_neuron =     NEUR_STATE >> (({3'b0,CTRL_SPI_ADDR[2*M-1:  M  ]} << 3));
    
	// SPI MISO
	assign MISO = spi_shift_reg_out[19];

    
	//----------------------------------------------------------------------------------
	//	Output config. registers
	//----------------------------------------------------------------------------------
  
    //SPI_GATE_ACTIVITY - 1 bit - address 0
    always @(posedge SCK)
        if   (!spi_addr[17] && !spi_addr[16] && (spi_addr[15:0] == 16'd0) && (spi_cnt == 6'd39))    SPI_GATE_ACTIVITY <= MOSI;
        else                                                                                        SPI_GATE_ACTIVITY <= SPI_GATE_ACTIVITY;
        
    //SPI_OPEN_LOOP - 1 bit - address 1
    always @(posedge SCK)
        if   (!spi_addr[17] && !spi_addr[16] && (spi_addr[15:0] == 16'd1) && (spi_cnt == 6'd39))   SPI_OPEN_LOOP <= MOSI;
        else                                                                                       SPI_OPEN_LOOP <= SPI_OPEN_LOOP;
    
    //SPI_SYN_SIGN - 256 bits - addresses 2 to 17
    generate
        for (i=0; i<(N>>4); i=i+1) begin
            always @(posedge SCK)
                if   (!spi_addr[17] && !spi_addr[16] && (spi_addr[15:0] == (16'd2+i)) && (spi_cnt == 6'd39)) SPI_SYN_SIGN[16*i+15:16*i] <= {spi_shift_reg_in[14:0], MOSI};
                else                                                                                         SPI_SYN_SIGN[16*i+15:16*i] <= SPI_SYN_SIGN[16*i+15:16*i];
        end
    endgenerate
    
    //SPI_BURST_TIMEREF - 20 bits - address 18
    always @(posedge SCK)
        if   (!spi_addr[17] && !spi_addr[16] && (spi_addr[15:0] == 16'd18) && (spi_cnt == 6'd39))  SPI_BURST_TIMEREF <= {spi_shift_reg_in[18:0], MOSI};
        else                                                                                       SPI_BURST_TIMEREF <= SPI_BURST_TIMEREF;
    
    //SPI_AER_SRC_CTRL_nNEUR - 1 bit - address 19
    always @(posedge SCK)
        if   (!spi_addr[17] && !spi_addr[16] && (spi_addr[15:0] == 16'd19) && (spi_cnt == 6'd39))  SPI_AER_SRC_CTRL_nNEUR <= MOSI;
        else                                                                                       SPI_AER_SRC_CTRL_nNEUR <= SPI_AER_SRC_CTRL_nNEUR;
    
    //SPI_OUT_AER_MONITOR_EN - 1 bit - address 20
    always @(posedge SCK)
        if   (!spi_addr[17] && !spi_addr[16] && (spi_addr[15:0] == 16'd20) && (spi_cnt == 6'd39))  SPI_OUT_AER_MONITOR_EN <= MOSI;
        else                                                                                       SPI_OUT_AER_MONITOR_EN <= SPI_OUT_AER_MONITOR_EN;
    
    //SPI_MONITOR_NEUR_ADDR - M bit - address 21
    always @(posedge SCK)
        if   (!spi_addr[17] && !spi_addr[16] && (spi_addr[15:0] == 16'd21) && (spi_cnt == 6'd39))  SPI_MONITOR_NEUR_ADDR <= {spi_shift_reg_in[M-2:0], MOSI};
        else                                                                                       SPI_MONITOR_NEUR_ADDR <= SPI_MONITOR_NEUR_ADDR;
    
    //SPI_MONITOR_SYN_ADDR - M bit - address 22
    always @(posedge SCK)
        if   (!spi_addr[17] && !spi_addr[16] && (spi_addr[15:0] == 16'd22) && (spi_cnt == 6'd39))  SPI_MONITOR_SYN_ADDR <= {spi_shift_reg_in[M-2:0], MOSI};
        else                                                                                       SPI_MONITOR_SYN_ADDR <= SPI_MONITOR_SYN_ADDR;

    //SPI_UPDATE_UNMAPPED_SYN - 1 bit - address 23
    always @(posedge SCK)
        if   (!spi_addr[17] && !spi_addr[16] && (spi_addr[15:0] == 16'd23) && (spi_cnt == 6'd39))  SPI_UPDATE_UNMAPPED_SYN <= MOSI;
        else                                                                                       SPI_UPDATE_UNMAPPED_SYN <= SPI_UPDATE_UNMAPPED_SYN;
    
	//SPI_PROPAGATE_UNMAPPED_SYN - 1 bit - address 24
    always @(posedge SCK)
        if   (!spi_addr[17] && !spi_addr[16] && (spi_addr[15:0] == 16'd24) && (spi_cnt == 6'd39))  SPI_PROPAGATE_UNMAPPED_SYN <= MOSI;
        else                                                                                       SPI_PROPAGATE_UNMAPPED_SYN <= SPI_PROPAGATE_UNMAPPED_SYN;
    
	//SPI_SDSP_ON_SYN_STIM - 1 bit - address 25
    always @(posedge SCK)
        if   (!spi_addr[17] && !spi_addr[16] && (spi_addr[15:0] == 16'd25) && (spi_cnt == 6'd39))  SPI_SDSP_ON_SYN_STIM <= MOSI;
        else                                                                                       SPI_SDSP_ON_SYN_STIM <= SPI_SDSP_ON_SYN_STIM; 
	
    /*                                                 *
     * Some address room for other params if necessary *
     *                                                 */

    
    
endmodule
