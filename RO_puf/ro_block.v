//=============================================================================
// ro_block.v
//
// One RO "BLOCK" from Fig. 1 (BLOCK 0 or BLOCK 1): an array of N identical
// ro_cell instances, plus the two select-muxes that pick:
//   - the cell used as this block's "target" oscillator   (Target_sel{0,1})
//   - the cell used as this block's "reference" oscillator (Ref_sel{0,1})
//
// Per Section II/III:
//   "we construct two RO blocks that are comprised of n identical RO
//    cells" ... "If we assume that one RO block consists of 32 RO cells,
//    n = 32, then we need 64 RO cells in the PDRO PUF."
//
// One instance of this module = one BLOCK (0 or 1). The top level
// (pdro_puf_top.v) instantiates two of these and cross-wires their
// target/reference outputs into PD0 / PD1, exactly as Fig. 1 shows.
//=============================================================================
`timescale 1ns/1ps

module ro_block #(
    parameter integer N        = 32,  // RO cells in this block (paper: n = 32)
    parameter integer SEL_BITS = 5,   // ceil(log2(N)) -- 5 bits selects 1-of-32
    parameter integer NUM_INV  = 5    // inverters per RO cell (paper: 5)
) (
    input  wire                rst,
    input  wire                osc_enable,
    input  wire [SEL_BITS-1:0] target_sel,  // selects this block's "target" cell
    input  wire [SEL_BITS-1:0] ref_sel,     // selects this block's "reference" cell
    output wire                target_clk,  // selected target cell's osc_clock/2
    output wire                ref_clk      // selected reference cell's osc_clock/2
);

    wire [N-1:0] cell_out;

    genvar i;
    generate
        for (i = 0; i < N; i = i + 1) begin : RO_CELLS
            (* DONT_TOUCH = "true" *)
            ro_cell #(
                .NUM_INV(NUM_INV)
            ) u_ro_cell (
                .enable      (osc_enable),
                .rst         (rst),
                .osc_clk_div2(cell_out[i])
            );
        end
    endgenerate

    // Mux pair for this block (Mux0/Mux2 for BLOCK0, Mux1/Mux3 for BLOCK1
    // in Fig. 1). Synthesis will map these onto the device's native wide
    // mux fabric (MUXFx / dedicated mux LUTs) automatically.
    assign target_clk = cell_out[target_sel];
    assign ref_clk     = cell_out[ref_sel];

endmodule
