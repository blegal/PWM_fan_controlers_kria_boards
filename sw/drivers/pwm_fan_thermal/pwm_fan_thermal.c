/*-----------------------------------------------------------------------------
 * pwm_fan_thermal.c
 *
 * Implementation du driver baremetal pour pwm_fan_thermal_axi_v1_0.
 * Voir pwm_fan_thermal.h pour la description de la carte memoire.
 *---------------------------------------------------------------------------*/

#include "pwm_fan_thermal.h"

#define PWM_FAN_THERMAL_READY_MAGIC 0x11111111U

static inline u32 RegRead(PWM_FanThermal *InstancePtr, u32 Offset)
{
    return Xil_In32(InstancePtr->BaseAddress + Offset);
}

static inline void RegWrite(PWM_FanThermal *InstancePtr, u32 Offset, u32 Value)
{
    Xil_Out32(InstancePtr->BaseAddress + Offset, Value);
}

int PWM_FanThermal_Init(PWM_FanThermal *InstancePtr, UINTPTR BaseAddress)
{
    if (InstancePtr == NULL) {
        return XST_FAILURE;
    }

    InstancePtr->BaseAddress = BaseAddress;
    InstancePtr->IsReady     = PWM_FAN_THERMAL_READY_MAGIC;

    return XST_SUCCESS;
}

void PWM_FanThermal_Enable(PWM_FanThermal *InstancePtr, u8 Enable)
{
    u32 Ctrl = RegRead(InstancePtr, PWM_FAN_THERMAL_CTRL_OFFSET);

    if (Enable) {
        Ctrl |= PWM_FAN_THERMAL_CTRL_ENABLE_MASK;
    } else {
        Ctrl &= ~PWM_FAN_THERMAL_CTRL_ENABLE_MASK;
    }

    RegWrite(InstancePtr, PWM_FAN_THERMAL_CTRL_OFFSET, Ctrl);
}

void PWM_FanThermal_SetAutoMode(PWM_FanThermal *InstancePtr, u8 AutoMode)
{
    u32 Ctrl = RegRead(InstancePtr, PWM_FAN_THERMAL_CTRL_OFFSET);

    if (AutoMode) {
        Ctrl |= PWM_FAN_THERMAL_CTRL_AUTO_MODE_MASK;
    } else {
        Ctrl &= ~PWM_FAN_THERMAL_CTRL_AUTO_MODE_MASK;
    }

    RegWrite(InstancePtr, PWM_FAN_THERMAL_CTRL_OFFSET, Ctrl);
}

u32 PWM_FanThermal_GetCtrl(PWM_FanThermal *InstancePtr)
{
    return RegRead(InstancePtr, PWM_FAN_THERMAL_CTRL_OFFSET);
}

void PWM_FanThermal_SetPeriod(PWM_FanThermal *InstancePtr, u32 PeriodCycles)
{
    RegWrite(InstancePtr, PWM_FAN_THERMAL_PERIOD_OFFSET, PeriodCycles);
}

u32 PWM_FanThermal_GetPeriod(PWM_FanThermal *InstancePtr)
{
    return RegRead(InstancePtr, PWM_FAN_THERMAL_PERIOD_OFFSET);
}

void PWM_FanThermal_SetDutyRaw(PWM_FanThermal *InstancePtr, u32 DutyCycles)
{
    RegWrite(InstancePtr, PWM_FAN_THERMAL_DUTY_OFFSET, DutyCycles);
}

u32 PWM_FanThermal_GetDutyRaw(PWM_FanThermal *InstancePtr)
{
    return RegRead(InstancePtr, PWM_FAN_THERMAL_DUTY_OFFSET);
}

int PWM_FanThermal_SetDutyPercent(PWM_FanThermal *InstancePtr, u32 Percent)
{
    u32 Period;
    u64 DutyCycles;

    if (Percent > 100U) {
        return XST_INVALID_PARAM;
    }

    Period     = PWM_FanThermal_GetPeriod(InstancePtr);
    DutyCycles = ((u64)Period * (u64)Percent) / 100U;

    PWM_FanThermal_SetDutyRaw(InstancePtr, (u32)DutyCycles);

    return XST_SUCCESS;
}

u32 PWM_FanThermal_GetDutyAuto(PWM_FanThermal *InstancePtr)
{
    return RegRead(InstancePtr, PWM_FAN_THERMAL_DUTY_AUTO_OFFSET);
}

s16 PWM_FanThermal_GetTempCentideg(PWM_FanThermal *InstancePtr)
{
    u32 Raw = RegRead(InstancePtr, PWM_FAN_THERMAL_TEMP_RAW_OFFSET);
    /* Le registre est deja sign-extend sur 32 bits cote VHDL (resize d'un
     * signed 16 bits) ; on retronque simplement au type s16 attendu. */
    return (s16)(Raw & 0xFFFFU);
}

