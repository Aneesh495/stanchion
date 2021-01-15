# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Liquid-Cooled Cable & Power Electronics Chiller Controller (500A+ HPC)
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import math
import math_ext as MathExt

# Liquid Cooling Operational States
class CoolingLoopState
    static var OFF           = "OFF"
    static var STANDBY       = "STANDBY"
    static var RUNNING       = "RUNNING"
    static var WARNING       = "WARNING"
    static var FAULT_TRIPPED = "FAULT_TRIPPED"
end

# Liquid Cooling Controller for Ultra-Fast High-Power Charging
class CoolingLoopController
    var cable_resistance_ohms
    var coolant_supply_temp_c
    var coolant_return_temp_c
    var connector_pin_pos_temp_c
    var connector_pin_neg_temp_c
    var coolant_flow_rate_lpm # Liters per minute
    var coolant_pressure_bar
    var pump_pwm_pct
    var fan_pwm_pct
    var current_state
    var max_safe_pin_temp_c
    var min_safe_flow_lpm
    var min_safe_pressure_bar

    def init()
        self.cable_resistance_ohms = 0.00045 # 0.45 milliOhms active loop resistance
        self.coolant_supply_temp_c = 25.0
        self.coolant_return_temp_c = 26.0
        self.connector_pin_pos_temp_c = 28.0
        self.connector_pin_neg_temp_c = 28.0
        self.coolant_flow_rate_lpm = 6.5
        self.coolant_pressure_bar = 2.1
        self.pump_pwm_pct = 0.0
        self.fan_pwm_pct = 0.0
        self.current_state = CoolingLoopState.STANDBY
        self.max_safe_pin_temp_c = 90.0
        self.min_safe_flow_lpm = 1.5
        self.min_safe_pressure_bar = 0.8
    end

    # Step cooling control loop given charging current and elapsed time
    def step_cooling(charging_current_a, delta_time_sec)
        var i = real(charging_current_a)
        var dt = real(delta_time_sec)

        # 1. Check for physical sensor faults (leakage, pump stall)
        if self.coolant_pressure_bar < self.min_safe_pressure_bar
            self.current_state = CoolingLoopState.FAULT_TRIPPED
            return self._build_status(0.0, "LeakageDetectedUnderPressure")
        end

        if self.coolant_flow_rate_lpm < self.min_safe_flow_lpm && i > 50.0
            self.current_state = CoolingLoopState.FAULT_TRIPPED
            return self._build_status(0.0, "FlowRateLossPumpStall")
        end

        # 2. Thermal dissipation: Q = I^2 * R
        var heat_watts = i * i * self.cable_resistance_ohms

        # 3. Dynamic pump & fan modulation
        if i < 30.0
            self.pump_pwm_pct = 20.0 # Idle circulation
            self.fan_pwm_pct = 0.0
            self.current_state = CoolingLoopState.STANDBY
        else
            # Modulate pump proportional to current: 30A (30%) to 500A (100%)
            var target_pump = 30.0 + (70.0 * (i - 30.0) / 470.0)
            self.pump_pwm_pct = MathExt.clamp(target_pump, 30.0, 100.0)
            # Modulate radiator fan proportional to return temp
            var target_fan = (self.coolant_return_temp_c - 30.0) * 3.0
            self.fan_pwm_pct = MathExt.clamp(target_fan, 0.0, 100.0)
            self.current_state = CoolingLoopState.RUNNING
        end

        # 4. Temperature dynamics
        var cooling_power_w = (self.pump_pwm_pct / 100.0) * 4500.0
        var net_heat_w = heat_watts - cooling_power_w
        var temp_delta = (net_heat_w / 8000.0) * (dt / 10.0)

        self.coolant_return_temp_c = self.coolant_supply_temp_c + (heat_watts / 600.0)
        self.connector_pin_pos_temp_c = self.connector_pin_pos_temp_c + temp_delta
        self.connector_pin_neg_temp_c = self.connector_pin_neg_temp_c + temp_delta

        # Clamp pin temperatures to ambient minimum
        if self.connector_pin_pos_temp_c < self.coolant_supply_temp_c
            self.connector_pin_pos_temp_c = self.coolant_supply_temp_c
            self.connector_pin_neg_temp_c = self.coolant_supply_temp_c
        end

        # 5. Over-temperature protection and current derating
        var max_pin_temp = (self.connector_pin_pos_temp_c > self.connector_pin_neg_temp_c) ?
            self.connector_pin_pos_temp_c : self.connector_pin_neg_temp_c

        var current_derating_factor = 1.0
        var alarm_reason = nil

        if max_pin_temp >= self.max_safe_pin_temp_c || self.coolant_return_temp_c >= 70.0
            self.current_state = CoolingLoopState.FAULT_TRIPPED
            current_derating_factor = 0.0
            alarm_reason = "ConnectorOverTemperatureTrip"
        elif max_pin_temp >= (self.max_safe_pin_temp_c - 10.0) || self.coolant_return_temp_c >= 60.0
            self.current_state = CoolingLoopState.WARNING
            # Smooth linear derating down to 40%
            var excess = max_pin_temp - (self.max_safe_pin_temp_c - 10.0)
            current_derating_factor = 1.0 - (0.06 * excess)
            alarm_reason = "ConnectorThermalWarning"
        end

        return self._build_status(current_derating_factor, alarm_reason)
    end

    def _build_status(derating, reason)
        return {
            "state": self.current_state,
            "pump_pwm_pct": MathExt.round_to(self.pump_pwm_pct, 1),
            "fan_pwm_pct": MathExt.round_to(self.fan_pwm_pct, 1),
            "return_temp_c": MathExt.round_to(self.coolant_return_temp_c, 1),
            "pin_pos_temp_c": MathExt.round_to(self.connector_pin_pos_temp_c, 1),
            "pin_neg_temp_c": MathExt.round_to(self.connector_pin_neg_temp_c, 1),
            "flow_rate_lpm": MathExt.round_to(self.coolant_flow_rate_lpm, 2),
            "pressure_bar": MathExt.round_to(self.coolant_pressure_bar, 2),
            "derating_factor": MathExt.round_to(derating, 2),
            "alarm": reason
        }
    end
end

return {
    "CoolingLoopState": CoolingLoopState,
    "CoolingLoopController": CoolingLoopController
}
