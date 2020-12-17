# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Transformer Winding Hot-Spot & Busbar Thermal Aging Model (IEC 60076-7)
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import math
import math_ext as MathExt

# Transformer & Switchgear Thermal Aging Model
# Implements IEC 60076-7 differential equations for top-oil and winding hot-spot temperatures,
# Arrhenius relative loss of life factor, and dynamic thermal curtailment setpoints.
class TransformerThermalModel
    var rated_power_kva
    var rated_hotspot_rise_c
    var rated_top_oil_rise_c
    var ambient_temp_c
    var current_top_oil_temp_c
    var current_hotspot_temp_c
    var tau_top_oil_sec # Top-oil thermal time constant (e.g. 7200 sec / 2 hours)
    var tau_winding_sec # Winding thermal time constant (e.g. 300 sec / 5 mins)
    var cumulative_loss_of_life_hours
    var warning_temp_threshold_c
    var trip_temp_threshold_c

    def init(rated_kva)
        self.rated_power_kva = (rated_kva != nil) ? real(rated_kva) : 250.0
        self.rated_hotspot_rise_c = 28.0 # Hot-spot gradient above top oil at rated load
        self.rated_top_oil_rise_c = 52.0 # Top-oil rise above ambient at rated load
        self.ambient_temp_c = 25.0
        self.current_top_oil_temp_c = 25.0 + 20.0
        self.current_hotspot_temp_c = self.current_top_oil_temp_c + 10.0
        self.tau_top_oil_sec = 7200.0
        self.tau_winding_sec = 300.0
        self.cumulative_loss_of_life_hours = 0.0
        self.warning_temp_threshold_c = 115.0 # Warning threshold
        self.trip_temp_threshold_c = 135.0    # Emergency trip threshold
    end

    def set_ambient_temperature(temp_c)
        self.ambient_temp_c = real(temp_c)
    end

    # Calculate Arrhenius Relative Loss of Life Factor (V)
    # Reference hot-spot temperature is 110 degC where V = 1.0 (normal insulation aging)
    # V = exp(15000 / (110 + 273) - 15000 / (hotspot + 273))
    def compute_relative_aging_rate(hotspot_c)
        var t = real(hotspot_c)
        if t < 50.0
            return 0.001
        end
        var exponent = (15000.0 / 383.0) - (15000.0 / (t + 273.15))
        if exponent > 6.0
            exponent = 6.0
        elif exponent < -10.0
            exponent = -10.0
        end
        return math.exp(exponent)
    end

    # Step thermal simulation over delta_time_sec given actual substation load
    def step_thermal(actual_load_kva, delta_time_sec)
        var dt = real(delta_time_sec)
        var k = real(actual_load_kva) / self.rated_power_kva # Load ratio K
        if k < 0.0
            k = 0.0
        end

        # Steady-state top-oil temperature rise: Delta Theta_to_u = Delta Theta_to_r * ((1 + R*K^2)/(1 + R))^x
        # Approximation with exponent x = 0.8
        var oil_exponent = 0.8
        var steady_oil_rise = self.rated_top_oil_rise_c * math.pow(k * k, oil_exponent * 0.5)
        var steady_top_oil_temp = self.ambient_temp_c + steady_oil_rise

        # Differential update for top oil
        var d_oil = (steady_top_oil_temp - self.current_top_oil_temp_c) * (dt / self.tau_top_oil_sec)
        self.current_top_oil_temp_c = self.current_top_oil_temp_c + d_oil

        # Steady-state hot-spot rise above top oil: Delta Theta_h_u = Delta Theta_hr * K^(2*y)
        # Exponent y = 0.8
        var steady_hotspot_gradient = self.rated_hotspot_rise_c * math.pow(k, 1.6)
        var steady_hotspot_temp = self.current_top_oil_temp_c + steady_hotspot_gradient

        # Differential update for winding hot spot
        var d_hs = (steady_hotspot_temp - self.current_hotspot_temp_c) * (dt / self.tau_winding_sec)
        self.current_hotspot_temp_c = self.current_hotspot_temp_c + d_hs

        # Aging rate integration
        var v = self.compute_relative_aging_rate(self.current_hotspot_temp_c)
        var dt_hours = dt / 3600.0
        var aging_increment_hours = v * dt_hours
        self.cumulative_loss_of_life_hours = self.cumulative_loss_of_life_hours + aging_increment_hours

        # Thermal curtailment factor: 1.0 (no throttle) down to 0.0 (full shutdown)
        var curtailment_factor = 1.0
        var is_thermal_warning = false
        var is_thermal_trip = false

        if self.current_hotspot_temp_c >= self.trip_temp_threshold_c
            curtailment_factor = 0.0
            is_thermal_trip = true
        elif self.current_hotspot_temp_c >= self.warning_temp_threshold_c
            # Linear curtailment from 115 C (1.0) to 135 C (0.2)
            var span = self.trip_temp_threshold_c - self.warning_temp_threshold_c
            var excess = self.current_hotspot_temp_c - self.warning_temp_threshold_c
            curtailment_factor = 1.0 - (0.80 * (excess / span))
            is_thermal_warning = true
        end

        return {
            "top_oil_temp_c": MathExt.round_to(self.current_top_oil_temp_c, 1),
            "hotspot_temp_c": MathExt.round_to(self.current_hotspot_temp_c, 1),
            "relative_aging_factor": MathExt.round_to(v, 3),
            "cumulative_aging_hours": MathExt.round_to(self.cumulative_loss_of_life_hours, 4),
            "curtailment_factor": MathExt.round_to(curtailment_factor, 2),
            "is_thermal_warning": is_thermal_warning,
            "is_thermal_trip": is_thermal_trip
        }
    end
end

return TransformerThermalModel
