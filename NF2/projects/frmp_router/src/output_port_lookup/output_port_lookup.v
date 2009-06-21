///////////////////////////////////////////////////////////////////////////////
// vim:set shiftwidth=3 softtabstop=3 expandtab:
// $Id: output_port_lookup.v 45 2009-06-10 05:56:12Z hyzeng $
//
// Module: output_port_lookup.v
// Project: CS344 starter code
//
// Description: Acts as a "wire" connected as follows:
//
//   Ethernet port 0   <-->   Ethernet port 1
//   Ethernet port 2   <-->   Ethernet port 3
//
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps
  module output_port_lookup
    #(parameter DATA_WIDTH = 64,
      parameter CTRL_WIDTH = DATA_WIDTH/8,
      parameter UDP_REG_SRC_WIDTH = 2,
      parameter INPUT_ARBITER_STAGE_NUM = 2,
      parameter IO_QUEUE_STAGE_NUM = `IO_QUEUE_STAGE_NUM,
      parameter NUM_OUTPUT_QUEUES = 8,
      parameter NUM_IQ_BITS = 3,
      parameter STAGE_NUM = 4,
      parameter CPU_QUEUE_NUM = 0)

   (// --- data path interface
    output     [DATA_WIDTH-1:0]           out_data,
    output     [CTRL_WIDTH-1:0]           out_ctrl,
    output	                          out_wr,
    input                                 out_rdy,

    input  [DATA_WIDTH-1:0]               in_data,
    input  [CTRL_WIDTH-1:0]               in_ctrl,
    input                                 in_wr,
    output                                in_rdy,


    // For Fast Reroute
    input  [(NUM_OUTPUT_QUEUES) - 1:0]	eth_link_status,

    // --- Register interface
    input                                 reg_req_in,
    input                                 reg_ack_in,
    input                                 reg_rd_wr_L_in,
    input  [`UDP_REG_ADDR_WIDTH-1:0]      reg_addr_in,
    input  [`CPCI_NF2_DATA_WIDTH-1:0]     reg_data_in,
    input  [UDP_REG_SRC_WIDTH-1:0]        reg_src_in,

    output                            	reg_req_out,
    output                            	reg_ack_out,
    output                            	reg_rd_wr_L_out,
    output [`UDP_REG_ADDR_WIDTH-1:0]  	reg_addr_out,
    output [`CPCI_NF2_DATA_WIDTH-1:0] 	reg_data_out,
    output [UDP_REG_SRC_WIDTH-1:0]    	reg_src_out,

    // --- Misc
    input                                 clk,
    input                                 reset);

   function integer log2;
      input integer number;
      begin
         log2=0;
         while(2**log2<number) begin
            log2=log2+1;
         end
      end
   endfunction // log2
   
   //--------------------- Internal Parameter-------------------------

   //---------------------- Wires/Regs -------------------------------
   wire 			word_IOQ;
   wire 			word_MAC_DST;
   wire 			word_MAC_SRC_HI;
   wire 			word_MAC_SRC_LO;
   wire 			word_ETHERTYPE;
   wire 			word_IP_TTL;
   wire 			word_IP_VER;
   wire 			word_IP_CHECKSUM;
   wire 			word_IP_DST_HI;
   wire 			word_IP_DST_LO;
   wire 			word_IP_SRC;
   wire 			word_LAST_USEFUL;

   wire 			wrong_dest;
   wire 			cpu_packet;
   wire 			ip_packet;
   wire 			arp_packet;
   wire 			ospf_packet;
   wire 			unknown_packet;
   wire 			broadcast_packet;
   wire				bad_version;

   wire [47:0]			mac_addr_src;
   wire [47:0]			mac_addr_dst;

   wire [31:0]			ip_addr_src;
   wire [31:0]			ip_addr_dst;

   wire 			header_parser_in_rdy;
   wire 			header_parser_rd;
   wire 			header_parser_vld;

   wire 			bad_ttl;
   wire 			bad_checksum;
   wire [7:0]			new_ttl;
   wire [15:0]			new_checksum;
   wire 			ttl_checksum_in_rdy;
   wire 			ttl_checksum_rd;
   wire 			ttl_checksum_vld;

   wire [47:0] 			mac_addr_0;
   wire [47:0] 			mac_addr_1;
   wire [47:0] 			mac_addr_2;
   wire [47:0] 			mac_addr_3;
   wire				fast_reroute_enable;
   wire				multipath_enable;

   wire 			cntr_arp_misses;
   wire 			cntr_lpm_misses;
   wire 			cntr_cpu_pkts_sent;
   wire 			cntr_bad_opts_ver;
   wire 			cntr_bad_chksums;
   wire 			cntr_bad_ttls;
   wire 			cntr_non_ip_rcvd;
   wire 			cntr_pkts_forwarded;
   wire 			cntr_wrong_dest;
   wire 			cntr_filtered_pkts;
   wire 			cntr_arp_pkts;
   wire 			cntr_ospf_pkts;
   wire 			cntr_ip_pkts;


   //IP filter table
   // --- Interface to registers
    wire                               	ip_filter_table_rd_req;
    wire                          	ip_filter_table_rd_ack;
    wire    [4:0]                      	ip_filter_table_rd_addr;
    wire [31:0]                   	ip_filter_table_rd_data;
    wire                               	ip_filter_table_wr_req;
    wire                          	ip_filter_table_wr_ack;
    wire    [4:0]                      	ip_filter_table_wr_addr;
    wire      [31:0]                   	ip_filter_table_wr_data;

   // --- Interface to the main state machine
   wire				     ip_filter_req;
   wire				     ip_filter_done;
   wire  [31:0] 		     ip_filter_search_ip;
   wire     			     ip_filter_found;			     

   //Gateway table
   // --- Interface to registers
    wire                               	gateway_table_rd_req;
    wire                          	gateway_table_rd_ack;
    wire    [4:0]                      	gateway_table_rd_addr;
    wire [31:0]                   	gateway_table_rd_data;
    wire                               	gateway_table_wr_req;
    wire                          	gateway_table_wr_ack;
    wire    [4:0]                      	gateway_table_wr_addr;
    wire      [31:0]                   	gateway_table_wr_data;

   //ARP table
   // --- Interface to registers
    wire                               	arp_table_rd_req;
    wire                          	arp_table_rd_ack;
    wire    [4:0]                      	arp_table_rd_addr;
    wire [95:0]                  	arp_table_rd_data;
    wire                               	arp_table_wr_req;
    wire                          	arp_table_wr_ack;
    wire    [4:0]                      	arp_table_wr_addr;
    wire      [95:0]                  	arp_table_wr_data;
   // --- Interface to the main state machine
   wire				     arp_lookup_req;
   wire				     arp_lookup_done;
   wire  [31:0] 		     arp_lookup_search_ip;
   wire  [47:0]   	 	     arp_lookup_result_mac;

   //Route table
   // --- Interface to registers
    wire                               	route_table_rd_req;
    wire                          	route_table_rd_ack;
    wire    [5:0]                      	route_table_rd_addr;
    wire [127:0]                  	route_table_rd_data;
    wire                               	route_table_wr_req;
    wire                          	route_table_wr_ack;
    wire    [5:0]                      	route_table_wr_addr;
    wire      [127:0]                  	route_table_wr_data;

   // --- Interface to the main state machine
   wire				     lpm_lookup_req;
   wire				     lpm_lookup_done;
   wire  [31:0] 		     lpm_lookup_search_ip;
   wire  [31:0] 		     lpm_lookup_nexthop_ip;
   wire  [15:0]   	 	     lpm_lookup_port;

   //----------------------- Modules ---------------------------------
  scheduler
    #(.DATA_WIDTH(DATA_WIDTH),
      .CTRL_WIDTH(CTRL_WIDTH)
      ) scheduler
   (
    // --- Interface to the previous module
    .in_data			(in_data),
    .in_ctrl			(in_ctrl),
    .in_wr			(in_wr),

    // position information for other modules
    .word_IOQ			(word_IOQ),
    .word_MAC_DST		(word_MAC_DST),
    .word_MAC_SRC_HI		(word_MAC_SRC_HI),
    .word_MAC_SRC_LO		(word_MAC_SRC_LO),
    .word_ETHERTYPE		(word_ETHERTYPE),
    .word_IP_TTL		(word_IP_TTL),
    .word_IP_VER		(word_IP_VER),
    .word_IP_CHECKSUM		(word_IP_CHECKSUM),
    .word_IP_DST_HI		(word_IP_DST_HI),
    .word_IP_DST_LO		(word_IP_DST_LO),
    .word_IP_SRC		(word_IP_SRC),
    .word_LAST_USEFUL		(word_LAST_USEFUL),

    // --- Misc
    .reset			(reset),
    .clk			(clk)
   );

   header_parser
    #(.DATA_WIDTH(DATA_WIDTH),
      .NUM_QUEUES(NUM_OUTPUT_QUEUES)
      ) header_parser
   (// --- Interface to the previous module
    .in_data			(in_data),

    // --- Interface to the main state machine
    .wrong_dest			(wrong_dest),
    .cpu_packet			(cpu_packet),
    .ip_packet			(ip_packet),
    .arp_packet			(arp_packet),
    .unknown_packet		(unknown_packet),
    .broadcast_packet		(broadcast_packet),
    .ospf_packet		(ospf_packet),
    .bad_version		(bad_version),

    .mac_addr_src		(mac_addr_src),
    .mac_addr_dst		(mac_addr_dst),

    .ip_addr_src		(ip_addr_src),
    .ip_addr_dst		(ip_addr_dst),

    .header_parser_in_rdy	(header_parser_in_rdy),
    .header_parser_rd		(header_parser_rd),
    .header_parser_vld		(header_parser_vld),

    // --- Interface to scheduler
    .word_IOQ			(word_IOQ),
    .word_MAC_DST		(word_MAC_DST),
    .word_MAC_SRC_HI		(word_MAC_SRC_HI),
    .word_MAC_SRC_LO		(word_MAC_SRC_LO),
    .word_ETHERTYPE		(word_ETHERTYPE),
    .word_IP_DST_HI		(word_IP_DST_HI),
    .word_IP_DST_LO		(word_IP_DST_LO),
    .word_IP_SRC		(word_IP_SRC),
    .word_IP_TTL		(word_IP_TTL),
    .word_LAST_USEFUL		(word_LAST_USEFUL),

    // --- Interface to registers
    .mac_addr_0			(mac_addr_0),
    .mac_addr_1			(mac_addr_1),
    .mac_addr_2			(mac_addr_2),
    .mac_addr_3			(mac_addr_3),

    // --- Misc   
    .reset			(reset),
    .clk			(clk)
   );

   ttl_checksum
    #(.DATA_WIDTH(DATA_WIDTH)
      ) ttl_checksum
   (// --- Interface to the previous module
    .in_data			(in_data),

    // --- Interface to the main state machine
    .bad_ttl			(bad_ttl),
    .bad_checksum		(bad_checksum),
    .new_ttl			(new_ttl),
    .new_checksum		(new_checksum),
    .ttl_checksum_in_rdy	(ttl_checksum_in_rdy),
    .ttl_checksum_rd		(ttl_checksum_rd),
    .ttl_checksum_vld		(ttl_checksum_vld),

    // --- Interface to scheduler
    .word_IOQ			(word_IOQ),
    .word_MAC_DST		(word_MAC_DST),
    .word_MAC_SRC_HI		(word_MAC_SRC_HI),
    .word_MAC_SRC_LO		(word_MAC_SRC_LO),
    .word_ETHERTYPE		(word_ETHERTYPE),
    .word_IP_DST_HI		(word_IP_DST_HI),
    .word_IP_DST_LO		(word_IP_DST_LO),
    .word_IP_SRC		(word_IP_SRC),
    .word_IP_TTL		(word_IP_TTL),
    .word_LAST_USEFUL		(word_LAST_USEFUL),
    .word_IP_CHECKSUM		(word_IP_CHECKSUM),

    // --- Misc   
    .reset			(reset),
    .clk			(clk)
   );

  main_state_machine
    #(.DATA_WIDTH(DATA_WIDTH),
      .CTRL_WIDTH(CTRL_WIDTH),
      .UDP_REG_SRC_WIDTH(UDP_REG_SRC_WIDTH),
      .NUM_OUTPUT_QUEUES(NUM_OUTPUT_QUEUES)
      )  main_state_machine
   (// --- data path interface
    .out_data			(out_data),
    .out_ctrl			(out_ctrl),
    .out_wr			(out_wr),
    .out_rdy			(out_rdy),

    .in_data			(in_data),
    .in_ctrl			(in_ctrl),
    .in_wr			(in_wr),
    .in_rdy			(in_rdy),

    // --- Interface to scheduler
    .word_IOQ			(word_IOQ),
    .word_MAC_DST		(word_MAC_DST),
    .word_MAC_SRC_HI		(word_MAC_SRC_HI),
    .word_MAC_SRC_LO		(word_MAC_SRC_LO),
    .word_ETHERTYPE		(word_ETHERTYPE),
    .word_IP_TTL		(word_IP_TTL),
    .word_IP_VER		(word_IP_VER),
    .word_IP_CHECKSUM		(word_IP_CHECKSUM),
    .word_IP_DST_HI		(word_IP_DST_HI),
    .word_IP_DST_LO		(word_IP_DST_LO),
    .word_IP_SRC		(word_IP_SRC),
    .word_LAST_USEFUL		(word_LAST_USEFUL),

    // --- Interface to the header_parser
    .wrong_dest			(wrong_dest),
    .cpu_packet			(cpu_packet),
    .ip_packet			(ip_packet),
    .arp_packet			(arp_packet),
    .ospf_packet		(ospf_packet),
    .unknown_packet		(unknown_packet),
    .broadcast_packet		(broadcast_packet),
    .bad_version		(bad_version),

    .mac_addr_src		(mac_addr_src),
    .mac_addr_dst		(mac_addr_dst),

    .ip_addr_src		(ip_addr_src),
    .ip_addr_dst		(ip_addr_dst),

    .header_parser_in_rdy	(header_parser_in_rdy),
    .header_parser_rd		(header_parser_rd),
    .header_parser_vld		(header_parser_vld),

     .mac_addr_0	(mac_addr_0),
     .mac_addr_1	(mac_addr_1),
     .mac_addr_2	(mac_addr_2),
     .mac_addr_3	(mac_addr_3),

    // --- Interface to ttl_checksum
    .bad_ttl			(bad_ttl),
    .bad_checksum		(bad_checksum),
    .new_ttl			(new_ttl),
    .new_checksum		(new_checksum),
    .ttl_checksum_in_rdy	(ttl_checksum_in_rdy),
    .ttl_checksum_rd		(ttl_checksum_rd),
    .ttl_checksum_vld		(ttl_checksum_vld),

      //Counters
    .cntr_arp_misses		(cntr_arp_misses),
    .cntr_lpm_misses		(cntr_lpm_misses),
    .cntr_cpu_pkts_sent		(cntr_cpu_pkts_sent),
    .cntr_bad_opts_ver		(cntr_bad_opts_ver),
    .cntr_bad_chksums		(cntr_bad_chksums),
    .cntr_bad_ttls		(cntr_bad_ttls),
    .cntr_non_ip_rcvd		(cntr_non_ip_rcvd),
    .cntr_pkts_forwarded	(cntr_pkts_forwarded),
    .cntr_wrong_dest		(cntr_wrong_dest),
    .cntr_filtered_pkts		(cntr_filtered_pkts),
    .cntr_arp_pkts		(cntr_arp_pkts),
    .cntr_ospf_pkts		(cntr_ospf_pkts),
    .cntr_ip_pkts		(cntr_ip_pkts),

    // --- Interface to ip_filter
    .ip_filter_req		(ip_filter_req),
    .ip_filter_done		(ip_filter_done),
    .ip_filter_search_ip	(ip_filter_search_ip),
    .ip_filter_found		(ip_filter_found),

    // --- Interface to arp_lookup
    .arp_lookup_req		(arp_lookup_req),
    .arp_lookup_done		(arp_lookup_done),
    .arp_lookup_search_ip	(arp_lookup_search_ip),
    .arp_lookup_result_mac	(arp_lookup_result_mac),

    // --- Interface to lpm_lookup
    .lpm_lookup_req		(lpm_lookup_req),
    .lpm_lookup_done		(lpm_lookup_done),
    .lpm_lookup_search_ip	(lpm_lookup_search_ip),
    .lpm_lookup_nexthop_ip	(lpm_lookup_nexthop_ip),
    .lpm_lookup_port		(lpm_lookup_port),

    // --- Misc   
    .reset			(reset),
    .clk			(clk)
   );

 ip_filter ip_filter
 (
    // --- Interface to the main state machine
    .ip_filter_req		(ip_filter_req),
    .ip_filter_done		(ip_filter_done),
    .search_ip			(ip_filter_search_ip),
    .found			(ip_filter_found),

    // --- Interface to registers
      .table_rd_addr    (ip_filter_table_rd_addr),
      .table_rd_data    (ip_filter_table_rd_data),
      .table_rd_req     (ip_filter_table_rd_req),
      .table_rd_ack     (ip_filter_table_rd_ack),
      .table_wr_addr    (ip_filter_table_wr_addr),
      .table_wr_data    (ip_filter_table_wr_data),
      .table_wr_req     (ip_filter_table_wr_req),
      .table_wr_ack     (ip_filter_table_wr_ack),

    // --- Misc   
    .reset			(reset),
    .clk			(clk)
 );

 arp_lookup arp_lookup
 (
    // --- Interface to the main state machine
    .arp_lookup_req		(arp_lookup_req),
    .arp_lookup_done		(arp_lookup_done),
    .search_ip			(arp_lookup_search_ip),
    .result_mac			(arp_lookup_result_mac),

    // --- Interface to registers
      .table_rd_addr    (arp_table_rd_addr),
      .table_rd_data    (arp_table_rd_data),
      .table_rd_req     (arp_table_rd_req),
      .table_rd_ack     (arp_table_rd_ack),
      .table_wr_addr    (arp_table_wr_addr),
      .table_wr_data    (arp_table_wr_data),
      .table_wr_req     (arp_table_wr_req),
      .table_wr_ack     (arp_table_wr_ack),


    // --- Misc   
    .reset			(reset),
    .clk			(clk)
 );

 lpm_lookup lpm_lookup
 (
    // --- Interface to the main state machine
    .lpm_lookup_req		(lpm_lookup_req),
    .lpm_lookup_done		(lpm_lookup_done),
    .search_ip			(lpm_lookup_search_ip),
    .nexthop_ip			(lpm_lookup_nexthop_ip),
    .port			(lpm_lookup_port),


    // For fast reroute
    .eth_link_status	   (eth_link_status),
    .fast_reroute_enable   (fast_reroute_enable),
    .multipath_enable	   (multipath_enable),

    // --- Interface to registers
      .table_rd_addr    (route_table_rd_addr),
      .table_rd_data    (route_table_rd_data),
      .table_rd_req     (route_table_rd_req),
      .table_rd_ack     (route_table_rd_ack),
      .table_wr_addr    (route_table_wr_addr),
      .table_wr_data    (route_table_wr_data),
      .table_wr_req     (route_table_wr_req),
      .table_wr_ack     (route_table_wr_ack),

    // --- Interface to registers
      .gateway_table_rd_addr    (gateway_table_rd_addr),
      .gateway_table_rd_data    (gateway_table_rd_data),
      .gateway_table_rd_req     (gateway_table_rd_req),
      .gateway_table_rd_ack     (gateway_table_rd_ack),
      .gateway_table_wr_addr    (gateway_table_wr_addr),
      .gateway_table_wr_data    (gateway_table_wr_data),
      .gateway_table_wr_req     (gateway_table_wr_req),
      .gateway_table_wr_ack     (gateway_table_wr_ack),

    // --- Misc   
    .reset			(reset),
    .clk			(clk)
 );

   output_port_lookup_regs
   #( 
       .UDP_REG_SRC_WIDTH(UDP_REG_SRC_WIDTH)
   )   output_port_lookup_regs
   (
    // --- Register interface
    .reg_req_in       (reg_req_in),
    .reg_ack_in       (reg_ack_in),
    .reg_rd_wr_L_in   (reg_rd_wr_L_in),
    .reg_addr_in      (reg_addr_in),
    .reg_data_in      (reg_data_in),
    .reg_src_in       (reg_src_in),

    .reg_req_out      (reg_req_out),
    .reg_ack_out      (reg_ack_out),
    .reg_rd_wr_L_out  (reg_rd_wr_L_out),
    .reg_addr_out     (reg_addr_out),
    .reg_data_out     (reg_data_out),
    .reg_src_out      (reg_src_out),

      //Counters
    .arp_misses		(cntr_arp_misses),
    .lpm_misses		(cntr_lpm_misses),
    .cpu_pkts_sent	(cntr_cpu_pkts_sent),
    .bad_opts_ver	(cntr_bad_opts_ver),
    .bad_chksums	(cntr_bad_chksums),
    .bad_ttls		(cntr_bad_ttls),
    .non_ip_rcvd	(cntr_non_ip_rcvd),
    .pkts_forwarded	(cntr_pkts_forwarded),
    .wrong_dest		(cntr_wrong_dest),
    .filtered_pkts	(cntr_filtered_pkts),
    .arp_pkts		(cntr_arp_pkts),
    .ospf_pkts		(cntr_ospf_pkts),
    .ip_pkts		(cntr_ip_pkts),

     .mac_addr_0	(mac_addr_0),
     .mac_addr_1	(mac_addr_1),
     .mac_addr_2	(mac_addr_2),
     .mac_addr_3	(mac_addr_3),
     .fast_reroute_enable	(fast_reroute_enable),
     .multipath_enable		(multipath_enable),

    .link_status	   (eth_link_status),

      //IP filter table
      .ip_filter_table_rd_addr    (ip_filter_table_rd_addr),
      .ip_filter_table_rd_data    (ip_filter_table_rd_data),
      .ip_filter_table_rd_req     (ip_filter_table_rd_req),
      .ip_filter_table_rd_ack     (ip_filter_table_rd_ack),
      .ip_filter_table_wr_addr    (ip_filter_table_wr_addr),
      .ip_filter_table_wr_data    (ip_filter_table_wr_data),
      .ip_filter_table_wr_req     (ip_filter_table_wr_req),
      .ip_filter_table_wr_ack     (ip_filter_table_wr_ack),	

      //IP filter table
      .gateway_table_rd_addr    (gateway_table_rd_addr),
      .gateway_table_rd_data    (gateway_table_rd_data),
      .gateway_table_rd_req     (gateway_table_rd_req),
      .gateway_table_rd_ack     (gateway_table_rd_ack),
      .gateway_table_wr_addr    (gateway_table_wr_addr),
      .gateway_table_wr_data    (gateway_table_wr_data),
      .gateway_table_wr_req     (gateway_table_wr_req),
      .gateway_table_wr_ack     (gateway_table_wr_ack),			     

      //ARP table
      .arp_table_rd_addr    (arp_table_rd_addr),
      .arp_table_rd_data    (arp_table_rd_data),
      .arp_table_rd_req     (arp_table_rd_req),
      .arp_table_rd_ack     (arp_table_rd_ack),
      .arp_table_wr_addr    (arp_table_wr_addr),
      .arp_table_wr_data    (arp_table_wr_data),
      .arp_table_wr_req     (arp_table_wr_req),
      .arp_table_wr_ack     (arp_table_wr_ack),

      //Route table
      .route_table_rd_addr    (route_table_rd_addr),
      .route_table_rd_data    (route_table_rd_data),
      .route_table_rd_req     (route_table_rd_req),
      .route_table_rd_ack     (route_table_rd_ack),
      .route_table_wr_addr    (route_table_wr_addr),
      .route_table_wr_data    (route_table_wr_data),
      .route_table_wr_req     (route_table_wr_req),
      .route_table_wr_ack     (route_table_wr_ack),
   			     

    // --- Misc   
    .reset			(reset),
    .clk			(clk)
    );

   //----------------------- Logic ---------------------------------

endmodule
