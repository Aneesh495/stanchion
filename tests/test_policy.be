# Stanchion Test Suite: Programmable Policy & Business Logic Engine
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import engine as PolicyEngine
import rules as StandardRules
import billing as BillingCalculator
import fleet_scheduler as FleetSchedulerModule
import types as Types
import math
import string
import global

var FleetVehicle = FleetSchedulerModule["Vehicle"]
var FleetScheduler = FleetSchedulerModule["Scheduler"]

var total_assertions = 0

def check(condition, desc)
    global.total_assertions = global.total_assertions + 1
    if !condition
        print("[FAIL] " + desc)
        assert(false)
    end
end

print(">>> Running test_policy.be ...")

# 1. Policy Engine & Rule Evaluation
var pe = PolicyEngine()
var r1_spec = StandardRules.fleet_departure_guarantee()
var r2_spec = StandardRules.employee_priority()
var r3_spec = StandardRules.green_power_only()

pe.add_rule(r1_spec["name"], r1_spec["priority"], r1_spec["condition"], r1_spec["action"])
pe.add_rule(r2_spec["name"], r2_spec["priority"], r2_spec["condition"], r2_spec["action"])
pe.add_rule(r3_spec["name"], r3_spec["priority"], r3_spec["condition"], r3_spec["action"])
check(pe.rule_count() == 3, "Registered 3 policy rules")

# Test context: Fleet delivery van with 1 hour left before departure and 50% SoC
var ctx_fleet = {
    "current_epoch_sec": 1000,
    "departure_epoch_sec": 4600, # 3600s left (1 hr)
    "current_soc_pct": 50.0,
    "user_group": "Fleet"
}
var actions_fleet = pe.evaluate_policies(ctx_fleet)
check(actions_fleet.size() >= 1, "Fleet departure rule triggered")
check(actions_fleet[0]["action"] == "Prioritize", "Prioritize action returned")
check(actions_fleet[0]["override_amps"] == 32.0, "Full 32A power granted to meet deadline")

# Test Eco Mode context
var ctx_eco = {
    "eco_mode": true,
    "available_solar_kw": 11.0 # ~16A at 400V 3-phase
}
var actions_eco = pe.evaluate_policies(ctx_eco)
check(actions_eco.size() >= 1, "Eco Mode rule triggered")
check(actions_eco[0]["action"] == "ThrottlePower", "Power throttled to match solar")

# 2. Billing Calculator
var billing = BillingCalculator(0.0825, "USD")
# 30 kWh consumed at $0.25/kWh = $7.50, $1.50 conn fee, $5.00 voucher discount
var inv = billing.generate_invoice("TX-9988-AA", 1, "BADGE-123", 30.0, 0.25, 1.50, 0.0, 5.0)
var lines = inv["line_items"]
check(lines["energy_subtotal"] == 7.50, "Energy subtotal = $7.50")
check(lines["discount_applied"] == 5.00, "Voucher discount = $5.00")
# Subtotal: 7.50 + 1.50 - 5.00 = 4.00, Tax: 4.00 * 0.0825 = 0.33, Grand Total: 4.33
check(lines["subtotal"] == 4.00, "Taxable subtotal = $4.00")
check(lines["grand_total"] == 4.33, "Grand total with tax = $4.33")

# 3. Fleet Depot Scheduler
var scheduler = FleetScheduler(100.0) # 100 kW total depot service capacity

# Van 1: Leaves at t=7200 (2 hrs), needs 30 kWh (starts 20%, target 80% on 50kWh battery), 22 kW charger
var v1 = FleetVehicle("VAN-01", 50.0, 20.0, 80.0, 0, 7200, 22.0)
# Van 2: Leaves at t=14400 (4 hrs), needs 30 kWh, 22 kW charger
var v2 = FleetVehicle("VAN-02", 50.0, 20.0, 80.0, 0, 14400, 22.0)
# Van 3: Leaves at t=3600 (1 hr), needs 20 kWh, 22 kW charger (Most urgent!)
var v3 = FleetVehicle("VAN-03", 40.0, 30.0, 80.0, 0, 3600, 22.0)

scheduler.add_vehicle(v1)
scheduler.add_vehicle(v2)
scheduler.add_vehicle(v3)

var sched_result = scheduler.solve_schedule(0)
check(sched_result.size() == 3, "Schedule generated for 3 vehicles")
# Most urgent Van 3 (leaves at 3600) should be scheduled first
check(sched_result[0]["vehicle_id"] == "VAN-03", "VAN-03 scheduled first due to least laxity")
check(sched_result[0]["status"] == "Charging", "VAN-03 status is Charging")
check(sched_result[1]["vehicle_id"] == "VAN-01", "VAN-01 scheduled second")

print(string.format("[PASS] test_policy.be passed with %d assertions verified.", total_assertions))
