// =============================================================================
// Module  : simon_key_schedule
// Purpose : SIMON-32/64 key schedule
// FIXED VERSION:
// - Registers round_key explicitly
// - Avoids datapath/key-schedule race condition
// - Ensures hardware and simulation alignment
// =============================================================================

module simon_key_schedule (
    input  wire        clk,
    input  wire        rst,
    input  wire        load,
    input  wire        round_en,
    input  wire [63:0] key_in,

    output wire [15:0] round_key
);

    // -------------------------------------------------------------------------
    // z0 sequence
    // -------------------------------------------------------------------------

    localparam [61:0] Z_SEQ =
        62'b01_1001_1100_0011_0101_0010_0010_1111_1011_0011_1000_0110_1010_0100_0101_1111;

    localparam [15:0] C = 16'hFFFC;

    // -------------------------------------------------------------------------
    // Key registers
    // -------------------------------------------------------------------------

    reg [15:0] k0, k1, k2, k3;

    reg [4:0] round_idx;

    // REGISTERED ROUND KEY
    reg [15:0] round_key_reg;

    // -------------------------------------------------------------------------
    // Rotate functions
    // -------------------------------------------------------------------------

    function [15:0] ror3;
        input [15:0] x;
        begin
            ror3 = {x[2:0], x[15:3]};
        end
    endfunction

    function [15:0] ror1;
        input [15:0] x;
        begin
            ror1 = {x[0], x[15:1]};
        end
    endfunction

    // -------------------------------------------------------------------------
    // Next-key computation
    // -------------------------------------------------------------------------

    wire [15:0] tmp_a;
    wire [15:0] tmp_b;
    wire [15:0] new_k0;

    assign tmp_a  = ror3(k3) ^ k1;

    assign tmp_b  = tmp_a ^ ror1(tmp_a);

    assign new_k0 = C ^ {15'd0, Z_SEQ[round_idx]} ^ k0 ^ tmp_b;

    // -------------------------------------------------------------------------
    // Sequential logic
    // -------------------------------------------------------------------------

    always @(posedge clk) begin

        if (rst) begin

            k0 <= 16'd0;
            k1 <= 16'd0;
            k2 <= 16'd0;
            k3 <= 16'd0;

            round_idx <= 5'd0;

            round_key_reg <= 16'd0;

        end

        else if (load) begin

            // Initial key load
            // k0 used in round 0

            k0 <= key_in[15:0];
            k1 <= key_in[31:16];
            k2 <= key_in[47:32];
            k3 <= key_in[63:48];

            round_idx <= 5'd0;

            // First round key
            round_key_reg <= key_in[15:0];

        end

        else if (round_en) begin

            // IMPORTANT:
            // Capture CURRENT k1 as NEXT round key
            // before shifting happens

            round_key_reg <= k1;

            // Shift key pipeline

            k0 <= k1;
            k1 <= k2;
            k2 <= k3;
            k3 <= new_k0;

            round_idx <= round_idx + 5'd1;

        end
    end

    // -------------------------------------------------------------------------
    // Output
    // -------------------------------------------------------------------------

    assign round_key = round_key_reg;

endmodule