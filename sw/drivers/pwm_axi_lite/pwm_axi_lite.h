/*-----------------------------------------------------------------------------
 * pwm_axi_lite.h
 *
 * Driver baremetal (Vitis standalone) pour l'IP AXI4-Lite
 * pwm_axi_lite_v1_0 (voir src/pwm_axi_lite_v1_0.vhd).
 *
 * Carte memoire (registres 32 bits, offsets par rapport a BaseAddress) :
 *
 *   0x00 PERIOD    nombre de coups d'horloge s_axi_aclk d'une periode PWM, RW
 *   0x04 THRESHOLD coup d'horloge a partir duquel pwm_out passe a l'etat
 *                  bas (doit rester <= PERIOD), RW
 *   0x08 CTRL      bit0 = ENABLE (1=actif, 0=inactif), RW
 *
 * Principe : le compteur materiel va de 0 a PERIOD-1 puis reboucle ;
 * pwm_out reste HAUT tant que le compteur est < THRESHOLD, puis passe bas
 * jusqu'a la fin de la periode. La duree haute vaut donc THRESHOLD coups
 * d'horloge (THRESHOLD/PERIOD = rapport cyclique) : AUGMENTER THRESHOLD
 * AUGMENTE le temps haut.
 *
 * NOTE POLARITE : cette polarite (HAUT en premier, avant THRESHOLD) est
 * l'inverse d'une premiere version de cette IP, suite a un asservissement
 * observe inverse par rapport a l'attendu en test reel -- cf. note dans
 * pwm_axi_lite_v1_0.vhd.
 *
 * IMPORTANT :
 *  - Au reset materiel, CTRL.ENABLE=1 (module ACTIF PAR DEFAUT, sans
 *    attendre d'ecriture logicielle), PERIOD=50000 et THRESHOLD=35000 :
 *    2kHz a 100MHz d'horloge s_axi_aclk, 70% de temps haut (a adapter au
 *    calcul de frequence si s_axi_aclk differe de 100MHz).
 *  - ENABLE=0 : pwm_out force BAS (PAS haut) et compteur fige a 0. Choix
 *    fail-safe deliberee pour piloter un ventilateur : desactiver le module
 *    met la sortie en pleine puissance plutot que de couper le ventilateur,
 *    pour ne jamais risquer une surchauffe silencieuse (avec cette polarite,
 *    BAS = pleine puissance, cf. note polarite ci-dessus). La generation PWM
 *    redemarre proprement a compter de 0 des le retour a ENABLE=1.
 *  - THRESHOLD >= PERIOD => pwm_out reste haut en permanence. THRESHOLD = 0
 *    => pwm_out reste bas en permanence. Aucune verification materielle :
 *    a la charge du logiciel (cf. PWM_AxiLite_SetThresholdPercent ci-dessous
 *    qui garantit Threshold <= Period par construction).
 *  - Changer PERIOD/THRESHOLD prend effet immediatement (pas de recopie en
 *    debut de periode).
 *---------------------------------------------------------------------------*/

#ifndef PWM_AXI_LITE_H
#define PWM_AXI_LITE_H

#ifdef __cplusplus
extern "C" {
#endif

#include "xil_types.h"
#include "xil_io.h"
#include "xstatus.h"

/* ------------------------------------------------------------------------ */
/* Offsets registres                                                        */
/* ------------------------------------------------------------------------ */
#define PWM_AXI_LITE_PERIOD_OFFSET    0x00U
#define PWM_AXI_LITE_THRESHOLD_OFFSET 0x04U
#define PWM_AXI_LITE_CTRL_OFFSET      0x08U

/* ------------------------------------------------------------------------ */
/* Champs de bits registre CTRL                                             */
/* ------------------------------------------------------------------------ */
#define PWM_AXI_LITE_CTRL_ENABLE_MASK 0x00000001U

/* ------------------------------------------------------------------------ */
/* Instance                                                                  */
/* ------------------------------------------------------------------------ */
typedef struct {
    UINTPTR BaseAddress;   /* Adresse de base S_AXI (depuis xparameters.h) */
    u32     IsReady;       /* XIL_COMPONENT_IS_READY apres Init */
} PWM_AxiLite;

/* ------------------------------------------------------------------------ */
/* API                                                                       */
/* ------------------------------------------------------------------------ */

/* Associe l'instance a une adresse de base. Ne touche a aucun registre. */
int PWM_AxiLite_Init(PWM_AxiLite *InstancePtr, UINTPTR BaseAddress);

/*
 * Active/desactive le module (CTRL.ENABLE). Actif par defaut au reset
 * materiel (pas d'appel necessaire pour un fonctionnement immediat).
 * IMPORTANT : Enable(FALSE) met pwm_out a l'etat BAS en permanence
 * (fail-safe pleine puissance ventilateur avec cette polarite), PAS a
 * l'etat haut -- ce n'est donc pas une mise a l'arret, cf. note polarite
 * en tete de fichier.
 */
void PWM_AxiLite_Enable(PWM_AxiLite *InstancePtr, u8 Enable);

/* Lecture de l'etat actif/inactif courant (CTRL.ENABLE). */
u8 PWM_AxiLite_IsEnabled(PWM_AxiLite *InstancePtr);

/* Periode PWM, en coups d'horloge s_axi_aclk. */
void PWM_AxiLite_SetPeriod(PWM_AxiLite *InstancePtr, u32 PeriodCycles);
u32  PWM_AxiLite_GetPeriod(PWM_AxiLite *InstancePtr);

/* Seuil de front descendant, en coups d'horloge (doit rester <= periode). */
void PWM_AxiLite_SetThreshold(PWM_AxiLite *InstancePtr, u32 ThresholdCycles);
u32  PWM_AxiLite_GetThreshold(PWM_AxiLite *InstancePtr);

/*
 * Consigne de temps haut en pourcentage entier (0-100), convertie en
 * THRESHOLD = PERIOD * Percent / 100 a partir de la periode actuellement
 * programmee (registre PERIOD relu a chaque appel, pas de valeur mise en
 * cache) -- garantit THRESHOLD <= PERIOD par construction.
 * Retourne XST_INVALID_PARAM si Percent > 100, XST_SUCCESS sinon.
 */
int PWM_AxiLite_SetHighPercent(PWM_AxiLite *InstancePtr, u32 Percent);

/*
 * Auto-test non destructif : motif alterne ecrit/relu sur PERIOD et sur
 * THRESHOLD (registres RW), valeurs d'origine restaurees en fin de test,
 * puis verification que les deux registres sont bien distincts (pas
 * d'aliasing d'adresse). Ne modifie pas l'etat du module au-dela du temps
 * du test (restaure PERIOD/THRESHOLD a leurs valeurs d'avant l'appel).
 * Retourne XST_SUCCESS ou XST_FAILURE.
 */
int PWM_AxiLite_SelfTest(PWM_AxiLite *InstancePtr);

#ifdef __cplusplus
}
#endif

#endif /* PWM_AXI_LITE_H */
