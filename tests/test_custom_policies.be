# Stanchion Test Suite: Enterprise Custom Charging Policies
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import custom_policies as CustomPolicyModule
import math
import string
import global

var SchoolBusDepotPolicy = CustomPolicyModule["SchoolBusDepotPolicy"]
var TransitBusOpportunityPolicy = CustomPolicyModule["TransitBusOpportunityPolicy"]
var WorksiteSolarOnlyPolicy = CustomPolicyModule["WorksiteSolarOnlyPolicy"]
var HighwayCorridorPolicy = CustomPolicyModule["HighwayCorridorPolicy"]
var SharedCondoPolicy = CustomPolicyModule["SharedCondoPolicy"]

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

print(">>> Running test_custom_policies suite...")

# 1. School Bus Depot Policy Tests
var bus_policy = SchoolBusDepotPolicy()

# 18:00 (evening peak), 75% SoC, 35 cents/kWh spot price -> V2G Discharge
var res_v2g = bus_policy.evaluate_bus_action(75.0, 18.0, 35.0)
assert_equal(res_v2g["action"], "V2G_DISCHARGE", "School bus discharges during evening peak")
assert_equal(res_v2g["target_soc"], 50.0, "Retains 50% reserve for morning route")

# 18:00, but low SoC (45%) -> Do NOT discharge
var res_low = bus_policy.evaluate_bus_action(45.0, 18.0, 35.0)
assert_equal(res_low["action"], "IDLE", "Does not discharge below 50% reserve")

# 23:00 (overnight) -> Charge
var res_night = bus_policy.evaluate_bus_action(45.0, 23.0, 8.0)
assert_equal(res_night["action"], "CHARGE", "Charges overnight")

# 2. Transit Bus Opportunity Charging Policy Tests
var transit = TransitBusOpportunityPolicy()
var t_res = transit.calculate_burst_allocation(40.0, 2, 360)
assert_equal(t_res["allocated_power_kw"], 450.0, "Allocates 450 kW pantograph burst")
assert_true(t_res["can_preempt_other_evses"], "High priority bus can preempt other EVSEs")
assert_equal(t_res["estimated_kwh_delivered"], 45.0, "Delivers 45 kWh in 6 minutes")

# 3. Worksite Solar-Only Policy Tests
var worksite = WorksiteSolarOnlyPolicy()
# 50 kW solar, 20 kW building, 2 kW buffer = 28 kW surplus for 4 EVs
# 28 kW / 4 = 7 kW per EV -> (7000) / (3 * 230) = 10.1A
var ws_res1 = worksite.calculate_worksite_limits(50.0, 20.0, 4)
assert_true(ws_res1["is_active"], "Worksite charging active with sufficient solar")
assert_true(ws_res1["per_ev_amps"] > 9.5 && ws_res1["per_ev_amps"] < 10.5, "Allocates approximately 10.1A per EV")

# Insufficient solar: 15 kW solar, 14 kW building -> surplus < 6A minimum -> pause
var ws_res2 = worksite.calculate_worksite_limits(15.0, 14.0, 4)
assert_true(!ws_res2["is_active"], "Worksite charging paused below 6A minimum threshold")
assert_equal(ws_res2["per_ev_amps"], 0.0, "Zero current allocated")

# 4. Highway Corridor Policy Tests (80% SoC Cap)
var hwy = HighwayCorridorPolicy()
# 60% SoC -> Fast Charge
var hwy_60 = hwy.evaluate_session_limits(60.0, 0.90)
assert_equal(hwy_60["action"], "FAST_CHARGE", "Fast charge allowed below 80% SoC")

# 85% SoC on congested plaza (90% occupancy) -> Terminate & Auto-Unlock
var hwy_85_cong = hwy.evaluate_session_limits(85.0, 0.90)
assert_equal(hwy_85_cong["action"], "TERMINATE_SESSION", "Session terminated at 85% on congested plaza")
assert_true(hwy_85_cong["auto_unlock"], "Cable auto-unlocked for next driver")

# 85% SoC on empty plaza (30% occupancy) -> Allow slow taper
var hwy_85_empty = hwy.evaluate_session_limits(85.0, 0.30)
assert_equal(hwy_85_empty["action"], "TAPER_POWER", "Allows slow charging when plaza uncongested")

# 5. Shared Condo Policy Tests (Fair-Share Round-Robin)
var condo = SharedCondoPolicy(100.0) # 100A panel
var vehicles = {
    "Apt-101": {"kwh_delivered": 5.0},  # Needs energy (< 20 kWh)
    "Apt-102": {"kwh_delivered": 21.0}, # Satisfied (>= 20 kWh)
    "Apt-103": {"kwh_delivered": 8.0}   # Needs energy (< 20 kWh)
}
var condo_alloc = condo.distribute_condo_power(vehicles)
assert_true(condo_alloc["Apt-101"] > 0.0, "Apt-101 receives charging current")
assert_true(condo_alloc["Apt-103"] > 0.0, "Apt-103 receives charging current")
assert_equal(condo_alloc["Apt-102"], 0.0, "Apt-102 zeroed out because 20 kWh quota reached")

print("test_custom_policies: " + str(test_passed) + " passed, " + str(test_failed) + " failed")
if test_failed > 0
    import os
    os.exit(1)
end
