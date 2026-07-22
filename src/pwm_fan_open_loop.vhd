-------------------------------------------------------------------------------
-- pwm_fan_open_loop.vhd
--
-- IP PWM ventilateur totalement autonome et en boucle ouverte : PAS
-- d'acquisition de temperature (pas de SYSMON, pas de dependance a
-- unisim), PAS d'interface AXI. Seul le port clk doit etre connecte.
--
-- La frequence de commutation PWM et le rapport cyclique sont des
-- GENERIQUES VHDL fixes a la synthese (exposes automatiquement comme
-- parametres de personnalisation Vivado lors du packaging IP, modifiables
-- graphiquement dans le Block Design a chaque instanciation, mais figes
-- pour cette instance -- pas de registre, pas de pilotage logiciel).
--
-- Objectif : vehicule de test minimal, decouple de toute la chaine SYSMON/
-- AXI, pour valider isolement le cablage physique (contrainte XDC
-- fan_en_b) et le comportement mecanique du ventilateur a differents
-- rapports cycliques fixes, avant de reintroduire l'asservissement
-- thermique et/ou l'AXI.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity pwm_fan_open_loop is
    generic (
        -- Frequence de l'horloge clk, en Hz (utilisee uniquement pour
        -- convertir PWM_FREQ_HZ en nombre de coups d'horloge ; ne pilote
        -- pas la frequence reelle de clk, qui reste fixee par la source
        -- d'horloge du Block Design). 100 MHz : frequence fabric FPGA
        -- courante, a adapter a l'horloge reellement cablee.
        CLK_FREQ_HZ  : positive := 100_000_000;

        -- Frequence de commutation PWM souhaitee, en Hz. 25 kHz : frequence
        -- de reference pour les ventilateurs PWM 4 fils (spec Intel "4-Wire
        -- PWM Controlled Fans", plage acceptee ~21-28 kHz -- au-dessus du
        -- spectre audible, pertes de commutation limitees).
        PWM_FREQ_HZ  : positive := 25_000;

        -- Rapport cyclique fixe, en pourcentage (0 = ventilateur coupe en
        -- continu, 100 = ventilateur actif en continu). 30% par defaut :
        -- en dessous d'environ 20%, beaucoup de ventilateurs PWM decrochent
        -- ou ne redemarrent pas de facon fiable -- valeur de repos prudente.
        DUTY_PERCENT : natural range 0 to 100 := 30;

        -- Nombre de cycles du reset interne a la mise sous tension /
        -- reconfiguration du PL.
        POR_CYCLES   : natural := 16;

        -- Duree (en millisecondes) d'un "coup de fouet" a pleine puissance
        -- (100%) applique juste apres la sortie de reset, avant de
        -- redescendre au rapport cyclique nominal DUTY_PERCENT. Technique
        -- standard des controleurs de ventilateur PWM : un rapport
        -- cyclique nominal bas (ex. 30%) peut ne pas fournir assez de
        -- couple pour vaincre le frottement statique au demarrage depuis
        -- l'arret, alors qu'il suffit a maintenir la rotation une fois
        -- lancee. 0 = kick-start desactive (comportement precedent,
        -- DUTY_PERCENT applique directement des la sortie de reset).
        KICKSTART_MS : natural := 500
    );
    port (
        clk : in std_logic;  -- SEUL port obligatoire a connecter

        -- Sortie fan gating, ACTIVE BASSE (convention "_b" = active-low,
        -- cf. contrainte XDC "fan_en_b" du carrier KR260).
        -- '0' = ventilateur actif, '1' = coupe.
        fan_en_b : out std_logic
    );
end entity pwm_fan_open_loop;

architecture rtl of pwm_fan_open_loop is

    -- Calcules a l'elaboration a partir des generiques (aucune division en
    -- logique synthetisee : ce sont des constantes).
    constant PERIOD_CYCLES    : positive := CLK_FREQ_HZ / PWM_FREQ_HZ;
    constant DUTY_CYCLES      : natural  := (PERIOD_CYCLES * DUTY_PERCENT) / 100;
    constant KICKSTART_CYCLES : natural  := (CLK_FREQ_HZ / 1000) * KICKSTART_MS;

    -- Reset interne (power-on-reset synchrone), meme principe que dans
    -- pwm_fan_thermal_standalone.vhd.
    signal por_count : unsigned(7 downto 0) := (others => '0');
    signal rst       : std_logic := '1';

    signal counter : unsigned(31 downto 0) := (others => '0');

    -- Phase de kick-start : active des la sortie de reset, retombe a '0'
    -- (definitivement, jusqu'au prochain reset) une fois KICKSTART_CYCLES
    -- ecoules. Si KICKSTART_MS=0, retombe des le premier cycle utile.
    signal kickstart_count  : unsigned(31 downto 0) := (others => '0');
    signal kickstart_active : std_logic := '1';

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
    -- Phase de kick-start : compte KICKSTART_CYCLES cycles depuis la
    -- sortie de reset, puis desactive definitivement kickstart_active
    -- (jusqu'au prochain reset).
    ---------------------------------------------------------------------
    process (clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                kickstart_count  <= (others => '0');
                kickstart_active <= '1';
            elsif kickstart_active = '1' then
                if KICKSTART_CYCLES = 0 or kickstart_count >= KICKSTART_CYCLES - 1 then
                    kickstart_active <= '0';
                else
                    kickstart_count <= kickstart_count + 1;
                end if;
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------
    -- Generation PWM -- rapport cyclique fixe (DUTY_CYCLES/PERIOD_CYCLES)
    -- une fois la phase de kick-start ecoulee, sortie active basse. A
    -- DUTY_PERCENT=0, DUTY_CYCLES=0 et counter < 0 n'est jamais vrai
    -- (counter est unsigned) : fan_en_b reste a '1' (coupe) en continu,
    -- comme attendu (kick-start mis a part). A DUTY_PERCENT=100,
    -- DUTY_CYCLES=PERIOD_CYCLES : fan_en_b reste a '0' (actif) en continu.
    ---------------------------------------------------------------------
    process (clk)
    begin
        if rising_edge(clk) then
            if rst = '1' then
                counter  <= (others => '0');
                fan_en_b <= '1';  -- coupe pendant le reset
            else
                if counter >= PERIOD_CYCLES - 1 then
                    counter <= (others => '0');
                else
                    counter <= counter + 1;
                end if;

                if kickstart_active = '1' then
                    fan_en_b <= '0';  -- coup de fouet : actif en continu
                elsif counter < DUTY_CYCLES then
                    fan_en_b <= '0';  -- phase active (ventilateur ON)
                else
                    fan_en_b <= '1';  -- phase inactive (ventilateur OFF)
                end if;
            end if;
        end if;
    end process;

end architecture rtl;
