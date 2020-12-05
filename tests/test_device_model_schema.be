# Stanchion Test Suite: OCPP 2.0.1 Device Model Schema & Variable Catalog
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import device_model_schema as SchemaModule
import math
import string
import global

var DataTypeCode = SchemaModule["DataTypeCode"]
var Mutability = SchemaModule["Mutability"]
var VariableCharacteristic = SchemaModule["VariableCharacteristic"]
var DeviceModelCatalog = SchemaModule["DeviceModelCatalog"]

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

print(">>> Running test_device_model_schema suite...")

var catalog = DeviceModelCatalog()
var comps = catalog.list_components()
assert_true(size(comps) >= 8, "Catalog contains at least 8 standard components")

# 1. Component & Variable Query Tests
var cs_vars = catalog.list_variables("ChargingStation")
assert_true(size(cs_vars) >= 5, "ChargingStation has at least 5 standard variables")

var evse_vars = catalog.list_variables("EVSE")
assert_true(size(evse_vars) >= 4, "EVSE has at least 4 standard variables")

var hb_char = catalog.get_characteristic("OCPPCommCtrl", "HeartbeatInterval")
assert_true(hb_char != nil, "Retrieved HeartbeatInterval characteristic")
assert_equal(hb_char.data_type, DataTypeCode.INTEGER, "HeartbeatInterval is integer type")
assert_equal(hb_char.mutability, Mutability.READ_WRITE, "HeartbeatInterval is read-write")
assert_equal(hb_char.unit, "s", "HeartbeatInterval unit is seconds")
assert_equal(hb_char.min_limit, 1, "Min limit is 1")
assert_equal(hb_char.max_limit, 86400, "Max limit is 86400")

# 2. Integer Range Validation
var v_int_ok = catalog.validate("OCPPCommCtrl", "HeartbeatInterval", 60)
assert_true(v_int_ok["valid"], "60s is valid heartbeat interval")

var v_int_low = catalog.validate("OCPPCommCtrl", "HeartbeatInterval", 0)
assert_true(!v_int_low["valid"], "0s rejected as below min limit 1")
assert_equal(v_int_low["reason"], "ValueBelowMinimum", "Reported ValueBelowMinimum")

var v_int_high = catalog.validate("OCPPCommCtrl", "HeartbeatInterval", 999999)
assert_true(!v_int_high["valid"], "999999s rejected as above max limit")
assert_equal(v_int_high["reason"], "ValueAboveMaximum", "Reported ValueAboveMaximum")

# 3. Decimal Range Validation
var v_dec_ok = catalog.validate("EVSE", "CurrentLimit", 32.0)
assert_true(v_dec_ok["valid"], "32.0A is valid current limit")

var v_dec_high = catalog.validate("EVSE", "CurrentLimit", 600.0)
assert_true(!v_dec_high["valid"], "600A rejected as above 500A max limit")

# 4. Boolean Validation
var v_bool_ok = catalog.validate("SmartChargingCtrl", "Enabled", true)
assert_true(v_bool_ok["valid"], "Boolean true is valid")

var v_bool_bad = catalog.validate("SmartChargingCtrl", "Enabled", "NotABoolean")
assert_true(!v_bool_bad["valid"], "Arbitrary string rejected for boolean variable")

# 5. OptionList Enum Validation
var v_opt_ok = catalog.validate("ControlPilot", "State", "C")
assert_true(v_opt_ok["valid"], "Pilot state C is valid option")

var v_opt_bad = catalog.validate("ControlPilot", "State", "Z")
assert_true(!v_opt_bad["valid"], "Pilot state Z rejected as not in options list")
assert_equal(v_opt_bad["reason"], "ValueNotInOptionsList", "Reported ValueNotInOptionsList")

# 6. Unknown Component / Variable
var v_unknown_comp = catalog.validate("WarpDrive", "OutputPower", 100)
assert_true(!v_unknown_comp["valid"], "Unknown component rejected")
assert_equal(v_unknown_comp["reason"], "UnknownComponentOrVariable", "Reported UnknownComponentOrVariable")

print("test_device_model_schema: " + str(test_passed) + " passed, " + str(test_failed) + " failed")
if test_failed > 0
    import os
    os.exit(1)
end
