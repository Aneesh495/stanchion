# Stanchion Test Suite: Smart Charging & Energy Management System
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import dlm as DynamicLoadManager
import phase_balance as PhaseBalanceModule
import tariff as TariffEngine
import solar_storage as SolarStorageOptimizer
import v2g as V2GModule
import curtailment as CurtailmentManager
import types as Types
import math
import string
import global

var PhaseLoad = PhaseBalanceModule["PhaseLoad"]
var PhaseBalancer = PhaseBalanceModule["PhaseBalancer"]
var V2GRouter = V2GModule["V2GRouter"]

var total_assertions = 0

def check(condition, desc)
    global.total_assertions = global.total_assertions + 1
    if !condition
        print("[FAIL] " + desc)
        assert(false)
    end
end

print(">>> Running test_energy.be ...")

# 1. Dynamic Load Management (DLM)
var dlm = DynamicLoadManager(64.0, "EqualShare")
dlm.update_request(1, 32.0, 32.0, 10)
dlm.update_request(2, 32.0, 32.0, 10)
# Total capacity 64A split across 2 EVSEs = 32A each
var alloc1 = dlm.solve_allocation()
check(alloc1[1] == 32.0 && alloc1[2] == 32.0, "Equal share 2 EVSEs = 32A each")

# Add 2 more EVSEs: 64A split across 4 EVSEs = 16A each
dlm.update_request(3, 32.0, 32.0, 10)
dlm.update_request(4, 32.0, 32.0, 10)
var alloc2 = dlm.solve_allocation()
check(alloc2[1] == 16.0 && alloc2[2] == 16.0 && alloc2[3] == 16.0 && alloc2[4] == 16.0, "Equal share 4 EVSEs = 16A each")

# Priority Weighted test: VIP on EVSE 1 gets 32A full speed, remaining 32A split across EVSE 2,3,4
dlm.set_strategy("PriorityWeighted")
dlm.update_request(1, 32.0, 32.0, 100) # VIP weight 100
dlm.update_request(2, 32.0, 32.0, 10)
dlm.update_request(3, 32.0, 32.0, 10)
dlm.update_request(4, 32.0, 32.0, 10)
var alloc_prio = dlm.solve_allocation()
check(alloc_prio[1] == 32.0, "VIP EVSE 1 allocated full 32A")
check(alloc_prio[2] + alloc_prio[3] + alloc_prio[4] <= 32.01, "Remaining EVSEs share remaining 32A")

# 2. Phase Balance & Asymmetry Mitigation
var balancer = PhaseBalancer(20.0, 230.0) # 20A limit
var loads = PhaseLoad(32.0, 10.0, 5.0)
check(loads.get_unbalance_amps() == 27.0, "Unbalance = 32 - 5 = 27A")
check(balancer.is_unbalance_excessive(loads) == true, "27A unbalance exceeds 20A limit")

# Optimal phase selection for new vehicle: lowest is L3 (5A)
var best_phase = balancer.select_optimal_phase(loads)
check(best_phase == Types.PHASE_1_L3, "Optimal phase selected is least loaded L3")

var curtail_res = balancer.calculate_phase_curtailment(loads)
check(curtail_res["curtailment_required"] == true, "Curtailment required on congested phase")
check(curtail_res["congested_phase"] == Types.PHASE_1_L1, "L1 is congested phase")
check(curtail_res["reduction_amps"] == 7.0, "Reduction of 7A restores balance to 20A")

# 3. Dynamic Tariffs & Receipts
var tariff = TariffEngine("USD")
# Nighttime: 02:00 UTC (Off-Peak)
var epoch_night = 1775008800 # weekday night
var rate_night = tariff.get_price_per_kwh(epoch_night)
check(rate_night == 0.12, "Night rate = $0.12/kWh")

# Evening peak: 18:00 UTC (On-Peak)
var epoch_evening = 1775066400 # weekday evening
var rate_eve = tariff.get_price_per_kwh(epoch_evening)
check(rate_eve == 0.48, "Evening peak rate = $0.48/kWh")

var receipt = tariff.calculate_session_cost(25.0, epoch_night, epoch_night + 7200, 30, false)
# Energy: 25 * 0.12 = 3.00, Conn: 1.50, Idle: (30-15)*0.50 = 7.50 => Subtotal: 12.00, Tax: 0.99, Total: 12.99
check(receipt["energy_cost"] == 3.00, "Receipt energy cost = $3.00")
check(receipt["idle_fee"] == 7.50, "Receipt idle fee = $7.50")
check(receipt["total_cost"] == 12.99, "Receipt total cost = $12.99")

# 4. Microgrid Solar + BESS Optimizer
var solar_bess = SolarStorageOptimizer(100.0, 200.0, 50.0, 50.0) # 100kW solar, 200kWh BESS (starts 50% = 100kWh)
# Case A: High solar (80 kW), low EV demand (30 kW) -> Solar covers EV, charges BESS with 50 kW
var disp_a = solar_bess.dispatch(30.0, 80.0, 3600) # 1 hour
check(disp_a["solar_to_ev_kw"] == 30.0, "All 30kW EV demand supplied by solar")
check(disp_a["grid_import_kw"] == 0.0, "Zero grid import during surplus solar")
check(disp_a["bess_soc_pct"] > 50.0, "BESS SoC increased from solar charging")

# Case B: Zero solar (night), high EV demand (40 kW) -> BESS discharges 40 kW to shave grid peak
var disp_b = solar_bess.dispatch(40.0, 0.0, 1800) # 0.5 hour
check(disp_b["bess_discharge_to_ev_kw"] == 40.0, "BESS discharged 40kW to cover EV demand")
check(disp_b["grid_import_kw"] == 0.0, "Grid peak completely shaved by BESS")

# 5. Vehicle-to-Grid (V2G) Router
var v2g = V2GRouter()
# EV with 75 kWh battery at 80% SoC, user min SoC 40%, 11 kW max discharge
v2g.register_vehicle(1, 75.0, 80.0, 40.0, 11.0)
check(v2g.get_total_v2g_capacity_kw() == 11.0, "11 kW V2G capacity available")

# Dispatch 10 kW V2G for 1 hour
var discharged = v2g.dispatch_v2g(10.0, 3600)
check(discharged == 10.0, "10 kW V2G power dispatched")
var sess = v2g.active_v2g_sessions[1]
# 10 kWh from 75 kWh = 13.33% SoC drop -> ~66.7% SoC
check(sess.current_soc_pct < 70.0 && sess.current_soc_pct > 65.0, "Vehicle SoC reduced from V2G export")

# 6. Demand Response Curtailment
var curtail = CurtailmentManager(100.0)
check(curtail.get_effective_capacity() == 100.0, "Initial nominal capacity = 100A")
curtail.apply_curtailment(2, 3600, 1000) # Level 2 Severe = 50% cut
check(curtail.get_effective_capacity() == 50.0, "Level 2 curtailed to 50A")
check(curtail.is_curtailed() == true, "Curtailment active")

curtail.check_expiration(5000) # Expired (1000 + 3600 = 4600)
check(curtail.get_effective_capacity() == 100.0, "Capacity restored after event expiry")

print(string.format("[PASS] test_energy.be passed with %d assertions verified.", total_assertions))
