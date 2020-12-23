# Stanchion Test Suite: Fast Frequency Response & Grid Droop Regulation
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import freq_regulation as FrequencyRegulationController
import math
import string
import global

var test_passed = 0
var test_failed = 0

def assert_true(cond, msg)
    if cond
        test_passed = test_passed + 1
    else
        test_failed = test_failed + 1
        print("FAIL: " + str(msg))
    end
end

def assert_equal(a, b, msg)
    if a == b
        test_passed = test_passed + 1
    else
        test_failed = test_failed + 1
        print("FAIL: " + str(msg) + " (expected " + str(b) + ", got " + str(a) + ")")
    end
end

print(">>> Running test_freq_regulation suite...")

var reg = FrequencyRegulationController(50.0, 100.0) # 50 Hz nominal, 100 kW capacity

# 1. Deadband Check (50.01 Hz)
var db_res = reg.calculate_regulation_delta_kw(50.01, 1000)
assert_equal(db_res["delta_kw"], 0.0, "Frequency inside 20 mHz deadband commands 0 kW delta")
assert_equal(db_res["action"], "STANDBY", "Action is STANDBY")

# 2. Moderate Under-Frequency (49.90 Hz, 100 mHz drop)
# eff_delta_f = -0.10 + 0.02 = -0.08 Hz.
# Droop = 4% (0.04). Delta P = - (1 / 0.04) * (-0.08 / 50.0) * 100 = 25 * 0.0016 * 100 = +4.0 kW
var under_res = reg.calculate_regulation_delta_kw(49.90, 1001)
assert_true(under_res["delta_kw"] > 3.9 && under_res["delta_kw"] < 4.1, "Delta P is approximately +4.0 kW")
assert_true(reg.is_underfrequency_alarm, "Under-frequency alarm raised")
assert_equal(under_res["action"], "DISCHARGING_SUPPORT", "Action is DISCHARGING_SUPPORT")

# 3. Dynamic EV Power Modulation & V2G Injection
# Baseline EV load = 10 kW. Under-frequency requires +20 kW reduction.
# EV charging throttles to 0 kW, and remaining 10 kW is injected via V2G!
var adj_res = reg.adjust_ev_charging_power(10.0, 49.50, 10.0, 1002)
assert_equal(adj_res["adjusted_kw"], 0.0, "EV load curtailed to 0 kW")
assert_true(adj_res["v2g_injection_kw"] > 0.0, "V2G injection activated to support grid")
assert_true(adj_res["cumulative_injected_kwh"] > 0.0, "Cumulative injected energy tracked")

# 4. Over-Frequency Surplus Absorption (50.20 Hz)
var over_res = reg.adjust_ev_charging_power(20.0, 50.20, 10.0, 1003)
assert_true(over_res["adjusted_kw"] > 20.0, "EV charge rate boosted to absorb surplus power")
assert_true(over_res["cumulative_absorbed_kwh"] > 0.0, "Cumulative absorbed energy tracked")

# 5. Critical RoCoF Emergency Trip
# Sudden 0.60 Hz frequency drop in 1 second (RoCoF = -0.60 Hz/s > 0.50 limit)
var rocof_res = reg.calculate_regulation_delta_kw(49.40, 1004)
assert_true(rocof_res["is_critical"], "Critical RoCoF detected")
assert_equal(rocof_res["delta_kw"], 100.0, "Commands full 100 kW emergency support")

print("test_freq_regulation: " + str(test_passed) + " passed, " + str(test_failed) + " failed")
if test_failed > 0
    import os
    os.exit(1)
end
