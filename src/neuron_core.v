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
// "neuron_core.v" - ODIN neuron core module
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


module neuron_core #(
    parameter N = 256,
    parameter M = 8
)(
    
    // Global inputs ------------------------------------------
    input  wire                 RSTN_syncn,
    input  wire                 CLK,
    
    // Inputs from SPI configuration registers ----------------
    input  wire                 SPI_GATE_ACTIVITY_sync,
	input  wire                 SPI_PROPAGATE_UNMAPPED_SYN,
    
    // Synaptic inputs ----------------------------------------
    input  wire [         31:0] SYNARRAY_RDATA,
    input  wire                 SYN_SIGN,
    
    // Inputs from controller ---------------------------------
    input  wire                 CTRL_NEUR_EVENT,
    input  wire                 CTRL_NEUR_TREF,
    input  wire [          4:0] CTRL_NEUR_VIRTS,
    input  wire                 CTRL_NEURMEM_CS,
    input  wire                 CTRL_NEURMEM_WE,
    input  wire [        M-1:0] CTRL_NEURMEM_ADDR,
    input  wire [      2*M-1:0] CTRL_PROG_DATA,
    input  wire [      2*M-1:0] CTRL_SPI_ADDR,
    
    // Inputs from scheduler ----------------------------------
    input  wire                 CTRL_NEUR_BURST_END,
    
    // Outputs ------------------------------------------------
    output wire [        127:0] NEUR_STATE,
    output wire [          6:0] NEUR_EVENT_OUT,
    output reg  [        N-1:0] NEUR_V_UP,
    output reg  [        N-1:0] NEUR_V_DOWN,
    output wire [         14:0] NEUR_STATE_MONITOR
);
    
    // Internal regs and wires definitions

    wire           neur_rstn;
    wire [    2:0] syn_weight;
    wire [   31:0] syn_weight_int;
    wire           syn_sign;
    wire           syn_event;
    wire           time_ref;
    
    wire           LIF_neuron_v_up_next,   IZH_neuron_v_up_next;
    wire           LIF_neuron_v_down_next, IZH_neuron_v_down_next;
    wire [    6:0] LIF_neuron_event_out,   IZH_neuron_event_out;
    
    wire [   15:0] LIF_neuron_next_NEUR_STATE;
    wire [   54:0] IZH_neuron_next_NEUR_STATE;
    
    wire [  127:0] neuron_data_int, neuron_data;
    
    genvar i;

    
    // Processing inputs from the synaptic array and the controller
    
    assign syn_weight_int  = SYNARRAY_RDATA >> ({2'b0,CTRL_NEURMEM_ADDR[2:0]} << 2);
    
    assign syn_weight      = |CTRL_NEUR_VIRTS ? CTRL_NEUR_VIRTS[4:2] : (syn_weight_int[2:0] & {3{syn_weight_int[3] | SPI_PROPAGATE_UNMAPPED_SYN}});
    assign syn_sign        = |CTRL_NEUR_VIRTS ? CTRL_NEUR_VIRTS[1]   : SYN_SIGN;
    assign syn_event       =  CTRL_NEUR_EVENT;
    assign time_ref        = |CTRL_NEUR_VIRTS ? CTRL_NEUR_VIRTS[0]   : CTRL_NEUR_TREF;
    

    // Updated or configured neuron state to be written to the neuron memory

    assign neuron_data_int = NEUR_STATE[0] ? {NEUR_STATE[127: 86], LIF_neuron_next_NEUR_STATE,NEUR_STATE[69:0]}
                                           : {NEUR_STATE[127:125], IZH_neuron_next_NEUR_STATE,NEUR_STATE[69:0]};
    generate
        for (i=0; i<(N>>4); i=i+1) begin
        
            assign neuron_data[M*i+M-1:M*i] = SPI_GATE_ACTIVITY_sync
                                            ? ((i == CTRL_SPI_ADDR[2*M-1:M])
                                                     ? ((CTRL_PROG_DATA[M-1:0] & ~CTRL_PROG_DATA[2*M-1:M]) | (NEUR_STATE[M*i+M-1:M*i] & CTRL_PROG_DATA[2*M-1:M]))
                                                     : NEUR_STATE[M*i+M-1:M*i])
                                            : neuron_data_int[M*i+M-1:M*i];
            
        end
    endgenerate
    

    // Neuron UP/DOWN registers for SDSP online learning

    generate
        for (i=0; i<N; i=i+1) begin
            always @(posedge CLK)
                if (CTRL_NEURMEM_CS && CTRL_NEURMEM_WE && (i == CTRL_NEURMEM_ADDR)) begin
                    NEUR_V_UP[i]   <= NEUR_STATE[0] ? LIF_neuron_v_up_next   : IZH_neuron_v_up_next;
                    NEUR_V_DOWN[i] <= NEUR_STATE[0] ? LIF_neuron_v_down_next : IZH_neuron_v_down_next;
                end else begin
                    NEUR_V_UP[i]   <= NEUR_V_UP[i];
                    NEUR_V_DOWN[i] <= NEUR_V_DOWN[i];
                end
        end
    endgenerate
    

    // Neuron state monitoring

    assign NEUR_STATE_MONITOR = NEUR_STATE[0]
                              ? {LIF_neuron_v_up_next, LIF_neuron_v_down_next, LIF_neuron_next_NEUR_STATE[10:8], 2'b0, LIF_neuron_next_NEUR_STATE[7:0]}
                              : {IZH_neuron_v_up_next, IZH_neuron_v_down_next, IZH_neuron_next_NEUR_STATE[48:46], IZH_neuron_next_NEUR_STATE[37:36], {4'b0,IZH_neuron_next_NEUR_STATE[15:12]}};
    
    // Neuron output spike events

    assign NEUR_EVENT_OUT     = NEUR_STATE[127] ? 7'b0 : ((CTRL_NEURMEM_CS && CTRL_NEURMEM_WE) ? (NEUR_STATE[0] ? LIF_neuron_event_out : IZH_neuron_event_out) : 7'b0);
    
    
    // Neuron update logic for leaky integrate-and-fire (LIF) model
    
    lif_neuron lif_neuron_0 ( 
        .param_leak_str(         NEUR_STATE[0] ? NEUR_STATE[  7:  1] : 7'b0),
        .param_leak_en(          NEUR_STATE[0] ? NEUR_STATE[      8] : 1'b0),
        .param_thr(              NEUR_STATE[0] ? NEUR_STATE[ 16:  9] : 8'b0),
        .param_ca_en(            NEUR_STATE[0] ? NEUR_STATE[     17] : 1'b0),
        .param_thetamem(         NEUR_STATE[0] ? NEUR_STATE[ 25: 18] : 8'b0),
        .param_ca_theta1(        NEUR_STATE[0] ? NEUR_STATE[ 28: 26] : 3'b0),
        .param_ca_theta2(        NEUR_STATE[0] ? NEUR_STATE[ 31: 29] : 3'b0),
        .param_ca_theta3(        NEUR_STATE[0] ? NEUR_STATE[ 34: 32] : 3'b0),
        .param_caleak(           NEUR_STATE[0] ? NEUR_STATE[ 39: 35] : 5'b0),
        
        .state_core(             NEUR_STATE[0] ? NEUR_STATE[ 77: 70] : 8'b0),
        .state_core_next(        LIF_neuron_next_NEUR_STATE[  7:  0]       ),
        .state_calcium(          NEUR_STATE[0] ? NEUR_STATE[ 80: 78] : 3'b0),
        .state_calcium_next(     LIF_neuron_next_NEUR_STATE[ 10:  8]       ),
        .state_caleak_cnt(       NEUR_STATE[0] ? NEUR_STATE[ 85: 81] : 5'b0),
        .state_caleak_cnt_next(  LIF_neuron_next_NEUR_STATE[ 15: 11]       ),
        
        .syn_weight(syn_weight),
        .syn_sign(syn_sign),
        .syn_event(syn_event),
        .time_ref(time_ref),
        
        .v_up_next(LIF_neuron_v_up_next),
        .v_down_next(LIF_neuron_v_down_next),
        .event_out(LIF_neuron_event_out) 
    );
    
    
    // Neuron update logic for phenomenological Izhikevich model

    izh_neuron #(
        .ACC_DEPTH(11)
    ) izh_neuron_0 ( 
        .param_leak_str(         ~NEUR_STATE[0] ? NEUR_STATE[  7:  1] : 7'b0),
        .param_leak_en(          ~NEUR_STATE[0] ? NEUR_STATE[      8] : 1'b0),
        .param_fi_sel(           ~NEUR_STATE[0] ? NEUR_STATE[ 11:  9] : 3'b0),
        .param_spk_ref(          ~NEUR_STATE[0] ? NEUR_STATE[ 14: 12] : 3'b0),
        .param_isi_ref(          ~NEUR_STATE[0] ? NEUR_STATE[ 17: 15] : 3'b0),
        .param_reson_sharp_en(   ~NEUR_STATE[0] ? NEUR_STATE[     18] : 1'b0),
        .param_thr(              ~NEUR_STATE[0] ? NEUR_STATE[ 21: 19] : 3'b0),
        .param_rfr(              ~NEUR_STATE[0] ? NEUR_STATE[ 24: 22] : 3'b0),
        .param_dapdel(           ~NEUR_STATE[0] ? NEUR_STATE[ 27: 25] : 3'b0),
        .param_spklat_en(        ~NEUR_STATE[0] ? NEUR_STATE[     28] : 1'b0),
        .param_dap_en(           ~NEUR_STATE[0] ? NEUR_STATE[     29] : 1'b0),
        .param_stim_thr(         ~NEUR_STATE[0] ? NEUR_STATE[ 32: 30] : 3'b0),
        .param_phasic_en(        ~NEUR_STATE[0] ? NEUR_STATE[     33] : 1'b0),
        .param_mixed_en(         ~NEUR_STATE[0] ? NEUR_STATE[     34] : 1'b0),
        .param_class2_en(        ~NEUR_STATE[0] ? NEUR_STATE[     35] : 1'b0),
        .param_neg_en(           ~NEUR_STATE[0] ? NEUR_STATE[     36] : 1'b0),
        .param_rebound_en(       ~NEUR_STATE[0] ? NEUR_STATE[     37] : 1'b0),
        .param_inhin_en(         ~NEUR_STATE[0] ? NEUR_STATE[     38] : 1'b0),
        .param_bist_en(          ~NEUR_STATE[0] ? NEUR_STATE[     39] : 1'b0),
        .param_reson_en(         ~NEUR_STATE[0] ? NEUR_STATE[     40] : 1'b0),
        .param_thrvar_en(        ~NEUR_STATE[0] ? NEUR_STATE[     41] : 1'b0),
        .param_thr_sel_of(       ~NEUR_STATE[0] ? NEUR_STATE[     42] : 1'b0),
        .param_thrleak(          ~NEUR_STATE[0] ? NEUR_STATE[ 46: 43] : 4'b0),
        .param_acc_en(           ~NEUR_STATE[0] ? NEUR_STATE[     47] : 1'b0),
        .param_ca_en(            ~NEUR_STATE[0] ? NEUR_STATE[     48] : 1'b0),
        .param_thetamem(         ~NEUR_STATE[0] ? NEUR_STATE[ 51: 49] : 3'b0),
        .param_ca_theta1(        ~NEUR_STATE[0] ? NEUR_STATE[ 54: 52] : 3'b0),
        .param_ca_theta2(        ~NEUR_STATE[0] ? NEUR_STATE[ 57: 55] : 3'b0),
        .param_ca_theta3(        ~NEUR_STATE[0] ? NEUR_STATE[ 60: 58] : 3'b0),
        .param_caleak(           ~NEUR_STATE[0] ? NEUR_STATE[ 65: 61] : 5'b0),
        .param_burst_incr(       ~NEUR_STATE[0] ? NEUR_STATE[     66] : 1'b0),
        .param_reson_sharp_amt(  ~NEUR_STATE[0] ? NEUR_STATE[ 69: 67] : 3'b0),
        
        .state_inacc(            ~NEUR_STATE[0] ? NEUR_STATE[ 80: 70] :11'b0),
        .state_inacc_next(        IZH_neuron_next_NEUR_STATE[ 10:  0]       ),
        .state_refrac(           ~NEUR_STATE[0] ? NEUR_STATE[     81] : 1'b0),
        .state_refrac_next(       IZH_neuron_next_NEUR_STATE[     11]       ),
        .state_core(             ~NEUR_STATE[0] ? NEUR_STATE[ 85: 82] : 4'b0),
        .state_core_next(         IZH_neuron_next_NEUR_STATE[ 15: 12]       ),
        .state_dapdel_cnt(       ~NEUR_STATE[0] ? NEUR_STATE[ 88: 86] : 3'b0),
        .state_dapdel_cnt_next(   IZH_neuron_next_NEUR_STATE[ 18: 16]       ),
        .state_stim_str(         ~NEUR_STATE[0] ? NEUR_STATE[ 92: 89] : 4'b0),
        .state_stim_str_next(     IZH_neuron_next_NEUR_STATE[ 22: 19]       ),
        .state_stim_str_tmp(     ~NEUR_STATE[0] ? NEUR_STATE[ 96: 93] : 4'b0),
        .state_stim_str_tmp_next( IZH_neuron_next_NEUR_STATE[ 26: 23]       ),
        .state_phasic_lock(      ~NEUR_STATE[0] ? NEUR_STATE[     97] : 1'b0),
        .state_phasic_lock_next(  IZH_neuron_next_NEUR_STATE[     27]       ),
        .state_mixed_lock(       ~NEUR_STATE[0] ? NEUR_STATE[     98] : 1'b0),
        .state_mixed_lock_next(   IZH_neuron_next_NEUR_STATE[     28]       ),
        .state_spkout_done(      ~NEUR_STATE[0] ? NEUR_STATE[     99] : 1'b0),
        .state_spkout_done_next(  IZH_neuron_next_NEUR_STATE[     29]       ),
        .state_stim0_prev(       ~NEUR_STATE[0] ? NEUR_STATE[101:100] : 2'b0),
        .state_stim0_prev_next(   IZH_neuron_next_NEUR_STATE[ 31: 30]       ),
        .state_inhexc_prev(      ~NEUR_STATE[0] ? NEUR_STATE[103:102] : 2'b0),
        .state_inhexc_prev_next(  IZH_neuron_next_NEUR_STATE[ 33: 32]       ),
        .state_bist_lock(        ~NEUR_STATE[0] ? NEUR_STATE[    104] : 1'b0),
        .state_bist_lock_next(    IZH_neuron_next_NEUR_STATE[     34]       ),
        .state_inhin_lock(       ~NEUR_STATE[0] ? NEUR_STATE[    105] : 1'b0),
        .state_inhin_lock_next(   IZH_neuron_next_NEUR_STATE[     35]       ),
        .state_reson_sign(       ~NEUR_STATE[0] ? NEUR_STATE[107:106] : 2'b0),
        .state_reson_sign_next(   IZH_neuron_next_NEUR_STATE[ 37: 36]       ),
        .state_thrmod(           ~NEUR_STATE[0] ? NEUR_STATE[111:108] : 4'b0),
        .state_thrmod_next(       IZH_neuron_next_NEUR_STATE[ 41: 38]       ),
        .state_thrleak_cnt(      ~NEUR_STATE[0] ? NEUR_STATE[115:112] : 4'b0),
        .state_thrleak_cnt_next(  IZH_neuron_next_NEUR_STATE[ 45: 42]       ),
        .state_calcium(          ~NEUR_STATE[0] ? NEUR_STATE[118:116] : 3'b0),
        .state_calcium_next(      IZH_neuron_next_NEUR_STATE[ 48: 46]       ),
        .state_caleak_cnt(       ~NEUR_STATE[0] ? NEUR_STATE[123:119] : 5'b0),
        .state_caleak_cnt_next(   IZH_neuron_next_NEUR_STATE[ 53: 49]       ),
        .state_burst_lock(       ~NEUR_STATE[0] ? NEUR_STATE[    124] : 1'b0),
        .state_burst_lock_next(   IZH_neuron_next_NEUR_STATE[     54]       ),
        
        .syn_weight(syn_weight),
        .syn_sign(syn_sign),
        .syn_event(syn_event),
        .time_ref(time_ref),
        .burst_end(CTRL_NEUR_BURST_END),
        
        .v_up_next(IZH_neuron_v_up_next),
        .v_down_next(IZH_neuron_v_down_next),
        .event_out(IZH_neuron_event_out)
    );
    

    // Neuron memory wrapper

    SRAM_256x128_wrapper neurarray_0 (       
        
        // Global inputs
        .RSTN       (RSTN_syncn),
        .CK         (CLK),
    
        // Control and data inputs
        .CS         (CTRL_NEURMEM_CS),
        .WE         (CTRL_NEURMEM_WE),
        .A          (CTRL_NEURMEM_ADDR),
        .D          (neuron_data),
        
        // Data output
        .Q          (NEUR_STATE)
    );
    

endmodule




module SRAM_256x128_wrapper (

    // Global inputs
    input          RSTN,                     // Reset_N
    input          CK,                       // Clock (synchronous read/write)

    // Control and data inputs
    input          CS,                       // Chip select (active high)
    input          WE,                       // Write enable (active high)
    input  [  7:0] A,                        // Address bus 
    input  [127:0] D,                        // Data input bus (write)

    // Data output
    output [127:0] Q                         // Data output bus (read)   
);


    /*
     *  Simple behavioral code for simulation, to be replaced by a 256-word 128-bit SRAM macro 
     *  or Block RAM (BRAM) memory with the same format for FPGA implementations.
     */      
        reg [127:0] SRAM[255:0];
        reg [127:0] Qr;
        always @(posedge CK) begin
            Qr <= CS ? SRAM[A] : Qr;
            if (CS & WE) SRAM[A] <= D;
        end
        assign Q = Qr;
    

endmodule
