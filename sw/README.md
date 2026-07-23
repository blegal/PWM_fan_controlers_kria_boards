# Couche logicielle -- pwm_fan_thermal_axi_v1_0, build_info_axi_v1_0 et pwm_axi_lite_v1_0

Applications baremetal (Vitis, domaine "standalone") pour :
- l'IP AXI4-Lite `pwm_fan_thermal_axi_v1_0` (voir
  `src/pwm_fan_thermal_axi_v1_0.vhd`), avec un driver ecrit a la main
  (`drivers/pwm_fan_thermal/`) et un exemple d'application demontrant le
  pilotage manuel du rapport cyclique ;
- l'IP AXI4-Lite en lecture seule `build_info_axi_v1_0` (voir
  `src/build_info_axi_v1_0.vhd`), avec un driver ecrit a la main
  (`drivers/build_info/`) et un exemple affichant la date/heure de synthese
  et la version du design ;
- l'IP AXI4-Lite `pwm_axi_lite_v1_0` (voir `src/pwm_axi_lite_v1_0.vhd`),
  generateur PWM generique a 3 registres (PERIOD/THRESHOLD/CTRL), actif par
  defaut au reset, avec un driver ecrit a la main (`drivers/pwm_axi_lite/`)
  et un exemple de rampe de temps haut 0-100%.

Chaque fichier `examples/test_*.c` expose une fonction `test_*(void)` --
**ce n'est pas un point d'entree** : aucun de ces fichiers ne contient de
`main()`. C'est a l'application (un seul `main()` par projet Vitis) d'appeler
celle(s) qu'elle souhaite executer.

```
sw/
  drivers/pwm_fan_thermal/
    pwm_fan_thermal.h   -- API + carte memoire des registres
    pwm_fan_thermal.c   -- implementation (Xil_In32/Xil_Out32)
  drivers/build_info/
    build_info.h        -- API + carte memoire des registres (MAGIC/BUILD_DATE/BUILD_TIME/VERSION_*)
    build_info.c         -- implementation (Xil_In32, decodage BCD)
  drivers/pwm_axi_lite/
    pwm_axi_lite.h      -- API + carte memoire des registres (PERIOD/THRESHOLD/CTRL)
    pwm_axi_lite.c      -- implementation (Xil_In32/Xil_Out32)
  examples/
    test_pwm_fan_thermal.c    -- self-test + rampe manuelle 0-100%
    test_build_info.c         -- self-test + affichage date/heure de synthese + version
    test_pwm_axi_lite.c       -- self-test + rampe de temps haut 100-0% + arret/pleine puissance/asservissement
```

## Prealable materiel

Cote Vivado : l'IP doit etre instanciee dans le Block Design avec `s_axi_aclk`
connecte a une horloge et `s_axi_aresetn` a un reset actif bas, puis le
hardware exporte (**File > Export > Export Hardware**, format `.xsa`,
"Include bitstream" coche).

## Integration dans un projet Vitis 2026.1

Vitis 2026.1 utilise le flot unifie (platform component / application
component bases sur CMake). Etapes :

