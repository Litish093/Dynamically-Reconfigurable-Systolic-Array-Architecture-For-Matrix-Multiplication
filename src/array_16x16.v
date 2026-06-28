// =============================================================================
// array_16x16.v
// 16x16 Systolic PE Array for the Dynamically Reconfigurable Systolic Array
//
// Instantiates a 16x16 grid of pe_16x16 modules and wires them together.
// Data flows:
//   A operands: injected at left edge (column 0), flow right across each row
//   B operands: injected at top edge (row 0), flow down each column
//   Valid tokens: propagate with the data to enable accumulation in each PE
//
// Mode 0 (16x16):
//   All 256 PEs cooperate as one unified array.
//   a_in for row i comes from a_bus[i].
//   b_in for col j comes from b_bus[j].
//
// Mode 1 (four 8x8):
//   Zero-wire isolation at col-8 and row-8 boundaries splits the array
//   into four independent 8x8 quadrants (TL, TR, BL, BR).
//   Quadrant isolation is done by assigning {DW{1'b0}} to h_w[i][8]
//   and v_w[8][j] - no extra logic inside the PE itself.
//   Each quadrant gets its own A and B data from separate BRAM banks.
//   The valid token bus is mirrored so all four quadrants start simultaneously.
//
// The c_out_flat port packs all 256 accumulator outputs into a single wide
// bus: c_out_flat[(i*16+j)*AW +: AW] = PE[i][j].acc
//
// Parameters:
//   DW - data width (8-bit)
//   AW - accumulator width (32-bit)
// =============================================================================

`timescale 1ns/1ps

module array_16x16 #(
    parameter DW = 8,
    parameter AW = 32
)(
    input  wire               clk,
    input  wire               rst_n,
    input  wire               clear,       // synchronous clear to all PEs
    input  wire               mode,        // 0 = 16x16, 1 = four 8x8
    input  wire [15:0]        v_in_rows,   // valid token per row (mirrored in Mode 1)
    input  wire [(32*DW)-1:0] a_bus,       // packed A operands (32 banks x 8 bits)
    input  wire [(32*DW)-1:0] b_bus,       // packed B operands (32 banks x 8 bits)
    output wire [(256*AW)-1:0] c_out_flat  // packed PE accumulator outputs
);

    // Internal wires for horizontal (A) and vertical (B) data propagation
    wire [DW-1:0] h_w    [0:15][0:16];  // horizontal wire: h_w[row][col] → PE[row][col].a_in
    wire [DW-1:0] v_w    [0:16][0:15];  // vertical wire:   v_w[row][col] → PE[row][col].b_in
    wire          v_prop [0:15][0:16];  // valid token propagation along each row

    genvar i, j;
    generate
        for (i = 0; i < 16; i = i + 1) begin : rows
            // Seed valid token at left edge of each row
            assign v_prop[i][0] = v_in_rows[i];

            for (j = 0; j < 16; j = j + 1) begin : cols

                // In Mode 1, re-inject valid token at col 8 boundary (right quadrants)
                wire v_step = (mode && j == 8) ? v_in_rows[i] : v_prop[i][j];

                // A input mux: selects correct BRAM bank depending on mode and quadrant
                wire [DW-1:0] a_in_w;
                assign a_in_w =
                    // Column 0: all modes inject from a_bus
                    (j == 0)         ? ((!mode)   ? a_bus[i*DW        +: DW]  // Mode 0: bank i
                                       : (i < 8)  ? a_bus[i*DW        +: DW]  // Mode 1 TL/TR: bank i
                                                  : a_bus[(i+8)*DW    +: DW]) // Mode 1 BL/BR: bank i+8
                    // Mode 1 column 8 boundary: re-inject for right quadrants
                  : (mode && j == 8) ? ((i < 8)   ? a_bus[(i+8)*DW   +: DW]  // Mode 1 TR: bank i+8
                                                  : a_bus[(i+16)*DW  +: DW]) // Mode 1 BR: bank i+16
                    // All other columns: pass through from left neighbour
                  : h_w[i][j];

                // B input mux: selects correct BRAM bank depending on mode and quadrant
                wire [DW-1:0] b_in_w;
                assign b_in_w =
                    // Row 0: all modes inject from b_bus
                    (i == 0)         ? b_bus[j*DW        +: DW]               // TL/TR top row
                    // Mode 1 row 8 boundary: re-inject for bottom quadrants
                  : (mode && i == 8) ? b_bus[(j+16)*DW   +: DW]              // BL/BR bank j+16
                    // All other rows: pass through from upper neighbour
                  : v_w[i][j];

                // PE output wires
                wire [DW-1:0] pa, pb;
                wire          pv;

                pe_16x16 #(DW, AW) pe (
                    .clk   (clk),
                    .rst_n (rst_n),
                    .clear (clear),
                    .v_in  (v_step),
                    .v_out (pv),
                    .a_in  (a_in_w),
                    .b_in  (b_in_w),
                    .a_out (pa),
                    .b_out (pb),
                    .acc   (c_out_flat[((i*16+j)*AW) +: AW])
                );

                // Propagate valid token rightward
                assign v_prop[i][j+1] = pv;

                // Zero the horizontal wire at col-7→8 boundary in Mode 1 (quadrant isolation)
                assign h_w[i][j+1] = (mode && j == 7) ? {DW{1'b0}} : pa;

                // Zero the vertical wire at row-7→8 boundary in Mode 1 (quadrant isolation)
                assign v_w[i+1][j] = (mode && i == 7) ? {DW{1'b0}} : pb;

            end
        end
    endgenerate

endmodule
