/*-----------------------------------------------------------------------------
 * pwm_axi_lite.c
 *
 * Implementation du driver baremetal pour pwm_axi_lite_v1_0.
 * Voir pwm_axi_lite.h pour la description de la carte memoire.
 *---------------------------------------------------------------------------*/

#include "pwm_axi_lite.h"

#define PWM_AXI_LITE_READY_MAGIC 0x44444444U

static inline u32 RegRead(PWM_AxiLite *InstancePtr, u32 Offset)
{
    return Xil_In32(InstancePtr->BaseAddress + Offset);
}

static inline void RegWrite(PWM_AxiLite *InstancePtr, u32 Offset, u32 Value)
{
    Xil_Out32(InstancePtr->BaseAddress + Offset, Value);
}

int PWM_AxiLite_Init(PWM_AxiLite *InstancePtr, UINTPTR BaseAddress)
{
    if (InstancePtr == NULL) {
        return XST_FAILURE;
    }

    InstancePtr->BaseAddress = BaseAddress;
    InstancePtr->IsReady     = PWM_AXI_LITE_READY_MAGIC;

    return XST_SUCCESS;
}

void PWM_AxiLite_Enable(PWM_AxiLite *InstancePtr, u8 Enable)
{
    u32 Ctrl = RegRead(InstancePtr, PWM_AXI_LITE_CTRL_OFFSET);

    if (Enable) {
        Ctrl |= PWM_AXI_LITE_CTRL_ENABLE_MASK;
    } else {
        Ctrl &= ~PWM_AXI_LITE_CTRL_ENABLE_MASK;
    }

    RegWrite(InstancePtr, PWM_AXI_LITE_CTRL_OFFSET, Ctrl);
}

u8 PWM_AxiLite_IsEnabled(PWM_AxiLite *InstancePtr)
{
    u32 Ctrl = RegRead(InstancePtr, PWM_AXI_LITE_CTRL_OFFSET);
    return (Ctrl & PWM_AXI_LITE_CTRL_ENABLE_MASK) ? 1U : 0U;
}

void PWM_AxiLite_SetPeriod(PWM_AxiLite *InstancePtr, u32 PeriodCycles)
{
    RegWrite(InstancePtr, PWM_AXI_LITE_PERIOD_OFFSET, PeriodCycles);
}

u32 PWM_AxiLite_GetPeriod(PWM_AxiLite *InstancePtr)
{
    return RegRead(InstancePtr, PWM_AXI_LITE_PERIOD_OFFSET);
}

void PWM_AxiLite_SetThreshold(PWM_AxiLite *InstancePtr, u32 ThresholdCycles)
{
    RegWrite(InstancePtr, PWM_AXI_LITE_THRESHOLD_OFFSET, ThresholdCycles);
}

u32 PWM_AxiLite_GetThreshold(PWM_AxiLite *InstancePtr)
{
    return RegRead(InstancePtr, PWM_AXI_LITE_THRESHOLD_OFFSET);
}

int PWM_AxiLite_SetHighPercent(PWM_AxiLite *InstancePtr, u32 Percent)
{
    u32 Period;
    u64 HighCycles;

    if (Percent > 100U) {
        return XST_INVALID_PARAM;
    }

    Period     = PWM_AxiLite_GetPeriod(InstancePtr);
    HighCycles = ((u64)Period * (u64)Percent) / 100U;

    /* Threshold = HighCycles (pwm_out haut tant que counter < Threshold) :
     * garantit Threshold <= Period par construction. */
    PWM_AxiLite_SetThreshold(InstancePtr, (u32)HighCycles);

    return XST_SUCCESS;
}

int PWM_AxiLite_SelfTest(PWM_AxiLite *InstancePtr)
{
    u32 SavedPeriod, SavedThreshold;
    u32 Readback;
    int Status = XST_SUCCESS;

    if ((InstancePtr == NULL) || (InstancePtr->IsReady != PWM_AXI_LITE_READY_MAGIC)) {
        return XST_FAILURE;
    }

    SavedPeriod    = PWM_AxiLite_GetPeriod(InstancePtr);
    SavedThreshold = PWM_AxiLite_GetThreshold(InstancePtr);

    /* 1) Motif alterne sur PERIOD. */
    RegWrite(InstancePtr, PWM_AXI_LITE_PERIOD_OFFSET, 0xA5A5A5A5U);
    Readback = RegRead(InstancePtr, PWM_AXI_LITE_PERIOD_OFFSET);
    if (Readback != 0xA5A5A5A5U) {
        Status = XST_FAILURE;
    }

    RegWrite(InstancePtr, PWM_AXI_LITE_PERIOD_OFFSET, 0x5A5A5A5AU);
    Readback = RegRead(InstancePtr, PWM_AXI_LITE_PERIOD_OFFSET);
    if (Readback != 0x5A5A5A5AU) {
        Status = XST_FAILURE;
    }

    /* 2) PERIOD et THRESHOLD doivent etre deux registres distincts (teste
     *    un decodage d'adresse fige/aliase entre les deux). */
    RegWrite(InstancePtr, PWM_AXI_LITE_PERIOD_OFFSET, 0x00000001U);
    RegWrite(InstancePtr, PWM_AXI_LITE_THRESHOLD_OFFSET, 0x00000002U);
    if ((RegRead(InstancePtr, PWM_AXI_LITE_PERIOD_OFFSET) != 0x00000001U) ||
        (RegRead(InstancePtr, PWM_AXI_LITE_THRESHOLD_OFFSET) != 0x00000002U)) {
        Status = XST_FAILURE;
    }

    /* Restauration des valeurs d'origine. */
    PWM_AxiLite_SetPeriod(InstancePtr, SavedPeriod);
    PWM_AxiLite_SetThreshold(InstancePtr, SavedThreshold);

    return Status;
}
