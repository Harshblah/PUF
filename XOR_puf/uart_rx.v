`timescale 1ns / 1ps
//=====================================================================
// uart_rx.v - standard 8-N-1 UART receiver
// Default CLKS_PER_BIT=868 -> 115200 baud @ 100 MHz (Basys 3 sys clk).
//=====================================================================
module uart_rx #(
    parameter CLKS_PER_BIT = 868
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       rx_pin,
    output reg  [7:0] rx_data,
    output reg        rx_done
);
    localparam IDLE = 0, START = 1, DATA = 2, STOP = 3;

    reg [1:0]  state    = IDLE;
    reg [12:0] clk_cnt  = 0;
    reg [2:0]  bit_idx  = 0;

    // synchronize the async rx pin
    reg rx_ff1, rx_ff2;
    always @(posedge clk) begin
        rx_ff1 <= rx_pin;
        rx_ff2 <= rx_ff1;
    end

    always @(posedge clk) begin
        if (rst) begin
            state   <= IDLE;
            rx_done <= 1'b0;
            clk_cnt <= 0;
            bit_idx <= 0;
        end else begin
            rx_done <= 1'b0;
            case (state)
                IDLE: if (!rx_ff2) state <= START;

                START: begin
                    if (clk_cnt == (CLKS_PER_BIT/2)) begin
                        if (!rx_ff2) begin clk_cnt <= 0; state <= DATA; end
                        else state <= IDLE;
                    end else clk_cnt <= clk_cnt + 1;
                end

                DATA: begin
                    if (clk_cnt < CLKS_PER_BIT - 1) begin
                        clk_cnt <= clk_cnt + 1;
                    end else begin
                        clk_cnt <= 0;
                        rx_data[bit_idx] <= rx_ff2;
                        if (bit_idx < 7) bit_idx <= bit_idx + 1;
                        else begin bit_idx <= 0; state <= STOP; end
                    end
                end

                STOP: begin
                    if (clk_cnt < CLKS_PER_BIT - 1) begin
                        clk_cnt <= clk_cnt + 1;
                    end else begin
                        rx_done <= 1'b1;
                        clk_cnt <= 0;
                        state   <= IDLE;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
