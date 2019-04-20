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
// "sdsp_update.v" - ODIN SDSP update logic module
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


module sdsp_update #(
    parameter WIDTH = 3
)(
    // Inputs
        // General
    input  wire             SYN_PRE,
    input  wire             SYN_BIST_REF,
        // From neuron
    input  wire             V_UP,
    input  wire             V_DOWN,    
        // From SRAM
    input  wire [WIDTH:0] WSYN_CURR,
    
	// Output
	output reg  [WIDTH:0] WSYN_NEW
);
    
    
    wire w_lt_half;
    wire do_up, do_down;
    wire overflow;
    
    assign w_lt_half = SYN_PRE & ~WSYN_CURR[WIDTH-1];
    assign do_up     = SYN_PRE & (SYN_BIST_REF ? ~w_lt_half : V_UP);
    assign do_down   = SYN_PRE & (SYN_BIST_REF ?  w_lt_half : V_DOWN);
    assign overflow  = SYN_PRE & ((do_up && (&WSYN_CURR[WIDTH-1:0])) || (do_down && (~|WSYN_CURR[WIDTH-1:0]))); 

	always @(*) begin
		if      (overflow) WSYN_NEW = WSYN_CURR;
		else if (do_up)    WSYN_NEW = WSYN_CURR + {{(WIDTH){1'b0}},1'b1};
		else if (do_down)  WSYN_NEW = WSYN_CURR - {{(WIDTH){1'b0}},1'b1};
		else               WSYN_NEW = WSYN_CURR;
	end 


endmodule
