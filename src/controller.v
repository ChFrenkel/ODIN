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
// "controller.v" - ODIN controller module
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


module controller #(
    parameter N = 256,
    parameter M = 8
)(    

    // Global inputs ------------------------------------------
    input  wire           CLK,
    input  wire           RST,
    
    // Inputs from AER ----------------------------------------
    input  wire   [2*M:0] AERIN_ADDR,
    input  wire           AERIN_REQ,
    output reg            AERIN_ACK,
    
    // Control interface for readback -------------------------
    input  wire           CTRL_READBACK_EVENT,
    input  wire           CTRL_PROG_EVENT,
    input  wire [2*M-1:0] CTRL_SPI_ADDR,
    input  wire     [1:0] CTRL_OP_CODE,
    
    // Inputs from SPI configuration registers ----------------
    input  wire           SPI_GATE_ACTIVITY, 
    output reg            SPI_GATE_ACTIVITY_sync,
    input  wire [  M-1:0] SPI_MONITOR_NEUR_ADDR,
	input  wire           SPI_SDSP_ON_SYN_STIM,
    
    // Inputs from scheduler ----------------------------------
    input  wire           SCHED_EMPTY,
    input  wire           SCHED_FULL,
    input  wire           SCHED_BURST_END,
    input  wire    [12:0] SCHED_DATA_OUT,
    
    // Input from AER output ----------------------------------
    input  wire           AEROUT_CTRL_BUSY,
    
    // Outputs to synaptic core -------------------------------
    output reg    [  7:0] CTRL_PRE_EN,
    output reg            CTRL_BIST_REF,
    output reg            CTRL_SYNARRAY_WE,
    output reg            CTRL_NEURMEM_WE,
    output reg    [ 12:0] CTRL_SYNARRAY_ADDR, 
    output reg    [M-1:0] CTRL_NEURMEM_ADDR,
    output reg            CTRL_SYNARRAY_CS,
    output reg            CTRL_NEURMEM_CS,
    
    // Outputs to neurons -------------------------------------
    output reg            CTRL_NEUR_EVENT, 
    output reg            CTRL_NEUR_TREF,
    output reg      [4:0] CTRL_NEUR_VIRTS,
    output reg            CTRL_NEUR_BURST_END,
    
    // Outputs to scheduler -----------------------------------
    output reg            CTRL_SCHED_POP_N,
    output reg    [M-1:0] CTRL_SCHED_ADDR,
    output reg    [  6:0] CTRL_SCHED_EVENT_IN,
    output reg    [  4:0] CTRL_SCHED_VIRTS,
    
    // Output to AER output -----------------------------------
    output wire           CTRL_AEROUT_POP_NEUR
);
    
	//----------------------------------------------------------------------------------
	//	PARAMETERS 
	//----------------------------------------------------------------------------------

	// FSM states 
	localparam WAIT       = 4'd0; 
    localparam W_NEUR     = 4'd1;
    localparam R_NEUR     = 4'd2;
    localparam W_SYN      = 4'd3;
    localparam R_SYN      = 4'd4;
	localparam TREF       = 4'd5;
	localparam BIST       = 4'd6;
    localparam SYNAPSE    = 4'd7;
    localparam PUSH       = 4'd8;
	localparam POP_NEUR   = 4'd9;
    localparam POP_VIRT   = 4'd10;
    localparam WAIT_SPIDN = 4'd11;
    localparam WAIT_REQDN = 4'd12;

	//----------------------------------------------------------------------------------
	//	REGS & WIRES
	//----------------------------------------------------------------------------------
    
    reg          AERIN_REQ_sync_int, AERIN_REQ_sync;
    reg          SPI_GATE_ACTIVITY_sync_int;
    reg          CTRL_READBACK_EVENT_sync_int, CTRL_READBACK_EVENT_sync;
    reg          CTRL_PROG_EVENT_sync_int, CTRL_PROG_EVENT_sync;

    wire         synapse_event, tref_event, bist_event, virt_event, neuron_event;
    
    reg  [ 31:0] ctrl_cnt;
    reg  [  7:0] neur_cnt;
    reg          neur_cnt_inc;
    
    reg  [  3:0] state, nextstate;
    
	//----------------------------------------------------------------------------------
	//	EVENT TYPE DECODING
	//----------------------------------------------------------------------------------

    assign synapse_event  =                     AERIN_ADDR[2*M];
    assign tref_event     = !synapse_event &&  &AERIN_ADDR[M-2:0];
    assign bist_event     = !synapse_event && ~|AERIN_ADDR[M-2:0];
    assign virt_event     = !synapse_event &&  (AERIN_ADDR[2:0] == 3'b001);
    assign neuron_event   = !synapse_event && !tref_event && !bist_event && !virt_event;

	//----------------------------------------------------------------------------------
	//	SYNC BARRIERS FROM AER AND FROM SPI
	//----------------------------------------------------------------------------------
    
   always @(posedge CLK, posedge RST) begin
		if(RST) begin
			AERIN_REQ_sync_int           <= 1'b0;
			AERIN_REQ_sync	             <= 1'b0;
            SPI_GATE_ACTIVITY_sync_int   <= 1'b0;
            SPI_GATE_ACTIVITY_sync       <= 1'b0;
            CTRL_READBACK_EVENT_sync_int <= 1'b0;
            CTRL_READBACK_EVENT_sync     <= 1'b0;
            CTRL_PROG_EVENT_sync_int     <= 1'b0;
            CTRL_PROG_EVENT_sync         <= 1'b0;
		end
		else begin
			AERIN_REQ_sync_int           <= AERIN_REQ;
			AERIN_REQ_sync	             <= AERIN_REQ_sync_int;
            SPI_GATE_ACTIVITY_sync_int   <= SPI_GATE_ACTIVITY;
            SPI_GATE_ACTIVITY_sync       <= SPI_GATE_ACTIVITY_sync_int & ((nextstate == WAIT) | SPI_GATE_ACTIVITY_sync);
            CTRL_READBACK_EVENT_sync_int <= CTRL_READBACK_EVENT;
            CTRL_READBACK_EVENT_sync     <= CTRL_READBACK_EVENT_sync_int;
            CTRL_PROG_EVENT_sync_int     <= CTRL_PROG_EVENT;
            CTRL_PROG_EVENT_sync         <= CTRL_PROG_EVENT_sync_int;
		end
	end
    
	//----------------------------------------------------------------------------------
	//	CONTROL FSM
	//----------------------------------------------------------------------------------
    
    // State register
	always @(posedge CLK, posedge RST)
	begin
		if   (RST) state <= WAIT;
		else       state <= nextstate;
	end
    
	// Next state logic
	always @(*)
		case(state)
			WAIT 		:	if      (AEROUT_CTRL_BUSY)                                                          nextstate = WAIT;
                            else if (SPI_GATE_ACTIVITY_sync)
                                if      (CTRL_PROG_EVENT_sync     && (CTRL_OP_CODE == 2'b01))                   nextstate = W_NEUR;
                                else if (CTRL_READBACK_EVENT_sync && (CTRL_OP_CODE == 2'b01))                   nextstate = R_NEUR;
                                else if (CTRL_PROG_EVENT_sync     && (CTRL_OP_CODE == 2'b10))                   nextstate = W_SYN;
                                else if (CTRL_READBACK_EVENT_sync && (CTRL_OP_CODE == 2'b10))                   nextstate = R_SYN;
                                else                                                                            nextstate = WAIT;
                            else
                                if (SCHED_FULL)
                                    if      (|SCHED_DATA_OUT[12:8])                                             nextstate = POP_VIRT;
                                    else                                                                        nextstate = POP_NEUR;
                                else if (AERIN_REQ_sync && !bist_event)
                                    if      (tref_event)                                                        nextstate = TREF;
                                    else if (synapse_event)                                                     nextstate = SYNAPSE;
                                    else if (virt_event | neuron_event)                                         nextstate = PUSH;
                                    else                                                                        nextstate = WAIT;
                                else if (~SCHED_EMPTY)
                                    if      (|SCHED_DATA_OUT[12:8])                                             nextstate = POP_VIRT;
                                    else                                                                        nextstate = POP_NEUR;
                                else if (AERIN_REQ_sync && bist_event)                                          nextstate = BIST;
                                else                                                                            nextstate = WAIT;
			W_NEUR    	:   if      (ctrl_cnt == 32'd1 )                                                        nextstate = WAIT_SPIDN;
							else					                                                            nextstate = W_NEUR;
			R_NEUR    	:                                                                                       nextstate = WAIT_SPIDN;
			W_SYN    	:   if      (ctrl_cnt == 32'd1 )                                                        nextstate = WAIT_SPIDN;
							else					                                                            nextstate = W_SYN;
			R_SYN    	:                                                                                       nextstate = WAIT_SPIDN;
			TREF    	:   if      (AERIN_ADDR[M-1] ? (ctrl_cnt == 32'd1) : (&neur_cnt && neur_cnt_inc))       nextstate = WAIT_REQDN;
							else					                                                            nextstate = TREF;
            BIST        :   if      (AERIN_ADDR[M-1] ? (ctrl_cnt == 32'h3F) : (&neur_cnt && &ctrl_cnt[5:0]))    nextstate = WAIT_REQDN;
                            else					                                                            nextstate = BIST;
            SYNAPSE     :   if      (ctrl_cnt == 32'd1)                                                         nextstate = WAIT_REQDN;
                            else					                                                            nextstate = SYNAPSE;
            PUSH        :                                                                                       nextstate = WAIT_REQDN;
			POP_NEUR    :   if      (&ctrl_cnt[8:0])                                                            nextstate = WAIT;
							else					                                                            nextstate = POP_NEUR;                
			POP_VIRT    :   if      (~CTRL_SCHED_POP_N)                                                         nextstate = WAIT;
							else					                                                            nextstate = POP_VIRT;
			WAIT_SPIDN 	:   if      (~CTRL_PROG_EVENT_sync && ~CTRL_READBACK_EVENT_sync)                        nextstate = WAIT;
							else					                                                            nextstate = WAIT_SPIDN;
			WAIT_REQDN 	:   if      (~AERIN_REQ_sync)                                                           nextstate = WAIT;
							else					                                                            nextstate = WAIT_REQDN;
			default		:							                                                            nextstate = WAIT;
		endcase 
        
    // Control counter
	always @(posedge CLK, posedge RST)
		if      (RST)               ctrl_cnt <= 32'd0;
        else if (state == WAIT)     ctrl_cnt <= 32'd0;
		else if (!AEROUT_CTRL_BUSY) ctrl_cnt <= ctrl_cnt + 32'd1;
        else                        ctrl_cnt <= ctrl_cnt;
        
    // Time-multiplexed neuron counter
	always @(posedge CLK, posedge RST)
		if      (RST)                                neur_cnt <= 8'd0;
        else if (state == WAIT)                      neur_cnt <= 8'd0;
		else if (neur_cnt_inc && !AEROUT_CTRL_BUSY)  neur_cnt <= neur_cnt + 8'd1;
        else                                         neur_cnt <= neur_cnt;
        
    assign CTRL_AEROUT_POP_NEUR = (state == POP_NEUR) && (neur_cnt == SPI_MONITOR_NEUR_ADDR) && ctrl_cnt[0];
 
 
 
    // Output logic      
    always @(*) begin
    
        if (state == W_NEUR) begin 
            CTRL_SYNARRAY_ADDR  = 13'b0;
            CTRL_SYNARRAY_CS    = 1'b0;
            CTRL_SYNARRAY_WE    = 1'b0;
            CTRL_NEUR_VIRTS     = 5'b0;
            CTRL_NEUR_BURST_END = 1'b0;
            CTRL_NEUR_EVENT     = 1'b0;
            CTRL_NEUR_TREF      = 1'b0;
            CTRL_PRE_EN         = 8'b0;
            CTRL_BIST_REF       = 1'b0;
            CTRL_SCHED_VIRTS    = 5'b0;
            CTRL_SCHED_ADDR     = 8'b0;
            CTRL_SCHED_EVENT_IN = 7'b0;
            CTRL_SCHED_POP_N    = 1'b1;
            AERIN_ACK           = 1'b0;
            neur_cnt_inc        = 1'b0;  
            
            CTRL_NEURMEM_ADDR   = CTRL_SPI_ADDR[M-1:0];
            CTRL_NEURMEM_CS     = 1'b1;
            if (ctrl_cnt == 32'd0) begin
                CTRL_NEURMEM_WE = 1'b0;
            end else begin
                CTRL_NEURMEM_WE = 1'b1;
            end 
            
        end else if (state == R_NEUR) begin
            CTRL_SYNARRAY_ADDR  = 13'b0;
            CTRL_SYNARRAY_CS    = 1'b0;
            CTRL_SYNARRAY_WE    = 1'b0;
            CTRL_NEUR_VIRTS     = 5'b0;
            CTRL_NEUR_BURST_END = 1'b0;
            CTRL_NEUR_EVENT     = 1'b0;
            CTRL_NEUR_TREF      = 1'b0;
            CTRL_PRE_EN         = 8'b0;
            CTRL_BIST_REF       = 1'b0;
            CTRL_SCHED_VIRTS    = 5'b0;
            CTRL_SCHED_ADDR     = 8'b0;
            CTRL_SCHED_EVENT_IN = 7'b0;
            CTRL_SCHED_POP_N    = 1'b1;
            AERIN_ACK           = 1'b0;
            neur_cnt_inc        = 1'b0;  
            
            CTRL_NEURMEM_ADDR   = CTRL_SPI_ADDR[M-1:0];
            CTRL_NEURMEM_CS     = 1'b1;
            CTRL_NEURMEM_WE     = 1'b0; 
            
        end else if (state == W_SYN) begin
            CTRL_NEURMEM_ADDR   = 8'b0;
            CTRL_NEURMEM_CS     = 1'b0;
            CTRL_NEURMEM_WE     = 1'b0;
            CTRL_NEUR_VIRTS     = 5'b0;
            CTRL_NEUR_BURST_END = 1'b0;
            CTRL_NEUR_EVENT     = 1'b0;
            CTRL_NEUR_TREF      = 1'b0;
            CTRL_PRE_EN         = 8'b0;
            CTRL_BIST_REF       = 1'b0;
            CTRL_SCHED_VIRTS    = 5'b0;
            CTRL_SCHED_ADDR     = 8'b0;
            CTRL_SCHED_EVENT_IN = 7'b0;
            CTRL_SCHED_POP_N    = 1'b1;
            AERIN_ACK           = 1'b0;
            neur_cnt_inc        = 1'b0;  
            
            CTRL_SYNARRAY_ADDR  = CTRL_SPI_ADDR[12:0];
            CTRL_SYNARRAY_CS    = 1'b1;
            if (ctrl_cnt == 32'd0) begin
                CTRL_SYNARRAY_WE = 1'b0;
            end else begin
                CTRL_SYNARRAY_WE = 1'b1;
            end 
            
        end else if (state == R_SYN) begin  
            CTRL_NEURMEM_ADDR   = 8'b0;
            CTRL_NEURMEM_CS     = 1'b0;
            CTRL_NEURMEM_WE     = 1'b0;
            CTRL_NEUR_VIRTS     = 5'b0;
            CTRL_NEUR_BURST_END = 1'b0;
            CTRL_NEUR_EVENT     = 1'b0;
            CTRL_NEUR_TREF      = 1'b0;
            CTRL_PRE_EN         = 8'b0;
            CTRL_BIST_REF       = 1'b0;
            CTRL_SCHED_VIRTS    = 5'b0;
            CTRL_SCHED_ADDR     = 8'b0;
            CTRL_SCHED_EVENT_IN = 7'b0;
            CTRL_SCHED_POP_N    = 1'b1;
            AERIN_ACK           = 1'b0;
            neur_cnt_inc        = 1'b0;  
            
            CTRL_SYNARRAY_ADDR   = CTRL_SPI_ADDR[12:0];
            CTRL_SYNARRAY_CS     = 1'b1;
            CTRL_SYNARRAY_WE     = 1'b0;
            
        end else if (state == TREF) begin
            CTRL_SYNARRAY_ADDR  = 13'b0;
            CTRL_SYNARRAY_CS    = 1'b0;
            CTRL_SYNARRAY_WE    = 1'b0;
            CTRL_NEUR_VIRTS     = 5'b0;
            CTRL_NEUR_BURST_END = 1'b0;
            CTRL_PRE_EN         = 8'b0;
            CTRL_BIST_REF       = 1'b0;
            CTRL_SCHED_VIRTS    = 5'b0;
            CTRL_SCHED_ADDR     = 8'b0;
            CTRL_SCHED_EVENT_IN = 7'b0;
            CTRL_SCHED_POP_N    = 1'b1;
            AERIN_ACK           = 1'b0;
            
            CTRL_NEURMEM_ADDR   = AERIN_ADDR[M-1] ? AERIN_ADDR[2*M-1:M] : neur_cnt;
            CTRL_NEUR_EVENT     = 1'b1;
            CTRL_NEUR_TREF      = 1'b1;
            CTRL_NEURMEM_CS     = 1'b1;
            if (ctrl_cnt[0] == 1'd0) begin
                CTRL_NEURMEM_WE = 1'b0;
                neur_cnt_inc    = 1'b0;
            end else begin
                CTRL_NEURMEM_WE = 1'b1;
                neur_cnt_inc    = ~AERIN_ADDR[M-1];
            end
            
        end else if (state == BIST) begin
            CTRL_NEURMEM_ADDR   = 8'b0;
            CTRL_NEURMEM_CS     = 1'b0;
            CTRL_NEURMEM_WE     = 1'b0;
            CTRL_NEUR_VIRTS     = 5'b0;
            CTRL_NEUR_BURST_END = 1'b0;
            CTRL_NEUR_EVENT     = 1'b0;
            CTRL_NEUR_TREF      = 1'b0;
            CTRL_SCHED_VIRTS    = 5'b0;
            CTRL_SCHED_ADDR     = 8'b0;
            CTRL_SCHED_EVENT_IN = 7'b0;
            CTRL_SCHED_POP_N    = 1'b1;
            AERIN_ACK           = 1'b0;
            
            CTRL_SYNARRAY_ADDR  = AERIN_ADDR[M-1] ? {AERIN_ADDR[2*M-1:M],ctrl_cnt[5:1]} : {neur_cnt,ctrl_cnt[5:1]};
            CTRL_PRE_EN         = 8'hFF;
            CTRL_BIST_REF       = 1'b1;
            CTRL_SYNARRAY_CS    = 1'b1;
            if (ctrl_cnt[0] == 1'd0) begin
                CTRL_SYNARRAY_WE = 1'b0;
                neur_cnt_inc     = 1'b0;
            end else begin
                CTRL_SYNARRAY_WE = 1'b1;
                neur_cnt_inc     = AERIN_ADDR[M-1] ? 1'b0 : &ctrl_cnt[5:1];
            end 
            
        end else if (state == SYNAPSE) begin 
            CTRL_NEUR_VIRTS     = 5'b0;
            CTRL_NEUR_BURST_END = 1'b0;
            CTRL_NEUR_TREF      = 1'b0;
            CTRL_BIST_REF       = 1'b0;
            CTRL_SCHED_VIRTS    = 5'b0;
            CTRL_SCHED_ADDR     = 8'b0;
            CTRL_SCHED_EVENT_IN = 7'b0;
            CTRL_SCHED_POP_N    = 1'b1;
            AERIN_ACK           = 1'b0;
            neur_cnt_inc        = 1'b0;
            
            CTRL_SYNARRAY_ADDR  = AERIN_ADDR[2*M-1:3];
            CTRL_NEURMEM_ADDR   = AERIN_ADDR[M-1:0];
            CTRL_PRE_EN         = {7'b0, SPI_SDSP_ON_SYN_STIM} << AERIN_ADDR[2:0];
            CTRL_NEUR_EVENT     = 1'b1;
            CTRL_SYNARRAY_CS    = 1'b1;
            CTRL_NEURMEM_CS     = 1'b1;
            if (ctrl_cnt == 32'd0) begin
                CTRL_SYNARRAY_WE = 1'b0;
                CTRL_NEURMEM_WE  = 1'b0;
            end else begin
                CTRL_SYNARRAY_WE = 1'b1;
                CTRL_NEURMEM_WE  = 1'b1;
            end
        
        end else if (state == PUSH) begin
            CTRL_SYNARRAY_ADDR  = 13'b0;
            CTRL_SYNARRAY_CS    = 1'b0;
            CTRL_SYNARRAY_WE    = 1'b0;
            CTRL_NEURMEM_ADDR   = 8'b0;
            CTRL_NEURMEM_CS     = 1'b0;
            CTRL_NEURMEM_WE     = 1'b0;
            CTRL_NEUR_VIRTS     = 5'b0;
            CTRL_NEUR_BURST_END = 1'b0;
            CTRL_NEUR_EVENT     = 1'b0;
            CTRL_NEUR_TREF      = 1'b0;
            CTRL_PRE_EN         = 8'b0;
            CTRL_BIST_REF       = 1'b0;
            CTRL_SCHED_POP_N    = 1'b1;
            AERIN_ACK           = 1'b0;
            neur_cnt_inc        = 1'b0;
            
            CTRL_SCHED_VIRTS    = AERIN_ADDR[M-1:M-5];
            CTRL_SCHED_ADDR     = AERIN_ADDR[2*M-1:M];
            CTRL_SCHED_EVENT_IN = 7'h40;

        end else if (state == POP_NEUR) begin  
            CTRL_NEUR_VIRTS     = 5'b0;
            CTRL_NEUR_TREF      = 1'b0;
            CTRL_BIST_REF       = 1'b0;
            CTRL_SCHED_VIRTS    = 5'b0;
            CTRL_SCHED_ADDR     = 8'b0;
            CTRL_SCHED_EVENT_IN = 7'b0;
            AERIN_ACK           = 1'b0;
            
            CTRL_SYNARRAY_ADDR  = {SCHED_DATA_OUT[M-1:0],neur_cnt[7:3]};
            CTRL_PRE_EN         = (ctrl_cnt[3:0] == 4'b0001) ? 8'hFF : 8'b0;
            CTRL_SYNARRAY_CS    = ~|neur_cnt[2:0];
            CTRL_SYNARRAY_WE    = (ctrl_cnt[3:0] == 4'b0001);
            CTRL_NEURMEM_ADDR   = neur_cnt;  
            CTRL_NEUR_BURST_END = (SCHED_DATA_OUT[M-1:0] == neur_cnt) && SCHED_BURST_END;
            CTRL_SCHED_POP_N    = ~&ctrl_cnt[8:0];
            CTRL_NEUR_EVENT     = 1'b1;
            CTRL_NEURMEM_CS     = 1'b1;
            if (ctrl_cnt[0] == 1'b0) begin
                CTRL_NEURMEM_WE = 1'b0;
                neur_cnt_inc    = 1'b0;
            end else begin
                CTRL_NEURMEM_WE = 1'b1;
                neur_cnt_inc    = 1'b1;    
            end 
        
        end else if (state == POP_VIRT) begin  
            CTRL_SYNARRAY_ADDR  = 13'b0;
            CTRL_SYNARRAY_CS    = 1'b0;
            CTRL_SYNARRAY_WE    = 1'b0;
            CTRL_NEUR_BURST_END = 1'b0;
            CTRL_NEUR_TREF      = 1'b0;
            CTRL_PRE_EN         = 8'b0;
            CTRL_BIST_REF       = 1'b0;
            CTRL_SCHED_VIRTS    = 5'b0;
            CTRL_SCHED_ADDR     = 8'b0;
            CTRL_SCHED_EVENT_IN = 7'b0;
            AERIN_ACK           = 1'b0;
            neur_cnt_inc        = 1'b0;
            
            CTRL_NEURMEM_ADDR   = SCHED_DATA_OUT[M-1:0];
            CTRL_NEUR_VIRTS     = SCHED_DATA_OUT[ 12:M];
            CTRL_NEUR_EVENT     = 1'b1;
            CTRL_NEURMEM_CS     = 1'b1;
            if (ctrl_cnt == 32'd0) begin
                CTRL_NEURMEM_WE  = 1'b0;
                CTRL_SCHED_POP_N = 1'b1;
            end else begin
                CTRL_NEURMEM_WE  = 1'b1;
                CTRL_SCHED_POP_N = 1'b0;
            end
        
        end else if (state == WAIT_REQDN) begin
            CTRL_SYNARRAY_ADDR  = 13'b0;
            CTRL_SYNARRAY_CS    = 1'b0;
            CTRL_SYNARRAY_WE    = 1'b0;
            CTRL_NEURMEM_ADDR   = 8'b0;
            CTRL_NEURMEM_CS     = 1'b0;
            CTRL_NEURMEM_WE     = 1'b0;
            CTRL_NEUR_VIRTS     = 5'b0;
            CTRL_NEUR_BURST_END = 1'b0;
            CTRL_NEUR_EVENT     = 1'b0;
            CTRL_NEUR_TREF      = 1'b0;
            CTRL_PRE_EN         = 8'b0;
            CTRL_BIST_REF       = 1'b0;
            CTRL_SCHED_VIRTS    = 5'b0;
            CTRL_SCHED_ADDR     = 8'b0;
            CTRL_SCHED_EVENT_IN = 7'b0;
            CTRL_SCHED_POP_N    = 1'b1;
            neur_cnt_inc        = 1'b0;
            
            AERIN_ACK           = 1'b1;

        end else begin
            CTRL_SYNARRAY_ADDR  = 13'b0;
            CTRL_SYNARRAY_CS    = 1'b0;
            CTRL_SYNARRAY_WE    = 1'b0;
            CTRL_NEURMEM_ADDR   = 8'b0;
            CTRL_NEURMEM_CS     = 1'b0;
            CTRL_NEURMEM_WE     = 1'b0;
            CTRL_NEUR_VIRTS     = 5'b0;
            CTRL_NEUR_BURST_END = 1'b0;
            CTRL_NEUR_EVENT     = 1'b0;
            CTRL_NEUR_TREF      = 1'b0;
            CTRL_PRE_EN         = 8'b0;
            CTRL_BIST_REF       = 1'b0;
            CTRL_SCHED_VIRTS    = 5'b0;
            CTRL_SCHED_ADDR     = 8'b0;
            CTRL_SCHED_EVENT_IN = 7'b0;
            CTRL_SCHED_POP_N    = 1'b1;
            AERIN_ACK           = 1'b0;
            neur_cnt_inc        = 1'b0;
        end
    end

    
endmodule

