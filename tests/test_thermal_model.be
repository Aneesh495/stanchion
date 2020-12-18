# Stanchion Test Suite: Transformer & Busbar Thermal Aging Model (IEC 60076-7)
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import thermal_model as TransformerThermalModel
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

print(">>> Running test_thermal_model suite...")

var model = TransformerThermalModel(250.0) # 250 kVA transformer

# 1. Arrhenius Relative Loss of Life Aging Rate Tests
var v_rated = model.compute_relative_aging_rate(110.0)
assert_true(math.abs(v_rated - 1.0) < 0.05, "At 110 C rated hot-spot, relative aging rate V is approximately 1.0")

var v_cool = model.compute_relative_aging_rate(90.0)
assert_true(v_cool < 0.20, "At 90 C, relative aging is below 0.20x")

var v_hot = model.compute_relative_aging_rate(130.0)
assert_true(v_hot > 3.5, "At 130 C, relative aging is above 3.5x accelerated degradation")

# 2. Ambient Temperature Adjustment
model.set_ambient_temperature(35.0)
assert_equal(model.ambient_temp_c, 35.0, "Ambient temperature set to 35 C heatwave")

# 3. Dynamic Thermal Stepping Under Normal Load (K = 0.8)
var res_normal = model.step_thermal(200.0, 300.0) # 5 minutes at 200 kVA
assert_true(res_normal["curtailment_factor"] == 1.0, "No curtailment under normal load")
assert_true(!res_normal["is_thermal_warning"], "No thermal warning")
assert_true(res_normal["cumulative_aging_hours"] > 0.0, "Cumulative aging tracked")

# 4. Severe Overload Stepping (K = 1.6)
# Drive hot-spot temperature up to test thermal curtailment governor
model.current_top_oil_temp_c = 95.0
model.current_hotspot_temp_c = 120.0 # Above 115 C warning threshold
var res_warn = model.step_thermal(400.0, 60.0)

assert_true(res_warn["is_thermal_warning"], "Thermal warning triggered above 115 C")
assert_true(res_warn["curtailment_factor"] < 1.0, "Curtailment factor throttles load below 1.0")
assert_true(res_warn["curtailment_factor"] > 0.0, "Curtailment maintains partial power in warning zone")

# 5. Emergency Trip Stepping (Hot-spot >= 135 C)
model.current_hotspot_temp_c = 136.0
var res_trip = model.step_thermal(400.0, 60.0)
assert_true(res_trip["is_thermal_trip"], "Emergency thermal trip triggered at 136 C")
assert_equal(res_trip["curtailment_factor"], 0.0, "Curtailment drops setpoint to 0.0A")

print("test_thermal_model: " + str(test_passed) + " passed, " + str(test_failed) + " failed")
if test_failed > 0
    import os
    os.exit(1)
end
