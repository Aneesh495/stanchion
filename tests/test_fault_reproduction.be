# Stanchion Test Suite: Regression Verification for Documented Defects & Edge Cases
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import math
import string
import types as Types
import meter as EnergyMeter
import charging_profile as ChargingProfileModule
import evse as EVSEChannel
import controller as StationController
import config as StationConfig
import global

var Profile = ChargingProfileModule["Profile"]
var CompositeCalc = ChargingProfileModule["CompositeCalculator"]

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

print(">>> Running test_fault_reproduction suite...")

# Bug 1 & 2: String Sizing & Byte Indexing
# Verifies that global size() and character byte indexing s[i] work accurately
var sample_str = "STANCHION_TEST"
assert_equal(size(sample_str), 14, "Bug 2 Fix: Builtin size() correctly returns string length")
var byte_val = string.byte(sample_str[1]) # 'T' = ASCII 84
assert_equal(byte_val, 84, "Bug 3 Fix: Character slice indexing s[i] before string.byte() returns correct ASCII byte")

# Bug 4: Map & List Type Checking
# Verifies that isinstance(obj, map) and isinstance(obj, list) identify Berry instances
var test_map = {"key": "value"}
var test_list = [1, 2, 3]
assert_true(isinstance(test_map, map), "Bug 4 Fix: isinstance(m, map) returns true")
assert_true(isinstance(test_list, list), "Bug 4 Fix: isinstance(l, list) returns true")
assert_equal(type(test_map), "instance", "type({}) returns 'instance' as expected in Berry")
assert_equal(classname(test_map), "map", "classname({}) returns 'map'")

# Bug 5: Global Namespace Mutation
# Verifies that mutating globals via import global functions properly without syntax error
import global
global.test_reproduction_counter = 42
assert_equal(global.test_reproduction_counter, 42, "Bug 5 Fix: import global namespace mutation succeeds")

# Bug 7: Energy Meter First Sample Timestamp at t=0
# Verifies that recording energy samples starting at t=0 does not skip the first interval
var meter = EnergyMeter(1)
meter.update_samples(230.0, 16.0, 230.0, 16.0, 230.0, 16.0, 1.0, 50.0, 0)
# Second sample 10 seconds later
meter.update_samples(230.0, 16.0, 230.0, 16.0, 230.0, 16.0, 1.0, 50.0, 10)
assert_true(meter.energy_import_total_kwh > 0.0, "Bug 7 Fix: Energy meter accumulates active energy starting from t=0")

# Bug 8: Charging Profile Schedule Offset with Zero Epoch Start
var p_zero = Profile(1, 1, "TxDefaultProfile", "Absolute", "A")
p_zero.add_period(0, 16.0, 3)
p_zero.add_period(3600, 32.0, 3)
var limit_t0 = CompositeCalc.calculate_composite_limit([p_zero], 0, 32.0)
var limit_t4000 = CompositeCalc.calculate_composite_limit([p_zero], 4000, 32.0)
assert_equal(limit_t0, 16.0, "Bug 8 Fix: Correct limit 16A at t=0 with schedule_start_epoch_sec=0")
assert_equal(limit_t4000, 32.0, "Bug 8 Fix: Correct limit 32A at t=4000 after period boundary")

# Bug 9: EVSE Channel State Machine Recovery After Emergency Stop
var cfg = StationConfig()
cfg.evse_count = 2
var station = StationController(cfg)
var evse1 = station.get_evse(1)
evse1.plug_in_vehicle()
evse1.authorize_and_start("TOKEN-REPRO-01", 1000)
assert_equal(evse1.fsm.current_state, Types.STATE_CHARGING, "EVSE in Charging state")

# Trigger Emergency Stop
station.press_emergency_stop()
assert_equal(evse1.fsm.current_state, Types.STATE_FAULTED, "Emergency stop transitioned EVSE to Faulted")
assert_equal(evse1.contactor.state, Types.CONTACTOR_OPEN, "Contactor opened on fault")

# Release Emergency Stop and verify recovery to Available state
station.release_emergency_stop()
assert_equal(evse1.fsm.current_state, Types.STATE_AVAILABLE, "Bug 9 Fix: Release emergency stop recovers EVSE to Available")

print("test_fault_reproduction: " + str(test_passed) + " passed, " + str(test_failed) + " failed")
if test_failed > 0
    import os
    os.exit(1)
end
