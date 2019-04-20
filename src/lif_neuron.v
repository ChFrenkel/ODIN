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
// "lif_neuron.v" - ODIN leaky integrate-and-fire (LIF) neuron update logic (LIF neuron top-level module)
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


module lif_neuron ( 
    input  wire [          6:0] param_leak_str,          // leakage strength parameter
    input  wire                 param_leak_en,           // leakage enable parameter
    input  wire [          7:0] param_thr,               // neuron firing threshold parameter
    input  wire                 param_ca_en,             // calcium concentration enable parameter    [SDSP]
    input  wire [          7:0] param_thetamem,          // membrane threshold parameter              [SDSP]
    input  wire [          2:0] param_ca_theta1,         // calcium threshold 1 parameter             [SDSP]
    input  wire [          2:0] param_ca_theta2,         // calcium threshold 2 parameter             [SDSP]
    input  wire [          2:0] param_ca_theta3,         // calcium threshold 3 parameter             [SDSP]
    input  wire [          4:0] param_caleak,            // calcium leakage strength parameter        [SDSP]
    
    input  wire [          7:0] state_core,              // membrane potential state from SRAM 
    output wire [          7:0] state_core_next,         // next membrane potential state to SRAM
    input  wire [          2:0] state_calcium,           // calcium concentration state from SRAM     [SDSP]
    output wire [          2:0] state_calcium_next,      // next calcium concentration state to SRAM  [SDSP]
    input  wire [          4:0] state_caleak_cnt,        // calcium leakage state from SRAM           [SDSP]
    output wire [          4:0] state_caleak_cnt_next,   // next calcium leakage state to SRAM        [SDSP]
    
    input  wire [          2:0] syn_weight,              // synaptic weight
    input  wire                 syn_sign,                // inhibitory (!excitatory) configuration bit
    input  wire                 syn_event,               // synaptic event trigger
    input  wire                 time_ref,                // time reference event trigger
    
    output wire                 v_up_next,               // next SDSP UP condition value              [SDSP]
    output wire                 v_down_next,             // next SDSP DOWN condition value            [SDSP]
    output wire [          6:0] event_out                // neuron spike event output  
);


    wire       event_leak, event_tref;
    wire       event_inh;
    wire       event_exc;

    assign event_leak =  syn_event  & time_ref;
    assign event_tref =  event_leak;
    assign event_exc  = ~event_leak & (syn_event & ~syn_sign);
    assign event_inh  = ~event_leak & (syn_event &  syn_sign);

        
    lif_calcium calcium_0 ( 
        .param_ca_en(param_ca_en),
        .param_thetamem(param_thetamem),
        .param_ca_theta1(param_ca_theta1),
        .param_ca_theta2(param_ca_theta2),
        .param_ca_theta3(param_ca_theta3),
        .param_caleak(param_caleak),
        .state_calcium(state_calcium),
        .state_caleak_cnt(state_caleak_cnt),
        .state_core_next(state_core_next),
        .spike_out(event_out[6]),
        .event_tref(event_tref),
        .v_up_next(v_up_next),
        .v_down_next(v_down_next),
        .state_calcium_next(state_calcium_next),
        .state_caleak_cnt_next(state_caleak_cnt_next)
    );

    lif_neuron_state neuron_state_0 (
        .param_leak_str(param_leak_str),
        .param_leak_en(param_leak_en),
        .param_thr(param_thr),
        .state_core(state_core),
        .event_leak(event_leak),
        .event_inh(event_inh),
        .event_exc(event_exc),
        .syn_weight(syn_weight),
        .state_core_next(state_core_next),
        .event_out(event_out)
    );


endmodule
