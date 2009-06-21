`timescale 1ns/1ps

module output_port_lookup_regs
   #( 
       parameter UDP_REG_SRC_WIDTH = 2
   )
   (
      input                                  reg_req_in,
      input                                  reg_ack_in,
      input                                  reg_rd_wr_L_in,
      input  [`UDP_REG_ADDR_WIDTH-1:0]       reg_addr_in,
      input  [`CPCI_NF2_DATA_WIDTH-1:0]      reg_data_in,
      input  [UDP_REG_SRC_WIDTH-1:0]         reg_src_in,

      output                                 reg_req_out,
      output                                 reg_ack_out,
      output                                 reg_rd_wr_L_out,
      output [`UDP_REG_ADDR_WIDTH-1:0]       reg_addr_out,
      output [`CPCI_NF2_DATA_WIDTH-1:0]      reg_data_out,
      output [UDP_REG_SRC_WIDTH-1:0]         reg_src_out,

      //Counters
      input				     arp_misses,
      input				     lpm_misses,
      input				     cpu_pkts_sent,
      input				     bad_opts_ver,
      input				     bad_chksums,
      input				     bad_ttls,
      input				     non_ip_rcvd,
      input				     pkts_forwarded,
      input				     wrong_dest,
      input				     filtered_pkts,
      input				     arp_pkts,
      input				     ospf_pkts,
      input				     ip_pkts,

      //CPU->FPGA registers
      output [47:0]			     mac_addr_0,
      output [47:0]			     mac_addr_1,
      output [47:0]			     mac_addr_2,
      output [47:0]			     mac_addr_3,
      output				     fast_reroute_enable,
      output				     multipath_enable,

      //FPGA->CPU registers
      input [7:0]			     link_status,

      //IP filter table
      output	                             ip_filter_table_rd_req,       // Request a read
      input                                  ip_filter_table_rd_ack,       // Pulses hi on ACK
      output 	  [4:0]			     ip_filter_table_rd_addr,      // Address in table to read
      input 	  [31:0]          	     ip_filter_table_rd_data,      // Value in table
      output                                 ip_filter_table_wr_req,       // Request a write
      input                                  ip_filter_table_wr_ack,       // Pulses hi on ACK
      output 	  [4:0]			     ip_filter_table_wr_addr,      // Address in table to write
      output 	  [31:0]          	     ip_filter_table_wr_data,      // Value to write to table
    
      //ARP table
      output	                             arp_table_rd_req,       // Request a read
      input                                  arp_table_rd_ack,       // Pulses hi on ACK
      output 	  [4:0]			     arp_table_rd_addr,      // Address in table to read
      input 	  [95:0]          	     arp_table_rd_data,      // Value in table
      output                                 arp_table_wr_req,       // Request a write
      input                                  arp_table_wr_ack,       // Pulses hi on ACK
      output 	  [4:0]			     arp_table_wr_addr,      // Address in table to write
      output 	  [95:0]          	     arp_table_wr_data,      // Value to write to table

      //Route table
      output	                             route_table_rd_req,       // Request a read
      input                                  route_table_rd_ack,       // Pulses hi on ACK
      output 	  [5:0]			     route_table_rd_addr,      // Address in table to read
      input 	  [127:0]          	     route_table_rd_data,      // Value in table
      output                                 route_table_wr_req,       // Request a write
      input                                  route_table_wr_ack,       // Pulses hi on ACK
      output 	  [5:0]			     route_table_wr_addr,      // Address in table to write
      output 	  [127:0]          	     route_table_wr_data,      // Value to write to table

      //Gateway table
      output	                             gateway_table_rd_req,       // Request a read
      input                                  gateway_table_rd_ack,       // Pulses hi on ACK
      output 	  [4:0]			     gateway_table_rd_addr,      // Address in table to read
      input 	  [31:0]          	     gateway_table_rd_data,      // Value in table
      output                                 gateway_table_wr_req,       // Request a write
      input                                  gateway_table_wr_ack,       // Pulses hi on ACK
      output 	  [4:0]			     gateway_table_wr_addr,      // Address in table to write
      output 	  [31:0]          	     gateway_table_wr_data,      // Value to write to table

      input                                  clk,
      input                                  reset
    );

   wire                             sw_req_in;
   wire                             sw_ack_in;
   wire                             sw_rd_wr_L_in;
   wire [`UDP_REG_ADDR_WIDTH-1:0]   sw_addr_in;
   wire [`CPCI_NF2_DATA_WIDTH-1:0]  sw_data_in;
   wire [UDP_REG_SRC_WIDTH-1:0]     sw_src_in;

   wire                             hw_req_in;
   wire                             hw_ack_in;
   wire                             hw_rd_wr_L_in;
   wire [`UDP_REG_ADDR_WIDTH-1:0]   hw_addr_in;
   wire [`CPCI_NF2_DATA_WIDTH-1:0]  hw_data_in;
   wire [UDP_REG_SRC_WIDTH-1:0]     hw_src_in;

   wire                             route_table_req_in;
   wire                             route_table_ack_in;
   wire                             route_table_rd_wr_L_in;
   wire [`UDP_REG_ADDR_WIDTH-1:0]   route_table_addr_in;
   wire [`CPCI_NF2_DATA_WIDTH-1:0]  route_table_data_in;
   wire [UDP_REG_SRC_WIDTH-1:0]     route_table_src_in;

   wire                             arp_table_req_in;
   wire                             arp_table_ack_in;
   wire                             arp_table_rd_wr_L_in;
   wire [`UDP_REG_ADDR_WIDTH-1:0]   arp_table_addr_in;
   wire [`CPCI_NF2_DATA_WIDTH-1:0]  arp_table_data_in;
   wire [UDP_REG_SRC_WIDTH-1:0]     arp_table_src_in;

   wire                             dst_ip_filter_table_req_in;
   wire                             dst_ip_filter_table_ack_in;
   wire                             dst_ip_filter_table_rd_wr_L_in;
   wire [`UDP_REG_ADDR_WIDTH-1:0]   dst_ip_filter_table_addr_in;
   wire [`CPCI_NF2_DATA_WIDTH-1:0]  dst_ip_filter_table_data_in;
   wire [UDP_REG_SRC_WIDTH-1:0]     dst_ip_filter_table_src_in;

   wire                             gateway_table_req_in;
   wire                             gateway_table_ack_in;
   wire                             gateway_table_rd_wr_L_in;
   wire [`UDP_REG_ADDR_WIDTH-1:0]   gateway_table_addr_in;
   wire [`CPCI_NF2_DATA_WIDTH-1:0]  gateway_table_data_in;
   wire [UDP_REG_SRC_WIDTH-1:0]     gateway_table_src_in;

   // ------------- Internal parameters --------------
   localparam NUM_REGS_USED_CNTR = 12;
   localparam NUM_REGS_USED_SW	 = 10;
   localparam NUM_REGS_USED_HW	 = 1;

   // ------------- Wires/reg ------------------

   wire [NUM_REGS_USED_CNTR-1:0]   updates;
   wire [(NUM_REGS_USED_SW + NUM_REGS_USED_CNTR)* `CPCI_NF2_DATA_WIDTH-1:(NUM_REGS_USED_CNTR) * `CPCI_NF2_DATA_WIDTH]   software_regs;
   wire [(NUM_REGS_USED_HW +NUM_REGS_USED_SW+ NUM_REGS_USED_CNTR) * `CPCI_NF2_DATA_WIDTH-1:(NUM_REGS_USED_SW+NUM_REGS_USED_CNTR) * `CPCI_NF2_DATA_WIDTH]   hardware_regs;

   // -------------- Logic --------------------
   generic_cntr_regs
   #( 
      .UDP_REG_SRC_WIDTH   (UDP_REG_SRC_WIDTH),
      .TAG                 (`ROUTER_OP_LUT_BLOCK_ADDR),     // Tag to match against
      .REG_ADDR_WIDTH      (`ROUTER_OP_LUT_REG_ADDR_WIDTH),// Width of block addresses
      .NUM_REGS_USED       (NUM_REGS_USED_CNTR),              // How many registers
      .INPUT_WIDTH         (1),                          // Width of each update request
      .MIN_UPDATE_INTERVAL (1),                          // Clocks between successive inputs
      .REG_WIDTH           (`CPCI_NF2_DATA_WIDTH),       // How wide should each counter be?
      .RESET_ON_READ       (0),
      .REG_START_ADDR	   (0)
   ) generic_cntr_regs (
      .reg_req_in       (reg_req_in),
      .reg_ack_in       (reg_ack_in),
      .reg_rd_wr_L_in   (reg_rd_wr_L_in),
      .reg_addr_in      (reg_addr_in),
      .reg_data_in      (reg_data_in),
      .reg_src_in       (reg_src_in),

      .reg_req_out       (sw_req_in),
      .reg_ack_out       (sw_ack_in),
      .reg_rd_wr_L_out   (sw_rd_wr_L_in),
      .reg_addr_out      (sw_addr_in),
      .reg_data_out      (sw_data_in),
      .reg_src_out       (sw_src_in),

      // --- update interface
      .updates          (updates),
      .decrement	(0),

      .clk              (clk),
      .reset            (reset)
    );

    assign updates[`ROUTER_OP_LUT_ARP_NUM_MISSES]     	= arp_misses;
    assign updates[`ROUTER_OP_LUT_LPM_NUM_MISSES]     	= lpm_misses;
    assign updates[`ROUTER_OP_LUT_NUM_CPU_PKTS_SENT]	= cpu_pkts_sent;
    assign updates[`ROUTER_OP_LUT_NUM_BAD_OPTS_VER]   	= bad_opts_ver;
    assign updates[`ROUTER_OP_LUT_NUM_BAD_CHKSUMS]    	= bad_chksums;
    assign updates[`ROUTER_OP_LUT_NUM_BAD_TTLS]     	= bad_ttls;
    assign updates[`ROUTER_OP_LUT_NUM_NON_IP_RCVD]	= non_ip_rcvd;
    assign updates[`ROUTER_OP_LUT_NUM_PKTS_FORWARDED]   = pkts_forwarded;
    assign updates[`ROUTER_OP_LUT_NUM_WRONG_DEST]    	= wrong_dest;
    assign updates[`ROUTER_OP_LUT_NUM_FILTERED_PKTS]	= filtered_pkts;
    assign updates[`ROUTER_OP_LUT_NUM_ARP_PKTS]   	= arp_pkts;
    assign updates[`ROUTER_OP_LUT_NUM_OSPF_PKTS]    	= ospf_pkts;
    //assign updates[`ROUTER_OP_LUT_NUM_IP_PKTS]    	= ip_pkts;

   generic_sw_regs
   #( 
      .UDP_REG_SRC_WIDTH   (UDP_REG_SRC_WIDTH),
      .TAG                 (`ROUTER_OP_LUT_BLOCK_ADDR),     // Tag to match against
      .REG_ADDR_WIDTH      (`ROUTER_OP_LUT_REG_ADDR_WIDTH),// Width of block addresses
      .NUM_REGS_USED       (NUM_REGS_USED_SW),              // How many registers
      .REG_START_ADDR	   (NUM_REGS_USED_CNTR)
   ) generic_sw_regs(
      .reg_req_in       (sw_req_in),
      .reg_ack_in       (sw_ack_in),
      .reg_rd_wr_L_in   (sw_rd_wr_L_in),
      .reg_addr_in      (sw_addr_in),
      .reg_data_in      (sw_data_in),
      .reg_src_in       (sw_src_in),

      .reg_req_out      (hw_req_in),
      .reg_ack_out      (hw_ack_in),
      .reg_rd_wr_L_out  (hw_rd_wr_L_in),
      .reg_addr_out     (hw_addr_in),
      .reg_data_out     (hw_data_in),
      .reg_src_out      (hw_src_in),

      // --- SW regs interface
      .software_regs	(software_regs), // signals from the software

      .clk              (clk),
      .reset            (reset)
    );

    assign mac_addr_0 = {software_regs[(`ROUTER_OP_LUT_MAC_0_HI + 1) * `CPCI_NF2_DATA_WIDTH - 17:`ROUTER_OP_LUT_MAC_0_HI * `CPCI_NF2_DATA_WIDTH], software_regs[(`ROUTER_OP_LUT_MAC_0_LO + 1) * `CPCI_NF2_DATA_WIDTH - 1 :`ROUTER_OP_LUT_MAC_0_LO * `CPCI_NF2_DATA_WIDTH]};
    assign mac_addr_1 = {software_regs[(`ROUTER_OP_LUT_MAC_1_HI + 1) * `CPCI_NF2_DATA_WIDTH - 17:`ROUTER_OP_LUT_MAC_1_HI * `CPCI_NF2_DATA_WIDTH], software_regs[(`ROUTER_OP_LUT_MAC_1_LO + 1) * `CPCI_NF2_DATA_WIDTH - 1 :`ROUTER_OP_LUT_MAC_1_LO * `CPCI_NF2_DATA_WIDTH]};
    assign mac_addr_2 = {software_regs[(`ROUTER_OP_LUT_MAC_2_HI + 1) * `CPCI_NF2_DATA_WIDTH - 17:`ROUTER_OP_LUT_MAC_2_HI * `CPCI_NF2_DATA_WIDTH], software_regs[(`ROUTER_OP_LUT_MAC_2_LO + 1) * `CPCI_NF2_DATA_WIDTH - 1 :`ROUTER_OP_LUT_MAC_2_LO * `CPCI_NF2_DATA_WIDTH]};
    assign mac_addr_3 = {software_regs[(`ROUTER_OP_LUT_MAC_3_HI + 1) * `CPCI_NF2_DATA_WIDTH - 17:`ROUTER_OP_LUT_MAC_3_HI * `CPCI_NF2_DATA_WIDTH], software_regs[(`ROUTER_OP_LUT_MAC_3_LO + 1) * `CPCI_NF2_DATA_WIDTH - 1 :`ROUTER_OP_LUT_MAC_3_LO * `CPCI_NF2_DATA_WIDTH]};
    assign fast_reroute_enable = software_regs[(`ROUTER_OP_LUT_FAST_REROUTE_ENABLE + 1) * `CPCI_NF2_DATA_WIDTH - 1:`ROUTER_OP_LUT_FAST_REROUTE_ENABLE * `CPCI_NF2_DATA_WIDTH];
    assign multipath_enable = software_regs[(`ROUTER_OP_LUT_MULTIPATH_ENABLE + 1) * `CPCI_NF2_DATA_WIDTH - 1:`ROUTER_OP_LUT_MULTIPATH_ENABLE * `CPCI_NF2_DATA_WIDTH];


   generic_hw_regs
   #( 
      .UDP_REG_SRC_WIDTH   (UDP_REG_SRC_WIDTH),
      .TAG                 (`ROUTER_OP_LUT_BLOCK_ADDR),     // Tag to match against
      .REG_ADDR_WIDTH      (`ROUTER_OP_LUT_REG_ADDR_WIDTH),// Width of block addresses
      .NUM_REGS_USED       (NUM_REGS_USED_HW),              // How many registers
      .REG_START_ADDR	   (NUM_REGS_USED_CNTR+NUM_REGS_USED_SW)
   ) generic_hw_regs(
      .reg_req_in       (hw_req_in),
      .reg_ack_in       (hw_ack_in),
      .reg_rd_wr_L_in   (hw_rd_wr_L_in),
      .reg_addr_in      (hw_addr_in),
      .reg_data_in      (hw_data_in),
      .reg_src_in       (hw_src_in),

      .reg_req_out      (route_table_req_in),
      .reg_ack_out      (route_table_ack_in),
      .reg_rd_wr_L_out  (route_table_rd_wr_L_in),
      .reg_addr_out     (route_table_addr_in),
      .reg_data_out     (route_table_data_in),
      .reg_src_out      (route_table_src_in),

      // --- HW regs interface
      .hardware_regs	(hardware_regs), // signals from the software

      .clk              (clk),
      .reset            (reset)
    );

    assign hardware_regs[(`ROUTER_OP_LUT_LINK_STATUS + 1) * `CPCI_NF2_DATA_WIDTH - 1:`ROUTER_OP_LUT_LINK_STATUS * `CPCI_NF2_DATA_WIDTH] = link_status;

   generic_table_regs
   #( 
      .UDP_REG_SRC_WIDTH   (UDP_REG_SRC_WIDTH),
      .TAG                 (`ROUTER_OP_LUT_BLOCK_ADDR),     // Tag to match against
      .REG_ADDR_WIDTH      (`ROUTER_OP_LUT_REG_ADDR_WIDTH),// Width of block addresses
      .TABLE_ENTRY_WIDTH   (128),
      .TABLE_ADDR_WIDTH	   (6),
      .REG_START_ADDR      (NUM_REGS_USED_CNTR + NUM_REGS_USED_SW+ NUM_REGS_USED_HW)                       // Address of the first counter
   ) route_table_regs (
      .reg_req_in       (route_table_req_in),
      .reg_ack_in       (route_table_ack_in),
      .reg_rd_wr_L_in   (route_table_rd_wr_L_in),
      .reg_addr_in      (route_table_addr_in),
      .reg_data_in      (route_table_data_in),
      .reg_src_in       (route_table_src_in),

      .reg_req_out      (arp_table_req_in),
      .reg_ack_out      (arp_table_ack_in),
      .reg_rd_wr_L_out  (arp_table_rd_wr_L_in),
      .reg_addr_out     (arp_table_addr_in),
      .reg_data_out     (arp_table_data_in),
      .reg_src_out      (arp_table_src_in),

      .table_rd_addr    (route_table_rd_addr),
      .table_rd_data    (route_table_rd_data),
      .table_rd_req     (route_table_rd_req),
      .table_rd_ack     (route_table_rd_ack),
      .table_wr_addr    (route_table_wr_addr),
      .table_wr_data    (route_table_wr_data),
      .table_wr_req     (route_table_wr_req),
      .table_wr_ack     (route_table_wr_ack),

      .clk              (clk),
      .reset            (reset)
    );

   generic_table_regs
   #( 
      .UDP_REG_SRC_WIDTH   (UDP_REG_SRC_WIDTH),
      .TAG                 (`ROUTER_OP_LUT_BLOCK_ADDR),     // Tag to match against
      .REG_ADDR_WIDTH      (`ROUTER_OP_LUT_REG_ADDR_WIDTH),// Width of block addresses
      .TABLE_ENTRY_WIDTH   (96),
      .TABLE_ADDR_WIDTH	   (5),
      .REG_START_ADDR      (NUM_REGS_USED_CNTR + NUM_REGS_USED_SW+ NUM_REGS_USED_HW + 2 + 4)                       // Address of the first counter
   ) arp_table_regs (
      .reg_req_in       (arp_table_req_in),
      .reg_ack_in       (arp_table_ack_in),
      .reg_rd_wr_L_in   (arp_table_rd_wr_L_in),
      .reg_addr_in      (arp_table_addr_in),
      .reg_data_in      (arp_table_data_in),
      .reg_src_in       (arp_table_src_in),

      .reg_req_out      (dst_ip_filter_table_req_in),
      .reg_ack_out      (dst_ip_filter_table_ack_in),
      .reg_rd_wr_L_out  (dst_ip_filter_table_rd_wr_L_in),
      .reg_addr_out     (dst_ip_filter_table_addr_in),
      .reg_data_out     (dst_ip_filter_table_data_in),
      .reg_src_out      (dst_ip_filter_table_src_in),

      .table_rd_addr    (arp_table_rd_addr),
      .table_rd_data    (arp_table_rd_data),
      .table_rd_req     (arp_table_rd_req),
      .table_rd_ack     (arp_table_rd_ack),
      .table_wr_addr    (arp_table_wr_addr),
      .table_wr_data    (arp_table_wr_data),
      .table_wr_req     (arp_table_wr_req),
      .table_wr_ack     (arp_table_wr_ack),

      .clk              (clk),
      .reset            (reset)
    );

   generic_table_regs
   #( 
      .UDP_REG_SRC_WIDTH   (UDP_REG_SRC_WIDTH),
      .TAG                 (`ROUTER_OP_LUT_BLOCK_ADDR),     // Tag to match against
      .REG_ADDR_WIDTH      (`ROUTER_OP_LUT_REG_ADDR_WIDTH),// Width of block addresses
      .TABLE_ENTRY_WIDTH   (32),
      .TABLE_ADDR_WIDTH	   (5),
      .REG_START_ADDR      (NUM_REGS_USED_CNTR + NUM_REGS_USED_SW+ NUM_REGS_USED_HW + 2 + 4 + 2 + 3)                       // Address of the first counter
   ) dst_ip_filter_table_regs (
      .reg_req_in       (dst_ip_filter_table_req_in),
      .reg_ack_in       (dst_ip_filter_table_ack_in),
      .reg_rd_wr_L_in   (dst_ip_filter_table_rd_wr_L_in),
      .reg_addr_in      (dst_ip_filter_table_addr_in),
      .reg_data_in      (dst_ip_filter_table_data_in),
      .reg_src_in       (dst_ip_filter_table_src_in),

      .reg_req_out      (gateway_table_req_in),
      .reg_ack_out      (gateway_table_ack_in),
      .reg_rd_wr_L_out  (gateway_table_rd_wr_L_in),
      .reg_addr_out     (gateway_table_addr_in),
      .reg_data_out     (gateway_table_data_in),
      .reg_src_out      (gateway_table_src_in),

      .table_rd_addr    (ip_filter_table_rd_addr),
      .table_rd_data    (ip_filter_table_rd_data),
      .table_rd_req     (ip_filter_table_rd_req),
      .table_rd_ack     (ip_filter_table_rd_ack),
      .table_wr_addr    (ip_filter_table_wr_addr),
      .table_wr_data    (ip_filter_table_wr_data),
      .table_wr_req     (ip_filter_table_wr_req),
      .table_wr_ack     (ip_filter_table_wr_ack),

      .clk              (clk),
      .reset            (reset)
    );

   generic_table_regs
   #( 
      .UDP_REG_SRC_WIDTH   (UDP_REG_SRC_WIDTH),
      .TAG                 (`ROUTER_OP_LUT_BLOCK_ADDR),     // Tag to match against
      .REG_ADDR_WIDTH      (`ROUTER_OP_LUT_REG_ADDR_WIDTH),// Width of block addresses
      .TABLE_ENTRY_WIDTH   (32),
      .TABLE_ADDR_WIDTH	   (5),
      .REG_START_ADDR      (NUM_REGS_USED_CNTR + NUM_REGS_USED_SW+ NUM_REGS_USED_HW + 2 + 4 + 2 + 3 + 3)                       // Address of the first counter
   ) gateway_table_regs (
      .reg_req_in       (gateway_table_req_in),
      .reg_ack_in       (gateway_table_ack_in),
      .reg_rd_wr_L_in   (gateway_table_rd_wr_L_in),
      .reg_addr_in      (gateway_table_addr_in),
      .reg_data_in      (gateway_table_data_in),
      .reg_src_in       (gateway_table_src_in),

      .reg_req_out      (reg_req_out),
      .reg_ack_out      (reg_ack_out),
      .reg_rd_wr_L_out  (reg_rd_wr_L_out),
      .reg_addr_out     (reg_addr_out),
      .reg_data_out     (reg_data_out),
      .reg_src_out      (reg_src_out),

      .table_rd_addr    (gateway_table_rd_addr),
      .table_rd_data    (gateway_table_rd_data),
      .table_rd_req     (gateway_table_rd_req),
      .table_rd_ack     (gateway_table_rd_ack),
      .table_wr_addr    (gateway_table_wr_addr),
      .table_wr_data    (gateway_table_wr_data),
      .table_wr_req     (gateway_table_wr_req),
      .table_wr_ack     (gateway_table_wr_ack),

      .clk              (clk),
      .reset            (reset)
    );
endmodule
