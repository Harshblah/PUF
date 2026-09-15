//=============================================================================
// pdro_puf_top.v  (FIXED)
//
// Key change: both event_counter instances now receive .clear(start).
//
// This ensures counter0 and counter1 are asynchronously reset to 0 at
// the beginning of every challenge evaluation before osc_enable rises,
// so each challenge is measured independently with no carry-over counts
// from the previous challenge.
//
// See event_counter.v for the full explanation of why async clear is
// safe here (rings are stopped when start fires).
//=============================================================================
`timescale 1ns/1ps

module pdro_puf_top #(
    parameter integer N          = 32,
    parameter integer SEL_BITS   = 5,
    parameter integer NUM_INV    = 5,
    parameter integer DIV_STAGES = 2,
    parameter integer CNT_WIDTH  = 16,
    parameter integer ACQ_WIDTH  = 32
) (
    input  wire                   clk,
    input  wire                   rst,
    input  wire                   start,
    input  wire [4*SEL_BITS-1:0]  challenge,
    input  wire [ACQ_WIDTH-1:0]   acq_cycles,
    output wire                   response,
    output wire                   valid,
    output wire                   busy
);

    // ── Challenge decode ──────────────────────────────────────────────────
    wire [SEL_BITS-1:0] target_sel0 = challenge[1*SEL_BITS-1 -: SEL_BITS];
    wire [SEL_BITS-1:0] ref_sel0    = challenge[2*SEL_BITS-1 -: SEL_BITS];
    wire [SEL_BITS-1:0] target_sel1 = challenge[3*SEL_BITS-1 -: SEL_BITS];
    wire [SEL_BITS-1:0] ref_sel1    = challenge[4*SEL_BITS-1 -: SEL_BITS];

    // ── Acquisition control ───────────────────────────────────────────────
    wire osc_enable, sample;

    acquisition_ctrl #(
        .CNT_WIDTH(ACQ_WIDTH)
    ) u_ctrl (
        .clk       (clk),
        .rst       (rst),
        .start     (start),
        .acq_cycles(acq_cycles),
        .osc_enable(osc_enable),
        .sample    (sample),
        .busy      (busy),
        .valid     (valid)
    );

    // ── BLOCK 0 / BLOCK 1 RO arrays ───────────────────────────────────────
    wire T0_raw, R0_raw, T1_raw, R1_raw;

    ro_block #(.N(N), .SEL_BITS(SEL_BITS), .NUM_INV(NUM_INV)) u_block0 (
        .rst       (rst),
        .osc_enable(osc_enable),
        .target_sel(target_sel0),
        .ref_sel   (ref_sel0),
        .target_clk(T0_raw),
        .ref_clk   (R0_raw)
    );

    ro_block #(.N(N), .SEL_BITS(SEL_BITS), .NUM_INV(NUM_INV)) u_block1 (
        .rst       (rst),
        .osc_enable(osc_enable),
        .target_sel(target_sel1),
        .ref_sel   (ref_sel1),
        .target_clk(T1_raw),
        .ref_clk   (R1_raw)
    );

    // ── Extra /4 dividers (Fig. 2) ────────────────────────────────────────
    wire T0, R0, T1, R1;

    clk_divider #(.STAGES(DIV_STAGES)) u_divT0 (.clk_in(T0_raw), .rst(rst), .clk_out(T0));
    clk_divider #(.STAGES(DIV_STAGES)) u_divR0 (.clk_in(R0_raw), .rst(rst), .clk_out(R0));
    clk_divider #(.STAGES(DIV_STAGES)) u_divT1 (.clk_in(T1_raw), .rst(rst), .clk_out(T1));
    clk_divider #(.STAGES(DIV_STAGES)) u_divR1 (.clk_in(R1_raw), .rst(rst), .clk_out(R1));

    // ── PD0 : Target=T0, Ref=R1  →  Counter 0 ───────────────────────────
    wire pd0_out;
    phase_detector u_pd0 (
        .target_clk(T0), .ref_clk(R1), .rst(rst), .pd_out(pd0_out)
    );

    wire [CNT_WIDTH-1:0] counter0;
    event_counter #(.WIDTH(CNT_WIDTH)) u_cnt0 (
        .clk     (R1),
        .rst     (rst),
        .clear   (start),       // FIXED: clear counter at start of every challenge
        .enable  (osc_enable),
        .event_in(pd0_out),
        .count   (counter0)
    );

    // ── PD1 : Target=T1, Ref=R0  →  Counter 1 ───────────────────────────
    wire pd1_out;
    phase_detector u_pd1 (
        .target_clk(T1), .ref_clk(R0), .rst(rst), .pd_out(pd1_out)
    );

    wire [CNT_WIDTH-1:0] counter1;
    event_counter #(.WIDTH(CNT_WIDTH)) u_cnt1 (
        .clk     (R0),
        .rst     (rst),
        .clear   (start),       // FIXED: clear counter at start of every challenge
        .enable  (osc_enable),
        .event_in(pd1_out),
        .count   (counter1)
    );

    // ── Final comparator → 1-bit response ────────────────────────────────
    reg resp_reg;
    always @(posedge clk or posedge rst) begin
        if (rst)
            resp_reg <= 1'b0;
        else if (sample)
            resp_reg <= (counter0 > counter1) ? 1'b1 : 1'b0;
    end

    assign response = resp_reg;

endmodule
