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

	--opcodes used by the CPU
	constant NOP	:	std_logic_vector(7 downto 0) := "00000000";	--No operation
	constant LDAWV 	: 	std_logic_vector(7 downto 0) := "00000001";	--Load A with value given after opcode
	constant LDBWV	:	std_logic_vector(7 downto 0) := "00011001"; --Load B with value given after opcode
	constant LDAFM	:	std_logic_vector(7 downto 0) := "00000010";	--Load A from memory location given after opcode
	constant LDBFM	:	std_logic_vector(7 downto 0) := "10000010";	--Load B from memory location given after opcode
	constant STA2M 	: 	std_logic_vector(7 downto 0) := "00000011";	--Store A to any RAM location
	constant STB2M 	: 	std_logic_vector(7 downto 0) := "00100011";	--Store B to any RAM location
	constant ADDM 	:	std_logic_vector(7 downto 0) := "00000100";	--Add contents of any RAM location to A

	constant INCA	:	std_logic_vector(7 downto 0) := "00000101";	--Increment A
	constant INCB	:	std_logic_vector(7 downto 0) := "00100101";	--Increment B
	constant DECRA	:	std_logic_vector(7 downto 0) := "00010011"; -- decrement A
	constant DECRB	:	std_logic_vector(7 downto 0) := "10010011"; -- decrement B

	
	constant LDSW	:	std_logic_vector(7 downto 0) := "00000111";	--Load A and B from switches (SW15-8 to A, SW7-0 to B)
	constant HALT	:	std_logic_vector(7 downto 0) := "00001000";	--stop executing instructions
	constant JUMP	:	std_logic_vector(7 downto 0) := "00001001";	--unconditional jump to new adr	
	constant ADDAB	:	std_logic_vector(7 downto 0) := "00001010";	--store the sum of A and B in A

	constant loopsentinelA	:	std_logic_vector(7 downto 0) := "00010010"; -- skip the next two bytes in program memory if A='11111111' (use case: can stop a loop [i.e. JUMP, <..adr..>] by skipping three op-codes ahead based on the state of the iterator `C`
	constant loopsentinelB	:	std_logic_vector(7 downto 0) := "00010011"; -- skip the next two bytes in program memory if B='11111111' (use case: can stop a loop [i.e. JUMP, <..adr..>] by skipping three op-codes ahead based on the state of the iterator `C`

	constant SUBBA	:	std_logic_vector(7 downto 0) := "00011010"; -- subtract B from A; store result in A
	constant CSUBA	:	std_logic_vector(7 downto 0) := "00010101"; -- used in long division; subtracts divisor from dividend

	constant DISPQA	:	std_logic_vector(7 downto 0) := "00010110";
	constant forloopsentinel	:	std_logic_vector(7 downto 0) := "00010111";

	constant ShiftAR	:	std_logic_vector(7 downto 0) := "01010111"; -- shift contents of register A once to the right
	constant ShiftBR	:	std_logic_vector(7 downto 0) := "01011000"; -- shift contents of register B once to the right

	constant CSUBNewtonRaphson	:	std_logic_vector(7 downto 0) := "01011001"; -- shift contents of register A once to the right
	constant loopsentinelNewtonRaphson :	std_logic_vector(7 downto 0) := "01011010"; -- shift contents of register A once to the right

	
  type ram_array is array (0 to 127) of std_logic_vector(7 downto 0); --128 bytes of scratchpad RAM memory
  type prog_array is array (0 to 127) of std_logic_vector(7 downto 0); --128 bytes of program memory (will be accessed
																							 --as addresses 128 to 255 or x80 to xFF)
  
   signal ram_data: ram_array := (others => x"00");							--stores data. All bytes contain zeros by default

	-- ==== ADDITION ====
  -- signal prog_data: prog_array := (LDSW, ADDAB, HALT, 			--a very short program	
											  -- others =>NOP	
											 -- );
	-- ==== DIVISION ====
	-- memory addresses  to store variables in scratchpad memory --
--	constant a : std_logic_vector(7 downto 0) := "00000001";
--	constant b : std_logic_vector(7 downto 0) := "00000010";										 
--	constant q : std_logic_vector(7 downto 0) := "00000011";
--	constant r : std_logic_vector(7 downto 0) := "00000100";
--	constant breakflag : std_logic_vector(7 downto 0) := "00000101"; -- set to 1 if CSUB does not execute
	-- division --
--	signal prog_data: prog_array := (
--		LDSW, 
--		STA2M, r, STA2M, a, STB2M, b, -- store initial values in memory
--		CSUBA,
--		STA2M, a, -- store result of subtraction to RAM
--		LDAFM, q, INCA, STA2M, q, --increment Q
--		LDAFM, a, -- restore A
--		STA2M, r, -- R = A
--		JUMP, x"87", -- jump to CSUBA to repeat the loop
--		LDAFM, q, -- display Q on A and R on B
--		LDBFM, r,
--		HALT, others => NOP);
	
	
	--Fibonnacci Sequence--
	--memory addresses to store variables in scratchpad memory--
	constant n : std_logic_vector(7 downto 0) := "00000001";
	constant b : std_logic_vector(7 downto 0) := "00000010";	
	constant sum : std_logic_vector(7 downto 0) := "00000011";
	constant a : std_logic_vector(7 downto 0) := "00000100";
	
	signal prog_data: prog_array := (
		LDSW,
		STA2M, n,
		LDAWV, x"00",
		LDBWV, x"01",
		ADDAB,
		STB2M, a,
		STA2M, b,
		LDBFM, n,
		DECRB,
		STB2M, n,
		forloopsentinel,
		LDAFM, a,
		LDBFM, b,
		jump, x"87",
		LDAFM, a,
		HALT, others => NOP);
		
		
		-- ===== NEWTON-RAPHSON sqrt finding =====
		-- -- memory addresses  to store variables in scratchpad memory --
		-- constant a : std_logic_vector(7 downto 0) := "00000001";
		-- constant b : std_logic_vector(7 downto 0) := "00000010";	 -- last iteration value									 
		-- constant q : std_logic_vector(7 downto 0) := "00000011";
		-- constant last : std_logic_vector(7 downto 0) := "00000100";
		-- constant n : std_logic_vector(7 downto 0) := "00000101"; -- original number
		-- constant iterator : std_logic_vector(7 downto 0) := "00000110"; -- loop iterator
	
		
		-- -- newton-raphson method of finding floor(sqrt(n))
		-- signal prog_data: prog_array := (
			
		-- 	LDSW, 
		-- 	STA2M, n, -- let n be the number of which to take the sqrt --STB2M, b, -- store initial values in memory
	
		-- 	LDAWV, "00000000", -- counts the number of loop iterations
		-- 	STA2M, iterator,
	
		-- 	LDBWV, "00000111", -- 7 in base 10; initial guess
		-- 	STB2M, last, -- register B will carry the previous iteration's guess
	
			
		-- 	-- beginning of next iteration of newton-raphson
		-- 	LDBWV, x"00", STB2M, q,-- reset quotient counter for new division process
		-- 	LDBFM, last, 
			
		-- 	-- division --
		-- 	LDAFM, n, -- make sure we have the original value of N
		-- 	CSUBNewtonRaphson, -- will need to edit the magic number in this function to skip to end of iteration
		-- 	STA2M, a, -- store result of subtraction to RAM
		-- 	LDAFM, q, INCA, STA2M, q, --increment Q
		-- 	LDAFM, a, -- restore A
		-- 	JUMP, x"93", -- jump to CSUBNewtonRaphson to repeat the loop
	
		-- 	LDAFM, q, -- load A with value of quotient (i.e. floor of division result)
			
		-- 	-- actual newton-raphson stuff -- 
		-- 	-- LDAFM, last, -- load last iteration guess -- B should still have `last` in it
		-- 	ADDAB, -- add last iteration guess (B) to quotient (A); store in A
		-- 	ShiftAR, -- shift A once to the right (divide by 2)
		-- 	STA2M, last, -- record the current guess in memory
		-- 	LDBFM, iterator, INCB, STB2M, iterator, -- increment loop count iterator
	
		-- 	loopsentinelNewtonRaphson, -- jump three ahead if iteration (register B) reaches max of 3 (arbitrary for convergence)
		-- 	JUMP, x"8B", -- jump to next iteration of newton-raphson iteration (`LDBFM, last`)
		-- 	-- last guess will already be on register A for display when we jump to HALT
		-- 	LDBFM, n, -- display input number on B
		-- 	HALT, others => NOP);

	
	-- signal prog_data: prog_array := (LDAWV, x"01", LDBWV, x"09", NOP, HALT, others => NOP); -- this works as expected; 1 on A and 9 on B
--   signal prog_data: prog_array := (LDSW, ADDAB, NOP, LDSW, MULTAB, NOP, LDSW, LDSW, DIVAB, JUMP, x"80", HALT, 			--a very short program	
-- 											  others =>NOP	
-- 											 );	

	-- this is for multiplication -- based on page 6 of https://www.eng.auburn.edu/~nelson/courses/elec4200/Slides/VHDL%207%20Multiplier%20Example.pdf
	-- following this algorithm except MAQ=AMB (substituted); loop add, shift 8 times, once per each of 8 bits of multiplicands
-- signal prog_data: prog_array := (LDSW, NOP, CADDMA, WS,CADDMA, WS,CADDMA, WS,CADDMA, WS,CADDMA, WS,CADDMA, WS,CADDMA, WS,CADDMA, WS, CONCATMB, HALT, 			--a very short program	
-- 											 others =>NOP	
-- 											);	

-- an attempt to condense the control flow of the multiplication algorithm using a `for` loop
--signal prog_data: prog_array := (LDSW, NOP, CADDMA, WS, DECRC, loopsentinel, JUMP, x"82", CONCATMB, HALT,
 											 --others =>NOP	
 											--);	


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
