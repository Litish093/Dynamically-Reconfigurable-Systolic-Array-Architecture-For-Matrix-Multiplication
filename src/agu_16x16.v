// =============================================================================
// agu_16x16.v
// Address Generation Unit for the 16x16 Dynamically Reconfigurable Systolic Array
//
// Generates staggered BRAM read addresses so operand wavefronts arrive
// at the PE grid boundary in the correct cycle.
//
// Two modes controlled by the mode bit:
//
//   Mode 0 (16x16 GEMM):
//     addr[k] = rd_ptr - k           stagger modulus S = 16
//     valid when rd_ptr >= k and rd_ptr <= K_MAX (K_MAX = DEPTH-1 = 31)
//
//   Mode 1 (four 8x8 GEMMs):
//     addr[k] = rd_ptr - (k mod 8)   stagger modulus S = 8
//     valid when rd_ptr >= (k mod 8) and rd_ptr <= K_MAX
//     This causes all four quadrants to start their wavefronts simultaneously
//
// valid_mask[k] gates the BRAM output to zero until the wavefront reaches
// bank k, preventing garbage data from entering the array during startup.
//
// Parameters:
//   BANKS       - number of BRAM banks (32, one per row/col of the 16x16 array
//                 for each operand)
//   DEPTH       - BRAM depth (32)
//   STAGGER_MOD - stagger modulus, set to 8 so that mode selection via
//                 bitmasking (k & (S-1)) handles both modes correctly
// =============================================================================

`timescale 1ns/1ps

module agu_16x16 #(
    parameter BANKS       = 32,
    parameter DEPTH       = 32,
    parameter STAGGER_MOD = 8
)(
    input  wire [$clog2(DEPTH)-1:0]         rd_ptr,      // current read pointer from controller
    input  wire                             mode,         // 0 = 16x16, 1 = four 8x8
    input  wire                             en_active,    // high during compute phase
    output reg  [(BANKS*$clog2(DEPTH))-1:0] addr_bus,    // packed address outputs
    output reg  [BANKS-1:0]                 valid_mask    // per-bank valid gate
);

    localparam ADDR_W = $clog2(DEPTH);
    localparam [ADDR_W-1:0] K_MAX = DEPTH - 1;

    integer k;

    always @(*) begin
        for (k = 0; k < BANKS; k = k + 1) begin : agu_blk
            reg [ADDR_W-1:0] k_addr, k_stag;

            k_addr = k[ADDR_W-1:0];
            // k_stag = k mod STAGGER_MOD using bitmask (works because STAGGER_MOD is power of 2)
            k_stag = k_addr & (STAGGER_MOD[ADDR_W-1:0] - 1'b1);

            if (!mode) begin
                // Mode 0: full 16x16, stagger by bank index
                valid_mask[k] = en_active && (rd_ptr >= k_addr) && (rd_ptr <= K_MAX);
                addr_bus[k*ADDR_W +: ADDR_W] =
                    valid_mask[k] ? (rd_ptr - k_addr) : {ADDR_W{1'b0}};
            end else begin
                // Mode 1: four 8x8, stagger by bank index within each 8-bank quadrant
                valid_mask[k] = en_active && (rd_ptr >= k_stag) && (rd_ptr <= K_MAX);
                addr_bus[k*ADDR_W +: ADDR_W] =
                    valid_mask[k] ? (rd_ptr - k_stag) : {ADDR_W{1'b0}};
            end
        end
    end

endmodule
