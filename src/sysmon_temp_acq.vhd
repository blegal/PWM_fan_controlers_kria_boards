-------------------------------------------------------------------------------
-- sysmon_temp_acq.vhd
--
-- Acquisition de la temperature on-chip via le bloc SYSMON (SYSMONE4) du PL,
-- Zynq UltraScale+ (KV260 / XCZU5EV).
--
-- Le SYSMON est un bloc materiel toujours present, mais il doit etre
-- INSTANCIE dans le PL pour etre accessible depuis la logique interconnect
-- (sinon seul JTAG/I2C ou l'espace PS AMS 0xFFA50000 y donnent acces).
-- Reference : UG580 "UltraScale Architecture System Monitor User Guide".
--
-- ATTENTION :
--  - DCLK doit respecter la frequence max du DRP SYSMON (verifier UG580
--    pour la revision d'outil utilisee, historiquement <= 26-40 MHz selon
--    les generations). Si l'horloge systeme est plus rapide, deriver un
--    DCLK plus lent (MMCM/PLL ou diviseur) avant de l'utiliser ici.
--  - La liste de ports ci-dessous suit le template standard SYSMONE4 mais
--    DOIT etre confirmee via Vivado (Language Templates > Xilinx Primitive
--    Instantiation > SYSMONE4) car generiques/ports varient selon version.
--  - Les constantes de conversion (SCALE_*/OFFSET_*) suivent la formule
--    couramment citee pour SYSMONE4 (equations UG580 "Temperature Sensor"),
--    A VERIFIER contre la revision exacte de l'UG580 livree avec le Vivado
--    utilise (l'equation a ete revisee plusieurs fois entre versions).
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

entity sysmon_temp_acq is
    generic (
        -- Periode de scrutation du DRP, en cycles de DCLK, entre deux
        -- lectures du registre temperature (le SYSMON n'a pas besoin d'etre
        -- interroge en continu, la temperature varie lentement).
        POLL_PERIOD_CYCLES : natural := 4096;

        -- Conversion code ADC (12 bits, 0..4095) -> temperature x100 (C).
        -- temp_centideg = (ADC_code * SCALE_NUM) / SCALE_DEN - OFFSET_CENTIDEG
        -- Valeurs par defaut usuelles UG580 (A VERIFIER, cf. note en tete),
        -- deja mises a l'echelle x100 pour rester en arithmetique entiere
        -- 32 bits sans depassement (code max 4095) :
        --   Temp(C) = ADC_code * 509.3140064 / 4096 - 280.23087870
        --   => SCALE_NUM = 50931 (509.31 x100), OFFSET = 28023 (280.23 x100)
        -- Precision limitee a 2 decimales sur les constantes ; largement
        -- suffisant vu la precision propre du capteur (de l'ordre de 1 C).
        SCALE_NUM        : integer := 50931;
        SCALE_DEN        : integer := 4096;
        OFFSET_CENTIDEG  : integer := 28023
    );
    port (
        dclk           : in  std_logic;  -- horloge DRP, cf. contrainte ci-dessus
        rst            : in  std_logic;

        -- Resultats
        temp_raw12     : out std_logic_vector(11 downto 0);
        temp_centideg  : out signed(15 downto 0);  -- ex: 4523 = 45.23 C
        temp_valid     : out std_logic;            -- pulse 1 cycle dclk

        -- Alarmes SYSMON (facultatif, cablees pour info/latch externe)
        ot_alarm       : out std_logic
    );
end entity sysmon_temp_acq;

architecture rtl of sysmon_temp_acq is

    -- Interface DRP
    -- NOTE : DADDR fait 8 bits sur SYSMONE4 (et non 7, cf. retour de
    -- synthese Synth 8-549 corrige ici).
    signal daddr  : std_logic_vector(7 downto 0) := (others => '0');
    signal den    : std_logic := '0';
    signal dwe    : std_logic := '0';
    signal di     : std_logic_vector(15 downto 0) := (others => '0');
    signal do_v   : std_logic_vector(15 downto 0);
    signal drdy   : std_logic;
    signal busy_v : std_logic;
    signal channel_v : std_logic_vector(5 downto 0);
    signal eoc_v  : std_logic;
    signal eos_v  : std_logic;
    signal alm_v  : std_logic_vector(15 downto 0);

    type state_t is (ST_WAIT_POLL, ST_ISSUE_READ, ST_WAIT_DRDY, ST_LATCH);
    signal state       : state_t := ST_WAIT_POLL;
    signal poll_cnt     : natural range 0 to POLL_PERIOD_CYCLES := 0;

    signal raw12_i      : unsigned(11 downto 0) := (others => '0');
    signal temp_valid_i : std_logic := '0';

begin

    ---------------------------------------------------------------------
    -- Instanciation SYSMONE4 (template a confirmer via Vivado, cf. note)
    ---------------------------------------------------------------------
    SYSMONE4_inst : SYSMONE4
        generic map (
            -- Cible Zynq UltraScale+ (KV260/KR260) : SIM_DEVICE doit etre
            -- "ZYNQ_ULTRASCALE" et non la valeur par defaut
            -- "ULTRASCALE_PLUS" (qui vise les familles UltraScale+
            -- non-Zynq, ex. Kintex/Virtex UltraScale+). Necessaire pour
            -- que la simulation corresponde au comportement materiel et
            -- pour eviter le blocage de generation du bitstream (cf.
            -- Netlist 29-345).
            SIM_DEVICE  => "ZYNQ_ULTRASCALE",
            INIT_40 => X"0000",  -- config reg0 : mode par defaut
            INIT_41 => X"2000",  -- config reg1 : sequencer off (DRP master)
            INIT_42 => X"0400",  -- config reg2 : ADCCLK = DCLK/... (cf. UG580)
            IS_DCLK_INVERTED => '0'
        )
        port map (
            -- DRP
            DCLK        => dclk,
            RESET       => rst,
            DADDR       => daddr,
            DEN         => den,
            DWE         => dwe,
            DI          => di,
            DO          => do_v,
            DRDY        => drdy,

            -- Statut / alarmes
            BUSY        => busy_v,
            CHANNEL     => channel_v,
            EOC         => eoc_v,
            EOS         => eos_v,
            ALM         => alm_v,
            OT          => ot_alarm,

            -- Conversion analogique demarree en interne (mode par defaut) :
            -- pas de CONVST externe necessaire pour la temperature.
            CONVST      => '0',
            CONVSTCLK   => '0',

            -- Entrees auxiliaires non utilisees ici
            VAUXP       => (others => '0'),
            VAUXN       => (others => '0'),
            VP          => '0',
            VN          => '0',

            -- I2C non utilise (DRP uniquement)
            I2C_SCLK    => '0',
            I2C_SDA     => '0'
        );

    ---------------------------------------------------------------------
    -- FSM de scrutation DRP : lit periodiquement le registre temperature
    -- (adresse status 0x00) et convertit le code ADC.
    ---------------------------------------------------------------------
    process (dclk)
    begin
        if rising_edge(dclk) then
            if rst = '1' then
                state        <= ST_WAIT_POLL;
                poll_cnt     <= 0;
                den          <= '0';
                dwe          <= '0';
                daddr        <= (others => '0');
                temp_valid_i <= '0';
            else
                temp_valid_i <= '0';

                case state is

                    when ST_WAIT_POLL =>
                        if poll_cnt = POLL_PERIOD_CYCLES then
                            poll_cnt <= 0;
                            state    <= ST_ISSUE_READ;
                        else
                            poll_cnt <= poll_cnt + 1;
                        end if;

                    when ST_ISSUE_READ =>
                        daddr <= "00000000";  -- 0x00 : registre temperature
                        dwe   <= '0';
                        den   <= '1';
                        state <= ST_WAIT_DRDY;

                    when ST_WAIT_DRDY =>
                        den <= '0';
                        if drdy = '1' then
                            state <= ST_LATCH;
                        end if;

                    when ST_LATCH =>
                        -- DO(15:4) = code ADC 12 bits, DO(3:0) reserve
                        raw12_i      <= unsigned(do_v(15 downto 4));
                        temp_valid_i <= '1';
                        state        <= ST_WAIT_POLL;

                end case;
            end if;
        end if;
    end process;

    temp_raw12 <= std_logic_vector(raw12_i);
    temp_valid <= temp_valid_i;

    ---------------------------------------------------------------------
    -- Conversion code ADC -> centidegres Celsius (registree en meme temps
    -- que temp_valid pour rester coherente avec le pulse de validite).
    ---------------------------------------------------------------------
    process (dclk)
        variable scaled_centideg : integer;
    begin
        if rising_edge(dclk) then
            if rst = '1' then
                temp_centideg <= (others => '0');
            elsif temp_valid_i = '1' then
                -- (4095 * 50931) ~= 2.086e8, largement < 2^31-1 : pas de
                -- depassement de capacite sur le type integer (32 bits).
                scaled_centideg := (to_integer(raw12_i) * SCALE_NUM) / SCALE_DEN
                                    - OFFSET_CENTIDEG;
                temp_centideg <= to_signed(scaled_centideg, 16);
            end if;
        end if;
    end process;

end architecture rtl;
