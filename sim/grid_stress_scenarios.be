# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Multi-Physics Grid Stress, Transformer Thermal & BESS Transient Scenarios
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import math
import math_ext as MathExt
import dlm as DynamicLoadManager
import solar_storage as SolarStorageOptimizer
import thermal_model as TransformerThermalModel
import cooling_loop as ChillerModule
import iso15118_20_dc as ISO20DCModule

var CoolingLoopController = ChillerModule["CoolingLoopController"]
var ISO15118_20_DCSession = ISO20DCModule["ISO15118_20_DCSession"]

# Advanced Multi-Physics Scenario Simulator
class GridStressScenarioRunner
    # Scenario 1: Substation Voltage Sag Brownout Throttling
    # Simulates a severe utility grid voltage drop from 230V to 185V.
    # The DLM controller reacts to prevent transformer overload by shedding non-critical load.
    static def run_substation_voltage_sag_scenario()
        var dlm = DynamicLoadManager(500.0, "EqualShare") # 500A nominal grid ceiling
        # 10 connected EVSEs demanding 32A each (320A total)
        for i : 1 .. 10
            dlm.update_request(i, 32.0, 32.0, 1)
        end
        var alloc_nominal = dlm.solve_allocation()

        # Utility grid browns out: grid voltage sags from 230V to 185V
        var sag_voltage_v = 185.0
        var nominal_voltage_v = 230.0
        # To maintain the same MVA limit on the feeder, current ceiling is derated:
        var voltage_ratio = sag_voltage_v / nominal_voltage_v
        var derated_capacity_a = 500.0 * voltage_ratio # 402.1A
        dlm.set_grid_capacity(derated_capacity_a)

        var alloc_derated = dlm.solve_allocation()
        var total_allocated = dlm.get_total_allocated_amps()

        return {
            "nominal_allocated_amps": 320.0,
            "derated_capacity_a": MathExt.round_to(derated_capacity_a, 1),
            "derated_allocated_amps": MathExt.round_to(total_allocated, 1),
            "success": (total_allocated <= derated_capacity_a + 0.1)
        }
    end

    # Scenario 2: Solar Transient Cloud Dip Buffered by BESS
    # Tests sub-second transition of stationary battery from absorption to discharge during solar eclipse
    static def run_solar_cloud_transient_scenario()
        # 120 kW solar peak, 150 kWh BESS with 80 kW charge/discharge capability
        var opt = SolarStorageOptimizer(120.0, 150.0, 80.0, 80.0)

        var ev_demand_kw = 50.0
        # t0: Full solar (90 kW) -> 50 kW to EV, 40 kW into BESS, 0 kW grid import
        var disp_sunny = opt.dispatch(ev_demand_kw, 90.0, 60.0)

        # t1: Heavy cloud arrives abruptly: solar drops from 90 kW to 15 kW
        # Deficit is 35 kW. BESS should discharge 35 kW to maintain 0 kW grid import!
        var disp_cloud = opt.dispatch(ev_demand_kw, 15.0, 60.0)

        return {
            "sunny_solar_to_bess_kw": disp_sunny["solar_to_bess_kw"],
            "sunny_grid_import_kw": disp_sunny["grid_import_kw"],
            "cloud_solar_to_ev_kw": disp_cloud["solar_to_ev_kw"],
            "cloud_bess_discharge_kw": disp_cloud["bess_discharge_to_ev_kw"],
            "cloud_grid_import_kw": disp_cloud["grid_import_kw"],
            "success": (disp_sunny["grid_import_kw"] < 0.1 && disp_cloud["grid_import_kw"] < 0.1 && disp_cloud["bess_discharge_to_ev_kw"] >= 34.9)
        }
    end

    # Scenario 3: Megawatt MCS Truck Charging with Liquid Cable Chilling & Transformer Thermal Guard
    static def run_megawatt_mcs_depot_scenario()
        var session1 = ISO15118_20_DCSession(1, 1000.0, 800.0, 800.0)
        var chiller = CoolingLoopController()
        var transformer = TransformerThermalModel(1000.0) # 1000 kVA transformer

        # Deploy ACD pantograph and match precharge
        session1.step_acd_docking()
        session1.step_acd_docking()
        session1.step_acd_docking()
        session1.handle_precharge_req(750.0)

        # Megawatt charge step at 800A (600 kW load) for 10 minutes (600s)
        # Using dt = 6.0s to allow the 150 A/s slew-rate limiter to ramp from 0A to 800A
        var loop_res = session1.handle_charge_loop_req(750.0, 800.0, false, 6.0)
        var chill_res = chiller.step_cooling(800.0, 10.0)
        var therm_res = transformer.step_thermal(600.0, 600.0)

        return {
            "evse_power_kw": loop_res["evse_power_kw"],
            "pump_pwm_pct": chill_res["pump_pwm_pct"],
            "pin_temp_c": chill_res["pin_pos_temp_c"],
            "transformer_hotspot_c": therm_res["hotspot_temp_c"],
            "curtailment_factor": therm_res["curtailment_factor"],
            "success": (loop_res["evse_power_kw"] >= 590.0 && chill_res["pump_pwm_pct"] >= 80.0 && therm_res["curtailment_factor"] == 1.0)
        }
    end
end

return GridStressScenarioRunner
