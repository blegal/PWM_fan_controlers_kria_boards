/*-----------------------------------------------------------------------------
 * test_build_info.c
 *
 * Application baremetal (Vitis, domaine "standalone") de detection et de
 * lecture pour l'IP build_info_axi_v1_0 :
 *
 *   1. Detection (BuildInfo_Init + BuildInfo_SelfTest) : verifie que le
 *      registre MAGIC contient bien la signature attendue ("BINF").
 *   2. Lecture et affichage de la date/heure de synthese (brute et decodee),
 *      du numero de build (a comparer avec tcl/package_ip_build_info.tcl et
 *      Vivado), et de la version (majeur.mineur) du design.
 *
 * Registres tous en lecture seule (pas de configuration/test de charge a
 * proprement parler, contrairement aux autres IP du depot) : cette IP est
 * une simple etiquette d'identification du bitstream charge.
 *
 * A ajouter au projet application Vitis avec build_info.c/.h (dossier
 * sw/drivers/build_info/).
 *
 * N'est PAS un point d'entree (pas de main()) : appeler test_build_info()
 * depuis le main() de l'application (qui peut enchainer plusieurs tests).
 *---------------------------------------------------------------------------*/

#include "xparameters.h"
#include "xil_printf.h"
#include "xstatus.h"

#include "build_info.h"

/*
 * Adresse de base de l'IP, generee dans xparameters.h (Regenerate Output
 * Products + Export Hardware + Vitis "Update Hardware" doivent avoir ete
 * faits au prealable).
 *
 * Le nom de macro par defaut ci-dessous decoule directement de
 * tcl/package_ip_build_info.tcl : VLNV name = "build_info_axi_v1_0", bus
 * interface associee sous le nom "S_AXI". Avec le nommage automatique
 * Vivado pour la PREMIERE instance deposee dans le Block Design (suffixe
 * "_0"), le nom genere est deterministe :
 *   XPAR_BUILD_INFO_AXI_V1_0_0_S_AXI_BASEADDR
 *
 * A adapter uniquement si vous renommez l'instance dans le Block Design, ou
 * si vous en instanciez plusieurs (suffixe "_1", "_2", ... pour les
 * suivantes).
 */
#ifdef XPAR_BUILD_INFO_AXI_V1_0_0_S_AXI_BASEADDR
	#define BUILD_INFO_BASEADDR XPAR_BUILD_INFO_AXI_V1_0_0_S_AXI_BASEADDR
#else
	#error "XPAR_BUILD_INFO_AXI_V1_0_0_S_AXI_BASEADDR introuvable : instance renommee/dupliquee dans le Block Design ? Adaptez le nom de macro (cf. xparameters.h) ou definissez BUILD_INFO_BASEADDR manuellement."
#endif

static BuildInfo Info;

int test_build_info(void)
{
    int Status;
    u32 Magic;
    u16 Year;
    u8  Month, Day, Hour, Minute, Second;
    u32 VersionMajor, VersionMinor, BuildNumber;

    xil_printf("\r\n--- Test build_info_axi_v1_0 --------------------------\r\n");
    xil_printf("BaseAddress = 0x%08lX\r\n", (unsigned long)BUILD_INFO_BASEADDR);

    Status = BuildInfo_Init(&Info, BUILD_INFO_BASEADDR);
    if (Status != XST_SUCCESS) {
        xil_printf("ERREUR : BuildInfo_Init a echoue\r\n");
        return XST_FAILURE;
    }

    /* -------------------------------------------------------------- */
    /* 1) Detection                                                    */
    /* -------------------------------------------------------------- */
    xil_printf("Auto-test (verification MAGIC)... ");
    Status = BuildInfo_SelfTest(&Info);
    Magic  = BuildInfo_GetMagic(&Info);
    if (Status != XST_SUCCESS) {
        xil_printf("ECHEC\r\n");
        xil_printf("  MAGIC lu = 0x%08lX, attendu = 0x%08lX\r\n",
                   (unsigned long)Magic, (unsigned long)BUILD_INFO_EXPECTED_MAGIC);
        xil_printf("-> verifier BaseAddress et que l'IP est bien instanciee/connectee\r\n");
        xil_printf("   dans le Block Design.\r\n");
        return XST_FAILURE;
    }
    xil_printf("OK (MAGIC = 0x%08lX \"BINF\")\r\n", (unsigned long)Magic);

    /* -------------------------------------------------------------- */
    /* 2) Lecture date/heure de synthese et version                   */
    /* -------------------------------------------------------------- */
    BuildInfo_GetBuildDateFields(&Info, &Year, &Month, &Day);
    BuildInfo_GetBuildTimeFields(&Info, &Hour, &Minute, &Second);
    VersionMajor = BuildInfo_GetVersionMajor(&Info);
    VersionMinor = BuildInfo_GetVersionMinor(&Info);
    BuildNumber  = BuildInfo_GetBuildNumber(&Info);

    xil_printf("Date de synthese : %04d-%02d-%02d (brut = 0x%08lX)\r\n",
               Year, Month, Day, (unsigned long)BuildInfo_GetBuildDateRaw(&Info));
    xil_printf("Heure de synthese : %02d:%02d:%02d (brut = 0x%08lX)\r\n",
               Hour, Minute, Second, (unsigned long)BuildInfo_GetBuildTimeRaw(&Info));
    xil_printf("Version du design : %lu.%lu\r\n",
               (unsigned long)VersionMajor, (unsigned long)VersionMinor);
    xil_printf("Numero de build : %lu\r\n", (unsigned long)BuildNumber);
    xil_printf("-> a comparer avec le \"Build #%lu\" affiche par tcl/package_ip_build_info.tcl\r\n",
               (unsigned long)BuildNumber);
    xil_printf("   et avec la version Vivado du composant dans l'IP catalog (Report IP Status).\r\n");

    if ((Year == 0U) && (Month == 0U) && (Day == 0U) &&
        (VersionMajor == 0U) && (VersionMinor == 0U) && (BuildNumber == 0U)) {
        xil_printf("ATTENTION : toutes les valeurs sont a 0 -- les generics\r\n");
        xil_printf("G_BUILD_DATE/G_BUILD_TIME/G_VERSION_MAJOR/G_VERSION_MINOR/G_BUILD_NUMBER\r\n");
        xil_printf("n'ont probablement pas ete renseignees avant synthese (cf. tcl/set_build_info.tcl).\r\n");
    }

    xil_printf("-------------------------------------------------------\r\n");

    return XST_SUCCESS;
}
