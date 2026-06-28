// =============================================================================
// mem_bank_16x16.v
// Operand Memory Banks for the 16x16 Dynamically Reconfigurable Systolic Array
//
// 32 independent BRAM18 banks, each 8-bit wide x 32 entries deep.
// One bank per row of matrix A and per column of matrix B.
//
// The write interface is serial: one byte per cycle using a one-hot
// decoded write-enable. This keeps the top-level I/O count manageable.
//
// Output pipeline note:
//   A second register stage (rdata_q) is added after the standard BRAM
//   output register (rdata). This mirrors RAMB18E1 DOA_REG=1 behaviour
//   in portable RTL. Vivado maps rdata_q onto the BRAM's built-in output
//   register (OREG) at zero extra LUT/FF cost.
//
//   This extra latency cycle is compensated by:
//     (a) delaying the valid mask by 2 cycles instead of 1 in the top level
//     (b) adding 1 to DRAIN_0 and DRAIN_1 in the controller
//
// Parameters:
//   DW    - data width per bank (8-bit)
//   DEPTH - number of entries per bank (32)
//   BANKS - number of banks (32)
// =============================================================================

`timescale 1ns/1ps

module mem_bank_16x16 #(
    parameter DW    = 8,
    parameter DEPTH = 32,
    parameter BANKS = 32
)(
    input  wire                             clk,
    input  wire [BANKS-1:0]                 we,          // one-hot write enables
    input  wire [(BANKS*$clog2(DEPTH))-1:0] addr_bus,    // packed address bus
    input  wire [(BANKS*DW)-1:0]            din,         // packed write data
    output wire [(BANKS*DW)-1:0]            dout         // packed read data (2-cycle latency)
);

    localparam ADDR_W = $clog2(DEPTH);

    genvar b;
    generate
        for (b = 0; b < BANKS; b = b + 1) begin : bank

            (* ram_style = "block" *)
            reg [DW-1:0] mem [0:DEPTH-1];

            reg [DW-1:0] rdata;    // Stage 1: standard BRAM registered output
            reg [DW-1:0] rdata_q;  // Stage 2: second pipeline register (maps to BRAM OREG)

            integer idx;
            initial begin
                for (idx = 0; idx < DEPTH; idx = idx + 1)
                    mem[idx] = {DW{1'b0}};
                rdata   = {DW{1'b0}};
                rdata_q = {DW{1'b0}};
            end

            always @(posedge clk) begin
                // Write port
                if (we[b])
                    mem[addr_bus[b*ADDR_W +: ADDR_W]] <= din[b*DW +: DW];
                // Read port - 2-stage pipeline
                rdata   <= mem[addr_bus[b*ADDR_W +: ADDR_W]];
                rdata_q <= rdata;
            end

            // Expose 2nd stage output (aligned with 2-cycle valid mask delay in top level)
            assign dout[b*DW +: DW] = rdata_q;

        end
    endgenerate

endmodule
