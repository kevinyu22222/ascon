`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/22/2026 11:52:09 PM
// Design Name: 
// Module Name: ascon_top_tb
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


module ascon_top_tb(

    );
    
    reg [15:0] in = 15'b0000_0000_0110_1101;
    reg load, start;
    reg rst, clk;
    wire [15:0] LED;
    wire [4:0] state_out;
    wire [31:0] pt_out;
    
    ascong_top top_tb(
        .in(in),
        .start(start),
        .rst(rst),
        .load(load),
        .clk(clk),
        .LED(LED),
        .state_out(state_out),
        .pt_out(pt_out)
    );
    
  initial clk = 0;
    always #5 clk = ~clk;   // 10 ns period - easier to read in waveform   
     
    initial begin
        rst = 1; load = 0; start = 0;

        // Hold reset for 4 clean cycles
        repeat(4) @(posedge clk);
        @(negedge clk); rst = 0;   // deassert between edges to avoid race

        // Load plaintext - pulse load for 1 cycle
        @(negedge clk); load = 1;
        @(negedge clk); load = 0;

        // Trigger encryption - hold start for 2 cycles so edge detector catches it
        @(negedge clk); start = 1;
        repeat(2) @(posedge clk);
        @(negedge clk); start = 0;

        // Wait long enough for full ASCON encryption to complete
        repeat(1000) @(posedge clk);
        $finish;
    end
    
    always @(posedge clk)
    $display("t=%0t  state=%02d  LED=%h  pt=%h", $time, state_out, LED, pt_out);

endmodule
