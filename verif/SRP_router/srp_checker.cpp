#include <iostream>
#include <string>
#include <fstream>
#include <map>
#include <assert.h>


using namespace std;

int ttw_preset = 31*4;

int parseinput(ifstream &file, int &cycle, int &ttw, int &pid, int &port){
  double raw;
  file>>cycle>>ttw>>pid>>port>>raw;
  return (pid<<5)+port;
}
int parseoutput(ifstream &file, int &cycle, int &ttw, int &pid, int &port, int &actual){
  double raw;
  file>>cycle>>ttw>>pid>>port>>actual>>raw;
  return (pid<<5)+port;
}


int main(int argc, char** argv){
  
  ifstream srp_in;
  ifstream srp_out;

  //packet_unique, inject_time
  map<int, int> input_data;
  int cycle;
  int ttw;
  int pid;
  int port;
  int actual_port;
  string line;
  //Test bench input parsing
  srp_in.open("srp_input.txt");
  int input_ttw;
  if(srp_in.is_open()){
    while(!srp_in.eof()){
      int unique_id  = parseinput(srp_in, cycle, ttw, pid, port);
      input_ttw = ttw;
      input_data[unique_id] = cycle;
    }
    srp_in.close();
  }


  //Output testing
  srp_out.open("srp_output.txt");
  if(srp_out.is_open()){
    while(!srp_out.eof()){
      int unique_id  = parseoutput(srp_out, cycle, ttw, pid, port, actual_port);
      if(input_data.count(unique_id)==0){
	cout<<"Not matched, ignore if last packet read\n";//cycle<<"\t"<<ttw<<"\t"<<pid<<"\t"<<port<<"\n";
	//assert(false);
      } else {
	int deltat = cycle-input_data[unique_id];
	//assert(deltat>0);
	cout<<((port!=actual_port)?"":"#")<<"Port "<<port
	    <<"\tTTW "<<(input_ttw-ttw)*4
	    <<"\tdeltaT "<<deltat
	    <<((((deltat>=ttw_preset)&&(port==actual_port))||(!(deltat>=ttw_preset+4)&&(port!=actual_port)))?"\tpassed ":"\t\terror ")<<deltat-ttw_preset<<endl;
	input_data.erase(unique_id);
      }
    }
    srp_out.close();
  }
  cout<<"Estimate "<<input_data.size()<<" packets dropped\n";
  
  return 0;
}
