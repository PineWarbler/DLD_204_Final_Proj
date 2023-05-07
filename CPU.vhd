library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

entity cpu is
	port(	reset		: 	in std_logic;
			clk		:	in	std_logic;
			cpu_di	:	in std_logic_vector(7 downto 0);		--input data bus to CPU
			cpu_do	:	out std_logic_vector(7 downto 0);	--output data bus from CPU
			adr		:	out std_logic_vector(7 downto 0);	--address bus
			wren		:	out std_logic;								--write enable (1= write to mem, 0= read from mem)	
			pc_disp	:	out std_logic_vector(7 downto 0);	--program counter (for display)
			A_disp	:	out std_logic_vector(7 downto 0);	--accumulator A (for display at top level)	
			B_disp	:	out std_logic_vector(7 downto 0);	--accum B for display
			state_disp: out std_logic_vector(7 downto 0);	--current state for display
			switches :	in	std_logic_vector(15 downto 0)		--switch inputs
		 );
end cpu;

architecture fsm of cpu is

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
	------------------ DEPRECATED CODES: -------------------------------
	-- constant JBNZ	:	std_logic_vector(7 downto 0) := "00000110";	--Jump to new adr if contents of B not zero
	-- constant LDCI	:	std_logic_vector(7 downto 0) := "00010100"; -- load C immediately from memory location given after opcode
	-- constant specialDivFunc	:	std_logic_vector(7 downto 0) := "00010110"; -- used in long division; left shifts M and sets the LSB of M equal to bit C of the dividend (A)
	-- constant finishDiv	:	std_logic_vector(7 downto 0) := "00010111"; -- used in long division; does some variable storage shifting to display the division results on A and B
	-- constant INCMEM	:	std_logic_vector(7 downto 0) := "00011000"; -- increment memory location given after opcode
	-- constant cheatMULTAB	:	std_logic_vector(7 downto 0) := "00001011";	--store the product of A and B in A
	-- constant cheatDIVAB	:	std_logic_vector(7 downto 0) := "00001110";		-- store floor(A/B) in A and store mod(A/B) in B
	-- constant CADDMA	:	std_logic_vector(7 downto 0) := "00001111";	-- Conditionally ADD M and A (store A<=A+M if B(0)==1)
	-- constant WS		:	std_logic_vector(7 downto 0) := "00010000"; -- waterfall shift. right shift M and right shift B, but store "bumped-off"bit of M in MSB of B
	-- constant CONCATMB		:	std_logic_vector(7 downto 0) := "00010001"; -- final step of the multiplication add-and-shift algorithm. -- final step of the multiplication add-and-shift algorithm.  Concatenate A and Q, keeping only 8 LSBs; store in A Concatenate A and Q, keeping only 8 LSBs
	--constant SWAPAB	:	std_logic_vector(7 downto 0) := "01011011"; -- swaps the contents in registers A and B


	--internal CPU registers.  You can add others if you want.
	signal op_code:	std_logic_vector(7 downto 0);		--holds opcode of instr after fetched from program memory
	signal pc:			std_logic_vector(7 downto 0);		--holds address of next instr after the one currently being executed
	signal A:			std_logic_vector(7 downto 0)	:= "00000000";		--Accumulator A
	signal B:			std_logic_vector(7 downto 0)	:= "00000000";		--Accumulator B
	-- signal C:			std_logic_vector(7 downto 0)	:= "00001000";		--Accumulator C; used for (cheating) division at the moment and for loop counting (downwards)
	-- signal Q:			std_logic_vector(7 downto 0)	:= "00000000";		--Accumulator Q; used only for multiplication at the moment
	-- signal M:			std_logic_vector(7 downto 0)	:= "00000000";		--Accumulator M; used only for multiplication at the moment; summation for multiplication and remainder for division

	
	--States of CPU FSM
	type FSM is (load_op,LDAWV1,STA2M1,STA2M2,JBNZ1,JUMP1,STOP, LDSW1, STB2M1, STB2M2, LDCI1, LDBWV1, LDAFM1, LDAFM2, LDBFM1, LDBFM2);
																		--You will need to add more states as you add instructions.
																		--Many instructions will take more than one clock cycle, so you will
																		--need to define a new state for each clock cycle.  For example,
																		--LDAWV will take 2 clock cycles: one to load the op-code and a second
																		--to load the byte after the opcode into A.  The LDA1 state is entered
																		--to accommodate this second clock cycle.
	
