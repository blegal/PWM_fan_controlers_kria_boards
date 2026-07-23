-------------------------------------------------------------------------------
-- pwm_axi_lite_v1_0.vhd
--
-- IP AXI4-Lite : generateur de signal PWM configurable via 3 registres.
--
-- Principe : un compteur cyclique compte de 0 a PERIOD-1 (coups d'horloge
-- s_axi_aclk), puis reboucle a 0. La sortie pwm_out est a l'etat HAUT tant
-- que le compteur est strictement inferieur a THRESHOLD, puis passe a
-- l'etat BAS des que le compteur atteint THRESHOLD, et ce jusqu'a la fin
-- de la periode (retour du compteur a 0). On module donc ici la DUREE DE
-- L'ETAT HAUT : duree haute = THRESHOLD coups d'horloge (THRESHOLD/PERIOD
-- = rapport cyclique).
--
-- NOTE POLARITE : polarite inversee par rapport a une premiere version de
-- cette IP (ou THRESHOLD marquait le front MONTANT au lieu du front
-- DESCENDANT) suite a un asservissement observe inverse par rapport a
-- l'attendu en test reel. Si vous branchez pwm_out sur un driver/transistor
-- qui inverse lui-meme le signal (cas frequent pour piloter un
-- ventilateur), verifiez le sens reel obtenu au banc avant de vous fier a
-- la seule documentation.
--
--   compteur : 0 ----------------- THRESHOLD ----------------- PERIOD-1 -> 0
--   pwm_out  : _________________HAUT________|___________BAS______________|
--
-- Carte memoire (registres 32 bits, adresses sur 4 bits -> decode sur
-- s_axi_awaddr(3 downto 2), 4 emplacements possibles, 3 utilises) :
--
--   0x00 PERIOD    nombre de coups d'horloge d'une periode PWM, RW
--   0x04 THRESHOLD coup d'horloge a partir duquel pwm_out passe a l'etat
--                  bas (doit rester <= PERIOD, sans quoi pwm_out reste haut
--                  en permanence -- pas de verification materielle), RW
--   0x08 CTRL      bit0 = ENABLE (1=actif, 0=inactif), RW
--
-- IMPORTANT (logiciel) :
--  - THRESHOLD >= PERIOD => pwm_out reste haut en permanence (le compteur
--    n'atteint jamais THRESHOLD avant de reboucler a 0).
--  - THRESHOLD = 0 => pwm_out reste bas en permanence.
--  - ENABLE=0 : pwm_out force a '0' (etat BAS, PAS haut) et compteur fige a
--    0. Choix fail-safe delibere pour piloter un ventilateur : desactiver
--    le module met la sortie en pleine puissance plutot que de couper le
--    ventilateur, pour ne jamais risquer une surchauffe silencieuse en cas
--    de desactivation logicielle (accidentelle ou non) -- cf. note polarite
--    ci-dessus : '0' est ici l'etat "pleine puissance" (inverse de la
--    premiere version de cette IP). La generation PWM redemarre proprement
--    a compter de 0 des le retour a ENABLE=1.
--  - Valeurs par defaut au reset : CTRL.ENABLE=1 (module ACTIF PAR DEFAUT,
--    sans attendre de configuration logicielle), PERIOD=50000,
--    THRESHOLD=35000, soit 2kHz a 100MHz d'horloge s_axi_aclk et 70% de
--    temps haut (a adapter si s_axi_aclk n'est pas a 100MHz).
--  - Changer PERIOD/THRESHOLD prend effet immediatement (pas de recopie en
--    debut de periode) : un changement en cours de periode peut donc
--    produire une periode partielle ponctuelle le temps que le compteur
--    reboucle.
--
-- Handshake AXI4-Lite : meme pattern READY/VALID correctement sequence que
-- les autres IP AXI-Lite de ce depot (un seul transfert en vol par canal),
-- cf. pwm_fan_thermal_axi_v1_0.vhd / build_info_axi_v1_0.vhd.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity pwm_axi_lite_v1_0 is
    port (
        s_axi_aclk    : in  std_logic;
        s_axi_aresetn : in  std_logic;

        s_axi_awaddr  : in  std_logic_vector(3 downto 0);
        s_axi_awvalid : in  std_logic;
        s_axi_awready : out std_logic;

        s_axi_wdata   : in  std_logic_vector(31 downto 0);
        s_axi_wvalid  : in  std_logic;
        s_axi_wready  : out std_logic;

        s_axi_bresp   : out std_logic_vector(1 downto 0);
        s_axi_bvalid  : out std_logic;
        s_axi_bready  : in  std_logic;

        s_axi_araddr  : in  std_logic_vector(3 downto 0);
        s_axi_arvalid : in  std_logic;
        s_axi_arready : out std_logic;

        s_axi_rdata   : out std_logic_vector(31 downto 0);
        s_axi_rresp   : out std_logic_vector(1 downto 0);
        s_axi_rvalid  : out std_logic;
        s_axi_rready  : in  std_logic;

        pwm_out       : out std_logic
    );
end entity pwm_axi_lite_v1_0;

architecture rtl of pwm_axi_lite_v1_0 is

    -- Registres AXI (valeurs par defaut : module ACTIF (ENABLE=1), 50000
    -- coups/periode (2kHz a 100MHz), 35000 coups avant le front descendant
    -- -- 70% de temps haut des la sortie de reset, cf. note en tete de fichier).
    signal ctrl_reg      : std_logic_vector(31 downto 0) := x"00000001";
    signal period_reg    : unsigned(31 downto 0) := to_unsigned(50000, 32);
    signal threshold_reg : unsigned(31 downto 0) := to_unsigned(35000, 32);

    alias enable : std_logic is ctrl_reg(0);

    -- Compteur PWM
    signal counter : unsigned(31 downto 0) := (others => '0');

    -- Handshake AXI4-Lite (pattern standard, identique aux autres IP de ce
    -- depot : un seul transfert en vol par canal).
    signal axi_awaddr  : std_logic_vector(3 downto 0) := (others => '0');
    signal axi_awready : std_logic := '0';
    signal axi_wready  : std_logic := '0';
    signal aw_en       : std_logic := '1';
    signal axi_bvalid  : std_logic := '0';

    signal axi_araddr  : std_logic_vector(3 downto 0) := (others => '0');
    signal axi_arready : std_logic := '0';
    signal axi_rvalid  : std_logic := '0';

    signal slv_reg_wren : std_logic;

    signal rdata_i : std_logic_vector(31 downto 0) := (others => '0');

begin

    ---------------------------------------------------------------------
    -- Interface AXI-Lite -- handshake READY/VALID correct (un transfert en
    -- vol par canal).
    ---------------------------------------------------------------------
    s_axi_awready <= axi_awready;
    s_axi_wready  <= axi_wready;
    s_axi_bresp   <= "00";
    s_axi_bvalid  <= axi_bvalid;
    s_axi_arready <= axi_arready;
    s_axi_rresp   <= "00";
    s_axi_rvalid  <= axi_rvalid;

    slv_reg_wren <= axi_wready and s_axi_wvalid and axi_awready and s_axi_awvalid;

    -- AWREADY : accepte une nouvelle adresse d'ecriture quand aucune n'est
    -- deja en cours de traitement (aw_en), et tant que BVALID n'a pas ete
    -- acquitte par le maitre (BREADY).
    process (s_axi_aclk)
    begin
        if rising_edge(s_axi_aclk) then
            if s_axi_aresetn = '0' then
                axi_awready <= '0';
                aw_en       <= '1';
            elsif axi_awready = '0' and s_axi_awvalid = '1' and
                  s_axi_wvalid = '1' and aw_en = '1' then
                axi_awready <= '1';
                aw_en       <= '0';
            elsif s_axi_bready = '1' and axi_bvalid = '1' then
                aw_en       <= '1';
                axi_awready <= '0';
            else
                axi_awready <= '0';
            end if;
        end if;
    end process;

    -- Capture de l'adresse d'ecriture au moment de son acceptation.
    process (s_axi_aclk)
    begin
        if rising_edge(s_axi_aclk) then
            if s_axi_aresetn = '0' then
                axi_awaddr <= (others => '0');
            elsif axi_awready = '0' and s_axi_awvalid = '1' and
                  s_axi_wvalid = '1' and aw_en = '1' then
                axi_awaddr <= s_axi_awaddr;
            end if;
        end if;
    end process;

    -- WREADY : suit AWREADY (adresse et donnee acceptees ensemble).
    process (s_axi_aclk)
    begin
        if rising_edge(s_axi_aclk) then
            if s_axi_aresetn = '0' then
                axi_wready <= '0';
            elsif axi_wready = '0' and s_axi_wvalid = '1' and
                  s_axi_awvalid = '1' and aw_en = '1' then
                axi_wready <= '1';
            else
                axi_wready <= '0';
            end if;
        end if;
    end process;

    -- Ecriture effective des registres (un seul cycle, sur slv_reg_wren).
    process (s_axi_aclk)
    begin
        if rising_edge(s_axi_aclk) then
            if s_axi_aresetn = '0' then
                ctrl_reg      <= x"00000001";  -- ENABLE=1 (actif par defaut)
                period_reg    <= to_unsigned(50000, 32);
                threshold_reg <= to_unsigned(35000, 32);  -- 70% de temps haut
            else
                if slv_reg_wren = '1' then
                    case axi_awaddr(3 downto 2) is
                        when "00" =>
                            period_reg <= unsigned(s_axi_wdata);
                        when "01" =>
                            threshold_reg <= unsigned(s_axi_wdata);
                        when "10" =>
                            ctrl_reg <= s_axi_wdata;
                        when others =>
                            null;
                    end case;
                end if;
            end if;
        end if;
    end process;

    -- BVALID/BRESP : une reponse par ecriture acceptee, maintenue jusqu'a
    -- l'acquittement BREADY du maitre.
    process (s_axi_aclk)
    begin
        if rising_edge(s_axi_aclk) then
            if s_axi_aresetn = '0' then
                axi_bvalid <= '0';
            elsif axi_awready = '1' and s_axi_awvalid = '1' and
                  axi_wready = '1' and s_axi_wvalid = '1' and axi_bvalid = '0' then
                axi_bvalid <= '1';
            elsif s_axi_bready = '1' and axi_bvalid = '1' then
                axi_bvalid <= '0';
            end if;
        end if;
    end process;

    -- ARREADY : accepte une nouvelle adresse de lecture quand aucune
    -- reponse RVALID n'est en cours.
    process (s_axi_aclk)
    begin
        if rising_edge(s_axi_aclk) then
            if s_axi_aresetn = '0' then
                axi_arready <= '0';
                axi_araddr  <= (others => '0');
            elsif axi_arready = '0' and s_axi_arvalid = '1' and axi_rvalid = '0' then
                axi_arready <= '1';
                axi_araddr  <= s_axi_araddr;
            else
                axi_arready <= '0';
            end if;
        end if;
    end process;

    -- RVALID/RRESP : une reponse par lecture acceptee, maintenue jusqu'a
    -- l'acquittement RREADY du maitre.
    process (s_axi_aclk)
    begin
        if rising_edge(s_axi_aclk) then
            if s_axi_aresetn = '0' then
                axi_rvalid <= '0';
            elsif axi_arready = '1' and s_axi_arvalid = '1' and axi_rvalid = '0' then
                axi_rvalid <= '1';
            elsif axi_rvalid = '1' and s_axi_rready = '1' then
                axi_rvalid <= '0';
            end if;
        end if;
    end process;

    ---------------------------------------------------------------------
    -- Donnee de lecture (mux combinatoire sur l'adresse capturee)
    ---------------------------------------------------------------------
    process (axi_araddr, period_reg, threshold_reg, ctrl_reg)
    begin
        case axi_araddr(3 downto 2) is
            when "00" =>
                rdata_i <= std_logic_vector(period_reg);
            when "01" =>
                rdata_i <= std_logic_vector(threshold_reg);
            when "10" =>
                rdata_i <= ctrl_reg;
            when others =>
                rdata_i <= (others => '0');
        end case;
    end process;

    s_axi_rdata <= rdata_i;

    ---------------------------------------------------------------------
    -- Generation PWM -- gatee par CTRL.ENABLE (actif par defaut au reset,
    -- cf. note en tete de fichier). Polarite inversee par rapport a la
    -- premiere version de cette IP (cf. note polarite en tete de fichier) :
    -- pwm_out est HAUT tant que counter < THRESHOLD, BAS ensuite. Quand
    -- ENABLE=0 : compteur fige a 0 et pwm_out FORCE BAS (fail-safe pleine
    -- puissance ventilateur avec cette nouvelle polarite, PAS un arret),
    -- redemarrage propre a compter de 0 des le retour a ENABLE=1 (pas
    -- d'etat "en cours de periode" fige a la reprise).
    ---------------------------------------------------------------------
    process (s_axi_aclk)
    begin
        if rising_edge(s_axi_aclk) then
            if s_axi_aresetn = '0' then
                counter <= (others => '0');
                pwm_out <= '1';
            elsif enable = '0' then
                counter <= (others => '0');
                pwm_out <= '0';
            else
                if counter >= period_reg - 1 then
                    counter <= (others => '0');
                else
                    counter <= counter + 1;
                end if;

                if counter < threshold_reg then
                    pwm_out <= '1';
                else
                    pwm_out <= '0';
                end if;
            end if;
        end if;
    end process;

end architecture rtl;
