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

	--op codes used by the CPU.  So we can use mnemonics to load program memory instead of
	--writing all the hex numbers.  You don't have to use these.  You can make up your own.  
	--You will need more than these to accomplish all the tasks.
	constant NOP	:	std_logic_vector(7 downto 0) := "00000000";	--No operation
	constant LDAI 	: 	std_logic_vector(7 downto 0) := "00000001";	--Load A immediate (from next mem loc after op code)
	constant LDAM	:	std_logic_vector(7 downto 0) := "00000010";	--Load A from any RAM location
	constant STAM 	: 	std_logic_vector(7 downto 0) := "00000011";	--Store A to any RAM location
	constant ADDM 	:	std_logic_vector(7 downto 0) := "00000100";	--Add contents of any RAM location to A
	constant INCA	:	std_logic_vector(7 downto 0) := "00000101";	--Increment A
	constant JBNZ	:	std_logic_vector(7 downto 0) := "00000111";	--Jump to new adr if contents of B not zero
	constant LDSW	:	std_logic_vector(7 downto 0) := "00001000";	--Load A and B from switches (SW15-8 to A, SW7-0 to B)
	constant HALT	:	std_logic_vector(7 downto 0) := "00001011";	--stop executing instructions
	constant JUMP	:	std_logic_vector(7 downto 0) := "00001001";	--unconditional jump to new adr	
	constant ADDAB		:	std_logic_vector(7 downto 0) := "00001010";	--store the sum of A and B in A
	constant MULTAB	:	std_logic_vector(7 downto 0) := "00001011";	--store the product of A and B in A
	constant DIVAB		:	std_logic_vector(7 downto 0) := "00001100";	-- store floor(A/B) in A and store mod(A/B) in B
	
  type ram_array is array (0 to 127) of std_logic_vector(7 downto 0); --128 bytes of scratchpad RAM memory
  type prog_array is array (0 to 127) of std_logic_vector(7 downto 0); --128 bytes of program memory (will be accessed
																							 --as addresses 128 to 255 or x80 to xFF)
  
  signal ram_data: ram_array := (others => x"00");							--stores data. All bytes contain zeros by default
  signal prog_data: prog_array := (LDSW, ADDAB, HALT, 			--a very short program	
											  others =>NOP	
											 );	

 
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