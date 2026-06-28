// =============================================================================
// systolic_16x16_fpga.v
// Top-Level Module: Dynamically Reconfigurable Systolic Array (16x16)
//
// Integrates all sub-modules:
//   - write_iob_reg    : IOB-registered write interface
//   - ctrl_16x16       : 3-phase FSM (clear → compute → drain)
//   - agu_16x16 x2     : staggered address generation for A and B banks
//   - mem_bank_16x16x2 : 32 BRAM18 banks each for A and B operands
//   - array_16x16      : 16x16 grid of pipelined MAC processing elements
//   - result_bram_16x16: sequential result store + read interface
//
// Two runtime modes selected by the mode input:
//   mode=0 : one 16x16 GEMM  (all 256 PEs, latency 56 cycles + 256 fill)
//   mode=1 : four 8x8 GEMMs  (quadrant isolation, latency 32 cycles + 256 fill)
//
// Valid mask pipeline fix:
//   The BRAM has a 2-cycle output latency (rdata → rdata_q in mem_bank_16x16).
//   To keep the valid token aligned with actual data arriving at the PE input,
//   the valid mask from the AGU is delayed by 2 cycles (m_d1 → m_d2) instead
//   of the original 1-cycle delay. Without this fix, PEs accumulate garbage
//   data in the first cycle when the BRAM output is not yet valid.
//
// Port description:
//   clk        - 100 MHz system clock
//   rst_n      - active-low synchronous reset
//   start      - 1-cycle pulse to begin computation (mode must be stable)
//   mode       - 0 = 16x16, 1 = four 8x8, must be stable at start pulse
//   we         - write enable for loading operands
//   mem_sel    - 0 = write to A banks, 1 = write to B banks
//   bank_sel   - which of the 32 banks to write (one-hot decoded internally)
//   wr_addr    - address within the selected bank to write
//   data_in    - 8-bit data byte to write
//   done       - registered version of controller done pulse
//   rd_ready   - high when result BRAM is filled and safe to read
//   rd_addr    - result address to read (0..255, = row*16 + col)
//   rd_data    - 32-bit result at rd_addr (registered, 1-cycle latency)
//
// Parameters:
//   DW    - data width of operands (8)
//   AW    - accumulator width (32)
//   DEPTH - BRAM depth per bank (32, must be >= 2*N-1 = 31 for N=16)
//   BANKS - number of BRAM banks (32)
// =============================================================================

