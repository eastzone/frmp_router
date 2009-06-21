///////////////////////////////////////////////////////////////////////////////
//
// Module: header_parser.v
// Description: provides packet information (ARP, IPv4) and addresses (MAC/IP)
//
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps
  module header_parser
    #(parameter DATA_WIDTH = 64,
      parameter NUM_QUEUES = 8,
      parameter NUM_QUEUES_WIDTH = log2(NUM_QUEUES)
      )
   (// --- Interface to the previous module
    input  [DATA_WIDTH-1:0]            in_data,

    // --- Interface to the main state machine
    output                             wrong_dest, //DROP the packet please!
    output			       broadcast_packet,
    output                             cpu_packet,  //Packet from CPU. Just let it go!
    output                             ip_packet,   //Please check TTL and checksum before search.
    output                             arp_packet,  //An arp packet.
    output                             ospf_packet,  //An arp packet.
    output                             unknown_packet,
    output			       bad_version,

    output  [47:0]                     mac_addr_src,
    output  [47:0]                     mac_addr_dst,

    output  [31:0]                     ip_addr_src,
    output  [31:0]                     ip_addr_dst,

    output                             header_parser_in_rdy,
    input                              header_parser_rd,
    output                             header_parser_vld,

    // --- Interface to scheduler
    input                              word_IOQ,//Reset all regs! new packet coming!
    input                              word_MAC_DST,
    input                              word_MAC_SRC_HI,
    input                              word_MAC_SRC_LO,
    input                              word_ETHERTYPE,
    input                              word_IP_DST_HI,
    input                              word_IP_DST_LO,
    input                              word_IP_SRC,
    input                              word_IP_TTL,
    input                              word_LAST_USEFUL,//This is the last useful word.

    // --- Interface to registers
    input  [47:0]                      mac_addr_0,
    input  [47:0]                      mac_addr_1,
    input  [47:0]                      mac_addr_2,
    input  [47:0]                      mac_addr_3,

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

   //---------------------- Wires/Regs -------------------------------
   reg		local_wrong_dest,local_wrong_dest_next;
   reg		local_cpu_packet,local_cpu_packet_next;
   reg		local_arp_packet,local_arp_packet_next;
   reg		local_ospf_packet,local_ospf_packet_next;
   reg		local_ip_packet,local_ip_packet_next;
   reg		local_unknown_packet,local_unknown_packet_next;
   reg		local_broadcast_packet,local_broadcast_packet_next;
   reg		local_bad_version,local_bad_version_next;
   reg	[47:0]	local_mac_addr_src,local_mac_addr_src_next;
   reg	[47:0]	local_mac_addr_dst,local_mac_addr_dst_next;
   reg	[31:0]	local_ip_addr_src,local_ip_addr_src_next;
   reg	[31:0]	local_ip_addr_dst,local_ip_addr_dst_next;
   reg  [15:0]	src_port, src_port_next;

   wire		fifo_empty;
   wire		fifo_nearly_full;
   reg		fifo_wr_en;
   reg		state,	state_next;

   //----------------------- Modules ---------------------------------
   // The three small fifos are synchronized. If some values are invalid (for example, a non-IP
   // packet doesn't have an IP address), the main state machine will discard the information.
   fallthrough_small_fifo #(.WIDTH(8), .MAX_DEPTH_BITS(2))
      information_fifo
        (.din ({local_wrong_dest, local_cpu_packet, local_broadcast_packet, local_ip_packet, local_arp_packet, local_ospf_packet, local_unknown_packet, local_bad_version}),
         .wr_en (fifo_wr_en),
         .rd_en (header_parser_rd),
         .dout ({wrong_dest, cpu_packet, broadcast_packet, ip_packet, arp_packet, ospf_packet, unknown_packet, bad_version}),
         .full (),
         .nearly_full (fifo_nearly_full),
         .empty (fifo_empty),
         .reset (reset),
         .clk (clk)
         );   

   fallthrough_small_fifo #(.WIDTH(48*2), .MAX_DEPTH_BITS(2))
      mac_addr_fifo
        (.din ({local_mac_addr_src,local_mac_addr_dst}),
         .wr_en (fifo_wr_en),
         .rd_en (header_parser_rd),
         .dout ({mac_addr_src,mac_addr_dst}),
         .full (),
         .nearly_full (),
         .empty (),
         .reset (reset),
         .clk (clk)
         ); 

   fallthrough_small_fifo #(.WIDTH(32*2), .MAX_DEPTH_BITS(2))
      ip_addr_fifo
        (.din ({local_ip_addr_src,local_ip_addr_dst}),
         .wr_en (fifo_wr_en),
         .rd_en (header_parser_rd),
         .dout ({ip_addr_src,ip_addr_dst}),
         .full (),
         .nearly_full (),
         .empty (),
         .reset (reset),
         .clk (clk)
         ); 
       
   //------------------------ Logic ----------------------------------
   assign header_parser_vld = !fifo_empty;
   assign header_parser_in_rdy = !fifo_nearly_full;

   //In fact, we don't need mac_src and ip_src. But it is worth to write it down for now.
   always @(*) begin
	local_wrong_dest_next = local_wrong_dest;
	local_cpu_packet_next = local_cpu_packet;
	local_arp_packet_next = local_arp_packet;
	local_ospf_packet_next = local_ospf_packet;
	local_ip_packet_next  = local_ip_packet;
	local_broadcast_packet_next  = local_broadcast_packet;
	local_unknown_packet_next = local_unknown_packet;
	local_mac_addr_src_next = local_mac_addr_src;
	local_mac_addr_dst_next = local_mac_addr_dst;
	local_ip_addr_src_next = local_ip_addr_src;
	local_ip_addr_dst_next = local_ip_addr_dst;
	local_bad_version_next = local_bad_version;

        src_port_next = src_port;

	if(word_IOQ) begin
		local_cpu_packet_next = in_data[`IOQ_SRC_PORT_POS];
		src_port_next = in_data[`IOQ_SRC_PORT_POS+15:`IOQ_SRC_PORT_POS];
	end
	if(word_MAC_DST) begin
		local_mac_addr_dst_next = in_data[DATA_WIDTH-1:DATA_WIDTH-48];
		local_broadcast_packet_next = local_mac_addr_dst_next[40] == 1;
		local_wrong_dest_next = !((local_mac_addr_dst_next == mac_addr_0 && src_port == 16'd0) ||
					(local_mac_addr_dst_next == mac_addr_1 && src_port == 16'd2) ||
					(local_mac_addr_dst_next == mac_addr_2 && src_port == 16'd4) ||
					(local_mac_addr_dst_next == mac_addr_3 && src_port == 16'd6) ||
					(local_broadcast_packet_next));
	end
	if(word_MAC_SRC_HI) begin
		local_mac_addr_src_next[47:32] = in_data[15:0];
	end
	if(word_MAC_SRC_LO) begin
		local_mac_addr_src_next[31:0] = in_data[DATA_WIDTH-1:DATA_WIDTH-32];
	end
	if(word_IP_SRC) begin
		local_ip_addr_src_next = in_data[DATA_WIDTH-16:16];
	end
	if(word_IP_DST_HI) begin
		local_ip_addr_dst_next[31:16] = in_data[15:0];
	end
	if(word_IP_DST_LO) begin
		local_ip_addr_dst_next[15:0] = in_data[DATA_WIDTH-1:DATA_WIDTH-16];
	end
	if(word_IP_TTL) begin
		local_ospf_packet_next = (in_data[7:0] == 8'd89);
	end
	if(word_ETHERTYPE) begin
		local_arp_packet_next = (in_data[31:16] == 16'h0806);
		local_ip_packet_next  = (in_data[31:16] == 16'h0800); //IPv4!
		local_bad_version_next = (in_data[15:12] != 4'd4);
		local_unknown_packet_next = (!local_arp_packet_next) && (!local_ip_packet_next);
	end
   end // always @ (*)

   always@(*) begin
      state_next = state;
      fifo_wr_en = 0;
      case(state)
        ST_PARSE: begin
	   if(word_LAST_USEFUL) begin
	      state_next = ST_WRITE;
	   end
        end

        ST_WRITE: begin
	      fifo_wr_en = 1;
	      state_next = ST_PARSE;
        end
      endcase // case(state)
   end // always@ (*)

   always @(posedge clk) begin
      if(reset) begin
		local_wrong_dest <= 0;
		local_cpu_packet <= 0;
		local_arp_packet <= 0;
		local_ip_packet  <= 0;
		local_ospf_packet  <= 0;
		local_unknown_packet <= 0;
		local_mac_addr_src <= 0;
		local_mac_addr_dst <= 0;
		local_ip_addr_src <= 0;
		local_ip_addr_dst <= 0;
                local_broadcast_packet <= 0;
		local_bad_version <= 0;
	        state <= ST_PARSE;
		src_port <= 0;
      end
      else begin
		local_wrong_dest <= local_wrong_dest_next;
		local_cpu_packet <= local_cpu_packet_next;
		local_arp_packet <= local_arp_packet_next;
		local_ip_packet  <= local_ip_packet_next;
		local_ospf_packet  <= local_ospf_packet_next;
		local_unknown_packet <= local_unknown_packet_next;
		local_mac_addr_src <= local_mac_addr_src_next;
		local_mac_addr_dst <= local_mac_addr_dst_next;
		local_ip_addr_src <= local_ip_addr_src_next;
		local_ip_addr_dst <= local_ip_addr_dst_next;
		local_broadcast_packet <= local_broadcast_packet_next;
		local_bad_version <= local_bad_version_next;
	        state <= state_next;
		src_port <= src_port_next;
      end
   end
endmodule // header_parser

  