void PWM_FanThermal_SetThresholds(PWM_FanThermal *InstancePtr, s16 TMinCentideg, s16 TMaxCentideg)
{
    u32 Reg = ((u32)(u16)TMinCentideg & PWM_FAN_THERMAL_T_THRESH_TMIN_MASK) |
              ((u32)(u16)TMaxCentideg << PWM_FAN_THERMAL_T_THRESH_TMAX_SHIFT);

    RegWrite(InstancePtr, PWM_FAN_THERMAL_T_THRESH_OFFSET, Reg);
}

void PWM_FanThermal_GetThresholds(PWM_FanThermal *InstancePtr, s16 *TMinCentideg, s16 *TMaxCentideg)
{
    u32 Reg = RegRead(InstancePtr, PWM_FAN_THERMAL_T_THRESH_OFFSET);

    if (TMinCentideg != NULL) {
        *TMinCentideg = (s16)(Reg & PWM_FAN_THERMAL_T_THRESH_TMIN_MASK);
    }
    if (TMaxCentideg != NULL) {
        *TMaxCentideg = (s16)(Reg >> PWM_FAN_THERMAL_T_THRESH_TMAX_SHIFT);
    }
}

void PWM_FanThermal_SetDutyBounds(PWM_FanThermal *InstancePtr, u32 DutyMin, u32 DutyMax)
{
    RegWrite(InstancePtr, PWM_FAN_THERMAL_DUTY_MIN_OFFSET, DutyMin);
    RegWrite(InstancePtr, PWM_FAN_THERMAL_DUTY_MAX_OFFSET, DutyMax);
}

void PWM_FanThermal_GetDutyBounds(PWM_FanThermal *InstancePtr, u32 *DutyMin, u32 *DutyMax)
{
    if (DutyMin != NULL) {
        *DutyMin = RegRead(InstancePtr, PWM_FAN_THERMAL_DUTY_MIN_OFFSET);
    }
    if (DutyMax != NULL) {
        *DutyMax = RegRead(InstancePtr, PWM_FAN_THERMAL_DUTY_MAX_OFFSET);
    }
}

u8 PWM_FanThermal_IsTempValid(PWM_FanThermal *InstancePtr)
{
    u32 Status = RegRead(InstancePtr, PWM_FAN_THERMAL_STATUS_OFFSET);
    return (Status & PWM_FAN_THERMAL_STATUS_TEMP_VALID_MASK) ? 1U : 0U;
}

int PWM_FanThermal_SelfTest(PWM_FanThermal *InstancePtr)
{
    u32 SavedDutyMin, SavedDutyMax;
    u32 Readback;
    int Status = XST_SUCCESS;

    if ((InstancePtr == NULL) || (InstancePtr->IsReady != PWM_FAN_THERMAL_READY_MAGIC)) {
        return XST_FAILURE;
    }

    PWM_FanThermal_GetDutyBounds(InstancePtr, &SavedDutyMin, &SavedDutyMax);

    /* 1) Motif alterne sur DUTY_MIN : verifie que le bus AXI ecrit/relit
     *    correctement les 32 bits (defaut de decodage d'adresse, bit
     *    bloque a 0/1, etc. se verraient ici). */
    RegWrite(InstancePtr, PWM_FAN_THERMAL_DUTY_MIN_OFFSET, 0xA5A5A5A5U);
    Readback = RegRead(InstancePtr, PWM_FAN_THERMAL_DUTY_MIN_OFFSET);
    if (Readback != 0xA5A5A5A5U) {
        Status = XST_FAILURE;
    }

    RegWrite(InstancePtr, PWM_FAN_THERMAL_DUTY_MIN_OFFSET, 0x5A5A5A5AU);
    Readback = RegRead(InstancePtr, PWM_FAN_THERMAL_DUTY_MIN_OFFSET);
    if (Readback != 0x5A5A5A5AU) {
        Status = XST_FAILURE;
    }

    /* 2) DUTY_MIN et DUTY_MAX doivent etre deux registres distincts (teste
     *    un decodage d'adresse fige/aliase entre les deux). */
    RegWrite(InstancePtr, PWM_FAN_THERMAL_DUTY_MIN_OFFSET, 0x00000001U);
    RegWrite(InstancePtr, PWM_FAN_THERMAL_DUTY_MAX_OFFSET, 0x00000002U);
    if ((RegRead(InstancePtr, PWM_FAN_THERMAL_DUTY_MIN_OFFSET) != 0x00000001U) ||
        (RegRead(InstancePtr, PWM_FAN_THERMAL_DUTY_MAX_OFFSET) != 0x00000002U)) {
        Status = XST_FAILURE;
    }

    /* Restauration des valeurs d'origine (le self-test ne doit pas laisser
     * le module dans un etat different de celui trouve avant l'appel). */
    PWM_FanThermal_SetDutyBounds(InstancePtr, SavedDutyMin, SavedDutyMax);

    return Status;
}
