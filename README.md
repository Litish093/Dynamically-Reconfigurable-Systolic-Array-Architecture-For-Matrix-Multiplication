
# Dynamically Reconfigurable Systolic Array for Parallel Matrix Multiplication on FPGA

A hardware accelerator for matrix multiplication implemented on a **Xilinx Artix-7 100T (Nexys 4 DDR)** board. The design supports two runtime-selectable modes via a single control bit — achieving **4.3× GEMM throughput improvement** for 8×8 workloads over a fixed baseline at only **5.11% power overhead**.

---

## Overview

Conventional systolic arrays are designed for fixed dimensions. When processing matrices smaller than the array size, a large fraction of processing elements (PEs) sit idle — wasting power and reducing efficiency. This is especially problematic in modern LLM inference, where tensor shapes vary widely across requests.

This project proposes a **Dynamically Reconfigurable Systolic Array (DRSA)**: a 16×16 architecture that switches at runtime between:

| Mode | Description | Latency | Throughput |
|------|-------------|---------|------------|
| **Mode 0** | One full 16×16 GEMM | 55 cycles | 1.82 M GEMM/s |
| **Mode 1** | Four independent 8×8 GEMMs in parallel | 31 cycles | 7.84 M GEMM/s |

No reconfiguration overhead — the switch takes effect at the next `start` pulse.

---

## Architecture

```
┌─────────────────────────────────────────────────┐
│                  Top Level (DRSA)               │
│                                                 │
│  ┌──────────┐   ┌──────────┐   ┌─────────────┐ │
│  │  ctrl_   │   │ agu_     │   │ mem_bank_   │ │
│  │  16x16   │──▶│ 16x16   │──▶│ 16x16 (A,B) │ │
│  │ (FSM)    │   │ (AGU)    │   │ 32×BRAM18   │ │
│  └──────────┘   └──────────┘   └─────────────┘ │
│                                      │          │
│                                      ▼          │
│                          ┌───────────────────┐  │
│                          │   array_16x16     │  │
│                          │  (256 PEs, 16×16) │  │
│                          └───────────────────┘  │
│                                      │          │
│                                      ▼          │
│                          ┌───────────────────┐  │
│                          │ result_bram_16x16 │  │
│                          └───────────────────┘  │
└─────────────────────────────────────────────────┘
```

### Key Sub-modules

**Processing Element (`pe_16x16`)**
Each PE is a 3-stage pipelined MAC cell:
- Stage 1 — registers 8-bit inputs `a_in`, `b_in`
- Stage 2 — computes 16-bit product
- Stage 3 — conditionally accumulates into a 32-bit output register

A synchronous `clear` input resets the accumulator without any asynchronous path, simplifying timing closure. Data flows right (A) and down (B) to neighbouring PEs.

**Systolic Controller (`ctrl_16x16`)**
Three-phase FSM:
1. **Clear phase** (4 cycles) — flushes all PE accumulators via `clr`
2. **Compute phase** — asserts `en`, increments `rd_ptr` from 0 to K_eff
3. **Drain phase** — flushes pipeline, then asserts `done`

Mode-dependent parameters latched at `start`:
- Mode 0: K_eff = 31, Drain = 20 → done at cycle 55
- Mode 1: K_eff = 14, Drain = 13 → done at cycle 31

**Address Generation Unit (`agu_16x16`)**
Generates staggered read addresses to align operand wavefronts at PE boundaries. Supports dual stagger moduli:
- Mode 0: `addr[k] = rd_ptr − k` (S = 16)
- Mode 1: `addr[k] = rd_ptr − (k mod 8)` (S = 8)

A `valid_mask[k]` gates each bank's output to zero until its wavefront arrives.

**Mode-1 Quadrant Isolation**
Inter-quadrant wires at the column-8 and row-8 boundaries are zeroed:
- `h_wire[i][8] = 0` for all rows i ∈ [0,7]
- `v_wire[8][j] = 0` for all cols j ∈ [0,7]

This creates four fully independent 8×8 sub-arrays (Q1–Q4) with no logic added to the PE itself.

**Operand Memory (`mem_bank_16x16`)**
- 32 single-port BRAM18 banks, each 8-bit wide × depth 32
- Serial load interface: 1 byte/cycle with 5-bit `bank_sel`, 5-bit `wr_addr`, `mem_sel` (A or B), `data_in`
- One-hot write-enable decoder per bank

---

## Results

### Resource Utilisation (Artix-7 100T, post-synthesis)

| Resource | Baseline | DRSA | Available | Overhead |
|----------|----------|------|-----------|----------|
| Slice LUTs | 34,220 | 36,303 | 63,400 | +6.08% |
| Slice Registers | 16,591 | 24,772 | 126,800 | +49.3% |
| F7/F8 Muxes | 0 | 3,264 | 47,550 | — |
| BRAM Tiles | 32 | 32 | 135 | 0% |
| DSP48E1 | 0 | 0 | 240 | 0% |

