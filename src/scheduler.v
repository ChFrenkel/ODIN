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
// "scheduler.v" - ODIN scheduler module
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

 
module scheduler #(
    parameter                   prio_num = 57,
    parameter                   N = 256,
    parameter                   M = 8
)( 

    // Global inputs ------------------------------------------
    input  wire                 CLK,
    input  wire                 RSTN,
    
    // Inputs from controller ---------------------------------
    input  wire                 CTRL_SCHED_POP_N,
    input  wire [          4:0] CTRL_SCHED_VIRTS,
    input  wire [          7:0] CTRL_SCHED_ADDR,
    input  wire [          6:0] CTRL_SCHED_EVENT_IN,
    
    // Inputs from neurons ------------------------------------
    input  wire [        M-1:0] CTRL_NEURMEM_ADDR,
    input  wire [          6:0] NEUR_EVENT_OUT,
    
    // Inputs from SPI configuration registers ----------------
    input  wire                 SPI_OPEN_LOOP,
    input  wire [         19:0] SPI_BURST_TIMEREF,
    
    // Outputs ------------------------------------------------
    output wire                 SCHED_EMPTY,
    output wire                 SCHED_FULL,
    output wire                 SCHED_BURST_END,
    output wire [         12:0] SCHED_DATA_OUT
);


    wire                   spike_in;
    wire [            2:0] spk_ref;
    wire [            3:0] isi_shift;
     
    reg  [  prio_num- 1:0] push_req_burst_n;
    reg                    push_req_n;
    reg  [  prio_num- 1:0] last_spk_in_burst;

    reg  [            7:0] priority; 
    reg  [           19:0] priority_cnt;
    wire                   rst_priority;

    wire [  prio_num- 1:0] push_req_burst_n_fifo;
    wire [  prio_num- 1:0] last_spk_in_burst_fifo;
    wire [  prio_num- 1:0] empty_burst_fifo;
    wire [  prio_num- 1:0] full_burst_fifo;
    wire [9*prio_num- 1:0] data_out_fifo;
    wire                   last_spk_in_burst_int;

    wire                   empty_main;
    wire                   full_main;
    wire [           12:0] data_out_main;
    wire [  prio_num- 2:0] empty_burst_dummy;
    wire [  prio_num- 2:0] full_burst_dummy;
    wire [9*prio_num-10:0] data_out_burst_dummy;
    wire                   empty_burst;
    wire                   full_burst;
    wire [            7:0] data_out_burst;

    reg                    SPI_OPEN_LOOP_sync_int, SPI_OPEN_LOOP_sync;

    wire                   timestamp_next;

    genvar i;


    // Sync barrier from SPI

    always @(posedge CLK, negedge RSTN) begin
        if(~RSTN) begin
            SPI_OPEN_LOOP_sync_int  <= 1'b0;
            SPI_OPEN_LOOP_sync	    <= 1'b0;
        end
        else begin
            SPI_OPEN_LOOP_sync_int  <= SPI_OPEN_LOOP;
            SPI_OPEN_LOOP_sync	    <= SPI_OPEN_LOOP_sync_int;
        end
    end

    // Splitting event_out into FIFO push commands

    assign spike_in  = (~SPI_OPEN_LOOP_sync & NEUR_EVENT_OUT[6]) | CTRL_SCHED_EVENT_IN[6];
    assign spk_ref   = CTRL_SCHED_EVENT_IN[6] ? CTRL_SCHED_EVENT_IN[5:3] : NEUR_EVENT_OUT[5:3];
    assign isi_shift = CTRL_SCHED_EVENT_IN[6] ? ({1'b0, CTRL_SCHED_EVENT_IN[2:0]} + 4'b1) : ({1'b0, NEUR_EVENT_OUT[2:0]} + 4'b1);

    always @(*) begin

        if (spike_in) begin
            if ((spk_ref == 3'd0) || rst_priority) begin
                push_req_burst_n  = {prio_num{1'b1}};
                push_req_n        = 1'b0;
                last_spk_in_burst = {prio_num{1'b0}};
            end else begin 
                push_req_burst_n  = ~(
                                      ({{(prio_num-1){1'b0}},1'b1}            << ( isi_shift   ) ) |
                                      ({{(prio_num-1){1'b0}},(spk_ref>=3'd2)} << ((isi_shift*2)) ) |
                                      ({{(prio_num-1){1'b0}},(spk_ref>=3'd3)} << ((isi_shift*3)) ) |
                                      ({{(prio_num-1){1'b0}},(spk_ref>=3'd4)} << ((isi_shift*4)) ) |
                                      ({{(prio_num-1){1'b0}},(spk_ref>=3'd5)} << ((isi_shift*5)) ) |
                                      ({{(prio_num-1){1'b0}},(spk_ref>=3'd6)} << ((isi_shift*6)) ) |
                                      ({{(prio_num-1){1'b0}},(spk_ref==3'd7)} << ((isi_shift*7)) ) );
                push_req_n        = 1'b0;
                last_spk_in_burst =  (
                                      ({{(prio_num-1){1'b0}},(spk_ref==3'd1)} << ( isi_shift   ) ) |
                                      ({{(prio_num-1){1'b0}},(spk_ref==3'd2)} << ((isi_shift*2)) ) |
                                      ({{(prio_num-1){1'b0}},(spk_ref==3'd3)} << ((isi_shift*3)) ) |
                                      ({{(prio_num-1){1'b0}},(spk_ref==3'd4)} << ((isi_shift*4)) ) |
                                      ({{(prio_num-1){1'b0}},(spk_ref==3'd5)} << ((isi_shift*5)) ) |
                                      ({{(prio_num-1){1'b0}},(spk_ref==3'd6)} << ((isi_shift*6)) ) |
                                      ({{(prio_num-1){1'b0}},(spk_ref==3'd7)} << ((isi_shift*7)) ) );
            end
        end else begin
            push_req_burst_n  = {prio_num{1'b1}};
            push_req_n        = 1'b1;
            last_spk_in_burst = {prio_num{1'b0}};
        end
    end


    // Priority

    always @(posedge CLK, posedge rst_priority) begin

        if (rst_priority)
            priority_cnt <= 20'b0;
        else
            if (timestamp_next)
                priority_cnt <= 20'b0;
            else 
                priority_cnt <= priority_cnt + 20'b1;

    end

    assign timestamp_next = (priority_cnt == SPI_BURST_TIMEREF);

    always @(posedge CLK, posedge rst_priority) begin

        if (rst_priority)
            priority <= 8'b0;
        else
            if (timestamp_next)
                if (priority == (prio_num - 1))
                    priority <= 8'b0;
                else 
                    priority <= priority + 8'b1;
            else
                priority  <= priority;

    end

    assign rst_priority = ~RSTN || SPI_OPEN_LOOP_sync || (~|SPI_BURST_TIMEREF);


    // FIFO instances

    fifo #(
        .width(13),
        .depth(32),
        .depth_addr(5)
    ) fifo_spike_0 (
        .clk(CLK),
        .rst_n(RSTN),
        .push_req_n(full_main | push_req_n),
        .pop_req_n(empty_main | ~empty_burst | CTRL_SCHED_POP_N),
        .data_in(CTRL_SCHED_EVENT_IN[6] ? {CTRL_SCHED_VIRTS,CTRL_SCHED_ADDR} : {5'b0,CTRL_NEURMEM_ADDR}),
        .empty(empty_main),
        .full(full_main),
        .data_out(data_out_main)
    );

    generate

        for (i=0; i<prio_num; i=i+1) begin
        
            fifo #(
                .width(9),
                .depth(4),
                .depth_addr(5)
            ) fifo_burst (
                .clk(CLK),
                .rst_n(~rst_priority),
                .push_req_n(full_burst_fifo[i] | push_req_burst_n_fifo[i]),//~(~full_burst_fifo[i] & push_req_burst_n_fifo[i])),
                .pop_req_n(~(~empty_burst_fifo[i] & (i == priority)) | CTRL_SCHED_POP_N),
                .data_in({last_spk_in_burst_fifo[i],CTRL_NEURMEM_ADDR}),
                .empty(empty_burst_fifo[i]), 
                .full(full_burst_fifo[i]),
                .data_out(data_out_fifo[9*i+8:9*i])
            );
                  
        end
        
    endgenerate

    assign push_req_burst_n_fifo  = (push_req_burst_n  << priority) | (push_req_burst_n  >> (prio_num - priority));
    assign last_spk_in_burst_fifo = (last_spk_in_burst << priority) | (last_spk_in_burst >> (prio_num - priority));  


    // Output selection

    assign {empty_burst_dummy,empty_burst}                             = empty_burst_fifo >> priority;
    assign {full_burst_dummy,full_burst}                               = full_burst_fifo >> priority;
    assign {data_out_burst_dummy,last_spk_in_burst_int,data_out_burst} = data_out_fifo >> (9*priority);

    assign SCHED_DATA_OUT                                              = empty_burst ? data_out_main : {5'b0,data_out_burst};
    assign SCHED_BURST_END                                             = empty_burst ? 1'b0 : last_spk_in_burst_int;
    assign SCHED_EMPTY                                                 = empty_main && empty_burst;
    assign SCHED_FULL                                                  = full_main;



endmodule
