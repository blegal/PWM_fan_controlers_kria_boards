# Couche logicielle -- pwm_fan_thermal_axi_v1_0

Driver baremetal (Vitis, domaine "standalone") pour l'IP AXI4-Lite
`pwm_fan_thermal_axi_v1_0` (voir `src/pwm_fan_thermal_axi_v1_0.vhd`), avec un
exemple d'application demontrant le pilotage manuel du rapport cyclique.

```
sw/
  drivers/pwm_fan_thermal/
    pwm_fan_thermal.h   -- API + carte memoire des registres
    pwm_fan_thermal.c   -- implementation (Xil_In32/Xil_Out32)
  examples/
    test_pwm_fan_thermal.c  -- self-test + rampe manuelle 0-100%
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
   - `examples/test_pwm_fan_thermal.c` (remplace/complete le `main()` genere
     par le template)
5. Ouvrir `xparameters.h` genere (dans le platform component,
   `psu_cortexa53_0/standalone_domain/bsp/psu_cortexa53_0/include/` ou
   equivalent) et chercher l'entree `..._S_AXI_BASEADDR` correspondant a
   l'instance `pwm_fan_thermal_axi_v1_0` (le nom exact depend du nom donne a
   l'instance dans le Block Design, ex.
   `XPAR_PWM_FAN_THERMAL_AXI_V1_0_0_S_AXI_BASEADDR`). Adapter en tete de
   `test_pwm_fan_thermal.c` si le nom differe de celui suppose par defaut.
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
