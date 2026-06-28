# =============================================================================
# nexys4ddr_systolic.xdc
# Nexys 4 DDR (xc7a100tcsg324-1) pin constraints for systolic_16x16_fpga
#
# PORT MAPPING OVERVIEW
# ─────────────────────────────────────────────────────────────────────────────
# clk          → E3        100 MHz on-board oscillator
# rst_n        → C12       CPU_RESET pushbutton (active-low, has on-board pullup)
# start        → BTNC (N17) Centre pushbutton
# mode         → BTNU (M18) Up pushbutton
#
# we           → SW[0]  J15
# mem_sel      → SW[1]  L16
# bank_sel[4:0]→ SW[6:2]  (SW2=M13, SW3=R15, SW4=R17, SW5=T18, SW6=U18)
# wr_addr[4:0] → SW[11:7] (SW7=R13, SW8=T8, SW9=U8, SW10=R16, SW11=T13)
# data_in[7:0] → SW[15:8] (note: wr_addr and data_in are quasi-static/false-path,
#                           so sharing bank with remaining switches is safe)
#   data_in[0] → SW[8]  T8   (same as wr_addr upper overlap — load sequentially)
#   NOTE: wr_addr is 5-bit (DEPTH=32, $clog2=5), data_in 8-bit = 13 inputs.
#   SW[0..15] = 16 switches, more than enough.
#   Final mapping without overlap:
#     we           → SW[0]  J15
#     mem_sel      → SW[1]  L16
#     bank_sel[0]  → SW[2]  M13
#     bank_sel[1]  → SW[3]  R15
#     bank_sel[2]  → SW[4]  R17
#     bank_sel[3]  → SW[5]  T18
#     bank_sel[4]  → SW[6]  U18
#     wr_addr[0]   → SW[7]  R13
#     wr_addr[1]   → SW[8]  T8
#     wr_addr[2]   → SW[9]  U8
#     wr_addr[3]   → SW[10] R16
#     wr_addr[4]   → SW[11] T13
#     data_in[0]   → SW[12] H6
#     data_in[1]   → SW[13] U12
#     data_in[2]   → SW[14] U11
#     data_in[3]   → SW[15] V10
#     data_in[4..7]→ JC Pmod (lower nibble input, pins JC1..JC4)
#
# rd_addr[7:0] → JA Pmod header (JA1..JA4, JA7..JA10)
# done         → LED[0]  H17
# rd_ready     → LED[1]  K15
# rd_data[31:0]→ JB Pmod (8 pins) + JXADC Pmod (8 pins) + LED[15:2] (14 pins)
#                JB: rd_data[7:0]
#                JC lower: rd_data[11:8]  (4 pins, input side repurposed as output)
#                LED[15:2]: rd_data[13:0] (14 of 32 bits on LEDs for visual debug)
#                Full 32-bit readout: use rd_addr to step through and read on LEDs
#
# PRACTICAL NOTE: rd_data is 32 bits wide. The Nexys 4 DDR only has enough
# spare I/O to expose ~16 bits directly. The recommended approach for testing
# is to use rd_addr to select a 16-bit slice, display lower 16b on LEDs[15:0].
# For full 32-bit access, use a UART or the Pmod ports with external logic.
# This XDC exposes all 32 bits across JB (8 pins), JC (4 pins), and LEDs (14).
# You can also drive rd_data to fewer signals and OR/MUX for demo purposes.
# =============================================================================

# ── Clock ─────────────────────────────────────────────────────────────────────
set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports { clk }];
create_clock -period 10.000 -name clk -waveform {0.000 5.000} [get_ports clk]

# ── Reset (CPU_RESET, active-low, external 4k7 pullup, Bank 15) ───────────────
set_property -dict { PACKAGE_PIN C12   IOSTANDARD LVCMOS33 } [get_ports { rst_n }];

# ── Control Pushbuttons ───────────────────────────────────────────────────────
# BTNC = centre = start
set_property -dict { PACKAGE_PIN N17   IOSTANDARD LVCMOS33 } [get_ports { start }];
# BTNU = up = mode
set_property -dict { PACKAGE_PIN M18   IOSTANDARD LVCMOS33 } [get_ports { mode }];

