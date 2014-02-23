/*******************************************************************************
 *
 *  NetFPGA-10G http://www.netfpga.org
 *
 *  File:
 *        nicpic.v
 *
 *  Library:
 *        hw/contrib/pcores/nicpic_dma_v1_00_a
 *
 *  Module:
 *        dma
 *
 *  Author:
 *        Yilong Geng
 *
 *  Description:
 *        nicpic scheduler.
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

module nicpic
   (
   // tx task queue
   input                   tx_task_q_deq_en,
   output  [381:0]         tx_task_q_data,
   output                  tx_task_q_empty,

   // doorbell task queue
   input                   doorbell_task_q_enq_en,
   input  [127:0]          doorbell_task_q_data,
   output                  doorbell_task_q_full,

   // doorbell dne queue
   input                   doorbell_dne_q_deq_en,
   output [31:0]           doorbell_dne_q_deq_data,
   output                  doorbell_dne_q_empty,

   // feedback task queue
   input                   feedback_task_q_enq_en,
   input [195:0]           feedback_task_q_enq_data,
   output                  feedback_task_q_full,

   // misc
   input                   clk,
   input                   rst
   );

   // doorbell instructions
   localparam DOORBELL_ADD_CLASS = 1;
   localparam DOORBELL_SET_RATE = 2;
   localparam DOORBELL_SET_TOKENS_MAX = 3;
   localparam DOORBELL_ADD_DSC = 4;
   localparam DOORBELL_STOP_CLASS = 5;
   localparam DOORBELL_DELETE_CLASS = 6;

   // doorbell task queue signals
   reg doorbell_task_q_deq_en;
   wire [127:0] doorbell_task_q_deq_data;
   wire doorbell_task_q_empty;
   wire [5:0] inst_doorbell;
   assign inst_doorbell = doorbell_task_q_deq_data[5:0];
   wire [9:0] class_index_doorbell;
   assign class_index_doorbell = doorbell_task_q_deq_data[15:6];
   // DOORBELL_ADD_CLASS
   wire [63:0] dsc_buffer_host_addr_doorbell;
   assign dsc_buffer_host_addr_doorbell = doorbell_task_q_deq_data[127:64];
   wire [31:0] dsc_buffer_mask_doorbell;
   assign dsc_buffer_mask_doorbell = doorbell_task_q_deq_data[63:32];
   // DOORBELL_SET_RATE
   wire [63:0] rate_doorbell;
   assign rate_doorbell = doorbell_task_q_deq_data[127:64];
   // DOORBELL_SET_TOKENS_MAX
   wire [63:0] tokens_max_doorbell;
   assign tokens_max_doorbell = doorbell_task_q_deq_data[127:64];
   // DOORBELL_ADD_DSC
   wire [63:0] pkt_host_addr_doorbell;
   assign pkt_host_addr_doorbell = doorbell_task_q_deq_data[127:64];
   wire [15:0] pkt_port_doorbell;
   wire [3:0] pkt_port_short_doorbell;
   assign pkt_port_short_doorbell = doorbell_task_q_deq_data[35:32];
   assign pkt_port_doorbell[1] = pkt_port_short_doorbell[0];
   assign pkt_port_doorbell[8] = pkt_port_short_doorbell[0];
   assign pkt_port_doorbell[3] = pkt_port_short_doorbell[1];
   assign pkt_port_doorbell[10] = pkt_port_short_doorbell[1];
   assign pkt_port_doorbell[5] = pkt_port_short_doorbell[2];
   assign pkt_port_doorbell[12] = pkt_port_short_doorbell[2];
   assign pkt_port_doorbell[7] = pkt_port_short_doorbell[3];
   assign pkt_port_doorbell[14] = pkt_port_short_doorbell[3];
   assign pkt_port_doorbell[0] = 0;
   assign pkt_port_doorbell[2] = 0;
   assign pkt_port_doorbell[4] = 0;
   assign pkt_port_doorbell[6] = 0;
   assign pkt_port_doorbell[9] = 0;
   assign pkt_port_doorbell[11] = 0;
   assign pkt_port_doorbell[13] = 0;
   assign pkt_port_doorbell[15] = 0;
   wire [15:0] pkt_len_doorbell;
   assign pkt_len_doorbell = doorbell_task_q_deq_data[31:16];
   wire [25:0] dsc_tail_index_doorbell;
   assign dsc_tail_index_doorbell = doorbell_task_q_deq_data[63:38];


   // doorbell done signals tell the host when it can free
   // old dsc buffers
   wire [31:0] doorbell_dne_q_enq_data;
   reg    doorbell_dne_q_enq_en;
   wire    doorbell_dne_q_full;
   reg [9:0] class_index_doorbell_dne;
   reg [5:0] inst_doorbell_dne;
   reg success_doorbell_dne;
   assign doorbell_dne_q_enq_data[7:0] = 8'd1;
   assign doorbell_dne_q_enq_data[8] = success_doorbell_dne;
   assign doorbell_dne_q_enq_data[15:9] = 0;
   assign doorbell_dne_q_enq_data[21:16] = inst_doorbell_dne;
   assign doorbell_dne_q_enq_data[31:22] = class_index_doorbell_dne;

   // tx task queue signals
   wire [381:0] tx_task_q_enq_data;
   reg tx_task_q_enq_en;
   wire tx_task_q_full;

   // feedback task queue signals
   reg feedback_task_q_deq_en;
   wire [195:0] feedback_task_q_deq_data;
   wire feedback_task_q_empty;
   wire [9:0] class_index_feedback;
   wire [63:0] tokens_feedback;
   wire [25:0] dsc_head_index_feedback;
   wire [63:0] pkt_host_addr_feedback;
   wire [15:0] pkt_port_feedback;
   wire [15:0] pkt_len_feedback;
   assign {class_index_feedback,
           tokens_feedback,
           dsc_head_index_feedback,
           pkt_host_addr_feedback,
           pkt_port_feedback,
           pkt_len_feedback} = feedback_task_q_deq_data;
   

   // doorbell task queue
   fallthrough_small_fifo
   #(.WIDTH(128)
    )
   doorbell_task_q
   (.din(doorbell_task_q_data),
    .wr_en(doorbell_task_q_enq_en),
    .rd_en(doorbell_task_q_deq_en),
    .dout(doorbell_task_q_deq_data),
    .full(),
    .nearly_full(doorbell_task_q_full),
    .prog_full(),
    .empty(doorbell_task_q_empty),
    .reset(rst),
    .clk(clk)
   );

   // doorbell dne queue
   fallthrough_small_fifo
   #(.WIDTH(32)
    )
   doorbell_dne_q
   (.din(doorbell_dne_q_enq_data),
    .wr_en(doorbell_dne_q_enq_en),
    .rd_en(doorbell_dne_q_deq_en),
    .dout(doorbell_dne_q_deq_data),
    .full(),
    .nearly_full(doorbell_dne_q_full),
    .prog_full(),
    .empty(doorbell_dne_q_empty),
    .reset(rst),
    .clk(clk)
   );

   // tx task queue
   fallthrough_small_fifo
   #(.WIDTH(382)
    )
   tx_task_q
   (.din(tx_task_q_enq_data),
    .wr_en(tx_task_q_enq_en),
    .rd_en(tx_task_q_deq_en),
    .dout(tx_task_q_data),
    .full(),
    .nearly_full(tx_task_q_full),
    .prog_full(),
    .empty(tx_task_q_empty),
    .reset(rst),
    .clk(clk)
   );

   // feedback task queue
   fallthrough_small_fifo
   #(.WIDTH(196)
    )
   feedback_task_q
   (.din(feedback_task_q_enq_data),
    .wr_en(feedback_task_q_enq_en),
    .rd_en(feedback_task_q_deq_en),
    .dout(feedback_task_q_deq_data),
    .full(),
    .nearly_full(feedback_task_q_full),
    .prog_full(),
    .empty(feedback_task_q_empty),
    .reset(rst),
    .clk(clk)
   );

   reg          ram_wr_en;
   reg [9:0]    ram_addr;
   wire [511:0]  ram_din;
   wire [511:0] ram_dout;

   // has to be write first
   nicpic_ram u_ram
   (.clka(clk),
    .rsta(rst),
    .wea(ram_wr_en),
    .addra(ram_addr),
    .dina(ram_din),
    .douta(ram_dout)
   );

   reg [63:0] ram_din_dsc_buffer_host_addr;
   reg [31:0] ram_din_dsc_buffer_mask;
   reg [25:0] ram_din_dsc_head_index;
   reg [25:0] ram_din_dsc_tail_index;
   reg [63:0] ram_din_pkt_host_addr;
   reg [15:0] ram_din_pkt_port;
   reg [15:0] ram_din_pkt_len;
   reg [63:0] ram_din_rate;
   reg [63:0] ram_din_tokens;
   reg [63:0] ram_din_tokens_max;
   reg [63:0] ram_din_timestamp;
   reg ram_din_dirty;
   assign ram_din[511:500] = 0;
   assign ram_din[499:0] = {ram_din_dsc_buffer_host_addr,
                     ram_din_dsc_buffer_mask,
                     ram_din_dsc_head_index,
                     ram_din_dsc_tail_index,
                     ram_din_pkt_host_addr,
                     ram_din_pkt_port,
                     ram_din_pkt_len,
                     ram_din_rate,
                     ram_din_tokens,
                     ram_din_tokens_max,
                     ram_din_timestamp,
                     ram_din_dirty};

   wire [63:0] ram_dout_dsc_buffer_host_addr;
   wire [31:0] ram_dout_dsc_buffer_mask;
   wire [25:0] ram_dout_dsc_head_index;
   wire [25:0] ram_dout_dsc_tail_index;
   wire [63:0] ram_dout_pkt_host_addr;
   wire [15:0] ram_dout_pkt_port;
   wire [15:0] ram_dout_pkt_len;
   wire [63:0] ram_dout_rate;
   wire [63:0] ram_dout_tokens;
   wire [63:0] ram_dout_tokens_max;
   wire [63:0] ram_dout_timestamp;
   wire ram_dout_dirty;
   assign {ram_dout_dsc_buffer_host_addr,
           ram_dout_dsc_buffer_mask,
           ram_dout_dsc_head_index,
           ram_dout_dsc_tail_index,
           ram_dout_pkt_host_addr,
           ram_dout_pkt_port,
           ram_dout_pkt_len,
           ram_dout_rate,
           ram_dout_tokens,
           ram_dout_tokens_max,
           ram_dout_timestamp,
           ram_dout_dirty} = ram_dout[499:0];

   localparam STATE_IDLE = 0;
   localparam STATE_FEEDBACK = 1;
   localparam STATE_DOORBELL = 2;
   localparam STATE_TOKENS_L1 = 3;
   localparam STATE_TOKENS_L2 = 4;
   //localparam STATE_TOKENS_L3 = 5;

   reg [63:0] timestamp_reg, timestamp_reg_nxt;
   //reg [63:0] timestamp_old_reg, timestamp_old_reg_nxt;
   //reg [63:0] tokens_old_reg, tokens_old_reg_nxt;
   //reg [63:0] tokens_max_reg, tokens_max_reg_nxt;
   reg [63:0] pkt_host_addr_reg, pkt_host_addr_reg_nxt;
   reg [15:0] pkt_len_reg, pkt_len_reg_nxt;
   reg [63:0] rate_reg, rate_reg_nxt;
   reg [63:0] tokens_reg, tokens_reg_nxt;
   //reg        tokens_enough_reg, tokens_enough_reg_nxt;

   reg [3:0] state, state_nxt;
   reg doorbell_stall, doorbell_stall_nxt;
   reg [63:0] timecount;
   wire [63:0] timecount_nxt;
   assign timecount_nxt = timecount + 1;
   reg [9:0] class_index, class_index_nxt;
   wire [9:0] class_index_plus_1;
   assign class_index_plus_1 = class_index + 1;
   reg [9:0] class_num, class_num_nxt;
   wire [9:0] class_num_plus_1;
   assign class_num_plus_1 = class_num + 1;
   wire [9:0] class_num_minus_1;
   assign class_num_minus_1 = class_num - 1;
   wire [63:0] tokens_nxt;
   assign tokens_nxt = ((timecount - ram_dout_timestamp)<<4) + ram_dout_tokens;
   wire [63:0] tokens_needed;
   assign tokens_needed[63:27] = 0;
   assign tokens_needed[26:0] = pkt_len_reg[10:0] * rate_reg[15:0];

   assign tx_task_q_enq_data = {class_index,
                                tokens_reg,
                                ram_dout_rate,
                                ram_dout_dsc_buffer_host_addr,
                                ram_dout_dsc_buffer_mask,
                                ram_dout_dsc_head_index,
                                ram_dout_dsc_tail_index,
                                ram_dout_pkt_host_addr,
                                ram_dout_pkt_len,
                                ram_dout_pkt_port};

   always @(*) begin
      state_nxt = state;
      doorbell_stall_nxt = doorbell_stall;
      class_index_nxt = class_index;
      class_num_nxt = class_num;

      timestamp_reg_nxt = timestamp_reg;
      //timestamp_old_reg_nxt = timestamp_old_reg;
      //tokens_old_reg_nxt = tokens_old_reg;
      //tokens_max_reg_nxt = tokens_max_reg;
      pkt_host_addr_reg_nxt = pkt_host_addr_reg;
      pkt_len_reg_nxt = pkt_len_reg;
      rate_reg_nxt = rate_reg;
      tokens_reg_nxt = tokens_reg;
      //tokens_enough_reg_nxt = tokens_enough_reg;

      ram_din_dsc_buffer_host_addr = ram_dout_dsc_buffer_host_addr;
      ram_din_dsc_buffer_mask      = ram_dout_dsc_buffer_mask;
      ram_din_dsc_head_index       = ram_dout_dsc_head_index;
      ram_din_dsc_tail_index       = ram_dout_dsc_tail_index;
      ram_din_pkt_host_addr        = ram_dout_pkt_host_addr;
      ram_din_pkt_port             = ram_dout_pkt_port;
      ram_din_pkt_len              = ram_dout_pkt_len;
      ram_din_rate                 = ram_dout_rate;
      ram_din_tokens               = ram_dout_tokens;
      ram_din_tokens_max           = ram_dout_tokens_max;
      ram_din_timestamp            = ram_dout_timestamp;
      ram_din_dirty                = ram_dout_dirty;

      ram_wr_en = 0;
      ram_addr = 0;

      doorbell_task_q_deq_en = 0;
      doorbell_dne_q_enq_en = 0;
      tx_task_q_enq_en = 0;
      feedback_task_q_deq_en = 0;

      class_index_doorbell_dne = 0;
      inst_doorbell_dne = 0;
      success_doorbell_dne = 0;

      case(state)
         STATE_IDLE: begin
            if(!doorbell_task_q_empty && !doorbell_stall) begin
               ram_addr = class_index_doorbell;
               state_nxt = STATE_DOORBELL;
            end
            else if(!feedback_task_q_empty) begin
               ram_addr = class_index_feedback;
               state_nxt = STATE_FEEDBACK;
            end
            else if(class_num != 0) begin
               ram_addr = class_index;
               state_nxt = STATE_TOKENS_L1;
            end
         end

         STATE_TOKENS_L1: begin
            ram_addr = class_index;
            if(ram_dout_dirty) begin
               // skip to next class
               if(class_index >= class_num_minus_1) begin
                  class_index_nxt = 0;
               end
               else begin
                  class_index_nxt = class_index_plus_1;
               end
               state_nxt = STATE_IDLE;
            end
            else begin
               if(tokens_nxt < ram_dout_tokens_max) begin
                  tokens_reg_nxt = tokens_nxt;
               end
               else begin
                  tokens_reg_nxt = ram_dout_tokens_max;
               end

               timestamp_reg_nxt = timecount;
               //timestamp_old_reg_nxt = ram_dout_timestamp;
               //tokens_old_reg_nxt = ram_dout_tokens;
               //tokens_max_reg_nxt = ram_dout_tokens_max;
               pkt_host_addr_reg_nxt = ram_dout_pkt_host_addr;
               pkt_len_reg_nxt = ram_dout_pkt_len;
               rate_reg_nxt = ram_dout_rate;

               state_nxt = STATE_TOKENS_L2;
            end
         end

         STATE_TOKENS_L2: begin
            ram_addr = class_index;
            // send tx task
            if((pkt_host_addr_reg != 0) && 
               (tokens_reg >= tokens_needed) &&
               (rate_reg != 0)) begin
               if(!tx_task_q_full) begin
                  tx_task_q_enq_en = 1;

                  // set dirty bit
                  ram_wr_en = 1;
                  ram_din_tokens = tokens_reg;
                  ram_din_timestamp = timestamp_reg;
                  ram_din_dirty = 1;
                  // move to next class and state
                  if(class_index >= class_num_minus_1) begin
                     class_index_nxt = 0;
                  end
                  else begin
                     class_index_nxt = class_index_plus_1;
                  end
                  state_nxt = STATE_IDLE;
               end
            end
            else begin
               // move to next class and state
               if(class_index >= class_num_minus_1) begin
                  class_index_nxt = 0;
               end
               else begin
                  class_index_nxt = class_index_plus_1;
               end
               state_nxt = STATE_IDLE;
            end
         end

         STATE_FEEDBACK: begin
            feedback_task_q_deq_en = 1;
            ram_addr = class_index_feedback;
            ram_wr_en = 1;
            ram_din_tokens = tokens_feedback;
            // avoid stalls in consuming doorbells
            if((pkt_host_addr_feedback == 0) &&
               (dsc_head_index_feedback != ram_dout_dsc_tail_index)) begin
               ram_din_dsc_head_index = (dsc_head_index_feedback + 1) & 
                                        ram_dout_dsc_buffer_mask[31:6];
            end
            else begin
               ram_din_dsc_head_index = dsc_head_index_feedback;
               ram_din_pkt_host_addr = pkt_host_addr_feedback;
               ram_din_pkt_port = pkt_port_feedback;
               ram_din_pkt_len = pkt_len_feedback;
            end
            ram_din_dirty = 0;
            doorbell_stall_nxt = 0;
            state_nxt = STATE_IDLE;
         end

         STATE_DOORBELL: begin

            case(inst_doorbell)
               DOORBELL_ADD_CLASS: begin
                  if(!doorbell_dne_q_full) begin
                     if(class_num != 10'd1023) begin
                        class_num_nxt = class_num_plus_1;
                        ram_addr = class_num;
                        ram_wr_en = 1;
                        ram_din_dsc_buffer_host_addr = dsc_buffer_host_addr_doorbell;
                        ram_din_dsc_buffer_mask      = dsc_buffer_mask_doorbell;
                        ram_din_dsc_head_index       = 0;
                        ram_din_dsc_tail_index       = 0;
                        ram_din_pkt_host_addr        = 0;
                        ram_din_pkt_port             = 0;
                        ram_din_pkt_len              = 0;
                        ram_din_rate                 = 0;
                        ram_din_tokens               = 0;
                        ram_din_tokens_max           = 0;
                        ram_din_timestamp            = timecount;
                        ram_din_dirty                = 0;

                        success_doorbell_dne = 1;
                     end
                     else begin
                        success_doorbell_dne = 0;
                     end
                     inst_doorbell_dne = inst_doorbell;
                     class_index_doorbell_dne = class_num;
                     doorbell_dne_q_enq_en = 0;

                     doorbell_task_q_deq_en = 1;
                     state_nxt = STATE_IDLE;
                  end
               end

               DOORBELL_SET_RATE: begin
                  if(!doorbell_dne_q_full) begin
                     ram_addr = class_index_doorbell;
                     ram_wr_en = 1;
                     ram_din_rate = rate_doorbell;

                     inst_doorbell_dne = inst_doorbell;
                     class_index_doorbell_dne = class_index_doorbell;
                     success_doorbell_dne = 1;
                     doorbell_dne_q_enq_en = 0;

                     doorbell_task_q_deq_en = 1;
                     state_nxt = STATE_IDLE;
                  end
               end

               DOORBELL_SET_TOKENS_MAX: begin
                  if(!doorbell_dne_q_full) begin
                     ram_addr = class_index_doorbell;
                     ram_wr_en = 1;
                     ram_din_tokens_max = tokens_max_doorbell;

                     inst_doorbell_dne = inst_doorbell;
                     class_index_doorbell_dne = class_index_doorbell;
                     success_doorbell_dne = 1;
                     doorbell_dne_q_enq_en = 0;

                     doorbell_task_q_deq_en = 1;
                     state_nxt = STATE_IDLE;
                  end
               end

               DOORBELL_ADD_DSC: begin
                  ram_addr = class_index_doorbell;
                  if(!doorbell_dne_q_full) begin
                     ram_wr_en = 1;
                     if(ram_dout_dirty) begin
                        ram_din_dsc_tail_index = dsc_tail_index_doorbell;
                        ram_din_pkt_host_addr = pkt_host_addr_doorbell;
                        ram_din_pkt_port = pkt_port_doorbell;
                        ram_din_pkt_len = pkt_len_doorbell;
                     end
                     else begin
                        if(ram_dout_pkt_host_addr != 0) begin
                           ram_din_dsc_tail_index = dsc_tail_index_doorbell;
                        end
                        else begin
                           ram_din_dsc_head_index = (ram_dout_dsc_head_index + 1) & 
                                                    ram_dout_dsc_buffer_mask[31:6];
                           ram_din_dsc_tail_index = dsc_tail_index_doorbell;
                           ram_din_pkt_host_addr = pkt_host_addr_doorbell;
                           ram_din_pkt_port = pkt_port_doorbell;
                           ram_din_pkt_len = pkt_len_doorbell;
                        end
                     end

                     inst_doorbell_dne = inst_doorbell;
                     class_index_doorbell_dne = class_index_doorbell;
                     success_doorbell_dne = 1;
                     doorbell_dne_q_enq_en = 0;

                     doorbell_task_q_deq_en = 1;
                     state_nxt = STATE_IDLE;
                  end
               end

               DOORBELL_STOP_CLASS: begin
                  if(ram_dout_dirty) begin
                     doorbell_stall_nxt = 1;
                     state_nxt = STATE_IDLE;
                  end
                  else begin
                     ram_addr = class_index_doorbell;
                     if(!doorbell_dne_q_full) begin
                        ram_wr_en = 1;
                        ram_din_dsc_buffer_host_addr = 0;
                        ram_din_dsc_buffer_mask      = 0;
                        ram_din_dsc_head_index       = 0;
                        ram_din_dsc_tail_index       = 0;
                        ram_din_pkt_host_addr        = 0;
                        ram_din_pkt_port             = 0;
                        ram_din_pkt_len              = 0;
                        ram_din_rate                 = 0;
                        ram_din_tokens               = 0;
                        ram_din_tokens_max           = 0;
                        ram_din_timestamp            = 0;
                        ram_din_dirty                = 0;

                        inst_doorbell_dne = inst_doorbell;
                        class_index_doorbell_dne = class_index_doorbell;
                        success_doorbell_dne = 1;
                        doorbell_dne_q_enq_en = 0;

                        doorbell_task_q_deq_en = 1;
                        state_nxt = STATE_IDLE;
                     end
                  end
               end

               DOORBELL_DELETE_CLASS: begin
                  if(!doorbell_dne_q_full) begin
                     if(class_num != 0) begin
                        class_num_nxt = class_num_minus_1;
                        success_doorbell_dne = 1;
                     end
                     else begin
                        success_doorbell_dne = 0;
                     end

                     inst_doorbell_dne = inst_doorbell;
                     class_index_doorbell_dne = class_num_minus_1;
                     doorbell_dne_q_enq_en = 0;

                     doorbell_task_q_deq_en = 1;
                     state_nxt = STATE_IDLE;
                  end
               end

               default: begin
                  if(!doorbell_dne_q_full) begin
                     success_doorbell_dne = 0;
                     inst_doorbell_dne = inst_doorbell;
                     doorbell_dne_q_enq_en = 0;
                     doorbell_task_q_deq_en = 1;
                     state_nxt = STATE_IDLE;
                  end
               end
            endcase
         end
      endcase
   end

   always @(posedge clk) begin
      if(rst) begin
         state <= STATE_IDLE;
         doorbell_stall <= 0;
         timecount <= 0;
         class_index <= 0;
         class_num <= 0;
         timestamp_reg <= 0;
         //timestamp_old_reg <= 0;
         //tokens_old_reg <= 0;
         //tokens_max_reg <= 0;
         pkt_host_addr_reg <= 0;
         pkt_len_reg <= 0;
         rate_reg <= 0;
         tokens_reg <= 0;
         //tokens_enough_reg <= 0;
      end
      else begin
         state <= state_nxt;
         doorbell_stall <= doorbell_stall_nxt;
         timecount <= timecount_nxt;
         class_index <= class_index_nxt;
         class_num <= class_num_nxt;
         timestamp_reg <= timestamp_reg_nxt;
         //timestamp_old_reg <= timestamp_old_reg_nxt;
         //tokens_old_reg <= tokens_old_reg_nxt;
         //tokens_max_reg <= tokens_max_reg_nxt;
         pkt_host_addr_reg <= pkt_host_addr_reg_nxt;
         pkt_len_reg <= pkt_len_reg_nxt;
         rate_reg <= rate_reg_nxt;
         tokens_reg <= tokens_reg_nxt;
         //tokens_enough_reg <= tokens_enough_reg_nxt;
      end
   end

   /*
   localparam STATE_IDLE = 0;
   localparam STATE_L1 = 1;
   localparam STATE_L2 = 2;
   localparam STATE_L3 = 3;

   reg [1:0] state, state_nxt;
   reg [15:0] class_num_reg, class_num_reg_nxt;
   reg [31:0] tokens_reg, tokens_reg_nxt;
   reg [63:0] dsc_buffer_host_addr_reg, dsc_buffer_host_addr_reg_nxt;
   reg [31:0] dsc_buffer_mask_reg, dsc_buffer_mask_reg_nxt;
   reg [25:0] dsc_head_index_reg, dsc_head_index_reg_nxt;
   reg [25:0] dsc_tail_index_reg, dsc_tail_index_reg_nxt;
   reg [63:0] pkt_host_addr;
   reg [15:0] pkt_len;
   reg [15:0] pkt_port;
   assign tx_task_q_enq_data = {pkt_port, pkt_len, pkt_host_addr,
                                dsc_tail_index_reg, dsc_head_index_reg, dsc_buffer_mask_reg,
                                dsc_buffer_host_addr_reg, tokens_reg, class_num_reg};
//   assign state_out = state;
//   assign tokens_out = tokens_reg;

   always @(*) begin
      state_nxt = state;
      class_num_reg_nxt = class_num_reg;
      tokens_reg_nxt = tokens_reg;
      dsc_buffer_host_addr_reg_nxt = dsc_buffer_host_addr_reg;
      dsc_buffer_mask_reg_nxt = dsc_buffer_mask_reg;
      dsc_head_index_reg_nxt = dsc_head_index_reg;
      dsc_tail_index_reg_nxt = dsc_tail_index_reg;
      pkt_host_addr = 0;
      pkt_len = 0;
      pkt_port = 0;
      doorbell_task_q_deq_en = 0;
      tx_task_q_enq_en = 0;

      case(state)
         STATE_IDLE: begin
            if(!doorbell_task_q_empty) begin
               class_num_reg_nxt = doorbell_task_q_deq_data[15:0];
               tokens_reg_nxt = doorbell_task_q_deq_data[63:32];
               dsc_buffer_host_addr_reg_nxt = doorbell_task_q_deq_data[127:64];
               doorbell_task_q_deq_en = 1;
               state_nxt = STATE_L1;
            end
         end
         STATE_L1: begin
            if(!doorbell_task_q_empty) begin
               dsc_buffer_mask_reg_nxt = doorbell_task_q_deq_data[31:0];
               dsc_head_index_reg_nxt = doorbell_task_q_deq_data[63-:26];
               dsc_tail_index_reg_nxt = doorbell_task_q_deq_data[95-:26];
               doorbell_task_q_deq_en = 1;
               state_nxt = STATE_L2;
            end
         end
         STATE_L2: begin
            if(!doorbell_task_q_empty) begin
               pkt_host_addr = doorbell_task_q_deq_data[63:0];
               pkt_len = doorbell_task_q_deq_data[79:64];
               pkt_port = doorbell_task_q_deq_data[96+:16];
               if(!tx_task_q_full) begin
                  doorbell_task_q_deq_en = 1;
                  tx_task_q_enq_en = 1;
                  state_nxt = STATE_IDLE;
               end
            end
         end
      endcase
   end

   always @(posedge clk) begin
      if(rst) begin
         state <= STATE_IDLE;
         class_num_reg <= 0;
         tokens_reg <= 0;
         dsc_buffer_host_addr_reg <= 0;
         dsc_buffer_mask_reg <= 0;
         dsc_head_index_reg <= 0;
         dsc_tail_index_reg <= 0;
      end
      else begin
         state <= state_nxt;
         class_num_reg <= class_num_reg_nxt;
         tokens_reg <= tokens_reg_nxt;
         dsc_buffer_host_addr_reg <= dsc_buffer_host_addr_reg_nxt;
         dsc_buffer_mask_reg <= dsc_buffer_mask_reg_nxt;
         dsc_head_index_reg <= dsc_head_index_reg_nxt;
         dsc_tail_index_reg <= dsc_tail_index_reg_nxt;
      end
   end
   */

endmodule
