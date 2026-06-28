// =============================================================================
// write_iob_reg.v
// IOB Input Register for the write interface
//
// Registers all slow-changing write-interface signals at the IOB (I/O Block)
// level. This moves the input flip-flop physically to the pad, eliminating
// the routing delay from pad to fabric FF from the timing path.
//
// The (* IOB = "TRUE" *) attribute tells Vivado to pack these registers
// into the IOB primitives rather than placing them in the fabric slice.
//
// All write interface signals (we, mem_sel, bank_sel, wr_addr, data_in)
// are quasi-static during normal operation - they are set up well before
// the write enable pulse, so placing them in IOBs is timing-safe.
//
// Parameters:
//   DW - data width (8-bit)
//   AW - address width (5-bit for DEPTH=32)
// =============================================================================

`timescale 1ns/1ps

module write_iob_reg #(
    parameter DW = 8,
    parameter AW = 5
)(
    input  wire          clk,
    input  wire          we_in,
    input  wire          mem_sel_in,
    input  wire [4:0]    bank_sel_in,
    input  wire [AW-1:0] wr_addr_in,
    input  wire [DW-1:0] data_in,
    output reg           we_out,
    output reg           mem_sel_out,
    output reg  [4:0]    bank_sel_out,
    output reg  [AW-1:0] wr_addr_out,
    output reg  [DW-1:0] data_out
);

    (* IOB = "TRUE" *)
    always @(posedge clk) begin
        we_out       <= we_in;
        mem_sel_out  <= mem_sel_in;
        bank_sel_out <= bank_sel_in;
        wr_addr_out  <= wr_addr_in;
        data_out     <= data_in;
    end

endmodule
