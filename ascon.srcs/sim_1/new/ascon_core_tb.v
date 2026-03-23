`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/19/2026 06:58:01 PM
// Design Name: 
// Module Name: ascon_core_tb
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module ascon_core_tb(

    );

    localparam CCW  = 32;
    localparam CCWD8 = CCW / 8;           // 4 bytes per transfer word
    localparam [2:0] M_AEAD128_ENC = 3'd1;
    
    localparam [2:0] D_NONCE = 3'd1;
    localparam [2:0] D_AD    = 3'd2;
    localparam [2:0] D_MSG   = 3'd3;
    localparam [2:0] D_TAG   = 3'd4;


    reg clk = 0, rst = 0, key_valid = 0, bdi_eot = 0;
    reg bdi_eoi = 0, bdo_ready = 0, bdo_eoo = 0;
    reg [3:0] mode = 1,  bdi_type = 0;
    reg [CCW - 1:0] key  = 0;
    reg [CCWD8 - 1:0] bdi_valid = 0;
    reg [CCW - 1:0] bdi = 0;
    wire key_ready, bdi_ready, bdo_valid, bdo_eot, auth, auth_valid;
    wire [CCW - 1:0] bdo;
    wire [3:0] bdo_type;

    ascon_core test(
        .clk(clk),
        .rst(rst),
        .key(key),
        .key_valid(key_valid),
        .key_ready(key_ready),
        .bdi(bdi),
        .bdi_valid(bdi_valid),
        .bdi_ready(bdi_ready),
        .bdi_type(bdi_type),
        .bdi_eot(bdi_eot),
        .bdi_eoi(bdi_eoi),
        .mode(mode),
        .bdo(bdo),
        .bdo_valid(bdo_valid),
        .bdo_ready(bdo_ready),
        .bdo_type(bdo_type),
        .bdo_eot(bdo_eot),
        .bdo_eoo(bdo_eoo),
        .auth(auth),
        .auth_valid(auth_valid)
    );

  // ---------------------------------------------------------------------------
  // 2 ns clock
  // ---------------------------------------------------------------------------
  initial clk = 0;
  always #1 clk = ~clk;
 
  // ---------------------------------------------------------------------------
  // Hardcoded test vectors
  // ---------------------------------------------------------------------------
 
  // Key:   00 01 02 03 | 04 05 06 07 | 08 09 0A 0B | 0C 0D 0E 0F
  localparam [CCW-1:0] KEY_W0 = 32'h03020100;
  localparam [CCW-1:0] KEY_W1 = 32'h07060504;
  localparam [CCW-1:0] KEY_W2 = 32'h0B0A0908;
  localparam [CCW-1:0] KEY_W3 = 32'h0F0E0D0C;
 
  // Nonce: 00 01 02 03 | 04 05 06 07 | 08 09 0A 0B | 0C 0D 0E 0F
  localparam [CCW-1:0] NONCE_W0 = 32'h03020100;
  localparam [CCW-1:0] NONCE_W1 = 32'h07060504;
  localparam [CCW-1:0] NONCE_W2 = 32'h0B0A0908;
  localparam [CCW-1:0] NONCE_W3 = 32'h0F0E0D0C;
 
  // AD:    00 01 02 03 (4 bytes = 1 word)
  localparam [CCW-1:0] AD_W0 = 32'h03020100;
 
  // PT:    00 01 02 03 (4 bytes = 1 word)
  localparam [CCW-1:0] PT_W0 = 32'h03020100;
 
  // ---------------------------------------------------------------------------
  // Result registers
  // ---------------------------------------------------------------------------
  reg [CCW-1:0] ct_hw;
  reg [CCW-1:0] tag_hw0, tag_hw1, tag_hw2, tag_hw3;
  reg [CCW-1:0] _unused;   // discard bdo when not needed
  integer       errors;
 
  // ---------------------------------------------------------------------------
  // Task: clear_bdi
  //   Deassert all BDI / BDO_READY signals
  // ---------------------------------------------------------------------------
  task clear_bdi;
    begin
      bdi       = 0;
      bdi_valid = 0;
      bdi_type  = 0;
      bdi_eot   = 0;
      bdi_eoi   = 0;
      bdo_ready = 0;
      bdo_eoo   = 0;
      bdo_eoo   = 0;    
    end
  endtask
 
  // ---------------------------------------------------------------------------
  // Task: send_key
  //   Sends 4 x CCW-bit words over the key channel using valid/ready handshake.
  // ---------------------------------------------------------------------------
  task send_key;
    input [CCW-1:0] w0, w1, w2, w3;
    begin
      // Word 0
      key = w0; key_valid = 1;
      @(posedge clk);
      while (!key_ready) @(posedge clk);
 
      // Word 1
      key = w1;
      @(posedge clk);
      while (!key_ready) @(posedge clk);
 
      // Word 2
      key = w2;
      @(posedge clk);
      while (!key_ready) @(posedge clk);
 
      // Word 3
      key = w3;
      @(posedge clk);
      while (!key_ready) @(posedge clk);
 
      key = 0; key_valid = 0;
    end
  endtask
 
  // ---------------------------------------------------------------------------
  // Task: send_bdi
  //   Sends a single fully-valid word (all 4 byte-enables set) over the BDI
  //   channel and optionally captures the simultaneous BDO output.
  //
  //   dtype    : D_NONCE / D_AD / D_MSG
  //   eot      : 1 = last word of this segment
  //   eoi      : 1 = last word of all input
  //   bdo_rdy  : drive bdo_ready (set when expecting inline CT output)
  //   captured : BDO word sampled when the BDI handshake fires
  // ---------------------------------------------------------------------------
  task send_bdi;
    input [CCW-1:0]    data;
    input [2:0]        dtype;
    input              eot;
    input              eoi;
    input              bdo_rdy;
    output [CCW-1:0]   captured;
    begin
      bdi       = data;
      bdi_valid = {CCWD8{1'b1}};  // all 4 byte-enables asserted
      bdi_type  = dtype;
      bdi_eot   = eot;
      bdi_eoi   = eoi;
      bdo_ready = bdo_rdy;
 
      @(posedge clk);
      while (!bdi_ready) @(posedge clk);
      captured = bdo;   // valid when bdo_rdy=1 and hardware outputs CT in same cycle
      clear_bdi;
      $display("Captured: %08h", captured);
    end
  endtask
 
  // ---------------------------------------------------------------------------
  // Task: recv_bdo
  //   Waits for one BDO word of the specified type and captures it.
  //
  //   dtype    : D_TAG / D_HASH / etc.
  //   eoo      : 1 = last word being received
  //   captured : BDO word captured on a valid handshake
  // ---------------------------------------------------------------------------
  task recv_bdo;
    input [2:0]      dtype;
    output [CCW-1:0] captured;
    begin
    $display("Waiting for BDO of type %d...", dtype);
      bdo_ready = 1;
      bdo_eoo   = 0;
 
      @(posedge clk);
      while (!(bdo_valid && (bdo_type == dtype))) @(posedge clk);
 
      captured  = bdo;
      bdo_ready = 0;
      bdo_eoo   = 0;
      $display("Received BDO: type=%d, data=%08h", bdo_type, captured);
    end
  endtask
 
  // ---------------------------------------------------------------------------
  // Main test sequence
  // ---------------------------------------------------------------------------
  initial begin
    errors = 0;
 
    // Initialise all driven signals
    rst = 0; mode = 0; key = 0; key_valid = 0;
    clear_bdi;
 
    // ── Reset ────────────────────────────────────────────────────
    @(posedge clk);
    rst = 1;
    @(posedge clk);
    rst = 0;
    @(posedge clk);
 
    $display("============================================");
    $display(" ASCON-AEAD128 Encryption Test              ");     
    $display("============================================");
    $display(" Key:   000102030405060708090A0B0C0D0E0F");
    $display(" Nonce: 000102030405060708090A0B0C0D0E0F");
    $display(" AD:    00010203");
    $display(" PT:    00010203");
    $display("--------------------------------------------");
 
    // ── Pulse mode to start encryption ───────────────────────────
    mode = M_AEAD128_ENC;
 
    // ── Send 128-bit key (4 words) ────────────────────────────────
    send_key(KEY_W0, KEY_W1, KEY_W2, KEY_W3);
 
    // ── Send 128-bit nonce (4 words) ──────────────────────────────
    // eot=0 on first three words; eot=1 on final word.
    // eoi=0 because associated data follows.
    send_bdi(NONCE_W0, D_NONCE, 1'b0, 1'b0, 1'b0, _unused);
    send_bdi(NONCE_W1, D_NONCE, 1'b0, 1'b0, 1'b0, _unused);
    send_bdi(NONCE_W2, D_NONCE, 1'b0, 1'b0, 1'b0, _unused);    
    send_bdi(NONCE_W3, D_NONCE, 1'b1, 1'b0, 1'b0, _unused);  // eot=1
 
    // ── Send associated data (1 word) ─────────────────────────────
    // eot=1 (last AD word); eoi=0 because plaintext follows.
    send_bdi(AD_W0, D_AD, 1'b1, 1'b0, 1'b0, _unused);
 
    // ── Send plaintext; capture ciphertext inline ─────────────────
    // bdo_ready=1 enables simultaneous CT output.
    // eot=1, eoi=1 — this is the last word of all input.
    send_bdi(PT_W0, D_MSG, 1'b1, 1'b1, 1'b1, ct_hw);
 
    // ── Receive 128-bit authentication tag (4 words) ─────────────
    // bdo_eoo stays 0 throughout.
    recv_bdo(D_TAG, tag_hw0);
    recv_bdo(D_TAG, tag_hw1);
    recv_bdo(D_TAG, tag_hw2);
    recv_bdo(D_TAG, tag_hw3);
 
    // ── Display results ───────────────────────────────────────────
    $display(" CT:    %08h", ct_hw);
    $display(" Tag:   %08h_%08h_%08h_%08h",
             tag_hw0, tag_hw1, tag_hw2, tag_hw3);
    $display("--------------------------------------------");
 
    $display("============================================");
    $finish;
  end
 
  // ---------------------------------------------------------------------------
  // Watchdog — fail if simulation runs longer than expected
  // ---------------------------------------------------------------------------
  initial begin
    #200_000;
    $display("TIMEOUT: simulation exceeded 100 us");
    $finish;
  end
endmodule
