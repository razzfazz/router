#include <iostream>
#include <string>
#include <fstream>
#include <map>
#include <assert.h>


using namespace std;


void parse(ifstream &file, int &cycle, int &hash){
  long stuff;
  file>>cycle>>hash>>stuff;
  return;
}



int main(int argc, char** argv){
  
  ifstream srp_in;
  ifstream srp_out;

  //packet_unique, inject_time
  map<int, int> input_data;
  int cycle;
  int router;
  int id;
  int hash;
  int dest;
  map<int, map<int, int> >dest_hist;

  string line;
  //Test bench input parsing
  srp_in.open("srp_input.txt");
  int input_ttw;
  if(srp_in.is_open()){
    while(!srp_in.eof()){
      parse(srp_in, cycle,hash);
      input_data[hash] = cycle;
    }
    srp_in.close();
  }

  float lat_count=0;
  float  lat_sum=0;

  //Output testing
  srp_out.open("srp_output.txt");
  if(srp_out.is_open()){
    while(!srp_out.eof()){
      parse(srp_out, cycle, hash);
      if(input_data.count(hash)==0){
	cout<<"Not matched, ignore if last packet read\n";
      } else {
	int deltat = cycle-input_data[hash];
	if(deltat<=0)
	  cout<<"Error "<<hash<<endl;
	lat_sum+=deltat;
	lat_count+=1;
	input_data.erase(hash);
      }
    }
    srp_out.close();
  }
  cout<<"Estimate "<<lat_sum/lat_count<<" cycles\n";
  cout<<"Left over "<<input_data.size()<<endl;

  return 0;
}
