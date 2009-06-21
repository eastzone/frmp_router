///////////////////////////////////////////////////////////////////////////////
//
// Module: ttl_checksum.v
// Description: provides packet information (ARP, IPv4) and addresses (MAC/IP)
//
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps
  module ttl_checksum
    #(parameter DATA_WIDTH = 64
      )
   (// --- Interface to the previous module
    input  [DATA_WIDTH-1:0]            in_data,

    // --- Interface to the main state machine
    output                             bad_ttl,
    output                             bad_checksum,
    output  [7:0]                      new_ttl,
    output  [15:0]                     new_checksum,
    output                             ttl_checksum_in_rdy,
    input                              ttl_checksum_rd,
    output                             ttl_checksum_vld,

    // --- Interface to scheduler
    input                              word_IOQ,//Reset all regs! new packet coming!
    input                              word_MAC_DST,
    input                              word_MAC_SRC_HI,
    input                              word_MAC_SRC_LO,
    input                              word_IP_CHECKSUM,
    input                              word_ETHERTYPE,
    input                              word_IP_DST_HI,
    input                              word_IP_DST_LO,
    input                              word_IP_SRC,
    input                              word_IP_TTL,
    input                              word_LAST_USEFUL,//This is the last useful word.

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
   
   parameter ST_PARSE = 0;
   parameter ST_WRITE = 1;
   parameter ST_CHECKSUM = 2;
   parameter ST_VERIFY = 4;


   //---------------------- Wires/Regs -------------------------------
   reg		local_bad_ttl,local_bad_ttl_next;
   reg		local_bad_checksum,local_bad_checksum_next;
   reg	[7:0]	local_new_ttl,local_new_ttl_next;
   reg	[15:0]	local_new_checksum,local_new_checksum_next;
   wire		fifo_empty;
   wire		fifo_nearly_full;
   reg		fifo_wr_en;
   reg [2:0]	state,	state_next;

   reg [16:0]	temp_checksum;
   reg [18:0]	checksum_1, checksum_2, checksum_3, checksum_4;
   reg [18:0]	checksum_1_next, checksum_2_next, checksum_3_next, checksum_4_next;
   reg [18:0]	checksum, checksum_next;
   wire [16:0]   checksum_adjusted, checksum_adjusted_adjusted;
   reg [3:0]	checksum_position, checksum_position_next;

   //----------------------- Modules ---------------------------------
   fallthrough_small_fifo #(.WIDTH(8+16+2), .MAX_DEPTH_BITS(2))
      ttl_checksum_fifo
        (.din ({local_bad_ttl, local_bad_checksum, local_new_ttl, local_new_checksum}),
         .wr_en (fifo_wr_en),
         .rd_en (ttl_checksum_rd),
         .dout ({bad_ttl, bad_checksum, new_ttl, new_checksum}),
         .full (),
         .nearly_full (fifo_nearly_full),
         .empty (fifo_empty),
         .reset (reset),
         .clk (clk)
         );   
       
   //------------------------ Logic ----------------------------------
   assign ttl_checksum_vld = !fifo_empty;
   assign ttl_checksum_in_rdy = !fifo_nearly_full;

   assign checksum_adjusted = checksum[15:0] + checksum[18:16];
   assign checksum_adjusted_adjusted = checksum_adjusted[15:0] + checksum_adjusted[16];

   always @(*) begin
	temp_checksum = 0;
	local_bad_ttl_next = local_bad_ttl;
	local_new_ttl_next = local_new_ttl;
	local_new_checksum_next = local_new_checksum;
	if(word_IP_TTL) begin
		if(in_data[15:8]==0 || in_data[15:8]==1) local_bad_ttl_next = 1;
		else local_bad_ttl_next = 0;
		//In fact, incoming TTL = 0 cannot happen.
		local_new_ttl_next = in_data[15:8] - 1;
	end
	if(word_IP_CHECKSUM) begin
		temp_checksum = {1'h0, in_data[DATA_WIDTH-1:DATA_WIDTH-16]} + 17'h0100;
		local_new_checksum_next = temp_checksum[15:0] + temp_checksum[16];
	end
   end // always @ (*)

   //Checksum verification
   always@(*) begin
      state_next = state;
      fifo_wr_en = 0;
      local_bad_checksum_next = local_bad_checksum;
      checksum_position_next = checksum_position;
      checksum_next = checksum;

      checksum_1_next = checksum_1;
      checksum_2_next = checksum_2;
      checksum_3_next = checksum_3;
      checksum_4_next = checksum_4;

      case(state)
        ST_PARSE: begin
	   if(word_IOQ) begin
		checksum_position_next = 0;
		checksum_next = 0;
	   end
	   if(word_ETHERTYPE && checksum_position[0] == 0) begin //1st word
		checksum_1_next = in_data[15:0];
		checksum_position_next[0] = 1;
	   end
	   if(word_IP_TTL && checksum_position[1] == 0) begin //2nd word
		checksum_2_next = in_data[15:0] + in_data[31:16] + in_data[47:32] + in_data[63:48];
		checksum_position_next[1] = 1;
	   end
	   if(word_IP_CHECKSUM && checksum_position[2] == 0) begin //3rd word
		checksum_3_next = in_data[15:0] + in_data[31:16] + in_data[47:32] + in_data[63:48];
		checksum_position_next[2] = 1;
	   end
	   if(word_IP_DST_LO && checksum_position[3] == 0) begin //4th word
		checksum_4_next = in_data[63:48];
		checksum_position_next[3] = 1;
		state_next = ST_CHECKSUM;
	   end
        end

	ST_CHECKSUM: begin
	   checksum_next = checksum_1_next + checksum_2_next + checksum_3_next + checksum_4_next;
           state_next = ST_WRITE;
        end

	ST_VERIFY: begin
	   local_bad_checksum_next = (checksum_adjusted_adjusted[15:0] != 16'hffff);
           state_next = ST_WRITE;
        end

        ST_WRITE: begin
	      state_next = ST_PARSE;
	      fifo_wr_en = 1;
        end
      endcase // case(state)
   end // always@ (*)

   always @(posedge clk) begin
      if(reset) begin
		local_bad_ttl <= 0;
		local_bad_checksum <= 0;
		local_new_ttl <= 0;
		local_new_checksum <= 0;
		checksum <= 0;
		checksum_position <= 0;
	        state <= ST_PARSE;
      end 
      else begin
		local_bad_ttl <= local_bad_ttl_next;
		local_bad_checksum <= local_bad_checksum_next;
		local_new_ttl <= local_new_ttl_next;
		local_new_checksum <= local_new_checksum_next;
		checksum <= checksum_next;
		checksum_position <= checksum_position_next;
	        state <= state_next;
      end

   end
endmodule // ttl_checksum

  
