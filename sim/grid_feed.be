# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Substation Grid Feeder Simulator, Voltage Drop & Background Facility Load
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import math
import math_ext as MathExt

class GridFeederModel
    var substation_nominal_voltage_v
    var transformer_capacity_kva
    var feeder_resistance_ohms
    var feeder_reactance_ohms
    var nominal_frequency_hz
    var current_voltage_v
    var current_frequency_hz
    var background_load_kw

    def init(nominal_voltage_v, transformer_kva)
        self.substation_nominal_voltage_v = (nominal_voltage_v != nil) ? real(nominal_voltage_v) : 230.0
        self.transformer_capacity_kva = (transformer_kva != nil) ? real(transformer_kva) : 250.0
        self.feeder_resistance_ohms = 0.035 # 35 milliOhms line resistance
        self.feeder_reactance_ohms = 0.020  # 20 milliOhms line inductive reactance
        self.nominal_frequency_hz = 50.0
        self.current_voltage_v = self.substation_nominal_voltage_v
        self.current_frequency_hz = self.nominal_frequency_hz
        self.background_load_kw = 25.0 # 25 kW depot building base load
    end

    # Calculate real-time voltage sag at charging station service entrance given EV load
    def step_grid(ev_load_kw, ev_current_a, power_factor, hour_of_day)
        ev_load_kw = real(ev_load_kw)
        ev_current_a = real(ev_current_a)
        var pf = (power_factor != nil) ? real(power_factor) : 1.0

        # Background diurnal load variation
        var h = (hour_of_day != nil) ? int(hour_of_day) : 12
        var bg_factor = 1.0
        if h >= 8 && h <= 17
            bg_factor = 1.6 # Daytime facility HVAC & lighting
        elif h >= 18 && h <= 22
            bg_factor = 1.2
        else
            bg_factor = 0.8 # Overnight base
        end
        var total_facility_kw = self.background_load_kw * bg_factor

        # Voltage drop approximation: Delta V = I * (R * cos(phi) + X * sin(phi))
        var sin_phi = math.sqrt(1.0 - pf * pf)
        var v_drop = (ev_current_a / 3.0) * (self.feeder_resistance_ohms * pf + self.feeder_reactance_ohms * sin_phi)
        self.current_voltage_v = self.substation_nominal_voltage_v - v_drop

        # Small grid frequency fluctuation under total grid strain
        var total_kw = ev_load_kw + total_facility_kw
        var load_ratio = total_kw / (self.transformer_capacity_kva * 0.95)
        var freq_droop = (load_ratio > 0.85) ? (0.15 * (load_ratio - 0.85)) : 0.0
        self.current_frequency_hz = self.nominal_frequency_hz - freq_droop

        return {
            "service_voltage_v": MathExt.round_to(self.current_voltage_v, 2),
            "voltage_drop_v": MathExt.round_to(v_drop, 2),
            "grid_frequency_hz": MathExt.round_to(self.current_frequency_hz, 2),
            "total_facility_kw": MathExt.round_to(total_facility_kw, 2),
            "transformer_loading_pct": MathExt.round_to((total_kw / self.transformer_capacity_kva) * 100.0, 1)
        }
    end
end

return GridFeederModel
