//VERIFICATION OF CLOCK GENERATOR, INCLUDE THIS IN UART PROTOCOL FOR DIFFERENT OUTPUT CLOCK FREQUENCIES

`timescale 1ns / 1ps

`include "uvm_macros.svh"
 import uvm_pkg::*;


typedef enum bit [1:0] {reset_asserted = 0, random_baud = 1} oper_mode;

/////////////////////// SEQ_ITEM (LECTURE 1) ///////////////////////////////////////////

class transaction extends uvm_sequence_item;
  `uvm_object_utils(transaction)
  
    oper_mode   oper;
    rand logic [16:0] baud;
    logic tx_clk, rx_clk;
    real period;
    
  constraint baud_c { baud inside {4800,9600,14400,19200,38400,57600}; }
  

  function new(string name = "transaction");
    super.new(name);
  endfunction

endclass 
/////////////////////////// SEQUENCE CASE 1 ///////////////////////////

class reset_clk extends uvm_sequence#(transaction);
  `uvm_object_utils(reset_clk)
  
  transaction tr;

  function new(string name = "reset_clk");
    super.new(name);
  endfunction
  
  virtual task body();
    repeat(5)
      begin
        tr = transaction::type_id::create("tr");
        start_item(tr);
        assert(tr.randomize);
        tr.oper = reset_asserted;        // MODE SELECT DEFINED AT START OF ITEM
        finish_item(tr);
      end
  endtask
  

endclass


