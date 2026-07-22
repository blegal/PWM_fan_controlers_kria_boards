# Couche logicielle -- pwm_fan_thermal_axi_v1_0 et vec_copy_and_inc

Applications baremetal (Vitis, domaine "standalone") pour :
- l'IP AXI4-Lite `pwm_fan_thermal_axi_v1_0` (voir
  `src/pwm_fan_thermal_axi_v1_0.vhd`), avec un driver ecrit a la main
  (`drivers/pwm_fan_thermal/`) et un exemple d'application demontrant le
  pilotage manuel du rapport cyclique ;
- l'accelerateur Vitis HLS `vec_copy_and_inc` (m_axi + s_axilite), avec un
  exemple de detection/config/test et de benchmark latence/debit
  (`examples/test_vec_copy_and_inc.c`).

```
sw/
  drivers/pwm_fan_thermal/
    pwm_fan_thermal.h   -- API + carte memoire des registres
    pwm_fan_thermal.c   -- implementation (Xil_In32/Xil_Out32)
  examples/
    test_pwm_fan_thermal.c    -- self-test + rampe manuelle 0-100%
    test_vec_copy_and_inc.c   -- self-test + test fonctionnel + benchmark latence/debit vs N
```

Contrairement a `pwm_fan_thermal`, `vec_copy_and_inc` n'a **pas** de driver
ecrit a la main dans ce depot : Vitis HLS genere lui-meme un driver complet
(`xvec_copy_and_inc.h`/`.c`, eventuellement `xvec_copy_and_inc_hw.h`) lors de
l'**Export RTL**, avec l'API standard `XVec_copy_and_inc_*`. Il suffit de
copier ces fichiers generes (typiquement dans
`<export>/drivers/vec_copy_and_inc_v1_0/src/`) dans les sources de
l'application, a cote de `test_vec_copy_and_inc.c` qui les consomme.

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
   - `examples/test_pwm_fan_thermal.c` (remplace/complete le `main()` genere
     par le template)
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
   equivalent).
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

# Couche logicielle -- vec_copy_and_inc (accelerateur Vitis HLS)

Application de detection/config/test/benchmark pour l'accelerateur HLS
suivant (m_axi bundle `BUS_A` pour `src`/`dst`, s_axilite pour
`size`/`return`) :

```c
void vec_copy_and_inc(const unsigned int *src, unsigned int *dst, int size);
```

`test_vec_copy_and_inc.c` n'utilise QUE l'API standard generee par Vitis HLS
(`XVec_copy_and_inc_Initialize`, `_Start`, `_IsDone`, `_IsIdle`,
`Set_src`/`Get_src`, `Set_dst`/`Get_dst`, `Set_size`/`Get_size`) : aucun
driver ecrit a la main dans ce depot, aucune hypothese sur la carte memoire
des registres.

## Prealable materiel

Contrairement a `pwm_fan_thermal_axi_v1_0`, cette IP n'est pas packagee par un
script `tcl/package_ip_*.tcl` de ce depot : elle provient d'un projet **Vitis
HLS** distinct. Etapes cote materiel :

1. Dans Vitis HLS : C Synthesis, puis **Export RTL** (format "IP Catalog").
   Ceci genere automatiquement un repertoire `drivers/vec_copy_and_inc_v1_0/`
   (API + carte memoire des registres, fichiers `xvec_copy_and_inc.*`).
2. Ajouter le repertoire d'IP exporte au repository IP du projet Vivado, puis
   instancier `vec_copy_and_inc` dans le Block Design, avec son interface
   `s_axi_control` connectee a une horloge/reset et son port maitre `m_axi_BUS_A`
   relie a un interconnect AXI vers la DDR (memoire accessible en ecriture par
   le PS ET l'accelerateur).
3. Export Hardware (`.xsa`, "Include bitstream").

## Integration dans un projet Vitis 2026.1

Meme flot que pour `pwm_fan_thermal` (Create Platform Component -> build BSP
-> Create Application Component), en copiant cette fois :
- les fichiers du driver **generes par Vitis HLS** (`xvec_copy_and_inc.h`,
  `xvec_copy_and_inc.c`, et selon la version `xvec_copy_and_inc_hw.h`),
  recuperes dans `<export RTL>/drivers/vec_copy_and_inc_v1_0/src/`
- `examples/test_vec_copy_and_inc.c` (contient son propre `main()`)

Comme cette IP est exportee via le flot standard Vitis HLS (contrairement au
packaging manuel de `pwm_fan_thermal_axi_v1_0`), elle inclut un repertoire
`drivers/` reconnu par Vitis lors de la generation du platform component :
`XVec_copy_and_inc_Initialize()` fonctionne directement, soit par `DEVICE_ID`
(flot classique -- macro `XPAR_VEC_COPY_AND_INC_0_DEVICE_ID`), soit par
`BaseAddress` (flot SDT -- macro `XPAR_XVEC_COPY_AND_INC_0_BASEADDR`).
`test_vec_copy_and_inc.c` gere les deux via `#ifdef SDT`, avec une valeur de
repli (et un `#warning`) si la macro attendue n'est pas trouvee dans
`xparameters.h` -- a adapter si vous renommez l'instance dans le Block
Design, ou en instanciez plusieurs (suffixe `_1`, `_2`, ...).

## Ce que fait `test_vec_copy_and_inc.c`

1. **Detection** (`XVec_copy_and_inc_Initialize` + auto-test local) : motif
   alterne ecrit/relu sur le registre `size` (RW via l'API standard, sans
   effet tant qu'aucun calcul n'est lance), puis verification que l'IP est
   au repos (`XVec_copy_and_inc_IsIdle`).
2. **Test fonctionnel** : un calcul de taille 64, verification
   `dst[i] == src[i] + 100` et rapport du nombre d'erreurs.
3. **Benchmark** : pour `N` de 16 a 1024 (pas de 16), moyenne sur 50
   repetitions de la latence (registre-a-registre, gestion de cache incluse
   via `Xil_DCacheFlushRange`/`Xil_DCacheInvalidateRange`) et du debit utile
   (2*N*4 octets lus+ecrits par appel).

## Limites / a garder en tete

- `MAX_BUFFER` cote HLS vaut 1024 : non expose par le driver genere, defini
  localement dans `test_vec_copy_and_inc.c` (`VEC_COPY_AND_INC_MAX_SIZE`) --
  a garder synchronise a la main si vous changez `MAX_BUFFER` cote HLS.
  `size` (donc `N` dans le benchmark) doit rester `<= 1024`.
- Pas de double-buffering interne a l'IP : ne pas relancer un calcul avant
  `ap_done` du precedent (la fonction statique `RunOnce`/`WaitDone` du fichier
  de test s'en chargent).
- Les buffers `src`/`dst` sont dans la DDR, non coherents avec le cache D du
  CPU vis-a-vis du port maitre AXI de l'accelerateur (pas d'ACP) : d'ou les
  appels `Xil_DCacheFlushRange`/`Xil_DCacheInvalidateRange` autour de chaque
  calcul dans l'exemple.
