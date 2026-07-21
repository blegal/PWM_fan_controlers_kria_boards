-------------------------------------------------------------------------------
-- fan_thermal_ctrl.vhd
--
-- Loi de commande temperature -> duty cycle (asservissement statique,
-- interpolation lineaire par morceaux) :
--
--   temp <= t_min           => duty = duty_min
--   temp >= t_max           => duty = duty_max
--   t_min < temp < t_max    => interpolation lineaire entre duty_min et
--                              duty_max
--
-- duty_min/duty_max sont exprimes dans la meme unite que period_reg du
-- module PWM (nombre de coups d'horloge), pas en pourcentage.
--
-- NOTE SYNTHESE : la division utilisee pour l'interpolation emploie
-- l'operateur "/" sur des unsigned 32 bits. Vivado peut la synthetiser en
-- logique combinatoire (potentiellement plusieurs dizaines de LUTs / un
-- DSP). Comme le calcul n'est redeclenche que sur temp_valid (frequence
-- tres basse, la temperature variant lentement), la latence combinatoire
-- ne pose en general pas de probleme de timing. Si le timing venait a
-- echouer sur un design a frequence tres elevee, remplacer ce diviseur par
-- un diviseur sequentiel multi-cycles (registered instantiable a la place).
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fan_thermal_ctrl is
    port (
        clk           : in  std_logic;
        rst           : in  std_logic;

        -- Entree temperature (centidegres C, signe)
        temp_centideg : in  signed(15 downto 0);
        temp_valid    : in  std_logic;

        -- Seuils et bornes de duty (configurables via AXI depuis le top)
        t_min         : in  signed(15 downto 0);
        t_max         : in  signed(15 downto 0);
        duty_min      : in  unsigned(31 downto 0);
        duty_max      : in  unsigned(31 downto 0);

        -- Sortie
        duty_auto     : out unsigned(31 downto 0);
        duty_valid    : out std_logic
    );
end entity fan_thermal_ctrl;

architecture rtl of fan_thermal_ctrl is

    signal duty_auto_i  : unsigned(31 downto 0) := (others => '0');
    signal duty_valid_i : std_logic := '0';

begin

    process (clk)
        variable temp_span   : signed(16 downto 0);
        variable temp_offset : signed(16 downto 0);
        variable duty_span   : unsigned(31 downto 0);
        variable interp_num  : unsigned(63 downto 0);
        variable interp_res  : unsigned(31 downto 0);
    begin
        if rising_edge(clk) then
            duty_valid_i <= '0';

            if rst = '1' then
                duty_auto_i <= (others => '0');
            elsif temp_valid = '1' then

                if temp_centideg <= t_min then
                    duty_auto_i <= duty_min;

                elsif temp_centideg >= t_max then
                    duty_auto_i <= duty_max;

                else
                    -- temp_span = t_max - t_min (garanti > 0 par les tests
                    -- ci-dessus ; le logiciel doit s'assurer t_max > t_min)
                    temp_span   := resize(t_max, 17) - resize(t_min, 17);
                    temp_offset := resize(temp_centideg, 17) - resize(t_min, 17);
                    duty_span   := duty_max - duty_min;

                    -- interp = duty_min + duty_span * temp_offset / temp_span
                    interp_num := unsigned(resize(temp_offset, 32)) *
                                  resize(duty_span, 32);

                    if temp_span = 0 then
                        interp_res := (others => '0');
                    else
                        interp_res := resize(
                            interp_num / resize(unsigned(temp_span), 64), 32);
                    end if;

                    duty_auto_i <= duty_min + interp_res;
                end if;

                duty_valid_i <= '1';
            end if;
        end if;
    end process;

    duty_auto  <= duty_auto_i;
    duty_valid <= duty_valid_i;

end architecture rtl;
