------------------ PC Managing Unit(s) -----------------------------------------------------------
--------------------------------------------------------------------------------------------------


-- ieee packages ------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_misc.all;
use ieee.numeric_std.all;
use std.textio.all;

-- local packages ------------
use work.riscv_klessydra.all;
use work.thread_parameters_klessydra.all;


entity Program_Counter is
  port (
    absolute_jump                     : in  std_logic;
    data_we_o_lat                     : in  std_logic;
    PC_offset                         : in  replicated_32b_reg;
    taken_branch                      : in  std_logic;
    ie_taken_branch                   : in  std_logic;
    ls_taken_branch                   : in  std_logic;
    dsp_taken_branch                  : in  std_logic;
    set_branch_condition              : in  std_logic;
    ls_except_condition               : in  std_logic;
    ie_except_condition               : in  std_logic;
    dsp_except_condition              : in  std_logic;
    set_except_condition              : in  std_logic;
    set_mret_condition                : in  std_logic;
    set_wfi_condition                 : in  std_logic;
    harc_ID                           : in  harc_range;
    harc_LS                           : in  harc_range;
    harc_EXEC                         : in  harc_range;
    instr_rvalid_IE                   : in  std_logic;
    pc_IE                             : in  std_logic_vector(31 downto 0);
    MSTATUS                           : in  array_2d(harc_range)(1 downto 0);
    MIP, MEPC, MCAUSE, MTVEC : in  replicated_32b_reg;
    instr_word_IE                     : in  std_logic_vector(31 downto 0);
    reset_state                       : in  std_logic;
    pc_IF                             : out std_logic_vector(31 downto 0);
    harc_IF                           : out harc_range;
    served_ie_except_condition        : out replicated_bit;
    served_ls_except_condition        : out replicated_bit;
    served_dsp_except_condition       : out replicated_bit;
    served_except_condition           : out replicated_bit;
    served_mret_condition             : out replicated_bit;
    served_irq                        : in  replicated_bit;
	taken_branch_pending              : out replicated_bit; 
    taken_branch_pc_lat               : out replicated_32b_reg;
    incremented_pc                    : out replicated_32b_reg;
    mepc_incremented_pc               : out replicated_32b_reg;
    mepc_interrupt_pc                 : out replicated_32b_reg;
    irq_pending                       : out replicated_bit;
    clk_i                             : in  std_logic;
    rst_ni                            : in  std_logic;
    irq_i                             : in  std_logic;
    fetch_enable_i                    : in  std_logic;
    boot_addr_i                       : in  std_logic_vector(31 downto 0);
    instr_gnt_i                       : in  std_logic
    );
end entity;



