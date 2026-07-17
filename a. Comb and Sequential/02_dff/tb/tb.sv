`timescale 1ns / 1ps
`include "uvm_macros.svh"
import uvm_pkg::*;

////////////////////ACTIVE AND PASSIVE OBJECT CLASS //////////////////////////////////////////

class config_dff extends uvm_object;
  `uvm_object_utils(config_dff)
 
  uvm_active_passive_enum agent_type = UVM_ACTIVE;  // active agent : Drives stimulus( DRIVER, MONITOR)
                                                    // PASSIVE AGENT: COllects the response (MONITOR, SCOREBOARD)
  function new(input string path = "config_dff");
    super.new(path);
   endfunction 
  
endclass

///////////////////////SEQUENCE ITEM /////////////////////////////////////
class transaction extends uvm_sequence_item;
`uvm_object_utils(transaction)
  
  rand bit rst;
  rand bit din;
       bit dout;
        
   function new(input string path = "transaction");
    super.new(path);
   endfunction
  

endclass




///////////////////////// SEQUENCE ///////////////////////////////////////////////

class valid_din extends uvm_sequence#(transaction);
`uvm_object_utils(valid_din)  //register it as an object
  
    transaction tr; // creating instance to store transaction data

   function new(input string path = "valid_din"); //standard constructor of OBJECT of a class valid_din
    super.new(path);
   endfunction
   
   
   virtual task body(); 
   repeat(15)
     begin
         tr = transaction::type_id::create("tr"); //create an instance and construct tr.
         start_item(tr);
         assert(tr.randomize());
         tr.rst = 1'b0; 
         `uvm_info("SEQ", $sformatf("rst : %0b  din : %0b  dout : %0b", tr.rst, tr.din, tr.dout), UVM_NONE);
         finish_item(tr);     
     end
   endtask

endclass
//////////////////////////////////////////////////////////////////////////////
class rst_dff extends uvm_sequence#(transaction); 
`uvm_object_utils(rst_dff)
  
    transaction tr;

   function new(input string path = "rst_dff");
    super.new(path);
   endfunction
   
   
   virtual task body(); 
   repeat(15)
     begin
         tr = transaction::type_id::create("tr");
         start_item(tr);  //SEND REQ. TO THE SEQUENCER
         assert(tr.randomize());
         tr.rst = 1'b1;
         `uvm_info("SEQ", $sformatf("rst : %0b  din : %0b  dout : %0b", tr.rst, tr.din, tr.dout), UVM_NONE);
         finish_item(tr);    
     end
   endtask

endclass

//////////////////////////////////////////////////////////////////////////////
class rand_din_rst extends uvm_sequence#(transaction);
`uvm_object_utils(rand_din_rst)
  
    transaction tr;

   function new(input string path = "rand_din_rst");
    super.new(path);
   endfunction
   
   
   virtual task body(); //       DOUBT    //  ?? WHY NOT RUN PHASE AND VIRTUAL TASK BODY ??
   repeat(15)
     begin
         tr = transaction::type_id::create("tr");
         start_item(tr);
         assert(tr.randomize());
         `uvm_info("SEQ", $sformatf("rst : %0b  din : %0b  dout : %0b", tr.rst, tr.din, tr.dout), UVM_NONE);
         finish_item(tr);     
     end
   endtask

endclass


////////////////////////// DRIVER ////////////////////////////////////////////////////
class drv extends uvm_driver#(transaction);
  `uvm_component_utils(drv)

  transaction tr;   // INITIALIZATION 
  virtual dff_if dif;  // INSTANCE OF VIRTUAL INTERFACE

  function new(input string path = "drv", uvm_component parent = null); // CONSTRUCTOR OF CLASS DRV
    super.new(path,parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);  // ACCESSING THE INTERFACE
  super.build_phase(phase);
    if(!uvm_config_db#(virtual dff_if)::get(this,"","dif",dif))//uvm_test_top.env.agent.drv.aif
      `uvm_error("drv","Unable to access Interface");
  endfunction
  
   virtual task run_phase(uvm_phase phase);
      tr = transaction::type_id::create("tr");  //AGAIN CREATING THE OBJECT OF ALL CLASS INSTANCE TR, TO STORE THE TRANSACTIONS 
     forever begin
        seq_item_port.get_next_item(tr);  //TELL WHEN TO SEND Tx.  (TO SEQUENCER)
        dif.rst <= tr.rst;                //DRIVE SIGNALS ONTO DUT , SIGNAL CONVERSION
        dif.din <= tr.din;
       `uvm_info("DRV", $sformatf("rst : %0b  din : %0b  dout : %0b", tr.rst, tr.din, tr.dout), UVM_NONE);
        seq_item_port.item_done();       //TELL WHEN TO STOP Tx. 
       repeat(2) @(posedge dif.clk);    
      end
   endtask

endclass

////////////////////////// MONITOR ////////////////////////////////////////////////
class mon extends uvm_monitor;
`uvm_component_utils(mon)

