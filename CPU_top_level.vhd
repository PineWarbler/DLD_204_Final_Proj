library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

entity cpu_top_level is
	port	( 	KEY	:	in		std_logic_vector(1 downto 0);		--reset is KEY1, cpu clock is KEY0
				SW		:	in		std_logic_vector(15 downto 0);	--switch inputs
				LEDR	:	out	std_logic_vector(17 downto 0);	--for debug display
				LEDG	:	out	std_logic_vector(7 downto 0);		--for debug display
				HEX7	:	out 	std_logic_vector(6 downto 0);		--displays hi nibble of PC in hex
				HEX6	:	out	std_logic_vector(6 downto 0);		--displays lo nibble of PC in hex
				HEX5	:	out 	std_logic_vector(6 downto 0);		--displays hi nibble of current state code in hex
				HEX4	:	out	std_logic_vector(6 downto 0);		--displays lo nibble of current state code in hex
				HEX3	:	out	std_logic_vector(6 downto 0);		--displays hi nibble of accum A in hex
				HEX2	:	out	std_logic_vector(6 downto 0);		--displays lo nibble of accum A in hex
				HEX1	:	out	std_logic_vector(6 downto 0);		--displays hi nibble of accum B in hex
				HEX0	:	out	std_logic_vector(6 downto 0);		--displays lo nibble of accum B in hex
				CLOCK_50 : in	std_logic								--used by switch debouncer. Can also use for clk when debugged.
			);
end cpu_top_level;

architecture behavior of cpu_top_level is

	signal	clk		: 	std_logic;									--test cpu clock mapped from key0
	signal	cpu_di	:	std_logic_vector(7 downto 0);			--input data bus to CPU from RAM
	signal	cpu_do	:	std_logic_vector(7 downto 0);			--output data bus from CPU to RAM
	signal	adr		:	std_logic_vector(7 downto 0);			--address bus to RAM
	signal	wren		:	std_logic;									--write enable (1= write to RAM, 0= read from RAM)
	signal	pc			:  std_logic_vector(7 downto 0);			--program counter. Always points to op code of next instruction
	signal 	A			:	std_logic_vector(7 downto 0);			--accumulator A
	signal	B			:	std_logic_vector(7 downto 0);			--accumulator B
	signal	curr_state:	std_logic_vector(7 downto 0);			--for display of current state code
	signal 	reset		:	std_logic;									--activated by key1
	
	component cpu
		port(	reset		: 	in std_logic;
				clk		:	in	std_logic;
				cpu_di	:	in std_logic_vector(7 downto 0);	--input data bus (display on LEDR7:0)
				cpu_do	:	out std_logic_vector(7 downto 0);	--output data bus (display on LEDR15:8)
				adr		:	out std_logic_vector(7 downto 0);	--address bus (display on LEDG7:0)
				wren		:	out std_logic;								--write enable (1= write to mem, 0= read from mem). Display on LEDR16	
				pc_disp	:	out std_logic_vector(7 downto 0);	--program counter to display on HEX7:HEX6
				A_disp	:	out std_logic_vector(7 downto 0);	--accumulator A display on HEX3:HEX2
				B_disp	:	out std_logic_vector(7 downto 0);	--accumulator B display on HEX1:HEX0
				state_disp:	out std_logic_vector(7 downto 0);	--to display current state code on HEX5:HEX4
				switches	:	in	std_logic_vector(15 downto 0)		--for user-controlled input
			 );
	end component;

	component ram
		port(	reset		:	in std_logic;	
				clk		:	in std_logic;								--cpu clock
				ram_di	:	in std_logic_vector(7 downto 0);		--ram data in (mapped to cpu_do)
				ram_do	:	out std_logic_vector(7 downto 0);	--ram data out (mapped to cpu_di)
				adr		:	in std_logic_vector(7 downto 0);		--address (msbit=0 for ram)
				wren		:	in std_logic								--write enable
			 );
	end component; 
	
	component sevenSeg														  --you will use your own 7seg decoder here
		port(	num_to_display		: in std_logic_vector(3 downto 0); -- 4-bit number to be displayed
				HEX_display	: out std_logic_vector(6 downto 0) 		  -- 7-seg display to be used.  Remember LEDs are active low
			 );
	end component;
	
	component debounce IS							--I found switch debounce VHDL code online.  You can do the same.
	  GENERIC(
		 clk_freq    : INTEGER := 50_000_000;  --system clock frequency in Hz
		 stable_time : INTEGER := 10);         --time button must remain stable in msec
	  PORT(
		 clk     : IN  STD_LOGIC;  --input clock
		 reset_n : IN  STD_LOGIC;  --asynchronous active low reset
		 button  : IN  STD_LOGIC;  --input signal to be debounced
		 result  : OUT STD_LOGIC); --debounced signal
	END component;
	
begin
	
		debounce1: debounce port map(CLOCK_50,'1',KEY(1),reset);		--debounced key1 will serve as reset
		debounce2: debounce port map(CLOCK_50,'1',KEY(0),clk);		--debounced key0 will serve as clk
		cpu1: cpu port map(reset,clk,cpu_di,cpu_do,adr,wren,pc,A,B,curr_state,SW(15 downto 0));--instantiate cpu
		ram1:	ram port map(reset,clk,cpu_do,cpu_di,adr,wren);			--instantiate ram
		pchi:	sevenSeg port map(pc(7 downto 4),HEX7);					--display hi nibble of pc on HEX7
		pclo:	sevenSeg port map(pc(3 downto 0),HEX6);					--display lo nibble of pc on HEX6
		cshi:	sevenSeg port map(curr_state(7 downto 4),HEX5);			--display hi nibble of curr state code on HEX5
		cslo: sevenSeg port map(curr_state(3 downto 0),HEX4);			--display lo nibble of state code on HEX4
		Ahi:	sevenSeg port map(A(7 downto 4),HEX3);						--display hi nibble of Accum A on HEX3
		Alo:	sevenSeg port map(A(3 downto 0),HEX2);						--display lo nibble of Accum A on HEX2
		Bhi:	sevenSeg port map(B(7 downto 4),HEX1);						--display hi nibble of Accum B on HEX1
		Blo:	sevenSeg port map(B(3 downto 0),HEX0);						--display lo nibble of ACCum B on HEX0
		
		LEDR(7 downto 0) <= cpu_di;											--debug display of cpu input data on LEDR7:0
		LEDR(15 downto 8) <= cpu_do;											--debug display of cpu output data on LEDR15:8
		LEDR(16) <= wren;															--debug display of write enable on LEDR16
		LEDG <= adr;																--debug display of address bus on LEDG7:0
end;