1. **Create Platform Component** a partir du `.xsa` exporte, domaine
   `standalone` (ou `freertos` si vous utilisez FreeRTOS -- le driver ne
   depend d'aucun OS, il fonctionne dans les deux cas), processeur cible
   (`psu_cortexa53_0` / `psv_cortexa53_0` selon la famille -- KR260 =
   Zynq UltraScale+, coeurs Cortex-A53).
2. Build le platform component pour generer `xparameters.h`.
3. **Create Application Component**, lie a ce platform.
4. Copier (ou ajouter comme source externe) les fichiers de ce dossier dans
   les sources de l'application :
   - `drivers/pwm_fan_thermal/pwm_fan_thermal.c` et `.h`
   - `examples/test_pwm_fan_thermal.c` (n'est PAS un point d'entree : ecrire
     un `main()` propre a l'application qui appelle `test_pwm_fan_thermal()`)
5. Le nom de macro `BASEADDR` par defaut suppose dans `test_pwm_fan_thermal.c`
   (`XPAR_PWM_FAN_THERMAL_AXI_V1_0_0_S_AXI_BASEADDR`) decoule directement de
   `tcl/package_ip_axi.tcl` (VLNV name `pwm_fan_thermal_axi_v1_0`, bus
   interface associee sous le nom `S_AXI`) combine au nommage automatique
   Vivado de la premiere instance deposee dans le Block Design (suffixe
   `_0`) : c'est le nom attendu tel quel dans la config par defaut. A
   n'adapter que si vous renommez l'instance dans le Block Design, ou en
   instanciez plusieurs (suffixe `_1`, `_2`, ... pour les suivantes) --
   dans ce cas, verifier dans `xparameters.h` genere (platform component,
   `psu_cortexa53_0/standalone_domain/bsp/psu_cortexa53_0/include/` ou
   equivalent). Si la macro attendue est introuvable, la compilation
   s'arrete avec une erreur explicite (`#error`) plutot que de se rabattre
   silencieusement sur une adresse par defaut potentiellement fausse.
6. Build + **Run As > Launch Hardware** (ou debug JTAG) sur la cible.

> Comme l'IP a ete packagee via les scripts `tcl/package_ip_*.tcl` sans
> repertoire `drivers/` Xilinx (pas de `driver_v1_0` genere par
> `ipx::add_file_group` dans le packaging), Vitis ne proposera pas
> automatiquement ce driver via son mecanisme habituel de detection de BSP
> ("generic" peripheral). C'est voulu : le driver de ce dossier s'utilise en
> l'ajoutant manuellement aux sources de l'application, comme decrit
> ci-dessus.

## Ce que fait `test_pwm_fan_thermal.c`

1. **Auto-test** (`PWM_FanThermal_SelfTest`) : verifie que le bus AXI-Lite
   repond correctement (motif alterne ecrit/relu sur un registre, verification
   que deux registres distincts ne sont pas aliases). Ne modifie pas l'etat
   du module (restaure les valeurs d'origine).
2. Configure le module en **mode manuel** (`AUTO_MODE=0`), programme la
   periode PWM, les bornes de duty et les seuils thermiques par defaut.
3. **Re-active** le module (`ENABLE=1`) -- note : au reset materiel,
   `CTRL=ENABLE=1/AUTO_MODE=0` et `DUTY=50%` par defaut cote VHDL (demarrage
   a mi-puissance sans intervention logicielle). Le test desactive
   volontairement le module en debut de sequence (etape 2) le temps de
   (re)programmer periode/bornes/seuils proprement, puis le reactive ici
   explicitement. Si le logiciel desactive le module (`ENABLE=0`) sans le
   reactiver, la sortie `fan_en_b` (active basse) reste forcee active en
   continu par conception (fail-safe pleine puissance).
4. Effectue une **rampe de rapport cyclique 0% -> 100% par pas de 10%**, en
   affichant a chaque palier le duty applique, la temperature on-chip lue via
   SYSMON, et le duty qu'aurait produit la loi de commande thermique (calcule
   en arriere-plan meme non applique en mode manuel) -- utile pour verifier
   que toute la chaine (bus AXI, PWM, SYSMON/DRP) est fonctionnelle sans avoir
   a activer `AUTO_MODE`.
5. Termine avec un rapport cyclique modere (50%) plutot que de laisser 100%
   actif indefiniment.

## Passer en mode asservi (optionnel)

Pour laisser la loi de commande thermique piloter le ventilateur au lieu du
registre `DUTY` manuel :

```c
PWM_FanThermal_SetThresholds(&FanInst, 4000, 7680); /* 40.00C / 76.80C */
PWM_FanThermal_SetDutyBounds(&FanInst, 10000, 90000);
PWM_FanThermal_SetAutoMode(&FanInst, 1);
PWM_FanThermal_Enable(&FanInst, 1);
```

`T_MAX` doit rester strictement superieur a `T_MIN`, et `DUTY_MAX >= DUTY_MIN`
(cf. note dans `pwm_fan_thermal_axi_v1_0.vhd`), sous peine de calcul
d'interpolation incoherent cote VHDL.

# Couche logicielle -- build_info_axi_v1_0

Driver baremetal pour l'IP AXI4-Lite en lecture seule `build_info_axi_v1_0`
(voir `src/build_info_axi_v1_0.vhd`) : 6 registres RO exposant une signature
fixe de detection, la date/heure de synthese, un numero de build, et la
version (majeur/mineur) du design -- toutes ces valeurs sont figees a
l'elaboration via generics VHDL (cf. `tcl/set_build_info.tcl`), pas de
logique runtime.

## Tracabilite du build (terminal / Vivado / cible)

Chaque script `tcl/package_ip_*.tcl` (les 4 IP du depot) tient desormais un
compteur de build persistant local (`tcl/build_counter.tcl`, fichiers dans
`tcl/.build_counters/`, non versionnes) : a chaque execution, le compteur du
composant concerne est incremente, affiche dans le terminal (`Build #N`), et
applique a la propriete Vivado `version` du composant packagee (visible dans
l'IP catalog / Customize IP / Report IP Status), sous la forme `1.N`.

Pour `build_info_axi_v1_0` specifiquement, ce numero est en plus destine a
finir dans le bitstream via le generic `G_BUILD_NUMBER` (registre
`BUILD_NUMBER`, cf. carte memoire ci-dessous) : `tcl/set_build_info.tcl`
relit par defaut ce meme compteur (sans l'incrementer) pour l'appliquer a
une instance du Block Design. Cela permet de verifier, sur votre poste, que
le bitstream charge sur la carte correspond bien au dernier packaging
effectue : le numero affiche par `package_ip_build_info.tcl`, la version
Vivado du composant, et `BuildInfo_GetBuildNumber()` lu depuis le logiciel
embarque devraient tous les trois coincider.

**Note** : ce compteur est local a votre poste de travail (comme
`ip_repo_*/`) -- il ne fournit pas un numero de build unique partage entre
plusieurs machines/checkouts, seulement une coherence verifiable en local.
A noter egalement que faire progresser la propriete `version` Vivado du
composant a chaque packaging peut declencher une invite "Upgrade IP" dans
Vivado pour les instances deja placees dans un Block Design -- c'est le prix
de cette tracabilite, attendu et sans consequence (acceptez la mise a jour).

## Prealable materiel

Comme `pwm_fan_thermal_axi_v1_0`, cette IP est packagee via un script
`tcl/package_ip_*.tcl` de ce depot (`tcl/package_ip_build_info.tcl`) :

1. `vivado -mode batch -source tcl/package_ip_build_info.tcl` (ou via
   `tcl/package_ip_all.tcl` qui package les 4 IP du depot en une fois) --
   affiche `Build #N` dans le terminal (cf. section tracabilite ci-dessus).
2. Ajouter le repertoire genere (`ip_repo_build_info` par defaut) au
   repository IP du projet Vivado, instancier `build_info_axi_v1_0` dans le
   Block Design (`s_axi_aclk`/`s_axi_aresetn` connectes).
3. **Important** : renseigner les generics `G_BUILD_DATE`/`G_BUILD_TIME`/
   `G_VERSION_MAJOR`/`G_VERSION_MINOR`/`G_BUILD_NUMBER` sur l'instance
   (valeur par defaut = 0 sinon) -- soit a la main dans l'onglet de
   personnalisation de l'IP, soit via `tcl/set_build_info.tcl` :
   ```tcl
   source tcl/set_build_info.tcl
   set_build_info build_info_axi_v1_0_0 1 0
   ```
   (`G_BUILD_NUMBER` est relu automatiquement depuis le compteur de
   packaging si vous ne le precisez pas en 4e argument.) Pour que
   `BUILD_DATE`/`BUILD_TIME` refletent automatiquement chaque build plutot
   qu'une valeur figee une fois pour toutes, appeler `set_build_info` depuis
   un hook Tcl pre-synthese (`STEPS.SYNTH_DESIGN.TCL.PRE` du run de
   synthese).
4. Export Hardware (`.xsa`, "Include bitstream").

## Integration dans un projet Vitis 2026.1

Meme flot que pour `pwm_fan_thermal` (Create Platform Component -> build BSP
-> Create Application Component), en copiant :
- `drivers/build_info/build_info.c` et `.h`
- `examples/test_build_info.c` (appeler `test_build_info()` depuis le
  `main()` de l'application -- ce fichier n'en contient pas)

Le nom de macro `BASEADDR` par defaut suppose dans `test_build_info.c`
(`XPAR_BUILD_INFO_AXI_V1_0_0_S_AXI_BASEADDR`) decoule du VLNV
`build_info_axi_v1_0` combine au nommage automatique Vivado de la premiere
instance (suffixe `_0`) -- a adapter si vous renommez l'instance ou en
instanciez plusieurs. Si la macro attendue est introuvable, la compilation
s'arrete avec une erreur explicite (`#error`) plutot que de se rabattre
silencieusement sur une adresse par defaut potentiellement fausse.

## Ce que fait `test_build_info.c`

1. **Detection** (`BuildInfo_SelfTest`) : verifie que le registre `MAGIC`
   contient bien la signature fixe `0x42494E46` ("BINF"). Tous les
   registres etant RO, c'est la seule verification pertinente (pas de motif
   ecriture/lecture possible).
2. Affiche la date de synthese (`YYYY-MM-DD`), l'heure de synthese
   (`HH:MM:SS`), le numero de build et la version (`major.minor`), decodees
   depuis le format BCD brut des registres `BUILD_DATE`/`BUILD_TIME` (cf.
   note dans `build_info.h`), ainsi que les valeurs brutes en hexadecimal.
   Le numero de build affiche est a comparer avec celui du terminal lors du
   packaging et avec la version Vivado du composant (cf. section
   tracabilite plus haut).
3. Avertit si toutes les valeurs lues sont a 0 (generics non renseignees
   avant synthese, cf. prealable materiel ci-dessus).

# Couche logicielle -- pwm_axi_lite_v1_0

Driver baremetal (Vitis, domaine "standalone") pour l'IP AXI4-Lite
`pwm_axi_lite_v1_0` (voir `src/pwm_axi_lite_v1_0.vhd`), generateur PWM
generique a 3 registres (PERIOD/THRESHOLD/CTRL). Le module est **actif par
defaut** (`CTRL.ENABLE=1` au reset materiel), avec un rapport cyclique par
defaut de **70%** (`PERIOD=50000`, `THRESHOLD=35000`, 2kHz a 100MHz) : la
generation PWM demarre sans aucune intervention logicielle.

**Polarite** : `pwm_out` est HAUT tant que le compteur est `< THRESHOLD`,
BAS ensuite (temps haut = `THRESHOLD`/`PERIOD`). Cette polarite a ete
INVERSEE par rapport a la premiere version de cette IP suite a un
asservissement observe inverse par rapport a l'attendu en test reel (cf.
note detaillee dans `src/pwm_axi_lite_v1_0.vhd`). Consequence sur le
fail-safe : `ENABLE=0` force desormais `pwm_out` **BAS** (et non plus haut)
pour representer la pleine puissance ventilateur.

## Prealable materiel

Cette IP est packagee via `tcl/package_ip_pwm_axi_lite.tcl` (ou via
`tcl/package_ip_all.tcl` qui package les 5 IP du depot en une fois) --
affiche `Build #N` dans le terminal (cf. section tracabilite dans la partie
`build_info_axi_v1_0` de ce document). Etapes cote materiel :

1. `vivado -mode batch -source tcl/package_ip_pwm_axi_lite.tcl`.
2. Ajouter le repertoire genere (`ip_repo_pwm_axi_lite` par defaut) au
   repository IP du projet Vivado, instancier `pwm_axi_lite_v1_0` dans le
   Block Design (`s_axi_aclk`/`s_axi_aresetn` connectes, `pwm_out` relie a
   la broche de sortie souhaitee).
3. Export Hardware (`.xsa`, "Include bitstream").

## Integration dans un projet Vitis 2026.1

Meme flot que pour `pwm_fan_thermal` (Create Platform Component -> build BSP
-> Create Application Component), en copiant :
- `drivers/pwm_axi_lite/pwm_axi_lite.c` et `.h`
- `examples/test_pwm_axi_lite.c` (appeler `test_pwm_axi_lite()` depuis le
  `main()` de l'application -- ce fichier n'en contient pas)

Le nom de macro `BASEADDR` par defaut suppose dans `test_pwm_axi_lite.c`
(`XPAR_PWM_AXI_LITE_V1_0_0_BASEADDR`, SANS `_S_AXI_` -- l'interface AXI-Lite
etant auto-inferee et unique sur cette IP, Vivado omet le nom d'interface
dans la macro) decoule du VLNV `pwm_axi_lite_v1_0` combine au nommage
automatique Vivado de la premiere instance (suffixe `_0`) -- a adapter si
vous renommez l'instance ou en instanciez plusieurs. Si la macro attendue
est introuvable, la compilation s'arrete avec une erreur explicite
(`#error`) plutot que de se rabattre silencieusement sur une adresse par
defaut potentiellement fausse.

## Ce que fait `test_pwm_axi_lite.c`

1. **Auto-test** (`PWM_AxiLite_SelfTest`) : motif alterne ecrit/relu sur
   `PERIOD`, puis verification que `PERIOD` et `THRESHOLD` sont bien deux
   registres distincts (pas d'aliasing d'adresse). Restaure les valeurs
   d'origine en fin de test.
2. Verifie que le module est **actif par defaut** (`PWM_AxiLite_IsEnabled`
   doit retourner vrai des la sortie de reset, sans ecriture logicielle) --
   reactive explicitement si ce n'est pas le cas (inattendu).
3. Configure `PERIOD` a 50000 coups d'horloge (2kHz a 100MHz, identique au
   defaut materiel).
4. Effectue une **rampe de temps haut 100% -> 0% par pas de 10%**
   (`PWM_AxiLite_SetHighPercent`), en reaffichant a chaque palier
   `PERIOD`/`THRESHOLD` relus et le nombre de coups d'horloge a l'etat haut,
   pour verifier que la conversion pourcentage <-> coups d'horloge est
   coherente.
5. Enchaine une sequence **arret (0%) -> pleine puissance (100%) ->
   asservissement (70%, defaut materiel)**, avec des pauses (`sleep`) pour
   observer chaque palier, plutot que de laisser 0% ou 100% actif
   indefiniment a la fin de la demo.

## A garder en tete

- Le module est **actif par defaut** (`CTRL.ENABLE=1` au reset materiel,
  70% de temps haut). `PWM_AxiLite_Enable(&Inst, 0)` desactive la
  generation PWM : `pwm_out` est alors force **BAS** (PAS haut -- fail-safe
  pleine puissance ventilateur avec cette polarite, pour ne jamais risquer
  une surchauffe silencieuse en cas de desactivation) et le compteur fige a
  0, pour un redemarrage propre a compter de 0 des la reactivation
  (`PWM_AxiLite_Enable(&Inst, 1)`).
- `THRESHOLD >= PERIOD` => `pwm_out` reste haut en permanence ; `THRESHOLD = 0`
  => `pwm_out` reste bas en permanence. Aucune verification materielle :
  `PWM_AxiLite_SetHighPercent` garantit `THRESHOLD <= PERIOD` par
  construction, mais un acces direct via `PWM_AxiLite_SetThreshold` doit
  respecter cette contrainte lui-meme.
- Changer `PERIOD`/`THRESHOLD` prend effet immediatement (pas de recopie en
  debut de periode materielle) : un changement en cours de periode peut
  produire une periode partielle ponctuelle le temps que le compteur
  reboucle.
