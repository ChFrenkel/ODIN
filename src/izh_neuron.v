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
// "izh_neuron.v" - ODIN phenomenological Izhikevich neuron update logic (IZH neuron top-level module)
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


module izh_neuron #(
	parameter ACC_DEPTH = 11
)( 
    input  wire [          6:0] param_leak_str,          // leakage strength parameter
    input  wire                 param_leak_en,           // leakage enable parameter
    input  wire [          2:0] param_fi_sel,            // accumulator depth parameter for fan-in configuration
    input  wire [          2:0] param_spk_ref,           // number of spikes per burst parameter
    input  wire [          2:0] param_isi_ref,           // inter-spike-interval in burst parameter
    input  wire                 param_reson_sharp_en,    // sharp resonant behavior enable parameter
    input  wire [          2:0] param_thr,               // neuron firing threshold parameter
    input  wire [          2:0] param_rfr,               // neuron refractory period parameter
    input  wire [          2:0] param_dapdel,            // delay for spike latency or DAP parameter
    input  wire                 param_spklat_en,         // spike latency enable parameter
    input  wire                 param_dap_en,            // DAP enable parameter
    input  wire [          2:0] param_stim_thr,          // stimulation threshold (phasic, mixed,...) parameter
    input  wire                 param_phasic_en,         // phasic behavior enable parameter
    input  wire                 param_mixed_en,          // mixed mode behavior enable parameter
    input  wire                 param_class2_en,         // class 2 excitability enable parameter
    input  wire                 param_neg_en,            // negative state enable parameter
    input  wire                 param_rebound_en,        // rebound behavior enable parameter
    input  wire                 param_inhin_en,          // inhibition-induced behavior enable parameter
    input  wire                 param_bist_en,           // bistability behavior enable parameter
    input  wire                 param_reson_en,          // resonant behavior enable parameter
    input  wire                 param_thrvar_en,         // threshold variability and spike frequency adaptation behavior enable parameter
    input  wire                 param_thr_sel_of,        // selection between O (0) and F (1) behaviors parameter (according to Izhikevich behavior numbering)
    input  wire [          3:0] param_thrleak,           // threshold leakage strength parameter
    input  wire                 param_acc_en,            // accommodation behavior enable parameter (requires threshold variability enabled)
    input  wire                 param_ca_en,             // calcium concentration enable parameter                                     [SDSP]
    input  wire [          2:0] param_thetamem,          // membrane threshold parameter                                               [SDSP]
    input  wire [          2:0] param_ca_theta1,         // calcium threshold 1 parameter                                              [SDSP]
    input  wire [          2:0] param_ca_theta2,         // calcium threshold 2 parameter                                              [SDSP]
    input  wire [          2:0] param_ca_theta3,         // calcium threshold 3 parameter                                              [SDSP]
    input  wire [          4:0] param_caleak,            // calcium leakage strength parameter                                         [SDSP]
    input  wire                 param_burst_incr,        // effective threshold and calcium incrementation by burst amount parameter  ([SDSP])
    input  wire [          2:0] param_reson_sharp_amt,   // sharp resonant behavior time constant parameter
    
    input  wire [ACC_DEPTH-1:0] state_inacc,             // input accumulator state from SRAM
    output wire [ACC_DEPTH-1:0] state_inacc_next,        // next input accumulator state to SRAM   
    input  wire                 state_refrac,            // refractory period state from SRAM 
    output wire                 state_refrac_next,       // next refractory period state to SRAM
    input  wire [          3:0] state_core,              // membrane potential state from SRAM 
    output wire [          3:0] state_core_next,         // next membrane potential state to SRAM 
    input  wire [          2:0] state_dapdel_cnt,        // dapdel counter state from SRAM 
    output wire [          2:0] state_dapdel_cnt_next,   // next dapdel counter state to SRAM 
    input  wire [          3:0] state_stim_str,          // stimulation strength state from SRAM 
    output wire [          3:0] state_stim_str_next,     // next stimulation strength state to SRAM 
    input  wire [          3:0] state_stim_str_tmp,      // temporary stimulation strength state from SRAM 
    output wire [          3:0] state_stim_str_tmp_next, // next temporary stimulation strength state to SRAM  
    input  wire                 state_phasic_lock,       // phasic lock state from SRAM
    output wire                 state_phasic_lock_next,  // next phasic lock state to SRAM
    input  wire                 state_mixed_lock,        // mixed lock state from SRAM
    output wire                 state_mixed_lock_next,   // next mixed lock state to SRAM
    input  wire                 state_spkout_done,       // spike sent in current Tref interval state from SRAM
    output wire                 state_spkout_done_next,  // next spike sent in current Tref interval state to SRAM
    input  wire [          1:0] state_stim0_prev,        // zero stimulation monitoring state from SRAM
    output wire [          1:0] state_stim0_prev_next,   // next zero stimulation monitoring state to SRAM
    input  wire [          1:0] state_inhexc_prev,       // inh/exc stimulation monitoring state from SRAM
    output wire [          1:0] state_inhexc_prev_next,  // next inh/exc stimulation monitoring state to SRAM
    input  wire                 state_bist_lock,         // bistability lock state from SRAM
    output wire                 state_bist_lock_next,    // next bistability lock state to SRAM
    input  wire                 state_inhin_lock,        // inhibition-induced lock state from SRAM
    output wire                 state_inhin_lock_next,   // next inhibition-induced lock state to SRAM
    input  wire [          1:0] state_reson_sign,        // resonant sign state from SRAM
    output wire [          1:0] state_reson_sign_next,   // next resonant sign state to SRAM
    input  wire [          3:0] state_thrmod,            // threshold modificator state from SRAM
    output wire [          3:0] state_thrmod_next,       // next threshold modificator state to SRAM
    input  wire [          3:0] state_thrleak_cnt,       // threshold leakage state from SRAM
    output wire [          3:0] state_thrleak_cnt_next,  // next threshold leakage state to SRAM
    input  wire [          2:0] state_calcium,           // calcium concentration state from SRAM     [SDSP]
    output wire [          2:0] state_calcium_next,      // next calcium concentration state to SRAM  [SDSP]
    input  wire [          4:0] state_caleak_cnt,        // calcium leakage state from SRAM           [SDSP]
    output wire [          4:0] state_caleak_cnt_next,   // next calcium leakage state to SRAM        [SDSP]
    input  wire                 state_burst_lock,        // burst lock state from SRAM
    output wire                 state_burst_lock_next,   // next burst lock state to SRAM
    
    input  wire [          2:0] syn_weight,              // synaptic weight
    input  wire                 syn_sign,                // inhibitory (!excitatory) configuration bit
    input  wire                 syn_event,               // synaptic event trigger
    input  wire                 time_ref,                // time reference event trigger
    input  wire                 burst_end,               // end of burst signal
    
    output wire                 v_up_next,               // next SDSP UP condition value              [SDSP]
    output wire                 v_down_next,             // next SDSP DOWN condition value            [SDSP]
    output wire [          6:0] event_out                // neuron spike event output  
);


    wire       event_leak, event_tref;
    wire       event_inh;
    wire       event_exc;

    wire       ovfl_leak;
    wire       ovfl_exc;
    wire       ovfl_inh;

    wire       stim_gt_thr_exc, stim_gt_thr_inh;
    wire       stim_tmp_gt_thr_exc, stim_tmp_gt_thr_inh;
    wire       stim_lone_spike_exc, stim_lone_spike_inh;
    wire       stim_zero;
    wire [3:0] threshold_eff;


    assign event_leak =  syn_event  & time_ref;
    assign event_tref =  event_leak;
    assign event_exc  = ~event_leak & (syn_event & ~syn_sign);
    assign event_inh  = ~event_leak & (syn_event &  syn_sign);

        

    izh_input_accumulator #(
    	.ACC_DEPTH(ACC_DEPTH)
    ) input_accumulator_0 ( 
        .param_leak_str(param_leak_str),
        .param_leak_en(param_leak_en),
        .param_fi_sel(param_fi_sel),
        .state_inacc(state_inacc),
        .syn_weight(syn_weight),
        .event_leak(event_leak),
        .event_exc(event_exc),
        .event_inh(event_inh),
        .state_refrac(state_refrac),
        .state_inacc_next(state_inacc_next),
        .ovfl_leak(ovfl_leak),
        .ovfl_exc(ovfl_exc),
        .ovfl_inh(ovfl_inh)
    );


    izh_stimulation_strength stimulation_strength_0 ( 
        .param_stim_thr(param_stim_thr),
        .state_stim_str(state_stim_str),
        .state_stim_str_tmp(state_stim_str_tmp),
        .state_stim0_prev(state_stim0_prev),
        .state_inhexc_prev(state_inhexc_prev),
        .ovfl_inh(ovfl_inh),
        .ovfl_exc(ovfl_exc),
        .event_tref(event_tref),
        .state_stim_str_next(state_stim_str_next),
        .state_stim_str_tmp_next(state_stim_str_tmp_next),
        .state_stim0_prev_next(state_stim0_prev_next),
        .state_inhexc_prev_next(state_inhexc_prev_next),
        .stim_gt_thr_exc(stim_gt_thr_exc),
        .stim_tmp_gt_thr_exc(stim_tmp_gt_thr_exc),
        .stim_gt_thr_inh(stim_gt_thr_inh),
        .stim_tmp_gt_thr_inh(stim_tmp_gt_thr_inh),
        .stim_lone_spike_exc(stim_lone_spike_exc),
        .stim_lone_spike_inh(stim_lone_spike_inh),
        .stim_zero(stim_zero)
    ); 

    izh_effective_threshold effective_threshold_0 (
        .param_thr(param_thr),
        .param_thrvar_en(param_thrvar_en),
        .param_thr_sel_of(param_thr_sel_of),
        .param_thrleak(param_thrleak),
        .param_acc_en(param_acc_en),
        .param_burst_incr(param_burst_incr),
        .state_thrmod(state_thrmod),
        .state_thrleak_cnt(state_thrleak_cnt),
        .state_stim_str_tmp(state_stim_str_tmp),
        .ovfl_inh(ovfl_inh),
        .ovfl_exc(ovfl_exc),
        .event_tref(event_tref),
        .event_out(event_out),
        .state_thrmod_next(state_thrmod_next),
        .state_thrleak_cnt_next(state_thrleak_cnt_next),
        .threshold_eff(threshold_eff)
    );

    izh_calcium calcium_0 ( 
        .param_ca_en(param_ca_en),
        .param_thetamem(param_thetamem),
        .param_ca_theta1(param_ca_theta1),
        .param_ca_theta2(param_ca_theta2),
        .param_ca_theta3(param_ca_theta3),
        .param_caleak(param_caleak),
        .param_burst_incr(param_burst_incr),
        .state_calcium(state_calcium),
        .state_caleak_cnt(state_caleak_cnt),
        .state_core_next(state_core_next), 
        .event_out(event_out),
        .event_tref(event_tref),
        .v_up_next(v_up_next),
        .v_down_next(v_down_next),
        .state_calcium_next(state_calcium_next),
        .state_caleak_cnt_next(state_caleak_cnt_next)
    );

    izh_neuron_state neuron_state_0 (
        .param_spk_ref(param_spk_ref),
        .param_isi_ref(param_isi_ref),
        .param_rfr(param_rfr),
        .param_dapdel(param_dapdel),
        .param_spklat_en(param_spklat_en),
        .param_dap_en(param_dap_en),
        .param_phasic_en(param_phasic_en),
        .param_mixed_en(param_mixed_en),
        .param_class2_en(param_class2_en),
        .param_neg_en(param_neg_en),
        .param_rebound_en(param_rebound_en),
        .param_inhin_en(param_inhin_en),
        .param_bist_en(param_bist_en),
        .param_reson_en(param_reson_en),
        .param_acc_en(param_acc_en),
        .param_reson_sharp_en(param_reson_sharp_en),
        .param_reson_sharp_amt(param_reson_sharp_amt),
        .state_refrac(state_refrac),
        .state_core(state_core),
        .state_dapdel_cnt(state_dapdel_cnt),
        .state_phasic_lock(state_phasic_lock),
        .state_mixed_lock(state_mixed_lock),
        .state_spkout_done(state_spkout_done),
        .state_bist_lock(state_bist_lock),
        .state_inhin_lock(state_inhin_lock),
        .state_reson_sign(state_reson_sign),
        .state_burst_lock(state_burst_lock),
        .state_stim_str_tmp(state_stim_str_tmp),
        .ovfl_leak(ovfl_leak),
        .ovfl_inh(ovfl_inh),
        .ovfl_exc(ovfl_exc),
        .event_tref(event_tref),
        .burst_end(burst_end),
        .stim_gt_thr_exc(stim_gt_thr_exc),
        .stim_tmp_gt_thr_exc(stim_tmp_gt_thr_exc),
        .stim_gt_thr_inh(stim_gt_thr_inh),
        .stim_tmp_gt_thr_inh(stim_tmp_gt_thr_inh),
        .stim_lone_spike_exc(stim_lone_spike_exc),
        .stim_lone_spike_inh(stim_lone_spike_inh),
        .stim_zero(stim_zero),
        .threshold_eff(threshold_eff),
        .state_refrac_next(state_refrac_next),
        .state_core_next(state_core_next),
        .state_dapdel_cnt_next(state_dapdel_cnt_next),
        .state_phasic_lock_next(state_phasic_lock_next),
        .state_mixed_lock_next(state_mixed_lock_next),
        .state_spkout_done_next(state_spkout_done_next),
        .state_bist_lock_next(state_bist_lock_next),
        .state_inhin_lock_next(state_inhin_lock_next),
        .state_reson_sign_next(state_reson_sign_next),
        .state_burst_lock_next(state_burst_lock_next),
        .event_out(event_out)
    );


endmodule
