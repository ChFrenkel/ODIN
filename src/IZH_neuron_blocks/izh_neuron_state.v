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
// "izh_neuron state.v" - ODIN phenomenological Izhikevich neuron update logic (neuron state part)
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


`define RES_POS          2'd0
`define RES_NEG          2'd1
`define RES_ZERO_TO_P    2'd2
`define RES_ZERO_TO_N    2'd3
 
module izh_neuron_state (
    input  wire [          2:0] param_spk_ref,          // number of spikes per burst parameter
    input  wire [          2:0] param_isi_ref,          // inter-spike-interval in burst parameter
    input  wire [          2:0] param_rfr,              // neuron refractory period parameter
    input  wire [          2:0] param_dapdel,           // delay for spike latency or DAP parameter
    input  wire                 param_spklat_en,        // spike latency enable parameter
    input  wire                 param_dap_en,           // DAP enable parameter
    input  wire                 param_phasic_en,        // phasic behavior enable parameter
    input  wire                 param_mixed_en,         // mixed mode behavior enable parameter
    input  wire                 param_class2_en,        // class 2 excitability enable parameter
    input  wire                 param_neg_en,           // negative state enable parameter
    input  wire                 param_rebound_en,       // rebound behavior enable parameter
    input  wire                 param_inhin_en,         // inhibition-induced behavior enable parameter
    input  wire                 param_bist_en,          // bistability behavior enable parameter
    input  wire                 param_reson_en,         // resonant behavior enable parameter
    input  wire                 param_acc_en,           // accommodation behavior enable parameter (requires threshold variability enabled)
    input  wire                 param_reson_sharp_en,   // sharp resonant behavior enable parameter
    input  wire [          2:0] param_reson_sharp_amt,  // sharp resonant behavior time constant parameter
    input  wire                 state_refrac,           // refractory period state from SRAM 
    input  wire [          3:0] state_core,             // membrane potential state from SRAM 
    input  wire [          2:0] state_dapdel_cnt,       // dapdel counter state from SRAM  
    input  wire                 state_phasic_lock,      // phasic lock state from SRAM
    input  wire                 state_mixed_lock,       // mixed lock state from SRAM
    input  wire                 state_spkout_done,      // spike sent in current Tref interval state from SRAM
    input  wire                 state_bist_lock,        // bistability lock state from SRAM
    input  wire                 state_inhin_lock,       // inhibition-induced lock state from SRAM
    input  wire [          1:0] state_reson_sign,       // resonant sign state from SRAM
    input  wire                 state_burst_lock,       // burst lock state from SRAM
    input  wire [          3:0] state_stim_str_tmp,     // temporary stimulation strength state from SRAM 
    input  wire                 ovfl_leak,              // overflow leakage type event
    input  wire                 ovfl_inh,               // overflow excitatory type event
    input  wire                 ovfl_exc,               // overflow inhibitory type event
    input  wire                 event_tref,             // time reference event
    input  wire                 burst_end,              // end of burst signal
    input  wire                 stim_gt_thr_exc,        // excitatory stimulation strength greater than threshold signal
    input  wire                 stim_tmp_gt_thr_exc,    // current excitatory stimulation strength greater than threshold signal
    input  wire                 stim_gt_thr_inh,        // inhibitory stimulation strength greater than threshold signal
    input  wire                 stim_tmp_gt_thr_inh,    // current inhibitory stimulation strength greater than threshold signal
    input  wire                 stim_lone_spike_exc,    // isolated excitatory spike signal
    input  wire                 stim_lone_spike_inh,    // isolated inhibitory spike signal
    input  wire                 stim_zero,              // zero stimulation signal
    input  wire [          3:0] threshold_eff,          // neuron current effective threshold signal
    output wire                 state_refrac_next,      // next refractory period state to SRAM
    output wire [          3:0] state_core_next,        // next membrane potential state to SRAM 
    output reg  [          2:0] state_dapdel_cnt_next,  // next dapdel counter state to SRAM
    output reg                  state_phasic_lock_next, // next phasic lock state to SRAM
    output reg                  state_mixed_lock_next,  // next mixed lock state to SRAM
    output reg                  state_spkout_done_next, // next spike sent in current Tref interval state to SRAM
    output reg                  state_bist_lock_next,   // next bistability lock state to SRAM
    output reg                  state_inhin_lock_next,  // next inhibition-induced lock state to SRAM
    output wire [          1:0] state_reson_sign_next,  // next resonant sign state to SRAM
    output reg                  state_burst_lock_next,  // next burst lock state to SRAM
    output wire [          6:0] event_out               // neuron spike event output   
);


    reg [3:0] state_core_next_i;
    reg [1:0] state_reson_sign_next_i;

    reg    spike_out;
    wire   refrac_en;
    wire   dap_event, spklat_event;

    assign event_out             = state_mixed_lock ? {spike_out, 3'b000, 3'b0} : {spike_out, param_spk_ref, param_isi_ref};
    assign refrac_en             = ~param_dap_en & |param_rfr;

    always @(*) begin 
        if (param_spklat_en && |state_dapdel_cnt)
            state_core_next_i = state_core;
        else if (state_phasic_lock && ~|state_core)
            state_core_next_i = state_core;
        else
            if (event_tref)
                if      (param_reson_en)
                    state_core_next_i = (state_reson_sign == `RES_ZERO_TO_N) ? (state_core - 4'b1) : state_core;
                else if (state_refrac)
                    state_core_next_i = state_burst_lock ? state_core : (state_core + 4'b1);
                else if (param_acc_en)
                    state_core_next_i = state_spkout_done ? state_core : (state_core - state_stim_str_tmp);
                else if (param_dap_en && (state_dapdel_cnt == 3'b1) && (state_core > 4'b0))
                    state_core_next_i = 4'b0;
                else if (ovfl_leak && |state_core)
                    state_core_next_i = state_core[3] ? (state_core + 4'b1) : (state_core - 4'b1);
                else
                    state_core_next_i = state_core;
            else if (ovfl_inh)
                if (param_reson_en)
                    state_core_next_i = (((state_reson_sign == `RES_ZERO_TO_N) || (state_reson_sign == `RES_NEG)) && ~(state_core == 4'b0111)) ? (state_core + 4'b1) : ((((state_reson_sign == `RES_ZERO_TO_P) || (state_reson_sign == `RES_POS)) && ~(state_core == 4'b0)) ? (state_core - 4'b1) : state_core);
                else
                    state_core_next_i = state_refrac ? state_core : ((param_neg_en ? (state_core == 4'b1000) : ~|state_core) ? state_core : (state_core - 1'b1)); 
            else if (ovfl_exc)
                if (param_reson_en)
                    state_core_next_i = (((state_reson_sign == `RES_ZERO_TO_N) || (state_reson_sign == `RES_NEG)) && ~(state_core == 4'b0)) ? (state_core - 4'b1) : ((((state_reson_sign == `RES_ZERO_TO_P) || (state_reson_sign == `RES_POS)) && ~(state_core == 4'b0111)) ? (state_core + 4'b1) : state_core);
                else
                    state_core_next_i = state_refrac ? state_core : ((param_class2_en && ~stim_gt_thr_exc && ~stim_tmp_gt_thr_exc) ? state_core: ((state_core == 4'b0111) ? state_core : (state_core + 1'b1)));
            else 
                state_core_next_i = state_core;
    end

    assign spklat_event      =  param_spklat_en & (state_core_next_i == threshold_eff) & (state_core != threshold_eff);
    assign dap_event         =  param_dap_en & spike_out;
    assign state_refrac_next = (spike_out || state_inhin_lock_next) ? (refrac_en && ~param_reson_en) : ((state_core_next_i == 4'b0) ? 1'b0 : state_refrac);

    always @(*) begin 
        if (~param_reson_en)
            state_reson_sign_next_i = `RES_POS;
        else
            if (event_tref)
                if (~|state_core)
                    state_reson_sign_next_i = `RES_POS;
                else begin
                    case(state_reson_sign) 
                        `RES_POS      : state_reson_sign_next_i = `RES_ZERO_TO_N;
                        `RES_NEG      : state_reson_sign_next_i = `RES_ZERO_TO_P;
                        `RES_ZERO_TO_P: state_reson_sign_next_i = `RES_POS;
                        `RES_ZERO_TO_N: if (state_core_next_i == 4'b0)
                                            state_reson_sign_next_i = `RES_POS;
                                        else
                                            state_reson_sign_next_i = `RES_NEG;
                        default:        state_reson_sign_next_i = state_reson_sign;
                    endcase
                end
            else
                state_reson_sign_next_i = state_reson_sign;
    end

    always @(*) begin 
        if (param_reson_sharp_en)
            if (event_tref && ~&state_dapdel_cnt)
                state_dapdel_cnt_next = state_dapdel_cnt + 3'b1;
            else if (ovfl_exc)
                state_dapdel_cnt_next = 3'b0;
            else 
                state_dapdel_cnt_next = state_dapdel_cnt;
        else
            if (dap_event || spklat_event)
                state_dapdel_cnt_next = param_dapdel;
            else
                if (event_tref && |state_dapdel_cnt)
                    state_dapdel_cnt_next = state_dapdel_cnt - 3'b1;
                else 
                    state_dapdel_cnt_next = state_dapdel_cnt;
    end

    always @(*) begin 
        if (spike_out && (stim_tmp_gt_thr_exc || stim_gt_thr_exc)) begin
            state_phasic_lock_next = param_phasic_en;
            state_mixed_lock_next  = param_mixed_en;
        end else if (event_tref && state_spkout_done && (~|state_core || state_refrac) && stim_tmp_gt_thr_exc) begin
            state_phasic_lock_next = param_phasic_en;
            state_mixed_lock_next  = param_mixed_en;
        end else if (~stim_gt_thr_exc) begin
            state_phasic_lock_next = 1'b0;
            state_mixed_lock_next  = 1'b0;
        end else begin
            state_phasic_lock_next = state_phasic_lock;
            state_mixed_lock_next  = state_mixed_lock;
        end
    end

    always @(*) begin 
        if (event_tref)
            state_spkout_done_next = 1'b0;
        else if (spike_out)
            state_spkout_done_next = 1'b1;
        else
            state_spkout_done_next = state_spkout_done;
    end

    always @(*) begin 
        if (event_tref && param_bist_en)
            state_bist_lock_next = stim_lone_spike_exc ? ~state_bist_lock : state_bist_lock;
        else
            state_bist_lock_next = state_bist_lock;
    end

    always @(*) begin 
        if (param_inhin_en && ~state_refrac && ((-state_core) == threshold_eff))
            state_inhin_lock_next = 1'b1;
        else if (event_tref && state_inhin_lock && (stim_zero))
            state_inhin_lock_next = 1'b0;
        else
            state_inhin_lock_next = state_inhin_lock;
    end

    always @(*) begin 
        if (param_reson_sharp_en)
            spike_out = (ovfl_exc && (state_dapdel_cnt == param_reson_sharp_amt));
        else if (param_spklat_en)
            spike_out = (event_tref && (state_dapdel_cnt == 3'b1));
        else if (param_rebound_en)
            spike_out = stim_lone_spike_inh || (state_core_next_i == threshold_eff);
        else if (param_bist_en)
            spike_out = (~state_bist_lock && stim_lone_spike_exc) || (state_bist_lock && ~|state_core_next_i) || (state_core_next_i == threshold_eff);
        else if (state_inhin_lock)
            spike_out = (state_core_next_i == 4'b0);
        else if (param_reson_en)
            spike_out = (state_reson_sign_next_i == `RES_POS) && (state_core_next_i == threshold_eff);
        else
            spike_out = (state_core_next_i == threshold_eff);
    end

    always @(*) begin 
        if (event_out[6] && |event_out[5:3])
            state_burst_lock_next = 1'b1;
        else if (burst_end)
            state_burst_lock_next = 1'b0;
        else
            state_burst_lock_next = state_burst_lock;
    end

    assign state_reson_sign_next = (spike_out && param_reson_en) ?                                                                  `RES_NEG : state_reson_sign_next_i;
    assign state_core_next       =  spike_out                    ? ((param_dap_en || param_reson_en) ? {1'b0,param_rfr} : -{1'b0,param_rfr}) : state_core_next_i;


endmodule 
