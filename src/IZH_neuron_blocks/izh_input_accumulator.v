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
// "izh_input_accumulator.v" - ODIN phenomenological Izhikevich neuron update logic (input accumulator part)
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


module izh_input_accumulator #(
	parameter ACC_DEPTH = 11
)( 
    input  wire [          6:0] param_leak_str,   // leakage strength parameter
    input  wire                 param_leak_en,    // leakage enable parameter
    input  wire [          2:0] param_fi_sel,     // accumulator depth parameter for fan-in configuration
    input  wire [ACC_DEPTH-1:0] state_inacc,      // input accumulator state from SRAM
    input  wire [          2:0] syn_weight,       // synaptic weight
    input  wire                 event_leak,       // leakage event trigger
    input  wire                 event_exc,        // excitatory event trigger
    input  wire                 event_inh,        // inhibitory event trigger
    input  wire                 state_refrac,     // neuron in refractory period
    output reg  [ACC_DEPTH-1:0] state_inacc_next, // next input accumulator state to SRAM
    output wire                 ovfl_leak,        // negative leakage overflow signal
    output wire                 ovfl_exc,         // positive excitatory overflow signal
    output wire                 ovfl_inh          // negative inhibitory overflow signal
);


    reg  state_inacc_fi, state_inacc_next_fi;
    wire toggle;


    always @(*) begin 
        if (event_leak)
            state_inacc_next = param_leak_en ? (state_inacc - {{(ACC_DEPTH-7){1'b0}},param_leak_str}) : state_inacc;
        else if (event_exc)
            state_inacc_next = state_inacc + {{(ACC_DEPTH-3){1'b0}},syn_weight};
        else if (event_inh)
            state_inacc_next = state_inacc - {{(ACC_DEPTH-3){1'b0}},syn_weight};
    	else
    		state_inacc_next = state_inacc;
    end

    always @(*)
        case (param_fi_sel) 
            3'd0    : begin state_inacc_fi = state_inacc[3 ]; state_inacc_next_fi = state_inacc_next[3 ]; end
            3'd1    : begin state_inacc_fi = state_inacc[4 ]; state_inacc_next_fi = state_inacc_next[4 ]; end
            3'd2    : begin state_inacc_fi = state_inacc[5 ]; state_inacc_next_fi = state_inacc_next[5 ]; end 
            3'd3    : begin state_inacc_fi = state_inacc[6 ]; state_inacc_next_fi = state_inacc_next[6 ]; end
            3'd4    : begin state_inacc_fi = state_inacc[7 ]; state_inacc_next_fi = state_inacc_next[7 ]; end
            3'd5    : begin state_inacc_fi = state_inacc[8 ]; state_inacc_next_fi = state_inacc_next[8 ]; end 
            3'd6    : begin state_inacc_fi = state_inacc[9 ]; state_inacc_next_fi = state_inacc_next[9 ]; end 
            3'd7    : begin state_inacc_fi = state_inacc[10]; state_inacc_next_fi = state_inacc_next[10]; end
            default : begin state_inacc_fi = state_inacc[3 ]; state_inacc_next_fi = state_inacc_next[3 ]; end
        endcase 

    assign toggle = state_inacc_fi ^ state_inacc_next_fi;
        
    assign ovfl_leak = toggle & event_leak;
    assign ovfl_exc  = toggle & event_exc ;
    assign ovfl_inh  = toggle & event_inh ;


endmodule 
