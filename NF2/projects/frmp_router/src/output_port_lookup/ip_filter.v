`timescale 1ns/1ps
  module ip_filter
 (
    // --- Interface to the main state machine
    input				ip_filter_req,
    output reg				ip_filter_done,
    input [31:0] 			search_ip,
    output reg      			found,

   // --- Table interface
    input                               table_rd_req,
    output reg                          table_rd_ack,
    input    [4:0]                      table_rd_addr,
    output reg [31:0]                   table_rd_data,
    input                               table_wr_req,
    output reg                          table_wr_ack,
    input    [4:0]                      table_wr_addr,
    input      [31:0]                   table_wr_data,

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
   parameter NUM_STATES		                    = 3;
   parameter ST_WAIT_FOR_REQ                        = 3'd1;
   parameter ST_SEARCH	                            = 3'd2;

   parameter ST_REG_WAIT_FOR_REQ		    = 3'd1;
   parameter ST_REG_READ_FROM_TABLE		    = 3'd2;
   parameter ST_REG_WRITE_TO_TABLE		    = 3'd4;   

   //---------------------- Wires/Regs -------------------------------
   reg [4:0]				table_addr, table_addr_next;
   reg [31:0]				ip;
   wire [31:0]				table_dout;
   reg [NUM_STATES-1:0]			state, state_next;

   // To the registers
   reg [NUM_STATES-1:0]			reg_state, reg_state_next;
   reg					reg_table_write_enable;
   reg  [31:0]				reg_table_din;
   wire [31:0]				reg_table_dout;
   reg	[4:0]				reg_table_addr;

   reg				first_time, first_time_next;


   //----------------------- Modules ---------------------------------
  sync_32x32_table
   ip_table
   (
   // 1st Port: Used by main state machine
	.clka(clk),
	.dina(0),
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
      ip_filter_done	= 0;
      ip 		= search_ip;
      found 		= 0;
      case(state)
         ST_WAIT_FOR_REQ: begin
		if(ip_filter_req) begin
			table_addr_next = 0;
			state_next = ST_SEARCH;
			first_time_next = 1;
		end	
         end // case: ST_WAIT_FOR_REQ

         ST_SEARCH: begin
		table_addr_next	= table_addr + 1;
		first_time_next = 0;
		if(table_dout == ip) begin
			found = 1;
			ip_filter_done = 1;
			state_next = ST_WAIT_FOR_REQ;
		end
		else if(table_addr == 0 && !first_time) begin
			ip_filter_done = 1;
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
      reg_table_din = table_wr_data;
      reg_table_addr = table_rd_addr;
      table_rd_data = reg_table_dout;

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
	 first_time <= 0;
      end
      else begin
	 table_addr <= table_addr_next;
         state <= state_next;
         reg_state <= reg_state_next;
	 first_time <= first_time_next;
      end
   end

  endmodule
