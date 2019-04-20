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
// "synaptic_core.v" - ODIN synaptic core module
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


module synaptic_core #(
    parameter N = 256,
    parameter M = 8
)(
    
    // Global inputs ------------------------------------------
    input  wire           RSTN_syncn,
    input  wire           CLK,
    
    // Inputs from SPI configuration registers ----------------
    input  wire           SPI_GATE_ACTIVITY_sync,
    input  wire [  N-1:0] SPI_SYN_SIGN, 
    input  wire           SPI_UPDATE_UNMAPPED_SYN,
    
    // Inputs from controller ---------------------------------
    input  wire [    7:0] CTRL_PRE_EN,
    input  wire           CTRL_BIST_REF,
    input  wire           CTRL_SYNARRAY_WE,
    input  wire [   12:0] CTRL_SYNARRAY_ADDR,
    input  wire           CTRL_SYNARRAY_CS,
    input  wire [2*M-1:0] CTRL_PROG_DATA,
    input  wire [2*M-1:0] CTRL_SPI_ADDR,
    
    // Inputs from neurons ------------------------------------
    input  wire [  N-1:0] NEUR_V_UP,
    input  wire [  N-1:0] NEUR_V_DOWN,
    
    // Outputs ------------------------------------------------
    output wire [   31:0] SYNARRAY_RDATA,
    output wire [   31:0] SYNARRAY_WDATA,
    output wire           SYN_SIGN
);

    // Internal regs and wires definitions
    
    wire [   31:0] SYNARRAY_WDATA_int;
    wire [  N-1:0] NEUR_V_UP_int, NEUR_V_DOWN_int;
    wire [  N-2:0] syn_sign_dummy;
    
    genvar i;
    
    
    // SDSP update logic

    generate
        for (i=0; i<8; i=i+1) begin
        
            sdsp_update #(
                .WIDTH(3)
            ) sdsp_update_gen (
                // Inputs
                    // General
                .SYN_PRE(CTRL_PRE_EN[i] & (SPI_UPDATE_UNMAPPED_SYN | SYNARRAY_RDATA[(i<<2)+3])),
                .SYN_BIST_REF(CTRL_BIST_REF),
                    // From neuron
                .V_UP(NEUR_V_UP_int[i]),
                .V_DOWN(NEUR_V_DOWN_int[i]),    
                    // From SRAM
                .WSYN_CURR(SYNARRAY_RDATA[(i<<2)+3:(i<<2)]),
                
                // Output
                .WSYN_NEW(SYNARRAY_WDATA_int[(i<<2)+3:(i<<2)])
		    );
        end
    endgenerate

    assign NEUR_V_UP_int   = NEUR_V_UP   >> ({3'b0,CTRL_SYNARRAY_ADDR[4:0]} << 3);
    assign NEUR_V_DOWN_int = NEUR_V_DOWN >> ({3'b0,CTRL_SYNARRAY_ADDR[4:0]} << 3);
    

    // Updated or configured weights to be written to the synaptic memory

    generate
        for (i=0; i<4; i=i+1) begin
            assign SYNARRAY_WDATA[(i<<3)+7:(i<<3)] = SPI_GATE_ACTIVITY_sync
                                                   ?
                                                       ((i == CTRL_SPI_ADDR[14:13])
                                                       ? ((CTRL_PROG_DATA[M-1:0] & ~CTRL_PROG_DATA[2*M-1:M]) | (SYNARRAY_RDATA[(i<<3)+7:(i<<3)] & CTRL_PROG_DATA[2*M-1:M]))
                                                       : SYNARRAY_RDATA[(i<<3)+7:(i<<3)])
                                                   : SYNARRAY_WDATA_int[(i<<3)+7:(i<<3)];
        end
    endgenerate
    
    
    // Synaptic memory wrapper

    SRAM_8192x32_wrapper synarray_0 (
        
        // Global inputs
        .RSTN       (RSTN_syncn),
        .CK         (CLK),
	
		// Control and data inputs
		.CS         (CTRL_SYNARRAY_CS),
		.WE         (CTRL_SYNARRAY_WE),
		.A			(CTRL_SYNARRAY_ADDR),
		.D			(SYNARRAY_WDATA),
		
		// Data output
		.Q			(SYNARRAY_RDATA)
    );
    
    assign {syn_sign_dummy,SYN_SIGN} = SPI_SYN_SIGN >> CTRL_SYNARRAY_ADDR[12:5];


endmodule




module SRAM_8192x32_wrapper (

    // Global inputs
    input         RSTN,                     // Reset
    input         CK,                       // Clock (synchronous read/write)

    // Control and data inputs
    input         CS,                       // Chip select (active low) (init low)
    input         WE,                       // Write enable (active low)
    input  [12:0] A,                        // Address bus 
    input  [31:0] D,                        // Data input bus (write)

    // Data output
    output [31:0] Q                         // Data output bus (read)   
);


    /*
     *  Simple behavioral code for simulation, to be replaced by a 8192-word 32-bit SRAM macro 
     *  or Block RAM (BRAM) memory with the same format for FPGA implementations.
     */      
        reg [31:0] SRAM[8191:0];
        reg [31:0] Qr;
        always @(posedge CK) begin
            Qr <= CS ? SRAM[A] : Qr;
            if (CS & WE) SRAM[A] <= D;
        end
        assign Q = Qr;

    
endmodule
