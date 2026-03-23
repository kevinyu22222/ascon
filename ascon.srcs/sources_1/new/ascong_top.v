`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: ascong_top
// Description: Synthesizable ASCON-128 encryption top-level.
//              All simulation tasks replaced with a clocked FSM.
//////////////////////////////////////////////////////////////////////////////////

module ascong_top(
    input  [15:0] in,
    input         load,
    input         start,
    input         rst,
    input         clk,
    output [15:0] LED
);

    // -----------------------------------------------------------------------
    // Parameters
    // -----------------------------------------------------------------------
    localparam CCW   = 32;
    localparam CCWD8 = CCW / 8;   // 4 byte-enables per word

    localparam [2:0] M_AEAD128_ENC = 3'd1;
    localparam [2:0] D_NONCE       = 3'd1;
    localparam [2:0] D_AD          = 3'd2;
    localparam [2:0] D_MSG         = 3'd3;
    localparam [2:0] D_TAG         = 3'd4;

    // Key:   00 01 02 03 | 04 05 06 07 | 08 09 0A 0B | 0C 0D 0E 0F
    localparam [CCW-1:0] KEY_W0   = 32'h03020100;
    localparam [CCW-1:0] KEY_W1   = 32'h07060504;
    localparam [CCW-1:0] KEY_W2   = 32'h0B0A0908;
    localparam [CCW-1:0] KEY_W3   = 32'h0F0E0D0C;

    // Nonce: 00 01 02 03 | 04 05 06 07 | 08 09 0A 0B | 0C 0D 0E 0F
    localparam [CCW-1:0] NONCE_W0 = 32'h03020100;
    localparam [CCW-1:0] NONCE_W1 = 32'h07060504;
    localparam [CCW-1:0] NONCE_W2 = 32'h0B0A0908;
    localparam [CCW-1:0] NONCE_W3 = 32'h0F0E0D0C;

    // AD: 00 01 02 03 (1 word)
    localparam [CCW-1:0] AD_W0    = 32'h03020100;

    // -----------------------------------------------------------------------
    // FSM State Encoding
    // -----------------------------------------------------------------------
    localparam [4:0]
        ST_IDLE   = 5'd0,
        // --- send_key ---
        ST_SET_MODE = 5'd1,   // ← new: set mode, wait 1 cycle
        ST_SK0      = 5'd2,   // drive KEY_W1, wait key_ready
        ST_SK1      = 5'd3,
        ST_SK2      = 5'd4,
        ST_SK3      = 5'd5,
        // --- send nonce (send_bdi x4) ---
        ST_SN0    = 5'd6,
        ST_SN1    = 5'd7,
        ST_SN2    = 5'd8,
        ST_SN3    = 5'd9,   // eot=1
        // --- send AD (send_bdi x1) ---
        ST_SAD    = 5'd10,   // eot=1
        // --- send PT / capture CT (send_bdi x1, bdo_ready=1) ---
        ST_SMSG   = 5'd11,  // eot=1, eoi=1, bdo_ready=1
        // --- recv_bdo tag words ---
        ST_RTAG0    = 5'd12,
        ST_RTAG1    = 5'd13,
        ST_RTAG2    = 5'd14,
        ST_RTAG3    = 5'd15,
        ST_DONE     = 5'd16;

    // -----------------------------------------------------------------------
    // Registers
    // -----------------------------------------------------------------------
    reg [4:0]      state;

    // Plaintext word loaded via button[0]
    reg [CCW-1:0]  PT_W0;

    // ASCON interface driven regs
    reg [CCW-1:0]  key;
    reg            key_valid;
    reg [CCW-1:0]  bdi;
    reg [CCWD8-1:0] bdi_valid;
    reg [3:0]      bdi_type;
    reg            bdi_eot;
    reg            bdi_eoi;
    reg            bdo_ready;
    reg            bdo_eoo;
    reg [3:0]      mode;

    // Captured outputs
    reg [CCW-1:0]  ct_hw;
    reg [CCW-1:0]  tag_hw0, tag_hw1, tag_hw2, tag_hw3;

    // ASCON interface wires
    wire           key_ready;
    wire           bdi_ready;
    wire           bdo_valid;
    wire           bdo_eot;
    wire           auth;
    wire           auth_valid;
    wire [CCW-1:0] bdo;
    wire [3:0]     bdo_type;

    // Button edge detection (synthesizable rising-edge detect)
    reg  btn1_prev;
    wire btn1_rise = start & ~btn1_prev;

    always @(posedge clk)
        begin
           if(rst) PT_W0 <= 0;
           else if(load) PT_W0 <= in[7:0];
        end     

    // -----------------------------------------------------------------------
    // Main FSM
    // -----------------------------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            btn1_prev <= 0;
            state     <= ST_IDLE;
            key       <= 0;
            key_valid <= 0;
            bdi       <= 0;
            bdi_valid <= 0;
            bdi_type  <= 0;
            bdi_eot   <= 0;
            bdi_eoi   <= 0;
            bdo_ready <= 0;
            bdo_eoo   <= 0;
            mode      <= 0;
            ct_hw     <= 0;
            tag_hw0   <= 0;
            tag_hw1   <= 0;
            tag_hw2   <= 0;
            tag_hw3   <= 0;
        end else begin
            btn1_prev <= start;
            case (state)
                ST_IDLE: begin
                    mode      <= 0;
                    key       <= 0;
                    key_valid <= 0;
                    bdi       <= 0;
                    bdi_valid <= 0;
                    bdi_eot   <= 0;
                    bdi_eoi   <= 0;
                    bdo_ready <= 0;
                    bdo_eoo   <= 0;
                    if (btn1_rise) begin
                        mode      <= M_AEAD128_ENC;
                        key_valid <= 1;  
                        key       <= KEY_W0;
                        state     <= ST_SK0;
                    end
                end

                // ----------------------------------------------------------------
                // Send Key — 4 words, advance when key_ready is asserted
                // ----------------------------------------------------------------
                ST_SK0: begin
                    key       <= KEY_W0;
                    key_valid <= 1;
                    if (key_ready) begin
                        key   <= KEY_W1;
                        state <= ST_SK1;
                    end
                end

                ST_SK1: begin
                    key       <= KEY_W1;
                    key_valid <= 1;
                    if (key_ready) begin
                        key   <= KEY_W2;
                        state <= ST_SK2;
                    end
                end

                ST_SK2: begin
                    key       <= KEY_W2;
                    key_valid <= 1;
                    if (key_ready) begin
                        key   <= KEY_W3;
                        state <= ST_SK3;
                    end
                end

                ST_SK3: begin
                    key       <= KEY_W3;
                    key_valid <= 1;
                    if (key_ready) begin
                        // Key done — de-assert and begin nonce
                        key       <= 0;
                        key_valid <= 0;
                        bdi       <= NONCE_W0;
                        bdi_valid <= {CCWD8{1'b1}};
                        bdi_type  <= D_NONCE;
                        bdi_eot   <= 0;
                        bdi_eoi   <= 0;
                        bdo_ready <= 0;
                        state     <= ST_SN0;
                    end
                end

                // ----------------------------------------------------------------
                // Send Nonce — 4 words
                // ----------------------------------------------------------------
                ST_SN0: begin
                    bdi       <= NONCE_W0;
                    bdi_valid <= {CCWD8{1'b1}};
                    bdi_type  <= D_NONCE;
                    bdi_eot   <= 0;
                    bdi_eoi   <= 0;
                    bdo_ready <= 0;
                    if (bdi_ready) begin
                        bdi   <= NONCE_W1;
                        state <= ST_SN1;
                    end
                end

                ST_SN1: begin
                    bdi       <= NONCE_W1;
                    bdi_valid <= {CCWD8{1'b1}};
                    bdi_type  <= D_NONCE;
                    bdi_eot   <= 0;
                    bdi_eoi   <= 0;
                    bdo_ready <= 0;
                    if (bdi_ready) begin
                        bdi   <= NONCE_W2;
                        state <= ST_SN2;
                    end
                end

                ST_SN2: begin
                    bdi       <= NONCE_W2;
                    bdi_valid <= {CCWD8{1'b1}};
                    bdi_type  <= D_NONCE;
                    bdi_eot   <= 0;
                    bdi_eoi   <= 0;
                    bdo_ready <= 0;
                    if (bdi_ready) begin
                        bdi   <= NONCE_W3;
                        state <= ST_SN3;
                    end
                end

                ST_SN3: begin
                    bdi       <= NONCE_W3;
                    bdi_valid <= {CCWD8{1'b1}};
                    bdi_type  <= D_NONCE;
                    bdi_eot   <= 1;   // last nonce word
                    bdi_eoi   <= 0;
                    bdo_ready <= 0;
                    if (bdi_ready) begin
                        bdi     <= AD_W0;
                        bdi_type <= D_AD;
                        bdi_eot <= 1;
                        bdi_eoi <= 0;
                        state   <= ST_SAD;
                    end
                end

                // ----------------------------------------------------------------
                // Send AD — 1 word, eot=1
                // ----------------------------------------------------------------
                ST_SAD: begin
                    bdi       <= AD_W0;
                    bdi_valid <= {CCWD8{1'b1}};
                    bdi_type  <= D_AD;
                    bdi_eot   <= 1;
                    bdi_eoi   <= 0;
                    bdo_ready <= 0;
                    if (bdi_ready) begin
                        bdi       <= PT_W0;
                        bdi_type  <= D_MSG;
                        bdi_eot   <= 1;
                        bdi_eoi   <= 1;
                        bdo_ready <= 1;   // request CT output inline
                        state     <= ST_SMSG;
                    end
                end

                // ----------------------------------------------------------------
                // Send Plaintext / Capture Ciphertext
                // ----------------------------------------------------------------
                ST_SMSG: begin
                    bdi       <= PT_W0;
                    bdi_valid <= {CCWD8{1'b1}};
                    bdi_type  <= D_MSG;
                    bdi_eot   <= 1;
                    bdi_eoi   <= 1;
                    bdo_ready <= 1;
                    if (bdi_ready) begin
                        ct_hw     <= bdo;   // capture CT in same cycle as acceptance
                        bdi       <= 0;
                        bdi_valid <= 0;
                        bdi_eot   <= 0;
                        bdi_eoi   <= 0;
                        bdo_ready <= 1;     // keep ready for tag reception
                        state     <= ST_RTAG0;
                    end
                end

                // ----------------------------------------------------------------
                // Receive Tag — 4 words
                // ----------------------------------------------------------------
                ST_RTAG0: begin
                    bdo_ready <= 1;
                    bdo_eoo   <= 0;
                    if (bdo_valid && (bdo_type == D_TAG)) begin
                        tag_hw0 <= bdo;
                        state   <= ST_RTAG1;
                    end
                end

                ST_RTAG1: begin
                    bdo_ready <= 1;
                    bdo_eoo   <= 0;
                    if (bdo_valid && (bdo_type == D_TAG)) begin
                        tag_hw1 <= bdo;
                        state   <= ST_RTAG2;
                    end
                end

                ST_RTAG2: begin
                    bdo_ready <= 1;
                    bdo_eoo   <= 0;
                    if (bdo_valid && (bdo_type == D_TAG)) begin
                        tag_hw2 <= bdo;
                        state   <= ST_RTAG3;
                    end
                end

                ST_RTAG3: begin
                    bdo_ready <= 1;
                    bdo_eoo   <= 0;
                    if (bdo_valid && (bdo_type == D_TAG)) begin
                        tag_hw3   <= bdo;
                        bdo_ready <= 0;
                        bdo_eoo   <= 1;
                        state     <= ST_DONE;
                    end
                end

                // ----------------------------------------------------------------
                // DONE — hold outputs, wait for reset
                // ----------------------------------------------------------------
                ST_DONE: begin
                    bdo_ready <= 0;
                    bdo_eoo   <= 0;
                end

                default: state <= ST_IDLE;

            endcase
        end
    end

    // -----------------------------------------------------------------------
    // LED output — show lower 16 bits of captured ciphertext
    // -----------------------------------------------------------------------
    assign LED = ct_hw;
    assign state_out = state;
    assign pt_out = PT_W0;

    // -----------------------------------------------------------------------
    // ASCON core instantiation
    // -----------------------------------------------------------------------
    ascon_core test(
        .clk        (clk),
        .rst        (rst),
        .key        (key),
        .key_valid  (key_valid),
        .key_ready  (key_ready),
        .bdi        (bdi),
        .bdi_valid  (bdi_valid),
        .bdi_ready  (bdi_ready),
        .bdi_type   (bdi_type),
        .bdi_eot    (bdi_eot),
        .bdi_eoi    (bdi_eoi),
        .mode       (mode),
        .bdo        (bdo),
        .bdo_valid  (bdo_valid),
        .bdo_ready  (bdo_ready),
        .bdo_type   (bdo_type),
        .bdo_eot    (bdo_eot),
        .bdo_eoo    (bdo_eoo),
        .auth       (auth),
        .auth_valid (auth_valid)
    );

endmodule
