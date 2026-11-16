/*
 * tt_um_hybrid_crypto_sel — Tiny Tapeout 1x1 wrapper
 * On-chip : selection_logic (AES/SIMON decision engine) + SIMON-32/64 core
 * Off-chip: AES-Lite (when selected, chip flags AES_REQ for the host to run it)
 *
 * Pins
 *   ui_in[7:0]   : write data byte
 *   uio_in[3:0]  : register address
 *   uio_in[4]    : WE    (write ui_in to addr on rising clk while high)
 *   uio_in[5]    : START (rising edge starts a request)
 *   uio_in[6]    : FORCE_SIMON (1 = ignore selection, always run SIMON)
 *   uio_out[7]   : DONE  (sticky, cleared by next START)
 *   uo_out[7:0]  : read data byte at addr
 *
 * Write map              Read map
 *   0-3  PT[7:0..31:24]    0-3  CT[7:0..31:24]
 *   4-11 KEY[7:0..63:56]   4-11 0x00 (key is write-only)
 *   12   CFG0              12   STATUS {2'b0, err, aes_req, done, busy, crypt_sel[1:0]}
 *   13   CFG1              13   CFG1 readback
 *
 * CFG0 = {latency_req, src_trust, pac_rate[1:0], length[1:0], dst_port_502, protocol}
 * CFG1 = {3'b0, power_mode[1:0], anamoly_score[1:0], hw_sup}
 */
`default_nettype none

module tt_um_hybrid_crypto_sel (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);
    wire rst = ~rst_n;

    wire [3:0] addr        = uio_in[3:0];
    wire       we          = uio_in[4];
    wire       start_in    = uio_in[5];
    wire       force_simon = uio_in[6];

    // ---------------- register file ----------------
    reg [31:0] pt;
    reg [63:0] key;
    reg [7:0]  cfg0;
    reg [4:0]  cfg1;

    always @(posedge clk) begin
        if (we && !rst) begin   // data regs: no reset needed (saves area)
            case (addr)
                4'd0:  pt[7:0]    <= ui_in;
                4'd1:  pt[15:8]   <= ui_in;
                4'd2:  pt[23:16]  <= ui_in;
                4'd3:  pt[31:24]  <= ui_in;
                4'd4:  key[7:0]   <= ui_in;
                4'd5:  key[15:8]  <= ui_in;
                4'd6:  key[23:16] <= ui_in;
                4'd7:  key[31:24] <= ui_in;
                4'd8:  key[39:32] <= ui_in;
                4'd9:  key[47:40] <= ui_in;
                4'd10: key[55:48] <= ui_in;
                4'd11: key[63:56] <= ui_in;
                4'd12: cfg0       <= ui_in;
                4'd13: cfg1       <= ui_in[4:0];
                default: ;
            endcase
        end
    end

    // ---------------- selection logic ----------------
    wire [1:0] crypt_sel;
    selection_logic u_sel (
        .protocol     (cfg0[0]),
        .dst_port_502 (cfg0[1]),
        .length       (cfg0[3:2]),
        .pac_rate     (cfg0[5:4]),
        .src_trust    (cfg0[6]),
        .latency_req  (cfg0[7]),
        .hw_sup       (cfg1[0]),
        .anamoly_score(cfg1[2:1]),
        .power_mode   (cfg1[4:3]),
        .crypt_sel    (crypt_sel)
    );

    // ---------------- control ----------------
    reg start_d;
    reg busy, done, aes_req, err;
    reg simon_start;
    wire start_rise = start_in & ~start_d;
    wire simon_done;
    wire [31:0] ct;

    always @(posedge clk) begin
        if (rst) begin
            start_d <= 1'b0; busy <= 1'b0; done <= 1'b0;
            aes_req <= 1'b0; err <= 1'b0; simon_start <= 1'b0;
        end else begin
            start_d     <= start_in;
            simon_start <= 1'b0;
            if (start_rise && !busy) begin
                done <= 1'b0; aes_req <= 1'b0; err <= 1'b0;
                if (force_simon || crypt_sel == 2'b01) begin
                    simon_start <= 1'b1;
                    busy        <= 1'b1;
                end else if (crypt_sel == 2'b00) begin
                    aes_req <= 1'b1;          // host runs AES-Lite
                    done    <= 1'b1;
                end else begin
                    err  <= 1'b1;             // tie / n.a.
                    done <= 1'b1;
                end
            end else if (busy && simon_done) begin
                busy <= 1'b0;
                done <= 1'b1;
            end
        end
    end

    // ---------------- SIMON-32/64 core ----------------
    simon_top_clean u_simon (
        .clk     (clk),
        .rst     (rst),
        .start   (simon_start),
        .data_in (pt),
        .key     (key),
        .data_out(ct),
        .done    (simon_done)
    );

    // ---------------- readback ----------------
    reg [7:0] rdata;
    always @(*) begin
        case (addr)
            4'd0:  rdata = ct[7:0];
            4'd1:  rdata = ct[15:8];
            4'd2:  rdata = ct[23:16];
            4'd3:  rdata = ct[31:24];
            4'd12: rdata = {2'b00, err, aes_req, done, busy, crypt_sel};
            4'd13: rdata = {3'b000, cfg1};
            default: rdata = 8'h00;
        endcase
    end

    assign uo_out  = rdata;
    assign uio_out = {done, 7'b0};
    assign uio_oe  = 8'b1000_0000;

    wire _unused = &{ena, uio_in[7], 1'b0};
endmodule
