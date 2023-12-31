`timescale 1ns / 1ps
/////////////////////////////////////////////////////////////////////////////////////
// PHARM
// Kyle Daruwalla
//
// delay_buffer
//		Delay buffer unit
/////////////////////////////////////////////////////////////////////////////////////
module delay_buffer #(
    parameter DELAY = 1
) (
    input logic CLK,
    input logic nRST,
    input logic x,
    output logic y
);

// internal wires
logic [(DELAY - 1):0] buffer;
logic [(DELAY - 1):0] next_buffer;

assign y = buffer[DELAY - 1];
assign next_buffer = (DELAY > 1) ? {buffer[(DELAY - 2):0], x} : x;

always @(posedge CLK) begin
    if (!nRST) buffer <= {DELAY{1'b0}};
    else buffer <= next_buffer;
end

endmodule
