/*-----------------------------------------------------------------------------
 * test_pwm_axi_lite.c
 *
 * Application baremetal (Vitis, domaine "standalone") de test/demo pour
 * l'IP pwm_axi_lite_v1_0 :
 *
 *   1. Auto-test du driver (acces bus AXI, decodage d'adresse des registres)
 *   2. Verification que le module est actif par defaut (CTRL.ENABLE=1 des
 *      la sortie de reset, sans intervention logicielle)
 *   3. Configuration d'une periode de demo (2kHz a 100MHz d'horloge s_axi_aclk)
 *   4. Rampe de temps haut 100% -> 0% par pas de 10%, puis sequence
 *      arret/pleine puissance/asservissement (70%, defaut materiel).
 *
 * NOTE POLARITE : pwm_out est HAUT tant que counter < THRESHOLD (polarite
 * inversee par rapport a une premiere version de cette IP, suite a un
 * asservissement observe inverse en test reel) -- cf. note dans
 * pwm_axi_lite_v1_0.vhd / pwm_axi_lite.h.
 *
 * A ajouter au projet application Vitis avec pwm_axi_lite.c/.h (dossier
 * sw/drivers/pwm_axi_lite/).
 *
 * N'est PAS un point d'entree (pas de main()) : appeler test_pwm_axi_lite()
 * depuis le main() de l'application (qui peut enchainer plusieurs tests).
 *---------------------------------------------------------------------------*/

#include "xparameters.h"
#include "xil_printf.h"
#include "xstatus.h"
#include "sleep.h"

#include "pwm_axi_lite.h"

/*
 * Adresse de base de l'IP, generee dans xparameters.h (Regenerate Output
 * Products + Export Hardware + Vitis "Update Hardware" doivent avoir ete
 * faits au prealable).
 *
 * Le nom de macro par defaut ci-dessous decoule directement de
 * tcl/package_ip_pwm_axi_lite.tcl : VLNV name = "pwm_axi_lite_v1_0", bus
 * interface auto-inferee sous le nom "S_AXI". Avec le nommage automatique
 * Vivado pour la PREMIERE instance deposee dans le Block Design (suffixe
 * "_0"), le nom genere est deterministe :
 *   XPAR_PWM_AXI_LITE_V1_0_0_BASEADDR
 *
 * A adapter uniquement si vous renommez l'instance dans le Block Design, ou
 * si vous en instanciez plusieurs (suffixe "_1", "_2", ... pour les
 * suivantes).
 */
#ifdef XPAR_PWM_AXI_LITE_V1_0_0_BASEADDR
	#define PWM_AXI_LITE_BASEADDR XPAR_PWM_AXI_LITE_V1_0_0_BASEADDR
#else
	#error "XPAR_PWM_AXI_LITE_V1_0_0_BASEADDR introuvable : instance renommee/dupliquee dans le Block Design ? Adaptez le nom de macro (cf. xparameters.h) ou definissez PWM_AXI_LITE_BASEADDR manuellement."
#endif

/* Periode PWM utilisee pour la demo (coups d'horloge s_axi_aclk) : 2kHz a
 * 100MHz, identique a la valeur par defaut au reset materiel. */
#define DEMO_PERIOD_CYCLES 50000U

static PWM_AxiLite PwmInst;

static void PrintStatusLine(u32 PercentRequested)
{
    u32 Period    = PWM_AxiLite_GetPeriod(&PwmInst);
    u32 Threshold = PWM_AxiLite_GetThreshold(&PwmInst);
    u32 HighCycles = Threshold; /* pwm_out haut tant que counter < Threshold */

    xil_printf("  haut=%3lu%% (period=%6lu, threshold=%6lu, haut=%6lu coups)\r\n",
               (unsigned long)PercentRequested,
               (unsigned long)Period,
               (unsigned long)Threshold,
               (unsigned long)HighCycles);
}

