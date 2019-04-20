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
// "izh_stimulation_strength.v" - ODIN phenomenological Izhikevich neuron update logic (stimulation strength part)
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


module izh_stimulation_strength ( 
    input  wire [          2:0] param_stim_thr,          // stimulation threshold (phasic, mixed,...) parameter
    input  wire [          3:0] state_stim_str,          // stimulation strength state from SRAM 
    input  wire [          3:0] state_stim_str_tmp,      // temporary stimulation strength state from SRAM 
    input  wire [          1:0] state_stim0_prev,        // zero stimulation monitoring state from SRAM
    input  wire [          1:0] state_inhexc_prev,       // inh/exc stimulation monitoring state from SRAM
    input  wire                 ovfl_inh,                // overflow excitatory type event signal
    input  wire                 ovfl_exc,                // overflow inhibitory type event signal
    input  wire                 event_tref,              // time reference event signal
    output reg  [          3:0] state_stim_str_next,     // next stimulation strength state to SRAM 
    output reg  [          3:0] state_stim_str_tmp_next, // next temporary stimulation strength state to SRAM 
    output reg  [          1:0] state_stim0_prev_next,   // next zero stimulation monitoring state to SRAM
    output reg  [          1:0] state_inhexc_prev_next,  // next inh/exc stimulation monitoring state to SRAM
    output wire                 stim_gt_thr_exc,         // excitatory stimulation strength greater than threshold signal
    output wire                 stim_tmp_gt_thr_exc,     // current excitatory stimulation strength greater than threshold signal
    output wire                 stim_gt_thr_inh,         // inhibitory stimulation strength greater than threshold signal
    output wire                 stim_tmp_gt_thr_inh,     // current inhibitory stimulation strength greater than threshold signal
    output wire                 stim_lone_spike_exc,     // isolated excitatory spike signal
    output wire                 stim_lone_spike_inh,     // isolated inhibitory spike signal
    output wire                 stim_zero                // zero stimulation signal
);


    assign stim_gt_thr_exc     = ~state_stim_str[3]     && (      state_stim_str[2:0]  >=       param_stim_thr );
    assign stim_tmp_gt_thr_exc = ~state_stim_str_tmp[3] && (  state_stim_str_tmp[2:0]  >=       param_stim_thr );
    assign stim_gt_thr_inh     =  state_stim_str[3]     && ((    -state_stim_str     ) >= {1'b0,param_stim_thr});
    assign stim_tmp_gt_thr_inh =  state_stim_str_tmp[3] && ((-state_stim_str_tmp     ) >= {1'b0,param_stim_thr});
    assign stim_lone_spike_exc =  event_tref && (state_stim_str_tmp == 4'b0) && ~state_stim0_prev[1] && state_inhexc_prev[0];
    assign stim_lone_spike_inh =  event_tref && (state_stim_str_tmp == 4'b0) && ~state_stim0_prev[1] && state_inhexc_prev[1];
    assign stim_zero           =  event_tref && (state_stim_str_tmp == 4'b0);

    always @(*) begin 
        if (event_tref)
            state_stim_str_tmp_next = 4'b0;
        else if (ovfl_exc && (state_stim_str_tmp != 4'b0111))
            state_stim_str_tmp_next = state_stim_str_tmp + 4'b1;
        else if (ovfl_inh && (state_stim_str_tmp != 4'b1001))
            state_stim_str_tmp_next = state_stim_str_tmp - 4'b1;
        else
            state_stim_str_tmp_next = state_stim_str_tmp;
    end

    always @(*) begin 
        if (event_tref)
            state_stim_str_next = state_stim_str_tmp;
        else
            state_stim_str_next = state_stim_str;
    end

    always @(*) begin 
        if (event_tref)
            state_stim0_prev_next = {state_stim0_prev[0], ~(state_stim_str_tmp == 4'b0)};
        else
            state_stim0_prev_next = state_stim0_prev;
    end

    always @(*) begin 
        if (event_tref)
            state_inhexc_prev_next = {stim_tmp_gt_thr_inh, stim_tmp_gt_thr_exc};
        else
            state_inhexc_prev_next = state_inhexc_prev;
    end
    
    
endmodule 
