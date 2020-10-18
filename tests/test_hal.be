# Stanchion Test Suite: Hardware Abstraction Layer & Safety Supervisors
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import types as Types
import pilot as ControlPilot
import meter as EnergyMeter
import contactor as Contactor
import safety as SafetySupervisor
import lock as ConnectorLock
import display as StationDisplay
import adc_filter as ADCFilter
import math
import string
import global

var total_assertions = 0

def check(condition, desc)
    global.total_assertions = global.total_assertions + 1
    if !condition
        print("[FAIL] " + desc)
        assert(false)
    end
end

print(">>> Running test_hal.be ...")

# 1. Control Pilot Tests
var pilot = ControlPilot(1)
check(pilot.get_state() == Types.PILOT_STATE_A, "Pilot starts in State A (12V)")
check(!pilot.is_vehicle_connected(), "Vehicle not connected in State A")

# Plug in vehicle (9V detected -> State B)
var changed = pilot.update_pilot_measurement(9.0, 1000)
check(changed == true, "Pilot measurement update detected change")
check(pilot.get_state() == Types.PILOT_STATE_B, "Pilot transitioned to State B (9V)")
check(pilot.is_vehicle_connected(), "Vehicle connected in State B")
check(!pilot.is_charging_requested(), "Charging not yet requested in State B")

# Vehicle requests charging (6V detected -> State C)
pilot.update_pilot_measurement(6.0, 2000)
check(pilot.get_state() == Types.PILOT_STATE_C, "Pilot transitioned to State C (6V)")
check(pilot.is_charging_requested(), "Charging requested in State C")

# Set charging current to 16A -> Check duty cycle
pilot.set_charging_current_limit(16.0)
var duty = pilot.get_duty_cycle()
# 16A / 0.6 = 26.666% duty cycle
check(math.abs(duty - 0.2666) < 0.005, "16A translates to ~26.7% PWM duty")

# Test Proximity Pilot Resistance decoding
check(ControlPilot.decode_proximity_resistance(1500) == 13.0, "1500 Ohm = 13A cable")
check(ControlPilot.decode_proximity_resistance(680) == 20.0,  "680 Ohm = 20A cable")
check(ControlPilot.decode_proximity_resistance(220) == 32.0,  "220 Ohm = 32A cable")
check(ControlPilot.decode_proximity_resistance(100) == 63.0,  "100 Ohm = 63A cable")

# 2. Energy Meter Tests
var meter = EnergyMeter(1)
# 230V, 32A per phase, pf 1.0 at t=0
meter.update_samples(230.0, 32.0, 230.0, 32.0, 230.0, 32.0, 1.0, 50.0, 0)
var p_total = meter.get_total_active_power_kw()
check(math.abs(p_total - 22.08) < 0.01, "3x 230Vx32A = 22.08 kW")

# Advance 1800 seconds (0.5 hour) at 22.08 kW -> 11.04 kWh accumulated
meter.update_samples(230.0, 32.0, 230.0, 32.0, 230.0, 32.0, 1.0, 50.0, 1800)
var snap = meter.get_meter_value_snapshot()
check(math.abs(snap["energy_active_import_kwh"] - 11.04) < 0.02, "0.5 hr accumulation = 11.04 kWh")

# 3. Contactor & Weld Detection
var contactor = Contactor(1)
check(contactor.is_open(), "Contactor starts Open")
check(contactor.close(1000) == true, "Command close succeeds")
check(contactor.is_closed(), "Contactor reports Closed")
contactor.update_hardware_feedback(true, true)
check(!contactor.is_welded(), "No weld when commanded closed and feedback closed")

contactor.open(2000)
check(contactor.is_open(), "Contactor commanded open")
# Simulate weld: commanded open, but aux contact remains closed and downstream voltage detected!
var weld_result = contactor.update_hardware_feedback(true, true)
check(weld_result == false, "Weld check flagged fault")
check(contactor.is_welded(), "Contactor flagged as welded")
check(contactor.close(3000) == false, "Refuses to close welded contactor")

# 4. Safety Supervisor Tests
var safety = SafetySupervisor(1, 32.0)
# Nominal conditions
var ok = safety.evaluate_safety(2.0, 0.5, 30.0, 230.0, 35.0, 32.0, 1.0)
check(ok == true, "Nominal safety checks pass")
check(!safety.has_tripped(), "Safety supervisor not tripped")

# DC leakage fault (>= 6 mA)
var dc_trip = safety.evaluate_safety(2.0, 7.5, 30.0, 230.0, 35.0, 32.0, 1.0)
check(dc_trip == false, "DC leakage >= 6mA trips safety supervisor")
check(safety.has_tripped(), "Safety supervisor latched trip")
safety.clear_trips_technician()

# Over-temperature derating test
safety.evaluate_safety(0.0, 0.0, 10.0, 230.0, 75.0, 70.0, 1.0) # 75 C is halfway between 65 C and 85 C
var derate = safety.get_thermal_derating_factor()
check(math.abs(derate - 0.50) < 0.01, "75 C thermal derates to 50% capacity")

# Emergency Stop
safety.press_emergency_stop()
check(safety.evaluate_safety(0.0, 0.0, 0.0, 230.0, 25.0, 25.0, 1.0) == false, "E-Stop active trips safety")
safety.release_emergency_stop()
safety.clear_trips_technician()

# 5. Connector Lock Tests
var lock = ConnectorLock(1)
check(!lock.is_connector_locked(), "Starts unlocked")
check(lock.lock() == true, "Lock engaged")
check(lock.is_connector_locked(), "Reports locked")
check(lock.unlock() == true, "Unlock disengaged")
check(!lock.is_connector_locked(), "Reports unlocked")

# 6. ADC Filter Tests
var adc = ADCFilter("pilot_adc", 6, 0.3)
adc.update(9.0)
adc.update(9.1)
adc.update(8.9)
adc.update(9.0)
adc.update(25.0) # Noise spike outlier
var filtered = adc.update(9.0)
check(math.abs(filtered - 9.0) < 0.5, "Outlier rejection discarded 25V noise spike")

print(string.format("[PASS] test_hal.be passed with %d assertions verified.", total_assertions))
