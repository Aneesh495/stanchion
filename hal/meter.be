# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Multi-Phase High-Accuracy Energy Meter & Telemetry Accumulator
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import math
import math_ext as MathExt

class PhaseReading
    var phase_name
    var voltage_ln_v
    var current_a
    var active_power_kw
    var reactive_power_kvar
    var apparent_power_kva
    var power_factor

    def init(name)
        self.phase_name = str(name)
        self.voltage_ln_v = 0.0
        self.current_a = 0.0
        self.active_power_kw = 0.0
        self.reactive_power_kvar = 0.0
        self.apparent_power_kva = 0.0
        self.power_factor = 1.0
    end

    def update(v, i, pf)
        self.voltage_ln_v = real(v)
        self.current_a = real(i)
        self.power_factor = (pf != nil) ? real(pf) : 1.0

        # Apparent power S = V * I / 1000 (kVA)
        self.apparent_power_kva = (self.voltage_ln_v * self.current_a) / 1000.0

        # Active power P = S * PF (kW)
        self.active_power_kw = self.apparent_power_kva * self.power_factor

        # Reactive power Q = sqrt(S^2 - P^2) (kVAR)
        var s = self.apparent_power_kva
        var p = self.active_power_kw
        var diff = s * s - p * p
        if diff > 0.0
            self.reactive_power_kvar = math.sqrt(diff)
        else
            self.reactive_power_kvar = 0.0
        end
    end

    def to_map()
        return {
            "phase": self.phase_name,
            "voltage_v": MathExt.round_to(self.voltage_ln_v, 2),
            "current_a": MathExt.round_to(self.current_a, 2),
            "power_kw": MathExt.round_to(self.active_power_kw, 3),
            "reactive_kvar": MathExt.round_to(self.reactive_power_kvar, 3),
            "apparent_kva": MathExt.round_to(self.apparent_power_kva, 3),
            "power_factor": MathExt.round_to(self.power_factor, 3)
        }
    end
end

class EnergyMeter
    var evse_id
    var phase_l1
    var phase_l2
    var phase_l3
    var grid_frequency_hz
    var energy_import_total_kwh
    var energy_export_total_kwh
    var last_sample_time_sec

    def init(evse_id)
        self.evse_id = int(evse_id)
        self.phase_l1 = PhaseReading("L1")
        self.phase_l2 = PhaseReading("L2")
        self.phase_l3 = PhaseReading("L3")
        self.grid_frequency_hz = 50.0
        self.energy_import_total_kwh = 0.0
        self.energy_export_total_kwh = 0.0
        self.last_sample_time_sec = nil
    end

    # Process instantaneous sample across all 3 phases
    def update_samples(v1, i1, v2, i2, v3, i3, pf, freq, current_time_sec)
        current_time_sec = int(current_time_sec)
        self.phase_l1.update(v1, i1, pf)
        self.phase_l2.update(v2, i2, pf)
        self.phase_l3.update(v3, i3, pf)
        self.grid_frequency_hz = (freq != nil) ? real(freq) : 50.0

        if self.last_sample_time_sec != nil && current_time_sec > self.last_sample_time_sec
            var delta_sec = current_time_sec - self.last_sample_time_sec
            var delta_hours = real(delta_sec) / 3600.0

            var total_active_kw = self.get_total_active_power_kw()
            if total_active_kw >= 0.0
                self.energy_import_total_kwh = self.energy_import_total_kwh + (total_active_kw * delta_hours)
            else
                # Reverse power flow (V2G vehicle discharging)
                var export_kw = math.abs(total_active_kw)
                self.energy_export_total_kwh = self.energy_export_total_kwh + (export_kw * delta_hours)
            end
        end

        self.last_sample_time_sec = current_time_sec
    end

    def get_total_active_power_kw()
        return self.phase_l1.active_power_kw +
               self.phase_l2.active_power_kw +
               self.phase_l3.active_power_kw
    end

    def get_total_apparent_power_kva()
        return self.phase_l1.apparent_power_kva +
               self.phase_l2.apparent_power_kva +
               self.phase_l3.apparent_power_kva
    end

    def get_total_current_a()
        return self.phase_l1.current_a +
               self.phase_l2.current_a +
               self.phase_l3.current_a
    end

    # Return structured snapshot map for OCPP 2.0.1 MeterValues message
    def get_meter_value_snapshot()
        var total_kw = self.get_total_active_power_kw()
        var total_kva = self.get_total_apparent_power_kva()
        var pf = (total_kva > 0.001) ? (total_kw / total_kva) : 1.0

        return {
            "evse_id": self.evse_id,
            "energy_active_import_kwh": MathExt.round_to(self.energy_import_total_kwh, 4),
            "energy_active_export_kwh": MathExt.round_to(self.energy_export_total_kwh, 4),
            "power_active_total_kw": MathExt.round_to(total_kw, 3),
            "power_apparent_total_kva": MathExt.round_to(total_kva, 3),
            "power_factor_total": MathExt.round_to(pf, 3),
            "frequency_hz": MathExt.round_to(self.grid_frequency_hz, 2),
            "phases": {
                "L1": self.phase_l1.to_map(),
                "L2": self.phase_l2.to_map(),
                "L3": self.phase_l3.to_map()
            }
        }
    end

    def reset_energy()
        self.energy_import_total_kwh = 0.0
        self.energy_export_total_kwh = 0.0
    end
end

return EnergyMeter
