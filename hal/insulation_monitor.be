# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# High Voltage DC Insulation Monitoring Device (IMD) Simulator (IEC 61851-23)
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import math
import math_ext as MathExt

# IMD Operational States
class IMDState
    static var INITIALIZING   = "INITIALIZING"
    static var SELF_TESTING   = "SELF_TESTING"
    static var MONITORING     = "MONITORING"
    static var WARNING        = "WARNING"
    static var FAULT_TRIPPED  = "FAULT_TRIPPED"
end

# Insulation Monitoring Device (Bender A-ISOMETER Architecture)
class InsulationMonitor
    var nominal_dc_voltage_v
    var warning_threshold_ohms_per_v
    var fault_threshold_ohms_per_v
    var earth_capacitance_uf
    var current_state
    var resistance_pos_to_pe_kohm
    var resistance_neg_to_pe_kohm
    var total_equivalent_r_kohm
    var is_symmetrical_fault
    var self_test_passed
    var measurement_settled
    var sample_counter

    def init(nominal_voltage_v)
        self.nominal_dc_voltage_v = (nominal_voltage_v != nil) ? real(nominal_voltage_v) : 800.0
        self.warning_threshold_ohms_per_v = 500.0 # 500 Ohm/V warning limit
        self.fault_threshold_ohms_per_v = 100.0   # 100 Ohm/V critical shutdown limit
        self.earth_capacitance_uf = 2.0           # 2 uF earth capacitance
        self.current_state = IMDState.INITIALIZING
        self.resistance_pos_to_pe_kohm = 5000.0   # 5 MOhm healthy baseline
        self.resistance_neg_to_pe_kohm = 5000.0   # 5 MOhm healthy baseline
        self.total_equivalent_r_kohm = 2500.0
        self.is_symmetrical_fault = false
        self.self_test_passed = false
        self.measurement_settled = true
        self.sample_counter = 0
    end

    # Run IMD internal calibration and relay self-test
    def run_self_test()
        self.current_state = IMDState.SELF_TESTING
        # Simulate injection of internal calibration test impedance
        var internal_test_ok = (self.nominal_dc_voltage_v > 0.0)
        if internal_test_ok
            self.self_test_passed = true
            self.current_state = IMDState.MONITORING
            return {"status": "Passed", "error": nil}
        else
            self.self_test_passed = false
            self.current_state = IMDState.FAULT_TRIPPED
            return {"status": "Failed", "error": "InternalHardwareFault"}
        end
    end

    # Set real-time insulation resistance values for DC+ and DC- to protective earth
    def update_insulation_sample(r_pos_kohm, r_neg_kohm, bus_voltage_v)
        self.sample_counter = self.sample_counter + 1
        var rp = real(r_pos_kohm)
        var rn = real(r_neg_kohm)
        var v_dc = (bus_voltage_v != nil) ? real(bus_voltage_v) : self.nominal_dc_voltage_v
        if v_dc < 1.0 v_dc = 1.0 end

        self.resistance_pos_to_pe_kohm = rp
        self.resistance_neg_to_pe_kohm = rn

        # Parallel equivalent insulation resistance: R_iso = (R_pos * R_neg) / (R_pos + R_neg)
        var r_equiv = 0.0
        if (rp + rn) > 0.001
            r_equiv = (rp * rn) / (rp + rn)
        end
        self.total_equivalent_r_kohm = r_equiv

        # Symmetrical vs Asymmetrical determination
        var ratio = (rp > rn) ? (rp / (rn + 0.001)) : (rn / (rp + 0.001))
        self.is_symmetrical_fault = (ratio < 1.5)

        # Calculate Ohms per Volt
        var r_ohms_per_volt = (r_equiv * 1000.0) / v_dc

        # State transition evaluation
        if r_ohms_per_volt < self.fault_threshold_ohms_per_v
            self.current_state = IMDState.FAULT_TRIPPED
        elif r_ohms_per_volt < self.warning_threshold_ohms_per_v
            self.current_state = IMDState.WARNING
        else
            self.current_state = IMDState.MONITORING
        end

        return {
            "state": self.current_state,
            "r_pos_kohm": MathExt.round_to(rp, 1),
            "r_neg_kohm": MathExt.round_to(rn, 1),
            "total_r_kohm": MathExt.round_to(r_equiv, 1),
            "ohms_per_volt": MathExt.round_to(r_ohms_per_volt, 1),
            "is_symmetrical": self.is_symmetrical_fault,
            "is_trip": (self.current_state == IMDState.FAULT_TRIPPED),
            "is_warning": (self.current_state == IMDState.WARNING)
        }
    end

    def reset_fault()
        if self.self_test_passed
            self.current_state = IMDState.MONITORING
            return true
        end
        return false
    end
end

return {
    "IMDState": IMDState,
    "InsulationMonitor": InsulationMonitor
}
