`timescale 1ns/1ps
  module lpm_lookup
 (
    // --- Interface to the main state machine
    input				lpm_lookup_req,
    output reg				lpm_lookup_done,
    input [31:0] 			search_ip,
    output reg [31:0]     		nexthop_ip,
    output reg [15:0]     		port,

   // --- Table interface
    input                               table_rd_req,
    output reg                          table_rd_ack,
    input    [5:0]                      table_rd_addr,
    output reg [127:0]                  table_rd_data,
    input                               table_wr_req,
    output reg                          table_wr_ack,
    input    [5:0]                      table_wr_addr,
    input      [127:0]                  table_wr_data,

   // --- Table interface
    input                               gateway_table_rd_req,
    output reg                          gateway_table_rd_ack,
    input    [4:0]                      gateway_table_rd_addr,
    output reg [31:0]                  gateway_table_rd_data,
    input                               gateway_table_wr_req,
    output reg                          gateway_table_wr_ack,
    input    [4:0]                      gateway_table_wr_addr,
    input      [31:0]                  gateway_table_wr_data,

    // For Fast Reroute
    input  [7:0]			eth_link_status,
    input				fast_reroute_enable,
    input				multipath_enable,

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
   parameter NUM_STATES		                    = 10;
   parameter ST_WAIT_FOR_REQ                        = 10'd1;
   parameter ST_SEARCH	                            = 10'd2;
   parameter ST_MATCH	                            = 10'd4;
   parameter ST_LOOK_FOR_OUTPUT                     = 10'd8;
   parameter ST_UPDATE_START_POSITION		    = 10'd16;
   parameter ST_WAIT_ROUTING_TABLE		    = 10'd32;
   parameter ST_OUTPUT_RESULT			    = 10'd64;
   parameter ST_NEXTHOP_IP			    = 10'd128;
   parameter ST_WAIT_GATEWAY_TABLE		    = 10'd256;
  
   parameter ST_REG_WAIT_FOR_REQ		    = 10'd1;
   parameter ST_REG_READ_FROM_TABLE		    = 10'd2;
   parameter ST_REG_WRITE_TO_TABLE		    = 10'd4;   

   //---------------------- Wires/Regs -------------------------------
   // To the main state machine
   reg [5:0]				table_addr, table_addr_next;
   reg [31:0]				ip;
   wire [127:0]				table_dout;
   reg [NUM_STATES-1:0]			state, state_next;

   // To the registers
   reg [NUM_STATES-1:0]			reg_state, reg_state_next;
   reg					reg_table_write_enable;
   reg  [127:0]				reg_table_din;
   wire [127:0]				reg_table_dout;
   reg	[5:0]				reg_table_addr;

   // To the lpm_lookup
   reg [4:0]				gateway_table_addr, gateway_table_addr_next;
   wire [31:0]				gateway_table_dout;

   // To the registers
   reg [NUM_STATES-1:0]			gateway_reg_state, gateway_reg_state_next;
   reg					gateway_reg_table_write_enable;
   reg  [31:0]				gateway_reg_table_din;
   wire [31:0]				gateway_reg_table_dout;
   reg	[4:0]				gateway_reg_table_addr;

   reg[31:0] 				masked_entry,masked_searchkey;
   reg[15:0]				entry_port;
   reg[31:0]				entry_nexthop_ip;
   wire					matched;

   reg  [31:0]     			nexthop_ip_next;
   reg    [15:0]     			port_next;
   reg   				lpm_lookup_done_next;

   reg  [7:0]				port_position, port_position_start, port_position_next, port_position_start_next;
   wire	[7:0]				port_position_hit;
   reg					first_time, first_time_next;

   //----------------------- Modules ---------------------------------
  sync_64x128_table
   lpm_table
   (
   // 1st Port: Used by main state machine
	.clka(clk),
	.dina(128'b0),
	.addra(table_addr),
	.wea(64'b0),
	.douta(table_dout),

   // 2nd Port: Used by register
	.clkb(clk),
	.dinb(reg_table_din),
	.addrb(reg_table_addr),
	.web(reg_table_write_enable),
	.doutb(reg_table_dout)
   );

  sync_32x32_table
   gateway_table
   (
   // 1st Port: Used by lpm_lookup
	.clka(clk),
	.dina(32'b0),
	.addra(gateway_table_addr),
	.wea(0),
	.douta(gateway_table_dout),

   // 2nd Port: Used by register
	.clkb(clk),
	.dinb(gateway_reg_table_din),
	.addrb(gateway_reg_table_addr),
	.web(gateway_reg_table_write_enable),
	.doutb(gateway_reg_table_dout)
   );

   //------------------------ Logic ----------------------------------
   assign matched = (masked_entry == masked_searchkey) && (masked_entry!=32'b0);
   assign port_position_hit = fast_reroute_enable ? (port_position & port) & eth_link_status : port_position & port;

   always @(*) begin
      table_addr_next		= table_addr;
      gateway_table_addr	= 0;
      state_next        	= state;
      ip 			= search_ip;
      lpm_lookup_done_next	= lpm_lookup_done;
      nexthop_ip_next 		= nexthop_ip;
      port_next	   		= port;

      port_position_next 	= port_position;
      port_position_start_next 	= port_position_start; 
      first_time_next 		= 0;


      case(state)

         ST_WAIT_FOR_REQ: begin
		lpm_lookup_done_next	= 0;
		if(lpm_lookup_req) begin
      			nexthop_ip_next 	= 32'hffffffff;
      			port_next	   	= 0;	
			table_addr_next 	= 0;
			state_next 		= ST_WAIT_ROUTING_TABLE;
		end	
         end // case: ST_WAIT_FOR_REQ

	 ST_WAIT_ROUTING_TABLE: begin
		state_next = ST_SEARCH;
		first_time_next = 1;
	 end // case: ST_WAIT_ROUTING_TABLE

         ST_SEARCH: begin
		//set gateway_addr
		if(entry_port==8'h01) begin
			gateway_table_addr = entry_nexthop_ip[7:0];
		end
		if(entry_port==8'h04) begin
			gateway_table_addr = entry_nexthop_ip[15:8];
		end
		if(entry_port==8'h10) begin
			gateway_table_addr = entry_nexthop_ip[23:16];
		end
		if(entry_port==8'h40) begin
			gateway_table_addr = entry_nexthop_ip[31:24];
		end
		if(matched) begin
			if(multipath_enable) begin
				port_next = entry_port;
				nexthop_ip_next = entry_nexthop_ip;
				first_time_next = 1;
				port_position_next = port_position_start;
				state_next = ST_LOOK_FOR_OUTPUT;
			end
			else begin
				port_next = fast_reroute_enable ? entry_port & eth_link_status : entry_port;
				if(port_next) begin
					state_next = ST_NEXTHOP_IP;
				end
			end // else(no multipath)
		end
		else begin
			table_addr_next	= table_addr + 1;
			if(table_addr == 0 && !first_time) begin
				lpm_lookup_done_next = 1;
				state_next = ST_WAIT_FOR_REQ;
			end
		end 
         end // case: ST_SEARCH

	 ST_LOOK_FOR_OUTPUT: begin
		port_position_next = (port_position << 1) + port_position[7];
		//set gateway_addr
		if(port_position_hit==8'h01) begin
			gateway_table_addr = nexthop_ip[7:0];
		end
		if(port_position_hit==8'h04) begin
			gateway_table_addr = nexthop_ip[15:8];
		end
		if(port_position_hit==8'h10) begin
			gateway_table_addr = nexthop_ip[23:16];
		end
		if(port_position_hit==8'h40) begin
			gateway_table_addr = nexthop_ip[31:24];
		end
		if(port_position_hit) begin
			port_next = port_position_hit;
			port_position_start_next = (port_position << 1) + port_position[7];
			state_next = ST_NEXTHOP_IP;
		end
		else if(port_position == port_position_start && first_time == 0) begin
			table_addr_next	= table_addr + 1;
			port_next = 0;
			state_next = ST_SEARCH;		
		end
        end // case:ST_LOOK_FOR_OUTPUT

        ST_NEXTHOP_IP: begin
		nexthop_ip_next = gateway_table_dout;
		lpm_lookup_done_next = 1;
		state_next = ST_WAIT_FOR_REQ;
	end // case:ST_NEXTHOP_IP

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

   always @(*) begin
      gateway_reg_state_next    = gateway_reg_state;
      gateway_table_rd_ack	= 0;
      gateway_table_wr_ack	= 0;
      gateway_reg_table_write_enable = 0;
      gateway_reg_table_din = gateway_table_wr_data;
      gateway_reg_table_addr = gateway_table_rd_addr;
      gateway_table_rd_data = gateway_reg_table_dout;

      case(gateway_reg_state)
         ST_REG_WAIT_FOR_REQ: begin
		if(gateway_table_wr_req) begin
      			gateway_reg_table_addr = gateway_table_wr_addr;
			//reg_table_write_enable = 1;
			gateway_reg_state_next = ST_REG_WRITE_TO_TABLE;
		end
		else if(gateway_table_rd_req) begin
			gateway_reg_table_addr = gateway_table_rd_addr;
			gateway_reg_state_next = ST_REG_READ_FROM_TABLE;	
		end
         end // case: ST_REG_WAIT_FOR_REQ

         ST_REG_WRITE_TO_TABLE: begin
		gateway_reg_table_addr = gateway_table_wr_addr;
		gateway_reg_table_write_enable = 1;
		gateway_reg_state_next = ST_REG_WAIT_FOR_REQ;
		gateway_table_wr_ack = 1;
	 end // case: ST_REG_WRITE_TO_TABLE

         ST_REG_READ_FROM_TABLE: begin
		gateway_reg_state_next = ST_REG_WAIT_FOR_REQ;
		gateway_table_rd_ack = 1;
	 end // case: ST_REG_READ_FROM_TABLE

      endcase // case(reg_state)
   end // always @ (*)

   always @(posedge clk) begin
      if(reset) begin
         state 			<= ST_WAIT_FOR_REQ;
         reg_state 		<= ST_REG_WAIT_FOR_REQ;
         gateway_reg_state 	<= ST_REG_WAIT_FOR_REQ;

	 table_addr 		<= 6'd63;
         lpm_lookup_done	<= 0;
         nexthop_ip 		<= 32'hffffffff;
         port	   		<= 0;

	 port_position 		<= 8'h1;
	 port_position_start 	<= 8'h1;
      end
      else begin
	 table_addr 		<= table_addr_next;
         state 			<= state_next;
         gateway_reg_state 	<= gateway_reg_state_next;
         reg_state 		<= reg_state_next;

         lpm_lookup_done	<= lpm_lookup_done_next;
         nexthop_ip 		<= nexthop_ip_next;
         port	   		<= port_next;

         masked_entry 		<= table_dout[127:96] & table_dout[95:64];
	 masked_searchkey 	<= ip & table_dout[95:64];
	 entry_port 		<= table_dout[15:0];
	 entry_nexthop_ip 	<= table_dout[63:32];

      	 port_position 		<= port_position_next;
	 port_position_start 	<= port_position_start_next;
	 first_time 		<= first_time_next;
      end
   end

  endmodule
