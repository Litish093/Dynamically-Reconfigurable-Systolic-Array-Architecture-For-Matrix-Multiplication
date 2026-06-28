// =============================================================================
// ctrl_16x16.v
// Systolic Controller FSM for the 16x16 Dynamically Reconfigurable Systolic Array
//
// Drives the three-phase compute sequence:
//
//   Phase 1 - Clear (CLR_CYCLES = 4):
//     Asserts clr to flush all PE accumulators before a new computation.
//
//   Phase 2 - Compute:
//     Asserts en and increments rd_ptr from 0 to K_eff.
//     The AGU uses rd_ptr to generate staggered BRAM addresses.
//
//   Phase 3 - Drain:
//     Waits for the last valid token to propagate through the pipeline
//     and the last accumulation to complete, then asserts done.
//
// Mode-dependent timing (latched at start):
//
//   Mode 0 (16x16):  K_eff=31, DRAIN=21  → total = 4+31+21 = 56 cycles
//   Mode 1 (4x 8x8): K_eff=14, DRAIN=14  → total = 4+14+14 = 32 cycles
//
//   Note: DRAIN values are +1 vs theoretical due to the 2-cycle BRAM
//   output pipeline in mem_bank_16x16. Original values were DRAIN_0=20,
//   DRAIN_1=13 before this fix was applied.
//
// Parameters:
//   DEPTH      - BRAM depth (sets address width)
//   CLR_CYCLES - number of accumulator clear cycles before compute
//   DRAIN_0    - drain cycles for Mode 0 (accounts for BRAM pipeline)
//   DRAIN_1    - drain cycles for Mode 1 (accounts for BRAM pipeline)
//   KEFF1      - effective K for Mode 1 (= S-1 + Nsub-1 = 7+7 = 14)
// =============================================================================

`timescale 1ns/1ps

module ctrl_16x16 #(
    parameter DEPTH      = 32,
    parameter CLR_CYCLES = 4,
    parameter DRAIN_0    = 21,   // +1 vs original to account for BRAM output pipeline
    parameter DRAIN_1    = 14,   // +1 vs original to account for BRAM output pipeline
    parameter KEFF1      = 14
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    start,   // pulse to begin a computation
    input  wire                    mode,    // 0 = 16x16, 1 = four 8x8
    output reg                     en,      // enable signal for AGU and array
    output reg                     clr,     // accumulator clear to all PEs
    output reg                     done,    // high for 1 cycle when results are ready
    output reg [$clog2(DEPTH)-1:0] rd_ptr   // current BRAM read pointer for AGU
);

    localparam ADDR_W = $clog2(DEPTH);
    localparam K0     = DEPTH - 1;          // K_eff for Mode 0 = 31
    localparam CNT_W  = ADDR_W + 7;         // counter wide enough for drain cycles

    reg [CNT_W-1:0]  count;
    reg              running;
    reg [CNT_W-1:0]  drain_r;   // latched drain count for current mode
    reg [ADDR_W-1:0] keff_r;    // latched K_eff for current mode

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            en      <= 0;
            clr     <= 0;
            done    <= 0;
            rd_ptr  <= 0;
            count   <= 0;
            running <= 0;
            drain_r <= 0;
            keff_r  <= 0;
        end else begin
            clr  <= 0;
            done <= 0;

            if (start && !running) begin
                // Latch mode parameters at start pulse
                running <= 1'b1;
                count   <= {CNT_W{1'b0}};
                rd_ptr  <= {ADDR_W{1'b0}};
                en      <= 1'b0;
                drain_r <= mode ? DRAIN_1[CNT_W-1:0] : DRAIN_0[CNT_W-1:0];
                keff_r  <= mode ? KEFF1[ADDR_W-1:0]  : K0[ADDR_W-1:0];

            end else if (running) begin
                count <= count + 1'b1;

                // Phase 1: clear accumulate registers
                if (count < CLR_CYCLES)
                    clr <= 1'b1;

                // Phase 2: enable compute, start incrementing read pointer
                if (count == CLR_CYCLES)
                    en <= 1'b1;

                if (en && rd_ptr < keff_r)
                    rd_ptr <= rd_ptr + 1'b1;

                // Phase 3: drain complete, assert done for 1 cycle
                if (count == (keff_r + CLR_CYCLES[CNT_W-1:0] + drain_r)) begin
                    running <= 0;
                    en      <= 0;
                    done    <= 1;
                end
            end
        end
    end

endmodule
