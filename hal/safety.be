# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Hardware Safety Supervisor, RCD/GFCI Detection, Overcurrent & Thermal Derating
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import types as Types
import errors as ErrorsModule
import math_ext as MathExt

var ErrorSeverity = ErrorsModule["Severity"]
var ErrorCode = ErrorsModule["Code"]
var StationError = ErrorsModule["StationError"]

class SafetySupervisor
    var evse_id
    var rcd_ac_current_ma
    var rcd_dc_current_ma
    var current_rms_a
    var rated_current_a
    var voltage_ln_v
    var temperature_heatsink_c
    var temperature_connector_c
    var emergency_stop_pressed
    var active_errors
    var is_tripped
    var overcurrent_energy_accumulator

    def init(evse_id, rated_current_a)
        self.evse_id = int(evse_id)
        self.rated_current_a = (rated_current_a != nil) ? real(rated_current_a) : 32.0
        self.rcd_ac_current_ma = 0.0
        self.rcd_dc_current_ma = 0.0
        self.current_rms_a = 0.0
        self.voltage_ln_v = Types.NOMINAL_VOLTAGE_LN_V
        self.temperature_heatsink_c = 25.0
        self.temperature_connector_c = 25.0
        self.emergency_stop_pressed = false
        self.active_errors = []
        self.is_tripped = false
        self.overcurrent_energy_accumulator = 0.0
    end

    # Evaluate all safety telemetry channels against IEC statutory protection limits
    def evaluate_safety(rcd_ac_ma, rcd_dc_ma, max_phase_current_a, voltage_v, temp_sink, temp_plug, delta_time_sec)
        self.rcd_ac_current_ma = real(rcd_ac_ma)
        self.rcd_dc_current_ma = real(rcd_dc_ma)
        self.current_rms_a = real(max_phase_current_a)
        self.voltage_ln_v = real(voltage_v)
        self.temperature_heatsink_c = real(temp_sink)
        self.temperature_connector_c = real(temp_plug)
        delta_time_sec = real(delta_time_sec)

        # 1. Emergency Stop Check
        if self.emergency_stop_pressed
            self._raise_error(ErrorCode.ERR_POWER_SWITCH_FAILURE, ErrorSeverity.CRITICAL, "Emergency Stop button depressed")
            return false
        end

        # 2. Residual Current Monitor (RCD Type B / RDC-DD)
        # IEC 62955: DC leakage >= 6.0 mA requires cutoff within 10 seconds (or immediate for > 60mA)
        # IEC 61008: AC leakage >= 30.0 mA requires immediate trip
        if self.rcd_dc_current_ma >= Types.RCD_DC_TRIP_MA
            self._raise_error(ErrorCode.ERR_GROUND_FAILURE, ErrorSeverity.CRITICAL,
                "DC residual current exceeded limit: " + str(self.rcd_dc_current_ma) + " mA")
            return false
        end
        if self.rcd_ac_current_ma >= Types.RCD_AC_TRIP_MA
            self._raise_error(ErrorCode.ERR_GROUND_FAILURE, ErrorSeverity.CRITICAL,
                "AC residual current exceeded limit: " + str(self.rcd_ac_current_ma) + " mA")
            return false
        end

        # 3. Voltage Limits (Nominal 230V +-15%: 195.5V to 264.5V)
        if self.voltage_ln_v > 265.0
            self._raise_error(ErrorCode.ERR_OVER_VOLTAGE, ErrorSeverity.SEVERE,
                "Overvoltage condition: " + str(self.voltage_ln_v) + " V")
            return false
        elif self.voltage_ln_v < 180.0 && self.voltage_ln_v > 50.0
            self._raise_error(ErrorCode.ERR_UNDER_VOLTAGE, ErrorSeverity.MODERATE,
                "Undervoltage sag: " + str(self.voltage_ln_v) + " V")
            return false
        end

        # 4. Thermal Critical Trip (> 85 C)
        var max_temp = (self.temperature_heatsink_c > self.temperature_connector_c) ?
                       self.temperature_heatsink_c : self.temperature_connector_c
        if max_temp >= Types.OVERTEMP_CRITICAL_TRIP_C
            self._raise_error(ErrorCode.ERR_OVER_TEMPERATURE, ErrorSeverity.CRITICAL,
                "Critical overtemperature trip: " + str(max_temp) + " C")
            return false
        end

        # 5. Overcurrent Inverse-Time Integration (I^2 * t thermal model)
        var ratio = self.current_rms_a / self.rated_current_a
        if ratio > Types.OVERCURRENT_TRIP_FACTOR
            var excess = ratio * ratio - 1.0
            self.overcurrent_energy_accumulator = self.overcurrent_energy_accumulator + (excess * delta_time_sec)
            # Trip threshold reached
            if self.overcurrent_energy_accumulator >= 5.0 # 5 second thermal budget at 1.4x overload
                self._raise_error(ErrorCode.ERR_OVER_CURRENT, ErrorSeverity.CRITICAL,
                    "Overcurrent I2t trip: " + str(self.current_rms_a) + " A")
                return false
            end
        else
            # Cool down accumulator
            self.overcurrent_energy_accumulator = self.overcurrent_energy_accumulator - (1.0 * delta_time_sec)
            if self.overcurrent_energy_accumulator < 0.0
                self.overcurrent_energy_accumulator = 0.0
            end
        end

        return true # All safety parameters nominal
    end

    # Calculate thermal derating factor (1.0 = 100% full rating, 0.0 = suspended)
    # Starts linear derating above 65 C down to 0 at 85 C
    def get_thermal_derating_factor()
        var max_temp = (self.temperature_heatsink_c > self.temperature_connector_c) ?
                       self.temperature_heatsink_c : self.temperature_connector_c

        if max_temp <= Types.OVERTEMP_DERATE_START_C
            return 1.0
        elif max_temp >= Types.OVERTEMP_CRITICAL_TRIP_C
            return 0.0
        else
            var span = Types.OVERTEMP_CRITICAL_TRIP_C - Types.OVERTEMP_DERATE_START_C
            var excess = max_temp - Types.OVERTEMP_DERATE_START_C
            return 1.0 - (excess / span)
        end
    end

    def press_emergency_stop()
        self.emergency_stop_pressed = true
        self.is_tripped = true
    end

    def release_emergency_stop()
        self.emergency_stop_pressed = false
    end

    def _raise_error(code, severity, description)
        self.is_tripped = true
        var err = StationError(code, severity, description, self.evse_id)
        self.active_errors.push(err)
        print("[SAFETY TRIP EVSE " + str(self.evse_id) + "] " + str(code) + " (" + str(severity) + "): " + description)
    end

    def clear_trips_technician()
        self.is_tripped = false
        self.active_errors = []
        self.overcurrent_energy_accumulator = 0.0
    end

    def has_tripped()
        return self.is_tripped
    end

    def get_errors()
        return self.active_errors
    end
end

return SafetySupervisor
