//=============================================================================
// clk_divider.v
//
// Cascaded divide-by-2 stages. Fig. 2 ("Timing diagram of the phase
// detecting block") shows each oscillator output further divided down
// through /2 and /4 stages (CLKtarget, CLKtarget/2, CLKtarget/4 and the
// same for CLKref) before being fed into the phase detector. This module
// implements that additional division (STAGES=2 => an extra /4 on top of
// the /2 already done inside ro_cell, matching Fig. 2).
//
// Like ro_cell's internal divider, every stage here is clocked by a
// free-running, asynchronous (non-static-timing) signal -- this is
// expected for RO-PUF designs.
//=============================================================================
`timescale 1ns/1ps

module clk_divider #(
    parameter integer STAGES = 2   // number of extra /2 stages (2 => /4 total)
) (
    input  wire clk_in,
    input  wire rst,
    output wire clk_out
);

    wire [STAGES:0] stage;
    assign stage[0] = clk_in;

    genvar i;
    generate
        for (i = 0; i < STAGES; i = i + 1) begin : DIV_STAGE
            reg q;
            always @(posedge stage[i] or posedge rst) begin
                if (rst)
                    q <= 1'b0;
                else
                    q <= ~q;
            end
            assign stage[i+1] = q;
        end
    endgenerate

    assign clk_out = stage[STAGES];

endmodule