# ── Write-interface switches (quasi-static / false-path) ──────────────────────
# we
set_property -dict { PACKAGE_PIN J15   IOSTANDARD LVCMOS33 } [get_ports { we }];       ;# SW[0]
# mem_sel
set_property -dict { PACKAGE_PIN L16   IOSTANDARD LVCMOS33 } [get_ports { mem_sel }];  ;# SW[1]
# bank_sel[4:0]
set_property -dict { PACKAGE_PIN M13   IOSTANDARD LVCMOS33 } [get_ports { bank_sel[0] }]; ;# SW[2]
set_property -dict { PACKAGE_PIN R15   IOSTANDARD LVCMOS33 } [get_ports { bank_sel[1] }]; ;# SW[3]
set_property -dict { PACKAGE_PIN R17   IOSTANDARD LVCMOS33 } [get_ports { bank_sel[2] }]; ;# SW[4]
set_property -dict { PACKAGE_PIN T18   IOSTANDARD LVCMOS33 } [get_ports { bank_sel[3] }]; ;# SW[5]
set_property -dict { PACKAGE_PIN U18   IOSTANDARD LVCMOS33 } [get_ports { bank_sel[4] }]; ;# SW[6]
# wr_addr[4:0]  ($clog2(DEPTH=32) = 5 bits)
set_property -dict { PACKAGE_PIN R13   IOSTANDARD LVCMOS33 } [get_ports { wr_addr[0] }];  ;# SW[7]
set_property -dict { PACKAGE_PIN T8    IOSTANDARD LVCMOS33 } [get_ports { wr_addr[1] }];  ;# SW[8]
set_property -dict { PACKAGE_PIN U8    IOSTANDARD LVCMOS33 } [get_ports { wr_addr[2] }];  ;# SW[9]
set_property -dict { PACKAGE_PIN R16   IOSTANDARD LVCMOS33 } [get_ports { wr_addr[3] }];  ;# SW[10]
set_property -dict { PACKAGE_PIN T13   IOSTANDARD LVCMOS33 } [get_ports { wr_addr[4] }];  ;# SW[11]
# data_in[7:0]  — lower nibble on SW[12..15], upper nibble on JC lower row
set_property -dict { PACKAGE_PIN H6    IOSTANDARD LVCMOS33 } [get_ports { data_in[0] }];  ;# SW[12]
set_property -dict { PACKAGE_PIN U12   IOSTANDARD LVCMOS33 } [get_ports { data_in[1] }];  ;# SW[13]
set_property -dict { PACKAGE_PIN U11   IOSTANDARD LVCMOS33 } [get_ports { data_in[2] }];  ;# SW[14]
set_property -dict { PACKAGE_PIN V10   IOSTANDARD LVCMOS33 } [get_ports { data_in[3] }];  ;# SW[15]
# data_in[7:4] on JC Pmod lower row (pins 1-4 = K1, F6, J2, G6)
set_property -dict { PACKAGE_PIN K1    IOSTANDARD LVCMOS33 } [get_ports { data_in[4] }];  ;# JC[1]
set_property -dict { PACKAGE_PIN F6    IOSTANDARD LVCMOS33 } [get_ports { data_in[5] }];  ;# JC[2]
set_property -dict { PACKAGE_PIN J2    IOSTANDARD LVCMOS33 } [get_ports { data_in[6] }];  ;# JC[3]
set_property -dict { PACKAGE_PIN G6    IOSTANDARD LVCMOS33 } [get_ports { data_in[7] }];  ;# JC[4]

