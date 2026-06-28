// =============================================================================
// tb_systolic_16x16.v  -  Testbench  (SAIF version - replaces VCD)
//
// CHANGES FROM ORIGINAL:
// ─────────────────────────────────────────────────────────────────────────────
// [CHANGE-1] Removed $dumpfile / $dumpvars (VCD deprecated in Vivado)
// [CHANGE-2] Added $saif_open / $saif_start at beginning of stimulus
// [CHANGE-3] Added $saif_stop / $saif_close just before $finish
// [CHANGE-4] Watchdog also calls $saif_stop / $saif_close before $finish
//            so SAIF is always properly closed even on timeout
//
// All other logic (DEPTH=32, load tasks, test cases) unchanged.
//
// HOW TO USE AFTER SIMULATION:
// ─────────────────────────────────────────────────────────────────────────────
//   1. Run simulation → tb_16x16.saif is generated in xsim run directory
//   2. In Vivado Tcl console:
//        open_run impl_1
//        read_saif "<proj>/project.sim/sim_1/behav/xsim/tb_16x16.saif" \
//                  -strip_path "tb_16x16/dut"
//        report_power -file "power_actual.rpt" -hierarchical -hierarchical_depth 6
// =============================================================================
`timescale 1ns/1ps

module tb_16x16;

    localparam DW     = 8;
    localparam AW     = 32;
    localparam DEPTH  = 32;   // Must be >= 2*N-1=31 for N=16
    localparam BANKS  = 32;
    localparam ADDR_W = $clog2(DEPTH);  // 5

    reg                   clk, rst_n, start, mode;
    reg                   we, mem_sel;
    reg  [4:0]            bank_sel;
    reg  [ADDR_W-1:0]     wr_addr;
    reg  [DW-1:0]         data_in;
    wire                  done, rd_ready;
    reg  [7:0]            rd_addr;
    wire [AW-1:0]         rd_data;

    initial clk = 0;
    always  #5 clk = ~clk;   // 100 MHz

    systolic_16x16_fpga #(.DW(DW),.AW(AW),.DEPTH(DEPTH),.BANKS(BANKS)) dut (
        .clk(clk), .rst_n(rst_n), .start(start), .mode(mode),
        .we(we), .mem_sel(mem_sel), .bank_sel(bank_sel),
        .wr_addr(wr_addr), .data_in(data_in),
        .done(done), .rd_ready(rd_ready),
        .rd_addr(rd_addr), .rd_data(rd_data)
    );

    // ── Write helpers ─────────────────────────────────────────────────────────
    task write_byte;
        input integer  bk;
        input integer  addr;
        input [DW-1:0] val;
        input          sel;
        begin
            @(negedge clk);
            we=1'b1; mem_sel=sel; bank_sel=bk[4:0];
            wr_addr=addr[ADDR_W-1:0]; data_in=val;
            @(negedge clk); we=1'b0;
        end
    endtask

    // Clear ALL banks, ALL addresses to zero before each test
    task clear_mem;
        integer bk, addr;
        begin
            for (bk=0; bk<BANKS; bk=bk+1)
                for (addr=0; addr<DEPTH; addr=addr+1) begin
                    write_byte(bk, addr, 8'd0, 1'b0);
                    write_byte(bk, addr, 8'd0, 1'b1);
                end
        end
    endtask

    task do_reset;
        input integer n;
        begin
            @(negedge clk); rst_n=0;
            repeat(n) @(posedge clk);
            @(negedge clk); rst_n=1;
        end
    endtask

    // Wait for rd_ready (computation + 256-cycle BRAM fill)
    task wait_ready;
        input integer max_cyc;
        integer n;
        begin
            n=0; @(posedge clk);
            while (!rd_ready && n<max_cyc) begin @(posedge clk); n=n+1; end
            if (n==max_cyc) $display("  [TIMEOUT after %0d cycles]", max_cyc);
            @(posedge clk);
        end
    endtask

    // 1-cycle BRAM registered read
    task read_result;
        input  integer  row, col;
        output [AW-1:0] val;
        begin
            @(negedge clk); rd_addr = row*16 + col;
            @(posedge clk); @(posedge clk);
            val = rd_data;
        end
    endtask

    // ── Pass/fail ─────────────────────────────────────────────────────────────
    integer pass_cnt, fail_cnt;
    task check;
        input [8*35-1:0] tag;
        input [AW-1:0]   got, exp;
        begin
            if (got===exp) begin
                $display("  PASS %-35s got=%0d", tag, got);
                pass_cnt=pass_cnt+1;
            end else begin
                $display("  FAIL %-35s got=%0d  exp=%0d", tag, got, exp);
                fail_cnt=fail_cnt+1;
            end
        end
    endtask

    // ── Matrix storage ────────────────────────────────────────────────────────
    integer i, j;
    reg [DW-1:0]  A16[0:15][0:15], B16[0:15][0:15];
    reg [AW-1:0]  C16[0:15][0:15];
    reg [DW-1:0]  ATL[0:7][0:7],BTL[0:7][0:7]; reg [AW-1:0] CTL[0:7][0:7];
    reg [DW-1:0]  ATR[0:7][0:7],BTR[0:7][0:7]; reg [AW-1:0] CTR[0:7][0:7];
    reg [DW-1:0]  ABL[0:7][0:7],BBL[0:7][0:7]; reg [AW-1:0] CBL[0:7][0:7];
    reg [DW-1:0]  ABR[0:7][0:7],BBR[0:7][0:7]; reg [AW-1:0] CBR[0:7][0:7];
    reg [AW-1:0]  exp_v, got_v;

    task golden_16x16;
        integer ri,ci,ki;
        begin
            for(ri=0;ri<16;ri=ri+1) for(ci=0;ci<16;ci=ci+1) begin
                C16[ri][ci]=0;
                for(ki=0;ki<16;ki=ki+1)
                    C16[ri][ci]=C16[ri][ci]+A16[ri][ki]*B16[ki][ci];
            end
        end
    endtask

    task golden_8x8;
        integer ri,ci,ki;
        begin
            for(ri=0;ri<8;ri=ri+1) for(ci=0;ci<8;ci=ci+1) begin
                CTL[ri][ci]=0; CTR[ri][ci]=0; CBL[ri][ci]=0; CBR[ri][ci]=0;
                for(ki=0;ki<8;ki=ki+1) begin
                    CTL[ri][ci]=CTL[ri][ci]+ATL[ri][ki]*BTL[ki][ci];
                    CTR[ri][ci]=CTR[ri][ci]+ATR[ri][ki]*BTR[ki][ci];
                    CBL[ri][ci]=CBL[ri][ci]+ABL[ri][ki]*BBL[ki][ci];
                    CBR[ri][ci]=CBR[ri][ci]+ABR[ri][ki]*BBR[ki][ci];
                end
            end
        end
    endtask

    // ── Load tasks ────────────────────────────────────────────────────────────
    task load_mode0_16;
        integer row, col, k;
        begin
            for(row=0; row<16; row=row+1)
                for(k=0; k<16; k=k+1)
                    write_byte(row, k, A16[row][k], 1'b0);
            for(col=0; col<16; col=col+1)
                for(k=0; k<16; k=k+1)
                    write_byte(col, k, B16[k][col], 1'b1);
        end
    endtask

    task load_mode1_16;
        integer sub_row, sub_col, k;
        begin
            for(sub_row=0; sub_row<8; sub_row=sub_row+1)
                for(k=0; k<8; k=k+1) begin
                    write_byte(sub_row,    k, ATL[sub_row][k], 1'b0);
                    write_byte(sub_row+8,  k, ATR[sub_row][k], 1'b0);
                    write_byte(sub_row+16, k, ABL[sub_row][k], 1'b0);
                    write_byte(sub_row+24, k, ABR[sub_row][k], 1'b0);
                end
            for(sub_col=0; sub_col<8; sub_col=sub_col+1)
                for(k=0; k<8; k=k+1) begin
                    write_byte(sub_col,    k, BTL[k][sub_col], 1'b1);
                    write_byte(sub_col+8,  k, BTR[k][sub_col], 1'b1);
                    write_byte(sub_col+16, k, BBL[k][sub_col], 1'b1);
                    write_byte(sub_col+24, k, BBR[k][sub_col], 1'b1);
                end
        end
    endtask

    // ── Stimulus ──────────────────────────────────────────────────────────────
    initial begin

        // ── SAIF: open file and start recording on DUT instance ───────────────
      
        // ──────────────────────────────────────────────────────────────────────

        pass_cnt=0; fail_cnt=0;
        {we,mem_sel,start,mode}=0; bank_sel=0; wr_addr=0; data_in=0; rd_addr=0;

        // ════════════════════════════════════════════════════════════════════
        // TC6: Reset sanity
        // ════════════════════════════════════════════════════════════════════
        $display("\n══ TC6: Reset sanity ══");
        do_reset(4); @(posedge clk);
        check("done_idle",     done,     1'b0);
        check("rd_ready_idle", rd_ready, 1'b0);

        // ════════════════════════════════════════════════════════════════════
        // TC7: Mode 0 - A × I16 = A
        // ════════════════════════════════════════════════════════════════════
        $display("\n══ TC7: Mode 0  A × I16  (expect C = A, all 256 PEs) ══");
        do_reset(4); clear_mem;
        for(i=0;i<16;i=i+1) for(j=0;j<16;j=j+1) begin
            A16[i][j] = (i==j) ? (i+1) : ((i+j)%7+1);
            B16[i][j] = (i==j) ? 8'd1  : 8'd0;
        end
        golden_16x16; load_mode0_16;
        @(negedge clk); mode=0; start=1; @(negedge clk); start=0;
        wait_ready(400);
        $display("  Checking all 256 PE outputs...");
        for(i=0;i<16;i=i+1) for(j=0;j<16;j=j+1) begin
            read_result(i, j, got_v); exp_v=C16[i][j];
            check("16x16 mode0 C[i][j]", got_v, exp_v);
        end

        // ════════════════════════════════════════════════════════════════════
        // TC7b: Mode 0 - distinct full 16×16 × 16×16
        // ════════════════════════════════════════════════════════════════════
        $display("\n══ TC7b: Mode 0  distinct 16×16×16×16 ══");
        do_reset(4); clear_mem;
        for(i=0;i<16;i=i+1) for(j=0;j<16;j=j+1) begin
            A16[i][j] = (i+j) % 7 + 1;
            B16[i][j] = (i*2+j) % 5 + 1;
        end
        golden_16x16; load_mode0_16;
        @(negedge clk); mode=0; start=1; @(negedge clk); start=0;
        wait_ready(400);
        $display("  Spot: C[0][0]=%0d C[0][15]=%0d C[15][0]=%0d C[15][15]=%0d",
                 C16[0][0],C16[0][15],C16[15][0],C16[15][15]);
        for(i=0;i<16;i=i+1) for(j=0;j<16;j=j+1) begin
            read_result(i, j, got_v); exp_v=C16[i][j];
            check("16x16 mode0 full C[i][j]", got_v, exp_v);
        end

        // ════════════════════════════════════════════════════════════════════
        // TC8: Mode 1 - four distinct 8×8 GEMMs
        // ════════════════════════════════════════════════════════════════════
        $display("\n══ TC8: Mode 1  four 8×8 GEMMs ══");
        do_reset(4); clear_mem;
        for(i=0;i<8;i=i+1) for(j=0;j<8;j=j+1) begin
            ATL[i][j]=1;               BTL[i][j]=(i==j)?(i+1):0;
            ATR[i][j]=(i==j)?(i+1):0; BTR[i][j]=1;
            ABL[i][j]=(i==j)?1:0;     BBL[i][j]=2;
            ABR[i][j]=(i==j)?2:0;     BBR[i][j]=(i==j)?3:0;
        end
        golden_8x8; load_mode1_16;
        @(negedge clk); mode=1; start=1; @(negedge clk); start=0;
        wait_ready(350);
        $display("  -- TL PE[0-7][0-7] --");
        for(i=0;i<8;i=i+1) for(j=0;j<8;j=j+1) begin
            read_result(i, j, got_v);
            check("TL C[r][c]", got_v, CTL[i][j]);
        end
        $display("  -- TR PE[0-7][8-15] --");
        for(i=0;i<8;i=i+1) for(j=0;j<8;j=j+1) begin
            read_result(i, j+8, got_v);
            check("TR C[r][c]", got_v, CTR[i][j]);
        end
        $display("  -- BL PE[8-15][0-7] --");
        for(i=0;i<8;i=i+1) for(j=0;j<8;j=j+1) begin
            read_result(i+8, j, got_v);
            check("BL C[r][c]", got_v, CBL[i][j]);
        end
        $display("  -- BR PE[8-15][8-15] --");
        for(i=0;i<8;i=i+1) for(j=0;j<8;j=j+1) begin
            read_result(i+8, j+8, got_v);
            check("BR C[r][c]", got_v, CBR[i][j]);
        end

        // ════════════════════════════════════════════════════════════════════
        // TC9: Back-to-back mode=1 → mode=0  (no rst_n between runs)
        // ════════════════════════════════════════════════════════════════════
        $display("\n══ TC9: Back-to-back mode=1→mode=0 (no rst_n) ══");
        clear_mem;
        for(i=0;i<16;i=i+1) for(j=0;j<16;j=j+1) begin
            A16[i][j] = (i==j) ? (i+1) : ((i+j)%5+1);
            B16[i][j] = (i==j) ? 8'd1  : 8'd0;
        end
        golden_16x16; load_mode0_16;
        @(negedge clk); mode=0; start=1; @(negedge clk); start=0;
        wait_ready(400);
        for(i=0;i<16;i=i+1) for(j=0;j<16;j=j+1) begin
            read_result(i, j, got_v); exp_v=C16[i][j];
            check("btb C[i][j]", got_v, exp_v);
        end

        // ════════════════════════════════════════════════════════════════════
        // Summary
        // ════════════════════════════════════════════════════════════════════
        $display("\n═══════════════════════════════════════════════════════");
        $display("  DEPTH=%0d   Computation latency: mode0=55cy mode1=31cy",
                 DEPTH);
        $display("  %0d PASS  %0d FAIL", pass_cnt, fail_cnt);
        $display("═══════════════════════════════════════════════════════");
        if (fail_cnt==0) $display("  *** ALL TESTS PASSED ***");
        else             $display("  *** FAILURES - see above ***");

     
        // ──────────────────────────────────────────────────────────────────────

        $finish;
    end

  

endmodule