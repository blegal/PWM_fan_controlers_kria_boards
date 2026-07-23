/*-----------------------------------------------------------------------------
 * build_info.c
 *
 * Implementation du driver baremetal pour build_info_axi_v1_0.
 * Voir build_info.h pour la description de la carte memoire.
 *---------------------------------------------------------------------------*/

#include "build_info.h"

#define BUILD_INFO_READY_MAGIC 0x33333333U

static inline u32 RegRead(BuildInfo *InstancePtr, u32 Offset)
{
    return Xil_In32(InstancePtr->BaseAddress + Offset);
}

/* Decode un octet BCD (chaque quartet = un chiffre decimal 0-9) en valeur
 * binaire normale, ex: 0x23 (BCD) -> 23 (decimal). */
static u8 BcdByteToBin(u8 BcdByte)
{
    return (u8)(((BcdByte >> 4) & 0xFU) * 10U + (BcdByte & 0xFU));
}

int BuildInfo_Init(BuildInfo *InstancePtr, UINTPTR BaseAddress)
{
    if (InstancePtr == NULL) {
        return XST_FAILURE;
    }

    InstancePtr->BaseAddress = BaseAddress;
    InstancePtr->IsReady     = BUILD_INFO_READY_MAGIC;

    return XST_SUCCESS;
}

int BuildInfo_SelfTest(BuildInfo *InstancePtr)
{
    u32 Magic;

    if ((InstancePtr == NULL) || (InstancePtr->IsReady != BUILD_INFO_READY_MAGIC)) {
        return XST_FAILURE;
    }

    Magic = RegRead(InstancePtr, BUILD_INFO_MAGIC_OFFSET);
    if (Magic != BUILD_INFO_EXPECTED_MAGIC) {
        return XST_FAILURE;
    }

    return XST_SUCCESS;
}

u32 BuildInfo_GetMagic(BuildInfo *InstancePtr)
{
    return RegRead(InstancePtr, BUILD_INFO_MAGIC_OFFSET);
}

u32 BuildInfo_GetBuildDateRaw(BuildInfo *InstancePtr)
{
    return RegRead(InstancePtr, BUILD_INFO_BUILD_DATE_OFFSET);
}

u32 BuildInfo_GetBuildTimeRaw(BuildInfo *InstancePtr)
{
    return RegRead(InstancePtr, BUILD_INFO_BUILD_TIME_OFFSET);
}

u32 BuildInfo_GetVersionMajor(BuildInfo *InstancePtr)
{
    return RegRead(InstancePtr, BUILD_INFO_VERSION_MAJOR_OFFSET);
}

u32 BuildInfo_GetVersionMinor(BuildInfo *InstancePtr)
{
    return RegRead(InstancePtr, BUILD_INFO_VERSION_MINOR_OFFSET);
}

u32 BuildInfo_GetBuildNumber(BuildInfo *InstancePtr)
{
    return RegRead(InstancePtr, BUILD_INFO_BUILD_NUMBER_OFFSET);
}

void BuildInfo_GetBuildDateFields(BuildInfo *InstancePtr, u16 *Year, u8 *Month, u8 *Day)
{
    u32 Raw = BuildInfo_GetBuildDateRaw(InstancePtr);
    u8  YearHi = (u8)((Raw >> 24) & 0xFFU);
    u8  YearLo = (u8)((Raw >> 16) & 0xFFU);
    u8  MonthB = (u8)((Raw >> 8)  & 0xFFU);
    u8  DayB   = (u8)(Raw & 0xFFU);

    if (Year != NULL) {
        *Year = (u16)BcdByteToBin(YearHi) * 100U + (u16)BcdByteToBin(YearLo);
    }
    if (Month != NULL) {
        *Month = BcdByteToBin(MonthB);
    }
    if (Day != NULL) {
        *Day = BcdByteToBin(DayB);
    }
}

void BuildInfo_GetBuildTimeFields(BuildInfo *InstancePtr, u8 *Hour, u8 *Minute, u8 *Second)
{
    u32 Raw = BuildInfo_GetBuildTimeRaw(InstancePtr);
    u8  HourB   = (u8)((Raw >> 16) & 0xFFU);
    u8  MinuteB = (u8)((Raw >> 8)  & 0xFFU);
    u8  SecondB = (u8)(Raw & 0xFFU);

    if (Hour != NULL) {
        *Hour = BcdByteToBin(HourB);
    }
    if (Minute != NULL) {
        *Minute = BcdByteToBin(MinuteB);
    }
    if (Second != NULL) {
        *Second = BcdByteToBin(SecondB);
    }
}
