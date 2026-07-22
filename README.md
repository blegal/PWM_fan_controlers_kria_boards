# kv260_pwm_fan_thermal

Controleur PWM du ventilateur de la Kria KV260 (Zynq UltraScale+), avec
acquisition de la temperature on-chip via le bloc SYSMON du PL et
asservissement (interpolation lineaire duty <-> temperature).

Deux variantes fournies :

- **`pwm_fan_thermal_axi_v1_0`** : IP AXI4-Lite complete (registres CTRL,
  PERIOD, DUTY manuel/auto, TEMP_RAW, seuils, bornes de duty), pilotable
  depuis le PS.
- **`pwm_fan_thermal_standalone`** : IP autonome, aucune interface AXI, seul
  le port `clk` doit etre connecte. Tous les parametres (periode, seuils,
  bornes de duty) sont des generiques VHDL exposes automatiquement comme
  parametres de personnalisation dans le Block Design Vivado.

Les deux variantes partagent les memes blocs d'acquisition et de commande :

```
src/
  sysmon_temp_acq.vhd          -- instancie SYSMONE4, lit la temperature via DRP
  fan_thermal_ctrl.vhd         -- loi de commande duty <-> temperature
  pwm_fan_thermal_axi_v1_0.vhd -- top-level AXI4-Lite
  pwm_fan_thermal_standalone.vhd -- top-level autonome (horloge seule)
```

## Points a verifier avant synthese reelle

1. **Constantes de conversion temperature** (`SCALE_NUM`/`SCALE_DEN`/
   `OFFSET_CENTIDEG` dans `sysmon_temp_acq.vhd`) : basees sur la formule
   UG580 couramment citee pour SYSMONE4, mais cette equation a ete revisee
   plusieurs fois entre versions du guide. A recaler sur la revision exacte
   livree avec votre Vivado.
2. **Ports/generiques exacts de `SYSMONE4`** : le template utilise est
   standard mais doit etre confirme via *Vivado -> Language Templates ->
   Xilinx Primitive Instantiation -> SYSMONE4* pour votre version d'outil.
3. **Frequence de `DCLK`** (le port horloge de `sysmon_temp_acq`, alimente
   par la meme horloge que le reste du design) : le DRP du SYSMON a une
   frequence max a respecter (cf. UG580). Deriver une horloge plus lente si
   necessaire.
4. **Part number KV260** : la carte embarque un `XCK26-SFVC784-2LV-C` (SOM
   Kria K26), pas un XCZU5EV generique. Les scripts de packaging utilisent
   cette partie par defaut ; adaptez si votre projet utilise un board file
   different.
5. Pour l'IP AXI, avant de passer en `AUTO_MODE=1` : le logiciel doit
   garantir `DUTY_MAX >= DUTY_MIN` et `T_MAX > T_MIN`.

## Generer les IP avec Vivado

Chaque script Tcl cree un projet Vivado temporaire, y ajoute les sources,
package l'IP, puis nettoie. Le projet temporaire de build (`_pkg_build_*`)
peut etre supprime apres coup ; seul le repertoire `ip_repo_*` genere est a
conserver et versionner (ou non, selon votre convention -- voir
`.gitignore`).

### Les 2 IP en une seule commande

```bash
cd kv260_pwm_fan_thermal
vivado -mode batch -source tcl/package_ip_all.tcl \
    -tclargs xck26-sfvc784-2LV-c ./ip_repo_axi ./ip_repo_standalone
```

`package_ip_all.tcl` reutilise tel quel `package_ip_axi.tcl` et
`package_ip_standalone.tcl` ci-dessous (pas de logique dupliquee) ; une
erreur sur l'une des 2 IP n'empeche pas la tentative de packaging de
l'autre.

### IP AXI4-Lite seule

```bash
cd kv260_pwm_fan_thermal
vivado -mode batch -source tcl/package_ip_axi.tcl -tclargs xck26-sfvc784-2LV-c ./ip_repo_axi
```

### IP standalone seule (horloge seule)

```bash
cd kv260_pwm_fan_thermal
vivado -mode batch -source tcl/package_ip_standalone.tcl -tclargs xck26-sfvc784-2LV-c ./ip_repo_standalone
```

### Ajouter le repository IP genere a un projet existant

Dans le Tcl Console de Vivado (ou un script d'ouverture de projet) :

```tcl
set_property ip_repo_paths {/chemin/absolu/vers/ip_repo_axi} [current_project]
update_ip_catalog
```

L'IP apparait alors dans le catalogue IP (categorie `UserIP`), utilisable
normalement dans IP Integrator (glisser-deposer dans le Block Design).

## Note sur l'inference AXI4-Lite automatique

Le script `package_ip_axi.tcl` tente d'inferer automatiquement l'interface
AXI4-Lite via `ipx::infer_bus_interface`, a partir du nommage standard des
ports (`s_axi_*`). Si l'onglet **Interfaces** de l'IP packagee ne montre pas
correctement `S_AXI` apres generation (cela peut varier selon la version de
Vivado), ouvrez l'IP une fois via l'assistant graphique (*Tools -> Create
and Package New IP -> Package a specification*, en pointant vers le
`repo_dir` genere), finalisez l'onglet Interfaces manuellement (Vivado
detecte tres bien le nommage `s_axi_*` dans ce flux), puis re-sauvegardez.
Le Tcl Console affichera alors les commandes exactes executees : il suffit
de les reporter dans le script pour le rendre reproductible sur votre
version d'outil.