uvm_analysis_port#(transaction) send; //analysis port creation
transaction tr;                      //instances of object and interface
virtual dff_if dif;

    function new(input string inst = "mon", uvm_component parent = null);
    super.new(inst,parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);  //ADD CONSTRUCTORS AND ACCESS VIRTUAL INTERFACE VIA CONFIG DB
    super.build_phase(phase);                            
    
    tr = transaction::type_id::create("tr");    
    send = new("send", this);
      if(!uvm_config_db#(virtual dff_if)::get(this,"","dif",dif))//uvm_test_top.env.agent.drv.aif
      `uvm_error("drv","Unable to access Interface");
    endfunction
    
    
    virtual task run_phase(uvm_phase phase);
    forever begin
      repeat(2) @(posedge dif.clk);
    tr.rst  = dif.rst;
    tr.din  = dif.din;
    tr.dout = dif.dout;
      `uvm_info("MON", $sformatf("rst : %0b  din : %0b  dout : %0b", tr.rst, tr.din, tr.dout), UVM_NONE);
        send.write(tr);
    end
   endtask 

endclass

////////////////////////// SCOREBOARD ///////////////////////////////////////////////
class sco extends uvm_scoreboard;           
`uvm_component_utils(sco)

  uvm_analysis_imp#(transaction,sco) recv;  //EX-PORT DECLARATION, INSTANCE OF IT 


    function new(input string inst = "sco", uvm_component parent = null);
    super.new(inst,parent);
    endfunction
    
    virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    recv = new("recv", this);
    endfunction
    
    
  virtual function void write(transaction tr);
    `uvm_info("SCO", $sformatf("rst : %0b  din : %0b  dout : %0b", tr.rst, tr.din, tr.dout), UVM_NONE);
    if(tr.rst == 1'b1)
      `uvm_info("SCO", "DFF Reset", UVM_NONE)
    else if(tr.rst == 1'b0 && (tr.din == tr.dout))
      `uvm_info("SCO", "TEST PASSED", UVM_NONE)
    else
      `uvm_info("SCO", "TEST FAILED", UVM_NONE)
      
          
    $display("----------------------------------------------------------------");
    endfunction

endclass

//////////////////////////////// AGENT ///////////////////////////////////////////

class agent extends uvm_agent;     //
`uvm_component_utils(agent)

function new(input string inst = "agent", uvm_component parent = null);
super.new(inst,parent);
endfunction

 drv d;
 uvm_sequencer#(transaction) seqr;
 mon m;
  
  ///////////////////
  config_dff cfg;


virtual function void build_phase(uvm_phase phase);
super.build_phase(phase);

  m = mon::type_id::create("m",this);
  cfg = config_dff::type_id::create("cfg"); 
  
  ////////////////////////////////////////////////////////////
  if(!uvm_config_db#(config_dff)::get(this, "", "cfg", cfg))
    `uvm_error("AGENT", "FAILED TO ACCESS CONFIG");
  
  if(cfg.agent_type == UVM_ACTIVE)
    begin
    d = drv::type_id::create("d",this); 
    seqr = uvm_sequencer#(transaction)::type_id::create("seqr", this); 
    end  
  
endfunction

virtual function void connect_phase(uvm_phase phase);
super.connect_phase(phase);
d.seq_item_port.connect(seqr.seq_item_export);
endfunction

endclass

////////////////////////// ENVIOURNMENT /////////////////////////////////////////////

class env extends uvm_env;
`uvm_component_utils(env)

function new(input string inst = "env", uvm_component c);
super.new(inst,c);
endfunction

agent a;
sco s;
config_dff cfg;

virtual function void build_phase(uvm_phase phase);
super.build_phase(phase);
  a = agent::type_id::create("a",this);
  s = sco::type_id::create("s", this);
  cfg = config_dff::type_id::create("cfg"); 
  //////////////////////////////////////////
  uvm_config_db#(config_dff)::set(this, "a", "cfg", cfg);
endfunction

virtual function void connect_phase(uvm_phase phase);
super.connect_phase(phase);
a.m.send.connect(s.recv);
endfunction

endclass


///////////////////////// TEST CLASS /////////////////////////////////////////
class test extends uvm_test;        //
`uvm_component_utils(test)

function new(input string inst = "test", uvm_component c);
super.new(inst,c);
endfunction

env e;
valid_din    vdin;
rst_dff      rff;
rand_din_rst rdin;


virtual function void build_phase(uvm_phase phase);
super.build_phase(phase);
  e    = env::type_id::create("env",this);
  vdin = valid_din::type_id::create("vdin");
  rff  = rst_dff::type_id::create("rff");
  rdin = rand_din_rst::type_id::create("rdin");
endfunction

virtual task run_phase(uvm_phase phase);
phase.raise_objection(this);
  rff.start(e.a.seqr);
  #40;
  vdin.start(e.a.seqr);
  #40;
  rdin.start(e.a.seqr);
  #40;
phase.drop_objection(this);
endtask
endclass


///////////////////////// TB TOP MODULE INSTANCE (STATIC) ///////////////////////////////////////////
module tb;

  dff_if dif();
  
  dff dut (.clk(dif.clk), .rst(dif.rst), .din(dif.din), .dout(dif.dout));

  initial 
  begin
    uvm_config_db #(virtual dff_if)::set(null, "*", "dif", dif);
    run_test("test"); 
  end
  
  initial begin
    dif.clk = 0;
  end
  
  always #10 dif.clk = ~dif.clk;
  
  initial begin
    $dumpfile("dump.vcd");
    $dumpvars;
  end
endmodule

