module transport
  #(
    parameter rows = 4,
    parameter cols = 4
    )
   (
    input [0:cols-1] data_in[0:rows-1],
    output [0:rows-1] data_out [0:cols-1]
    );

   genvar 	      row, col;
   generate
      for(row = 0; row < rows; row = row + 1)
	begin:for_rows
	   for(col = 0, col < cols; col = col + 1)
	     begin:for_cols
		assign data_out[col][row] = data_in[row][col];
	     end
	end
   endgenerate

endmodule