# ── rd_addr[7:0] — JA Pmod header ────────────────────────────────────────────
# JA pins 1-4 (lower row) and 7-10 (upper row)
set_property -dict { PACKAGE_PIN C17   IOSTANDARD LVCMOS33 } [get_ports { rd_addr[0] }];  ;# JA[1]
set_property -dict { PACKAGE_PIN D18   IOSTANDARD LVCMOS33 } [get_ports { rd_addr[1] }];  ;# JA[2]
set_property -dict { PACKAGE_PIN E18   IOSTANDARD LVCMOS33 } [get_ports { rd_addr[2] }];  ;# JA[3]
set_property -dict { PACKAGE_PIN G17   IOSTANDARD LVCMOS33 } [get_ports { rd_addr[3] }];  ;# JA[4]
set_property -dict { PACKAGE_PIN D17   IOSTANDARD LVCMOS33 } [get_ports { rd_addr[4] }];  ;# JA[7]
set_property -dict { PACKAGE_PIN E17   IOSTANDARD LVCMOS33 } [get_ports { rd_addr[5] }];  ;# JA[8]
set_property -dict { PACKAGE_PIN F18   IOSTANDARD LVCMOS33 } [get_ports { rd_addr[6] }];  ;# JA[9]
set_property -dict { PACKAGE_PIN G18   IOSTANDARD LVCMOS33 } [get_ports { rd_addr[7] }];  ;# JA[10]

# ── Status outputs ────────────────────────────────────────────────────────────
set_property -dict { PACKAGE_PIN H17   IOSTANDARD LVCMOS33 } [get_ports { done }];      ;# LED[0]
set_property -dict { PACKAGE_PIN K15   IOSTANDARD LVCMOS33 } [get_ports { rd_ready }];  ;# LED[1]

