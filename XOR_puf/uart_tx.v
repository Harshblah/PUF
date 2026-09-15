`timescale 1ns / 1ps
//=====================================================================
// uart_tx.v - standard 8-N-1 UART transmitter
// Default CLKS_PER_BIT=868 -> 115200 baud @ 100 MHz (Basys 3 sys clk).
//=====================================================================
module uart_tx #(
    parameter CLKS_PER_BIT = 868
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       tx_start,
    input  wire [7:0] tx_data,
    output reg        tx_pin,
    output reg        tx_busy,
    output reg        tx_done
);
    localparam IDLE = 0, START = 1, DATA = 2, STOP = 3;

    reg [1:0]  state   = IDLE;
    reg [12:0] clk_cnt = 0;
    reg [2:0]  bit_idx = 0;
    reg [7:0]  data_latched;

    always @(posedge clk) begin
        if (rst) begin
            state   <= IDLE;
            tx_pin  <= 1'b1;
            tx_busy <= 1'b0;
            tx_done <= 1'b0;
            clk_cnt <= 0;
            bit_idx <= 0;
        end else begin
            tx_done <= 1'b0;
            case (state)
                IDLE: begin
                    tx_pin <= 1'b1;
                    if (tx_start) begin
                        data_latched <= tx_data;
                        tx_busy      <= 1'b1;
                        state        <= START;
                    end
                end

                START: begin
                    tx_pin <= 1'b0;
                    if (clk_cnt < CLKS_PER_BIT - 1) clk_cnt <= clk_cnt + 1;
                    else begin clk_cnt <= 0; state <= DATA; end
                end

                DATA: begin
                    tx_pin <= data_latched[bit_idx];
                    if (clk_cnt < CLKS_PER_BIT - 1) begin
                        clk_cnt <= clk_cnt + 1;
                    end else begin
                        clk_cnt <= 0;
                        if (bit_idx < 7) bit_idx <= bit_idx + 1;
                        else begin bit_idx <= 0; state <= STOP; end
                    end
                end

                STOP: begin
                    tx_pin <= 1'b1;
                    if (clk_cnt < CLKS_PER_BIT - 1) begin
                        clk_cnt <= clk_cnt + 1;
                    end else begin
                        tx_busy <= 1'b0;
                        tx_done <= 1'b1;
                        clk_cnt <= 0;
                        state   <= IDLE;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
