/*-----------------------------------------------------------------------------
 * pwm_fan_thermal.h
 *
 * Driver baremetal (Vitis standalone) pour l'IP AXI4-Lite
 * pwm_fan_thermal_axi_v1_0 (voir src/pwm_fan_thermal_axi_v1_0.vhd).
 *
 * Carte memoire (registres 32 bits, offsets par rapport a BaseAddress) :
 *
 *   0x00 CTRL       bit0=ENABLE, bit1=AUTO_MODE (1=asservi, 0=manuel)
 *   0x04 PERIOD     periode PWM, en coups d'horloge s_axi_aclk
 *   0x08 DUTY       consigne duty manuelle (coups d'horloge), utilisee si
 *                   AUTO_MODE=0, RW
 *   0x0C DUTY_AUTO  duty calcule par la loi de commande thermique, RO
 *   0x10 TEMP_RAW   temperature en centidegres C, signee (sign-extend), RO
 *   0x14 T_THRESH   [15:0]=T_MIN, [31:16]=T_MAX (centidegres C, signes)
 *   0x18 DUTY_MIN   borne basse de duty (coups d'horloge), RW
 *   0x1C DUTY_MAX   borne haute de duty (coups d'horloge), RW
 *   0x20 STATUS     bit0 = temp_valid (sticky jusqu'a lecture), RO
 *
 * IMPORTANT :
 *  - Au reset materiel, CTRL=0x1 (ENABLE=1, AUTO_MODE=0) et DUTY=50000 pour
 *    PERIOD=100000 : le module pilote donc fan_en_b a 50% de rapport
 *    cyclique des la sortie de reset, sans attendre d'ecriture logicielle
 *    (repos raisonnable quand rien ne pilote encore l'asservissement). Si
 *    le logiciel ecrit CTRL avec ENABLE=0 (desactivation explicite), la
 *    sortie fan_en_b (active basse) est forcee active en continu
 *    (fail-safe pleine puissance) jusqu'a un nouvel appel a
 *    PWM_FanThermal_Enable(&inst, TRUE).
 *  - En mode manuel (AUTO_MODE=0), c'est le registre DUTY qui pilote le
 *    rapport cyclique ; DUTY_AUTO continue d'etre calcule en arriere-plan
 *    (a partir de la temperature) mais n'est pas applique tant que
 *    AUTO_MODE=0.
 *  - Avant de passer en AUTO_MODE=1 : s'assurer DUTY_MAX >= DUTY_MIN et
 *    T_MAX > T_MIN (sinon interpolation incoherente cote VHDL).
 *---------------------------------------------------------------------------*/

#ifndef PWM_FAN_THERMAL_H
#define PWM_FAN_THERMAL_H

