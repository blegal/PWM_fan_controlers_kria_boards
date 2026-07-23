/*-----------------------------------------------------------------------------
 * build_info.h
 *
 * Driver baremetal (Vitis standalone) pour l'IP AXI4-Lite en lecture seule
 * `build_info_axi_v1_0` (voir src/build_info_axi_v1_0.vhd) : expose la
 * date/heure de synthese, un numero de build, et la version (majeur/mineur)
 * du design.
 *
 * Carte memoire (registres 32 bits, offsets par rapport a BaseAddress,
 * TOUS EN LECTURE SEULE) :
 *
 *   0x00 MAGIC         signature fixe 0x42494E46 ("BINF"), RO
 *   0x04 BUILD_DATE    date de synthese, format BCD 0xYYYYMMDD
 *                      (ex: 0x20260723 pour le 23 juillet 2026), RO
 *   0x08 BUILD_TIME    heure de synthese, format BCD 0x00HHMMSS
 *                      (ex: 0x00143512 pour 14:35:12), RO
 *   0x0C VERSION_MAJOR numero de version majeur, RO
 *   0x10 VERSION_MINOR numero de version mineur, RO
 *   0x14 BUILD_NUMBER  compteur de build (tcl/build_counter.tcl), permet de
 *                      verifier que le bitstream charge correspond bien au
 *                      dernier packaging effectue (comparer avec le numero
 *                      affiche dans le terminal par
 *                      tcl/package_ip_build_info.tcl), RO
 *
 * IMPORTANT :
 *  - BUILD_DATE/BUILD_TIME sont encodes en BCD (chaque quartet de 4 bits =
 *    un chiffre decimal 0-9, PAS une valeur binaire/hexadecimale classique) :
 *    c'est ce qui permet d'afficher la valeur brute en hexadecimal (%X) et
 *    d'obtenir directement la date/heure calendaire lisible. Utiliser
 *    BuildInfo_GetBuildDateFields()/BuildInfo_GetBuildTimeFields() pour
 *    obtenir les champs individuels (annee, mois, jour, heure, minute,
 *    seconde) sous forme d'entiers decimaux normaux. BUILD_NUMBER, lui,
 *    est un entier binaire classique (pas du BCD).
 *  - Ces valeurs sont figees a l'elaboration du bitstream (generics VHDL
 *    G_BUILD_DATE/G_BUILD_TIME/G_VERSION_MAJOR/G_VERSION_MINOR/G_BUILD_NUMBER,
 *    cf. tcl/set_build_info.tcl) : elles ne changent jamais au runtime, un
 *    seul rafraichissement de cache/lecture est necessaire (pas de polling).
 *  - Si ces generics n'ont pas ete renseignees avant synthese (defaut = 0
 *    cote VHDL), tous ces registres se liront a 0 : ce n'est pas une erreur
 *    de driver, verifier le Block Design / tcl/set_build_info.tcl.
 *---------------------------------------------------------------------------*/

#ifndef BUILD_INFO_H
#define BUILD_INFO_H

#ifdef __cplusplus
extern "C" {
#endif

#include "xil_types.h"
#include "xil_io.h"
#include "xstatus.h"

/* ------------------------------------------------------------------------ */
/* Offsets registres                                                        */
/* ------------------------------------------------------------------------ */
#define BUILD_INFO_MAGIC_OFFSET         0x00U
#define BUILD_INFO_BUILD_DATE_OFFSET    0x04U
#define BUILD_INFO_BUILD_TIME_OFFSET    0x08U
#define BUILD_INFO_VERSION_MAJOR_OFFSET 0x0CU
#define BUILD_INFO_VERSION_MINOR_OFFSET 0x10U
#define BUILD_INFO_BUILD_NUMBER_OFFSET  0x14U

/* Signature fixe attendue dans MAGIC ("BINF" en ASCII), cf. build_info_axi_v1_0.vhd. */
#define BUILD_INFO_EXPECTED_MAGIC 0x42494E46U

/* ------------------------------------------------------------------------ */
/* Instance                                                                  */
/* ------------------------------------------------------------------------ */
typedef struct {
    UINTPTR BaseAddress;   /* Adresse de base S_AXI (depuis xparameters.h) */
    u32     IsReady;       /* XIL_COMPONENT_IS_READY apres Init */
} BuildInfo;

/* ------------------------------------------------------------------------ */
/* API                                                                       */
/* ------------------------------------------------------------------------ */

/* Associe l'instance a une adresse de base. Ne touche a aucun registre. */
int BuildInfo_Init(BuildInfo *InstancePtr, UINTPTR BaseAddress);

/*
 * Detection non destructive : verifie que MAGIC == BUILD_INFO_EXPECTED_MAGIC.
 * Tous les registres etant en lecture seule, c'est la seule verification
 * pertinente (pas de motif ecriture/lecture possible ici) : un mismatch
 * signale un mauvais BaseAddress, une IP absente/non connectee, ou un
 * probleme de decodage d'adresse AXI.
 * Retourne XST_SUCCESS ou XST_FAILURE.
 */
int BuildInfo_SelfTest(BuildInfo *InstancePtr);

/* Lecture brute des registres (RO). */
u32 BuildInfo_GetMagic(BuildInfo *InstancePtr);
u32 BuildInfo_GetBuildDateRaw(BuildInfo *InstancePtr);   /* BCD 0xYYYYMMDD */
u32 BuildInfo_GetBuildTimeRaw(BuildInfo *InstancePtr);   /* BCD 0x00HHMMSS */
u32 BuildInfo_GetVersionMajor(BuildInfo *InstancePtr);
u32 BuildInfo_GetVersionMinor(BuildInfo *InstancePtr);
u32 BuildInfo_GetBuildNumber(BuildInfo *InstancePtr);

/*
 * Decodage BCD -> champs decimaux normaux (annee sur 4 chiffres, mois/jour
 * 1-31/1-12). Pointeurs de sortie optionnels (NULL accepte, champ ignore).
 */
void BuildInfo_GetBuildDateFields(BuildInfo *InstancePtr, u16 *Year, u8 *Month, u8 *Day);

/* Decodage BCD -> champs decimaux normaux (heure/minute/seconde 0-23/0-59/0-59). */
void BuildInfo_GetBuildTimeFields(BuildInfo *InstancePtr, u8 *Hour, u8 *Minute, u8 *Second);

#ifdef __cplusplus
}
#endif

#endif /* BUILD_INFO_H */
