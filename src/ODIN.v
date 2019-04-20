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
// "ODIN.v" - ODIN Spiking Neural Network (SNN) top-level module
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


module ODIN #(
	parameter N = 256,
	parameter M = 8
)(
    // Global input     -------------------------------
    input  wire           CLK,
    input  wire           RST,
    
    // SPI slave        -------------------------------
    input  wire           SCK,
    input  wire           MOSI,
    output wire           MISO,

	// Input 16-bit AER -------------------------------
	input  wire [  2*M:0] AERIN_ADDR,
	input  wire           AERIN_REQ,
	output wire 		  AERIN_ACK,

	// Output 8-bit AER -------------------------------
	output wire [  M-1:0] AEROUT_ADDR,
	output wire 	      AEROUT_REQ,
	input  wire 	      AEROUT_ACK
);

    //----------------------------------------------------------------------------------
	//	Internal regs and wires
	//----------------------------------------------------------------------------------

    // Reset and clock
    wire                 RSTN_sync;
    reg                  RST_sync_int, RST_sync, RSTN_syncn;

    // AER output
    wire                 AEROUT_CTRL_BUSY;
    
    // SPI + parameter bank
    wire                 SPI_GATE_ACTIVITY, SPI_GATE_ACTIVITY_sync;
    wire                 SPI_OPEN_LOOP;
    wire [        N-1:0] SPI_SYN_SIGN;
    wire [         19:0] SPI_BURST_TIMEREF;
    wire                 SPI_OUT_AER_MONITOR_EN;
    wire [        M-1:0] SPI_MONITOR_NEUR_ADDR;
    wire [        M-1:0] SPI_MONITOR_SYN_ADDR; 
    wire                 SPI_AER_SRC_CTRL_nNEUR;
    wire                 SPI_UPDATE_UNMAPPED_SYN;
	wire                 SPI_PROPAGATE_UNMAPPED_SYN;
	wire                 SPI_SDSP_ON_SYN_STIM;
    
    // Controller
    wire                 CTRL_READBACK_EVENT;
    wire                 CTRL_PROG_EVENT;
    wire [      2*M-1:0] CTRL_SPI_ADDR;
    wire [          1:0] CTRL_OP_CODE;
    wire [      2*M-1:0] CTRL_PROG_DATA;
    wire [          7:0] CTRL_PRE_EN;
    wire                 CTRL_BIST_REF;
    wire                 CTRL_SYNARRAY_WE;
    wire                 CTRL_NEURMEM_WE;
    wire [         12:0] CTRL_SYNARRAY_ADDR;
    wire [        M-1:0] CTRL_NEURMEM_ADDR;
    wire                 CTRL_SYNARRAY_CS;
    wire                 CTRL_NEURMEM_CS;
    wire                 CTRL_NEUR_EVENT; 
    wire                 CTRL_NEUR_TREF;  
    wire [          4:0] CTRL_NEUR_VIRTS;
    wire                 CTRL_NEUR_BURST_END;
    wire                 CTRL_NEUR_MAPTABLE;
    wire                 CTRL_SCHED_POP_N;
    wire [        M-1:0] CTRL_SCHED_ADDR;
    wire [          6:0] CTRL_SCHED_EVENT_IN;
    wire [          4:0] CTRL_SCHED_VIRTS;
    wire                 CTRL_AEROUT_POP_NEUR;
    
    // Synaptic core
    wire [         31:0] SYNARRAY_RDATA;
    wire [         31:0] SYNARRAY_WDATA;
    wire                 SYN_SIGN;
    
    // Scheduler
    wire                 SCHED_EMPTY;
    wire                 SCHED_FULL;
    wire                 SCHED_BURST_END;
    wire [         12:0] SCHED_DATA_OUT;
    
    // Neuron core
    wire [        127:0] NEUR_STATE;
    wire [         14:0] NEUR_STATE_MONITOR;
    wire [          6:0] NEUR_EVENT_OUT;
    wire [        N-1:0] NEUR_V_UP;
    wire [        N-1:0] NEUR_V_DOWN;
    
    
    //----------------------------------------------------------------------------------
	//	Reset (with double sync barrier)
	//----------------------------------------------------------------------------------
    
    always @(posedge CLK) begin
        RST_sync_int <= RST;
		RST_sync     <= RST_sync_int;
	end
    
    assign RSTN_sync = ~RST_sync;
    
    always @(negedge CLK) begin
        RSTN_syncn <= RSTN_sync;
    end
    
    
    //----------------------------------------------------------------------------------
	//	AER OUT
	//----------------------------------------------------------------------------------
    
    aer_out #(
        .N(N),
        .M(M)
    ) aer_out_0 (

        // Global input ----------------------------------- 
        .CLK(CLK),
        .RST(RST_sync),
        
        // Inputs from SPI configuration latches ----------
        .SPI_GATE_ACTIVITY_sync(SPI_GATE_ACTIVITY_sync),
        .SPI_OUT_AER_MONITOR_EN(SPI_OUT_AER_MONITOR_EN),
        .SPI_MONITOR_NEUR_ADDR(SPI_MONITOR_NEUR_ADDR),
        .SPI_MONITOR_SYN_ADDR(SPI_MONITOR_SYN_ADDR), 
        .SPI_AER_SRC_CTRL_nNEUR(SPI_AER_SRC_CTRL_nNEUR),
        
        // Neuron data inputs -----------------------------
        .NEUR_STATE_MONITOR(NEUR_STATE_MONITOR),
        .NEUR_EVENT_OUT(NEUR_EVENT_OUT),
        .CTRL_NEURMEM_WE(CTRL_NEURMEM_WE), 
        .CTRL_NEURMEM_ADDR(CTRL_NEURMEM_ADDR),
        .CTRL_NEURMEM_CS(CTRL_NEURMEM_CS),
        
        // Synapse data inputs ----------------------------
        .SYNARRAY_WDATA(SYNARRAY_WDATA),
        .CTRL_SYNARRAY_WE(CTRL_SYNARRAY_WE), 
        .CTRL_SYNARRAY_ADDR(CTRL_SYNARRAY_ADDR),
        .CTRL_SYNARRAY_CS(CTRL_SYNARRAY_CS),
        
        // Input from scheduler ---------------------------
        .SCHED_DATA_OUT(SCHED_DATA_OUT),
        
        // Input from controller --------------------------
        .CTRL_AEROUT_POP_NEUR(CTRL_AEROUT_POP_NEUR),
        
        // Output to controller ---------------------------
        .AEROUT_CTRL_BUSY(AEROUT_CTRL_BUSY),
        
        // Output 8-bit AER link --------------------------
        .AEROUT_ADDR(AEROUT_ADDR),
        .AEROUT_REQ(AEROUT_REQ),
        .AEROUT_ACK(AEROUT_ACK)
    );
    
    
    //----------------------------------------------------------------------------------
	//	SPI + parameter bank + clock int/ext handling
	//----------------------------------------------------------------------------------

    spi_slave #(
        .N(N),
        .M(M)
    ) spi_slave_0 (

        // Global inputs ------------------------------------------
        .RST_async(RST),
    
        // SPI slave interface ------------------------------------
        .SCK(SCK),
        .MISO(MISO),
        .MOSI(MOSI),
        
        // Control interface for readback -------------------------
        .CTRL_READBACK_EVENT(CTRL_READBACK_EVENT),
        .CTRL_PROG_EVENT(CTRL_PROG_EVENT),
        .CTRL_SPI_ADDR(CTRL_SPI_ADDR),
        .CTRL_OP_CODE(CTRL_OP_CODE),
        .CTRL_PROG_DATA(CTRL_PROG_DATA),
        .SYNARRAY_RDATA(SYNARRAY_RDATA),
        .NEUR_STATE(NEUR_STATE),
    
        // Configuration registers output -------------------------
        .SPI_GATE_ACTIVITY(SPI_GATE_ACTIVITY),
        .SPI_OPEN_LOOP(SPI_OPEN_LOOP),
        .SPI_SYN_SIGN(SPI_SYN_SIGN),
        .SPI_BURST_TIMEREF(SPI_BURST_TIMEREF),
        .SPI_OUT_AER_MONITOR_EN(SPI_OUT_AER_MONITOR_EN),
        .SPI_AER_SRC_CTRL_nNEUR(SPI_AER_SRC_CTRL_nNEUR),
        .SPI_MONITOR_NEUR_ADDR(SPI_MONITOR_NEUR_ADDR),
        .SPI_MONITOR_SYN_ADDR(SPI_MONITOR_SYN_ADDR),
        .SPI_UPDATE_UNMAPPED_SYN(SPI_UPDATE_UNMAPPED_SYN),
		.SPI_PROPAGATE_UNMAPPED_SYN(SPI_PROPAGATE_UNMAPPED_SYN),
		.SPI_SDSP_ON_SYN_STIM(SPI_SDSP_ON_SYN_STIM)
    );
    
    
    //----------------------------------------------------------------------------------
	//	Controller
	//----------------------------------------------------------------------------------

    controller #(
        .N(N),
        .M(M)
    ) controller_0 (
    
        // Global inputs ------------------------------------------
        .CLK(CLK),
        .RST(RST_sync),
    
        // Inputs from AER ----------------------------------------
        .AERIN_ADDR(AERIN_ADDR),
        .AERIN_REQ(AERIN_REQ),
        .AERIN_ACK(AERIN_ACK),

        // Control interface for readback -------------------------
        .CTRL_READBACK_EVENT(CTRL_READBACK_EVENT),
        .CTRL_PROG_EVENT(CTRL_PROG_EVENT),
        .CTRL_SPI_ADDR(CTRL_SPI_ADDR),
        .CTRL_OP_CODE(CTRL_OP_CODE),
		.SPI_SDSP_ON_SYN_STIM(SPI_SDSP_ON_SYN_STIM),
        
        // Inputs from SPI configuration registers ----------------
        .SPI_GATE_ACTIVITY(SPI_GATE_ACTIVITY),
        .SPI_GATE_ACTIVITY_sync(SPI_GATE_ACTIVITY_sync),
        .SPI_MONITOR_NEUR_ADDR(SPI_MONITOR_NEUR_ADDR),
        
        // Inputs from scheduler ----------------------------------
        .SCHED_EMPTY(SCHED_EMPTY),
        .SCHED_FULL(SCHED_FULL),
        .SCHED_BURST_END(SCHED_BURST_END),
        .SCHED_DATA_OUT(SCHED_DATA_OUT),
        
        // Input from AER output ----------------------------------
        .AEROUT_CTRL_BUSY(AEROUT_CTRL_BUSY),
        
        // Outputs to synaptic core -------------------------------
        .CTRL_PRE_EN(CTRL_PRE_EN),
        .CTRL_BIST_REF(CTRL_BIST_REF),
        .CTRL_SYNARRAY_WE(CTRL_SYNARRAY_WE),
        .CTRL_SYNARRAY_ADDR(CTRL_SYNARRAY_ADDR),
        .CTRL_SYNARRAY_CS(CTRL_SYNARRAY_CS),
        .CTRL_NEURMEM_WE(CTRL_NEURMEM_WE),
        .CTRL_NEURMEM_ADDR(CTRL_NEURMEM_ADDR),
        .CTRL_NEURMEM_CS(CTRL_NEURMEM_CS),
        
        // Outputs to neurons -------------------------------------
        .CTRL_NEUR_EVENT(CTRL_NEUR_EVENT), 
        .CTRL_NEUR_TREF(CTRL_NEUR_TREF),
        .CTRL_NEUR_VIRTS(CTRL_NEUR_VIRTS),
        .CTRL_NEUR_BURST_END(CTRL_NEUR_BURST_END),
        
        // Outputs to scheduler -----------------------------------
        .CTRL_SCHED_POP_N(CTRL_SCHED_POP_N),
        .CTRL_SCHED_ADDR(CTRL_SCHED_ADDR),
        .CTRL_SCHED_EVENT_IN(CTRL_SCHED_EVENT_IN),
        .CTRL_SCHED_VIRTS(CTRL_SCHED_VIRTS),

        // Output to AER output -----------------------------------
        .CTRL_AEROUT_POP_NEUR(CTRL_AEROUT_POP_NEUR)
    );
    
    
    //----------------------------------------------------------------------------------
	//	Scheduler
	//----------------------------------------------------------------------------------

    scheduler #(
        .prio_num(57),
        .N(N),
        .M(M)
    ) scheduler_0 (
    
        // Global inputs ------------------------------------------
        .CLK(CLK),
        .RSTN(RSTN_sync),
    
        // Inputs from controller ---------------------------------
        .CTRL_SCHED_POP_N(CTRL_SCHED_POP_N),
        .CTRL_SCHED_VIRTS(CTRL_SCHED_VIRTS),
        .CTRL_SCHED_ADDR(CTRL_SCHED_ADDR),
        .CTRL_SCHED_EVENT_IN(CTRL_SCHED_EVENT_IN),
        
        // Inputs from neurons ------------------------------------
        .CTRL_NEURMEM_ADDR(CTRL_NEURMEM_ADDR),
        .NEUR_EVENT_OUT(NEUR_EVENT_OUT),
        
        // Inputs from SPI configuration registers ----------------
        .SPI_OPEN_LOOP(SPI_OPEN_LOOP),
        .SPI_BURST_TIMEREF(SPI_BURST_TIMEREF),
        
        // Outputs ------------------------------------------------
        .SCHED_EMPTY(SCHED_EMPTY),
        .SCHED_FULL(SCHED_FULL),
        .SCHED_BURST_END(SCHED_BURST_END),
        .SCHED_DATA_OUT(SCHED_DATA_OUT)
    );
    
    
    //----------------------------------------------------------------------------------
	//	Synaptic core
	//----------------------------------------------------------------------------------
   
    synaptic_core #(
        .N(N),
        .M(M)
    ) synaptic_core_0 (
    
        // Global inputs ------------------------------------------
        .RSTN_syncn(RSTN_syncn),
        .CLK(CLK),

        // Inputs from SPI configuration registers ----------------
        .SPI_GATE_ACTIVITY_sync(SPI_GATE_ACTIVITY_sync),
        .SPI_SYN_SIGN(SPI_SYN_SIGN),
        .SPI_UPDATE_UNMAPPED_SYN(SPI_UPDATE_UNMAPPED_SYN),
        
        // Inputs from controller ---------------------------------
        .CTRL_PRE_EN(CTRL_PRE_EN),
        .CTRL_BIST_REF(CTRL_BIST_REF),
        .CTRL_SYNARRAY_WE(CTRL_SYNARRAY_WE),
        .CTRL_SYNARRAY_ADDR(CTRL_SYNARRAY_ADDR),
        .CTRL_SYNARRAY_CS(CTRL_SYNARRAY_CS),
        .CTRL_PROG_DATA(CTRL_PROG_DATA),
        .CTRL_SPI_ADDR(CTRL_SPI_ADDR),
        
        // Inputs from neurons ------------------------------------
        .NEUR_V_UP(NEUR_V_UP),
        .NEUR_V_DOWN(NEUR_V_DOWN),
        
        // Outputs ------------------------------------------------
        .SYNARRAY_RDATA(SYNARRAY_RDATA),
        .SYNARRAY_WDATA(SYNARRAY_WDATA),
        .SYN_SIGN(SYN_SIGN)
	);
    
    
    //----------------------------------------------------------------------------------
	//	Neural core
	//----------------------------------------------------------------------------------
      
    neuron_core #(
        .N(N),
        .M(M)
    ) neuron_core_0 (
    
        // Global inputs ------------------------------------------
        .RSTN_syncn(RSTN_syncn),
        .CLK(CLK),
        
        // Inputs from SPI configuration registers ----------------
        .SPI_GATE_ACTIVITY_sync(SPI_GATE_ACTIVITY_sync),
        .SPI_PROPAGATE_UNMAPPED_SYN(SPI_PROPAGATE_UNMAPPED_SYN),
		
        // Synaptic inputs ----------------------------------------
        .SYNARRAY_RDATA(SYNARRAY_RDATA),
        .SYN_SIGN(SYN_SIGN),
        
        // Inputs from controller ---------------------------------
        .CTRL_NEUR_EVENT(CTRL_NEUR_EVENT),
        .CTRL_NEUR_TREF(CTRL_NEUR_TREF),
        .CTRL_NEUR_VIRTS(CTRL_NEUR_VIRTS),
        .CTRL_NEURMEM_WE(CTRL_NEURMEM_WE),
        .CTRL_NEURMEM_ADDR(CTRL_NEURMEM_ADDR),
        .CTRL_NEURMEM_CS(CTRL_NEURMEM_CS),
        .CTRL_PROG_DATA(CTRL_PROG_DATA),
        .CTRL_SPI_ADDR(CTRL_SPI_ADDR),
        
        // Inputs from scheduler ----------------------------------
        .CTRL_NEUR_BURST_END(CTRL_NEUR_BURST_END), 
        
        // Outputs ------------------------------------------------
        .NEUR_STATE(NEUR_STATE),
        .NEUR_EVENT_OUT(NEUR_EVENT_OUT),
        .NEUR_V_UP(NEUR_V_UP),
        .NEUR_V_DOWN(NEUR_V_DOWN),
        .NEUR_STATE_MONITOR(NEUR_STATE_MONITOR)
    );
     
        
    
endmodule
