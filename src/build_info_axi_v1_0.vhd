-------------------------------------------------------------------------------
-- build_info_axi_v1_0.vhd
--
-- IP AXI4-Lite SLAVE, en lecture seule : expose a la partie PS la date/heure
-- de synthese, un numero de build, et le numero de version (majeur/mineur)
-- du design, via 6 registres 32 bits fixes (valeurs figees a l'elaboration
-- par generics, pas de logique d'horloge temps reel -- le VHDL n'a pas
-- acces a une horloge de compilation, cf. tcl/set_build_info.tcl pour la
-- fabrication automatique de ces valeurs).
--
-- Carte memoire (registres 32 bits, adresses sur 6 bits -> decode sur
-- s_axi_awaddr(5 downto 2), 16 emplacements possibles, 6 utilises), TOUS
-- EN LECTURE SEULE (le canal d'ecriture AXI4-Lite est neanmoins implemente
-- pour rester conforme au protocole : toute ecriture est acceptee et
-- acquittee OKAY, mais son contenu est ignore) :
--
--   0x00 MAGIC         signature fixe x"42494E46" ("BINF" en ASCII), pour
--                       permettre a un driver logiciel de confirmer qu'il
--                       dialogue bien avec cette IP (motif fixe non nul et
--                       non trivial, plus fiable qu'un simple test
--                       ecriture/lecture puisque le registre est RO).
--   0x04 BUILD_DATE    date de synthese, format 0xYYYYMMDD (ex: 0x20260723
--                       pour le 23 juillet 2026), depuis generic G_BUILD_DATE.
--   0x08 BUILD_TIME    heure de synthese, format 0x00HHMMSS (ex: 0x00143512
--                       pour 14:35:12), depuis generic G_BUILD_TIME.
--   0x0C VERSION_MAJOR numero de version majeur, depuis generic G_VERSION_MAJOR.
--   0x10 VERSION_MINOR numero de version mineur, depuis generic G_VERSION_MINOR.
--   0x14 BUILD_NUMBER  compteur de build (incremente a chaque packaging de
--                       l'IP par tcl/package_ip_build_info.tcl, cf.
--                       tcl/build_counter.tcl), depuis generic G_BUILD_NUMBER.
--                       Sert a verifier que le bitstream charge correspond
--                       bien au dernier packaging effectue (comparer avec le
--                       numero affiche dans le terminal lors du packaging).
--
-- Les 5 generics sont exposees comme parametres de personnalisation de l'IP
-- (onglet Vivado IP customization, generation automatique via
-- ipx::create_xgui_files). Valeurs par defaut = 0 : PENSER A LES RENSEIGNER
-- (a la main dans le Block Design, ou via tcl/set_build_info.tcl qui calcule
-- la date/heure courante, relit le dernier BUILD_NUMBER connu, et peut
-- positionner CONFIG.G_BUILD_DATE/G_BUILD_TIME/G_BUILD_NUMBER sur l'instance
-- juste avant la synthese) sous peine d'obtenir 0 partout.
--
-- Handshake AXI4-Lite : meme pattern READY/VALID correctement sequence que
-- pwm_fan_thermal_axi_v1_0.vhd (un seul transfert en vol par canal) --
-- reutilise ici tel quel pour la partie infrastructure AXI, seule la partie
-- registres (ici constants figes, pas d'ecriture reelle) differe.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity build_info_axi_v1_0 is
    generic (
        G_VERSION_MAJOR : std_logic_vector(31 downto 0) := x"00000000";
        G_VERSION_MINOR : std_logic_vector(31 downto 0) := x"00000000";
        G_BUILD_DATE    : std_logic_vector(31 downto 0) := x"00000000";
        G_BUILD_TIME    : std_logic_vector(31 downto 0) := x"00000000";
        G_BUILD_NUMBER  : std_logic_vector(31 downto 0) := x"00000000"
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
        s_axi_rready  : in  std_logic
    );
end entity build_info_axi_v1_0;

architecture rtl of build_info_axi_v1_0 is

    constant MAGIC_REG : std_logic_vector(31 downto 0) := x"42494E46";  -- "BINF"

    -- Handshake AXI4-Lite (pattern standard, identique a
    -- pwm_fan_thermal_axi_v1_0.vhd : un seul transfert en vol par canal).
    signal axi_awaddr  : std_logic_vector(5 downto 0) := (others => '0');
    signal axi_awready : std_logic := '0';
    signal axi_wready  : std_logic := '0';
    signal aw_en       : std_logic := '1';
    signal axi_bvalid  : std_logic := '0';

    signal axi_araddr  : std_logic_vector(5 downto 0) := (others => '0');
    signal axi_arready : std_logic := '0';
    signal axi_rvalid  : std_logic := '0';

    signal rdata_i : std_logic_vector(31 downto 0) := (others => '0');

begin

    ---------------------------------------------------------------------
    -- Interface AXI-Lite -- handshake READY/VALID correct (un transfert en
    -- vol par canal). Le canal d'ecriture est implemente pour rester
    -- conforme AXI4-Lite (BVALID/BRESP requis en reponse a toute ecriture)
    -- mais aucun registre n'est reellement modifiable : tout est en
    -- lecture seule, valeurs figees par generics.
    ---------------------------------------------------------------------
    s_axi_awready <= axi_awready;
    s_axi_wready  <= axi_wready;
    s_axi_bresp   <= "00";
    s_axi_bvalid  <= axi_bvalid;
    s_axi_arready <= axi_arready;
    s_axi_rresp   <= "00";
    s_axi_rvalid  <= axi_rvalid;

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

    -- Capture de l'adresse d'ecriture (non utilisee pour du decodage
    -- registre ici puisque tout est RO, conservee pour rester au plus
    -- proche du pattern standard et faciliter une extension future).
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

    -- BVALID/BRESP : une reponse par ecriture acceptee, maintenue jusqu'a
    -- l'acquittement BREADY du maitre. Aucune donnee n'est ecrite (RO).
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
    process (axi_araddr)
    begin
        case axi_araddr(5 downto 2) is
            when "0000" =>
                rdata_i <= MAGIC_REG;
            when "0001" =>
                rdata_i <= G_BUILD_DATE;
            when "0010" =>
                rdata_i <= G_BUILD_TIME;
            when "0011" =>
                rdata_i <= G_VERSION_MAJOR;
            when "0100" =>
                rdata_i <= G_VERSION_MINOR;
            when "0101" =>
                rdata_i <= G_BUILD_NUMBER;
            when others =>
                rdata_i <= (others => '0');
        end case;
    end process;

    s_axi_rdata <= rdata_i;

end architecture rtl;
