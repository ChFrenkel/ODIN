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
// "fifo.v" - ODIN scheduler FIFO module
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


module fifo #(
	parameter width      = 9,
    parameter depth      = 4,
    parameter depth_addr = 2
)(
    input  wire              clk,
    input  wire              rst_n,
    input  wire              push_req_n,
    input  wire              pop_req_n,
    input  wire [width-1: 0] data_in,
    output reg               empty,
    output wire              full,
    output wire [width-1: 0] data_out
);
  
    reg [width-1:0] mem [0:depth-1]; 

    reg [depth_addr-1:0] write_ptr;
    reg [depth_addr-1:0] read_ptr;
    reg [depth_addr-1:0] fill_cnt;

    genvar i;



    always @(posedge clk, negedge rst_n) begin
        if (!rst_n)
            write_ptr <= 2'b0;
        else if (!push_req_n)
            write_ptr <= write_ptr + {{(depth_addr-1){1'b0}},1'b1};
        else
            write_ptr <= write_ptr;
    end

    always @(posedge clk, negedge rst_n) begin
        if (!rst_n)
            read_ptr <= 2'b0;
        else if (!pop_req_n)
            read_ptr <= read_ptr + {{(depth_addr-1){1'b0}},1'b1};
        else
            read_ptr <= read_ptr;
    end

    always @(posedge clk, negedge rst_n) begin
        if (!rst_n)
            fill_cnt <= 2'b0;
        else if (!push_req_n && pop_req_n && !empty)
            fill_cnt <= fill_cnt + {{(depth_addr-1){1'b0}},1'b1};
        else if (!push_req_n && !pop_req_n)
            fill_cnt <= fill_cnt;
        else if (!pop_req_n && |fill_cnt)
            fill_cnt <= fill_cnt - {{(depth_addr-1){1'b0}},1'b1};
        else
            fill_cnt <= fill_cnt;
    end

    always @(posedge clk, negedge rst_n) begin
        if (!rst_n)
            empty <= 1'b1;
        else if (!push_req_n)
            empty <= 1'b0;
        else if (!pop_req_n)
            empty <= ~|fill_cnt; 
    end

    assign full  =  &fill_cnt;


    generate

        for (i=0; i<depth; i=i+1) begin
            
            always @(posedge clk) begin
                if (!push_req_n && (write_ptr == i))
                    mem[i] <= data_in;
                else 
                    mem[i] <= mem[i];
            end
            
        end
        
    endgenerate

    assign data_out = mem[read_ptr];


endmodule 
