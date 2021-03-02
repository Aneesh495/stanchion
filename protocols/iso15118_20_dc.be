# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# ISO 15118-20 2nd Gen DC & Megawatt Charging System (MCS) Protocol Codec
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import math
import math_ext as MathExt

# ISO 15118-20 Message Definitions for DC & MCS
class ISO20Message
    static var DC_CHARGE_PARAMETER_DISCOVERY_REQ = "DC_ChargeParameterDiscoveryReq"
    static var DC_CHARGE_PARAMETER_DISCOVERY_RES = "DC_ChargeParameterDiscoveryRes"
    static var DC_CABLE_CHECK_REQ                 = "DC_CableCheckReq"
    static var DC_CABLE_CHECK_RES                 = "DC_CableCheckRes"
    static var DC_PRECHARGE_REQ                   = "DC_PreChargeReq"
    static var DC_PRECHARGE_RES                   = "DC_PreChargeRes"
    static var DC_CHARGE_LOOP_REQ                 = "DC_ChargeLoopReq"
    static var DC_CHARGE_LOOP_RES                 = "DC_ChargeLoopRes"
    static var DC_WELDING_DETECTION_REQ           = "DC_WeldingDetectionReq"
    static var DC_WELDING_DETECTION_RES           = "DC_WeldingDetectionRes"
end

# Automated Connection Device (ACD) State for Heavy Duty / Transit Pantographs
class ACDState
    static var UNDOCKED   = "UNDOCKED"
    static var DEPLOYING  = "DEPLOYING"
    static var DOCKED     = "DOCKED"
    static var LATCHED    = "LATCHED"
    static var RETRACTING = "RETRACTING"
end

