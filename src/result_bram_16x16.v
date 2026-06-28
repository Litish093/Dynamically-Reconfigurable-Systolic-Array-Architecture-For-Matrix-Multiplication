// =============================================================================
// result_bram_16x16.v
// Result Buffer for the 16x16 Dynamically Reconfigurable Systolic Array
//
// After the systolic controller asserts done, the 256 PE accumulator values
// available on result_flat need to be stored for sequential readout.
// Reading them directly from PE registers would require a 256x32-bit bus
// to the outside world which isn't practical on an FPGA.
//
// This module solves that by:
//   1. Detecting the done pulse from the controller
//   2. Sequentially writing all 256 results into an inferred BRAM
//      (one result per cycle, takes 256 cycles to fill)
//   3. Asserting rd_ready when the fill is complete
//   4. Allowing the host to read results at any address via rd_addr / rd_data
//
// The result_flat input is a packed bus:
//   result_flat[(i*16+j)*AW +: AW] = PE[i][j].acc
//   index = i*16+j, so rd_addr = row*16 + col
//
// Parameters:
//   N  - number of results to store (256 for 16x16 array)
//   AW - accumulator width (32-bit)
// =============================================================================

`timescale 1ns/1ps

module result_bram_16x16 #(
    parameter N  = 256,
    parameter AW = 32
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  done,           // 1-cycle pulse from controller
    input  wire                  start,          // clears rd_ready for next run
    input  wire [(N*AW)-1:0]     result_flat,    // all 256 PE accumulator outputs
    output reg                   rd_ready,       // high when BRAM is filled and readable
    input  wire [$clog2(N)-1:0]  rd_addr,        // address to read (0..255)
    output reg  [AW-1:0]         rd_data         // registered read output
);

    localparam ADDR_W = $clog2(N);

    (* ram_style = "block" *)
    reg [AW-1:0] result_bram [0:N-1];

    reg               filling;   // high while writing results into BRAM
    reg [ADDR_W-1:0]  wr_cnt;    // current write address during fill

    // Fill state machine: triggered by done, writes 256 results sequentially
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            filling  <= 0;
            wr_cnt   <= 0;
            rd_ready <= 0;
        end else begin
            if (start) begin
                // Clear ready flag when a new computation starts
                rd_ready <= 1'b0;
                filling  <= 1'b0;
            end else if (done) begin
                // Start filling result BRAM
                filling <= 1'b1;
                wr_cnt  <= {ADDR_W{1'b0}};
            end else if (filling) begin
                result_bram[wr_cnt] <= result_flat[wr_cnt * AW +: AW];
                if (wr_cnt == N-1) begin
                    filling  <= 1'b0;
                    rd_ready <= 1'b1;  // signal to host that results are ready
                end else begin
                    wr_cnt <= wr_cnt + 1'b1;
                end
            end
        end
    end

    // 1-cycle registered read port
    always @(posedge clk)
        rd_data <= result_bram[rd_addr];

endmodule
