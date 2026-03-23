`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 03/16/2026 10:04:13 PM
// Design Name: 
// Module Name: functions
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

`ifndef FUNCTIONS_SV
`define FUNCTIONS_SV

`include "config.sv"
// Pad input during ABS_AD, ABS_MSG (encryption):
// in:  [0x00, 0x00, 0x11, 0x22]
// val: [   0,    0,    1,    1]
// =>
// pad: [0x00, 0x01, 0x11, 0x22]
function automatic logic [CCW-1:0] pad;
  input logic [CCW-1:0] in;
  input logic [CCW/8-1:0] val;
  pad[7:0] = val[0] ? in[7:0] : 'd0;
  for (int i = 1; i < CCW / 8; i += 1) begin
    pad[i*8+:8] = val[i] ? in[i*8+:8] : val[i-1] ? 'd1 : 'd0;
  end
endfunction

// Pad input during ABS_MSG (decryption):
// in1:  [0x00, 0x11, 0x22, 0x33]
// in2:  [0x44, 0x55, 0x66, 0x77]
// val:  [   0,    0,    1,    1]
// =>
// pad2: [0x44, 0x54, 0x22, 0x33]
function automatic logic [CCW-1:0] pad2;
  input logic [CCW-1:0] in1;
  input logic [CCW-1:0] in2;
  input logic [CCW/8-1:0] val;
  pad2[7:0] = val[0] ? in1[7:0] : in2[7:0];
  for (int i = 1; i < CCW / 8; i += 1) begin
    pad2[i*8+:8] = val[i] ? in1[i*8+:8] : (val[i-1] ? 'd1 ^ in2[i*8+:8] : in2[i*8+:8]);
  end
endfunction

// Mask output during ABS_MSG:
// in1:  [0x00, 0x11, 0x22, 0x33]
// val:  [   0,    0,    1,    1]
// =>
// mask: [0x00, 0x00, 0x22, 0x33]
function automatic logic [CCW-1:0] mask;
  input logic [CCW-1:0] in1;
  input logic [CCW/8-1:0] val;
  for (int i = 0; i < CCW / 8; i += 1) begin
    mask[i*8+:8] = val[i] ? in1[i*8+:8] : 'd0;
  end
endfunction

`endif // FUNCTIONS_SV