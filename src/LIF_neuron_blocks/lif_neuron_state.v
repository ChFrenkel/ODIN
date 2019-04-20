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
// "lif_neuron_state.v" - ODIN leaky integrate-and-fire (LIF) neuron update logic (neuron state part)
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


module lif_neuron_state ( 
    input  wire [          6:0] param_leak_str,         // leakage strength parameter
    input  wire                 param_leak_en,          // leakage enable parameter
    input  wire [          7:0] param_thr,              // neuron firing threshold parameter
    input  wire [          7:0] state_core,             // membrane potential state from SRAM 
    input  wire                 event_leak,             // leakage type event
    input  wire                 event_inh,              // excitatory type event
    input  wire                 event_exc,              // inhibitory type event
    input  wire [          2:0] syn_weight,             // synaptic weight
    output wire [          7:0] state_core_next,        // next membrane potential state to SRAM 
    output wire [          6:0] event_out               // neuron spike event output  
);


    reg  [7:0] state_core_next_i;
    wire [7:0] state_leak, state_inh, state_exc;
    wire       spike_out;

    assign spike_out       = (state_core_next_i >= param_thr);
    assign event_out       = {spike_out, 3'b000, 3'b0};
    assign state_core_next =  spike_out ? 8'd0 : state_core_next_i;

    always @(*) begin 

            if (event_leak && param_leak_en)
                if (state_core >= state_leak)
                    state_core_next_i = state_leak;
                else
                    state_core_next_i = 8'b0;
            else if (event_inh)
                if (state_core >= state_inh)
                    state_core_next_i = state_inh;
                else
                    state_core_next_i = 8'b0;
            else if (event_exc)
                if (state_core <= state_exc)
                    state_core_next_i = state_exc;
                else
                    state_core_next_i = 8'hFF;
            else 
                state_core_next_i = state_core;
    end

    assign state_leak = (state_core - {1'b0,param_leak_str});
    assign state_inh  = (state_core - {5'b0,syn_weight});
    assign state_exc  = (state_core + {5'b0,syn_weight});

endmodule 
