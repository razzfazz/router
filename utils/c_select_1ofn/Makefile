c_select_1ofn.v: head gen_body tail
	cat head > c_select_1ofn.v
	./gen_body >> c_select_1ofn.v
	cat tail >> c_select_1ofn.v

gen_body: gen_body.cpp
	g++ -o gen_body gen_body.cpp

clean:
	rm -f c_select_1ofn.v gen_body *~
