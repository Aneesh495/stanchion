# Stanchion Test Suite: Multi-Physics Grid Stress & Megawatt MCS Scenarios
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import grid_stress_scenarios as StressRunner
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

print(">>> Running test_grid_stress_scenarios suite...")

# 1. Substation Voltage Sag Brownout Scenario
var sag_res = StressRunner.run_substation_voltage_sag_scenario()
assert_true(sag_res["success"], "Substation brownout successfully throttled DLM allocations")
assert_true(sag_res["derated_allocated_amps"] <= sag_res["derated_capacity_a"] + 0.1, "Allocations within derated capacity")

# 2. Solar Transient Cloud Dip Buffered by BESS Scenario
var solar_res = StressRunner.run_solar_cloud_transient_scenario()
assert_true(solar_res["success"], "BESS seamlessly buffered sudden solar drop with zero grid import")
assert_equal(solar_res["cloud_grid_import_kw"], 0.0, "Zero grid import during solar drop")
assert_true(solar_res["cloud_bess_discharge_kw"] >= 34.9, "BESS discharged 35 kW deficit")

# 3. Megawatt MCS High-Power Truck Depot Scenario
var mcs_res = StressRunner.run_megawatt_mcs_depot_scenario()
assert_true(mcs_res["success"], "Megawatt MCS charging coordinated with cable chiller and transformer model")
assert_true(mcs_res["pump_pwm_pct"] >= 80.0, "Chiller pump operated above 80% PWM for 800A load")
assert_equal(mcs_res["curtailment_factor"], 1.0, "Transformer thermal model maintained 1.0 factor under normal load")

print("test_grid_stress_scenarios: " + str(test_passed) + " passed, " + str(test_failed) + " failed")
if test_failed > 0
    import os
    os.exit(1)
end
