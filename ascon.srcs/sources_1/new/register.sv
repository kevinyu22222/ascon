`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/16/2026 10:05:16 PM
// Design Name: 
// Module Name: register
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


module register #(parameter DATA_WIDTH, parameter RST_VALUE = DATA_WIDTH'('d0)) (
  clk,
  rst,
  data_d, // input
  data_q  // output
);

  input logic clk;
  input logic rst;
  input  logic[DATA_WIDTH-1:0] data_d;
  output logic[DATA_WIDTH-1:0] data_q;

  always_ff @(posedge clk, posedge rst) begin : register_update
    if (rst) begin
      data_q <= RST_VALUE;
    end else begin
      data_q <= data_d;
    end
  end
endmodule
