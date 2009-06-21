///////////////////////////////////////////////////////////////////////////////
//
// Module: ttl_checksum.v
// Description: provides packet information (ARP, IPv4) and addresses (MAC/IP)
//
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps
  module main_state_machine
    #(parameter DATA_WIDTH = 64,
      parameter CTRL_WIDTH = DATA_WIDTH/8,
      parameter UDP_REG_SRC_WIDTH = 2,
      parameter NUM_OUTPUT_QUEUES = 8
      )
   (// --- data path interface
    output        [DATA_WIDTH-1:0]        out_data,
    output        [CTRL_WIDTH-1:0]        out_ctrl,
    output                                out_wr,
    input                                 out_rdy,

    input  [DATA_WIDTH-1:0]               in_data,
    input  [CTRL_WIDTH-1:0]               in_ctrl,
    input                                 in_wr,
    output                                in_rdy,

    // --- Interface to scheduler
    input			       word_IOQ,
    input			       word_MAC_DST,
    input			       word_MAC_SRC_HI,
    input			       word_MAC_SRC_LO,
    input			       word_ETHERTYPE,
    input			       word_IP_TTL,
    input			       word_IP_VER,
    input			       word_IP_CHECKSUM,
    input			       word_IP_DST_HI,
    input			       word_IP_DST_LO,
    input			       word_IP_SRC,
    input			       word_LAST_USEFUL,

    // --- Interface to the header_parser
    input                              wrong_dest, //DROP the packet please!
    input                              cpu_packet,  //Packet from CPU. Just let it go!
    input                              ip_packet,   //Please check TTL and checksum before search.
    input                              arp_packet,  //An arp packet.
    input                              ospf_packet,  //An arp packet.
    input			       broadcast_packet,
    input                              unknown_packet,
    input			       bad_version,
    input   [47:0]                     mac_addr_src,
    input   [47:0]                     mac_addr_dst,
    input   [31:0]                     ip_addr_src,
    input   [31:0]                     ip_addr_dst,
    input                              header_parser_in_rdy,
    output reg                         header_parser_rd,
    input                              header_parser_vld,

    // --- Interface to ttl_checksum
    input                              bad_ttl,
    input                              bad_checksum,
    input [7:0]                        new_ttl,
    input [15:0]                       new_checksum,
    input                              ttl_checksum_in_rdy,
    output reg                         ttl_checksum_rd,
    input                              ttl_checksum_vld,

      //Counters
    output reg				cntr_arp_misses,
    output reg				cntr_lpm_misses,
    output reg				cntr_cpu_pkts_sent,
    output reg				cntr_bad_opts_ver,
    output reg				cntr_bad_chksums,
    output reg				cntr_bad_ttls,
    output reg				cntr_non_ip_rcvd,
    output reg				cntr_pkts_forwarded,
    output reg				cntr_wrong_dest,
    output reg				cntr_filtered_pkts,
    output reg				cntr_arp_pkts,
    output reg				cntr_ospf_pkts,
    output reg				cntr_ip_pkts,


    // --- Interface to the dest ip filter
    output reg				ip_filter_req,
    input				ip_filter_done,
    output reg [31:0] 			ip_filter_search_ip,
    input	      			ip_filter_found,

    // --- Interface to the arp_lookup
    output reg				arp_lookup_req,
    input				arp_lookup_done,
    output reg [31:0] 			arp_lookup_search_ip,
    input  [47:0]      			arp_lookup_result_mac,

    // --- Interface to the arp_lookup
    output reg				lpm_lookup_req,
    input				lpm_lookup_done,
    output reg [31:0] 			lpm_lookup_search_ip,
    input  [31:0]      			lpm_lookup_nexthop_ip,
    input  [15:0]      			lpm_lookup_port,

    // --- Interface to registers
    input  [47:0]                      mac_addr_0,
    input  [47:0]                      mac_addr_1,
    input  [47:0]                      mac_addr_2,
    input  [47:0]                      mac_addr_3,

    // --- Misc   
    input                              	reset,
    input                               clk
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
   parameter NUM_STATES		                    = 14;
   parameter ST_IDLE	                            = 14'd1;
   parameter ST_SEND_PACKET                         = 14'd2;
   parameter ST_DROP_PACKET                         = 14'd4;
   parameter ST_DST_IP_SEARCH	                    = 14'd8;
   parameter ST_LPM_SEARCH	                    = 14'd16;
   parameter ST_ARP_SEARCH	                    = 14'd32;
   parameter ST_FROM_CPU			    = 14'd64;
   parameter ST_TO_CPU				    = 14'd128;
   parameter ST_FORWARD_IOQ			    = 14'd256;
   parameter ST_FORWARD_MAC			    = 14'd512;
   parameter ST_FORWARD_ETHERTYPE		    = 14'd1024;
   parameter ST_FORWARD_TTL			    = 14'd2048;
   parameter ST_FORWARD_CHECKSUM		    = 14'd4096;
   parameter ST_IOQ_HEADER			    = 14'd8192;

   //---------------------- Wires/Regs -------------------------------
   reg					fifo_rd_en;
   wire					fifo_empty;
   wire					fifo_almost_full;
   wire [DATA_WIDTH-1:0]		fifo_out_data;
   wire [CTRL_WIDTH-1:0]		fifo_out_ctrl;
   reg [DATA_WIDTH/4-1:0]           	decoded_src;
   reg [NUM_STATES-1:0]			state, state_next;

   reg	[15:0]				dst_port;
   reg  [31:0]				nexthop_ip, nexthop_ip_next;
   reg	[47:0]				dst_mac;
   wire [47:0]				src_mac;

   reg [DATA_WIDTH-1:0]			output_fifo_in_data;

   reg					output_fifo_wr_en;
   wire					output_fifo_empty;
   wire					output_fifo_nearly_full;

   //----------------------- Modules ---------------------------------
   sync_128x72_fifo
      input_fifo
        (.din ({in_ctrl, in_data}),
         .wr_en (in_wr),
         .rd_en (fifo_rd_en),
         .dout ({fifo_out_ctrl, fifo_out_data}),
         .full (),
         .almost_full (fifo_almost_full),
         .empty (fifo_empty),
         .rst (reset),
         .clk (clk)
         );

   sync_128x72_fifo
      output_fifo
        (.din ({fifo_out_ctrl, output_fifo_in_data}),
         .wr_en (output_fifo_wr_en),
         .rd_en (out_wr),
         .dout ({out_ctrl, out_data}),
         .full (),
         .almost_full (output_fifo_nearly_full),
         .empty (output_fifo_empty),
         .rst (reset),
         .clk (clk)
         );
       
   //------------------------ Logic ----------------------------------
   /* handle outputs */
   assign out_wr = out_rdy && !output_fifo_empty;


   assign in_rdy = !fifo_almost_full && ttl_checksum_in_rdy && header_parser_in_rdy;
   assign src_mac = (dst_port == 16'h01) ? mac_addr_0 :
		    (dst_port == 16'h04) ? mac_addr_1 :
		    (dst_port == 16'h10) ? mac_addr_2 :
		    (dst_port == 16'h40) ? mac_addr_3 :
						    0 ;

   always @(*) begin

      state_next        = state; 
      header_parser_rd	= 0;
      ttl_checksum_rd	= 0;
      fifo_rd_en	= 0;

      cntr_arp_misses	= 0;
      cntr_lpm_misses	= 0;
      cntr_cpu_pkts_sent	= 0;
      cntr_bad_opts_ver	= 0;
      cntr_bad_chksums	= 0;
      cntr_bad_ttls	= 0;
      cntr_non_ip_rcvd	= 0;
      cntr_pkts_forwarded	= 0;
      cntr_wrong_dest	= 0;
      cntr_filtered_pkts	= 0;
      cntr_arp_pkts	= 0;
      cntr_ospf_pkts	= 0;
      cntr_ip_pkts	= 0;

      output_fifo_in_data = fifo_out_data;
      output_fifo_wr_en   = 0;

      decoded_src = 0;

      ip_filter_search_ip = ip_addr_dst;
      ip_filter_req = 0;
      lpm_lookup_search_ip = ip_addr_dst;
      lpm_lookup_req = 0;
      arp_lookup_search_ip = nexthop_ip;
      arp_lookup_req = 0;

      dst_mac = arp_lookup_result_mac;
      dst_port = lpm_lookup_port;
      nexthop_ip_next = nexthop_ip;

      case(state)
	 ST_IDLE: begin
	    if(header_parser_vld && ttl_checksum_vld && fifo_out_ctrl==`IO_QUEUE_STAGE_NUM) begin
		state_next = ST_IOQ_HEADER;
	    end
         end
         ST_IOQ_HEADER: begin
		//Send Packet to MAC without modification
		if(cpu_packet) begin
			cntr_cpu_pkts_sent = 1;
			state_next = ST_FROM_CPU;
		end
		//Drop the Packet
		else if(wrong_dest) begin
			cntr_wrong_dest	= 1;
			state_next = ST_DROP_PACKET;
			header_parser_rd = 1;
			ttl_checksum_rd = 1;
		end
		//Send Packet to CPU without modification
		else if((unknown_packet || arp_packet)) begin
			cntr_non_ip_rcvd = unknown_packet || arp_packet;
			cntr_arp_pkts = arp_packet;
			state_next = ST_TO_CPU;
		end
		//Send Packet to CPU without modification
		else if(ip_packet && (bad_ttl || bad_checksum || bad_version)) begin
			cntr_bad_chksums = bad_checksum;
			cntr_bad_ttls = bad_ttl;
      			cntr_ip_pkts	= 1;
			cntr_bad_opts_ver = bad_version;
			state_next = ST_TO_CPU;
		end
		else if(ip_packet) begin
      			cntr_ip_pkts	= 1;
			state_next = ST_DST_IP_SEARCH;
		end
		else
			state_next = ST_TO_CPU;	    
         end // case: ST_IOQ_HEADER

         ST_TO_CPU: begin
	    output_fifo_in_data = fifo_out_data;
            decoded_src[fifo_out_data[`IOQ_SRC_PORT_POS+15:`IOQ_SRC_PORT_POS]] = 1'b1;
	    output_fifo_in_data[`IOQ_DST_PORT_POS+15:`IOQ_DST_PORT_POS] = {decoded_src[14:0], 1'b0};
	    if(!fifo_empty && !output_fifo_nearly_full) begin
	    	fifo_rd_en = 1;
	    	output_fifo_wr_en = 1;
	    	state_next = ST_SEND_PACKET;
	    	header_parser_rd = 1;
	    	ttl_checksum_rd = 1;
	    end
         end // case: ST_FROM_CPU

         ST_FROM_CPU: begin
	    output_fifo_in_data = fifo_out_data;
            decoded_src = 0;
            decoded_src[fifo_out_data[`IOQ_SRC_PORT_POS+15:`IOQ_SRC_PORT_POS]] = 1'b1;
	    output_fifo_in_data[`IOQ_DST_PORT_POS+15:`IOQ_DST_PORT_POS] = {1'b0, decoded_src[15:1]};
	    if(!fifo_empty && !output_fifo_nearly_full) begin
	    	fifo_rd_en = 1;
	    	output_fifo_wr_en = 1;
	    	state_next = ST_SEND_PACKET;
	    	header_parser_rd = 1;
	    	ttl_checksum_rd = 1;
	    end
         end // case: ST_FROM_CPU

         ST_DST_IP_SEARCH: begin
	    ip_filter_req = 1;
	    ip_filter_search_ip = ip_addr_dst;
	    if(ip_filter_done) begin
		ip_filter_req = 0;
		if(ip_filter_found) begin
			cntr_filtered_pkts = 1;
			state_next = ST_TO_CPU;
		end
		else if(broadcast_packet) begin
			cntr_wrong_dest = 1;
			state_next = ST_DROP_PACKET;
	    		header_parser_rd = 1;
	    		ttl_checksum_rd = 1;
		end
		else begin
			state_next = ST_LPM_SEARCH;
		end
	    end
         end // case: ST_DST_IP_SEARCH

         ST_LPM_SEARCH: begin
	    lpm_lookup_req = 1;
	    lpm_lookup_search_ip = ip_addr_dst;
	    if(lpm_lookup_done) begin
		lpm_lookup_req = 0;
		if(lpm_lookup_nexthop_ip == 32'hffffffff || lpm_lookup_port == 16'b0) begin
			cntr_lpm_misses = 1;
			state_next = ST_TO_CPU;
		end
		else if(lpm_lookup_nexthop_ip == 32'b0) begin
			dst_port = lpm_lookup_port;
			nexthop_ip_next = lpm_lookup_search_ip;
			state_next = ST_ARP_SEARCH;
		end
		else begin
			dst_port = lpm_lookup_port;
			nexthop_ip_next = lpm_lookup_nexthop_ip;
			state_next = ST_ARP_SEARCH;
		end
	    end
         end // case: ST_LPM_SEARCH

         ST_ARP_SEARCH: begin
	    arp_lookup_req = 1;
	    arp_lookup_search_ip = nexthop_ip;
	    if(arp_lookup_done) begin
		arp_lookup_req = 0;
		if(arp_lookup_result_mac == 48'b0) begin
			cntr_arp_misses = 1;
			state_next = ST_TO_CPU;
		end
		else begin
			dst_mac = arp_lookup_result_mac;
			state_next = ST_FORWARD_IOQ;
		end
	    end
         end // case: ST_ARP_SEARCH

         ST_FORWARD_IOQ: begin
	    output_fifo_in_data = fifo_out_data;
	    output_fifo_in_data[`IOQ_DST_PORT_POS+15:`IOQ_DST_PORT_POS] = dst_port;
	    if(!fifo_empty && !output_fifo_nearly_full) begin
	    	fifo_rd_en = 1;
	    	output_fifo_wr_en = 1;
	    	cntr_pkts_forwarded	= 1;
	    	header_parser_rd = 1;
	    	ttl_checksum_rd = 1;
	    	state_next = ST_FORWARD_MAC;
	    end
         end // case: ST_FORWARD_IOQ

         ST_FORWARD_MAC: begin
	    output_fifo_in_data = fifo_out_data;
	    output_fifo_in_data[63:16] = dst_mac;
	    output_fifo_in_data[15:0] = src_mac[47:32];
	    if(!fifo_empty && !output_fifo_nearly_full) begin
	    	fifo_rd_en = 1;
	    	output_fifo_wr_en = 1;
	    	state_next = ST_FORWARD_ETHERTYPE;
	    end
         end // case: ST_FORWARD_MAC

         ST_FORWARD_ETHERTYPE: begin
	    output_fifo_in_data = fifo_out_data;
	    output_fifo_in_data[63:32] = src_mac[31:0];
	    if(!fifo_empty && !output_fifo_nearly_full) begin
	    	fifo_rd_en = 1;
	    	output_fifo_wr_en = 1;
	    	state_next = ST_FORWARD_TTL;
	    end
         end // case: ST_FORWARD_ETHERTYPE

         ST_FORWARD_TTL: begin
	    output_fifo_in_data = fifo_out_data;
	    output_fifo_in_data[15:8] = new_ttl;
	    if(!fifo_empty && !output_fifo_nearly_full) begin
	    	fifo_rd_en = 1;
	    	output_fifo_wr_en = 1;
	    	state_next = ST_FORWARD_CHECKSUM;
	    end
         end // case: ST_FORWARD_TTL

         ST_FORWARD_CHECKSUM: begin
	    output_fifo_in_data = fifo_out_data;
	    output_fifo_in_data[63:48] = new_checksum;
	    if(!fifo_empty && !output_fifo_nearly_full) begin
	    	fifo_rd_en = 1;
	    	output_fifo_wr_en = 1;
	    	state_next = ST_SEND_PACKET;
	    end
         end // case: ST_FORWARD_CHECKSUM

         ST_SEND_PACKET: begin
	    output_fifo_in_data = fifo_out_data;
	    if(!fifo_empty && !output_fifo_nearly_full) begin
	       output_fifo_wr_en = 1;
	       fifo_rd_en = 1;
               if(fifo_out_ctrl!=0 && fifo_out_ctrl!=`IO_QUEUE_STAGE_NUM) begin //Reached the end of packet.
               	   state_next = ST_IDLE;
               end
	    end
         end // case: ST_SEND_PACKET

         ST_DROP_PACKET: begin
	    if(!fifo_empty) begin	//Drop the packet!
	       fifo_rd_en = 1;
               if(fifo_out_ctrl!=0 && fifo_out_ctrl!=`IO_QUEUE_STAGE_NUM) begin //Reached the end of packet.
               	   state_next = ST_IDLE;
               end
	    end
         end // case: ST_DROP_PACKET

      endcase // case(state)
   end // always @ (*)

   always @(posedge clk) begin
      if(reset) begin
	 nexthop_ip <= 0;
         state <= ST_IDLE;
      end
      else begin
	 nexthop_ip <= nexthop_ip_next;
         state <= state_next;
      end
   end
endmodule // main_state_machine
