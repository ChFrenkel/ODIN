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
// "izh_calcium.v" - ODIN phenomenological Izhikevich neuron update logic (Calcium part)
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

 
module izh_calcium ( 
    input  wire                 param_ca_en,             // calcium concentration enable parameter                                     [SDSP]
    input  wire [          2:0] param_thetamem,          // membrane threshold parameter                                               [SDSP]
    input  wire [          2:0] param_ca_theta1,         // calcium threshold 1 parameter                                              [SDSP]
    input  wire [          2:0] param_ca_theta2,         // calcium threshold 2 parameter                                              [SDSP]
    input  wire [          2:0] param_ca_theta3,         // calcium threshold 3 parameter                                              [SDSP]
    input  wire [          4:0] param_caleak,            // calcium leakage strength parameter                                         [SDSP]
    input  wire                 param_burst_incr,        // effective threshold and calcium incrementation by burst amount parameter  ([SDSP])
    input  wire [          2:0] state_calcium,           // calcium concentration state from SRAM                                      [SDSP]
    input  wire [          4:0] state_caleak_cnt,        // calcium leakage state from SRAM                                            [SDSP]
    input  wire [          3:0] state_core_next,         // next membrane potential state to SRAM
    input  wire [          6:0] event_out,               // neuron spike event output 
    input  wire                 event_tref,              // time reference event signal
    output wire                 v_up_next,               // next SDSP UP condition value                                               [SDSP]
    output wire                 v_down_next,             // next SDSP DOWN condition value                                             [SDSP]
    output reg  [          2:0] state_calcium_next,      // next calcium concentration state to SRAM                                   [SDSP]
    output reg  [          4:0] state_caleak_cnt_next    // next calcium leakage state to SRAM                                         [SDSP]
);


    reg    ca_leak;
    wire   spike_out;

    assign spike_out   = event_out[6];
    assign v_up_next   = param_ca_en && ~state_core_next[3] && (state_core_next[2:0] >= param_thetamem) && (param_ca_theta1 <= state_calcium_next) && (state_calcium_next < param_ca_theta3);
    assign v_down_next = param_ca_en && ~state_core_next[3] && (state_core_next[2:0] <  param_thetamem) && (param_ca_theta1 <= state_calcium_next) && (state_calcium_next < param_ca_theta2);

    always @(*) begin 
        if (param_ca_en) 
            if (spike_out && ~ca_leak && ~&state_calcium)
                state_calcium_next = param_burst_incr ? (((3'b111 - state_calcium) < (event_out[5:3] + {2'b0,~&event_out[5:3]})) ? 3'b111 : (state_calcium + event_out[5:3] + {2'b0,~&event_out[5:3]})) : (state_calcium + 3'b1);
            else if (ca_leak && ~spike_out && |state_calcium)
                state_calcium_next = state_calcium - 3'b1;
            else
                state_calcium_next = state_calcium;
        else
            state_calcium_next = state_calcium;
    end

    always @(*) begin 
        if (param_ca_en && |param_caleak && event_tref)
            if (state_caleak_cnt == (param_caleak - 5'b1)) begin
                state_caleak_cnt_next = 5'b0;
                ca_leak               = 1'b1;
            end else begin
                state_caleak_cnt_next = state_caleak_cnt + 5'b1;
                ca_leak               = 1'b0;
            end
        else begin
            state_caleak_cnt_next = state_caleak_cnt;
            ca_leak               = 1'b0;
        end
    end


endmodule
