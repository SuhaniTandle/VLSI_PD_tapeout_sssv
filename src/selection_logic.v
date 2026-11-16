// selection_logic + security_logic
// Original logic by the project team. One change for ASIC:
//   security_logic: added a default assignment (security = low_sec) at the
//   top of the always block. The original left `security` unassigned on
//   several paths (e.g. bulk + mid_freq + len_low), which infers LATCHES.
//   Functionally the default only matters through (security == high_sec)
//   in the scoring, so any non-high default gives identical crypt_sel.

module selection_logic(
    input protocol,
    input dst_port_502,
    input [1:0] length,
    input [1:0] pac_rate,
    input src_trust,
    input [1:0] anamoly_score,
    input [1:0] power_mode,
    input latency_req,
    input hw_sup,
    output reg [1:0] crypt_sel
    );

parameter [1:0] aes = 2'b00, simon = 2'b01, na = 2'b10;
parameter tcp = 1'b0 , udp = 1'b1;
parameter strict = 1'b1, relaxed = 1'b0;

parameter [1:0] low_sec = 2'b00, mid_sec = 2'b01, high_sec = 2'b10, error = 2'b11;
parameter [1:0] control = 2'b00, sensor = 2'b01, bulk = 2'b10;
parameter [1:0] len_low = 2'b00, len_mid = 2'b01, len_high = 2'b10;
parameter [1:0] low_freq = 2'b00, mid_freq = 2'b01, high_freq = 2'b10;
parameter [1:0] anam_low = 2'b00, anam_mid = 2'b01, anam_high = 2'b10;
parameter trusted = 1'b1, untrusted = 1'b0;
parameter [1:0] lp = 2'b00, mp = 2'b01, hp = 2'b10;
reg [1:0] pac_type, pay_length, freq, anamoly;
wire [1:0] security;
reg signed [4:0] aes_score, simon_score;

security_logic dut(.pac_type(pac_type), .pay_length(pay_length), .freq(freq), .anamoly(anamoly),
 .trust(src_trust), .security(security));

always@(*)
begin
    pac_type   = bulk;
    pay_length = len_low;
    freq       = low_freq;
    anamoly    = anam_low;
    crypt_sel  = na;
    aes_score  = 0;
    simon_score = 0;

    if (protocol == tcp && dst_port_502)
        pac_type = control;
    else if (protocol == udp)
        pac_type = sensor;
    else
        pac_type = bulk;

    if (length == 2'b00)      pay_length = len_low;
    else if (length == 2'b01) pay_length = len_mid;
    else if (length == 2'b10) pay_length = len_high;

    if (pac_rate == 2'b00)      freq = low_freq;
    else if (pac_rate == 2'b01) freq = mid_freq;
    else if (pac_rate == 2'b10) freq = high_freq;

    if (anamoly_score == 2'b00)      anamoly = anam_low;
    else if (anamoly_score == 2'b01) anamoly = anam_mid;
    else if (anamoly_score == 2'b10) anamoly = anam_high;

    aes_score = 3*(security == high_sec) + 2*(pay_length == len_high) + 2*(hw_sup == 1)
              - 2*(power_mode == lp) - 1*(latency_req == 1);
    simon_score = 3*(power_mode == lp) + 2*(hw_sup == 0) + 2*(latency_req == 1)
                + 1*(pay_length == len_low) + 1*(pay_length == len_mid)
                - 2*(security == high_sec) - 1*(pay_length == len_high);

    if (aes_score > simon_score)
        crypt_sel = aes;
    else if (aes_score < simon_score)
        crypt_sel = simon;
    else
        crypt_sel = error;
end
endmodule

module security_logic(input [1:0] pac_type, pay_length, freq, anamoly,
 input trust, output reg [1:0] security);
parameter [1:0] low_sec = 2'b00, mid_sec = 2'b01, high_sec = 2'b10, error = 2'b11;
parameter [1:0] control = 2'b00, sensor = 2'b01, bulk = 2'b10;
parameter [1:0] len_low = 2'b00, len_mid = 2'b01, len_high = 2'b10;
parameter [1:0] low_freq = 2'b00, mid_freq = 2'b01, high_freq = 2'b10;
parameter [1:0] anam_low = 2'b00, anam_mid = 2'b01, anam_high = 2'b10;
parameter trusted = 1'b1, untrusted = 1'b0;

always@(*)
begin
    security = low_sec;   // ASIC fix: default removes inferred latches

    if (pac_type == bulk) begin
        if (freq == mid_freq) begin
            if (pay_length == len_high)     security = low_sec;
            else if (pay_length == len_mid) security = mid_sec;
        end
        else if (freq == high_freq) begin
            if (trust == trusted) begin
                if (anamoly == anam_low)       security = low_sec;
                else if (anamoly == anam_mid)  security = low_sec;
                else if (anamoly == anam_high) security = high_sec;
            end
            else if (trust == untrusted)
                security = high_sec;
        end
        else if (freq == low_freq)
            security = low_sec;
    end
    else if (pac_type == sensor) begin
        if (anamoly == anam_high)      security = high_sec;
        else if (anamoly == anam_low)  security = mid_sec;
        else if (anamoly == anam_mid) begin
            if (freq == mid_freq)       security = mid_sec;
            else if (freq == low_freq)  security = mid_sec;
            else if (freq == high_freq) begin
                if (pay_length == len_low)      security = low_sec;
                else if (pay_length == len_mid) security = mid_sec;
            end
        end
    end
    else if (pac_type == control)
        security = high_sec;
    else
        security = error;
end
endmodule
