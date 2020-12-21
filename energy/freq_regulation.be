# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Fast Frequency Response (FFR), Droop Control & Synthetic Inertia Controller
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import math
import math_ext as MathExt

# Fast Frequency Response & Frequency Containment Reserve (FCR) Engine
# Complies with ENTSO-E / CAISO fast frequency response specifications.
# Dynamically throttles EV loads or triggers V2G injection during under-frequency events.
class FrequencyRegulationController
    var nominal_frequency_hz
    var deadband_hz
    var droop_percentage # e.g. 4.0% droop
    var max_power_capacity_kw
    var v2g_export_enabled
    var rocof_trip_threshold_hz_per_s # Rate of Change of Frequency threshold
    var last_frequency_hz
    var last_timestamp_sec
    var cumulative_injected_kwh
    var cumulative_absorbed_kwh
    var is_underfrequency_alarm
    var is_overfrequency_alarm

    def init(nominal_freq_hz, capacity_kw)
        self.nominal_frequency_hz = (nominal_freq_hz != nil) ? real(nominal_freq_hz) : 50.0
        self.max_power_capacity_kw = (capacity_kw != nil) ? real(capacity_kw) : 100.0
        self.deadband_hz = 0.02 # +/- 20 mHz deadband
        self.droop_percentage = 4.0 # 4% droop
        self.v2g_export_enabled = true
        self.rocof_trip_threshold_hz_per_s = 0.50 # 500 mHz/s RoCoF trip limit
        self.last_frequency_hz = self.nominal_frequency_hz
        self.last_timestamp_sec = 0
        self.cumulative_injected_kwh = 0.0
        self.cumulative_absorbed_kwh = 0.0
        self.is_underfrequency_alarm = false
        self.is_overfrequency_alarm = false
    end

    # Calculate required active power adjustment Delta P based on grid frequency deviation
    def calculate_regulation_delta_kw(measured_frequency_hz, timestamp_sec)
        var f = real(measured_frequency_hz)
        var ts = real(timestamp_sec)
        var delta_f = f - self.nominal_frequency_hz

        # Calculate RoCoF (df/dt)
        var rocof = 0.0
        if self.last_timestamp_sec > 0 && ts > self.last_timestamp_sec
            var dt = ts - self.last_timestamp_sec
            rocof = (f - self.last_frequency_hz) / dt
        end
        self.last_frequency_hz = f
        self.last_timestamp_sec = ts

        # Check for RoCoF emergency trip
        var is_rocof_critical = (math.abs(rocof) >= self.rocof_trip_threshold_hz_per_s)

        # Check deadband
        if math.abs(delta_f) <= self.deadband_hz && !is_rocof_critical
            self.is_underfrequency_alarm = false
            self.is_overfrequency_alarm = false
            return {
                "delta_kw": 0.0,
                "rocof_hz_per_s": MathExt.round_to(rocof, 3),
                "action": "STANDBY",
                "is_critical": false
            }
        end

        # Effective frequency deviation outside deadband
        var eff_delta_f = 0.0
        if delta_f > self.deadband_hz
            eff_delta_f = delta_f - self.deadband_hz
            self.is_overfrequency_alarm = true
            self.is_underfrequency_alarm = false
        else
            eff_delta_f = delta_f + self.deadband_hz
            self.is_underfrequency_alarm = true
            self.is_overfrequency_alarm = false
        end

        # Standard Droop Formula: Delta P = - (1 / Droop) * (eff_delta_f / f_nom) * P_rated
        var droop_factor = self.droop_percentage / 100.0
        var norm_dev = eff_delta_f / self.nominal_frequency_hz
        var delta_kw = - (1.0 / droop_factor) * norm_dev * self.max_power_capacity_kw

        # Emergency boost if RoCoF is critical
        if is_rocof_critical
            if eff_delta_f < 0.0
                delta_kw = self.max_power_capacity_kw # Full emergency support
            else
                delta_kw = -self.max_power_capacity_kw # Full emergency absorption
            end
        end

        # Clamp Delta P within capacity
        delta_kw = MathExt.clamp(delta_kw, -self.max_power_capacity_kw, self.max_power_capacity_kw)

        var action = "MODULATING"
        if delta_kw > 0.1
            action = "DISCHARGING_SUPPORT"
        elif delta_kw < -0.1
            action = "ABSORBING_SURPLUS"
        end

        return {
            "delta_kw": MathExt.round_to(delta_kw, 2),
            "rocof_hz_per_s": MathExt.round_to(rocof, 3),
            "action": action,
            "is_critical": is_rocof_critical
        }
    end

    # Apply regulation adjustment to EV charging baseline power
    def adjust_ev_charging_power(baseline_charging_kw, measured_freq_hz, delta_time_sec, timestamp_sec)
        baseline_charging_kw = real(baseline_charging_kw)
        var reg = self.calculate_regulation_delta_kw(measured_freq_hz, timestamp_sec)
        var delta_kw = reg["delta_kw"]

        # If delta_kw > 0 (under-frequency: grid needs help), we decrease EV charging consumption
        # If delta_kw is greater than baseline charging, we switch to V2G injection (if enabled)
        var new_charging_kw = baseline_charging_kw - delta_kw

        var v2g_injection_kw = 0.0
        if new_charging_kw < 0.0
            if self.v2g_export_enabled
                v2g_injection_kw = -new_charging_kw
                new_charging_kw = 0.0
            else
                new_charging_kw = 0.0
            end
        end

        # Track energy integration
        var dt_hours = real(delta_time_sec) / 3600.0
        if delta_kw > 0.0
            self.cumulative_injected_kwh = self.cumulative_injected_kwh + (delta_kw * dt_hours)
        elif delta_kw < 0.0
            self.cumulative_absorbed_kwh = self.cumulative_absorbed_kwh + ((-delta_kw) * dt_hours)
        end

        return {
            "original_kw": baseline_charging_kw,
            "adjusted_kw": MathExt.round_to(new_charging_kw, 2),
            "v2g_injection_kw": MathExt.round_to(v2g_injection_kw, 2),
            "regulation_delta_kw": delta_kw,
            "action": reg["action"],
            "is_critical": reg["is_critical"],
            "cumulative_injected_kwh": MathExt.round_to(self.cumulative_injected_kwh, 4),
            "cumulative_absorbed_kwh": MathExt.round_to(self.cumulative_absorbed_kwh, 4)
        }
    end
end

return FrequencyRegulationController