/////////////////////////// SEQUENCE CASE 2 ////////////////////////////////////////////
class variable_baud extends uvm_sequence#(transaction);
  `uvm_object_utils(variable_baud)
  
  transaction tr;

  function new(string name = "variable_baud");
    super.new(name);
  endfunction
  
  virtual task body();            //defines start & end of a sequence containing items, so that it can be conveyed to a DRIVER
                                 // IS SEQUENCE WE ARE UPDATING THE OPERATING MODE 
    repeat(5)
      begin
        tr = transaction::type_id::create("tr");  
        start_item(tr);          //when we recieve the grant TO start the randomization
        assert(tr.randomize);
        tr.oper = random_baud;   // select mode
        finish_item(tr);         //FINISH ONE Tx.
      end
  endtask
  

endclass

/////////////////////////// DRIVER /////////////////////////////////////


class driver extends uvm_driver #(transaction);
  `uvm_component_utils(driver)
  
  virtual clk_if vif;
  transaction tr;
  
  
  function new(input string path = "drv", uvm_component parent = null);
    super.new(path,parent);
  endfunction
  
 virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
     tr = transaction::type_id::create("tr");
      
   if(!uvm_config_db#(virtual clk_if)::get(this,"","vif",vif)) 
      `uvm_error("drv","Unable to access Interface");
  endfunction
  
  
   virtual task run_phase(uvm_phase phase);
    forever begin
      seq_item_port.get_next_item(tr);   //ASKING GRANT FROM SEQUENCER, BUT WHERE IS THE SEQUENCER ??
      
      if(tr.oper == reset_asserted)
           begin
              vif.rst <= 1'b1;
             @(posedge vif.clk);
           end
      else if (tr.oper == random_baud )
           begin
             `uvm_info("DRV",$sformatf("Baud : %0d",tr.baud), UVM_NONE);
             vif.rst  <= 1'b0;
             vif.baud <= tr.baud;
             @(posedge vif.clk);
             @(posedge vif.tx_clk);
             @(posedge vif.tx_clk);
           end
  
      seq_item_port.item_done();   // TELLING 1 TX COMPLETED
    end
  endtask
  
endclass

////////////////////// MONITOR /////////////////////////////////////////
class mon extends uvm_monitor;
`uvm_component_utils(mon)

uvm_analysis_port#(transaction) send; // PORT TO SEND TR TO SCOREBOARD
transaction tr;                       // instance TO STORE RESPONSE FROM DUT  
virtual clk_if vif;                   // INSTANCE OF INTERFACE VIA CONFIG DB
real ton  = 0;                        //FOR SAMPLING OF A CLOCK TO GET PERIOD
real toff = 0;
  
    function new(input string inst = "mon", uvm_component parent = null);
    super.new(inst,parent);
    endfunction
  
    virtual function void build_phase(uvm_phase phase);  // INSTANCES OF ALL MEMBERS DEFINED INSIDE THE CHILD CLASS 
    super.build_phase(phase);
      send = new("send", this);                 //port instantiation
      
      tr = transaction::type_id::create("tr");  //object creation
      
      if(!uvm_config_db#(virtual clk_if)::get(this,"","vif",vif)) 
          `uvm_error("mon","Unable to access Interface");
    endfunction
  
      
    virtual task run_phase(uvm_phase phase);
    forever begin
      @(posedge vif.clk);           //WAIT FOR 1 CYCLE TO GET THE RESPONSE FROM DUT
      if(vif.rst)
        begin
          tr.oper = reset_asserted;
          ton    = 0;
          toff   = 0;
        `uvm_info("MON", "SYSTEM RESET DETECTED", UVM_NONE);
        send.write(tr);              //SEND DATA TO SCOREBOARD VIA WRITE METHOD
        end
      else
         begin
          tr.baud = vif.baud;
          tr.oper = random_baud; 
          ton     = 0;
          toff    = 0; 
           @(posedge vif.tx_clk);
           ton = $realtime;
           @(posedge vif.tx_clk);
           toff = $realtime;
           tr.period = toff - ton;  // TIME PERIOD FOR BAUD (fBAUD)
           
           `uvm_info("MON",$sformatf("Baud : %0d Period:%0f",tr.baud,tr.period), UVM_NONE);
           send.write(tr);

         end

    end
 endtask
  
endclass

/////////////////////////// SCOREBOARD ///]/////////////////////////////////
 class sco extends uvm_scoreboard;
`uvm_component_utils(sco)

   real count = 0;
   real baudcount = 0;
  uvm_analysis_imp#(transaction,sco) recv;  //import / export 

    function new(input string inst = "sco", uvm_component parent = null);
    super.new(inst,parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    recv = new("recv", this);
    endfunction
    
    
  virtual function void write(transaction tr); //WRITE MEANS DATA FROM SCOREBOARD 
    count =  tr.period / 20;   // tBAUD / tCLK (20ns)
    baudcount = count;
    `uvm_info("SCO", $sformatf("BAUD:%0d count:%0f bcount:%0f", tr.baud,count, baudcount), UVM_NONE);
    case(tr.baud)
      
      4800: begin
        if(baudcount == 10418) //(10416 + 2) NEED TO ADD 2 COZ OF WAITING FOR 2 CLOCK EDGES
          `uvm_info("SCO", "TEST PASSED", UVM_NONE)
        else
          `uvm_error("SCO" , "TEST FAILED")
      end
          
          
      9600: begin
        if(baudcount == 5210)
          `uvm_info("SCO", "TEST PASSED", UVM_NONE)
        else
          `uvm_error("SCO" , "TEST FAILED") 
        
      end
          
      14400: begin
        if(baudcount == 3474)
          `uvm_info("SCO", "TEST PASSED", UVM_NONE)
        else
          `uvm_error("SCO" , "TEST FAILED")
      end
        
      19200: begin
        if(baudcount == 2606)
          `uvm_info("SCO", "TEST PASSED", UVM_NONE)
        else
          `uvm_error("SCO" , "TEST FAILED")
        
      end
        
      38400: begin
        if(baudcount == 1304)
          `uvm_info("SCO", "TEST PASSED", UVM_NONE)
        else
          `uvm_error("SCO" , "TEST FAILED")
        
      end
        
      57600: begin
        if(baudcount == 870)
          `uvm_info("SCO", "TEST PASSED", UVM_NONE)
        else
          `uvm_error("SCO" , "TEST FAILED")
      end
          
          endcase     
  endfunction

endclass

//////////////////////////// AGENT (SEQUENCER <--> DRIVER)(LECTURE 2) ////////////////////////////////

                  
                  
class agent extends uvm_agent;
`uvm_component_utils(agent)

function new(input string inst = "agent", uvm_component parent = null);
super.new(inst,parent);
endfunction

 driver d;
 uvm_sequencer#(transaction) seqr;
 mon m;


virtual function void build_phase(uvm_phase phase);
super.build_phase(phase);
   m = mon::type_id::create("m",this);
   d = driver::type_id::create("d",this);
   seqr = uvm_sequencer#(transaction)::type_id::create("seqr", this);
  
endfunction

virtual function void connect_phase(uvm_phase phase);
super.connect_phase(phase);
    d.seq_item_port.connect(seqr.seq_item_export);
endfunction

endclass

////////////////////////// ENV : AGENT + SCO & (MONITOR <--> SCOREBOARD CONNECTION ////////////////////////////////////////////////
 
class env extends uvm_env;
`uvm_component_utils(env)

function new(input string inst = "env", uvm_component c);
super.new(inst,c);
endfunction

agent a;
sco s;

virtual function void build_phase(uvm_phase phase);
super.build_phase(phase);
  a = agent::type_id::create("a",this);
  s = sco::type_id::create("s", this);
endfunction

virtual function void connect_phase(uvm_phase phase);
super.connect_phase(phase);
 a.m.send.connect(s.recv);
endfunction

endclass


//////////////////////////// TEST CLASS  (IN THE END)/////////////////////////////////



class test extends uvm_test;
`uvm_component_utils(test)

  env e;
  variable_baud vbar;   //ADDING BOTH SEQUENCES
  reset_clk   rclk;
  
  
function new(input string inst = "test", uvm_component c);
super.new(inst,c);
endfunction
  
virtual function void build_phase(uvm_phase phase);
super.build_phase(phase);
 e       = env::type_id::create("env",this);  
 vbar = variable_baud::type_id::create("vbar");
  rclk = reset_clk::type_id::create("rclk"); 
endfunction

virtual task run_phase(uvm_phase phase);  //CALLING OF ALL SEQUENCES
phase.raise_objection(this);
vbar.start(e.a.seqr);
#20;
phase.drop_objection(this);
endtask
endclass  

///////////////////////////////////////////////////////////


module tb;
  
  
  clk_if vif(); 
  
  clk_gen dut (.clk(vif.clk),.rst(vif.rst), .baud(vif.baud), .tx_clk(vif.tx_clk)); //CONNECTION OF INTERFACE WITH DUT
  

  initial begin
    vif.clk <= 0;
  end

  always #10 vif.clk <= ~vif.clk; //1/50 20nsec 10nsec

  //COMMON CONFIG_DB TO ACCESS INTERFACE FOR ALL COMPONENTS 
  
  initial begin
    uvm_config_db#(virtual clk_if)::set(null, "*", "vif", vif);
    run_test("test");
   end
  
  
  initial begin
    $dumpfile("dump.vcd");
    $dumpvars;
  end

  
endmodule