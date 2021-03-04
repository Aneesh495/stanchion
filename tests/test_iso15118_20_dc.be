# Stanchion Test Suite: ISO 15118-20 DC & Megawatt Charging System (MCS)
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import iso15118_20_dc as ISO20DCModule
import math
import string
import global

var ISO20Message = ISO20DCModule["ISO20Message"]
var ACDState = ISO20DCModule["ACDState"]
var ISO15118_20_DCSession = ISO20DCModule["ISO15118_20_DCSession"]

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

print(">>> Running test_iso15118_20_dc suite...")

var session = ISO15118_20_DCSession(1, 1500.0, 1000.0, 1200.0) # 1500A, 1000V, 1.2 MW MCS

# 1. Automated Connection Device (Pantograph) Docking
assert_equal(session.acd_state, ACDState.UNDOCKED, "ACD starts in UNDOCKED state")
var dock1 = session.step_acd_docking()
assert_equal(session.acd_state, ACDState.DEPLOYING, "ACD in DEPLOYING state")
var dock2 = session.step_acd_docking()
assert_equal(session.acd_state, ACDState.DOCKED, "ACD in DOCKED state")
var dock3 = session.step_acd_docking()
assert_equal(session.acd_state, ACDState.LATCHED, "ACD in LATCHED state")
assert_equal(dock3["status"], "Completed", "Pantograph docking completed")

# 2. DC Cable Check
var cc_res = session.handle_cable_check_req()
assert_equal(cc_res["response_code"], "OK", "Cable check passed")
assert_equal(cc_res["cable_check_voltage_v"], 500.0, "Cable check performed at 500V")

# 3. DC Pre-Charge Matching (EV battery at 720.0V)
var pre_res = session.handle_precharge_req(720.0)
assert_equal(pre_res["response_code"], "OK", "Pre-charge response OK")
assert_equal(pre_res["evse_voltage_v"], 720.0, "EVSE voltage matched battery pack at 720V")
assert_true(pre_res["voltage_matched"], "Voltage matched within tolerance")

# 4. Megawatt Fast Charging Loop & Slew Rate Limiting
# Target 1000A. At 150 A/s with dt = 1.0s, first step should ramp up to 150A
var loop1 = session.handle_charge_loop_req(720.0, 1000.0, false, 1.0)
assert_equal(loop1["response_code"], "OK", "Charge loop response OK")
assert_equal(loop1["evse_current_a"], 150.0, "Current ramp rate limited to 150 A/s")

# Next 5 seconds (5 * 150 = 750A): total = 150 + 750 = 900A
var loop2 = session.handle_charge_loop_req(720.0, 1000.0, false, 5.0)
assert_equal(loop2["evse_current_a"], 900.0, "Ramped to 900A")

# Final step reaches 1000A (1000A * 720V = 720 kW)
var loop3 = session.handle_charge_loop_req(720.0, 1000.0, false, 1.0)
assert_equal(loop3["evse_current_a"], 1000.0, "Target current 1000A reached")
assert_equal(loop3["evse_power_kw"], 720.0, "Power delivered is 720 kW")

# 5. Welding Detection (Healthy contacts vs welded contactor)
var weld_ok = session.handle_welding_detection_req(false)
assert_equal(weld_ok["response_code"], "OK", "Welding check passed for normal contacts")
assert_true(!weld_ok["safety_lockout"], "No lockout on healthy contactor")

var weld_fail = session.handle_welding_detection_req(true)
assert_equal(weld_fail["response_code"], "FAILED", "Welding failure detected for stuck contacts")
assert_true(weld_fail["safety_lockout"], "Safety lockout triggered")

# 6. Pantograph Retraction
var ret_res = session.retract_acd()
assert_equal(ret_res["state"], ACDState.UNDOCKED, "Pantograph retracted to UNDOCKED")

print("test_iso15118_20_dc: " + str(test_passed) + " passed, " + str(test_failed) + " failed")
if test_failed > 0
    import os
    os.exit(1)
end
