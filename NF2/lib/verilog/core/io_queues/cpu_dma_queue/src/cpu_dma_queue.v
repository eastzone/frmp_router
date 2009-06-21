///////////////////////////////////////////////////////////////////////////////
// vim:set shiftwidth=3 softtabstop=3 expandtab:
// $Id: cpu_dma_queue.v 2265 2007-09-17 22:02:57Z grg $
//
// Module: cpu_dma_queue.v
// Project: NF2.1
// Description: 
//              a slim CPU rx_fifo and tx_fifo connecting to the DMA interface
// 
//              Note that both rx_fifo and tx_fifo are first-word-fall-through FIFOs.
//
///////////////////////////////////////////////////////////////////////////////

  module cpu_dma_queue 
    #(parameter DATA_WIDTH = 64,
      parameter CTRL_WIDTH=DATA_WIDTH/8,
      parameter DMA_DATA_WIDTH = `CPCI_NF2_DATA_WIDTH,
      parameter DMA_CTRL_WIDTH = DMA_DATA_WIDTH/8,
      parameter TX_WATCHDOG_TIMEOUT = 125000
      )
   (output [DATA_WIDTH-1:0]              out_data,
    output [CTRL_WIDTH-1:0]              out_ctrl,
    output                               out_wr,
    input                                out_rdy,
    
    input  [DATA_WIDTH-1:0]              in_data,
    input  [CTRL_WIDTH-1:0]              in_ctrl,
    input                                in_wr,
    output                               in_rdy,

    // --- DMA rd rxfifo interface
    output                               cpu_q_dma_pkt_avail,

    input                                cpu_q_dma_rd,
    output [DMA_DATA_WIDTH-1:0]          cpu_q_dma_rd_data,
    output [DMA_CTRL_WIDTH-1:0]          cpu_q_dma_rd_ctrl,

    // DMA wr txfifo interface
    output                               cpu_q_dma_nearly_full,

    input                                cpu_q_dma_wr,
    input [DMA_DATA_WIDTH-1:0]           cpu_q_dma_wr_data, 
    input [DMA_CTRL_WIDTH-1:0]           cpu_q_dma_wr_ctrl,

    // Register interface
    input                                reg_req,
    input                                reg_rd_wr_L,
    input  [`MAC_GRP_REG_ADDR_WIDTH-1:0] reg_addr,
    input  [`CPCI_NF2_DATA_WIDTH-1:0]    reg_wr_data,
     
    output [`CPCI_NF2_DATA_WIDTH-1:0]    reg_rd_data,
    output                               reg_ack,

    // --- Misc
    input                                reset,
    input                                clk
    );

   // -------- Internal parameters --------------


   // ------------- Wires/reg ------------------

   wire                          tx_timeout;

   // ------------- Modules -------------------
   
cpu_dma_queue_main
   #(
      .DATA_WIDTH          (DATA_WIDTH),
      .CTRL_WIDTH          (CTRL_WIDTH),
      .DMA_DATA_WIDTH      (DMA_DATA_WIDTH),
      .DMA_CTRL_WIDTH      (DMA_CTRL_WIDTH),
      .TX_WATCHDOG_TIMEOUT (TX_WATCHDOG_TIMEOUT)
   ) cpu_dma_queue_main (
      .out_data                     (out_data),
      .out_ctrl                     (out_ctrl),
      .out_wr                       (out_wr),
      .out_rdy                      (out_rdy),
      
      .in_data                      (in_data),
      .in_ctrl                      (in_ctrl),
      .in_wr                        (in_wr),
      .in_rdy                       (in_rdy),

      // --- DMA rd rxfifo interface
      .cpu_q_dma_pkt_avail          (cpu_q_dma_pkt_avail),

      .cpu_q_dma_rd                 (cpu_q_dma_rd),
      .cpu_q_dma_rd_data            (cpu_q_dma_rd_data),
      .cpu_q_dma_rd_ctrl            (cpu_q_dma_rd_ctrl),

      // DMA wr txfifo interface
      .cpu_q_dma_nearly_full        (cpu_q_dma_nearly_full),

      .cpu_q_dma_wr                 (cpu_q_dma_wr),
      .cpu_q_dma_wr_data            (cpu_q_dma_wr_data), 
      .cpu_q_dma_wr_ctrl            (cpu_q_dma_wr_ctrl),

      // Register interface
      .tx_timeout                   (tx_timeout),

      // --- Misc
      .reset                        (reset),
      .clk                          (clk)
   );



cpu_dma_queue_regs
   #(
      .TX_WATCHDOG_TIMEOUT (TX_WATCHDOG_TIMEOUT)
   ) cpu_dma_queue_regs (
      // Interface to "main" module
      .tx_timeout                            (tx_timeout),

      // Register interface
      .reg_req                               (reg_req),
      .reg_rd_wr_L                           (reg_rd_wr_L),
      .reg_addr                              (reg_addr),
      .reg_wr_data                           (reg_wr_data),
       
      .reg_rd_data                           (reg_rd_data),
      .reg_ack                               (reg_ack),

      // --- Misc
      .reset                                 (reset),
      .clk                                   (clk)
   );
   // -------------- Logic --------------------

endmodule // cpu_dma_queue
