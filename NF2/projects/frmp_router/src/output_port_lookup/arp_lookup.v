`timescale 1ns/1ps
  module arp_lookup
 (
    // --- Interface to the main state machine
    input				arp_lookup_req,
    output reg				arp_lookup_done,
    input [31:0] 			search_ip,
    output reg [47:0]  			result_mac,

   // --- Table interface
    input                               table_rd_req,
    output reg                          table_rd_ack,
    input    [4:0]                      table_rd_addr,
    output reg [95:0]                  table_rd_data,
    input                               table_wr_req,
    output reg                          table_wr_ack,
    input    [4:0]                      table_wr_addr,
    input      [95:0]                  table_wr_data,


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
   parameter NUM_STATES		                    = 8;
   parameter ST_WAIT_FOR_REQ                        = 8'd1;
   parameter ST_SEARCH	                            = 8'd2;

   parameter ST_REG_WAIT_FOR_REQ		    = 8'd1;
   parameter ST_REG_READ_FROM_TABLE		    = 8'd2;
   parameter ST_REG_WRITE_TO_TABLE		    = 8'd4;   

   //---------------------- Wires/Regs -------------------------------
   reg [4:0]				table_addr, table_addr_next;
   reg [31:0]				ip;
   wire [95:0]				table_dout;
   reg [NUM_STATES-1:0]			state, state_next;

   // To the registers
   reg [NUM_STATES-1:0]			reg_state, reg_state_next;
   reg					reg_table_write_enable;
   reg  [95:0]				reg_table_din;
   wire [95:0]				reg_table_dout;
   reg	[4:0]				reg_table_addr;

   reg [47:0]  			result_mac_next;
   reg				arp_lookup_done_next;

   reg				first_time, first_time_next;


   //----------------------- Modules ---------------------------------
  sync_32x96_table
   arp_table
   (
   // 1st Port: Used by main state machine
	.clka(clk),
	.dina(96'b0),
	.addra(table_addr),
	.wea(0),
	.douta(table_dout),

   // 2nd Port: Used by register
	.clkb(clk),
	.dinb(reg_table_din),
	.addrb(reg_table_addr),
	.web(reg_table_write_enable),
	.doutb(reg_table_dout)
   );


   //------------------------ Logic ----------------------------------
   always @(*) begin
      first_time_next	= first_time;
      table_addr_next	= table_addr;
      state_next        = state;
      ip 		= search_ip;
      arp_lookup_done_next	= arp_lookup_done;
      result_mac_next = result_mac;
      case(state)

         ST_WAIT_FOR_REQ: begin
		arp_lookup_done_next = 0;
		if(arp_lookup_req) begin
			result_mac_next = 48'b0;
			table_addr_next = 0;
			state_next = ST_SEARCH;
			first_time_next = 1;
		end	
         end // case: ST_WAIT_FOR_REQ

         ST_SEARCH: begin
		table_addr_next	= table_addr + 1;
		first_time_next = 0;
		if(table_dout[31:0] == ip) begin
			result_mac_next = table_dout[95:32];
			arp_lookup_done_next = 1;
			state_next = ST_WAIT_FOR_REQ;
		end
		else if(table_addr == 0 && !first_time) begin
			arp_lookup_done_next = 1;
			state_next = ST_WAIT_FOR_REQ;
		end	
         end // case: ST_SEARCH
      endcase // case(state)
   end // always @ (*)


   always @(*) begin
      reg_state_next    = reg_state;
      table_rd_ack	= 0;
      table_wr_ack	= 0;
      reg_table_write_enable = 0;
      table_rd_data = reg_table_dout;
      reg_table_din = table_wr_data;
      reg_table_addr = table_rd_addr;

      case(reg_state)
         ST_REG_WAIT_FOR_REQ: begin
		if(table_wr_req) begin
		        reg_table_addr = table_wr_addr;
			//reg_table_write_enable = 1;
			reg_state_next = ST_REG_WRITE_TO_TABLE;
		end
		else if(table_rd_req) begin
			reg_table_addr = table_rd_addr;
			reg_state_next = ST_REG_READ_FROM_TABLE;	
		end
         end // case: ST_REG_WAIT_FOR_REQ

         ST_REG_WRITE_TO_TABLE: begin
		reg_table_addr = table_wr_addr;
		reg_table_write_enable = 1;
		reg_state_next = ST_REG_WAIT_FOR_REQ;
		table_wr_ack = 1;
	 end // case: ST_REG_WRITE_TO_TABLE

         ST_REG_READ_FROM_TABLE: begin
		reg_state_next = ST_REG_WAIT_FOR_REQ;
		table_rd_ack = 1;
	 end // case: ST_REG_READ_FROM_TABLE

      endcase // case(reg_state)
   end // always @ (*)

   always @(posedge clk) begin
      if(reset) begin
         state <= ST_WAIT_FOR_REQ;
         reg_state <= ST_REG_WAIT_FOR_REQ;
	 table_addr <=  5'd31;
	 arp_lookup_done <= 0;
	 first_time <= 0;
         result_mac <= 0;
      end
      else begin
	 table_addr <= table_addr_next;
	 first_time <= first_time_next;
         state <= state_next;
         reg_state <= reg_state_next;
         arp_lookup_done <= arp_lookup_done_next;
         result_mac <= result_mac_next;
      end
   end

  endmodule
