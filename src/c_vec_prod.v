// $Id: c_vec_prod.v 1186 2009-03-29 21:44:25Z dub $

/*
 Copyright (c) 2007-2012, Trustees of The Leland Stanford Junior University
 All rights reserved.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:

 Redistributions of source code must retain the above copyright notice, this 
 list of conditions and the following disclaimer.
 Redistributions in binary form must reproduce the above copyright notice, this
 list of conditions and the following disclaimer in the documentation and/or
 other materials provided with the distribution.

 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE 
 DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
 ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
 ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

// vector product (column vector times row vector, result is matrix)
module c_vec_prod
  (col_vec, row_vec, result);
   
   // length of column vector
   parameter num_rows = 1;
   
   // length of row vector
   parameter num_cols = 1;
   
   // column vector
   input [0:num_rows-1] col_vec;
   
   // row vector
   input [0:num_cols-1] row_vec;
   
   // result
   output [0:num_rows*num_cols-1] result;
   wire [0:num_rows*num_cols-1] result;
   
   generate
      
      genvar 			row;
      for(row = 0; row < num_rows; row = row + 1)
	begin:rows
	   
	   genvar col;
	   for(col = 0; col < num_cols; col = col + 1)
	     begin:cols
		
		assign result[row*num_cols+col] = col_vec[row] & row_vec[col];
		
	     end
	   
	end
      
   endgenerate
   
endmodule
