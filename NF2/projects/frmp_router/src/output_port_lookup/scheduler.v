///////////////////////////////////////////////////////////////////////////////
//
// Module: scheduler.v
// Project: CS344 Team 1 James Hongyi Zeng
// Description: A scheduler to inform the "position" of CURRENT in_data!
//
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps
  module scheduler
    #(parameter DATA_WIDTH = 64,
      parameter CTRL_WIDTH = DATA_WIDTH/8
      )
   (
    // --- Interface to the previous module
    input  [DATA_WIDTH-1:0]            in_data,
    input  [CTRL_WIDTH-1:0]            in_ctrl,
    input                              in_wr,

    // position information for other modules
    output reg                         word_IOQ,
    output reg                         word_MAC_DST,
    output reg                         word_MAC_SRC_HI,
    output reg                         word_MAC_SRC_LO,
    output reg                         word_ETHERTYPE,
    output reg                         word_IP_TTL,
    output reg                         word_IP_VER,
    output reg                         word_IP_CHECKSUM,
    output reg                         word_IP_DST_HI,
    output reg                         word_IP_DST_LO,
    output reg                         word_IP_SRC,
    output reg                         word_LAST_USEFUL,

    // --- Misc    
    input                              reset,
    input                              clk
   );

   function integer log2;
      input integer number;
      begin
         log2=0;
         while(2**log2<number) begin
            log2=log2+1;
         end
      end
   endfunction // log2
   
   //------------------ Internal Parameter ---------------------------
   parameter NUM_WORD_STATES                        = 7;
   parameter ST_WAIT_IOQ                            = 7'd1;
   parameter ST_WORD_1                              = 7'd2;
   parameter ST_WORD_2                              = 7'd4;
   parameter ST_WORD_3                              = 7'd8;
   parameter ST_WORD_4                              = 7'd16;
   parameter ST_WORD_5                              = 7'd32;
   parameter ST_WAIT_EOP                            = 7'd64;

   //---------------------- Wires/Regs -------------------------------
   reg [NUM_WORD_STATES-1:0]                            state, state_next;
       
   //------------------------ Logic ----------------------------------

   always @(*) begin
      state_next = state;
      word_IOQ = 0;
      word_MAC_DST = 0;
      word_MAC_SRC_HI = 0;
      word_MAC_SRC_LO = 0;
      word_ETHERTYPE = 0;
      word_IP_TTL = 0;
      word_IP_VER = 0;
      word_IP_CHECKSUM = 0;
      word_IP_DST_HI = 0;
      word_IP_DST_LO = 0;
      word_IP_SRC = 0;
      word_LAST_USEFUL = 0;
      
      case(state)
        ST_WAIT_IOQ: begin
           if(in_ctrl==`IO_QUEUE_STAGE_NUM && in_wr) begin 
	   //This is IOQ header and they want to write. MAC header is coming!
	      word_IOQ = 1;
              state_next     = ST_WORD_1;
           end
        end

        ST_WORD_1: begin
           word_MAC_DST = 1;
           word_MAC_SRC_HI = 1;
           if(in_wr) begin
              state_next = ST_WORD_2;
           end
        end

        ST_WORD_2: begin
	   word_MAC_SRC_LO = 1;
	   word_ETHERTYPE = 1;
           if(in_wr) begin
              state_next = ST_WORD_3;
           end
        end

        ST_WORD_3: begin
	   word_IP_TTL = 1;
           if(in_wr) begin
              state_next = ST_WORD_4;
           end
        end

        ST_WORD_4: begin
	   word_IP_CHECKSUM = 1;
	   word_IP_SRC = 1;
	   word_IP_DST_HI = 1;
           if(in_wr) begin
              state_next = ST_WORD_5;
           end
        end

        ST_WORD_5: begin
	   word_IP_DST_LO = 1;
	   word_LAST_USEFUL = 1;
           if(in_wr) begin
              state_next = ST_WAIT_EOP;
           end
        end

        ST_WAIT_EOP: begin
           if(in_ctrl!=0 && in_wr) begin
	   //This is EOP and they want to write. We are looking for a new packet!
              state_next = ST_WAIT_IOQ;
           end
        end
      endcase // case(state)
   end // always @ (*)
   
   always@(posedge clk) begin
      if(reset) begin
         state <= ST_WAIT_IOQ;
      end
      else begin
         state <= state_next;
      end
   end

endmodule // op_lut_hdr_parser