#ifdef __cplusplus
extern "C" {
#endif

#include "xil_types.h"
#include "xil_io.h"
#include "xstatus.h"

/* ------------------------------------------------------------------------ */
/* Offsets registres                                                        */
/* ------------------------------------------------------------------------ */
#define PWM_FAN_THERMAL_CTRL_OFFSET      0x00U
#define PWM_FAN_THERMAL_PERIOD_OFFSET    0x04U
#define PWM_FAN_THERMAL_DUTY_OFFSET      0x08U
#define PWM_FAN_THERMAL_DUTY_AUTO_OFFSET 0x0CU
#define PWM_FAN_THERMAL_TEMP_RAW_OFFSET  0x10U
#define PWM_FAN_THERMAL_T_THRESH_OFFSET  0x14U
#define PWM_FAN_THERMAL_DUTY_MIN_OFFSET  0x18U
#define PWM_FAN_THERMAL_DUTY_MAX_OFFSET  0x1CU
#define PWM_FAN_THERMAL_STATUS_OFFSET    0x20U

/* ------------------------------------------------------------------------ */
/* Champs de bits                                                           */
/* ------------------------------------------------------------------------ */
#define PWM_FAN_THERMAL_CTRL_ENABLE_MASK    0x00000001U
#define PWM_FAN_THERMAL_CTRL_AUTO_MODE_MASK 0x00000002U

#define PWM_FAN_THERMAL_STATUS_TEMP_VALID_MASK 0x00000001U

#define PWM_FAN_THERMAL_T_THRESH_TMIN_MASK  0x0000FFFFU
#define PWM_FAN_THERMAL_T_THRESH_TMAX_SHIFT 16U

/* ------------------------------------------------------------------------ */
/* Instance                                                                  */
/* ------------------------------------------------------------------------ */
typedef struct {
    UINTPTR BaseAddress;   /* Adresse de base S_AXI (depuis xparameters.h) */
    u32     IsReady;       /* XIL_COMPONENT_IS_READY apres Init */
} PWM_FanThermal;

/* ------------------------------------------------------------------------ */
/* API                                                                       */
/* ------------------------------------------------------------------------ */

/* Associe l'instance a une adresse de base. Ne touche a aucun registre. */
int PWM_FanThermal_Init(PWM_FanThermal *InstancePtr, UINTPTR BaseAddress);

/* Active/desactive le module (CTRL.ENABLE). Cf. note fail-safe ci-dessus. */
void PWM_FanThermal_Enable(PWM_FanThermal *InstancePtr, u8 Enable);

/* Bascule entre pilotage manuel (DUTY) et asservi (DUTY_AUTO). */
void PWM_FanThermal_SetAutoMode(PWM_FanThermal *InstancePtr, u8 AutoMode);

/* Lecture brute du registre CTRL. */
u32 PWM_FanThermal_GetCtrl(PWM_FanThermal *InstancePtr);

/* Periode PWM, en coups d'horloge s_axi_aclk. */
void PWM_FanThermal_SetPeriod(PWM_FanThermal *InstancePtr, u32 PeriodCycles);
u32  PWM_FanThermal_GetPeriod(PWM_FanThermal *InstancePtr);

/* Consigne manuelle de duty, en coups d'horloge (doit rester <= periode). */
void PWM_FanThermal_SetDutyRaw(PWM_FanThermal *InstancePtr, u32 DutyCycles);
u32  PWM_FanThermal_GetDutyRaw(PWM_FanThermal *InstancePtr);

/*
 * Consigne manuelle de duty en pourcentage entier (0-100), convertie en
 * coups d'horloge a partir de la periode actuellement programmee (registre
 * PERIOD relu a chaque appel, pas de valeur mise en cache).
 * Retourne XST_INVALID_PARAM si Percent > 100, XST_SUCCESS sinon.
 */
int PWM_FanThermal_SetDutyPercent(PWM_FanThermal *InstancePtr, u32 Percent);

/* Duty calcule par la loi de commande thermique (RO, coups d'horloge). */
u32 PWM_FanThermal_GetDutyAuto(PWM_FanThermal *InstancePtr);

/* Temperature on-chip courante, en centidegres Celsius (ex: 4523 = 45.23C). */
s16 PWM_FanThermal_GetTempCentideg(PWM_FanThermal *InstancePtr);

/* Seuils de la loi de commande thermique (centidegres C, signes). */
void PWM_FanThermal_SetThresholds(PWM_FanThermal *InstancePtr, s16 TMinCentideg, s16 TMaxCentideg);
void PWM_FanThermal_GetThresholds(PWM_FanThermal *InstancePtr, s16 *TMinCentideg, s16 *TMaxCentideg);

/* Bornes de duty (coups d'horloge) utilisees par la loi de commande. */
void PWM_FanThermal_SetDutyBounds(PWM_FanThermal *InstancePtr, u32 DutyMin, u32 DutyMax);
void PWM_FanThermal_GetDutyBounds(PWM_FanThermal *InstancePtr, u32 *DutyMin, u32 *DutyMax);

/*
 * Indique si une nouvelle mesure de temperature a ete produite depuis la
 * derniere lecture de ce registre (sticky, remis a zero par la lecture
 * materielle elle-meme -- cf. STATUS bit0 dans le VHDL).
 */
u8 PWM_FanThermal_IsTempValid(PWM_FanThermal *InstancePtr);

/*
 * Auto-test non destructif : verifie l'acces au bus (motif alterne ecrit
 * puis relu sur un registre RW sans impact fonctionnel : DUTY_MIN, dont la
 * valeur d'origine est restauree en fin de test), puis verifie que le
 * chemin de lecture AXI distingue bien deux registres differents (DUTY_MIN
 * vs DUTY_MAX). Ne modifie pas CTRL : le module reste dans l'etat ou il se
 * trouvait avant l'appel.
 *
 * Retourne XST_SUCCESS ou XST_FAILURE.
 */
int PWM_FanThermal_SelfTest(PWM_FanThermal *InstancePtr);

#ifdef __cplusplus
}
#endif

#endif /* PWM_FAN_THERMAL_H */
