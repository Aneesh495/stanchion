# Stanchion Test Suite: Liquid-Cooled Cable & Converter Chiller
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import cooling_loop as ChillerModule
import math
import string
import global

var CoolingLoopState = ChillerModule["CoolingLoopState"]
var CoolingLoopController = ChillerModule["CoolingLoopController"]

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

print(">>> Running test_cooling_loop suite...")

var chiller = CoolingLoopController()

# 1. Standby Idle Circulation (< 30A)
var res_idle = chiller.step_cooling(10.0, 1.0)
assert_equal(res_idle["state"], CoolingLoopState.STANDBY, "Idle state is STANDBY")
assert_equal(res_idle["pump_pwm_pct"], 20.0, "Idle pump PWM is 20%")
assert_equal(res_idle["derating_factor"], 1.0, "No derating on idle")

# 2. High Current Charging (400A)
var res_400a = chiller.step_cooling(400.0, 5.0)
assert_equal(res_400a["state"], CoolingLoopState.RUNNING, "High current transitions to RUNNING")
assert_true(res_400a["pump_pwm_pct"] > 80.0, "Pump PWM modulated above 80%")
assert_equal(res_400a["derating_factor"], 1.0, "Healthy temperatures maintain 1.0 derating factor")

# 3. Thermal Warning Derating (Simulate connector pin reaching 82 C)
chiller.connector_pin_pos_temp_c = 82.0
var res_warn = chiller.step_cooling(400.0, 1.0)
assert_equal(res_warn["state"], CoolingLoopState.WARNING, "Warning state active at 82 C")
assert_true(res_warn["derating_factor"] < 1.0, "Current throttled below 1.0")
assert_true(res_warn["derating_factor"] > 0.0, "Maintains partial power")
assert_equal(res_warn["alarm"], "ConnectorThermalWarning", "Reported ConnectorThermalWarning")

# 4. Over-Temperature Safety Trip (Connector pin reaches 91 C)
chiller.connector_pin_pos_temp_c = 91.0
var res_trip = chiller.step_cooling(400.0, 1.0)
assert_equal(res_trip["state"], CoolingLoopState.FAULT_TRIPPED, "State tripped to FAULT_TRIPPED")
assert_equal(res_trip["derating_factor"], 0.0, "Derating drops current to 0.0A")
assert_equal(res_trip["alarm"], "ConnectorOverTemperatureTrip", "Reported ConnectorOverTemperatureTrip")

# 5. Pressure Loss / Leak Detection (< 0.8 Bar)
var leak_chiller = CoolingLoopController()
leak_chiller.coolant_pressure_bar = 0.50 # Leak pressure drop
var res_leak = leak_chiller.step_cooling(200.0, 1.0)
assert_equal(res_leak["state"], CoolingLoopState.FAULT_TRIPPED, "Leak pressure drops to FAULT_TRIPPED")
assert_equal(res_leak["alarm"], "LeakageDetectedUnderPressure", "Reported LeakageDetectedUnderPressure")

# 6. Flow Loss / Pump Stall (< 1.5 LPM under load)
var stall_chiller = CoolingLoopController()
stall_chiller.coolant_flow_rate_lpm = 0.8 # Severe flow restriction
var res_stall = stall_chiller.step_cooling(150.0, 1.0)
assert_equal(res_stall["state"], CoolingLoopState.FAULT_TRIPPED, "Pump stall drops to FAULT_TRIPPED")
assert_equal(res_stall["alarm"], "FlowRateLossPumpStall", "Reported FlowRateLossPumpStall")

print("test_cooling_loop: " + str(test_passed) + " passed, " + str(test_failed) + " failed")
if test_failed > 0
    import os
    os.exit(1)
end
