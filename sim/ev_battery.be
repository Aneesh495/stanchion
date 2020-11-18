# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Electric Vehicle Battery Pack, Onboard Charger (OBC) & CC/CV Curve Simulator
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import math
import math_ext as MathExt

class EVBatteryModel
    var vehicle_id
    var battery_capacity_kwh
    var current_soc_pct
    var nominal_pack_voltage_v
    var internal_resistance_ohms
    var max_ac_power_kw
    var max_dc_power_kw
    var battery_temperature_c
    var thermal_mass_j_per_c
    var heat_dissipation_w_per_c
    var total_energy_absorbed_kwh

    def init(vid, capacity_kwh, initial_soc_pct, max_ac_kw)
        self.vehicle_id = str(vid)
        self.battery_capacity_kwh = (capacity_kwh != nil) ? real(capacity_kwh) : 75.0
        self.current_soc_pct = (initial_soc_pct != nil) ? real(initial_soc_pct) : 20.0
        self.nominal_pack_voltage_v = 400.0
        self.internal_resistance_ohms = 0.045 # 45 milliOhms internal pack resistance
        self.max_ac_power_kw = (max_ac_kw != nil) ? real(max_ac_kw) : 11.0 # 11 kW typical 3-phase OBC
        self.max_dc_power_kw = 150.0
        self.battery_temperature_c = 25.0
        self.thermal_mass_j_per_c = 850000.0
        self.heat_dissipation_w_per_c = 35.0
        self.total_energy_absorbed_kwh = 0.0
    end

    # Compute battery power acceptance capability based on CC/CV characteristic
    # Up to 80% SoC: Constant Current phase (accepts 100% of EVSE allocated power)
    # Above 80% SoC: Constant Voltage phase (tapers power down linearly to 10% at 100% SoC)
    def get_max_acceptable_power_kw()
        var base_power = self.max_ac_power_kw
        if self.current_soc_pct <= 80.0
            return base_power
        elif self.current_soc_pct >= 100.0
            return 0.0
        else
            # Linear taper from 80% to 100% SoC: 1.0 down to 0.10
            var factor = 1.0 - (0.90 * (self.current_soc_pct - 80.0) / 20.0)
            return base_power * factor
        end
    end

    # Step battery simulation over delta_time_sec given EVSE allocated power
    def step_charge(evse_allocated_kw, delta_time_sec)
        evse_allocated_kw = real(evse_allocated_kw)
        delta_time_sec = real(delta_time_sec)

        var acceptable_kw = self.get_max_acceptable_power_kw()
        var actual_power_kw = (evse_allocated_kw < acceptable_kw) ? evse_allocated_kw : acceptable_kw
        if actual_power_kw < 0.0
            actual_power_kw = 0.0
        end

        var dt_hours = delta_time_sec / 3600.0
        var energy_kwh = actual_power_kw * dt_hours

        # Update SoC
        var delta_soc = (energy_kwh / self.battery_capacity_kwh) * 100.0
        self.current_soc_pct = self.current_soc_pct + delta_soc
        if self.current_soc_pct > 100.0
            self.current_soc_pct = 100.0
        end

        self.total_energy_absorbed_kwh = self.total_energy_absorbed_kwh + energy_kwh

        # Thermal calculation: Joule heating Q = I^2 * R
        if actual_power_kw > 0.1
            var pack_current_a = (actual_power_kw * 1000.0) / self.nominal_pack_voltage_v
            var heat_gen_w = pack_current_a * pack_current_a * self.internal_resistance_ohms
            var heat_diss_w = (self.battery_temperature_c - 25.0) * self.heat_dissipation_w_per_c
            var net_heat_j = (heat_gen_w - heat_diss_w) * delta_time_sec
            self.battery_temperature_c = self.battery_temperature_c + (net_heat_j / self.thermal_mass_j_per_c)
        else
            # Cooling towards ambient 25 C
            var cooling = (self.battery_temperature_c - 25.0) * 0.02 * dt_hours
            self.battery_temperature_c = self.battery_temperature_c - cooling
        end

        return {
            "actual_power_kw": MathExt.round_to(actual_power_kw, 2),
            "soc_pct": MathExt.round_to(self.current_soc_pct, 2),
            "temperature_c": MathExt.round_to(self.battery_temperature_c, 1),
            "is_full": (self.current_soc_pct >= 99.9)
        }
    end
end

return EVBatteryModel