begin

		pc_disp <= pc;				--so pc, A and B can be displayed on 7segs
		A_disp <= A;
		B_disp <= B;

	fsm_proc: process(reset,CLK)	

		variable CPU_state : FSM := load_op;		--a variable is like a signal, but assigned using := instead of <=
																--other differences you can look up if you wish.
		begin

		case CPU_state is		--so current state can be displayed on 7seg for debug purposes
			when load_op=> state_disp<="00000000";		--will display as "00" on current-state 7segs
			when LDAWV1=> 	state_disp<="00010001";		--will display as "11" on current-state 7segs
			when STA2M1=>	state_disp<="00100001";		--will display as "21" on current-state 7segs
			when STA2M2=>	state_disp<="00100010";		--will display as "22" on current-state 7segs
			when STB2M1=>	state_disp<="00110001";		--will display as "31" on current-state 7segs
			when STB2M2=>	state_disp<="00110010";		--will display as "32" on current-state 7segs
			when LDAFM1 => state_disp<="00110011";		--will display as "33" on current-state 7segs
			when LDAFM2 => state_disp<="00110100";		--will display as "34" on current-state 7segs
			when LDBFM1 => state_disp<="00110101";		--will display as "35" on current-state 7segs
			when LDBFM2 => state_disp<="00110110";		--will display as "36" on current-state 7segs
			
			when JBNZ1=> 	state_disp<="00110001";		--will display as "31" on current-state 7segs
			when STOP=>  	state_disp<="11100000";		--will display as "E0" on current-state 7segs
			-- when ADDAB1=>	state_disp<="11110001";		--will display as "F1" on current-state 7segs
			-- when INCA1=>	state_disp<="11110100";		--will display as "F4" on current-state 7segs
			-- when INCB1=>	state_disp<="11110110";		--will display as "F6" on current-state 7segs
			when LDSW1=>	state_disp<="11110101";		--will display as "F5" on current-state 7segs
			when LDCI1=>		state_disp<="11110110";		--will display as "F6" on current-state 7segs
			-- when INCMEM1=>		state_disp<="11110111";		--will display as "F7" on current-state 7segs
			-- when INCMEM2=>		state_disp<="11111000";		--will display as "F8" on current-state 7segs
			when others=> 	state_disp<="11111111" ;	--will display as "FF" on current-state 7segs
		end case;	
		
		if (reset= '0') then		
			adr <= "10000000";	--first adr in program memory
			pc <= "10000000";		--next address in program memory
			wren <= '0';			--set everything else to default values 
			-- Dr. Mohr said we couldn't use extra cpu registers
			A <= "00000000";
			B <= "00000000";
			--C <= "00001000"; -- initializing to 8 for each of bit of input number; used as iterator for division and looped multiplication
			-- M <= "00000000";
			-- Q <= "00000000";
			cpu_do <= "00000000";
			CPU_state:= load_op;
			
		elsif rising_edge(CLK) then	
			case CPU_state is 		
				when load_op =>
					op_code <= cpu_di;				--read opcode byte from RAM
					adr <= pc+1;						--address program byte after opcode.
					wren <= '0';						--wren low by default.  Only high when writing to RAM
					
					case cpu_di is						--respond to opcode
						when LDAWV =>
							CPU_state := LDAWV1;			--load A immediate with raw value given by byte after opcode on next clk cycle
							pc <= pc+2;					--next instr is 2 bytes up from the current one
						when LDBWV =>
							CPU_state := LDBWV1;
							pc <= pc+2;
						when LDSW =>
							A<= switches(15 downto 8);
							B<= switches(7 downto 0);
							CPU_state := load_op;
							pc <= pc+1;
						
						when INCA =>
							A <= A + 1;
							CPU_state := load_op;
							pc <= pc+1;
						
						when INCB =>
							B <= B + 1;
							CPU_state := load_op;
							pc <= pc+1;

						when STA2M =>					--Store A to RAM location given
							wren <= '1';
							CPU_state := STA2M1;
							pc <= pc+2;

						when STB2M => -- store B to the RAM location given after the opcode
							wren <= '1';
							CPU_state := STB2M1;
							pc <= pc+2;
						
						when LDAFM => -- load register A from memory adress given
							CPU_state := LDAFM1;
							pc <= pc+2;
						
						when LDBFM => -- load register A from memory adress given
							CPU_state := LDBFM1;
							pc <= pc+2;
							-- when JBNZ => --Jump to new adr if contents of B not zero
							-- 	if (B=0) then
							-- 		CPU_state := load_op;							--left to you if you want to include JBNZ in your instr set
							-- 	else
							-- 									--left to you
							-- 	end if;
								-- pc <= pc+2;
						when JUMP =>
							CPU_state := JUMP1;
						
						-- JUMPAngtB => -- jump only if !(A>=B) or (equivalently) A<B
						when HALT =>
							CPU_state := STOP;								--left to you
							adr <= pc;
							pc <= pc;


						when SUBBA =>
							A <= A - B;
							CPU_state := load_op;	--do nothing but prepare to fetch next instr
							pc <= pc+1;

						when forloopsentinel =>
							CPU_state := load_op;
							if (B="00000001") then
								pc<= pc + 6;
							else
								pc <= pc + 1;
							end if;
						
						-- when INCMEM =>
						-- 	CPU_state := INCMEM1;
						-- 	pc <= pc+2;
						
						-- when loopsentinelA => -- stop a loop by skipping three op-codes ahead based on the state of the iterator `C`
						-- 	CPU_state := load_op;
						-- 	if (A='11111111') then
						-- 		pc <= pc+3; -- originally 3 to skip the JUMP and <destination_address> to the next opcode
						-- 	else
						-- 		pc <= pc+1;
						-- 	end if;
						
						-- when loopsentinelB => -- stop a loop by skipping three op-codes ahead based on the state of the iterator `C`
						-- 	CPU_state := load_op;
						-- 	if (B='11111111') then
						-- 		pc <= pc+3; -- originally 3 to skip the JUMP and <destination_address> to the next opcode
						-- 	else
						-- 		pc <= pc+1;
						-- 	end if;
						when forloopsentinel =>
							CPU_state := load_op;
							if (B="00000001") then
								pc<= pc + 6;
							else
								pc <= pc + 1;
							end if;
							
						when DECRA => -- decrement A
							A <= A-1;
							CPU_state := load_op;
							pc <= pc+1;
						
						when DECRB => -- decrement B
							B <= B-1;
							CPU_state := load_op;
							pc <= pc+1;
						
						when NOP =>
							CPU_state := load_op;	--do nothing but prepare to fetch next instr
							pc <= pc+1;
						when ADDAB =>
							A <= A + B;
							CPU_state := load_op;
							pc <= pc+1;

						when CSUBA => -- conditionally subtract B from A, and store result in A
							if (A >= B) then
								A <= A - B;
								CPU_state := load_op;
								pc <= pc+1;
							else
								pc <= pc + 14; -- jump to last opcode in memory which will update lcd displays
								adr <= pc + 14;
								CPU_state := load_op;	--prepare to load opcode at this new adr
							end if;
								
						when CSUBNewtonRaphson => -- same thing as CSUBA except different magic numbers in jump advance
							if (A >= B) then
								A <= A - B;
								CPU_state := load_op;
								pc <= pc+1;
							else
								pc <= pc + 12; -- jump to next non-loop command
								adr <= pc + 12;
								CPU_state := load_op;	--prepare to load opcode at this new adr
							end if;

						when loopsentinelNewtonRaphson =>
							if (B >= 3) then
								pc <= pc + 3; -- jump to next non-loop command
								adr <= pc + 3;
								CPU_state := load_op;	--prepare to load opcode at this new adr
							else
								CPU_state := load_op;
								pc <= pc+1;
							end if;
						
						when ShiftAR => -- shift contents of register A once to the right
							A <= '0' & A(7 downto 1);
							CPU_state := load_op;
							pc <= pc+1;	

						when ShiftBR => -- shift contents of register B once to the right
							B <= '0' & B(7 downto 1);
							CPU_state := load_op;
							pc <= pc+1;	
								
						-- when DISPQA =>
						-- 	A <= Q;
						-- 	B <= R;
						-- 	pc <= pc+1;
						-- 	CPU_state := load_op;
								
						
						-- when CADDMA => -- store A<=A+M if B(0)==1
						-- 	if (B(0) = '1') then
							-- 		M <= M + A; -- else, do not add because LSB is 0
							-- 	end if;
						-- 	CPU_state := load_op;
						-- 	pc <= pc+1;
						
						-- when WS => -- waterfall shift. right shift A and right shift Q, but store "bumped-off"bit of A in MSB of Q
						-- 		B <= M(0) & B(7 downto 1);
						-- 		M <= '0' & M(7 downto 1);
						-- 		CPU_state := load_op;
						-- 		pc <= pc+1;
						
						-- when CONCATMB => -- final step of the multiplication add-and-shift algorithm.  Concatenate A and Q, keeping only 8 LSBs; store in A
								-- A <= (M & B)(7 downto 0); 
								--A <= B;
								-- CPU_state := load_op;
								-- pc <= pc+1;
						-- when specialDivFunc =>
						-- 		M <= M(6 downto 0) & A(to_integer(unsigned(C)-1)); -- left shift M and set the least-significant bit of R equal to bit C (iterator) of the numerator
						-- 		CPU_state := load_op;
						-- 		pc <= pc+1;

						-- when CSUB =>
						-- 	if M >= B then
						-- 		M <= M - B; -- subtract one multiple of divisor from dividend
						-- 		Q(to_integer(unsigned(C)-1)) <= '1';
						-- 	end if;
						-- 	CPU_state := load_op;
						-- 	pc <= pc+1;
						
						--when finishDiv =>
							-- display Quotient (Q) on A and remainder (M) on B
							--A <= Q;
							--B <= M;
							--CPU_state := load_op;
							--pc <= pc+1;

						-- when LDCI => -- load C from memory location given after the opcode
						-- 	CPU_state := LDCI1;		--load A immediate on next clk cycle
						-- 	pc <= pc+2;					--next instr is 2 bytes up from the current one
								
						-- when ADDM => --Add contents of any RAM location to A
						-- 	A <= A + cpu_di;
						-- 	CPU_state := load_op;	--do nothing but prepare to fetch next instr
						-- 	pc <= pc+1;

						-- when SWAPAB =>
						-- 	CPU_state := load_op;
						--	A <= A + B;
						--	B <= A - B;
						--	A <= A - B;
						--	pc <= pc+1;

						-- when cheatMULTAB =>
						-- 	-- this type casting recipe concocted based on https://nandland.com/common-vhdl-conversions/
						-- 	A <= std_logic_vector(to_unsigned(to_integer(unsigned(A)) * to_integer(unsigned(B)), A'length));
						-- 	CPU_state := load_op;	
						-- 	pc <= pc+1;
						-- when cheatDIVAB =>
						-- 	-- similar recipe to `cheatMULTAB`
						-- 	 -- calculate floor(A/B); don't have to use floor because VHDL integers always round down
						-- 	C <= std_logic_vector(to_unsigned(to_integer(unsigned(A)) / to_integer(unsigned(B)), A'length));
						-- 	A <= C; -- store floor(A/B) in A
						-- 	-- now calculate the remainder (A - (B*C))
						-- 	B <= std_logic_vector(to_unsigned(to_integer(unsigned(A)) - (to_integer(unsigned(B)) * to_integer(unsigned(C))), A'length));
						-- 	CPU_state := load_op;	
						-- 	pc <= pc+1;
						when others =>
							CPU_state := STOP;
							adr <= pc;
					end case;
					
				when LDAWV1 =>
					A <= cpu_di;				--store raw value given after opcode
					adr <= pc;					--adr bus gets adr of next instr
					CPU_state := load_op;	--this instr complete. Prepare for next opcode
				
				when LDBWV1 =>
					B <= cpu_di;				--read byte from RAM at loc just after opcode
					adr <= pc;					--adr bus gets adr of next instr
					CPU_state := load_op;	--this instr complete. Prepare for next opcode
				
				--when LDCI1 => -- imitating LDAWV1
					--C <= cpu_di;
					--adr <= pc;
					--CPU_state := load_op;

				when LDSW1 =>
					A<= switches(15 downto 8);
					B<= switches(7 downto 0);
					CPU_state := load_op;	
				
				-- when INCMEM1 =>
				-- 	wren <= '1';
				-- 	A <= cpu_di + 1;
				-- 	CPU_state := INCMEM2;
				-- when INCMEM2 =>
				-- 	wren <= '1';
				-- 	cpu_do <= A;
				-- 	adr <= pc;
				-- 	CPU_state := load_op;
					
				-- why do we need two STA2M helper functions? won't wren get re-written to 0 after STA2M1? No, wren=0 only happens or loadop
				when STA2M1 =>					--left to you  Store A to any RAM location (i.e. a ram location defined by the user after opcode)
					wren <= '1'; -- enable write
					adr <= cpu_di;
					cpu_do <= A;
					-- adr <= pc-1;
					CPU_state := STA2M2;
					-- adr <= pc + 1;
				when STA2M2 =>					--left to you
					wren <= '1'; -- enable write					
					CPU_state := load_op;	--this instr complete. Prepare for next opcode
					adr <= pc; --adr bus gets adr of next instr
					
				when STB2M1 =>					--left to you  Store A to any RAM location (i.e. a ram location defined by the user after opcode)
					wren <= '1'; -- enable write
					adr <= cpu_di;
					cpu_do <= B;
					CPU_state := STB2M2;
				when STB2M2 =>	
					wren <= '1';				--left to you
					adr <= pc;					--adr bus gets adr of next instr
					CPU_state := load_op;	--this instr complete. Prepare for next opcode

				when LDAFM1 =>
					adr <= cpu_di; -- redirect the adr after opcode back into ram
					CPU_state := LDAFM2;
					
				when LDAFM2 =>
					A <= cpu_di;
					CPU_state := load_op;
					adr <= pc;

				when LDBFM1 =>
					adr <= cpu_di; -- redirect the adr after opcode back into ram
					CPU_state := LDBFM2;
					
				when LDBFM2 =>
					B <= cpu_di;
					CPU_state := load_op;
					adr <= pc;

				-- when JBNZ1 => --Jump to new adr if contents of B not zero
				-- 	A <= cpu_di;								--left to you
				-- 	if B then
				-- 		elsif <condition> then
				-- 		else
				-- 	end if;
													
				when JUMP1 =>
					pc <= cpu_di;				--load pc with adr to jump to
					adr <= cpu_di;				--also put it on adr bus
					CPU_state := load_op;	--prepare to load opcode at this new adr
				when STOP=>					--left to you
					CPU_state := STOP;
					adr <= pc;
					pc <= pc;
					--pc <= x"12C"; -- reverse command that would increment pc count (stuck on Halt command)
				when others =>					-- all other states 

			end case;
		end if;
	end process fsm_proc;
end fsm;
		

				