# ── rd_data[31:0] ─────────────────────────────────────────────────────────────
# rd_data[7:0]  → JB Pmod (pins 1-4, 7-10)
set_property -dict { PACKAGE_PIN D14   IOSTANDARD LVCMOS33 } [get_ports { rd_data[0] }];  ;# JB[1]
set_property -dict { PACKAGE_PIN F16   IOSTANDARD LVCMOS33 } [get_ports { rd_data[1] }];  ;# JB[2]
set_property -dict { PACKAGE_PIN G16   IOSTANDARD LVCMOS33 } [get_ports { rd_data[2] }];  ;# JB[3]
set_property -dict { PACKAGE_PIN H14   IOSTANDARD LVCMOS33 } [get_ports { rd_data[3] }];  ;# JB[4]
set_property -dict { PACKAGE_PIN E16   IOSTANDARD LVCMOS33 } [get_ports { rd_data[4] }];  ;# JB[7]
set_property -dict { PACKAGE_PIN F13   IOSTANDARD LVCMOS33 } [get_ports { rd_data[5] }];  ;# JB[8]
set_property -dict { PACKAGE_PIN G13   IOSTANDARD LVCMOS33 } [get_ports { rd_data[6] }];  ;# JB[9]
set_property -dict { PACKAGE_PIN H16   IOSTANDARD LVCMOS33 } [get_ports { rd_data[7] }];  ;# JB[10]
# rd_data[11:8] → JC upper row (pins 7-10 = U1, V2, U2, V4)
set_property -dict { PACKAGE_PIN U1    IOSTANDARD LVCMOS33 } [get_ports { rd_data[8] }];  ;# JC[7]
set_property -dict { PACKAGE_PIN V2    IOSTANDARD LVCMOS33 } [get_ports { rd_data[9] }];  ;# JC[8]
set_property -dict { PACKAGE_PIN U2    IOSTANDARD LVCMOS33 } [get_ports { rd_data[10] }]; ;# JC[9]
set_property -dict { PACKAGE_PIN V4    IOSTANDARD LVCMOS33 } [get_ports { rd_data[11] }]; ;# JC[10]
# rd_data[15:12] → LED[5:2]  (visual debug - lower result nibbles)
set_property -dict { PACKAGE_PIN J13   IOSTANDARD LVCMOS33 } [get_ports { rd_data[12] }]; ;# LED[2]
set_property -dict { PACKAGE_PIN N14   IOSTANDARD LVCMOS33 } [get_ports { rd_data[13] }]; ;# LED[3]
set_property -dict { PACKAGE_PIN R18   IOSTANDARD LVCMOS33 } [get_ports { rd_data[14] }]; ;# LED[4]
set_property -dict { PACKAGE_PIN V17   IOSTANDARD LVCMOS33 } [get_ports { rd_data[15] }]; ;# LED[5]
# rd_data[31:16] → LED[15:6] + remaining LEDs (upper 16 bits, LED visual debug)
set_property -dict { PACKAGE_PIN U17   IOSTANDARD LVCMOS33 } [get_ports { rd_data[16] }]; ;# LED[6]
set_property -dict { PACKAGE_PIN U16   IOSTANDARD LVCMOS33 } [get_ports { rd_data[17] }]; ;# LED[7]
set_property -dict { PACKAGE_PIN V16   IOSTANDARD LVCMOS33 } [get_ports { rd_data[18] }]; ;# LED[8]
set_property -dict { PACKAGE_PIN T15   IOSTANDARD LVCMOS33 } [get_ports { rd_data[19] }]; ;# LED[9]
set_property -dict { PACKAGE_PIN U14   IOSTANDARD LVCMOS33 } [get_ports { rd_data[20] }]; ;# LED[10]
set_property -dict { PACKAGE_PIN T16   IOSTANDARD LVCMOS33 } [get_ports { rd_data[21] }]; ;# LED[11]
set_property -dict { PACKAGE_PIN V15   IOSTANDARD LVCMOS33 } [get_ports { rd_data[22] }]; ;# LED[12]
set_property -dict { PACKAGE_PIN V14   IOSTANDARD LVCMOS33 } [get_ports { rd_data[23] }]; ;# LED[13]
set_property -dict { PACKAGE_PIN V12   IOSTANDARD LVCMOS33 } [get_ports { rd_data[24] }]; ;# LED[14]
set_property -dict { PACKAGE_PIN V11   IOSTANDARD LVCMOS33 } [get_ports { rd_data[25] }]; ;# LED[15]
# rd_data[31:26] → JXADC Pmod lower row (6 pins: XA1P..XA3N)
# JXADC pins: 1=J3, 2=L3, 3=M2, 4=N2, 7=K3, 8=M3
set_property -dict { PACKAGE_PIN J3    IOSTANDARD LVCMOS33 } [get_ports { rd_data[26] }]; ;# JXADC[1]
set_property -dict { PACKAGE_PIN L3    IOSTANDARD LVCMOS33 } [get_ports { rd_data[27] }]; ;# JXADC[2]
set_property -dict { PACKAGE_PIN M2    IOSTANDARD LVCMOS33 } [get_ports { rd_data[28] }]; ;# JXADC[3]
set_property -dict { PACKAGE_PIN N2    IOSTANDARD LVCMOS33 } [get_ports { rd_data[29] }]; ;# JXADC[4]
set_property -dict { PACKAGE_PIN K3    IOSTANDARD LVCMOS33 } [get_ports { rd_data[30] }]; ;# JXADC[7]
set_property -dict { PACKAGE_PIN M3    IOSTANDARD LVCMOS33 } [get_ports { rd_data[31] }]; ;# JXADC[8]

# ── Timing constraints (carried over from original, unchanged) ─────────────────
set_input_delay -clock clk -max 1.000 [get_ports start]
set_input_delay -clock clk -min 0.000 [get_ports start]
set_input_delay -clock clk -max 1.000 [get_ports {rd_addr[*]}]
set_input_delay -clock clk -min 0.000 [get_ports {rd_addr[*]}]

set_false_path -from [get_ports rst_n]
set_false_path -from [get_ports we]
set_false_path -from [get_ports mem_sel]
set_false_path -from [get_ports {bank_sel[*]}]
set_false_path -from [get_ports {wr_addr[*]}]
set_false_path -from [get_ports {data_in[*]}]
set_false_path -from [get_ports mode]

set_false_path -to [get_ports done]
set_false_path -to [get_ports rd_ready]
set_false_path -to [get_ports {rd_data[*]}]

# ── FPGA Configuration ─────────────────────────────────────────────────────────
set_property CONFIG_VOLTAGE 3.3         [current_design]
set_property CFGBVS VCCO                [current_design]
set_property IOSTANDARD LVCMOS33        [get_ports *]