> The register increase comes from the mirrored valid-token bus, mode-aware AGU stagger registers, and registered result-MUX paths. No DSP slices are used — multipliers map to LUT-carry chains, appropriate for 8-bit operands.

### Timing

| Metric | Value |
|--------|-------|
| Clock frequency | 100 MHz |
| WNS | +0.25 ns |
| Critical path | 8-bit multiplier → 32-bit adder → 2× MUX (AGU) |

### Power (post-synthesis, 100 MHz, 25°C)

| Component | Baseline (W) | DRSA (W) |
|-----------|-------------|---------|
| Clocks | 0.069 | 0.078 |
| Slice Logic | 0.007 | 0.008 |
| Signals | 0.004 | 0.005 |
| Block RAM | 0.063 | 0.065 |
| Dynamic Total | 0.149 | 0.157 |
| Device Static | 0.099 | 0.099 |
| **Total On-Chip** | **0.243 W** | **0.255 W** |
| **Overhead** | — | **+5.11%** |

### Performance vs. Baseline

| Metric | Baseline | DRSA | Change |
|--------|----------|------|--------|
| Latency (cycles) | 55 | 31 | −43.6% |
| Throughput (M GEMM/s) | 1.82 | 7.84 | **+436%** |
| Compute (GOPS) | 0.942 | 0.942 | 0% |
| Total Power (W) | 0.243 | 0.255 | +5.11% |

> Raw compute throughput (GOPS) is identical in both modes since all 256 PEs remain active throughout.

---

## Tools & Target

| Item | Detail |
|------|--------|
| HDL | Verilog-2001 |
| Tool | Xilinx Vivado 2025.1 |
| Target device | Artix-7 100T (`xc7a100tfgg484-2I`, speed grade −2I) |
| Board | Nexys 4 DDR |
| Clock | 10 ns (100 MHz) |
| Verification | SystemVerilog testbench + software golden model |
| Debug | Xilinx VIO + ILA (JTAG in-system debug) |
| Power analysis | SAIF activity file from simulation (Vivado confidence: Medium) |

---

## Verification

Functional correctness is verified using a SystemVerilog testbench that:
- Computes a software golden reference for both modes
- Compares all 256 output elements per operating mode
- Tests back-to-back mode switches at cycle boundaries
- Covers all edge cases including boundary PEs at quadrant isolation lines

In-system validation was performed using **Xilinx VIO** (to drive inputs and mode control) and **ILA** (to capture output data), confirming hardware matches simulation results.

---

## Repository Structure

```
├── src/
│   ├── pe_16x16.v              # Processing Element
│   ├── array_16x16.v           # 16×16 PE array
│   ├── ctrl_16x16.v            # Systolic controller FSM
│   ├── agu_16x16.v             # Address Generation Unit
│   ├── mem_bank_16x16.v        # Operand memory (BRAM banks)
│   ├── result_bram_16x16.v     # Result buffer
│   └── top_drsa.v              # Top-level integration
├── tb/
│   └── tb_drsa.sv              # SystemVerilog testbench
├── constraints/
│   └── drsa.xdc                # Timing and pin constraints
├── paper/
│   └── DRSA_VDAT.pdf           # Conference paper
└── README.md
```

---

## How It Works — Data Flow

```
Load Phase:
  data_in → [bank_sel decoder] → BRAM bank (A or B)

Compute Phase (Mode 0 — 16×16):
  AGU generates staggered addresses (S=16)
  A flows →→→ across all 16 columns
  B flows ↓↓↓ across all 16 rows
  Each PE[i][j] accumulates at time t = i + j

Compute Phase (Mode 1 — four 8×8):
  AGU uses S=8, mirrored valid-token bus
  Boundary wires zeroed at col-8 and row-8
  Q1, Q2, Q3, Q4 compute simultaneously and independently
  Each sub-array completes in 31 cycles vs 55 for Mode 0
```

---

## Related Work

This design addresses a gap in existing literature: no prior work simultaneously demonstrates runtime mode switching between a full-array GEMM and a partitioned multi-GEMM with a serial I/O-efficient load interface and simulation-verified correctness on a resource-constrained Artix-7, all within a single unified architecture.

Related prior art includes:
- Google TPU: 256×256 weight-stationary systolic array for DL inference
- MAERI (Kwon et al., 2018): flexible dataflow via reconfigurable interconnects
- ISARA (Yang et al., 2025): island-style reconfigurable accelerator using memristors

---

## Future Work

- Support for three or more partition levels (e.g., 16×16 / 8×8 / 4×4)
- Port to higher-density **UltraScale+** devices targeting transformer attention kernels
- Batched LLM decoding workloads with variable tensor shapes

---

## Paper

This project is accompanied by a conference paper submitted to **VDAT 2025**:

> *A Dynamically Reconfigurable Systolic Array Architecture for Parallel Matrix Multiplication on FPGA*
