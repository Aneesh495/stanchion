# Stanchion Test Suite: DC Insulation Monitoring Device (IMD)
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import insulation_monitor as IMDModule
import math
import string
import global

var IMDState = IMDModule["IMDState"]
var InsulationMonitor = IMDModule["InsulationMonitor"]

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

print(">>> Running test_insulation_monitor suite...")

var imd = InsulationMonitor(800.0) # 800V DC fast charging bus

# 1. Self Test
assert_equal(imd.current_state, IMDState.INITIALIZING, "Initial state is INITIALIZING")
var st_res = imd.run_self_test()
assert_equal(st_res["status"], "Passed", "Self-test passed")
assert_equal(imd.current_state, IMDState.MONITORING, "State transitioned to MONITORING")

# 2. Healthy Insulation Baseline (5000 kOhm on both rails)
var res_healthy = imd.update_insulation_sample(5000.0, 5000.0, 800.0)
assert_equal(res_healthy["state"], IMDState.MONITORING, "Healthy insulation stays in MONITORING")
assert_true(res_healthy["ohms_per_volt"] > 3000.0, "Insulation exceeds 3000 Ohm/V")
assert_true(!res_healthy["is_warning"], "No warning on healthy line")
assert_true(!res_healthy["is_trip"], "No trip on healthy line")

# 3. Symmetrical Degradation Warning (300 kOhm on both rails at 800V = 150 kOhm total = 187.5 Ohm/V)
# Between 100 Ohm/V and 500 Ohm/V: Warning zone
var res_warn = imd.update_insulation_sample(300.0, 300.0, 800.0)
assert_equal(res_warn["state"], IMDState.WARNING, "Warning state reached")
assert_true(res_warn["is_warning"], "Warning flag active")
assert_true(res_warn["is_symmetrical"], "Detected symmetrical insulation degradation")

# 4. Critical Asymmetrical DC+ Ground Fault (40 kOhm on DC+ vs 5000 kOhm on DC-)
# Equivalent R = 39.7 kOhm at 800V = 49.6 Ohm/V < 100 Ohm/V fault limit
var res_trip = imd.update_insulation_sample(40.0, 5000.0, 800.0)
assert_equal(res_trip["state"], IMDState.FAULT_TRIPPED, "Critical fault state reached")
assert_true(res_trip["is_trip"], "Trip flag set")
assert_true(!res_trip["is_symmetrical"], "Identified asymmetrical single-pole fault")

# 5. Recovery & Fault Reset
var res_recovered = imd.update_insulation_sample(5000.0, 5000.0, 800.0)
assert_equal(res_recovered["state"], IMDState.MONITORING, "State recovered to MONITORING once fault cleared")

print("test_insulation_monitor: " + str(test_passed) + " passed, " + str(test_failed) + " failed")
if test_failed > 0
    import os
    os.exit(1)
end