----------------------------------------------------------------------------------------------------
-- Program Counter Managing Units -- synchronous process, one cycle
-- Note: in the present version, gives priority to branching over trapping, 
-- i.e. branch instructions are not interruptible. This can be changed but may be unsafe.
-- Implements as many hw units as the max number of threads supported
----------------------------------------------------------------------------------------------------
architecture PC of Program_counter is

  -- pc updater signals
  signal pc_update_enable                  : replicated_bit;
  signal taken_branch_replicated           : replicated_bit;
  signal set_branch_condition_replicated   : replicated_bit;
  signal set_wfi_condition_replicated      : replicated_bit;
  signal ls_except_condition_replicated    : replicated_bit;
  signal ie_except_condition_replicated    : replicated_bit;
  signal dsp_except_condition_replicated   : replicated_bit;
  signal set_except_condition_replicated   : replicated_bit;
  signal set_mret_condition_replicated     : replicated_bit;
  signal relative_to_PC                    : replicated_32b_reg;
  signal pc                                : replicated_32b_reg;
  signal boot_pc                           : std_logic_vector(31 downto 0);
  signal harc_IF_internal                  : harc_range;
  signal mret_condition_pending_internal   : replicated_bit;
  signal mepc_incremented_pc_internal      : replicated_32b_reg;
  signal incremented_pc_internal           : replicated_32b_reg;
  signal mepc_interrupt_pc_internal        : replicated_32b_reg;
  signal taken_branch_pc_lat_internal      : replicated_32b_reg;
  signal taken_branch_pc_pending_internal  : replicated_32b_reg;
  signal taken_branch_pending_internal     : replicated_bit;
  signal irq_pending_internal              : replicated_bit;

  ---------------------------------------------------------------------------------------------------
  -- Subroutine implementing pc updating combinat. logic, to be replicated for max threads supported
  ---------------------------------------------------------------------------------------------------
  procedure pc_update(
    signal MTVEC                         : in    std_logic_vector(31 downto 0);
    signal instr_gnt_i, taken_branch     : in    std_logic;
    signal set_wfi_condition             : in    std_logic;
    signal taken_branch_pending          : inout std_logic;
    signal irq_pending                   : in    std_logic;
    signal ie_except_condition           : in    std_logic;
    signal ls_except_condition           : in    std_logic;
    signal dsp_except_condition          : in    std_logic;
    signal set_except_condition          : in    std_logic;
    signal set_mret_condition            : in    std_logic;
    signal pc                            : inout std_logic_vector(31 downto 0);
    signal taken_branch_pc_lat           : in    std_logic_vector(31 downto 0);
    signal taken_branch_pc_pending       : in    std_logic_vector(31 downto 0);
    signal incremented_pc                : in    std_logic_vector(31 downto 0);
    signal boot_pc                       : in    std_logic_vector(31 downto 0);
    signal pc_update_enable              : in    std_logic;
    signal served_ie_except_condition    : out   std_logic;
    signal served_ls_except_condition    : out   std_logic;
    signal served_dsp_except_condition   : out   std_logic;
    signal served_except_condition       : out   std_logic;
    signal served_mret_condition         : out   std_logic) is
  begin
    if pc_update_enable = '1' then

      -- interrupt service launched in the previous instr. cycle
      -- this is done for a second instr. cycle for proper synchronization of flushing
      -- nothing pending    
      if not taken_branch = '1' and not taken_branch_pending = '1' then
        pc                      <= incremented_pc;
        served_except_condition <= '0';
        served_ie_except_condition  <= '0';
        served_ls_except_condition  <= '0';
        served_dsp_except_condition <= '0';
        served_mret_condition   <= '0';
      -- taken_branch pending 
      elsif taken_branch = '1' then
        pc                      <= taken_branch_pc_lat;
        taken_branch_pending    <= '0';
        served_ie_except_condition  <= '1' when ie_except_condition  = '1' else '0'; -- for CS units;
        served_ls_except_condition  <= '1' when ls_except_condition  = '1' else '0'; -- for CS units;
        served_dsp_except_condition <= '1' when dsp_except_condition = '1' else '0'; -- for CS units;
        served_except_condition     <= '1' when set_except_condition = '1' else '0'; -- for CS units;
        served_mret_condition       <= '1' when set_mret_condition   = '1' else '0'; -- for CS units;
      elsif  taken_branch_pending = '1' then
        pc                      <= taken_branch_pc_pending;
        taken_branch_pending    <= '0';
        served_ie_except_condition  <= '1' when ie_except_condition  = '1' else '0'; -- for CS units;
        served_ls_except_condition  <= '1' when ls_except_condition  = '1' else '0'; -- for CS units;
        served_dsp_except_condition <= '1' when dsp_except_condition = '1' else '0'; -- for CS units;
        served_except_condition     <= '1' when set_except_condition = '1' else '0'; -- for CS units;
        served_mret_condition       <= '1' when set_mret_condition   = '1' else '0'; -- for CS units;
      else
        pc <= boot_pc;                  -- default, should never occur
      end if;
      -- end of pc value update ---    
    else                                -- sets registers to record pending requests
      served_except_condition <= '0';
      served_mret_condition   <= '0';
      if taken_branch = '1' then
        taken_branch_pending <= '1';
      end if;
      if set_except_condition = '1' then
        served_except_condition <= '1';
      end if;
      if dsp_except_condition = '1' then
        served_dsp_except_condition <= '1';
      elsif ls_except_condition = '1' then
        served_ls_except_condition <= '1';
      elsif ie_except_condition = '1' then
        served_ie_except_condition <= '1';
      end if;
      if set_mret_condition = '1' then
        served_mret_condition <= '1';
      end if;
    end if;
  end pc_update;
  --------------------------------------------------------------------------------------