`timescale 1ns/1ps

module systolic_16x16_fpga #(
    parameter DW    = 8,
    parameter AW    = 32,
    parameter DEPTH = 32,
    parameter BANKS = 32
)(
    input  wire                      clk,
    input  wire                      rst_n,
    input  wire                      start,
    input  wire                      mode,
    input  wire                      we,
    input  wire                      mem_sel,
    input  wire [4:0]                bank_sel,
    input  wire [$clog2(DEPTH)-1:0]  wr_addr,
    input  wire [DW-1:0]             data_in,
    output reg                       done,
    output wire                      rd_ready,
    input  wire [7:0]                rd_addr,
    output wire [AW-1:0]             rd_data
);

    localparam ADDR_W = $clog2(DEPTH);

    // Internal signals
    wire                       en, clr, done_internal;
    wire [ADDR_W-1:0]          rp;
    wire [(BANKS*ADDR_W)-1:0]  addr_a, addr_b;
    wire [BANKS-1:0]           m_comb_a, m_comb_b;
    wire [(BANKS*DW)-1:0]      ma_raw, mb_raw;
    wire [(256*AW)-1:0]        c_flat;

    // 2-stage valid mask pipeline to match 2-cycle BRAM output latency
    reg [BANKS-1:0] m_d1_a, m_d1_b;  // Stage 1 delay
    reg [BANKS-1:0] m_d2_a, m_d2_b;  // Stage 2 delay (added to fix timing alignment)
    reg [15:0]      v_rows;            // shift register for valid token injection

    // IOB-registered write interface
    wire we_r, mem_sel_r;
    wire [4:0]    bank_sel_r;
    wire [ADDR_W-1:0] wr_addr_r;
    wire [DW-1:0] data_in_r;

    write_iob_reg #(.DW(DW), .AW(ADDR_W)) wr_iob (
        .clk         (clk),
        .we_in       (we),       .mem_sel_in  (mem_sel),
        .bank_sel_in (bank_sel), .wr_addr_in  (wr_addr),
        .data_in     (data_in),
        .we_out      (we_r),     .mem_sel_out (mem_sel_r),
        .bank_sel_out(bank_sel_r),.wr_addr_out(wr_addr_r),
        .data_out    (data_in_r)
    );

    // Valid mask 2-stage pipeline and valid token row shift register
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_d1_a <= 0; m_d1_b <= 0;
            m_d2_a <= 0; m_d2_b <= 0;
            v_rows <= 0;
        end else begin
            m_d1_a <= m_comb_a;
            m_d1_b <= m_comb_b;
            m_d2_a <= m_d1_a;   // 2nd pipeline stage aligns with rdata_q in BRAM
            m_d2_b <= m_d1_b;
            // Shift valid token into rows - en && !clr means compute phase is active
            v_rows <= {v_rows[14:0], (en && !clr)};
        end
    end

    // Register done_internal to add one cycle of output stability
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) done <= 1'b0;
        else        done <= done_internal;
    end

    // In Mode 1, mirror the lower 8 rows' valid tokens to the upper 8 rows
    // so all four quadrants start their wavefronts simultaneously
    wire [15:0] v_in_rows_muxed;
    assign v_in_rows_muxed = mode ? {v_rows[7:0], v_rows[7:0]} : v_rows;

    // Apply 2-cycle delayed valid mask to gate BRAM output
    // This prevents garbage data from reaching the PEs while BRAM is settling
    wire [(BANKS*DW)-1:0] a_masked, b_masked;
    genvar g;
    generate
        for (g = 0; g < BANKS; g = g + 1) begin : mask
            assign a_masked[g*DW +: DW] = m_d2_a[g] ? ma_raw[g*DW +: DW] : {DW{1'b0}};
            assign b_masked[g*DW +: DW] = m_d2_b[g] ? mb_raw[g*DW +: DW] : {DW{1'b0}};
        end
    endgenerate

    // Write decode: one-hot bank select for A and B separately
    wire [BANKS-1:0] we_a_dec, we_b_dec;
    wire [(BANKS*ADDR_W)-1:0] wr_addr_bus;
    wire [(BANKS*DW)-1:0]     wr_data_bus;
    genvar bd, wb;
    generate
        for (bd = 0; bd < BANKS; bd = bd + 1) begin : wr_decode
            assign we_a_dec[bd] = we_r && !mem_sel_r && (bank_sel_r == bd[4:0]);
            assign we_b_dec[bd] = we_r &&  mem_sel_r && (bank_sel_r == bd[4:0]);
        end
        for (wb = 0; wb < BANKS; wb = wb + 1) begin : wr_bus
            assign wr_addr_bus[wb*ADDR_W +: ADDR_W] = wr_addr_r;
            assign wr_data_bus[wb*DW     +: DW]     = data_in_r;
        end
    endgenerate

    // Controller
    ctrl_16x16 #(
        .DEPTH(DEPTH), .CLR_CYCLES(4),
        .DRAIN_0(21), .DRAIN_1(14), .KEFF1(14)
    ) ctrl (
        .clk(clk), .rst_n(rst_n), .start(start), .mode(mode),
        .en(en), .clr(clr), .done(done_internal), .rd_ptr(rp)
    );

    // AGU for A and B (separate instances, same parameters)
    agu_16x16 #(.BANKS(BANKS), .DEPTH(DEPTH), .STAGGER_MOD(8)) agu_a (
        .rd_ptr(rp), .mode(mode), .en_active(en),
        .addr_bus(addr_a), .valid_mask(m_comb_a)
    );
    agu_16x16 #(.BANKS(BANKS), .DEPTH(DEPTH), .STAGGER_MOD(8)) agu_b (
        .rd_ptr(rp), .mode(mode), .en_active(en),
        .addr_bus(addr_b), .valid_mask(m_comb_b)
    );

    // Operand memory banks for A
    mem_bank_16x16 #(.DW(DW), .DEPTH(DEPTH), .BANKS(BANKS)) mem_a (
        .clk(clk),
        .we(we_a_dec),
        .addr_bus(we_r && !mem_sel_r ? wr_addr_bus : addr_a),
        .din(wr_data_bus),
        .dout(ma_raw)
    );

    // Operand memory banks for B
    mem_bank_16x16 #(.DW(DW), .DEPTH(DEPTH), .BANKS(BANKS)) mem_b (
        .clk(clk),
        .we(we_b_dec),
        .addr_bus(we_r && mem_sel_r ? wr_addr_bus : addr_b),
        .din(wr_data_bus),
        .dout(mb_raw)
    );

    // 16x16 PE array
    array_16x16 #(.DW(DW), .AW(AW)) arr (
        .clk      (clk),
        .rst_n    (rst_n),
        .clear    (clr),
        .mode     (mode),
        .v_in_rows(v_in_rows_muxed),
        .a_bus    (a_masked),
        .b_bus    (b_masked),
        .c_out_flat(c_flat)
    );

    // Result BRAM: captures PE outputs and provides sequential readout
    result_bram_16x16 #(.N(256), .AW(AW)) rbram (
        .clk        (clk),
        .rst_n      (rst_n),
        .done       (done_internal),
        .start      (start),
        .result_flat(c_flat),
        .rd_ready   (rd_ready),
        .rd_addr    (rd_addr),
        .rd_data    (rd_data)
    );

endmodule