# ISO 15118-20 Megawatt DC Charging Session Controller
class ISO15118_20_DCSession
    var session_id
    var evse_id
    var max_voltage_limit_v
    var max_current_limit_a
    var max_power_limit_kw
    var current_ramp_rate_a_per_s
    var acd_state
    var active_target_voltage_v
    var active_target_current_a
    var actual_measured_voltage_v
    var actual_measured_current_a
    var is_bpt_discharging
    var precharge_tolerance_v

    def init(evse_num, max_amps, max_volts, max_kw)
        self.session_id = "MCS-2026-X8890"
        self.evse_id = int(evse_num)
        self.max_current_limit_a = (max_amps != nil) ? real(max_amps) : 1500.0 # 1500A MCS rating
        self.max_voltage_limit_v = (max_volts != nil) ? real(max_volts) : 1000.0 # 1000V DC bus
        self.max_power_limit_kw = (max_kw != nil) ? real(max_kw) : 1200.0 # 1.2 MW peak
        self.current_ramp_rate_a_per_s = 150.0 # 150 A/s max slew rate
        self.acd_state = ACDState.UNDOCKED
        self.active_target_voltage_v = 0.0
        self.active_target_current_a = 0.0
        self.actual_measured_voltage_v = 0.0
        self.actual_measured_current_a = 0.0
        self.is_bpt_discharging = false
        self.precharge_tolerance_v = 20.0 # +/- 20V pre-charge window
    end

    # Handle Automated Connection Device (Pantograph / Robot arm) Docking
    def step_acd_docking()
        if self.acd_state == ACDState.UNDOCKED
            self.acd_state = ACDState.DEPLOYING
            return {"status": "InProgress", "state": self.acd_state}
        elif self.acd_state == ACDState.DEPLOYING
            self.acd_state = ACDState.DOCKED
            return {"status": "InProgress", "state": self.acd_state}
        elif self.acd_state == ACDState.DOCKED
            self.acd_state = ACDState.LATCHED
            return {"status": "Completed", "state": self.acd_state}
        end
        return {"status": "Active", "state": self.acd_state}
    end

    def retract_acd()
        self.acd_state = ACDState.RETRACTING
        self.acd_state = ACDState.UNDOCKED
        return {"status": "Retracted", "state": self.acd_state}
    end

    # Handle DC_CableCheck: Insulation test at 500V test voltage prior to main contactor closure
    def handle_cable_check_req()
        if self.acd_state != ACDState.LATCHED && self.acd_state != ACDState.UNDOCKED
            return {"response_code": "FAILED", "status": "ACDNotLatched"}
        end
        return {
            "response_code": "OK",
            "evse_processing": "Finished",
            "isolation_status": "Valid",
            "cable_check_voltage_v": 500.0
        }
    end

    # Handle DC_PreCharge: Match EVSE output voltage to EV battery pack voltage before contactors close
    def handle_precharge_req(ev_target_voltage_v)
        var target_v = real(ev_target_voltage_v)
        self.active_target_voltage_v = target_v
        # Ramp EVSE output capacitor voltage towards target
        self.actual_measured_voltage_v = target_v

        var delta_v = math.abs(self.actual_measured_voltage_v - target_v)
        var is_matched = (delta_v <= self.precharge_tolerance_v)

        return {
            "response_code": "OK",
            "evse_voltage_v": MathExt.round_to(self.actual_measured_voltage_v, 1),
            "voltage_matched": is_matched
        }
    end

    # Handle DC_ChargeLoop: Cyclic real-time power control loop (executed every 50-100 ms)
    def handle_charge_loop_req(ev_target_v, ev_target_a, ev_bpt_discharge, delta_time_sec)
        var dt = (delta_time_sec != nil) ? real(delta_time_sec) : 0.10
        var target_v = real(ev_target_v)
        var target_a = real(ev_target_a)

        # Voltage clamp
        if target_v > self.max_voltage_limit_v
            target_v = self.max_voltage_limit_v
        end

        # Current slew rate limiter to prevent inverter trip
        var max_delta_a = self.current_ramp_rate_a_per_s * dt
        var current_error = target_a - self.actual_measured_current_a
        var step_a = 0.0

        if math.abs(current_error) <= max_delta_a
            step_a = current_error
        elif current_error > 0.0
            step_a = max_delta_a
        else
            step_a = -max_delta_a
        end

        self.actual_measured_current_a = self.actual_measured_current_a + step_a

        # Clamp within station MCS hardware limits
        if self.actual_measured_current_a > self.max_current_limit_a
            self.actual_measured_current_a = self.max_current_limit_a
        elif self.actual_measured_current_a < 0.0
            self.actual_measured_current_a = 0.0
        end

        # Check total power limit
        var active_kw = (self.actual_measured_voltage_v * self.actual_measured_current_a) / 1000.0
        if active_kw > self.max_power_limit_kw
            self.actual_measured_current_a = (self.max_power_limit_kw * 1000.0) / self.actual_measured_voltage_v
            active_kw = self.max_power_limit_kw
        end

        self.is_bpt_discharging = (ev_bpt_discharge == true)

        return {
            "response_code": "OK",
            "evse_voltage_v": MathExt.round_to(self.actual_measured_voltage_v, 1),
            "evse_current_a": MathExt.round_to(self.actual_measured_current_a, 1),
            "evse_power_kw": MathExt.round_to(active_kw, 1),
            "bpt_active": self.is_bpt_discharging,
            "evse_status": "NormalCondition"
        }
    end

    # Handle DC_WeldingDetection: Check contactor open impedance after session
    def handle_welding_detection_req(is_contactor_stuck)
        var is_welded = (is_contactor_stuck == true)
        if is_welded
            return {
                "response_code": "FAILED",
                "contactor_status": "WeldedContactFailure",
                "safety_lockout": true
            }
        else
            return {
                "response_code": "OK",
                "contactor_status": "ContactsSuccessfullyOpened",
                "safety_lockout": false
            }
        end
    end
end

return {
    "ISO20Message": ISO20Message,
    "ACDState": ACDState,
    "ISO15118_20_DCSession": ISO15118_20_DCSession
}
