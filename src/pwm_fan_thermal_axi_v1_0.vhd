-------------------------------------------------------------------------------
-- pwm_fan_thermal_axi_v1_0.vhd
--
-- IP AXI4-Lite : pilotage PWM du ventilateur KV260, avec asservissement
-- optionnel sur la temperature on-chip (SYSMON PL, via sysmon_temp_acq.vhd
-- et fan_thermal_ctrl.vhd).
--
-- Carte memoire (registres 32 bits, adresses sur 6 bits -> decode sur
-- s_axi_awaddr(5 downto 2), 16 emplacements possibles, 9 utilises) :
--
--   0x00 CTRL         bit0 = ENABLE, bit1 = AUTO_MODE (1=asservi, 0=manuel)
--   0x04 PERIOD_REG   periode PWM en coups d'horloge
--   0x08 DUTY_REG     consigne duty manuelle (utilisee si AUTO_MODE=0), RW
--   0x0C DUTY_AUTO    duty calcule par la loi de commande thermique, RO
--   0x10 TEMP_RAW     temperature en centidegres C, signee, sign-extend, RO
--   0x14 T_THRESH     [15:0]=T_MIN, [31:16]=T_MAX (centidegres C, signes)
--   0x18 DUTY_MIN     borne basse de duty (coups d'horloge), RW, 32 bits
--   0x1C DUTY_MAX     borne haute de duty (coups d'horloge), RW, 32 bits
--   0x20 STATUS       bit0 = temp_valid (sticky jusqu'a lecture), RO
--
-- IMPORTANT (logiciel) : s'assurer DUTY_MAX >= DUTY_MIN et T_MAX > T_MIN
-- avant de passer en AUTO_MODE=1, faute de quoi le calcul d'interpolation
-- de fan_thermal_ctrl.vhd produit un resultat incoherent (soustraction
-- unsigned negative). Valeurs par defaut fournies coherentes entre elles.
--
-- NOTE IMPORTANTE : cette version corrige egalement un bug present dans la
-- version precedente du module PWM (pwm_fan_axi_v1_0) : le chemin de
-- lecture AXI n'etait jamais reellement implemente (s_axi_rdata n'etait
-- jamais mis a jour en fonction de s_axi_araddr). Il est correctement
-- decode ici.
--
-- Cette IP reste une interface AXI-Lite simplifiee ("toujours pret", sans
-- machine a etats de handshake complete READY/VALID) coherente avec le
-- style du module d'origine. Pour une conformite AXI4-Lite stricte
-- (gestion des cas ou le maitre ne peut pas accepter BVALID/RVALID
-- immediatement), il faudrait ajouter des registres d'etat par canal.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity pwm_fan_thermal_axi_v1_0 is
    generic (
        POLL_PERIOD_CYCLES : natural := 4096
    );
    port (
        s_axi_aclk    : in  std_logic;
        s_axi_aresetn : in  std_logic;

        s_axi_awaddr  : in  std_logic_vector(5 downto 0);
        s_axi_awvalid : in  std_logic;
        s_axi_awready : out std_logic;

        s_axi_wdata   : in  std_logic_vector(31 downto 0);
        s_axi_wvalid  : in  std_logic;
        s_axi_wready  : out std_logic;

        s_axi_bresp   : out std_logic_vector(1 downto 0);
        s_axi_bvalid  : out std_logic;
        s_axi_bready  : in  std_logic;

        s_axi_araddr  : in  std_logic_vector(5 downto 0);
        s_axi_arvalid : in  std_logic;
        s_axi_arready : out std_logic;

        s_axi_rdata   : out std_logic_vector(31 downto 0);
        s_axi_rresp   : out std_logic_vector(1 downto 0);
        s_axi_rvalid  : out std_logic;
        s_axi_rready  : in  std_logic;

        -- Sortie fan gating, ACTIVE BASSE (convention "_b" = active-low,
        -- cf. contrainte XDC "fan_en_b" fournie par l'utilisateur sur le
        -- carrier KR260). '0' = ventilateur active, '1' = coupe.
        fan_en_b      : out std_logic
    );
end entity pwm_fan_thermal_axi_v1_0;

architecture rtl of pwm_fan_thermal_axi_v1_0 is

    -- Registres AXI
    signal ctrl_reg     : std_logic_vector(31 downto 0) := (others => '0');
    signal period_reg   : unsigned(31 downto 0) := to_unsigned(100000, 32);
    signal duty_reg     : unsigned(31 downto 0) := to_unsigned(50000, 32);
    signal t_thresh_reg : std_logic_vector(31 downto 0) :=
                             x"1E00_0FA0";  -- T_MIN=4000 (40.00C), T_MAX=7680 (76.80C)
    signal duty_min_reg : unsigned(31 downto 0) := to_unsigned(10000, 32);
    signal duty_max_reg : unsigned(31 downto 0) := to_unsigned(90000, 32);

    alias enable    : std_logic is ctrl_reg(0);
    alias auto_mode : std_logic is ctrl_reg(1);

    signal t_min_s : signed(15 downto 0);
    signal t_max_s : signed(15 downto 0);

    -- Acquisition temperature
    signal temp_raw12        : std_logic_vector(11 downto 0);
    signal temp_centideg     : signed(15 downto 0);
    signal temp_valid        : std_logic;
    signal ot_alarm          : std_logic;
    signal temp_valid_sticky : std_logic := '0';

    -- Loi de commande thermique
    signal duty_auto  : unsigned(31 downto 0);
    signal duty_valid : std_logic;

    -- Duty effectivement applique au PWM
    signal duty_active : unsigned(31 downto 0);

    -- Compteur PWM
    signal counter : unsigned(31 downto 0) := (others => '0');

    -- Read data mux
    signal rdata_i : std_logic_vector(31 downto 0) := (others => '0');

begin

    t_min_s <= signed(t_thresh_reg(15 downto 0));
    t_max_s <= signed(t_thresh_reg(31 downto 16));

    ---------------------------------------------------------------------
    -- Acquisition temperature (SYSMON)
    ---------------------------------------------------------------------
    u_sysmon_temp_acq : entity work.sysmon_temp_acq
        generic map (
            POLL_PERIOD_CYCLES => POLL_PERIOD_CYCLES
        )
        port map (
            dclk          => s_axi_aclk,
            rst           => not s_axi_aresetn,
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
            clk           => s_axi_aclk,
            rst           => not s_axi_aresetn,
            temp_centideg => temp_centideg,
            temp_valid    => temp_valid,
            t_min         => t_min_s,
            t_max         => t_max_s,
            duty_min      => duty_min_reg,
            duty_max      => duty_max_reg,
            duty_auto     => duty_auto,
            duty_valid    => duty_valid
        );

    duty_active <= duty_auto when auto_mode = '1' else duty_reg;

    ---------------------------------------------------------------------
    -- Interface AXI-Lite (toujours prete, cf. note en tete)
    ---------------------------------------------------------------------
    s_axi_awready <= '1';
    s_axi_wready  <= '1';
    s_axi_arready <= '1';

    s_axi_bresp  <= "00";
    s_axi_bvalid <= '1';
    s_axi_rresp  <= "00";
    s_axi_rvalid <= '1';

    process (s_axi_aclk)
    begin
        if rising_edge(s_axi_aclk) then
            if s_axi_aresetn = '0' then
                ctrl_reg     <= (others => '0');
                period_reg   <= to_unsigned(100000, 32);
                duty_reg     <= to_unsigned(50000, 32);
                t_thresh_reg <= x"1E00_0FA0";
                duty_min_reg <= to_unsigned(10000, 32);
                duty_max_reg <= to_unsigned(90000, 32);
            else

                if s_axi_awvalid = '1' and s_axi_wvalid = '1' then
                    case s_axi_awaddr(5 downto 2) is
                        when "0000" =>
                            ctrl_reg <= s_axi_wdata;

                        when "0001" =>
                            period_reg <= unsigned(s_axi_wdata);

                        when "0010" =>
                            duty_reg <= unsigned(s_axi_wdata);

                        -- "0011" (DUTY_AUTO), "0100" (TEMP_RAW) et "1000"
                        -- (STATUS) : lecture seule, ecriture ignoree.

                        when "0101" =>
                            t_thresh_reg <= s_axi_wdata;

                        when "0110" =>
                            duty_min_reg <= unsigned(s_axi_wdata);

                        when "0111" =>
                            duty_max_reg <= unsigned(s_axi_wdata);

                        when others =>
                            null;
                    end case;
                end if;

                -- Sticky "nouvelle temperature disponible", remis a zero
                -- lors de la lecture du registre STATUS (0x20).
                if temp_valid = '1' then
                    temp_valid_sticky <= '1';
                elsif s_axi_arvalid = '1' and s_axi_araddr(5 downto 2) = "1000" then
                    temp_valid_sticky <= '0';
                end if;

            end if;
        end if;
    end process;

    ---------------------------------------------------------------------
    -- Interface AXI-Lite (lecture)
    ---------------------------------------------------------------------
    process (s_axi_araddr, ctrl_reg, period_reg, duty_reg, duty_auto,
             temp_centideg, t_thresh_reg, duty_min_reg, duty_max_reg,
             temp_valid_sticky)
    begin
        case s_axi_araddr(5 downto 2) is
            when "0000" =>
                rdata_i <= ctrl_reg;
            when "0001" =>
                rdata_i <= std_logic_vector(period_reg);
            when "0010" =>
                rdata_i <= std_logic_vector(duty_reg);
            when "0011" =>
                rdata_i <= std_logic_vector(duty_auto);
            when "0100" =>
                rdata_i <= std_logic_vector(resize(temp_centideg, 32));
            when "0101" =>
                rdata_i <= t_thresh_reg;
            when "0110" =>
                rdata_i <= std_logic_vector(duty_min_reg);
            when "0111" =>
                rdata_i <= std_logic_vector(duty_max_reg);
            when "1000" =>
                rdata_i <= (31 downto 1 => '0') & temp_valid_sticky;
            when others =>
                rdata_i <= (others => '0');
        end case;
    end process;

    s_axi_rdata <= rdata_i;

    ---------------------------------------------------------------------
    -- Generation PWM -- SORTIE ACTIVE BASSE (fan_en_b)
    --
    -- Valeur par defaut au reset : '0' (ventilateur active en continu).
    -- C'est un choix de securite (fail-safe) : tant que la chaine
    -- d'acquisition/asservissement n'a pas produit de premiere mesure
    -- valide, le ventilateur tourne a pleine puissance plutot que d'etre
    -- coupe (empeche une surchauffe silencieuse si le SYSMON ou la
    -- commande thermique ne demarre pas correctement).
    ---------------------------------------------------------------------
    process (s_axi_aclk)
    begin
        if rising_edge(s_axi_aclk) then
            if s_axi_aresetn = '0' then
                counter  <= (others => '0');
                fan_en_b <= '0';
            else
                if enable = '1' then

                    if counter >= period_reg - 1 then
                        counter <= (others => '0');
                    else
                        counter <= counter + 1;
                    end if;

                    if counter < duty_active then
                        fan_en_b <= '0';  -- phase active (ventilateur ON)
                    else
                        fan_en_b <= '1';  -- phase inactive (ventilateur OFF)
                    end if;

                else
                    -- Module desactive (ENABLE=0) : fail-safe -> ventilateur
                    -- force ON en continu plutot que coupe.
                    fan_en_b <= '0';
                end if;
            end if;
        end if;
    end process;

end architecture rtl;
