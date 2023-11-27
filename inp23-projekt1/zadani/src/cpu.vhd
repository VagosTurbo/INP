-- cpu.vhd: Simple 8-bit CPU (BrainFuck interpreter)
-- Copyright (C) 2023 Brno University of Technology,
--                    Faculty of Information Technology
-- Author: Boris Semanco, xseman06@stud.fit.vutbr.cz
--
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
 port (
   CLK   : in std_logic;  -- hodinovy signal
   RESET : in std_logic;  -- asynchronni reset procesoru
   EN    : in std_logic;  -- povoleni cinnosti procesoru
 
   -- synchronni pamet RAM
   DATA_ADDR  : out std_logic_vector(12 downto 0); -- adresa do pameti
   DATA_WDATA : out std_logic_vector(7 downto 0); -- mem[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
   DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
   DATA_RDWR  : out std_logic;                    -- cteni (0) / zapis (1)
   DATA_EN    : out std_logic;                    -- povoleni cinnosti
   
   -- vstupni port
   IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA <- stav klavesnice pokud IN_VLD='1' a IN_REQ='1'
   IN_VLD    : in std_logic;                      -- data platna
   IN_REQ    : out std_logic;                     -- pozadavek na vstup data
   
   -- vystupni port
   OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
   OUT_BUSY : in std_logic;                       -- LCD je zaneprazdnen (1), nelze zapisovat
   OUT_WE   : out std_logic;                      -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'

   -- stavove signaly
   READY    : out std_logic;                      -- hodnota 1 znamena, ze byl procesor inicializovan a zacina vykonavat program
   DONE     : out std_logic                       -- hodnota 1 znamena, ze procesor ukoncil vykonavani programu (narazil na instrukci halt)
 );
end cpu;


-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is

  type cpu_state is (
    start_state,
    init_state,
    fetch_state,
    decode_state,
    inc_state,
    dec_state,
    putchar_state,
    getchar_state,
    while_state, 
    while2_state,
    while_end_state,
    while_end2_state, 
    while_end3_state, 
    while_end4_state,
    break_state,
    halt_state
  );
  signal curr_state: cpu_state := init_state;
  signal next_state: cpu_state;

  signal pc_reg   : std_logic_vector(12 downto 0);
  signal pc_inc   : std_logic;
  signal pc_dec   : std_logic;

  signal ptr_reg  : std_logic_vector(12 downto 0);
  signal ptr_inc  : std_logic;
  signal ptr_dec  : std_logic;

  signal cnt_reg  : std_logic_vector(7 downto 0);
  signal cnt_inc  : std_logic;
  signal cnt_dec  : std_logic;

  --multiplexors
  signal mx1_select  :  std_logic;
  signal mx2_select  :  std_logic_vector(1 downto 0);

  -- variable for break
  signal in_loop_condition: std_logic := '0';

begin

  pc: process (RESET, CLK, pc_inc, pc_dec) is 
    begin
        if RESET = '1' then 
            pc_reg <= (others => '0');
        elsif rising_edge(CLK) then
            if pc_inc = '1' then 
                pc_reg <= pc_reg + 1;
            elsif pc_dec = '1' then
                pc_reg <= pc_reg - 1;
            end if;
        end if;
    end process;

    ptr: process (RESET, CLK, ptr_inc, ptr_dec) is 
    begin
        if RESET = '1' then
            ptr_reg <= (others => '0');
        elsif rising_edge(CLK) then
            if ptr_inc = '1' then
                ptr_reg <= ptr_reg + 1;
            elsif ptr_dec = '1' then
                ptr_reg <= ptr_reg - 1;
            end if;
        end if;
    end process;

    cnt: process (RESET, CLK, cnt_inc, cnt_dec) is
      begin
          if RESET = '1' then
              cnt_reg <= (others => '0');
          elsif rising_edge(CLK) then
              if cnt_inc = '1' then
                  cnt_reg <= cnt_reg + 1;
              elsif cnt_dec = '1' then
                  cnt_reg <= cnt_reg - 1;
              end if;
          end if;
      end process;

    -- mx1
    with mx1_select select
    DATA_ADDR <= pc_reg when '0',
            ptr_reg when '1',
            (others => '0') when others;

  
    -- mx2
    with mx2_select select
    DATA_WDATA <= IN_DATA when "11",
                  DATA_RDATA + 1 when "01",
                  DATA_RDATA - 1 when "10",
                  (others => '0') when others;


  fsm_logic: process(CLK, RESET, EN, curr_state, next_state) is   
  begin
    if (RESET = '1') then
      curr_state <= start_state;
    elsif (rising_edge(CLK)) then
      if (EN = '1') then
        curr_state <= next_state;
      end if;
    end if; 
  end process;

  fsm: process(CLK, RESET, curr_state, next_state) is
    begin
      DATA_EN <= '0';
      OUT_WE <= '0';
      IN_REQ <= '0';
      OUT_DATA <= (others => '0');
      READY <= '0';
      DONE <= '0';

      pc_inc <= '0';
      pc_dec <= '0';
      ptr_inc <= '0';
      ptr_dec <= '0';
      cnt_inc <= '0';
      cnt_dec <= '0';

      mx1_select <= '0';
      mx2_select <= "00";
    
      case curr_state is

        when start_state =>
          next_state <= init_state;

        when init_state =>
          DATA_EN <= '1';                 -- enable data access
          DATA_RDWR <= '0';               -- select read mode
          mx1_select <= '1';              -- select ptr address
          
          if DATA_RDATA = x"40" then      -- if '@' comes
            READY <= '1';                 -- select READY to 1 so init is completed
            next_state <= fetch_state;    -- go to fetch_state
          else
            ptr_inc <= '1';               -- increment ptr
          end if;

        when fetch_state =>
          DATA_EN <= '1';                 -- enable data access
          mx1_select <= '0';              -- select pc address
          DATA_RDWR <= '0';               -- select read mode
          next_state <= decode_state;   

        when decode_state =>
          -- decoding instructions
          case DATA_RDATA is              -- reads data on pc index

            when x"3E" => -- > ptr++
              ptr_inc <= '1';             -- increment ptr
              pc_inc <= '1';              -- next instruction
              next_state <= fetch_state;  -- go back to fetch_state

            when x"3C" => -- < ptr--
              ptr_dec <= '1';             -- decrement ptr
              pc_inc <= '1';              -- next instruction
              next_state <= fetch_state;

            when x"2B" => -- + *ptr++
              DATA_EN <= '1';             -- enable data access
              DATA_RDWR <= '0';           -- select read mode
              mx1_select <= '1';          -- select ptr address
              next_state <= inc_state;    -- move to update memory

            when x"2D" => -- - *ptr--
              DATA_EN <= '1';             -- enable data access
              DATA_RDWR <= '0';           -- select read mode
              mx1_select <= '1';          -- select ptr address
              next_state <= dec_state;    -- move to update memory

            when x"5B" => -- [ while(*ptr){
              DATA_EN <= '1';                 -- enable data access
              DATA_RDWR <= '0';               -- select read mode
              mx1_select <= '1';              -- select ptr address
              pc_inc <= '1';                  -- next instruction
              in_loop_condition <= '1';       -- set the loop condition flag
              if DATA_RDATA = 0 then          -- check if data at ptr is zero
                cnt_inc <= '1';               -- incremnt loop counter
                next_state <= while2_state;   -- go to loop body
              else
                next_state <= fetch_state;    -- skip loop and continue fetching
              end if;

            when x"5D" =>  -- ] }  
              DATA_EN <= '1';                 -- enable data access 
              DATA_RDWR <= '0';               -- select read mode
              mx1_select <= '1';              -- select ptr address
              in_loop_condition <= '0';       -- clear the loop condition flag
              next_state <= while_end_state;  -- go to loop ending state  

            when x"7E" =>                     -- ~ break
              if (in_loop_condition = '1') then
                next_state <= break_state;    -- if in loop go to break_state
              else
                next_state <= halt_state;     -- break was called 
              end if;

            when x"2E" =>  -- . putchar(*ptr)
              DATA_EN <= '1';                 -- enable data access
              mx1_select <= '1';              -- select ptr address
              next_state <= putchar_state;    -- go to putchar state

            when x"2C" =>                     -- *ptr = getchar()
              IN_REQ <= '1';                  -- request input    
              if (IN_VLD = '1') then          
                next_state <= getchar_state;  -- if input valid, go to getchar state
              else
                next_state <= decode_state;   -- input is not valid, continue decoding
              end if;
            when x"40" =>   -- @ return
              next_state <= halt_state;       -- go to halt_state
            when others =>                        
              pc_inc <= '1';                  -- if unknown instruction, move to next one
              next_state <= fetch_state;
          end case;

      when halt_state =>
        READY <= '1';                     -- set READY to 1
        DONE <= '1';                      -- set DONE to 1 which terminates program

      when inc_state =>
        DATA_EN <= '1';                   -- enable data access
        DATA_RDWR <= '1';                 -- select write mode
        mx1_select <= '1';                -- select ptr address
        mx2_select <= "01";               -- select increment operation
        pc_inc <= '1';                    -- next instruction
        next_state <= fetch_state;        -- go back to fetch_state

      when dec_state =>
        DATA_EN <= '1';                   -- enable data access
        DATA_RDWR <= '1';                 -- select write mode
        mx1_select <= '1';                -- select ptr address
        mx2_select <= "10";               -- select decrement operation
        pc_inc <= '1';                    -- next instruction
        next_state <= fetch_state;        -- go back to fetch_state

      when putchar_state =>
        if (OUT_BUSY = '0') then          -- only if lcd is not busy
        OUT_DATA <= DATA_RDATA;           -- write DATA_RDATA to OUT_DATA
          OUT_WE <= '1';                  -- write OUT_DATA to lcd
          pc_inc <= '1';                  -- next instruction
          next_state <= fetch_state;
        else                              -- if lcd is busy try again
          DATA_EN <= '1';                 -- keep data enabled
          mx1_select <= '1';              -- keep ptr selected
        end if ;

      when getchar_state =>
        DATA_EN <= '1';                   -- enable data
        DATA_RDWR <= '1';                 -- select write mode
        mx1_select <= '1';                -- select ptr address
        mx2_select <= "11";               -- write DATA_IN
        pc_inc <= '1';                    -- next instruction
        next_state <= fetch_state;
            
  
      when while_state =>
        if cnt_reg = 0 then
          next_state <= fetch_state;      -- if the counter is 0 exit the loop
        else 
          DATA_EN <= '1';                 -- enable data access
          DATA_RDWR <= '0';               -- select read mode
          mx1_select <= '0';              -- select pc adress
          next_state <= while2_state;     -- move to next while state
        end if;
  
      when while2_state =>                -- update counter based of [ or ]
        if DATA_RDATA = x"5B" then
          cnt_inc <= '1';                 -- if [ comes increment the counter
        elsif DATA_RDATA = x"5D" then
          cnt_dec <= '1';                 -- if ] comes decremet the counter
        end if;
        pc_inc <= '1';                    -- next instruction
        next_state <= while_state;        -- loop back to chcek condition
          
      when while_end_state =>
        if DATA_RDATA = 0 then            -- chcek if the loop counter is zero
          pc_inc <= '1';                  -- next instruction
          next_state <= fetch_state;      -- exit loop if the counter is zero
        else
          cnt_inc <= '1';                 -- increment the loop counter
          pc_dec <= '1';                  -- move to previous instruction
          next_state <= while_end2_state; -- continue chcecking loop condition
        end if;
      
      when while_end2_state => 
        if cnt_reg = 0 then               -- check if the loop counter is zero
          next_state <= fetch_state;      -- exit loop
        else 
          DATA_EN <= '1';                 -- enable data access
          DATA_RDWR <= '0';               -- select read mode
          mx1_select <= '0';              -- select pc address
          next_state <= while_end3_state; -- continue chcecking loop condition
        end if;
  
      when while_end3_state =>
        if DATA_RDATA = x"5B" then        -- adjust loop counter based on [ or ]
          cnt_dec <= '1';                 -- decrement when [ was found      
        elsif DATA_RDATA = x"5D" then   
          cnt_inc <= '1';                 -- increment when ] was found
        end if;
        next_state <= while_end4_state;   -- move to conclude loop exit condition
  
      when while_end4_state =>
        if cnt_reg = 0 then               -- check if the loop counter is zero
          pc_inc <= '1';                  -- next instruction
          next_state <= fetch_state;      -- exit loop
        else        
          pc_dec <= '1';                  -- previous instruction
          next_state <= while_end2_state; -- continue checking loop condition
        end if;


      when break_state =>
        if (in_loop_condition = '1') then   -- only if its in loop
          DATA_EN <= '1';                   -- enable data
          DATA_RDWR <= '0';                 -- select read mode
          mx1_select <= '0';                -- select pc
          
          if DATA_RDATA = x"5D" then        -- keeps skipping instructions till ']' comes
            next_state <= fetch_state;      -- go back fetching
          else
            pc_inc <= '1';                  -- next instruction
          end if;
        else
          next_state <= halt_state;         -- if somehow '~' was called outside loop terminate program
        end if;
      
      when others =>
      next_state <= fetch_state;
      end case;
  end process;
end behavioral;
