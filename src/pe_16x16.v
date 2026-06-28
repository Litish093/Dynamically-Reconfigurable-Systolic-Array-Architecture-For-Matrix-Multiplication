// =============================================================================
// pe_16x16.v
// Processing Element for the 16x16 Dynamically Reconfigurable Systolic Array
//
// Each PE does a 2-stage pipelined MAC operation:
//   Stage 1 - Registers the 8-bit inputs and computes the 16-bit product
//   Stage 2 - Conditionally accumulates the product into a 32-bit register
//
// Data movement:
//   a_in flows right  → a_out  (to next column)
//   b_in flows down   → b_out  (to next row)
//
// The clear input resets the accumulator synchronously so timing closure
// is straightforward - no async paths.
//
// Parameters:
//   DW  - data width of input operands (default 8-bit)
//   AW  - accumulator width (default 32-bit)
// =============================================================================

`timescale 1ns/1ps

module pe_16x16 #(
    parameter DW = 8,
    parameter AW = 32
)(
    input  wire          clk,
    input  wire          rst_n,
    input  wire          v_in,       // valid token - when high, data at input is valid
    input  wire          clear,      // synchronous accumulator clear
    input  wire [DW-1:0] a_in,       // operand A (flows right)
    input  wire [DW-1:0] b_in,       // operand B (flows down)
    output reg           v_out,      // valid token propagated to next PE
    output reg  [DW-1:0] a_out,      // A forwarded to right neighbour
    output reg  [DW-1:0] b_out,      // B forwarded to bottom neighbour
    output reg  [AW-1:0] acc         // accumulated result output
);

    reg [2*DW-1:0] product_reg;  // holds registered product (Stage 1 output)
    reg            v_in_d1;      // valid delayed by 1 cycle to align with product_reg

    // Stage 1: register inputs, compute product
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            product_reg <= 0;
            v_in_d1     <= 0;
            a_out       <= 0;
            b_out       <= 0;
            v_out       <= 0;
        end else if (clear) begin
            product_reg <= 0;
            v_in_d1     <= 0;
            a_out       <= 0;
            b_out       <= 0;
            v_out       <= 0;
        end else begin
            product_reg <= a_in * b_in;  // 8x8 → 16-bit product
            v_in_d1     <= v_in;
            a_out       <= a_in;         // pass A right
            b_out       <= b_in;         // pass B down
            v_out       <= v_in;
        end
    end

    // Stage 2: accumulate when valid token arrives (delayed to match product_reg)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            acc <= 0;
        else if (clear)
            acc <= 0;
        else if (v_in_d1)
            acc <= acc + {{(AW-2*DW){1'b0}}, product_reg};
    end

endmodule
