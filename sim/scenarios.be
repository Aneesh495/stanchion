# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Multi-EVSE Depot Scenarios & Microgrid Dynamic Simulation Suite
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import math
import math_ext as MathExt
import types as Types
import config as StationConfig
import controller as StationController
import ev_battery as EVBattery
import grid_feed as GridFeed
import solar_sim as SolarSim
import solar_storage as SolarStorageOptimizer
import phase_balance as PhaseBalanceModule

var PhaseBalancer = PhaseBalanceModule["PhaseBalancer"]
var PhaseLoad = PhaseBalanceModule["PhaseLoad"]

# Scenario Runner for Stanchion Automated Verification
class ScenarioRunner
    # Scenario 1: Morning Fleet Depot Rush
    # Simulates 3 commercial vans plugged into a 3-channel EVSE station with 80A total grid cap.
    # Tests DLM proportional allocation and CC/CV power taper as vehicles reach high SoC.
    static def run_morning_fleet_rush()
        var cfg = StationConfig()
        cfg.evse_count = 3
        cfg.max_grid_current_a = 80.0
        var station = StationController(cfg)

        # Create simulated EV battery packs
        var van1 = EVBattery("VAN-01", 60.0, 15.0, 11.0) # 15% SoC, 11 kW max
        var van2 = EVBattery("VAN-02", 80.0, 40.0, 11.0) # 40% SoC, 11 kW max
        var van3 = EVBattery("VAN-03", 50.0, 75.0, 11.0) # 75% SoC, 11 kW max

        # Connect and authenticate vehicles
        station.get_evse(1).plug_in_vehicle()
        station.get_evse(1).authorize_and_start("FLEET-VAN-01", 1770000000)

        station.get_evse(2).plug_in_vehicle()
        station.get_evse(2).authorize_and_start("FLEET-VAN-02", 1770000000)

        station.get_evse(3).plug_in_vehicle()
        station.get_evse(3).authorize_and_start("FLEET-VAN-03", 1770000000)

        var step_seconds = 60.0
        var total_sim_steps = 15 # 15 minutes of simulated charging
        var step = 0

        while step < total_sim_steps
            var now_ts = 1770000000 + int(step * step_seconds)
            station.step(now_ts)

            # Update battery models based on allocated power
            var evse1 = station.get_evse(1)
            var evse2 = station.get_evse(2)
            var evse3 = station.get_evse(3)

            var kw1 = (evse1.current_allocated_amps * 230.0 * 3.0) / 1000.0
            var kw2 = (evse2.current_allocated_amps * 230.0 * 3.0) / 1000.0
            var kw3 = (evse3.current_allocated_amps * 230.0 * 3.0) / 1000.0

            van1.step_charge(kw1, step_seconds)
            van2.step_charge(kw2, step_seconds)
            van3.step_charge(kw3, step_seconds)

            step = step + 1
        end

        var total_draw = station.get_evse(1).current_allocated_amps + station.get_evse(2).current_allocated_amps + station.get_evse(3).current_allocated_amps
        return {
            "success": (total_draw <= 80.05),
            "total_allocated_amps": MathExt.round_to(total_draw, 1),
            "van1_soc": van1.current_soc_pct,
            "van2_soc": van2.current_soc_pct,
            "van3_soc": van3.current_soc_pct
        }
    end

    # Scenario 2: Solar Microgrid Peak Shaving
    # Tests rooftop solar PV generation and stationary battery co-optimization.
    static def run_solar_microgrid_peak_shaving()
        var solar = SolarSim(60.0, 50.0, 37.77) # 60 kW DC array, 50 kW AC inverter
        var opt = SolarStorageOptimizer(60.0, 100.0, 50.0, 50.0)

        # Simulate solar noon on day 172 (summer solstice)
        var step_res = solar.step_solar(172, 12.0, 300.0) # 5 minutes at noon

        # Plug EV demanding 22 kW total
        var ev_demand_kw = 22.0
        var dispatch = opt.dispatch(ev_demand_kw, step_res["ac_power_kw"], 300.0)

        return {
            "solar_ac_power_kw": step_res["ac_power_kw"],
            "grid_import_kw": dispatch["grid_import_kw"],
            "solar_to_ev_kw": dispatch["solar_to_ev_kw"],
            "bess_soc_pct": opt.get_bess_soc_pct(),
            "success": (step_res["ac_power_kw"] > 25.0 && dispatch["grid_import_kw"] < 5.0)
        }
    end

    # Scenario 3: Single Phase Asymmetry Mitigation
    # Tests phase load balancer under severe unbalanced single-phase vehicle charging.
    static def run_phase_asymmetry_mitigation()
        var pb = PhaseBalancer(16.0, 230.0) # 16A max unbalance limit
        pb.assign_evse_phase(1, "L1")
        pb.assign_evse_phase(2, "L2")
        pb.assign_evse_phase(3, "L1")

        # Readings map with severe phase unbalance: 64A on L1 vs 16A on L2
        var readings = {
            1: {"L1": 32.0, "L2": 0.0, "L3": 0.0},
            2: {"L1": 0.0, "L2": 16.0, "L3": 0.0},
            3: {"L1": 32.0, "L2": 0.0, "L3": 0.0}
        }
        var aggregate = pb.aggregate_phase_loads(readings)
        var is_excessive = pb.is_unbalance_excessive(aggregate)
        var curtailment = pb.calculate_phase_curtailment(aggregate)

        return {
            "aggregate_unbalance_a": aggregate.get_unbalance_amps(),
            "is_excessive": is_excessive,
            "curtailment_required": curtailment["curtailment_required"],
            "reduction_amps": curtailment["reduction_amps"],
            "congested_phase": curtailment["congested_phase"],
            "success": (is_excessive && curtailment["curtailment_required"] && curtailment["congested_phase"] == Types.PHASE_1_L1)
        }
    end

    # Scenario 4: Hardware Safety Trip on E-Stop
    # Tests immediate contactor isolation, fault event emission, and graceful recovery.
    static def run_hardware_safety_estop()
        var cfg = StationConfig()
        cfg.evse_count = 2
        var station = StationController(cfg)

        var evse1 = station.get_evse(1)
        evse1.plug_in_vehicle()
        evse1.authorize_and_start("RFID-OPERATOR-999", 1000)

        var pre_state = evse1.fsm.current_state

        # Engage Emergency Stop
        station.press_emergency_stop()
        var post_state = evse1.fsm.current_state
        var contactor_open = (evse1.contactor.state == Types.CONTACTOR_OPEN)

        # Release Emergency Stop
        station.release_emergency_stop()
        var recovery_state = evse1.fsm.current_state

        return {
            "pre_estop_state": pre_state,
            "post_estop_state": post_state,
            "contactor_is_open": contactor_open,
            "recovery_state": recovery_state,
            "success": (post_state == Types.STATE_FAULTED && contactor_open && recovery_state == Types.STATE_AVAILABLE)
        }
    end
end

return ScenarioRunner
