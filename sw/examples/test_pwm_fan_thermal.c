/*-----------------------------------------------------------------------------
 * test_pwm_fan_thermal.c
 *
 * Application baremetal (Vitis 2026.1, domaine "standalone") de test/demo
 * pour l'IP pwm_fan_thermal_axi_v1_0 :
 *
 *   1. Auto-test du driver (acces bus AXI, decodage d'adresse des registres)
 *   2. Mise en mode manuel (AUTO_MODE=0) et activation (ENABLE=1)
 *   3. Rampe de rapport cyclique 0% -> 100% par pas de 10%, avec lecture de
 *      la temperature on-chip et du duty auto (calcule en arriere-plan meme
 *      si non applique) a chaque palier, pour verifier que toute la chaine
 *      (bus AXI, PWM, SYSMON) fonctionne.
 *
 * A ajouter au projet application Vitis avec pwm_fan_thermal.c/.h (dossier
 * sw/drivers/pwm_fan_thermal/). Voir sw/README.md pour l'integration.
 *---------------------------------------------------------------------------*/

#include "xparameters.h"
#include "xil_printf.h"
#include "xstatus.h"
#include "sleep.h"

#include "pwm_fan_thermal.h"

/*
 * Adresse de base de l'IP, generee dans xparameters.h a partir du nom de
 * l'instance donnee dans le Block Design Vivado (Regenerate Output Products
 * + Export Hardware + Vitis "Update Hardware" doivent avoir ete faits au
 * prealable). Adaptez le nom de macro ci-dessous a celui reellement genere
 * chez vous (visible dans xparameters.h, rechercher "PWM_FAN_THERMAL").
 */
#ifndef PWM_FAN_THERMAL_BASEADDR
  #ifdef XPAR_PWM_FAN_THERMAL_AXI_V1_0_0_S_AXI_BASEADDR
    #define PWM_FAN_THERMAL_BASEADDR XPAR_PWM_FAN_THERMAL_AXI_V1_0_0_S_AXI_BASEADDR
  #else
    #warning "XPAR_PWM_FAN_THERMAL_AXI_V1_0_0_S_AXI_BASEADDR introuvable : adaptez le nom de macro (cf. xparameters.h) ou definissez PWM_FAN_THERMAL_BASEADDR manuellement."
    #define PWM_FAN_THERMAL_BASEADDR 0x80000000U
  #endif
#endif

/* Periode PWM utilisee pour la demo (coups d'horloge s_axi_aclk). */
#define DEMO_PERIOD_CYCLES 100000U

static PWM_FanThermal FanInst;

static void PrintStatusLine(u32 PercentRequested)
{
    s16 TempCentideg   = PWM_FanThermal_GetTempCentideg(&FanInst);
    u32 DutyRaw        = PWM_FanThermal_GetDutyRaw(&FanInst);
    u32 DutyAutoRaw    = PWM_FanThermal_GetDutyAuto(&FanInst);
    u8  TempValid      = PWM_FanThermal_IsTempValid(&FanInst);

    xil_printf("  duty=%3lu%% (raw=%6lu)  temp=%d.%02dC  duty_auto_raw=%6lu  temp_valid_sticky=%d\r\n",
               (unsigned long)PercentRequested,
               (unsigned long)DutyRaw,
               TempCentideg / 100, (TempCentideg < 0 ? -TempCentideg : TempCentideg) % 100,
               (unsigned long)DutyAutoRaw,
               TempValid);
}

int main(void)
{
    int Status;
    u32 Percent;

    xil_printf("\r\n--- Test pwm_fan_thermal_axi_v1_0 --------------------\r\n");
    xil_printf("BaseAddress = 0x%08lX\r\n", (unsigned long)PWM_FAN_THERMAL_BASEADDR);

    Status = PWM_FanThermal_Init(&FanInst, PWM_FAN_THERMAL_BASEADDR);
    if (Status != XST_SUCCESS) {
        xil_printf("ERREUR : PWM_FanThermal_Init a echoue\r\n");
        return XST_FAILURE;
    }

    /* -------------------------------------------------------------- */
    /* 1) Auto-test bus/registres                                     */
    /* -------------------------------------------------------------- */
    xil_printf("Auto-test registres... ");
    Status = PWM_FanThermal_SelfTest(&FanInst);
    if (Status != XST_SUCCESS) {
        xil_printf("ECHEC\r\n");
        xil_printf("-> verifier BaseAddress, mapping memoire (MMU/cache si applicable),\r\n");
        xil_printf("   et que l'IP est bien instanciee/connectee dans le Block Design.\r\n");
        return XST_FAILURE;
    }
    xil_printf("OK\r\n");

    /* -------------------------------------------------------------- */
    /* 2) Configuration : mode manuel, bornes/seuils par defaut, coupe */
    /*    le module le temps de tout configurer proprement.           */
    /* -------------------------------------------------------------- */
    PWM_FanThermal_Enable(&FanInst, 0);
    PWM_FanThermal_SetAutoMode(&FanInst, 0);
    PWM_FanThermal_SetPeriod(&FanInst, DEMO_PERIOD_CYCLES);
    PWM_FanThermal_SetDutyBounds(&FanInst, 0U, DEMO_PERIOD_CYCLES);
    PWM_FanThermal_SetThresholds(&FanInst, 4000, 7680); /* 40.00C / 76.80C, cf. defaut VHDL */
    PWM_FanThermal_SetDutyRaw(&FanInst, 0U);

    xil_printf("Periode PWM relue = %lu cycles\r\n",
               (unsigned long)PWM_FanThermal_GetPeriod(&FanInst));

    /* Re-active le module (desactive plus haut le temps de reprogrammer
     * periode/bornes/seuils). Note : au reset materiel, CTRL demarre deja
     * a ENABLE=1 (duty 50% par defaut) ; ce n'est qu'apres un ENABLE=0
     * explicite sans reactivation que fan_en_b resterait force actif en
     * continu (fail-safe pleine puissance). */
    PWM_FanThermal_Enable(&FanInst, 1);

    /* -------------------------------------------------------------- */
    /* 3) Rampe manuelle 0% -> 100% par pas de 10%                    */
    /* -------------------------------------------------------------- */
    xil_printf("Rampe manuelle de rapport cyclique :\r\n");
    for (Percent = 0U; Percent <= 100U; Percent += 10U) {
        Status = PWM_FanThermal_SetDutyPercent(&FanInst, Percent);
        if (Status != XST_SUCCESS) {
            xil_printf("ERREUR : SetDutyPercent(%lu) invalide\r\n", (unsigned long)Percent);
            continue;
        }

        usleep(500000); /* laisse le temps d'observer/mesurer une periode stable */
        PrintStatusLine(Percent);
    }

    /* Redescend a un rapport cyclique modere plutot que de laisser 100%
     * actif indefiniment a la fin de la demo. */
    PWM_FanThermal_SetDutyPercent(&FanInst, 50U);

    xil_printf("Test termine : module actif, mode manuel, duty=50%%.\r\n");
    xil_printf("-------------------------------------------------------\r\n");

    return XST_SUCCESS;
}
