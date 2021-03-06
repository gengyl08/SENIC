/*******************************************************************************
 *
 *  NetFPGA-10G http://www.netfpga.org
 *
 *  File:
 *        tx_ctrl.v
 *
 *  Library:
 *        hw/contrib/pcores/dma_v1_00_a
 *
 *  Module:
 *        dma
 *
 *  Author:
 *        Mario Flajslik
 *
 *  Description:
 *        This module controls the transmision of packets on the AXIS interface.
 *        It also manages TX descriptors on the card, sending DMA reads for
 *        fetching new packets, as well as realignment of data on the
 *        AXIS interface, if neccessary.
 *
 *  Copyright notice:
 *        Copyright (C) 2010, 2011 The Board of Trustees of The Leland Stanford
 *                                 Junior University
 *
 *  Licence:
 *        This file is part of the NetFPGA 10G development base package.
 *
 *        This file is free code: you can redistribute it and/or modify it under
 *        the terms of the GNU Lesser General Public License version 2.1 as
 *        published by the Free Software Foundation.
 *
 *        This package is distributed in the hope that it will be useful, but
 *        WITHOUT ANY WARRANTY; without even the implied warranty of
 *        MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 *        Lesser General Public License for more details.
 *
 *        You should have received a copy of the GNU Lesser General Public
 *        License along with the NetFPGA source package.  If not, see
 *        http://www.gnu.org/licenses/.
 *
 */

