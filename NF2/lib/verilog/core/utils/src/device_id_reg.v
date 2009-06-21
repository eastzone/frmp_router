///////////////////////////////////////////////////////////////////////////////
// vim:set shiftwidth=3 softtabstop=3 expandtab:
// $Id: device_id_reg.v 5085 2009-02-23 00:13:30Z grg $
//
// Module: device_id_reg.v
// Project: NetFPGA
// Description: Reprogramming RAM access registers
//
// Allows reading/writing to ram via registers
//
///////////////////////////////////////////////////////////////////////////////

module device_id_reg #(
      parameter DEVICE_ID = 0,
      parameter REVISION = 0,
      parameter DEVICE_STR = "Undefined device"
   )
   (
      // Register interface signals
      input                                     reg_req,
      output reg                                reg_ack,
      input                                     reg_rd_wr_L,

      input [(`CORE_REG_ADDR_WIDTH - 2 - 4) - 1:0] reg_addr,

      output reg [`CPCI_NF2_DATA_WIDTH - 1:0]   reg_rd_data,
      input [`CPCI_NF2_DATA_WIDTH - 1:0]        reg_wr_data,

      //
      input             clk,
      input             reset
   );

localparam NUM_REGS         = 32;
localparam STR_REGS         = 25;
localparam DEVICE_STR_LEN   = STR_REGS * 4;
localparam WORD_WIDTH       = `CPCI_NF2_DATA_WIDTH / 8;

// Extract a part of the device string
//
// Note: This assumes that CPCI_NF2_DATA_WIDTH is 32 bits
// Attempted to make this generic but it generated an XST error to
// do with array accesses (worked fine in ModelSim).
function [`CPCI_NF2_DATA_WIDTH - 1:0] get_device_substr;
   input integer word;
   reg [DEVICE_STR_LEN  *  8 - 1:0] temp_str;
   reg [7:0] result_1;
   reg [7:0] result_2;
   reg [7:0] result_3;
   reg [7:0] result_4;
   integer length;
   integer pos;
   integer i;
   begin
      temp_str = DEVICE_STR;

      // Calculate the length
      length = 0;
      //pos = DEVICE_STR_LEN * 8 - 1;
      pos = 0;
      while (pos <= DEVICE_STR_LEN * 8 - 1 && temp_str[pos +: 8] != 8'h0) begin
         length = length + 1;
         pos = pos + 8;
      end

      // Jump to the location that we are trying to copy data from
      pos = (length - word * WORD_WIDTH) * 8 - 1;

      // Copy the data
      result_1 = (pos < 0) ? 8'b0 : temp_str[pos -: 8];
      pos = pos - 8;

      result_2 = (pos < 0) ? 8'b0 : temp_str[pos -: 8];
      pos = pos - 8;

      result_3 = (pos < 0) ? 8'b0 : temp_str[pos -: 8];
      pos = pos - 8;

      result_4 = (pos < 0) ? 8'b0 : temp_str[pos -: 8];

      get_device_substr = {result_1, result_2, result_3, result_4};
   end
endfunction // get_device_substr


reg req_acked;

wire [`CPCI_NF2_DATA_WIDTH-1:0] device_id[0:NUM_REGS - 1];

genvar i;

assign device_id[`DEV_ID_MD5_0]      = `DEV_ID_MD5_VALUE_0;
assign device_id[`DEV_ID_MD5_1]      = `DEV_ID_MD5_VALUE_1;
assign device_id[`DEV_ID_MD5_2]      = `DEV_ID_MD5_VALUE_2;
assign device_id[`DEV_ID_MD5_3]      = `DEV_ID_MD5_VALUE_3;
assign device_id[`DEV_ID_DEVICE_ID]  = DEVICE_ID;
assign device_id[`DEV_ID_REVISION]   = REVISION;
assign device_id[`DEV_ID_CPCI_ID]    = {`CPCI_REVISION_ID, `CPCI_VERSION_ID};
generate
   for (i = 0 ; i < STR_REGS; i = i + 1) begin: device_id_gen
      assign device_id[i + (NUM_REGS - STR_REGS)] = get_device_substr(i);
   end
endgenerate


// ==============================================
// Main state machine

always @(posedge clk)
begin
   if (reset) begin
      reg_ack        <= 1'b0;
      reg_rd_data    <= 'h 0;

      req_acked      <= 1'b0;
   end
   else begin
      if (reg_req) begin
         // Only process the request if it's new
         if (!req_acked) begin
            reg_ack      <= 1'b1;
            req_acked    <= 1'b1;
            
            // Verify that the address actually corresponds to the RAM
            if (reg_addr < NUM_REGS) begin 
               reg_rd_data <= device_id[reg_addr];
            end
            else begin
               reg_rd_data <= 'h dead_beef;
            end
         end
         else begin
            reg_ack <= 1'b0;
         end
      end // if (reg_req)
      else begin
         reg_ack      <= 1'b0;
         req_acked    <= 1'b0;
      end // if (reg_req) else
   end
end

endmodule // device_id_reg
