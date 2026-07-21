-------------------------------------------------------------------------------
-- pwm_fan_thermal_standalone.vhd
--
-- IP autonome : ventilateur KV260 asservi sur la temperature on-chip
-- (SYSMON PL), SANS interface AXI. Le seul signal a connecter depuis le
-- Block Design est l'horloge (clk). Tous les autres ports sont optionnels
-- (sorties de supervision, peuvent rester non connectees).
--
-- Reutilise sysmon_temp_acq.vhd et fan_thermal_ctrl.vhd tels quels.
--
-- Tous les parametres qui etaient auparavant des registres AXI ecrits par
-- le logiciel deviennent des GENERIQUES VHDL, modifiables dans la fenetre
-- de personnalisation Vivado lors de l'instanciation de l'IP (Package IP
-- expose automatiquement les generiques comme parametres de customisation,
-- meme sans interface AXI).
--
-- Pas de reset externe requis : un reset interne (power-on-reset) est
-- genere en interne sur quelques cycles d'horloge a la mise sous tension /
-- reconfiguration du PL.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity pwm_fan_thermal_standalone is
    generic (
        -- PWM
        PERIOD_CYCLES      : natural := 100000;  -- periode PWM, coups d'horloge

        -- Bornes de duty (coups d'horloge, doit respecter DUTY_MAX <= PERIOD_CYCLES)
        DUTY_MIN           : natural := 10000;
        DUTY_MAX           : natural := 90000;

        -- Seuils temperature (centidegres C, signes)
        T_MIN_CENTIDEG     : integer := 4000;   -- 40.00 C
        T_MAX_CENTIDEG     : integer := 7680;   -- 76.80 C

        -- Acquisition SYSMON
        POLL_PERIOD_CYCLES : natural := 4096;

        -- Constantes de conversion ADC -> temperature (cf. sysmon_temp_acq,
        -- a recaler sur la revision UG580 exacte, cf. notes precedentes)
        TEMP_SCALE_NUM       : integer := 50931;
        TEMP_SCALE_DEN       : integer := 4096;
        TEMP_OFFSET_CENTIDEG : integer := 28023;

        -- Nombre de cycles du reset interne a la mise sous tension
        POR_CYCLES         : natural := 16
    );
    port (
        clk : in std_logic;  -- SEUL port obligatoire a connecter (PS ou PL)

        pwm_out : out std_logic;

        -- Ports de supervision, optionnels (peuvent rester non connectes
        -- dans le Block Design ; utiles pour debug via ILA par exemple)
        temp_centideg_dbg : out std_logic_vector(15 downto 0);
        duty_active_dbg   : out std_logic_vector(31 downto 0);
        ot_alarm          : out std_logic
    );
end entity pwm_fan_thermal_standalone;

architecture rtl of pwm_fan_thermal_standalone is

    -- Reset interne (power-on-reset synchrone)
    signal por_count : unsigned(7 downto 0) := (others => '0');
    signal rst       : std_logic := '1';

    -- Acquisition temperature
    signal temp_raw12    : std_logic_vector(11 downto 0);
    signal temp_centideg : signed(15 downto 0);
    signal temp_valid    : std_logic;

    -- Loi de commande thermique
    signal duty_auto  : unsigned(31 downto 0);
    signal duty_valid : std_logic;

    -- Bornes/seuils figes en generiques -> converties en signaux constants
    constant t_min_c    : signed(15 downto 0) := to_signed(T_MIN_CENTIDEG, 16);
    constant t_max_c    : signed(15 downto 0) := to_signed(T_MAX_CENTIDEG, 16);
    constant duty_min_c : unsigned(31 downto 0) := to_unsigned(DUTY_MIN, 32);
    constant duty_max_c : unsigned(31 downto 0) := to_unsigned(DUTY_MAX, 32);
    constant period_c   : unsigned(31 downto 0) := to_unsigned(PERIOD_CYCLES, 32);

    -- Compteur PWM
    signal counter : unsigned(31 downto 0) := (others => '0');

begin

    ---------------------------------------------------------------------
    -- Reset interne (power-on-reset)
    ---------------------------------------------------------------------
    process (clk)
    begin
        if rising_edge(clk) then
            if por_count /= POR_CYCLES then
                por_count <= por_count + 1;
                rst       <= '1';
            else
                rst <= '0';
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------
    -- Acquisition temperature (SYSMON)
    ---------------------------------------------------------------------
    u_sysmon_temp_acq : entity work.sysmon_temp_acq
        generic map (
            POLL_PERIOD_CYCLES => POLL_PERIOD_CYCLES,
            SCALE_NUM           => TEMP_SCALE_NUM,
            SCALE_DEN            => TEMP_SCALE_DEN,
            OFFSET_CENTIDEG       => TEMP_OFFSET_CENTIDEG
        )
        port map (
            dclk          => clk,
            rst           => rst,
            temp_raw12    => temp_raw12,
            temp_centideg => temp_centideg,
            temp_valid    => temp_valid,
            ot_alarm      => ot_alarm
        );

    ---------------------------------------------------------------------
    -- Loi de commande thermique
    ---------------------------------------------------------------------
    u_fan_thermal_ctrl : entity work.fan_thermal_ctrl
        port map (
            clk           => clk,
            rst           => rst,
            temp_centideg => temp_centideg,
            temp_valid    => temp_valid,
            t_min         => t_min_c,
            t_max         => t_max_c,
            duty_min      => duty_min_c,
            duty_max      => duty_max_c,
            duty_auto     => duty_auto,
            duty_valid    => duty_valid
        );

    ---------------------------------------------------------------------
    -- Generation PWM (toujours active, toujours asservie)
    ---------------------------------------------------------------------
    process (clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                counter <= (others => '0');
                pwm_out <= '0';
            else
                if counter >= period_c - 1 then
                    counter <= (others => '0');
                else
                    counter <= counter + 1;
                end if;

                if counter < duty_auto then
                    pwm_out <= '1';
                else
                    pwm_out <= '0';
                end if;
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------
    -- Sorties de supervision
    ---------------------------------------------------------------------
    temp_centideg_dbg <= std_logic_vector(temp_centideg);
    duty_active_dbg   <= std_logic_vector(duty_auto);

end architecture rtl;
