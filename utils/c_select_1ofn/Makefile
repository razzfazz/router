c_select_1ofn.v: gen_body
	cat c_select_1ofn.v.head > c_select_1ofn.v
	./gen_body >> c_select_1ofn.v
	cat c_select_1ofn.v.tail >> c_select_1ofn.v

gen_body: gen_body.cpp
	g++ -o gen_body gen_body.cpp

clean:
	rm -f c_select_1ofn.v gen_body *~
