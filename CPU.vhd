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
	constant cheatMULTAB	:	std_logic_vector(7 downto 0) := "00001011";	--store the product of A and B in A
	constant cheatDIVAB	:	std_logic_vector(7 downto 0) := "00001110";		-- store floor(A/B) in A and store mod(A/B) in B
	constant CADDMA	:	std_logic_vector(7 downto 0) := "00001111";	-- Conditionally ADD M and A (store A<=A+M if B(0)==1)
	constant WS		:	std_logic_vector(7 downto 0) := "00010000"; -- waterfall shift. right shift M and right shift B, but store "bumped-off"bit of M in MSB of B
	constant CONCATMB		:	std_logic_vector(7 downto 0) := "00010001"; -- final step of the multiplication add-and-shift algorithm. -- final step of the multiplication add-and-shift algorithm.  Concatenate A and Q, keeping only 8 LSBs; store in A Concatenate A and Q, keeping only 8 LSBs
	constant loopsentinel	:	std_logic_vector(7 downto 0) := "00010010"; -- skip the next two bytes in program memory if C=0 (use case: can stop a loop [i.e. JUMP, <..adr..>] by skipping three op-codes ahead based on the state of the iterator `C`
	constant DECRC	:	std_logic_vector(7 downto 0) := "00010011"; -- decrement C
	constant LDCI	:	std_logic_vector(7 downto 0) := "00010100"; -- load C immediately from memory location given after op code
	constant CSUB	:	std_logic_vector(7 downto 0) := "00010101"; -- used in long division; subtracts divisor from dividend
	constant specialDivFunc	:	std_logic_vector(7 downto 0) := "00010110"; -- used in long division; left shifts M and sets the LSB of M equal to bit C of the dividend (A)
	constant finishDiv	:	std_logic_vector(7 downto 0) := "00010111"; -- used in long division; does some variable storage shifting to display the division results on A and B




	--internal CPU registers.  You can add others if you want.
	signal op_code:	std_logic_vector(7 downto 0);		--holds op code of instr after fetched from program memory
	signal pc:			std_logic_vector(7 downto 0);		--holds address of next instr after the one currently being executed
	signal A:			std_logic_vector(7 downto 0)	:= "00000000";		--Accumulator A
	signal B:			std_logic_vector(7 downto 0)	:= "00000000";		--Accumulator B
	signal C:			std_logic_vector(7 downto 0)	:= "00001000";		--Accumulator C; used for (cheating) division at the moment and for loop counting (downwards)
	signal Q:			std_logic_vector(7 downto 0)	:= "00000000";		--Accumulator Q; used only for multiplication at the moment
	signal M:			std_logic_vector(7 downto 0)	:= "00000000";		--Accumulator M; used only for multiplication at the moment; summation for multiplication and remainder for division

	
	--States of CPU FSM
	type FSM is (load_op,LDAI1,STAM1,STAM2,JBNZ1,JUMP1,STOP, LDSW1, STBM1, STBM2, LDCI1);
																		--You will need to add more states as you add instructions.
																		--Many instructions will take more than one clock cycle, so you will
																		--need to define a new state for each clock cycle.  For example,
																		--LDAI will take 2 clock cycles: one to load the op-code and a second
																		--to load the byte after the op code into A.  The LDA1 state is entered
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
			when LDAI1=> 	state_disp<="00010001";		--will display as "11" on current-state 7segs
			when STAM1=>	state_disp<="00100001";		--will display as "21" on current-state 7segs
			when STAM2=>	state_disp<="00100010";		--will display as "22" on current-state 7segs
			when STBM1=>	state_disp<="00110001";		--will display as "31" on current-state 7segs
			when STBM2=>	state_disp<="00110010";		--will display as "32" on current-state 7segs
			
			when JBNZ1=> 	state_disp<="00110001";		--will display as "31" on current-state 7segs
			when STOP=>  	state_disp<="11110000";		--will display as "F0" on current-state 7segs
			-- when ADDAB1=>	state_disp<="11110001";		--will display as "F1" on current-state 7segs
			-- when INCA1=>	state_disp<="11110100";		--will display as "F4" on current-state 7segs
			-- when INCB1=>	state_disp<="11110110";		--will display as "F6" on current-state 7segs
			when LDSW1=>	state_disp<="11110101";		--will display as "F5" on current-state 7segs
			when LDCI1=>		state_disp<="11110110";		--will display as "F6" on current-state 7segs
			when others=> 	state_disp<="11111111" ;	--will display as "FF" on current-state 7segs
		end case;	
		
		if (reset= '0') then		
			adr <= "10000000";	--first adr in program memory
			pc <= "10000000";		--next address in program memory
			wren <= '0';			--set everything else to default values 
			A <= "00000000";
			B <= "00000000";
			C <= "00001000"; -- initializing to 8 for each of bit of input number; used as iterator for division and looped multiplication
			M <= "00000000";
			Q <= "00000000";
			cpu_do <= "00000000";
			CPU_state:= load_op;
			
		elsif rising_edge(CLK) then	
			case CPU_state is 		
				when load_op =>
					op_code <= cpu_di;				--read op code byte from RAM
					adr <= pc+1;						--address program byte after op code.
					wren <= '0';						--wren low by default.  Only high when writing to RAM
					
					case cpu_di is						--respond to op code
						when LDAI =>
							CPU_state := LDAI1;		--load A immediate on next clk cycle
							pc <= pc+2;					--next instr is 2 bytes up from the current one
						when LDSW =>
							A<= switches(15 downto 8);
							B<= switches(7 downto 0);
							-- Q <= B; -- for multiplication algorithm
							CPU_state := LDSW1;
							-- CPU_state := load_op;
							pc <= pc+1;
						when STAM =>					--Store A to any RAM location
							CPU_state := STAM1;
							pc <= pc+2;
						-- when JBNZ => --Jump to new adr if contents of B not zero
						-- 	if (B=0) then
						-- 		CPU_state := load_op;							--left to you if you want to include JBNZ in your instr set
						-- 	else
						-- 									--left to you
						-- 	end if;
							-- pc <= pc+2;
						when STBM => -- store B to the RAM location given after the op code
							CPU_state := STBM1;
							pc <= pc+2;
						when JUMP =>
							CPU_state := JUMP1;
						when HALT =>
							CPU_state := STOP;								--left to you

						when CADDMA => -- store A<=A+M if B(0)==1
							if (B(0) = '1') then
								M <= M + A; -- else, do not add because LSB is 0
							end if;
							CPU_state := load_op;
							pc <= pc+1;
						
						when WS => -- waterfall shift. right shift A and right shift Q, but store "bumped-off"bit of A in MSB of Q
								B <= M(0) & B(7 downto 1);
								M <= '0' & M(7 downto 1);
								CPU_state := load_op;
								pc <= pc+1;
						
						when CONCATMB => -- final step of the multiplication add-and-shift algorithm.  Concatenate A and Q, keeping only 8 LSBs; store in A
								-- A <= (M & B)(7 downto 0); 
								--A <= B;
								CPU_state := load_op;
								pc <= pc+1;
						
						when loopsentinel => -- stop a loop by skipping three op-codes ahead based on the state of the iterator `C`
							CPU_state := load_op;
							if (C=0) then
								pc <= pc+3;
							else
								pc <= pc+1;
							end if;
						
						when DECRC => -- decrement C
							C <= C-1;
							CPU_state := load_op;
							pc <= pc+1;
						
						when specialDivFunc =>
								M <= M(6 downto 0) & A(to_integer(unsigned(C)-1)); -- left shift M and set the least-significant bit of R equal to bit C (iterator) of the numerator
								CPU_state := load_op;
								pc <= pc+1;

						when CSUB =>
							if M >= B then
								M <= M - B; -- subtract one multiple of divisor from dividend
								Q(to_integer(unsigned(C)-1)) <= '1';
							end if;
							CPU_state := load_op;
							pc <= pc+1;
						
						when finishDiv =>
							-- display Quotient (Q) on A and remainder (M) on B
							A <= Q;
							B <= M;
							CPU_state := load_op;
							pc <= pc+1;

						when LDCI => -- load C from memory location given after the op code
							CPU_state := LDCI1;		--load A immediate on next clk cycle
							pc <= pc+2;					--next instr is 2 bytes up from the current one
								
						when NOP =>
							CPU_state := load_op;	--do nothing but prepare to fetch next instr
							pc <= pc+1;
						when ADDM => --Add contents of any RAM location to A
							A <= A + cpu_di;
							CPU_state := load_op;	--do nothing but prepare to fetch next instr
							pc <= pc+1;
						when ADDAB =>
							A <= A + B;
							CPU_state := load_op;
							pc <= pc+1;
						when cheatMULTAB =>
							-- this type casting recipe concocted based on https://nandland.com/common-vhdl-conversions/
							A <= std_logic_vector(to_unsigned(to_integer(unsigned(A)) * to_integer(unsigned(B)), A'length));
							CPU_state := load_op;	
							pc <= pc+1;
						when cheatDIVAB =>
							-- similar recipe to `cheatMULTAB`
							 -- calculate floor(A/B); don't have to use floor because VHDL integers always round down
							C <= std_logic_vector(to_unsigned(to_integer(unsigned(A)) / to_integer(unsigned(B)), A'length));
							A <= C; -- store floor(A/B) in A
							-- now calculate the remainder (A - (B*C))
							B <= std_logic_vector(to_unsigned(to_integer(unsigned(A)) - (to_integer(unsigned(B)) * to_integer(unsigned(C))), A'length));
							CPU_state := load_op;	
							pc <= pc+1;
						when others =>
							CPU_state := STOP;
							adr <= pc;
					end case;
					
				when LDAI1 =>
					A <= cpu_di;				--read byte from RAM at loc just after op code
					adr <= pc;					--adr bus gets adr of next instr
					CPU_state := load_op;	--this instr complete. Prepare for next op code
				
				when LDCI1 => -- imitating LDAI1
					C <= cpu_di;
					adr <= pc;
					CPU_state := load_op;

				when LDSW1 =>
					A<= switches(15 downto 8);
					B<= switches(7 downto 0);
					CPU_state := load_op;	
					
				-- why do we need two STAM helper functions? won't wren get re-written to 0 after STAM1? No, wren=0 only happens or loadop
				when STAM1 =>					--left to you  Store A to any RAM location (i.e. a ram location defined by the user after op code)
					wren <= '1'; -- enable write
					CPU_state := STAM2;
				when STAM2 =>					--left to you
					cpu_do <= A;
					adr <= pc;					--adr bus gets adr of next instr
					CPU_state := load_op;	--this instr complete. Prepare for next op code
					
				when STBM1 =>					--left to you  Store A to any RAM location (i.e. a ram location defined by the user after op code)
					wren <= '1'; -- enable write
					CPU_state := STBM2;
				when STBM2 =>					--left to you
					cpu_do <= B;
					adr <= pc;					--adr bus gets adr of next instr
					CPU_state := load_op;	--this instr complete. Prepare for next op code
					

				-- when JBNZ1 => --Jump to new adr if contents of B not zero
				-- 	A <= cpu_di;								--left to you
				-- 	if B then
				-- 		elsif <condition> then
				-- 		else
				-- 	end if;
													
				when JUMP1 =>
					pc <= cpu_di;				--load pc with adr to jump to
					adr <= cpu_di;				--also put it on adr bus
					CPU_state := load_op;	--prepare to load op code at this new adr
				when STOP=>					--left to you
					CPU_state := load_op;
					pc <= pc - 1; -- reverse command that would increment pc count (stuck on Halt command)
				when others =>					-- all other states 

			end case;
		end if;
	end process fsm_proc;
end fsm;
		

				

