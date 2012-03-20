#include <iostream>
#include <string>
#include <fstream>
#include <map>
#include <assert.h>


using namespace std;


int parseline(ifstream &file, int &cycle, int &ttw, int &pid, int &port);


int main(int argc, char** argv){
  
  ifstream srp_in;
  ifstream srp_out;

  //packet_unique, inject_time
  map<int, int> input_data;
  int cycle;
  int ttw;
  int pid;
  int port;
  string line;
  //Test bench input parsing
  srp_in.open("srp_input.txt");
  if(srp_in.is_open()){
    while(!srp_in.eof()){
      int unique_id  = parseline(srp_in, cycle, ttw, pid, port);
      assert(ttw==255);
      input_data[unique_id] = cycle;
    }
    srp_in.close();
  }


  //Output testing
  srp_out.open("srp_output.txt");
  if(srp_out.is_open()){
    while(!srp_out.eof()){
      int unique_id  = parseline(srp_out, cycle, ttw, pid, port);
      if(input_data.count(unique_id)==0){
	cout<<"Not matched, ignore if last packet read\n";//cycle<<"\t"<<ttw<<"\t"<<pid<<"\t"<<port<<"\n";
	//assert(false);
      } else {
	int deltat = cycle-input_data[unique_id];
	assert(deltat>0);
	cout<<"TTW "<<255-ttw
	    <<"\tdeltaT "<<deltat<<endl;
	input_data.erase(unique_id);
      }
    }
    srp_out.close();
  }
  
  return 0;
}

int parseline(ifstream &file, int &cycle, int &ttw, int &pid, int &port){
  file>>cycle>>ttw>>pid>>port;
  return (pid<<5)+port;
}
