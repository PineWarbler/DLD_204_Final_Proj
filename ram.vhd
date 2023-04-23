library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

entity ram is
	port(	reset		:	in std_logic;	
			clk		:	in std_logic;								--cpu clock
			ram_di	:	in std_logic_vector(7 downto 0);		--ram data in (matched with CPU_do)
			ram_do	:	out std_logic_vector(7 downto 0);	--ram data out (matched with CPU_di)
			adr		:	in std_logic_vector(7 downto 0);		--address
			wren		:	in std_logic								--write enable
		 );
end ram;

architecture behavior of ram is

	--op codes used by the CPU
	constant NOP	:	std_logic_vector(7 downto 0) := "00000000";	--No operation
	constant LDAI 	: 	std_logic_vector(7 downto 0) := "00000001";	--Load A immediate (from next mem loc after op code)
	constant LDAM	:	std_logic_vector(7 downto 0) := "00000010";	--Load A from any RAM location -- how is this different from the above?
	constant STAM 	: 	std_logic_vector(7 downto 0) := "00000011";	--Store A to any RAM location
	constant STBM 	: 	std_logic_vector(7 downto 0) := "00100011";	--Store B to any RAM location
	constant ADDM 	:	std_logic_vector(7 downto 0) := "00000100";	--Add contents of any RAM location to A
	constant INCA	:	std_logic_vector(7 downto 0) := "00000101";	--Increment A
	constant INCB	:	std_logic_vector(7 downto 0) := "00100101";	--Increment B
	constant JBNZ	:	std_logic_vector(7 downto 0) := "00000110";	--Jump to new adr if contents of B not zero
	constant LDSW	:	std_logic_vector(7 downto 0) := "00000111";	--Load A and B from switches (SW15-8 to A, SW7-0 to B)
	constant HALT	:	std_logic_vector(7 downto 0) := "00001000";	--stop executing instructions
	constant JUMP	:	std_logic_vector(7 downto 0) := "00001001";	--unconditional jump to new adr	
	constant ADDAB	:	std_logic_vector(7 downto 0) := "00001010";	--store the sum of A and B in A
	constant MULTAB	:	std_logic_vector(7 downto 0) := "00001011";	--store the product of A and B in A
	constant DIVAB	:	std_logic_vector(7 downto 0) := "00001110";	-- store floor(A/B) in A and store mod(A/B) in B
	constant CADDMA	:	std_logic_vector(7 downto 0) := "00001111";	-- Conditionally ADD M and A (store A<=A+M if B(0)==1)
	constant WS		:	std_logic_vector(7 downto 0) := "00010000"; -- waterfall shift. right shift M and right shift B, but store "bumped-off"bit of M in MSB of B
	constant CONCATMB		:	std_logic_vector(7 downto 0) := "00010001"; -- final step of the multiplication add-and-shift algorithm. -- final step of the multiplication add-and-shift algorithm.  Concatenate A and Q, keeping only 8 LSBs; store in A Concatenate A and Q, keeping only 8 LSBs
	constant loopsentinel	:	std_logic_vector(7 downto 0) := "00010010"; -- skip the next two bytes in program memory if C=0 (use case: can stop a loop [i.e. JUMP, <..adr..>] by skipping three op-codes ahead based on the state of the iterator `C`
	constant DECRC	:	std_logic_vector(7 downto 0) := "00010011"; -- decrement C
	constant LDCI	:	std_logic_vector(7 downto 0) := "00010100"; -- load C immediately from memory location given after op code
	constant CSUB	:	std_logic_vector(7 downto 0) := "00010101"; -- used in long division; subtracts divisor from dividend
	constant specialDivFunc	:	std_logic_vector(7 downto 0) := "00010110"; -- used in long division; left shifts M and sets the LSB of M equal to bit C of the dividend (A)
	constant finishDiv	:	std_logic_vector(7 downto 0) := "00010111"; -- used in long division; does some variable storage shifting to display the division results on A and B

	
  type ram_array is array (0 to 127) of std_logic_vector(7 downto 0); --128 bytes of scratchpad RAM memory
  type prog_array is array (0 to 127) of std_logic_vector(7 downto 0); --128 bytes of program memory (will be accessed
																							 --as addresses 128 to 255 or x80 to xFF)
  
	signal ram_data: ram_array := (others => x"00");							--stores data. All bytes contain zeros by default

  signal prog_data: prog_array := (LDSW, ADDAB, HALT, 			--a very short program	
											  others =>NOP	
											 );	
--   signal prog_data: prog_array := (LDSW, ADDAB, NOP, LDSW, MULTAB, NOP, LDSW, LDSW, DIVAB, JUMP, x"80", HALT, 			--a very short program	
-- 											  others =>NOP	
-- 											 );	

	-- this is for multiplication -- based on page 6 of https://www.eng.auburn.edu/~nelson/courses/elec4200/Slides/VHDL%207%20Multiplier%20Example.pdf
	-- following this algorithm except MAQ=AMB (substituted); loop add, shift 8 times, once per each of 8 bits of multiplicands
-- signal prog_data: prog_array := (LDSW, NOP, CADDMA, WS,CADDMA, WS,CADDMA, WS,CADDMA, WS,CADDMA, WS,CADDMA, WS,CADDMA, WS,CADDMA, WS, CONCATMB, HALT, 			--a very short program	
-- 											 others =>NOP	
-- 											);	

-- an attempt to condense the control flow of the multiplication algorithm using a `for` loop
-- signal prog_data: prog_array := (LDSW, NOP, CADDMA, WS, DECRC, loopsentinel, JUMP, x"82", CONCATMB, HALT,
-- 											 others =>NOP	
-- 											);	


-- this is for long division; I think an iterated loop implementation is the only option
-- this algorithm and component functions are based on https://en.wikipedia.org/wiki/Division_algorithm#Integer_division_(unsigned)_with_remainder
--signal prog_data: prog_array := (LDSW, NOP, specialDivFunc, CSUB, DECRC, loopsentinel, JUMP, x"82", finishDiv, NOP, HALT,
											 --others =>NOP	
											--);	


  begin

    process(clk, wren, reset, adr)
      variable address : integer := 0;
    begin
      address := to_integer(unsigned(adr));	--convert address to an integer number so we can do math with it

      if reset = '0' then							--clear RAM if reset
        ram_data <= (others => x"00");
		  ram_do <= prog_data(0);					--put first program byte on data out bus
		  
      elsif rising_edge(clk) then				--synchronous data writes to RAM
			if ((address<128) and (wren='1'))  then	--addresses 0 to 127 are for data
				ram_data(address) <= ram_di; 		--Write to RAM address
			end if;
		end if;

		if (address<128) then						--output data depends only on address, not clk edge
			ram_do <= ram_data(address);			--place ram byte on outputs
		else
			ram_do <= prog_data(address-128);	--place program byte on output
		end if;
    end process;
END behavior;