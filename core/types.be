# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Core Domain Enumerations, Electrical Constants & Engineering Units
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

class Types
    # Physical Connector Standards
    static var CONNECTOR_TYPE_UNKNOWN = "Unknown"
    static var CONNECTOR_TYPE_TYPE2   = "IEC62196Type2"
    static var CONNECTOR_TYPE_CCS2    = "IEC62196Type2Combo"
    static var CONNECTOR_TYPE_CHADEMO = "CHAdeMO"
    static var CONNECTOR_TYPE_NACS    = "SAEJ3400"

    # Operational Connector States (IEC 61851 / OCPP 2.0.1)
    static var STATE_AVAILABLE      = "Available"
    static var STATE_PREPARING      = "Preparing"
    static var STATE_CHARGING       = "Charging"
    static var STATE_SUSPENDED_EV   = "SuspendedEV"
    static var STATE_SUSPENDED_EVSE = "SuspendedEVSE"
    static var STATE_FINISHING      = "Finishing"
    static var STATE_RESERVED       = "Reserved"
    static var STATE_UNAVAILABLE    = "Unavailable"
    static var STATE_FAULTED        = "Faulted"

    # IEC 61851-1 Control Pilot Hardware Voltage States
    # State A: 12V DC (Vehicle not connected / Standby)
    # State B: 9V DC or 9V PWM (Vehicle connected, not ready to charge)
    # State C: 6V PWM (Vehicle connected, ready to charge, ventilation not required)
    # State D: 3V PWM (Vehicle connected, ready to charge, ventilation required)
    # State E: 0V (Short circuit to ground or power disconnected)
    # State F: -12V (Fault condition / diode failure)
    static var PILOT_STATE_A = "A"
    static var PILOT_STATE_B = "B"
    static var PILOT_STATE_C = "C"
    static var PILOT_STATE_D = "D"
    static var PILOT_STATE_E = "E"
    static var PILOT_STATE_F = "F"

    # Power Contactor Hardware States
    static var CONTACTOR_OPEN    = "Open"
    static var CONTACTOR_CLOSED  = "Closed"
    static var CONTACTOR_WELDED  = "Welded"
    static var CONTACTOR_FAULT   = "Fault"

    # Motorized Connector Lock States
    static var LOCK_UNLOCKED = "Unlocked"
    static var LOCK_LOCKED   = "Locked"
    static var LOCK_MOVING   = "Moving"
    static var LOCK_FAULT    = "Fault"

    # Authorization Verification Outcomes
    static var AUTH_ACCEPTED         = "Accepted"
    static var AUTH_BLOCKED          = "Blocked"
    static var AUTH_EXPIRED          = "Expired"
    static var AUTH_INVALID          = "Invalid"
    static var AUTH_CONCURRENT_TX    = "ConcurrentTx"
    static var AUTH_NO_CREDIT        = "NoCredit"

    # Smart Charging Profile Purposes
    static var PROFILE_PURPOSE_CHARGE_POINT_MAX = "ChargePointMaxProfile"
    static var PROFILE_PURPOSE_TX_DEFAULT       = "TxDefaultProfile"
    static var PROFILE_PURPOSE_TX_PROFILE       = "TxProfile"

    # Smart Charging Profile Kinds
    static var PROFILE_KIND_ABSOLUTE  = "Absolute"
    static var PROFILE_KIND_RECURRING = "Recurring"
    static var PROFILE_KIND_RELATIVE  = "Relative"

    # Charging Rate Engineering Units
    static var RATE_UNIT_WATTS   = "W"
    static var RATE_UNIT_AMPERES = "A"

    # AC Phase Configurations
    static var PHASE_1_L1 = "L1"
    static var PHASE_1_L2 = "L2"
    static var PHASE_1_L3 = "L3"
    static var PHASE_3    = "L1_L2_L3"

    # Standard Electrical & Safety Thresholds
    static var MIN_CHARGING_CURRENT_A     = 6.0
    static var MAX_AC_SINGLE_PHASE_A      = 32.0
    static var MAX_AC_THREE_PHASE_A       = 32.0
    static var NOMINAL_VOLTAGE_LN_V       = 230.0
    static var NOMINAL_VOLTAGE_LL_V       = 400.0
    static var NOMINAL_FREQUENCY_HZ       = 50.0
    static var MAX_FREQUENCY_DEVIATION_HZ = 0.5
    static var RCD_DC_TRIP_MA             = 6.0
    static var RCD_AC_TRIP_MA             = 30.0
    static var OVERCURRENT_TRIP_FACTOR    = 1.15
    static var OVERTEMP_DERATE_START_C    = 65.0
    static var OVERTEMP_CRITICAL_TRIP_C   = 85.0

    # Convert Control Pilot PWM duty cycle (0.0 to 1.0) to allowed charging current in Amperes
    # IEC 61851-1 Table A.6 specification:
    # Duty 10% to 85%: Current = Duty * 100 * 0.6 = Duty * 60
    # Duty 85% to 96%: Current = (Duty * 100 - 64) * 2.5
    # Duty < 10% or > 96%: Charging not allowed
    static def duty_cycle_to_amps(duty)
        duty = real(duty)
        var pct = duty * 100.0
        if pct < 10.0 || pct > 96.0
            return 0.0
        elif pct <= 85.0
            return pct * 0.6
        else
            return (pct - 64.0) * 2.5
        end
    end

    # Convert desired charging current in Amperes to IEC 61851-1 Control Pilot PWM duty cycle (0.0 to 1.0)
    static def amps_to_duty_cycle(amps)
        amps = real(amps)
        if amps < Types.MIN_CHARGING_CURRENT_A
            return 1.0 # 100% duty = digital communication or no charging permitted
        elif amps <= 51.0
            # Amps = DutyPct * 0.6 => DutyPct = Amps / 0.6
            var pct = amps / 0.6
            return pct / 100.0
        elif amps <= 80.0
            # Amps = (DutyPct - 64) * 2.5 => DutyPct = (Amps / 2.5) + 64
            var pct = (amps / 2.5) + 64.0
            return pct / 100.0
        else
            return 0.96 # Cap at 96%
        end
    end

    # Calculate 3-phase active power in kW from current per phase and line-to-neutral voltage
    static def calculate_3phase_kw(current_a, voltage_ln, pf)
        var i = real(current_a)
        var v = real(voltage_ln)
        var p_factor = (pf != nil) ? real(pf) : 1.0
        return (3.0 * v * i * p_factor) / 1000.0
    end

    # Calculate single-phase active power in kW
    static def calculate_1phase_kw(current_a, voltage_ln, pf)
        var i = real(current_a)
        var v = real(voltage_ln)
        var p_factor = (pf != nil) ? real(pf) : 1.0
        return (v * i * p_factor) / 1000.0
    end
end

return Types