`include "dma_defs.vh"

module tx_ctrl
  (
   input logic [63:0]                 mem_tx_dne_head,
   input logic [63:0]                 mem_tx_doorbell_dne_head,

   output logic [63:0]                dma_start,
   output logic [63:0]                dma_end,

   output logic [19:0]                mem_tx_doorbell_head,

   // feedback task queue
   output logic                       feedback_task_q_enq_en,
   output logic [195:0]               feedback_task_q_enq_data,
   input logic                        feedback_task_q_full,

   // doorbell dne queue
   output logic                       doorbell_dne_q_deq_en,
   input logic [31:0]                 doorbell_dne_q_deq_data,
   input logic                        doorbell_dne_q_empty,

   // tx task queue inputs
   output logic                       tx_task_q_deq_en,
   input logic [381:0]                tx_task_q_data,
   input logic                        tx_task_q_empty,

   // doorbell task queue output
   output logic                       doorbell_task_q_enq_en,
   output logic [127:0]               doorbell_task_q_data,
   input logic                        doorbell_task_q_full,
  
   // memory read interfaces
   output logic [`MEM_ADDR_BITS-1:0]  mem_tx_dsc_rd_addr,
   input logic [63:0]                 mem_tx_dsc_rd_data,
   output logic                       mem_tx_dsc_rd_en,

   output logic [`MEM_ADDR_BITS-1:0]  mem_tx_doorbell_rd_addr,
   input logic [63:0]                 mem_tx_doorbell_rd_data,
   output logic                       mem_tx_doorbell_rd_en,

   output logic [`MEM_ADDR_BITS-1:0]  mem_tx_pkt_rd_addr,
   input logic [63:0]                 mem_tx_pkt_rd_data,
   output logic                       mem_tx_pkt_rd_en,

   // memory write interfaces
   output logic [`MEM_ADDR_BITS-1:0]  mem_tx_doorbell_dne_wr_addr,
   output logic [63:0]                mem_tx_doorbell_dne_wr_data,
   output logic [7:0]                 mem_tx_doorbell_dne_wr_mask,
   output logic                       mem_tx_doorbell_dne_wr_en,

   output logic [`MEM_ADDR_BITS-1:0]  mem_tx_dne_wr_addr,
   output logic [63:0]                mem_tx_dne_wr_data,
   output logic [7:0]                 mem_tx_dne_wr_mask,
   output logic                       mem_tx_dne_wr_en,

   // memory valid interfaces
   output logic [`MEM_ADDR_BITS-12:0] mem_vld_tx_doorbell_wr_addr,
   output logic [31:0]                mem_vld_tx_doorbell_wr_mask,
   output logic                       mem_vld_tx_doorbell_wr_clear,
   input logic                        mem_vld_tx_doorbell_wr_stall,
   input logic                        mem_vld_tx_doorbell_rd_bit,

   output logic [`MEM_ADDR_BITS-12:0] mem_vld_tx_doorbell_dne_wr_addr,
   output logic [31:0]                mem_vld_tx_doorbell_dne_wr_mask,
   output logic                       mem_vld_tx_doorbell_dne_wr_clear,
   input logic                        mem_vld_tx_doorbell_dne_wr_stall,

   output logic [`MEM_ADDR_BITS-12:0] mem_vld_tx_dsc_wr_addr,
   output logic [31:0]                mem_vld_tx_dsc_wr_mask,
   output logic                       mem_vld_tx_dsc_wr_clear,
   input logic                        mem_vld_tx_dsc_wr_stall,
   input logic                        mem_vld_tx_dsc_rd_bit,

   output logic [`MEM_ADDR_BITS-12:0] mem_vld_tx_pkt_wr_addr,
   output logic [31:0]                mem_vld_tx_pkt_wr_mask,
   output logic                       mem_vld_tx_pkt_wr_clear,
   input logic                        mem_vld_tx_pkt_wr_stall,
   input logic                        mem_vld_tx_pkt_rd_bit,
   
   output logic [`MEM_ADDR_BITS-12:0] mem_vld_tx_dne_wr_addr,
   output logic [31:0]                mem_vld_tx_dne_wr_mask,
   output logic                       mem_vld_tx_dne_wr_clear,
   input logic                        mem_vld_tx_dne_wr_stall,

   // config registers
   input logic [63:0]                 tx_doorbell_mask,
   input logic [63:0]                 tx_doorbell_dne_mask,
   input logic [63:0]                 tx_dsc_mask,
   input logic [63:0]                 tx_pkt_mask,
   input logic [63:0]                 tx_dne_mask,
   input logic [63:0]                 rx_dsc_mask,

   // pcie read queue interface
   output logic                       rd_q_enq_en,
   output logic [`RD_Q_WIDTH-1:0]     rd_q_enq_data,
   input logic                        rd_q_full,
   
   // MAC interface
   output logic [63:0]                M_AXIS_TDATA,
   output logic [7:0]                 M_AXIS_TSTRB,
   output logic                       M_AXIS_TVALID,
   input logic                        M_AXIS_TREADY,
   output logic                       M_AXIS_TLAST,
   output logic [127:0]               M_AXIS_TUSER,

   // stats
   output logic [63:0]                stat_mac_tx_ts,
   output logic [31:0]                stat_mac_tx_word_cnt,
   output logic [31:0]                stat_mac_tx_pkt_cnt,

   // misc
   input logic                        clk,
   input logic                        rst
   );   
   
   // ----------------------------------
   // -- mem pointers
   // ----------------------------------
   logic [`MEM_ADDR_BITS-1:0]        mem_tx_doorbell_head_nxt;

   logic [`MEM_ADDR_BITS-1:0]        mem_tx_doorbell_dne_tail, mem_tx_doorbell_dne_tail_nxt;
   logic [`MEM_ADDR_BITS-1:0]        mem_tx_doorbell_dne_clear;

   logic [`MEM_ADDR_BITS-1:0]        mem_tx_dsc_head, mem_tx_dsc_head_nxt;
   logic [`MEM_ADDR_BITS-1:0]        mem_tx_dsc_tail, mem_tx_dsc_tail_nxt;

   logic [`MEM_ADDR_BITS-1:0]        mem_tx_pkt_head_bk, mem_tx_pkt_head_bk_nxt;  
   logic [`MEM_ADDR_BITS-1:0]        mem_tx_pkt_head, mem_tx_pkt_head_nxt;
   logic [`MEM_ADDR_BITS-1:0]        mem_tx_pkt_end,  mem_tx_pkt_end_nxt;
   logic [`MEM_ADDR_BITS-1:0]        mem_tx_pkt_tail,  mem_tx_pkt_tail_nxt;

   logic [`MEM_ADDR_BITS-1:0]        mem_tx_dne_tail, mem_tx_dne_tail_nxt;
   logic [`MEM_ADDR_BITS-1:0]        mem_tx_dne_clear;

   // ----------------------------------
   // -- stats
   // ----------------------------------
   logic [63:0]                      time_stamp;
   logic [63:0]                      stat_mac_tx_ts_nxt;
   logic [31:0]                      stat_mac_tx_word_cnt_nxt;
   logic [31:0]                      stat_mac_tx_pkt_cnt_nxt;

   logic [63:0]                      dma_start_nxt;
   logic [63:0]                      dma_end_nxt;

   always_comb begin
      stat_mac_tx_ts_nxt       = stat_mac_tx_ts;
      stat_mac_tx_word_cnt_nxt = stat_mac_tx_word_cnt;
      stat_mac_tx_pkt_cnt_nxt  = stat_mac_tx_pkt_cnt;

      if(M_AXIS_TVALID & M_AXIS_TREADY) begin
         stat_mac_tx_ts_nxt        = time_stamp;
         stat_mac_tx_word_cnt_nxt  = stat_mac_tx_word_cnt + 1;
         if(M_AXIS_TLAST) 
           stat_mac_tx_pkt_cnt_nxt = stat_mac_tx_pkt_cnt_nxt + 1;
      end
   end
   
   always_ff @(posedge clk) begin
      if(rst) begin
         time_stamp           <= 0;
         stat_mac_tx_ts       <= 0;
         stat_mac_tx_word_cnt <= 0;
         stat_mac_tx_pkt_cnt  <= 0;
         dma_start <= 0;
         dma_end <= 0;
      end
      else begin
         time_stamp           <= time_stamp + 1;
         stat_mac_tx_ts       <= stat_mac_tx_ts_nxt;
         stat_mac_tx_word_cnt <= stat_mac_tx_word_cnt_nxt;
         stat_mac_tx_pkt_cnt  <= stat_mac_tx_pkt_cnt_nxt;
         dma_start <= dma_start_nxt;
         dma_end <= dma_end_nxt;
      end
   end

   // -------------------------------------------
   // -- limit the number in flight dma mem reads
   // -------------------------------------------
   logic in_flight_counter_wr_en;
   logic in_flight_counter_rd_en;
   logic in_flight_counter_full;
   logic in_flight_counter_empty;

   logic dsc_cm_counter_wr_en;
   logic dsc_cm_counter_rd_en;
   logic dsc_cm_counter_full;
   logic dsc_cm_counter_empty;

   logic pkt_cm_counter_wr_en;
   logic pkt_cm_counter_rd_en;
   logic pkt_cm_counter_full;
   logic pkt_cm_counter_empty;

   counter_fifo #(.MAX(2)) in_flight_counter(.wr_en(in_flight_counter_wr_en),
                                             .rd_en(in_flight_counter_rd_en),
                                             .full(in_flight_counter_full),
                                             .empty(in_flight_counter_empty),
                                             .rst(rst),
                                             .clk(clk));

   counter_fifo #(.MAX(8)) dsc_cm_counter(.wr_en(dsc_cm_counter_wr_en),
                                          .rd_en(dsc_cm_counter_rd_en),
                                          .full(dsc_cm_counter_full),
                                          .empty(dsc_cm_counter_empty),
                                          .rst(rst),
                                          .clk(clk));

   counter_fifo #(.MAX(8)) pkt_cm_counter(.wr_en(pkt_cm_counter_wr_en),
                                          .rd_en(pkt_cm_counter_rd_en),
                                          .full(pkt_cm_counter_full),
                                          .empty(pkt_cm_counter_empty),
                                          .rst(rst),
                                          .clk(clk));

   always_comb begin

      dsc_cm_counter_rd_en = 0;
      pkt_cm_counter_rd_en = 0;
      in_flight_counter_rd_en = 0;

      if(!dsc_cm_counter_empty && !in_flight_counter_empty) begin
         dsc_cm_counter_rd_en = 1;
         in_flight_counter_rd_en = 1;
      end
      else if(!pkt_cm_counter_empty && !in_flight_counter_empty) begin
         pkt_cm_counter_rd_en = 1;
         in_flight_counter_rd_en = 1;
      end
   end
   
   // ----------------------------------
   // -- local signals
   // ----------------------------------
   /* verilator lint_off UNOPTFLAT */
   logic                             dma_rd_go;
   logic                             dma_rd_done;
   logic [63:0]                      dma_rd_host_addr;
   /* verilator lint_on UNOPTFLAT */
   logic [15:0]                      dma_rd_len;
   logic [`MEM_ADDR_BITS-1:0]        dma_rd_local_addr;
   logic [15:0]                      dma_rd_pkt_port;
   
   logic                             rd_q_enq_en_nxt;
   logic [`RD_Q_WIDTH-1:0]           rd_q_enq_data_nxt;

   // ----------------------------------
   // -- tx pending queue
   // ----------------------------------
   logic                           tx_pend_q_enq_en;
   logic [2*`MEM_ADDR_BITS+16-1:0] tx_pend_q_enq_data;
   logic                           tx_pend_q_deq_en;
   logic [2*`MEM_ADDR_BITS+16-1:0] tx_pend_q_deq_data;
   logic                           tx_pend_q_empty;                        
   logic                           tx_pend_q_full;
   
   fifo #(.WIDTH(`MEM_ADDR_BITS*2+16), .DEPTH(`TX_PENDING_DEPTH))
   u_tx_pending_q(.enq_en(tx_pend_q_enq_en),
                  .enq_data(tx_pend_q_enq_data),
                  .deq_en(tx_pend_q_deq_en),
                  .deq_data(tx_pend_q_deq_data),
                  .empty(tx_pend_q_empty),
                  .almost_full(),
                  .full(tx_pend_q_full),
                  .enq_clk(clk),
                  .deq_clk(clk),
                  .*);

   // ----------------------------------
   // -- Send DMA dsc+pkt reads
   // ----------------------------------

   localparam SEND_DMA_RD_STATE_IDLE = 0;
   localparam SEND_DMA_RD_STATE_DSC = 1;
   localparam SEND_DMA_RD_STATE_PKT = 2;
   localparam SEND_DMA_RD_STATE_END = 3;
   localparam SEND_DMA_RD_STATE_WAIT = 4;
   localparam SEND_DMA_RD_STATE_DEAD = 5;
   
   logic [2:0] send_dma_rd_state, send_dma_rd_state_nxt;
   logic [9:0] class_index, class_index_nxt;
   logic [63:0] tokens, tokens_l, tokens_nxt;
   logic [63:0] rate, rate_nxt;
   logic [63:0] dsc_buffer_host_addr, dsc_buffer_host_addr_nxt;
   logic [31:0] dsc_buffer_mask, dsc_buffer_mask_nxt;
   logic [25:0] dsc_head_index, dsc_head_index_l, dsc_head_index_nxt;
   logic [25:0] dsc_tail_index, dsc_tail_index_nxt;
   logic [63:0] pkt_host_addr_first, pkt_host_addr_first_nxt;
   logic [19:0] pkt_local_addr_first, pkt_local_addr_first_nxt;
   logic [15:0] pkt_len_first, pkt_len_first_nxt;
   logic [15:0] pkt_port_first, pkt_port_first_nxt;

   logic use_mem_tx_dsc, use_mem_tx_dsc_nxt;
   logic [63:0] pkt_host_addr;
   logic [19:0] pkt_local_addr;
   logic [19:0] pkt_end_addr;
   logic [15:0] pkt_len;
   logic [15:0] pkt_port;

   logic dsc_in_fly, dsc_in_fly_nxt;
   logic [63:0] tokens_needed;
   assign tokens_needed[63:27] = 0;
   assign tokens_needed[26:0] = pkt_len[10:0] * rate[15:0];

   logic tx_dne_ready;
   assign tx_dne_ready = (((mem_tx_dne_tail + 64*8) & tx_dne_mask[`MEM_ADDR_BITS-1:0]) != mem_tx_dne_head[`MEM_ADDR_BITS-1:0]);
   logic tx_doorbell_dne_ready;
   assign tx_doorbell_dne_ready = (((mem_tx_doorbell_dne_tail + 64*8) & tx_doorbell_dne_mask[`MEM_ADDR_BITS-1:0]) != mem_tx_doorbell_dne_head[`MEM_ADDR_BITS-1:0]);

   
   always_comb begin
   
      send_dma_rd_state_nxt = send_dma_rd_state;
      class_index_nxt = class_index;
      tokens = tokens_l;
      tokens_nxt = tokens_l;
      rate_nxt = rate;
      dsc_buffer_host_addr_nxt = dsc_buffer_host_addr;
      dsc_buffer_mask_nxt = dsc_buffer_mask;
      dsc_head_index = dsc_head_index_l;
      dsc_head_index_nxt = dsc_head_index_l;
      dsc_tail_index_nxt = dsc_tail_index;
      pkt_host_addr_first_nxt = pkt_host_addr_first;
      pkt_local_addr_first_nxt = pkt_local_addr_first;
      pkt_len_first_nxt = pkt_len_first;
      pkt_port_first_nxt = pkt_port_first;
      mem_tx_dsc_tail_nxt = mem_tx_dsc_tail;
      mem_tx_pkt_tail_nxt = mem_tx_pkt_tail;
      use_mem_tx_dsc_nxt = use_mem_tx_dsc;
      dsc_in_fly_nxt = dsc_in_fly;
      dma_rd_done = 0;
      tx_pend_q_enq_data = 0;
      tx_pend_q_enq_en   = 0;
      tx_task_q_deq_en = 0;

      in_flight_counter_wr_en = 0;

      if(~rd_q_full) begin
         rd_q_enq_en_nxt = 0;
         rd_q_enq_data_nxt = 0; 
      end
      else begin
         rd_q_enq_en_nxt = rd_q_enq_en;
         rd_q_enq_data_nxt = rd_q_enq_data;
      end

      if(use_mem_tx_dsc) begin
         pkt_host_addr = dma_rd_host_addr;
         pkt_local_addr = dma_rd_local_addr;
         pkt_end_addr = dma_rd_local_addr + {{(`MEM_ADDR_BITS-$bits(dma_rd_len)){1'b0}}, dma_rd_len};
         pkt_len = dma_rd_len;
         pkt_port = dma_rd_pkt_port;
      end
      else begin
         pkt_host_addr = pkt_host_addr_first;
         pkt_local_addr = pkt_local_addr_first;
         pkt_end_addr = pkt_local_addr_first + {{(`MEM_ADDR_BITS-$bits(pkt_len_first)){1'b0}}, pkt_len_first};
         pkt_len = pkt_len_first;
         pkt_port = pkt_port_first;
      end

      mem_tx_dne_clear        = (mem_tx_dne_tail + 64*8) & tx_dne_mask[`MEM_ADDR_BITS-1:0];
      mem_vld_tx_dne_wr_addr  = mem_tx_dne_clear[`MEM_ADDR_BITS-1:11];
      mem_vld_tx_dne_wr_mask  = 1 << mem_tx_dne_clear[10:6];
      mem_vld_tx_dne_wr_clear = 0;

      mem_tx_dne_wr_en     = 0;
      mem_tx_dne_wr_mask   = 8'hff;
      mem_tx_dne_wr_data   = 0;
      mem_tx_dne_wr_addr   = 0;
      mem_tx_dne_tail_nxt  = mem_tx_dne_tail;

      // feedback task queue
      feedback_task_q_enq_en = 0;
      feedback_task_q_enq_data = 0;

      dma_start_nxt = dma_start;
      
      case(send_dma_rd_state)
         SEND_DMA_RD_STATE_IDLE: begin
            if(~tx_task_q_empty /* && !mem_vld_tx_dne_wr_stall && tx_dne_ready*/) begin
               // read tokens, buffer information and first descriptor from task queue
               tx_task_q_deq_en = 1;

               {class_index_nxt,
               tokens,
               rate_nxt,
               dsc_buffer_host_addr_nxt,
               dsc_buffer_mask_nxt,
               dsc_head_index_nxt,
               dsc_tail_index_nxt,
               pkt_host_addr_first_nxt,
               pkt_len_first_nxt,
               pkt_port_first_nxt} = tx_task_q_data;

               pkt_local_addr_first_nxt = mem_tx_pkt_tail + pkt_host_addr_first_nxt[5:0];
               // scheduler should inforce initial bigger relationship
               tokens_nxt = tokens - pkt_len_first_nxt[10:0] * rate_nxt[15:0];
               use_mem_tx_dsc_nxt = 0;

               /*
               // debug begin
               mem_tx_dne_wr_en = 1;
               mem_tx_dne_wr_mask = 8'hff;
               mem_tx_dne_wr_data[15:0] = 'd1;
               mem_tx_dne_wr_data[31:16] = 16'd11;
               mem_tx_dne_wr_data[63:32] = {dsc_tail_index_nxt[15:0], dsc_head_index_nxt[15:0]};
               mem_tx_dne_wr_addr = mem_tx_dne_tail;
               mem_tx_dne_tail_nxt = (mem_tx_dne_tail + 64) & tx_dne_mask[`MEM_ADDR_BITS-1:0];
               mem_vld_tx_dne_wr_clear = 1;
               // debug end
               */
               

               if(dsc_head_index_nxt != dsc_tail_index_nxt) begin
                  dsc_in_fly_nxt = 1;
                  send_dma_rd_state_nxt = SEND_DMA_RD_STATE_DSC;
               end
               else begin
                  dsc_in_fly_nxt = 0;
                  send_dma_rd_state_nxt = SEND_DMA_RD_STATE_PKT;
               end
            end
         end

         SEND_DMA_RD_STATE_DSC: begin
            // the software has to make sure the
            // descriptor buffer is 64 bytes word aligned. One descriptor is
            // 64 bytes long on host. Acutal length is 16 bytes.
            if(~rd_q_full && /*!mem_vld_tx_dne_wr_stall && tx_dne_ready &&*/ !in_flight_counter_full) begin

               rd_q_enq_en_nxt = 1;
               rd_q_enq_data_nxt[15:0] = 16'd64;
               rd_q_enq_data_nxt[19:16] = `ID_MEM_TX_DSC; // mem_select
               rd_q_enq_data_nxt[83:20] = dsc_buffer_host_addr + {{(58-$bits(dsc_head_index)){1'b0}},dsc_head_index, 6'b0}; // host addr
               rd_q_enq_data_nxt[84+:`MEM_ADDR_BITS] = mem_tx_dsc_tail; // addr
               // move host dsc head ahead
               dsc_head_index_nxt = (dsc_head_index + 1) & dsc_buffer_mask[31:6];
               // move mem dsc tail ahead
               mem_tx_dsc_tail_nxt = (mem_tx_dsc_tail + 64) & tx_dsc_mask[`MEM_ADDR_BITS-1:0];
               // go to next state
               send_dma_rd_state_nxt = SEND_DMA_RD_STATE_PKT;
               // count in flight mem read request
               in_flight_counter_wr_en = 1;

               dma_start_nxt = time_stamp;


               /*
               // debug begin
               mem_tx_dne_wr_en = 1;
               mem_tx_dne_wr_mask = 8'hff;
               mem_tx_dne_wr_data[15:0] = 'd1;
               mem_tx_dne_wr_data[31:16] = 16'd22;
               mem_tx_dne_wr_data[63:32] = rd_q_enq_data_nxt[83:20];
               mem_tx_dne_wr_addr = mem_tx_dne_tail;
               mem_tx_dne_tail_nxt = (mem_tx_dne_tail + 64) & tx_dne_mask[`MEM_ADDR_BITS-1:0];
               mem_vld_tx_dne_wr_clear = 1;
               //send_dma_rd_state_nxt = SEND_DMA_RD_STATE_DEAD;
               // debug end
               */

               end
         end

         SEND_DMA_RD_STATE_PKT: begin
            if((~rd_q_full) && (~tx_pend_q_full) && /*!mem_vld_tx_dne_wr_stall && tx_dne_ready &&*/ !in_flight_counter_full && ((mem_tx_pkt_head_bk[14:0]-mem_tx_pkt_tail[14:0]-15'd64)>=15'd1664)) begin
               // dma rd pkt
               rd_q_enq_en_nxt = 1;
               if(pkt_local_addr[5:0] + pkt_len[5:0] == 6'b0) begin
                  rd_q_enq_data_nxt[15:0] = pkt_len[15:0];
               end
               else begin
                  rd_q_enq_data_nxt[15:0] = pkt_len[15:0] + {10'b0, 6'd0 - (pkt_local_addr[5:0] + pkt_len[5:0])};
                  rd_q_enq_data_nxt[19:16] = `ID_MEM_TX_PKT; // mem_select
                  rd_q_enq_data_nxt[83:20] = pkt_host_addr; // host addr
                  rd_q_enq_data_nxt[84+:`MEM_ADDR_BITS] = pkt_local_addr; // addr
               end

               // push pkt to pending queue
               tx_pend_q_enq_data[2*`MEM_ADDR_BITS+:16] = pkt_port;
               tx_pend_q_enq_data[`MEM_ADDR_BITS+:`MEM_ADDR_BITS] = pkt_local_addr;
               tx_pend_q_enq_data[0+:`MEM_ADDR_BITS] = pkt_end_addr;
               tx_pend_q_enq_en = 1;
              
               // move mem_tx_pkt_tail pointer
               if(pkt_end_addr[5:0] == 0) begin
                  mem_tx_pkt_tail_nxt = pkt_end_addr & tx_pkt_mask[`MEM_ADDR_BITS-1:0];
               end
               else begin
                  mem_tx_pkt_tail_nxt = ({pkt_end_addr[19:6], 6'b0} + 64) & tx_pkt_mask[`MEM_ADDR_BITS-1:0];
               end

               use_mem_tx_dsc_nxt = 1;
               if(use_mem_tx_dsc) begin
                  dma_rd_done = 1;
               end
            
               // move to next state
               if(dsc_in_fly) begin
                  send_dma_rd_state_nxt = SEND_DMA_RD_STATE_WAIT;
               end
               else begin
                  send_dma_rd_state_nxt = SEND_DMA_RD_STATE_END;
               end

               // count in flight mem read request
               in_flight_counter_wr_en = 1;

               /*
               // debug begin
               mem_tx_dne_wr_en = 1;
               mem_tx_dne_wr_mask = 8'hff;
               mem_tx_dne_wr_data[15:0] = 'd1;
               mem_tx_dne_wr_data[31:16] = 16'd33;
               mem_tx_dne_wr_data[63:32] = pkt_host_addr;
               mem_tx_dne_wr_addr = mem_tx_dne_tail;
               mem_tx_dne_tail_nxt = (mem_tx_dne_tail + 64) & tx_dne_mask[`MEM_ADDR_BITS-1:0];
               mem_vld_tx_dne_wr_clear = 1;
               //send_dma_rd_state_nxt = SEND_DMA_RD_STATE_DEAD;
               // debug end
               */

            end
         end

         SEND_DMA_RD_STATE_WAIT: begin
            if(dma_rd_go) begin
               if(tokens >= tokens_needed) begin
                  tokens_nxt = tokens - tokens_needed;
                  if(dsc_head_index != dsc_tail_index) begin
                     dsc_in_fly_nxt = 1;
                     send_dma_rd_state_nxt = SEND_DMA_RD_STATE_DSC;
                  end
                  else begin
                     dsc_in_fly_nxt = 0;
                     send_dma_rd_state_nxt = SEND_DMA_RD_STATE_PKT;
                  end
               end
               else begin
                  send_dma_rd_state_nxt = SEND_DMA_RD_STATE_END;
               end
            end
         end

         SEND_DMA_RD_STATE_END: begin
            if(!mem_vld_tx_dne_wr_stall && !feedback_task_q_full && tx_dne_ready) begin
               // interrupt host
               mem_tx_dne_wr_en = 1;
               mem_tx_dne_wr_mask = 8'hff;
               mem_tx_dne_wr_data[15:0] = 'd1;
               mem_tx_dne_wr_data[25:16] = class_index;
               mem_tx_dne_wr_data[63:32] = {6'b0, dsc_head_index};
               mem_tx_dne_wr_addr = mem_tx_dne_tail;
               mem_tx_dne_tail_nxt = (mem_tx_dne_tail + 64) & tx_dne_mask[`MEM_ADDR_BITS-1:0];
               mem_vld_tx_dne_wr_clear = 1;

               // feedback to scheduler
               feedback_task_q_enq_en = 1;
               feedback_task_q_enq_data = {class_index,
                                           tokens,
                                           dsc_head_index,
                                           pkt_host_addr,
                                           pkt_port,
                                           pkt_len};

               // clear the last descriptor
               if(dsc_in_fly) begin
                  dma_rd_done = 1;
               end

               // move to idle state
               send_dma_rd_state_nxt = SEND_DMA_RD_STATE_IDLE;
            end
         end

         SEND_DMA_RD_STATE_DEAD: begin
            send_dma_rd_state_nxt = SEND_DMA_RD_STATE_DEAD;
         end
      endcase
   
   end
   
   always_ff @(posedge clk) begin
      if(rst) begin
         send_dma_rd_state <= SEND_DMA_RD_STATE_IDLE;
         class_index <= 0;
         tokens_l <= 0;
         rate <= 0;
         dsc_buffer_host_addr <= 0;
         dsc_buffer_mask <= 0;
         dsc_head_index_l <= 0;
         dsc_tail_index <= 0;
         pkt_host_addr_first <= 0;
         pkt_local_addr_first <= 0;
         pkt_len_first <= 0;
         pkt_port_first <= 0;
         use_mem_tx_dsc <= 0;
         mem_tx_dsc_tail <= 0;
         mem_tx_pkt_tail <= 0;
         dsc_in_fly <= 0;
         rd_q_enq_en <= 0;
         mem_tx_dne_tail <= 0;
      end
      else begin
         send_dma_rd_state <= send_dma_rd_state_nxt;
         class_index <= class_index_nxt;
         tokens_l <= tokens_nxt;
         rate <= rate_nxt;
         dsc_buffer_host_addr <= dsc_buffer_host_addr_nxt;
         dsc_buffer_mask <= dsc_buffer_mask_nxt;
         dsc_head_index_l <= dsc_head_index_nxt;
         dsc_tail_index <= dsc_tail_index_nxt;
         pkt_host_addr_first <= pkt_host_addr_first_nxt;
         pkt_local_addr_first <= pkt_local_addr_first_nxt;
         pkt_len_first <= pkt_len_first_nxt;
         pkt_port_first <= pkt_port_first_nxt;
         use_mem_tx_dsc <= use_mem_tx_dsc_nxt;
         mem_tx_dsc_tail <= mem_tx_dsc_tail_nxt;
         mem_tx_pkt_tail <= mem_tx_pkt_tail_nxt;
         dsc_in_fly <= dsc_in_fly_nxt;
         rd_q_enq_en <= rd_q_enq_en_nxt;
         mem_tx_dne_tail <= mem_tx_dne_tail_nxt;
      end
      rd_q_enq_data <= rd_q_enq_data_nxt;
   end
   
   // -------------------------------------------
   // -- read new TX descriptor and process it
   // -------------------------------------------
   logic [15:0]               dma_rd_len_nxt;
   logic [15:0]               dma_rd_pkt_port_nxt;
   
   localparam READ_TX_DSC_STATE_IDLE      = 0;
   localparam READ_TX_DSC_STATE_L1        = 1;
   localparam READ_TX_DSC_STATE_L2        = 2;
   localparam READ_TX_DSC_STATE_WAIT      = 3;   

   logic [1:0]                 read_tx_dsc_state, read_tx_dsc_state_nxt;

   logic [`MEM_ADDR_BITS-1:0]  mem_tx_dsc_head_reg, mem_tx_dsc_head_reg_nxt;
   
   always_comb begin
      read_tx_dsc_state_nxt = read_tx_dsc_state;      
      mem_tx_dsc_head_nxt = mem_tx_dsc_head;

      mem_tx_dsc_rd_en = 1;
      mem_tx_dsc_rd_addr = mem_tx_dsc_head;

      mem_vld_tx_dsc_wr_addr  = mem_tx_dsc_head_reg[`MEM_ADDR_BITS-1:11];
      mem_vld_tx_dsc_wr_mask  = 1 << mem_tx_dsc_head_reg[10:6];
      mem_vld_tx_dsc_wr_clear = 0;
      
      dma_rd_len_nxt        = dma_rd_len;

      dma_rd_host_addr = 0;
      dma_rd_go        = 0;
      dma_rd_local_addr = 0;

      dma_rd_pkt_port_nxt = dma_rd_pkt_port;

      mem_tx_dsc_head_reg_nxt = mem_tx_dsc_head_reg;

      dsc_cm_counter_wr_en = 0;

      dma_end_nxt = dma_end;

      case(read_tx_dsc_state)
        READ_TX_DSC_STATE_IDLE: begin
           if(mem_vld_tx_dsc_rd_bit && !dsc_cm_counter_full) begin
              // count dscriptor completion
              dsc_cm_counter_wr_en = 1;
              // move head pointer
              mem_tx_dsc_head_nxt = (mem_tx_dsc_head + 8) & tx_dsc_mask[`MEM_ADDR_BITS-1:0];
              mem_tx_dsc_head_reg_nxt = mem_tx_dsc_head;
              // advance state
              read_tx_dsc_state_nxt = READ_TX_DSC_STATE_L1;

              dma_end_nxt = time_stamp;
           end
        end
        READ_TX_DSC_STATE_L1: begin
           // store read line
           dma_rd_len_nxt = mem_tx_dsc_rd_data[63:48];
           dma_rd_pkt_port_nxt   = mem_tx_dsc_rd_data[47:32];

           // advance state
           read_tx_dsc_state_nxt = READ_TX_DSC_STATE_L2;
        end
        READ_TX_DSC_STATE_L2: begin
           
           //if((mem_tx_dsc_rd_data != 0)) begin // data not already in mem_tx_pkt, dma_read
              dma_rd_host_addr = mem_tx_dsc_rd_data;
              dma_rd_local_addr = mem_tx_pkt_tail + {14'd0, dma_rd_host_addr[5:0]};
              dma_rd_go = 1;
           //end

           if(/*(mem_tx_dsc_rd_data == 0) ||*/ (dma_rd_done == 1))  begin // got DMA grant
              // clear valid bit              
              read_tx_dsc_state_nxt = READ_TX_DSC_STATE_WAIT;
              
              // move head pointer
              mem_tx_dsc_head_nxt = (mem_tx_dsc_head + 56) & tx_dsc_mask[`MEM_ADDR_BITS-1:0];
           end
        end

        READ_TX_DSC_STATE_WAIT: begin
           if(~mem_vld_tx_dsc_wr_stall) begin
              mem_vld_tx_dsc_wr_clear = 1;
              read_tx_dsc_state_nxt = READ_TX_DSC_STATE_IDLE;
           end
        end
      endcase
      
   end
   always_ff @(posedge clk) begin
      if(rst) begin
         read_tx_dsc_state <= READ_TX_DSC_STATE_IDLE;
         mem_tx_dsc_head  <= 0; 
      end
      else begin
         read_tx_dsc_state <= read_tx_dsc_state_nxt;
         mem_tx_dsc_head   <= mem_tx_dsc_head_nxt;
      end

      dma_rd_len        <= dma_rd_len_nxt;

      mem_tx_dsc_head_reg <= mem_tx_dsc_head_reg_nxt;
      dma_rd_pkt_port <= dma_rd_pkt_port_nxt;
   end

   // -------------------------------------------
   // -- read new doorbells and process it
   // -------------------------------------------
   localparam READ_TX_DOORBELL_STATE_IDLE      = 0;
   localparam READ_TX_DOORBELL_STATE_L1        = 1;
   localparam READ_TX_DOORBELL_STATE_L2        = 2;
   localparam READ_TX_DOORBELL_STATE_WAIT      = 3;

   logic [1:0]                 read_tx_doorbell_state, read_tx_doorbell_state_nxt;
   logic [`MEM_ADDR_BITS-1:0]  mem_tx_doorbell_head_reg, mem_tx_doorbell_head_reg_nxt;
   logic [63:0]                doorbell_lo_reg, doorbell_lo_reg_nxt;
   
   always_comb begin
      read_tx_doorbell_state_nxt = read_tx_doorbell_state;      
      mem_tx_doorbell_head_nxt = mem_tx_doorbell_head;

      mem_tx_doorbell_rd_en = 1;
      mem_tx_doorbell_rd_addr = mem_tx_doorbell_head;

      mem_vld_tx_doorbell_wr_addr  = mem_tx_doorbell_head_reg[`MEM_ADDR_BITS-1:11];
      mem_vld_tx_doorbell_wr_mask  = 1 << mem_tx_doorbell_head_reg[10:6];
      mem_vld_tx_doorbell_wr_clear = 0;

      mem_tx_doorbell_head_reg_nxt = mem_tx_doorbell_head_reg;
      doorbell_lo_reg_nxt = doorbell_lo_reg;

      doorbell_task_q_enq_en = 0;
      doorbell_task_q_data = 0;

      case(read_tx_doorbell_state)
        READ_TX_DOORBELL_STATE_IDLE: begin
           if(mem_vld_tx_doorbell_rd_bit) begin
              // move head pointer
              mem_tx_doorbell_head_nxt = (mem_tx_doorbell_head + 8) & tx_doorbell_mask[`MEM_ADDR_BITS-1:0];
              mem_tx_doorbell_head_reg_nxt = mem_tx_doorbell_head;
              // advance state
              read_tx_doorbell_state_nxt = READ_TX_DSC_STATE_L1;
           end
        end
        READ_TX_DOORBELL_STATE_L1: begin
           // store read line
           doorbell_lo_reg_nxt = mem_tx_doorbell_rd_data;

           // advance state
           read_tx_doorbell_state_nxt = READ_TX_DSC_STATE_L2;
        end
        READ_TX_DOORBELL_STATE_L2: begin
           if(~doorbell_task_q_full) begin
              // advance state
              read_tx_doorbell_state_nxt = READ_TX_DSC_STATE_WAIT;

              // push doorbell task queue
              doorbell_task_q_enq_en = 1;
              doorbell_task_q_data = {mem_tx_doorbell_rd_data, doorbell_lo_reg};
              
              // move head pointer
              mem_tx_doorbell_head_nxt = (mem_tx_doorbell_head + 56) & tx_doorbell_mask[`MEM_ADDR_BITS-1:0];
           end
        end

        READ_TX_DOORBELL_STATE_WAIT: begin
           if(~mem_vld_tx_doorbell_wr_stall) begin
              mem_vld_tx_doorbell_wr_clear = 1;
              read_tx_doorbell_state_nxt = READ_TX_DOORBELL_STATE_IDLE;
           end
        end
      endcase
      
   end
   always_ff @(posedge clk) begin
      if(rst) begin
         read_tx_doorbell_state <= READ_TX_DOORBELL_STATE_IDLE;
         mem_tx_doorbell_head  <= 0; 
      end
      else begin
         read_tx_doorbell_state <= read_tx_doorbell_state_nxt;
         mem_tx_doorbell_head   <= mem_tx_doorbell_head_nxt;
      end

      mem_tx_doorbell_head_reg <= mem_tx_doorbell_head_reg_nxt;
      doorbell_lo_reg <= doorbell_lo_reg_nxt;
   end

   // ----------------------------------
   // -- Doorbell completion queue
   // ----------------------------------

   always_comb begin
      doorbell_dne_q_deq_en = 0;

      // clear 7 entries ahead, make sure buffer is at least 16 lines deep
      mem_tx_doorbell_dne_clear        = (mem_tx_doorbell_dne_tail + 64*8) & tx_doorbell_dne_mask[`MEM_ADDR_BITS-1:0];
      mem_vld_tx_doorbell_dne_wr_addr  = mem_tx_doorbell_dne_clear[`MEM_ADDR_BITS-1:11];
      mem_vld_tx_doorbell_dne_wr_mask  = 1 << mem_tx_doorbell_dne_clear[10:6];
      mem_vld_tx_doorbell_dne_wr_clear = 0;

      mem_tx_doorbell_dne_wr_en     = 0;
      mem_tx_doorbell_dne_wr_mask   = 8'hff;
      mem_tx_doorbell_dne_wr_data   = 0;
      mem_tx_doorbell_dne_wr_addr   = 0;
      mem_tx_doorbell_dne_tail_nxt  = mem_tx_doorbell_dne_tail;

      if(!doorbell_dne_q_empty && !mem_vld_tx_doorbell_dne_wr_stall && tx_doorbell_dne_ready) begin
         doorbell_dne_q_deq_en = 1;

         // interrupt host
         mem_tx_doorbell_dne_wr_en = 1;
         mem_tx_doorbell_dne_wr_mask = 8'hff;
         mem_tx_doorbell_dne_wr_data[31:0] = doorbell_dne_q_deq_data;
         mem_tx_doorbell_dne_wr_addr = mem_tx_doorbell_dne_tail;
         mem_tx_doorbell_dne_tail_nxt = (mem_tx_doorbell_dne_tail + 64) & tx_doorbell_dne_mask[`MEM_ADDR_BITS-1:0];
         mem_vld_tx_doorbell_dne_wr_clear = 1;
      end
   end

   always_ff @(posedge clk) begin
      if(rst) begin
         mem_tx_doorbell_dne_tail <= 0;
      end
      else begin
         mem_tx_doorbell_dne_tail <= mem_tx_doorbell_dne_tail_nxt;
      end
   end

   // ----------------------------------
   // -- Shift ouput S_AXIS data
   // ----------------------------------
   logic [63:0]                M_AXIS_TDATA_L;
   logic                       M_AXIS_TREADY_L;
   logic [7:0]                 M_AXIS_TSTRB_L;
   logic                       M_AXIS_TVALID_L;
   logic                       M_AXIS_TLAST_L;
   logic [127:0]               M_AXIS_TUSER_L;

   tx_pkt_shift u_shift(.in_tdata(M_AXIS_TDATA_L),
                        .in_tstrb(M_AXIS_TSTRB_L),
                        .in_tvalid(M_AXIS_TVALID_L),
                        .in_tready(M_AXIS_TREADY_L),
                        .in_tlast(M_AXIS_TLAST_L),
                        .in_tuser(M_AXIS_TUSER_L),
                        .out_tdata(M_AXIS_TDATA),
                        .out_tstrb(M_AXIS_TSTRB),
                        .out_tvalid(M_AXIS_TVALID),
                        .out_tready(M_AXIS_TREADY),
                        .out_tlast(M_AXIS_TLAST),
                        .out_tuser(M_AXIS_TUSER),
                        .clk(clk),
                        .rst(rst)
                        );
   
   // ----------------------------------
   // -- send the packet out
   // ----------------------------------
   localparam PKT_SEND_STATE_IDLE       = 0;
   localparam PKT_SEND_STATE_PKT_START  = 1;
   localparam PKT_SEND_STATE_LINE_DATA  = 2;

   logic [1:0]                 pkt_send_state, pkt_send_state_nxt;
   
   logic                       mem_tx_pkt_mark_end, mem_tx_pkt_mark_end_nxt;

   logic [`MEM_ADDR_BITS-12:0] mem_vld_tx_pkt_wr_addr_nxt;
   logic [31:0]                mem_vld_tx_pkt_wr_mask_nxt;
   logic                       mem_vld_tx_pkt_wr_clear_nxt;
                                         
   logic [`MEM_ADDR_BITS-1:0]  mem_tx_pkt_head_l, mem_tx_pkt_head_reg;
   logic                       mem_vld_tx_pkt_wr_clear_l;

   logic [63:0]                M_AXIS_TDATA_L_nxt;
   logic [7:0]                 M_AXIS_TSTRB_L_nxt;
   logic                       M_AXIS_TVALID_L_nxt;
   logic                       M_AXIS_TLAST_L_nxt;
   logic [127:0]               M_AXIS_TUSER_L_nxt;

   logic [15:0]                mem_tx_pkt_port, mem_tx_pkt_port_nxt;

   assign mem_tx_pkt_rd_addr = mem_tx_pkt_head;
   
   always_comb begin
      pkt_send_state_nxt = pkt_send_state;

      mem_tx_pkt_head_bk_nxt = mem_tx_pkt_head_bk;
      
      mem_tx_pkt_head     = mem_tx_pkt_head_l;
      mem_tx_pkt_head_nxt = mem_tx_pkt_head_l;
      mem_tx_pkt_end_nxt  = mem_tx_pkt_end;
      mem_tx_pkt_rd_en    = 1;
      mem_tx_pkt_mark_end_nxt = mem_tx_pkt_mark_end;
      
      mem_vld_tx_pkt_wr_addr_nxt  = mem_vld_tx_pkt_wr_addr;
      mem_vld_tx_pkt_wr_mask_nxt  = mem_vld_tx_pkt_wr_mask;
      mem_vld_tx_pkt_wr_clear     = mem_vld_tx_pkt_wr_clear_l;
      mem_vld_tx_pkt_wr_clear_nxt = 0;
      
      M_AXIS_TDATA_L_nxt  = M_AXIS_TDATA_L;
      M_AXIS_TSTRB_L_nxt  = M_AXIS_TSTRB_L;
      M_AXIS_TLAST_L_nxt  = M_AXIS_TLAST_L;
      M_AXIS_TUSER_L_nxt  = M_AXIS_TUSER_L;

      pkt_cm_counter_wr_en = 0;
      
      if(M_AXIS_TREADY_L)
        M_AXIS_TVALID_L_nxt = 0;
      else
        M_AXIS_TVALID_L_nxt = M_AXIS_TVALID_L;
      
      tx_pend_q_deq_en = 0;

      mem_tx_pkt_port_nxt = mem_tx_pkt_port;
      
      case(pkt_send_state)
        PKT_SEND_STATE_IDLE: begin
           if(~tx_pend_q_empty) begin
              mem_tx_pkt_port_nxt = tx_pend_q_deq_data[2*`MEM_ADDR_BITS+:16];
              mem_tx_pkt_head_nxt = tx_pend_q_deq_data[`MEM_ADDR_BITS+:`MEM_ADDR_BITS] & tx_pkt_mask[`MEM_ADDR_BITS-1:0];
              mem_tx_pkt_end_nxt  = tx_pend_q_deq_data[0+:`MEM_ADDR_BITS] & tx_pkt_mask[`MEM_ADDR_BITS-1:0];;
              mem_tx_pkt_head     = mem_tx_pkt_head_nxt; // save a cycle by doing this
              pkt_send_state_nxt  = PKT_SEND_STATE_PKT_START;
           end
        end

        PKT_SEND_STATE_PKT_START: begin
           if(mem_vld_tx_pkt_rd_bit) begin
              // dequeue pending transmit
              tx_pend_q_deq_en = 1;
              // move head pointer
              mem_tx_pkt_head_nxt = (mem_tx_pkt_head + 8) & tx_pkt_mask[`MEM_ADDR_BITS-1:0];
              // advance state
              pkt_send_state_nxt = PKT_SEND_STATE_LINE_DATA;
              // prepare vld_tx_pkt clear mask and address
              mem_vld_tx_pkt_wr_addr_nxt = mem_tx_pkt_head[`MEM_ADDR_BITS-1:11];
              mem_vld_tx_pkt_wr_mask_nxt = 32'hffffffff << mem_tx_pkt_head[10:6];
              // prepare M_AXIS_TUSER
              M_AXIS_TUSER_L_nxt[31:16] = mem_tx_pkt_port;
              M_AXIS_TUSER_L_nxt[15:0]  = (mem_tx_pkt_end[15:0] - mem_tx_pkt_head[15:0]) & tx_pkt_mask[15:0];
           end
           else begin
              pkt_send_state_nxt = PKT_SEND_STATE_IDLE;
           end
        end

        PKT_SEND_STATE_LINE_DATA: begin
           if(!mem_vld_tx_pkt_rd_bit || !M_AXIS_TREADY_L || mem_vld_tx_pkt_wr_stall || pkt_cm_counter_full) begin
              mem_tx_pkt_head = mem_tx_pkt_head_reg;
              mem_vld_tx_pkt_wr_clear = 0;
              mem_vld_tx_pkt_wr_clear_nxt = mem_vld_tx_pkt_wr_clear_l;
           end
           else begin
              M_AXIS_TVALID_L_nxt = 1;
              if(~mem_tx_pkt_mark_end) begin
                 case(mem_tx_pkt_head[2:0])
                   3'h0: begin
                      M_AXIS_TSTRB_L_nxt = 8'hff;
                      M_AXIS_TDATA_L_nxt = mem_tx_pkt_rd_data;
                   end
                   3'h1: begin
                      M_AXIS_TSTRB_L_nxt = 8'h7f;
                      M_AXIS_TDATA_L_nxt = {8'b0, mem_tx_pkt_rd_data[63:8]};
                   end
                   3'h2: begin
                      M_AXIS_TSTRB_L_nxt = 8'h3f;
                      M_AXIS_TDATA_L_nxt = {16'b0, mem_tx_pkt_rd_data[63:16]};
                   end
                   3'h3: begin 
                      M_AXIS_TSTRB_L_nxt = 8'h1f;
                      M_AXIS_TDATA_L_nxt = {24'b0, mem_tx_pkt_rd_data[63:24]};
                   end
                   3'h4: begin 
                      M_AXIS_TSTRB_L_nxt = 8'h0f;
                      M_AXIS_TDATA_L_nxt = {32'b0, mem_tx_pkt_rd_data[63:32]};
                   end
                   3'h5: begin 
                      M_AXIS_TSTRB_L_nxt = 8'h07;
                      M_AXIS_TDATA_L_nxt = {40'b0, mem_tx_pkt_rd_data[63:40]};
                   end
                   3'h6: begin 
                      M_AXIS_TSTRB_L_nxt = 8'h03;
                      M_AXIS_TDATA_L_nxt = {48'b0, mem_tx_pkt_rd_data[63:48]};
                   end
                   3'h7: begin 
                      M_AXIS_TSTRB_L_nxt = 8'h01;
                      M_AXIS_TDATA_L_nxt = {56'b0, mem_tx_pkt_rd_data[63:56]};
                   end
                 endcase
                 M_AXIS_TLAST_L_nxt = 0;

                 // read next line
                 if(((mem_tx_pkt_end - mem_tx_pkt_head) & tx_pkt_mask[`MEM_ADDR_BITS-1:0]) > 8) begin
                    mem_tx_pkt_head_nxt = ({mem_tx_pkt_head[`MEM_ADDR_BITS-1:3],3'b0} + 8) & tx_pkt_mask[`MEM_ADDR_BITS-1:0];
                    // done with this batch of lines, clear valid bits
                    if((mem_tx_pkt_head[10:6] == 5'b11111) && (mem_tx_pkt_head_nxt[10:6] == 5'b00000)) begin
                       mem_vld_tx_pkt_wr_clear_nxt = 1;
                    end
                 end
                 else begin
                    mem_tx_pkt_mark_end_nxt = 1;   
                 end                  

                 // reinitialize vld_tx_pkt write
                 if(mem_tx_pkt_head[10:6] == 5'b00000) begin
                    mem_vld_tx_pkt_wr_addr_nxt = mem_tx_pkt_head[`MEM_ADDR_BITS-1:11];
                    mem_vld_tx_pkt_wr_mask_nxt = 32'hffffffff;
                 end  

              end
              else begin
                 case(mem_tx_pkt_end[2:0])
                   3'd0: begin
                      M_AXIS_TSTRB_L_nxt = 8'hff;
                      M_AXIS_TDATA_L_nxt = mem_tx_pkt_rd_data;
                   end
                   3'd1: begin
                      M_AXIS_TSTRB_L_nxt = 8'h01;
                      M_AXIS_TDATA_L_nxt = {56'b0, mem_tx_pkt_rd_data[7:0]};
                   end
                   3'd2: begin 
                      M_AXIS_TSTRB_L_nxt = 8'h03;
                      M_AXIS_TDATA_L_nxt = {48'b0, mem_tx_pkt_rd_data[15:0]};
                   end
                   3'd3: begin
                      M_AXIS_TSTRB_L_nxt = 8'h07;
                      M_AXIS_TDATA_L_nxt = {40'b0, mem_tx_pkt_rd_data[23:0]};
                   end
                   3'd4: begin
                      M_AXIS_TSTRB_L_nxt = 8'h0f;
                      M_AXIS_TDATA_L_nxt = {32'b0, mem_tx_pkt_rd_data[31:0]};
                   end
                   3'd5: begin
                      M_AXIS_TSTRB_L_nxt = 8'h1f;
                      M_AXIS_TDATA_L_nxt = {24'b0, mem_tx_pkt_rd_data[39:0]};
                   end
                   3'd6: begin
                      M_AXIS_TSTRB_L_nxt = 8'h3f;
                      M_AXIS_TDATA_L_nxt = {16'b0, mem_tx_pkt_rd_data[47:0]};
                   end
                   3'd7: begin
                      M_AXIS_TSTRB_L_nxt = 8'h7f;
                      M_AXIS_TDATA_L_nxt = {8'b0, mem_tx_pkt_rd_data[55:0]};
                   end
                   default: begin
                      M_AXIS_TSTRB_L_nxt = 8'hff;
                      M_AXIS_TDATA_L_nxt = mem_tx_pkt_rd_data;
                   end
                 endcase
                 M_AXIS_TLAST_L_nxt = 1;
                 
                 // clear the tx_pkt buffer
                 if(mem_tx_pkt_end[5:0] == 6'b0) begin
                    mem_tx_pkt_head_bk_nxt = mem_tx_pkt_end & tx_pkt_mask[`MEM_ADDR_BITS-1:0];
                    mem_vld_tx_pkt_wr_mask_nxt = mem_vld_tx_pkt_wr_mask & (32'hffffffff >> (5'd32 - mem_tx_pkt_end[10:6]));
                 end
                 else begin 
                    mem_tx_pkt_head_bk_nxt = ({mem_tx_pkt_end[19:6], 6'b0} + 20'd64) & tx_pkt_mask[`MEM_ADDR_BITS-1:0];
                    mem_vld_tx_pkt_wr_mask_nxt = mem_vld_tx_pkt_wr_mask & (32'hffffffff >> (5'd31 - mem_tx_pkt_end[10:6]));
                 end
                 mem_vld_tx_pkt_wr_clear_nxt = 1;

                 // clear the end mark
                 mem_tx_pkt_mark_end_nxt = 0;
                 
                 // advance state
                 pkt_send_state_nxt = PKT_SEND_STATE_IDLE;

                 // count pkt completion
                 pkt_cm_counter_wr_en = 1;
                 
              end             
           end
        end
                
      endcase
      
   end
   always_ff @(posedge clk) begin
      if(rst) begin
         pkt_send_state <= PKT_SEND_STATE_IDLE;

         mem_tx_pkt_head_l <= 0;         
         mem_tx_pkt_end  <= 0;
         mem_tx_pkt_mark_end <= 0;
         
         mem_vld_tx_pkt_wr_clear_l <= 0;

         M_AXIS_TVALID_L <= 0;

         mem_tx_pkt_head_bk <= 0;
      end
      else begin
         pkt_send_state <= pkt_send_state_nxt;       

         mem_tx_pkt_head_l <= mem_tx_pkt_head_nxt;         

         mem_tx_pkt_end  <= mem_tx_pkt_end_nxt;
         mem_tx_pkt_mark_end <= mem_tx_pkt_mark_end_nxt;
         
         mem_vld_tx_pkt_wr_clear_l <= mem_vld_tx_pkt_wr_clear_nxt;

         M_AXIS_TVALID_L <= M_AXIS_TVALID_L_nxt;

         mem_tx_pkt_head_bk <= mem_tx_pkt_head_bk_nxt;
      end

      mem_vld_tx_pkt_wr_addr <= mem_vld_tx_pkt_wr_addr_nxt;
      mem_vld_tx_pkt_wr_mask <= mem_vld_tx_pkt_wr_mask_nxt;

      mem_tx_pkt_head_reg <= mem_tx_pkt_head;
      mem_tx_pkt_port     <= mem_tx_pkt_port_nxt;

      M_AXIS_TDATA_L <= M_AXIS_TDATA_L_nxt;
      M_AXIS_TSTRB_L <= M_AXIS_TSTRB_L_nxt;
      M_AXIS_TLAST_L <= M_AXIS_TLAST_L_nxt;
      M_AXIS_TUSER_L <= M_AXIS_TUSER_L_nxt;
      
   end
   
endmodule

module tx_pkt_shift
  (
   input logic [63:0]   in_tdata,
   input logic [7:0]    in_tstrb,
   input logic          in_tvalid,
   output logic         in_tready,
   input logic          in_tlast,
   input logic [127:0]  in_tuser,
   
   output logic [63:0]  out_tdata,
   output logic [7:0]   out_tstrb,
   output logic         out_tvalid,
   input logic          out_tready,
   output logic         out_tlast, 
   output logic [127:0] out_tuser, 
   
   input logic          clk,
   input logic          rst
   );

   localparam STATE_IDLE = 0;
   localparam STATE_TX   = 1;
   localparam STATE_LAST = 2;

   logic [1:0]          state, state_nxt;
   
   logic [63:0]         out_tdata_nxt,  out_tdata_reg,  out_tdata_reg_d1;
   logic [7:0]          out_tstrb_nxt,  out_tstrb_reg,  out_tstrb_reg_d1;
   logic                out_tvalid_nxt, out_tvalid_reg, out_tvalid_reg_d1;
   logic                out_tlast_nxt,  out_tlast_reg,  out_tlast_reg_d1;
   logic [127:0]        out_tuser_nxt,  out_tuser_reg,  out_tuser_reg_d1;

   logic [63:0]         tdata, tdata_nxt;
   logic [7:0]          tstrb, tstrb_nxt;

   logic [2:0]          offset, offset_nxt;

   logic                in_tready_nxt;
   logic                out_tready_d1;
   
   always_comb begin
      state_nxt = state;

      offset_nxt = offset;

      tdata_nxt = tdata;
      tstrb_nxt = tstrb;

      out_tvalid_nxt = 0;
      out_tlast_nxt  = 0;
      out_tuser_nxt  = 0;
      out_tdata_nxt  = out_tdata_reg;
      out_tstrb_nxt  = out_tstrb_reg;

      out_tvalid = out_tvalid_reg;
      out_tlast  = out_tlast_reg;
      out_tuser  = out_tuser_reg;
      out_tdata  = out_tdata_reg;
      out_tstrb  = out_tstrb_reg;

      in_tready_nxt = 1;
      
      if(~out_tready) begin
         in_tready_nxt = 0;
      end
      else if(out_tready & ~out_tready_d1) begin
         out_tvalid = out_tvalid_reg_d1;
         out_tlast  = out_tlast_reg_d1;
         out_tuser  = out_tuser_reg_d1;
         out_tdata  = out_tdata_reg_d1;
         out_tstrb  = out_tstrb_reg_d1; 
         if(state == STATE_LAST) in_tready_nxt = 0;
      end
            
      if(out_tready_d1) begin
         case(state)
           STATE_IDLE: begin
              if(in_tvalid) begin
                 case(in_tstrb)
                   8'hff: begin 
                      offset_nxt = 0;
                      out_tdata_nxt = in_tdata;
                      out_tstrb_nxt = in_tstrb;
                      out_tvalid_nxt = 1;
                      out_tuser_nxt = in_tuser;
                   end
                   8'h7f: begin
                      tdata_nxt = {in_tdata[55:0], 8'b0};
                      tstrb_nxt = {in_tstrb[6:0], 1'b0};
                      offset_nxt = 1;
                   end
                   8'h3f: begin
                      tdata_nxt = {in_tdata[47:0], 16'b0};
                      tstrb_nxt = {in_tstrb[5:0], 2'b0};
                      offset_nxt = 2;
                   end
                   8'h1f: begin
                      tdata_nxt = {in_tdata[39:0], 24'b0};
                      tstrb_nxt = {in_tstrb[4:0], 3'b0};
                      offset_nxt = 3;
                   end
                   8'h0f: begin
                      tdata_nxt = {in_tdata[31:0], 32'b0};
                      tstrb_nxt = {in_tstrb[3:0], 4'b0};
                      offset_nxt = 4;
                   end
                   8'h07: begin
                      tdata_nxt = {in_tdata[23:0], 40'b0};
                      tstrb_nxt = {in_tstrb[2:0], 5'b0};
                      offset_nxt = 5;
                   end
                   8'h03: begin
                      tdata_nxt = {in_tdata[15:0], 48'b0};
                      tstrb_nxt = {in_tstrb[1:0], 6'b0};
                      offset_nxt = 6;
                   end
                   8'h01: begin
                      tdata_nxt = {in_tdata[7:0], 56'b0};
                      tstrb_nxt = {in_tstrb[0], 7'b0};
                      offset_nxt = 7;
                   end
                   default: begin
                   end
                 endcase
                 state_nxt = STATE_TX;
              end
           end
           STATE_TX: begin
              if(in_tvalid) begin
                 tdata_nxt = in_tdata;
                 tstrb_nxt = in_tstrb;
                 case(offset)
                   3'h0: begin
                      out_tdata_nxt = in_tdata;
                      out_tstrb_nxt = in_tstrb;
                      out_tvalid_nxt = 1;
                      out_tuser_nxt = in_tuser;
                      if(in_tlast) begin
                         out_tlast_nxt = 1;
                         state_nxt = STATE_IDLE;
                      end
                   end
                   3'h1: begin
                      out_tdata_nxt = {in_tdata[7:0], tdata[63:8]};
                      out_tstrb_nxt = {in_tstrb[0], tstrb[7:1]};
                      out_tvalid_nxt = 1;
                      out_tuser_nxt = in_tuser;
                      if(in_tlast & ~in_tstrb[1]) begin
                         out_tlast_nxt = 1;
                         state_nxt = STATE_IDLE;
                      end
                      else if(in_tlast & in_tstrb[1]) begin
                         state_nxt = STATE_LAST;
                         in_tready_nxt = 0;
                      end
                   end
                   3'h2: begin
                      out_tdata_nxt = {in_tdata[15:0], tdata[63:16]};
                      out_tstrb_nxt = {in_tstrb[1:0], tstrb[7:2]};
                      out_tvalid_nxt = 1;
                      out_tuser_nxt = in_tuser;
                      if(in_tlast & ~in_tstrb[2]) begin
                         out_tlast_nxt = 1;
                         state_nxt = STATE_IDLE;
                      end
                      else if(in_tlast & in_tstrb[2]) begin
                         state_nxt = STATE_LAST;
                         in_tready_nxt = 0;
                      end
                   end
                   3'h3: begin
                      out_tdata_nxt = {in_tdata[23:0], tdata[63:24]};
                      out_tstrb_nxt = {in_tstrb[2:0], tstrb[7:3]};
                      out_tvalid_nxt = 1;
                      out_tuser_nxt = in_tuser;
                      if(in_tlast & ~in_tstrb[3]) begin
                         out_tlast_nxt = 1;
                         state_nxt = STATE_IDLE;
                      end
                      else if(in_tlast & in_tstrb[3]) begin
                         state_nxt = STATE_LAST;
                         in_tready_nxt = 0;
                      end
                   end
                   3'h4: begin
                      out_tdata_nxt = {in_tdata[31:0], tdata[63:32]};
                      out_tstrb_nxt = {in_tstrb[3:0], tstrb[7:4]};
                      out_tvalid_nxt = 1;
                      out_tuser_nxt = in_tuser;
                      if(in_tlast & ~in_tstrb[4]) begin
                         out_tlast_nxt = 1;
                         state_nxt = STATE_IDLE;
                      end
                      else if(in_tlast & in_tstrb[4]) begin
                         state_nxt = STATE_LAST;
                         in_tready_nxt = 0;
                      end
                   end
                   3'h5: begin
                      out_tdata_nxt = {in_tdata[39:0], tdata[63:40]};
                      out_tstrb_nxt = {in_tstrb[4:0], tstrb[7:5]};
                      out_tvalid_nxt = 1;
                      out_tuser_nxt = in_tuser;
                      if(in_tlast & ~in_tstrb[5]) begin
                         out_tlast_nxt = 1;
                         state_nxt = STATE_IDLE;
                      end
                      else if(in_tlast & in_tstrb[5]) begin
                         state_nxt = STATE_LAST;
                         in_tready_nxt = 0;
                      end
                   end
                   3'h6: begin
                      out_tdata_nxt = {in_tdata[47:0], tdata[63:48]};
                      out_tstrb_nxt = {in_tstrb[5:0], tstrb[7:6]};
                      out_tvalid_nxt = 1;
                      out_tuser_nxt = in_tuser;
                      if(in_tlast & ~in_tstrb[6]) begin
                         out_tlast_nxt = 1;
                         state_nxt = STATE_IDLE;
                      end
                      else if(in_tlast & in_tstrb[6]) begin
                         state_nxt = STATE_LAST;
                         in_tready_nxt = 0;
                      end
                   end
                   3'h7: begin
                      out_tdata_nxt = {in_tdata[55:0], tdata[63:56]};
                      out_tstrb_nxt = {in_tstrb[6:0], tstrb[7]};
                      out_tvalid_nxt = 1;
                      out_tuser_nxt = in_tuser;
                      if(in_tlast & ~in_tstrb[7]) begin
                         out_tlast_nxt = 1;
                         state_nxt = STATE_IDLE;
                      end
                      else if(in_tlast & in_tstrb[7]) begin
                         state_nxt = STATE_LAST;
                         in_tready_nxt = 0;
                      end
                   end
                 endcase
              end
           end
           STATE_LAST: begin
              out_tlast_nxt = 1;
              out_tvalid_nxt = 1;
              case(offset)
                3'h0: begin
                end
                3'h1: begin
                   out_tdata_nxt = {8'b0, tdata[63:8]};
                   out_tstrb_nxt = {1'b0, tstrb[7:1]};
                end
                3'h2: begin
                   out_tdata_nxt = {16'b0, tdata[63:16]};
                   out_tstrb_nxt = {2'b0, tstrb[7:2]};
                end
                3'h3: begin
                   out_tdata_nxt = {24'b0, tdata[63:24]};
                   out_tstrb_nxt = {3'b0, tstrb[7:3]};
                end
                3'h4: begin
                   out_tdata_nxt = {32'b0, tdata[63:32]};
                   out_tstrb_nxt = {4'b0, tstrb[7:4]};
                end
                3'h5: begin
                   out_tdata_nxt = {40'b0, tdata[63:40]};
                   out_tstrb_nxt = {5'b0, tstrb[7:5]};
                end
                3'h6: begin
                   out_tdata_nxt = {48'b0, tdata[63:48]};
                   out_tstrb_nxt = {6'b0, tstrb[7:6]};
                end
                3'h7: begin
                   out_tdata_nxt = {56'b0, tdata[63:56]};
                   out_tstrb_nxt = {7'b0, tstrb[7]};
                end
              endcase
              state_nxt = STATE_IDLE;
           end
         endcase
      end
   end
   always_ff @(posedge clk) begin
      if(rst) begin
         state      <= STATE_IDLE;
         in_tready  <= 0;
         out_tvalid_reg    <= 0;
         out_tvalid_reg_d1 <= 0;
      end
      else begin
         state      <= state_nxt;
         in_tready  <= in_tready_nxt;
         
         if(out_tready_d1) begin
            out_tvalid_reg    <= out_tvalid_nxt;
            out_tvalid_reg_d1 <= out_tvalid_reg;
         end
         
      end
      offset <= offset_nxt;

      out_tready_d1 <= out_tready;
      tdata <= tdata_nxt;
      tstrb <= tstrb_nxt;

      if(out_tready_d1) begin
         out_tdata_reg    <= out_tdata_nxt;
         out_tstrb_reg    <= out_tstrb_nxt;
         out_tlast_reg    <= out_tlast_nxt;
         out_tuser_reg    <= out_tuser_nxt;
         out_tdata_reg_d1 <= out_tdata_reg;
         out_tstrb_reg_d1 <= out_tstrb_reg;
         out_tlast_reg_d1 <= out_tlast_reg;
         out_tuser_reg_d1 <= out_tuser_reg;
      end
         
   end
   
endmodule

module counter_fifo #(
                      parameter MAX=8)
   (
   input logic wr_en,
   input logic rd_en,
   input logic rst,
   input logic clk,
   output logic full,
   output logic empty
   );

   logic [$clog2(MAX+1)-1:0] counter, counter_nxt;

   always_comb begin
      if(rst) begin
         full = 1;
         empty = 1;
      end
      else begin
         full = (counter == MAX);
         empty = (counter == 0);
      end
      counter_nxt = counter;

      if(wr_en && !rd_en && !full) begin
         counter_nxt = counter + 1;
      end
      else if(!wr_en && rd_en && !empty) begin
         counter_nxt = counter - 1;
      end

   end

   always_ff @(posedge clk) begin
      if(rst) begin
         counter <= 0;
      end
      begin
         counter <= counter_nxt;
      end
   end


endmodule

