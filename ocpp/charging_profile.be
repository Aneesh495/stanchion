# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Smart Charging Profile Engine, Schedule Periods & Composite Limit Calculator
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import types as Types
import time_util as TimeUtil

class ChargingSchedulePeriod
    var start_period_sec
    var limit_value
    var number_phases

    def init(start_period_sec, limit_val, number_phases)
        self.start_period_sec = int(start_period_sec)
        self.limit_value = real(limit_val)
        self.number_phases = (number_phases != nil) ? int(number_phases) : 3
    end
end

class ChargingProfile
    var profile_id
    var stack_level
    var profile_purpose
    var profile_kind
    var valid_from_epoch_sec
    var valid_to_epoch_sec
    var charging_rate_unit
    var schedule_start_epoch_sec
    var duration_sec
    var schedule_periods

    def init(profile_id, stack_level, purpose, kind, rate_unit)
        self.profile_id = int(profile_id)
        self.stack_level = int(stack_level)
        self.profile_purpose = str(purpose)
        self.profile_kind = str(kind)
        self.charging_rate_unit = (rate_unit != nil) ? str(rate_unit) : Types.RATE_UNIT_AMPERES
        self.valid_from_epoch_sec = 0
        self.valid_to_epoch_sec = 0
        self.schedule_start_epoch_sec = 0
        self.duration_sec = 0
        self.schedule_periods = []
    end

    def add_period(start_sec, limit_val, num_phases)
        self.schedule_periods.push(ChargingSchedulePeriod(start_sec, limit_val, num_phases))
        # Keep periods sorted by start_period_sec ascending
        self._sort_periods()
    end

    def _sort_periods()
        var n = self.schedule_periods.size()
        for i : 0 .. (n - 2)
            for j : 0 .. (n - 2 - i)
                if self.schedule_periods[j].start_period_sec > self.schedule_periods[j + 1].start_period_sec
                    var tmp = self.schedule_periods[j]
                    self.schedule_periods[j] = self.schedule_periods[j + 1]
                    self.schedule_periods[j + 1] = tmp
                end
            end
        end
    end

    # Check whether profile is active at the given epoch timestamp
    def is_active_at(epoch_sec)
        epoch_sec = int(epoch_sec)
        if self.valid_from_epoch_sec > 0 && epoch_sec < self.valid_from_epoch_sec
            return false
        end
        if self.valid_to_epoch_sec > 0 && epoch_sec > self.valid_to_epoch_sec
            return false
        end
        return true
    end

    # Get active limit for a given offset seconds into the schedule
    def get_limit_at_offset(offset_sec)
        offset_sec = int(offset_sec)
        if self.schedule_periods.size() == 0
            return nil
        end
        var active_limit = self.schedule_periods[0].limit_value
        for p : self.schedule_periods
            if offset_sec >= p.start_period_sec
                active_limit = p.limit_value
            else
                break
            end
        end
        return active_limit
    end
end

class CompositeScheduleCalculator
    # Calculate the composite charging limit across a list of profiles for an EVSE at a specific time
    static def calculate_composite_limit(profiles_list, target_epoch_sec, default_limit_a)
        default_limit_a = (default_limit_a != nil) ? real(default_limit_a) : Types.MAX_AC_THREE_PHASE_A
        target_epoch_sec = int(target_epoch_sec)

        if profiles_list == nil || profiles_list.size() == 0
            return default_limit_a
        end

        var lowest_limit = default_limit_a

        for prof : profiles_list
            if prof.is_active_at(target_epoch_sec)
                var offset = (prof.schedule_start_epoch_sec > 0) ?
                             (target_epoch_sec - prof.schedule_start_epoch_sec) : target_epoch_sec
                var lim = prof.get_limit_at_offset(offset)
                if lim != nil
                    # Convert W to A if rate unit is Watts: Amps = Watts / (sqrt(3) * 400)
                    if prof.charging_rate_unit == Types.RATE_UNIT_WATTS
                        lim = lim / (1.7320508 * Types.NOMINAL_VOLTAGE_LL_V)
                    end
                    if lim < lowest_limit
                        lowest_limit = lim
                    end
                end
            end
        end

        # Hard floor at minimum charging current (6A) or 0 if completely suspended
        if lowest_limit < Types.MIN_CHARGING_CURRENT_A
            return 0.0
        end
        return lowest_limit
    end
end

var ChargingProfileModule = {
    "Period": ChargingSchedulePeriod,
    "Profile": ChargingProfile,
    "CompositeCalculator": CompositeScheduleCalculator
}

return ChargingProfileModule
