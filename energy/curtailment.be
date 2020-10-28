# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Fast Demand Response Curtailment & Grid Emergency Event Processor
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import types as Types
import math_ext as MathExt

class CurtailmentLevel
    static var LEVEL_NONE     = 0 # Normal operations
    static var LEVEL_MODERATE = 1 # 25% reduction of station baseline
    static var LEVEL_SEVERE   = 2 # 50% reduction of station baseline
    static var LEVEL_CRITICAL = 3 # Immediate drop to minimum safe current (6A per EVSE)
    static var LEVEL_EMERGENCY= 4 # Full power disconnect / shed all loads
end

class CurtailmentManager
    var current_level
    var baseline_capacity_a
    var effective_capacity_a
    var event_start_epoch_sec
    var event_duration_sec
    var is_active

    def init(baseline_capacity_a)
        self.baseline_capacity_a = (baseline_capacity_a != nil) ? real(baseline_capacity_a) : 100.0
        self.effective_capacity_a = self.baseline_capacity_a
        self.current_level = CurtailmentLevel.LEVEL_NONE
        self.event_start_epoch_sec = 0
        self.event_duration_sec = 0
        self.is_active = false
    end

    # Trigger a utility demand-response curtailment event
    def apply_curtailment(level, duration_sec, start_epoch_sec)
        self.current_level = int(level)
        self.event_duration_sec = int(duration_sec)
        self.event_start_epoch_sec = int(start_epoch_sec)
        self.is_active = true

        if self.current_level == CurtailmentLevel.LEVEL_NONE
            self.effective_capacity_a = self.baseline_capacity_a
            self.is_active = false
        elif self.current_level == CurtailmentLevel.LEVEL_MODERATE
            self.effective_capacity_a = self.baseline_capacity_a * 0.75 # 25% cut
        elif self.current_level == CurtailmentLevel.LEVEL_SEVERE
            self.effective_capacity_a = self.baseline_capacity_a * 0.50 # 50% cut
        elif self.current_level == CurtailmentLevel.LEVEL_CRITICAL
            self.effective_capacity_a = 24.0 # 4 EVSEs * 6A minimum
        elif self.current_level == CurtailmentLevel.LEVEL_EMERGENCY
            self.effective_capacity_a = 0.0 # Full shed
        end

        return self.effective_capacity_a
    end

    # Periodic check to automatically restore baseline capacity once event duration expires
    def check_expiration(current_epoch_sec)
        current_epoch_sec = int(current_epoch_sec)
        if self.is_active && self.event_duration_sec > 0
            if current_epoch_sec >= (self.event_start_epoch_sec + self.event_duration_sec)
                # Event expired, restore nominal
                self.is_active = false
                self.current_level = CurtailmentLevel.LEVEL_NONE
                self.effective_capacity_a = self.baseline_capacity_a
                return true # Restored
            end
        end
        return false
    end

    def get_effective_capacity()
        return self.effective_capacity_a
    end

    def is_curtailed()
        return self.is_active
    end
end

return CurtailmentManager
