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
// "izh_effective_threshold.v" - ODIN phenomenological Izhikevich neuron update logic (effective threshold part)
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

 
module izh_effective_threshold ( 
    input  wire [          2:0] param_thr,               // neuron firing threshold parameter
    input  wire                 param_thrvar_en,         // threshold variability and spike frequency adaptation behavior enable parameter
    input  wire                 param_thr_sel_of,        // selection between O (0) and F (1) behaviors parameter (according to Izhikevich behavior numbering)
    input  wire [          3:0] param_thrleak,           // threshold leakage strength parameter
    input  wire                 param_acc_en,            // accommodation behavior enable parameter (requires threshold variability enabled)
    input  wire                 param_burst_incr,        // effective threshold and calcium incrementation by burst amount parameter
    input  wire [          3:0] state_thrmod,            // threshold modificator state from SRAM
    input  wire [          3:0] state_thrleak_cnt,       // threshold leakage state from SRAM
    input  wire [          3:0] state_stim_str_tmp,      // temporary stimulation strength state from SRAM 
    input  wire                 ovfl_inh,                // overflow excitatory type event signal
    input  wire                 ovfl_exc,                // overflow inhibitory type event signal
    input  wire                 event_tref,              // time reference event signal
    input  wire [          6:0] event_out,               // neuron spike event output 
    output reg  [          3:0] state_thrmod_next,       // next threshold modificator state to SRAM
    output reg  [          3:0] state_thrleak_cnt_next,  // next threshold leakage state to SRAM
    output wire [          3:0] threshold_eff            // neuron current effective threshold signal
);


    reg        thr_leak;
    wire [3:0] predicted_acc_thr;
    wire       spike_out;

    assign predicted_acc_thr = param_acc_en ? (state_stim_str_tmp + {1'b0,param_thr}): 4'b0;
    assign spike_out         = event_out[6];

    always @(*) begin 
        if (param_acc_en)
            if (event_tref)
                if (~state_stim_str_tmp[3] && predicted_acc_thr[3])
                    state_thrmod_next = 4'b0111 - {1'b0,param_thr};
                else if (state_stim_str_tmp[3] && predicted_acc_thr[3])
                    state_thrmod_next = 4'b0001 - {1'b0,param_thr};
                else
                    state_thrmod_next = state_stim_str_tmp;
            else 
                state_thrmod_next = state_thrmod;
        else if (param_thrvar_en)
            if (param_thr_sel_of ? spike_out : ovfl_exc)
                state_thrmod_next = param_burst_incr ? (((4'b0111 - threshold_eff) < {1'b0,event_out[5:3]+{2'b0,~&event_out[5:3]}}) ? 4'b0111 : (state_thrmod + {1'b0,event_out[5:3]+{2'b0,~&event_out[5:3]}})) : ((threshold_eff == 4'b0111) ? state_thrmod : (state_thrmod + 4'b1));
            else if (~param_thr_sel_of && ovfl_inh)
                state_thrmod_next = (threshold_eff == 4'b0001) ? state_thrmod : (state_thrmod - 4'b1);
            else if (thr_leak && |state_thrmod)
                state_thrmod_next = state_thrmod[3] ? (state_thrmod + 4'b1) : (state_thrmod - 4'b1);
            else 
                state_thrmod_next = state_thrmod;
        else
            state_thrmod_next = state_thrmod;
    end

    assign threshold_eff = {1'b0,param_thr} + state_thrmod;

    always @(*) begin 
        if (param_thrvar_en && |param_thrleak && event_tref)
            if (state_thrleak_cnt == (param_thrleak - 4'b1)) begin
                state_thrleak_cnt_next = 4'b0;
                thr_leak               = 1'b1;
            end else begin
                state_thrleak_cnt_next = state_thrleak_cnt + 4'b1;
                thr_leak               = 1'b0;
            end
        else begin
            state_thrleak_cnt_next = state_thrleak_cnt;
            thr_leak               = 1'b0;
        end
    end

endmodule