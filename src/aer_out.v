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
// "aer_out.v" - ODIN AER output link module
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


module aer_out #(
	parameter N = 256,
	parameter M = 8
)(

    // Global input ----------------------------------- 
    input  wire           CLK,
    input  wire           RST,
    
    // Inputs from SPI configuration latches ----------
    input  wire           SPI_GATE_ACTIVITY_sync,
    input  wire           SPI_OUT_AER_MONITOR_EN,
    input  wire [  M-1:0] SPI_MONITOR_NEUR_ADDR,
    input  wire [  M-1:0] SPI_MONITOR_SYN_ADDR, 
    input  wire           SPI_AER_SRC_CTRL_nNEUR,
    
    // Neuron data inputs -----------------------------
    input  wire [   14:0] NEUR_STATE_MONITOR,
    input  wire [    6:0] NEUR_EVENT_OUT,
    input  wire           CTRL_NEURMEM_WE, 
    input  wire [  M-1:0] CTRL_NEURMEM_ADDR,
    input  wire           CTRL_NEURMEM_CS,
    
    // Synapse data inputs ----------------------------
    input  wire [   31:0] SYNARRAY_WDATA,
    input  wire           CTRL_SYNARRAY_WE, 
    input  wire [   12:0] CTRL_SYNARRAY_ADDR,
    input  wire           CTRL_SYNARRAY_CS,
    
    // Input from scheduler ---------------------------
    input  wire [   12:0] SCHED_DATA_OUT,
  
    // Input from controller --------------------------
    input  wire           CTRL_AEROUT_POP_NEUR,
    
    // Output to controller ---------------------------
    output reg            AEROUT_CTRL_BUSY,
    
	// Output 8-bit AER link --------------------------
	output reg  [  M-1:0] AEROUT_ADDR, 
	output reg  	      AEROUT_REQ,
	input  wire 	      AEROUT_ACK
);


   reg            AEROUT_ACK_sync_int, AEROUT_ACK_sync, AEROUT_ACK_sync_del; 
   wire           AEROUT_ACK_sync_negedge;
   
   reg  [    7:0] neuron_state_monitor_samp;
   reg  [    3:0] synapse_state_samp;
   wire [   31:0] synapse_state_int;
   wire           neuron_state_event, synapse_state_event, synapse_state_event_cond;
   reg            synapse_state_event_del;
   wire           monitored_neuron_popped;
   
   reg            do_neuron0_transfer, do_neuron1_transfer, do_synapse_transfer;
   
   wire           rst_activity;
   
   
   assign rst_activity = RST || SPI_GATE_ACTIVITY_sync;
   
   assign monitored_neuron_popped  = CTRL_AEROUT_POP_NEUR && (SCHED_DATA_OUT[M-1:0] == SPI_MONITOR_NEUR_ADDR);
   
   assign neuron_state_event       = SPI_OUT_AER_MONITOR_EN && ((CTRL_NEURMEM_CS  && CTRL_NEURMEM_WE  && (CTRL_NEURMEM_ADDR  == SPI_MONITOR_NEUR_ADDR)) || (monitored_neuron_popped && SPI_AER_SRC_CTRL_nNEUR));
   assign synapse_state_event_cond = SPI_OUT_AER_MONITOR_EN &&   CTRL_SYNARRAY_CS && CTRL_SYNARRAY_WE && (CTRL_SYNARRAY_ADDR == {SPI_MONITOR_SYN_ADDR, SPI_MONITOR_NEUR_ADDR[7:3]});
   assign synapse_state_event      = synapse_state_event_cond && !neuron_state_event;

   
   // Sync barrier
   always @(posedge CLK, posedge rst_activity) begin
		if (rst_activity) begin
			AEROUT_ACK_sync_int <= 1'b0;
			AEROUT_ACK_sync	    <= 1'b0;
			AEROUT_ACK_sync_del <= 1'b0;
		end
		else begin
			AEROUT_ACK_sync_int <= AEROUT_ACK;
			AEROUT_ACK_sync	    <= AEROUT_ACK_sync_int;
			AEROUT_ACK_sync_del <= AEROUT_ACK_sync;
		end
	end
    assign AEROUT_ACK_sync_negedge = ~AEROUT_ACK_sync && AEROUT_ACK_sync_del;
    
    
    // Register state bank    
    always @(posedge CLK) begin
		if (neuron_state_event)
            neuron_state_monitor_samp <= NEUR_STATE_MONITOR[7:0];
        else
            neuron_state_monitor_samp <= neuron_state_monitor_samp;
	end
    always @(posedge CLK) begin
		if (synapse_state_event_cond)
            synapse_state_samp <= synapse_state_int[3:0];
        else
            synapse_state_samp <= synapse_state_samp;
	end
    
    assign synapse_state_int = SYNARRAY_WDATA >> ({2'b0,SPI_MONITOR_NEUR_ADDR[2:0]} << 2);
    
    
    // Output AER interface
    always @(posedge CLK, posedge rst_activity) begin
		if (rst_activity) begin
			AEROUT_ADDR             <= 8'b0;
			AEROUT_REQ              <= 1'b0;
            AEROUT_CTRL_BUSY        <= 1'b0;
            do_neuron0_transfer     <= 1'b0;
            do_neuron1_transfer     <= 1'b0;
            do_synapse_transfer     <= 1'b0;
            synapse_state_event_del <= 1'b0;
		end else if (~SPI_OUT_AER_MONITOR_EN) begin
            do_neuron0_transfer     <= 1'b0;
            do_neuron1_transfer     <= 1'b0;
            do_synapse_transfer     <= 1'b0;
            synapse_state_event_del <= 1'b0;
            if ((SPI_AER_SRC_CTRL_nNEUR ? CTRL_AEROUT_POP_NEUR : NEUR_EVENT_OUT[6]) && ~AEROUT_ACK_sync) begin
                AEROUT_ADDR      <= SPI_AER_SRC_CTRL_nNEUR ? SCHED_DATA_OUT[M-1:0] : CTRL_NEURMEM_ADDR;
                AEROUT_REQ       <= 1'b1;
                AEROUT_CTRL_BUSY <= 1'b1;
            end else if (AEROUT_ACK_sync) begin
                AEROUT_ADDR      <= AEROUT_ADDR;
                AEROUT_REQ       <= 1'b0;
                AEROUT_CTRL_BUSY <= 1'b1;
            end else if (AEROUT_ACK_sync_negedge) begin
                AEROUT_ADDR      <= AEROUT_ADDR;
                AEROUT_REQ       <= 1'b0;
                AEROUT_CTRL_BUSY <= 1'b0;
            end else begin
                AEROUT_ADDR      <= AEROUT_ADDR;
                AEROUT_REQ       <= AEROUT_REQ;
                AEROUT_CTRL_BUSY <= AEROUT_CTRL_BUSY;
            end
        end else begin
            if (AEROUT_ACK_sync_negedge) begin
                AEROUT_ADDR             <= AEROUT_ADDR;
                AEROUT_REQ              <= 1'b0;
                AEROUT_CTRL_BUSY        <= do_neuron0_transfer || synapse_state_event_del;
                do_neuron0_transfer     <= 1'b0;
                do_neuron1_transfer     <= do_neuron0_transfer;
                do_synapse_transfer     <= 1'b0;
                synapse_state_event_del <= synapse_state_event_del;
            end else if (AEROUT_ACK_sync) begin
                AEROUT_ADDR             <= AEROUT_ADDR;
                AEROUT_REQ              <= 1'b0;
                AEROUT_CTRL_BUSY        <= 1'b1;
                do_neuron0_transfer     <= do_neuron0_transfer;
                do_neuron1_transfer     <= do_neuron1_transfer;
                do_synapse_transfer     <= do_synapse_transfer;
                synapse_state_event_del <= synapse_state_event_del;
            end else if ((neuron_state_event || synapse_state_event) && !AEROUT_REQ) begin
                AEROUT_ADDR             <= synapse_state_event ? {4'b1111,synapse_state_int[3:0]}
                                                               : {(SPI_AER_SRC_CTRL_nNEUR ? monitored_neuron_popped : NEUR_EVENT_OUT[6]),NEUR_STATE_MONITOR[14:8]};
                AEROUT_REQ              <= 1'b1;
                AEROUT_CTRL_BUSY        <= 1'b1;
                do_neuron0_transfer     <= neuron_state_event;
                do_neuron1_transfer     <= 1'b0;
                do_synapse_transfer     <= synapse_state_event;
                synapse_state_event_del <= synapse_state_event_cond && neuron_state_event;
            end else if (do_neuron1_transfer && !AEROUT_REQ) begin
                AEROUT_ADDR             <= neuron_state_monitor_samp;
                AEROUT_REQ              <= 1'b1;
                AEROUT_CTRL_BUSY        <= 1'b1;
                do_neuron0_transfer     <= 1'b0;
                do_neuron1_transfer     <= 1'b1;
                do_synapse_transfer     <= 1'b0;
                synapse_state_event_del <= synapse_state_event_del;
            end else if (synapse_state_event_del && !AEROUT_REQ) begin
                AEROUT_ADDR             <= {4'b1111,synapse_state_samp};
                AEROUT_REQ              <= 1'b1;
                AEROUT_CTRL_BUSY        <= 1'b1;
                do_neuron0_transfer     <= 1'b0;
                do_neuron1_transfer     <= 1'b0;
                do_synapse_transfer     <= 1'b0;
                synapse_state_event_del <= 1'b0;
            end else begin
                AEROUT_ADDR             <= AEROUT_ADDR;
                AEROUT_REQ              <= AEROUT_REQ;
                AEROUT_CTRL_BUSY        <= AEROUT_CTRL_BUSY;
                do_neuron0_transfer     <= do_neuron0_transfer;
                do_neuron1_transfer     <= do_neuron1_transfer;
                do_synapse_transfer     <= do_synapse_transfer;
                synapse_state_event_del <= synapse_state_event_del;
            end
        end
	end


endmodule 
