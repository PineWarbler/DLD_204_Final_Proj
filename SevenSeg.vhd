-- Altera Lab 1 Part 4: 
-- Control 7-segment display given 4-bit input
-- Assuming active-low display
-- 
-- Tested 03/14/21 LKR
-- Requires knowledge of processes, signals and std_logic_vectors

-- This is where libraries are included
library ieee;
use ieee.std_logic_1164.all;


-- Declare entity ports
entity SevenSeg is
	port 
	(
		num_to_display		: in std_logic_vector(3 downto 0); -- 4-bit number to be displayed
		HEX_display	: out std_logic_vector(6 downto 0) 		  -- 7-seg display to be used.  Remember LEDs are active low
	);
end SevenSeg;


architecture LogicFunction of SevenSeg is

	-- Signals go here
	signal SEG : std_logic_vector(6 downto 0); -- active low output vector to be written to HEX_display

begin

	-- Processes go here
	-- 	Using when statements (like a switch in Matlab or C) to determine what is displayed on 7-seg
	process(num_to_display) -- the process will run whenever one of the variables in dependency list takes on new value
		begin 
			case num_to_display is
			 when "0000" => 
				SEG <= "1000000"; -- "0"; each char maps to LED seg     -- to turn on LED, need 0;
			when "0001" => 
				SEG <= "1111001";
			when "0010" => 
				SEG <= "0100100";
			when "0011" => 
				SEG <= "0110000";
			when "0100" => 
				SEG <= "0011001";
			when "0101" => 
				SEG <= "0010010";
			when "0110" => 
				SEG <= "0000010";
			when "0111" => 
				SEG <= "1111000";
			when "1000" => 
				SEG <= "0000000";
			when "1001" =>  -- 9
				SEG <= "0010000";
			when "1010" => -- A
				SEG <= "0001000";
			when "1011" => -- b
				SEG <= "0000011";
			when "1100" => -- C
				SEG <= "1000110";			
			when "1101" => -- d
				SEG <= "0100001";
			when "1110" => -- E
				SEG <= "0000110";
			when "1111" => -- F
				SEG <= "0001110";
			

			when others => SEG<="1111111"; -- turn all segments off -- new statement!
		 end case;
		 
	end process;	
	
	-- In this example, the values are already active low; no need to invert
	HEX_display <= SEG;

end LogicFunction;
