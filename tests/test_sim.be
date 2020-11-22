# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Unit & Integration Tests: Simulation Models & Microgrid Scenarios
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import math
import math_ext as MathExt
import ev_battery as EVBattery
import grid_feed as GridFeed
import solar_sim as SolarSim
import central_system_mock as CentralSystemMock
import scenarios as ScenarioRunner

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

def assert_almost_equal(a, b, eps, msg)
    if math.abs(real(a) - real(b)) <= real(eps)
        test_passed = test_passed + 1
    else
        test_failed = test_failed + 1
        print("FAIL: " + str(msg) + " (expected " + str(b) + ", got " + str(a) + ")")
    end
end

print(">>> Running test_sim suite...")

# 1. EV Battery CC/CV Model Tests
var bat = EVBattery("TEST-EV-01", 75.0, 50.0, 11.0)
assert_almost_equal(bat.get_max_acceptable_power_kw(), 11.0, 0.01, "CC phase accepts full 11 kW")

# Charge in CC phase for 1 hour at 11 kW
var res1 = bat.step_charge(11.0, 3600.0)
assert_almost_equal(res1["actual_power_kw"], 11.0, 0.05, "Step charge drew 11 kW")
assert_true(bat.current_soc_pct > 64.0, "SoC increased after 1 hour")
assert_true(res1["temperature_c"] >= 25.0, "Battery temperature increased from Joule heating")

# Test CV taper at 90% SoC
bat.current_soc_pct = 90.0
var cv_power = bat.get_max_acceptable_power_kw()
assert_true(cv_power < 11.0 && cv_power > 1.0, "CV phase tapers power below 11 kW")

# Test 100% SoC
bat.current_soc_pct = 100.0
assert_almost_equal(bat.get_max_acceptable_power_kw(), 0.0, 0.01, "Full battery accepts 0 kW")

# 2. Grid Feeder Impedance & Voltage Sag Tests
var grid = GridFeed(230.0, 250.0)
var grid_res1 = grid.step_grid(0.0, 0.0, 1.0, 12)
assert_almost_equal(grid_res1["service_voltage_v"], 230.0, 0.05, "Zero EV load has zero voltage drop")

# Heavy EV load: 150 Amps at 0.95 power factor
var grid_res2 = grid.step_grid(100.0, 150.0, 0.95, 14)
assert_true(grid_res2["voltage_drop_v"] > 1.5, "Feeder experiences measurable voltage drop under 150A")
assert_true(grid_res2["service_voltage_v"] < 230.0, "Service voltage sags under heavy load")
assert_true(grid_res2["transformer_loading_pct"] > 40.0, "Transformer loading reflects total load")

# 3. Solar PV & Inverter Derating Tests
var solar = SolarSim(50.0, 45.0, 37.77)

# Night test (hour 0.0)
var ghi_night = solar.compute_solar_irradiance_w_m2(172, 0.0)
assert_almost_equal(ghi_night, 0.0, 0.01, "Night solar irradiance is 0 W/m^2")

# Solar noon test (hour 12.0)
var step_noon = solar.step_solar(172, 12.0, 300.0)
assert_true(step_noon["ghi_w_m2"] > 700.0, "Noon clear-sky irradiance exceeds 700 W/m^2")
assert_true(step_noon["ac_power_kw"] > 25.0, "Solar AC power exceeds 25 kW at noon")
assert_true(step_noon["energy_yield_kwh"] > 0.0, "Cumulative energy yield accumulates")

# Cloud attenuation test
solar.set_cloud_factor(0.30)
var ghi_cloud = solar.compute_solar_irradiance_w_m2(172, 12.0)
assert_true(ghi_cloud < step_noon["ghi_w_m2"] * 0.40, "Clouds attenuate solar irradiance")

# Inverter clipping test with oversized array
var big_solar = SolarSim(100.0, 30.0, 37.77)
var step_clip = big_solar.step_solar(172, 12.0, 300.0)
assert_almost_equal(step_clip["ac_power_kw"], 30.0, 0.05, "Inverter clips at 30 kW rating")
assert_true(step_clip["is_clipping"], "Clipping flag is set")

# 4. Mock OCPP 2.0.1 Central System (CSMS) Tests
var csms = CentralSystemMock()
var boot_req = '[2, "msg-001", "BootNotification", {"reason": "PowerUp", "chargingStation": {"model": "Stanchion-3P", "vendorName": "Stanchion"}}]'
var boot_reply = csms.handle_station_frame(boot_req)
assert_true(boot_reply != nil, "CSMS handled BootNotification")
assert_true(csms.count_received_action("BootNotification") == 1, "Counted 1 BootNotification")

# Test Authorize valid token
var auth_req_ok = '[2, "msg-002", "Authorize", {"idToken": {"idToken": "FLEET-VAN-01", "type": "ISO14443"}}]'
var auth_reply_ok = csms.handle_station_frame(auth_req_ok)
assert_true(auth_reply_ok != nil, "CSMS answered Authorize")

# Test Authorize blocked token
var auth_req_bad = '[2, "msg-003", "Authorize", {"idToken": {"idToken": "REVOKED-TAG-404", "type": "ISO14443"}}]'
var auth_reply_bad = csms.handle_station_frame(auth_req_bad)
assert_true(auth_reply_bad != nil, "CSMS answered blocked token Authorize")

# Test CSMS outbound commands
var set_prof_call = csms.make_set_charging_profile_call("csms-cmd-01", 1, 16.0)
assert_true(set_prof_call != nil, "Generated SetChargingProfile call frame")

var reset_call = csms.make_reset_call("csms-cmd-02", "Immediate")
assert_true(reset_call != nil, "Generated Reset call frame")

# 5. Integrated Multi-EVSE Scenarios
var rush_res = ScenarioRunner.run_morning_fleet_rush()
assert_true(rush_res["success"], "Morning fleet rush passed under grid cap")
assert_true(rush_res["total_allocated_amps"] <= 80.05, "Total allocated amps strictly within 80A")

var microgrid_res = ScenarioRunner.run_solar_microgrid_peak_shaving()
assert_true(microgrid_res["success"], "Solar microgrid peak shaving scenario passed")

var unbalance_res = ScenarioRunner.run_phase_asymmetry_mitigation()
assert_true(unbalance_res["success"], "Phase asymmetry mitigation scenario passed")

var estop_res = ScenarioRunner.run_hardware_safety_estop()
assert_true(estop_res["success"], "Hardware safety E-Stop trip and recovery scenario passed")

print("test_sim: " + str(test_passed) + " passed, " + str(test_failed) + " failed")
if test_failed > 0
    import os
    os.exit(1)
end
