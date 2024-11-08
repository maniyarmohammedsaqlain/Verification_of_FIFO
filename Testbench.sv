interface fifo_if;
  logic clock, rd, wr;         
  logic full, empty;           
  logic [7:0] data_in;         
  logic [7:0] data_out;        
  logic rst;                   
endinterface

//TRANSACTION
class transaction;
  rand bit oper;          
  bit rd, wr;            
  rand bit [7:0] data_in;      
  bit full, empty;        
  bit [7:0] data_out;   
  constraint oper_ctrl {  
    oper dist {1 :/ 50 , 0 :/ 50}; 
  }
endclass 
class generator;
  transaction tr;          
  mailbox gen2drv;  
  int count = 0;       
  int i = 0;                
  event next;               
  event done;               
  function new(mailbox gen2drv,event next);
    this.gen2drv = gen2drv;
    this.next=next;
    tr = new();
  endfunction; 
  task run(); 
    repeat (count) begin
      assert (tr.randomize) else $error("Randomization failed");
      i++;
      gen2drv.put(tr);
      $display("[GEN] : Oper : %0d iteration : %0d data_in is %d", tr.oper, i,tr.data_in);
      @(next);
    end -> done;
  endtask
endclass
//DRIVER
class driver;
  virtual fifo_if fif;     
  mailbox gen2drv; 
  transaction trans;      
  function new(mailbox gen2drv,virtual fifo_if fif);
    this.gen2drv = gen2drv;
    this.fif=fif;
    trans=new();
  endfunction; 
  task reset();
    fif.rst <= 1'b1;
    fif.rd <= 1'b0;
    fif.wr <= 1'b0;
    fif.data_in <= 0;
    repeat (5) @(posedge fif.clock);
    fif.rst <= 1'b0;
    $display("[DRV] : DUT Reset Done");
    $display("------------------------------------------");
  endtask
  task write();
    @(posedge fif.clock);
    fif.rst <= 1'b0;
    fif.rd <= 1'b0;
    fif.wr <= 1'b1;
    fif.data_in <= trans.data_in;
    @(posedge fif.clock);
    fif.wr <= 1'b0;
    $display("[DRV] : DATA WRITE  data : %0d", fif.data_in);  
  endtask
  task read();  
    @(posedge fif.clock);
    fif.rst <= 1'b0;
    fif.rd <= 1'b1;
    fif.wr <= 1'b0;
    @(posedge fif.clock);
    fif.rd <= 1'b0;      
    $display("[DRV] : DATA READ");  
  endtask
  task run();
    forever begin
      gen2drv.get(trans);  
      if (trans.oper == 1'b1)
        write();
      else
        read();
    end
  endtask
endclass
//MONITOR
class monitor;
  virtual fifo_if fif;     
  mailbox mon2scb; 
  transaction tr;         
  function new(mailbox mon2scb,virtual fifo_if fif);
    this.mon2scb = mon2scb;     
    this.fif=fif;
  endfunction;
  task run();
    tr = new();
    forever begin
      repeat (2) @(posedge fif.clock);
      tr.wr = fif.wr;
      tr.rd = fif.rd;
      tr.data_in = fif.data_in;
      tr.full = fif.full;
      tr.empty = fif.empty; 
      @(posedge fif.clock);
      tr.data_out = fif.data_out;
      mon2scb.put(tr);
      $display("[MON] : Wr:%0d rd:%0d din:%0d dout:%0d full:%0d empty:%0d", tr.wr, tr.rd, tr.data_in, tr.data_out, tr.full, tr.empty);
    end
  endtask
endclass
class scoreboard;
  mailbox  mon2scb; 
  transaction tr;         
  event next;
  bit [7:0] din[$];     
  bit [7:0] temp;         
  int err = 0;       
  function new(mailbox mon2scb,event next);
    this.mon2scb = mon2scb;     
    this.next=next;
  endfunction;
  task run();
    forever begin
      mon2scb.get(tr);
      $display("[SCO] : Wr:%0d rd:%0d din:%0d dout:%0d full:%0d empty:%0d", tr.wr, tr.rd, tr.data_in, tr.data_out, tr.full, tr.empty);
      if (tr.wr == 1'b1) begin
        if (tr.full == 1'b0) begin
          din.push_front(tr.data_in);
          $display("[SCO] : DATA STORED IN QUEUE :%0d", tr.data_in);
        end
        else begin
          $display("[SCO] : FIFO is full");
        end
        $display("--------------------------------------"); 
      end
      if (tr.rd == 1'b1) begin
        if (tr.empty == 1'b0) begin  
          temp = din.pop_back();
          if (tr.data_out == temp)
            $display("[SCO] : DATA MATCH",temp);
          else begin
            $error("[SCO] : DATA MISMATCH");
            err++;
          end
        end
        else begin
          $display("[SCO] : FIFO IS EMPTY");
        end
        $display("--------------------------------------"); 
      end
      -> next;
    end
  endtask
endclass
class environment;
  generator gen;
  driver drv;
  monitor mon;
  scoreboard sco;
  mailbox  gen2drv; 
  mailbox  mon2scb; 
  event nextgs;
  virtual fifo_if fif;
  function new(virtual fifo_if fif);
    gen2drv = new();
    gen = new(gen2drv,nextgs);
    drv = new(gen2drv,fif);
    mon2scb = new();
    mon = new(mon2scb,fif);
    sco = new(mon2scb,nextgs);
    this.fif = fif;
  endfunction
  task pre_test();
    drv.reset();
  endtask
  task test();
    fork
      gen.run();
      drv.run();
      mon.run();
      sco.run();
    join_any
  endtask
  task run();
    pre_test();
    test();
  endtask
endclass
module tb;
  fifo_if fif();
  FIFO dut (fif.clock, fif.rst, fif.wr, fif.rd, fif.data_in, fif.data_out, fif.empty, fif.full);
  initial begin
    fif.clock <= 0;
  end
  always #10 fif.clock <= ~fif.clock;
  environment env;
  initial begin
    env = new(fif);
    env.gen.count = 10;
    env.run();
  end
  initial
    begin
      #750 $finish();
    end   
endmodule