begin

  harc_IF                  <= harc_IF_internal;
  mepc_incremented_pc      <= mepc_incremented_pc_internal;
  mepc_interrupt_pc        <= mepc_interrupt_pc_internal;
  taken_branch_pc_lat      <= taken_branch_pc_lat_internal;
  incremented_pc           <= incremented_pc_internal;
  taken_branch_pending     <= taken_branch_pending_internal;
  irq_pending              <= irq_pending_internal;

  hardware_context_counter : process(all)
  begin
    if rst_ni = '0' then
      harc_IF_internal <= THREAD_POOL_SIZE -1;
    elsif rising_edge(clk_i) then
      if instr_gnt_i = '1' then
        harc_IF_internal <= harc_IF_internal - 1 when harc_IF_internal > 0 else THREAD_POOL_SIZE -1;
      end if;
    end if;
  end process hardware_context_counter;

  -- this is the multiplexer on the PC_IF
  pc_IF <= pc(harc_IF_internal);

  -- fixed connections, not replicated 
  boot_pc                                 <= boot_addr_i(31 downto 8) & std_logic_vector(to_unsigned(128, 8));
  ----------------------------------------------------------------------------------------------
  -- this part of logic and registers is replicated as many times as the supported threads:   --
  pc_update_logic : for h in harc_range generate

    mepc_incremented_pc_internal(h) <= MEPC(h);
    mepc_interrupt_pc_internal(h)   <= MEPC(h) when MCAUSE(h)(30) = '0' else std_logic_vector(unsigned(MEPC(h)) + 4);  -- (MCAUSE(30) = '0') indicates that we weren't executing a WFI instruction

    relative_to_PC(h) <= std_logic_vector(to_unsigned(0, 32)) when (absolute_jump = '1')
                         else pc_IE;
    incremented_pc_internal(h) <= std_logic_vector(unsigned(pc(h))+4);
    irq_pending_internal(h)    <= ((MIP(h)(11) or MIP(h)(7) or MIP(h)(3)) and MSTATUS(h)(0));

    set_wfi_condition_replicated(h) <= '1' when set_wfi_condition = '1' and (harc_EXEC = h)
                                  else '0';
    taken_branch_replicated(h) <=      '1' when dsp_taken_branch = '1' and (harc_EXEC = h)
	                              else '1' when ls_taken_branch  = '1' and (harc_EXEC = h)
	                              else '1' when ie_taken_branch  = '1' and (harc_EXEC = h)
                                  else '0';
    set_branch_condition_replicated(h) <= '1' when set_branch_condition = '1' and (harc_EXEC = h)
                                     else '0';
    dsp_except_condition_replicated(h) <= '1' when dsp_except_condition  = '1' and (harc_EXEC  = h)
                                     else '0';
    ls_except_condition_replicated(h)  <= '1' when ls_except_condition   = '1' and (harc_EXEC   = h)
                                     else '0';
    ie_except_condition_replicated(h) <= '1' when ie_except_condition  = '1' and (harc_EXEC = h)
                                     else '0';
    set_except_condition_replicated(h) <= '1' when dsp_except_condition_replicated(h)  = '1' or ls_except_condition_replicated(h) = '1' or ie_except_condition_replicated(h) = '1'
                                     else '0';
    set_mret_condition_replicated(h)   <= '1' when set_mret_condition = '1' and (harc_EXEC = h)
                                     else '0';

    -- latch on the branch address, possibly useless but may be needed in future situations, served_irq has the highest priority, interrupt request are checked before executing any instructions in the IE_Stage

    taken_branch_pc_lat_internal(h) <=
      MTVEC(h)                                                         when dsp_except_condition_replicated(h) = '1'                         else  -- sets MTVEC address for exception trap
      MTVEC(h)                                                         when ls_except_condition_replicated(h)  = '1'                         else  -- sets MTVEC address for exception trap
      std_logic_vector(signed(relative_to_PC(h))+signed(PC_offset(h))) when set_branch_condition_replicated(h) = '1'                         else  -- sets a jump or a branch address
      std_logic_vector(signed(relative_to_PC(h)))                      when set_wfi_condition_replicated(h)    = '1'                         else  -- sets a wfi address (spin lock)
      MTVEC(h)                                                         when ie_except_condition_replicated(h)  = '1'                         else  -- sets MTVEC address for exception trap
      mepc_incremented_pc_internal(h)                                  when set_mret_condition_replicated(h)   = '1' and MCAUSE(h)(31) = '0' else  -- sets return address from exception subroutine
      mepc_interrupt_pc_internal(h)                                    when set_mret_condition_replicated(h)   = '1' and MCAUSE(h)(31) = '1' else  -- sets return address from interrupt subroutine
      MTVEC(h)                                                         when served_irq(h)                                                    else  -- sets MTVEC address for exception trap, 
     (others => '0');


    pc_update_enable(h) <= '1' when instr_gnt_i = '1'
                           and (harc_IF_internal = h
                                or taken_branch_replicated(h) = '1'
                                or set_wfi_condition_replicated(h) = '1'
                                or taken_branch_pending_internal(h) = '1')
                           else '0';

    pc_updater : process(clk_i, rst_ni, boot_pc)
    begin
      if rst_ni = '0' then
        pc(h)                               <= (others => '0');  -- better to put 0 to ensure clear synthesis
        taken_branch_pc_pending_internal(h) <= (others => '0');
        taken_branch_pending_internal(h)    <= '0';
        served_ie_except_condition(h)       <= '0';
        served_ls_except_condition(h)       <= '0';
        served_dsp_except_condition(h)      <= '0';
        served_except_condition(h)          <= '0';
        served_mret_condition(h)            <= '0';
      elsif rising_edge(clk_i) then
        -- synch.ly updates pc with new value depending on conditions pending 
        -- synch.ly raises "served" signal for the condition that is being served 
        -- synch.ly lowers "served" signal for other conditions
        if taken_branch_replicated(h) = '1' then 
          taken_branch_pc_pending_internal(h) <= taken_branch_pc_lat_internal(h);
        end if;
        if reset_state = '1' then
          pc(h) <= boot_pc;
        else
          pc_update(MTVEC(h), instr_gnt_i, taken_branch_replicated(h), set_wfi_condition_replicated(h), taken_branch_pending_internal(h),
                    irq_pending_internal(h),ie_except_condition_replicated(h), ls_except_condition_replicated(h), dsp_except_condition_replicated(h),
					set_except_condition_replicated(h), set_mret_condition_replicated(h), pc(h), taken_branch_pc_lat_internal(h), taken_branch_pc_pending_internal(h),
					incremented_pc_internal(h), boot_pc, pc_update_enable(h), served_ie_except_condition(h), served_ls_except_condition(h),
					served_dsp_except_condition(h), served_except_condition(h),
                    served_mret_condition(h));
        end if;
      end if;  --rst , clk
    end process;


  end generate pc_update_logic;
  -- end of replicated logic --   
  --------------------------------------------------------------------------------------------



--------------------------------------------------------------------- end of PC Managing Units ---
--------------------------------------------------------------------------------------------------  
end PC;