int test_pwm_axi_lite(void)
{
    int Status;
    u32 Percent;

    xil_printf("\r\n--- Test pwm_axi_lite_v1_0 ----------------------------\r\n");
    xil_printf("BaseAddress = 0x%08lX\r\n", (unsigned long)PWM_AXI_LITE_BASEADDR);

    Status = PWM_AxiLite_Init(&PwmInst, PWM_AXI_LITE_BASEADDR);
    if (Status != XST_SUCCESS) {
        xil_printf("ERREUR : PWM_AxiLite_Init a echoue\r\n");
        return XST_FAILURE;
    }

    /* -------------------------------------------------------------- */
    /* 1) Auto-test bus/registres                                     */
    /* -------------------------------------------------------------- */
    xil_printf("Auto-test registres... ");
    Status = PWM_AxiLite_SelfTest(&PwmInst);
    if (Status != XST_SUCCESS) {
        xil_printf("ECHEC\r\n");
        xil_printf("-> verifier BaseAddress, et que l'IP est bien instanciee/connectee\r\n");
        xil_printf("   dans le Block Design.\r\n");
        return XST_FAILURE;
    }
    xil_printf("OK\r\n");

    /* -------------------------------------------------------------- */
    /* 2) Le module doit etre actif par defaut (CTRL.ENABLE=1 au reset,   */
    /*    sans intervention logicielle) : simple verification/rappel.    */
    /* -------------------------------------------------------------- */
    xil_printf("Etat actif/inactif (CTRL.ENABLE) au demarrage : %s\r\n",
               PWM_AxiLite_IsEnabled(&PwmInst) ? "ACTIF (attendu par defaut)" : "INACTIF (inattendu)");
    if (!PWM_AxiLite_IsEnabled(&PwmInst)) {
        xil_printf("-> reactivation explicite (le module devrait deja etre actif au reset).\r\n");
        PWM_AxiLite_Enable(&PwmInst, 1);
    }

    /* -------------------------------------------------------------- */
    /* 3) Configuration de la periode de demo                         */
    /* -------------------------------------------------------------- */
    PWM_AxiLite_SetPeriod(&PwmInst, DEMO_PERIOD_CYCLES);
    xil_printf("Periode PWM relue = %lu cycles\r\n",
               (unsigned long)PWM_AxiLite_GetPeriod(&PwmInst));

    /* -------------------------------------------------------------- */
    /* 4) Rampe de temps haut 100% -> 0% par pas de 10%                */
    /* -------------------------------------------------------------- */
    xil_printf("Rampe de temps haut :\r\n");
    for (Percent = 0U; Percent <= 100U; Percent += 10U) {
        u32 Consigne = 100U - Percent;

        Status = PWM_AxiLite_SetHighPercent(&PwmInst, Consigne);
        if (Status != XST_SUCCESS) {
            xil_printf("ERREUR : SetHighPercent(%lu) invalide\r\n", (unsigned long)Consigne);
            continue;
        }
        PrintStatusLine(Consigne);
        sleep(1); /* laisse le temps d'observer/mesurer une periode stable */
    }

    /* Sequence arret / pleine puissance / retour au ratio par defaut
     * materiel (70%) plutot que de laisser 0% ou 100% actif indefiniment a
     * la fin de la demo. */
    xil_printf("Arret du ventilateur (0%%)\r\n");
    PWM_AxiLite_SetHighPercent(&PwmInst, 0U);
    sleep(4);

    xil_printf("Redemarrage du ventilateur (100%%)\r\n");
    PWM_AxiLite_SetHighPercent(&PwmInst, 100U);
    sleep(4);

    xil_printf("Asservissement (70%%, defaut materiel)\r\n");
    PWM_AxiLite_SetHighPercent(&PwmInst, 70U);
    sleep(20); /* laisse le temps d'observer/mesurer une periode stable */

    xil_printf("Test termine : PERIOD=%lu, temps haut=70%% (defaut materiel).\r\n",
               (unsigned long)PWM_AxiLite_GetPeriod(&PwmInst));
    xil_printf("-------------------------------------------------------\r\n");

    return XST_SUCCESS;
}
