# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# IEC 61851-1 Control Pilot PWM Generator, ADC Voltage Classifier & Proximity Sensing
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import types as Types
import math

class ControlPilot
    var evse_id
    var current_state
    var pwm_duty_cycle
    var pwm_active
    var measured_voltage_v
    var proximity_resistor_ohms
    var cable_capacity_a
    var last_state_change_ms

    def init(evse_id)
        self.evse_id = int(evse_id)
        self.current_state = Types.PILOT_STATE_A
        self.pwm_duty_cycle = 1.0 # 100% DC (Static 12V = Standby)
        self.pwm_active = false
        self.measured_voltage_v = 12.0
        self.proximity_resistor_ohms = 0
        self.cable_capacity_a = 0.0
        self.last_state_change_ms = 0
    end

    # Set desired charging current limit; converts to PWM duty cycle per IEC 61851-1
    def set_charging_current_limit(amps)
        amps = real(amps)
        if amps < Types.MIN_CHARGING_CURRENT_A
            # Suspend charging: continuous 12V (duty = 1.0)
            self.pwm_duty_cycle = 1.0
            self.pwm_active = false
        else
            self.pwm_duty_cycle = Types.amps_to_duty_cycle(amps)
            self.pwm_active = true
        end
    end

    # Classify measured Control Pilot voltage with noise hysteresis
    static def classify_pilot_voltage(voltage_v)
        var v = real(voltage_v)
        if v >= 10.5 && v <= 13.5
            return Types.PILOT_STATE_A # 12V nominal (EV disconnected)
        elif v >= 7.8 && v <= 10.2
            return Types.PILOT_STATE_B # 9V nominal (EV connected, not ready)
        elif v >= 4.8 && v <= 7.2
            return Types.PILOT_STATE_C # 6V nominal (EV ready, charging active)
        elif v >= 2.0 && v <= 4.0
            return Types.PILOT_STATE_D # 3V nominal (Ventilation required)
        elif v >= -1.0 && v <= 1.0
            return Types.PILOT_STATE_E # 0V nominal (Short circuit / disconnected)
        elif v <= -10.5
            return Types.PILOT_STATE_F # -12V nominal (Fault / reversed diode)
        else
            return Types.PILOT_STATE_E # Undefined voltage treated as Error
        end
    end

    # Process new ADC voltage measurement and update state machine
    def update_pilot_measurement(voltage_v, timestamp_ms)
        self.measured_voltage_v = real(voltage_v)
        var new_state = ControlPilot.classify_pilot_voltage(self.measured_voltage_v)

        if new_state != self.current_state
            self.current_state = new_state
            self.last_state_change_ms = int(timestamp_ms)
            return true # State changed
        end
        return false # State unchanged
    end

    # Classify cable current rating from Proximity Pilot (PP) resistance (IEC 62196-1)
    static def decode_proximity_resistance(ohms)
        var r = real(ohms)
        if r >= 1200.0 && r <= 1800.0
            return 13.0 # 1500 Ohm nominal (13 Amps)
        elif r >= 550.0 && r <= 800.0
            return 20.0 # 680 Ohm nominal (20 Amps)
        elif r >= 180.0 && r <= 270.0
            return 32.0 # 220 Ohm nominal (32 Amps)
        elif r >= 80.0 && r <= 120.0
            return 63.0 # 100 Ohm nominal (63 Amps)
        else
            return 0.0  # Invalid / Disconnected
        end
    end

    # Update proximity pilot measurement
    def update_proximity(ohms)
        self.proximity_resistor_ohms = int(ohms)
        self.cable_capacity_a = ControlPilot.decode_proximity_resistance(self.proximity_resistor_ohms)
    end

    def is_vehicle_connected()
        return self.current_state == Types.PILOT_STATE_B ||
               self.current_state == Types.PILOT_STATE_C ||
               self.current_state == Types.PILOT_STATE_D
    end

    def is_charging_requested()
        return self.current_state == Types.PILOT_STATE_C ||
               self.current_state == Types.PILOT_STATE_D
    end

    def is_ventilation_required()
        return self.current_state == Types.PILOT_STATE_D
    end

    def is_faulted()
        return self.current_state == Types.PILOT_STATE_E ||
               self.current_state == Types.PILOT_STATE_F
    end

    def get_state()
        return self.current_state
    end

    def get_duty_cycle()
        return self.pwm_duty_cycle
    end

    def get_max_allowed_amps()
        if !self.pwm_active
            return 0.0
        end
        return Types.duty_cycle_to_amps(self.pwm_duty_cycle)
    end
end

return ControlPilot
