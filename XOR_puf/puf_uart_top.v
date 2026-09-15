`timescale 1ns / 1ps
//=====================================================================
// puf_uart_top.v
//
// PC sends 4 bytes (32-bit challenge, MSB first) over UART.
// Board evaluates the 128-cell XOR-PUF pool, selects 64 bits per the
// challenge, and replies with 8 bytes (64-bit response, MSB first).
//
// Basys 3 default pins (Digilent master XDC):
//   clk : W5   (100 MHz)
//   rst : U18  (center pushbutton, active high)
//   rx  : B18  (USB-UART -> FPGA)
//   tx  : A18  (FPGA -> USB-UART)
//=====================================================================
module puf_uart_top #(
    parameter POOL_N        = 128,
    parameter RESP_WIDTH    = 64,
    parameter CLEAR_CYCLES  = 4,
    parameter SETTLE_CYCLES = 16
)(
    input  wire clk,
    input  wire rst,
    input  wire rx,
    output wire tx
);

    localparam CHAL_BYTES = 4;                    // 32-bit challenge
    localparam RESP_BYTES = RESP_WIDTH / 8;        // 64-bit -> 8 bytes

    // ---------------- UART instances ----------------
    wire [7:0] rx_byte;
    wire       rx_done;
    reg  [7:0] tx_byte;
    reg        tx_start;
    wire       tx_busy, tx_done;

    uart_rx u_rx (
        .clk(clk), .rst(rst), .rx_pin(rx),
        .rx_data(rx_byte), .rx_done(rx_done)
    );
    uart_tx u_tx (
        .clk(clk), .rst(rst), .tx_start(tx_start),
        .tx_data(tx_byte), .tx_pin(tx), .tx_busy(tx_busy), .tx_done(tx_done)
    );

    // ---------------- PUF core ----------------
    reg                   puf_start;
    reg  [31:0]           challenge_reg;
    wire                  puf_busy, puf_valid;
    wire [RESP_WIDTH-1:0] puf_response;

    xor_puf_ctrl #(
        .POOL_N(POOL_N), .RESP_WIDTH(RESP_WIDTH),
        .CLEAR_CYCLES(CLEAR_CYCLES), .SETTLE_CYCLES(SETTLE_CYCLES)
    ) u_puf (
        .clk(clk), .rst(rst),
        .start(puf_start), .challenge(challenge_reg),
        .busy(puf_busy), .resp_valid(puf_valid), .response(puf_response)
    );

    reg [RESP_WIDTH-1:0] response_latched;

    // ---------------- top FSM ----------------
    localparam S_RX_CHAL  = 0,
               S_RUN_PUF  = 1,
               S_WAIT_PUF = 2,
               S_TX_RESP  = 3,
               S_TX_WAIT  = 4;

    reg [2:0] state;
    reg [2:0] byte_cnt;

    always @(posedge clk) begin
        if (rst) begin
            state            <= S_RX_CHAL;
            byte_cnt         <= 0;
            challenge_reg    <= 32'd0;
            puf_start        <= 1'b0;
            tx_start         <= 1'b0;
            response_latched <= {RESP_WIDTH{1'b0}};
        end else begin
            puf_start <= 1'b0;
            tx_start  <= 1'b0;

            case (state)
                // Receive CHAL_BYTES bytes, MSB first, into challenge_reg
                S_RX_CHAL: begin
                    if (rx_done) begin
                        challenge_reg <= {challenge_reg[23:0], rx_byte};
                        if (byte_cnt == CHAL_BYTES - 1) begin
                            byte_cnt <= 0;
                            state    <= S_RUN_PUF;
                        end else begin
                            byte_cnt <= byte_cnt + 1'b1;
                        end
                    end
                end

                S_RUN_PUF: begin
                    puf_start <= 1'b1;
                    state     <= S_WAIT_PUF;
                end

                S_WAIT_PUF: begin
                    if (puf_valid) begin
                        response_latched <= puf_response;
                        byte_cnt         <= 0;
                        state            <= S_TX_RESP;
                    end
                end

                // Transmit RESP_BYTES bytes, MSB first
                S_TX_RESP: begin
                    if (!tx_busy) begin
                        tx_byte  <= response_latched[RESP_WIDTH-1 -: 8];
                        tx_start <= 1'b1;
                        state    <= S_TX_WAIT;
                    end
                end

                S_TX_WAIT: begin
                    if (tx_done) begin
                        response_latched <= response_latched << 8;
                        if (byte_cnt == RESP_BYTES - 1) begin
                            byte_cnt <= 0;
                            state    <= S_RX_CHAL;
                        end else begin
                            byte_cnt <= byte_cnt + 1'b1;
                            state    <= S_TX_RESP;
                        end
                    end
                end

                default: state <= S_RX_CHAL;
            endcase
        end
    end

endmodule
