# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Multi-Tier 7-Day Recurring Composite Charging Schedule Generator
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import math
import math_ext as MathExt

# Period limit point in schedule
class SchedulePeriod
    var start_period_sec # Offset from schedule start
    var limit_value      # Limit in Amps or Watts
    var number_phases

    def init(start_sec, limit_val, phases)
        self.start_period_sec = int(start_sec)
        self.limit_value = real(limit_val)
        self.number_phases = (phases != nil) ? int(phases) : 3
    end

    def to_map()
        return {
            "startPeriod": self.start_period_sec,
            "limit": MathExt.round_to(self.limit_value, 2),
            "numberPhases": self.number_phases
        }
    end
end

# Multi-Tier Composite Schedule Calculator
class MultiTierCompositeScheduler
    var station_max_limit_a
    var profiles

    def init(default_max_a)
        self.station_max_limit_a = (default_max_a != nil) ? real(default_max_a) : 64.0
        self.profiles = []
    end

    def add_profile(profile_id, stack_level, purpose, recurring_kind, periods_list)
        self.profiles.push({
            "id": int(profile_id),
            "stack_level": int(stack_level),
            "purpose": str(purpose), # "ChargingStationMaxProfile", "TxDefaultProfile", "TxProfile"
            "recurrence": (recurring_kind != nil) ? str(recurring_kind) : "None", # "Daily", "Weekly", "None"
            "periods": periods_list
        })
    end

    def clear_profiles()
        self.profiles = []
    end

    # Calculate composite schedule for a specific EVSE over duration_sec starting from query_epoch_sec
    def generate_composite_schedule(query_epoch_sec, duration_sec, charging_rate_unit, nominal_voltage_v)
        var q_start = int(query_epoch_sec)
        var dur = int(duration_sec)
        var rate_unit = (charging_rate_unit != nil) ? str(charging_rate_unit) : "A"
        var v_ln = (nominal_voltage_v != nil) ? real(nominal_voltage_v) : 230.0

        # Collect critical transition timestamps within the query window
        var transition_offsets = {0: true}
        var i = 0
        while i < size(self.profiles)
            var p = self.profiles[i]
            var per_list = p["periods"]
            var j = 0
            while j < size(per_list)
                var p_obj = per_list[j]
                var offset = p_obj.start_period_sec

                if p["recurrence"] == "Daily"
                    # Modulo 86400
                    var current_day_sec = q_start % 86400
                    var rel = offset - current_day_sec
                    if rel < 0 rel = rel + 86400 end
                    if rel < dur
                        transition_offsets[rel] = true
                    end
                else
                    if offset >= 0 && offset < dur
                        transition_offsets[offset] = true
                    end
                end
                j = j + 1
            end
            i = i + 1
        end

        # Sort transition offsets ascending
        var sorted_offsets = []
        for k : transition_offsets.keys()
            sorted_offsets.push(int(k))
        end
        sorted_offsets = MathExt.sort_numeric(sorted_offsets)

        # Evaluate composite limit at each transition point
        var composite_periods = []
        var last_limit = -1.0

        var idx = 0
        while idx < size(sorted_offsets)
            var t_offset = sorted_offsets[idx]
            var current_t = q_start + t_offset

            # Start with station hardware ceiling
            var effective_limit_a = self.station_max_limit_a
            var max_stack_seen = -1

            # Iterate through profiles and apply stack level hierarchy
            var p_idx = 0
            while p_idx < size(self.profiles)
                var prof = self.profiles[p_idx]
                var lim_at_t = self._eval_profile_limit(prof, current_t)

                if lim_at_t != nil
                    # Higher stack level overrides lower stack level
                    if prof["stack_level"] > max_stack_seen
                        max_stack_seen = prof["stack_level"]
                        effective_limit_a = lim_at_t
                    elif prof["stack_level"] == max_stack_seen
                        # Same stack level: take the most restrictive (minimum)
                        if lim_at_t < effective_limit_a
                            effective_limit_a = lim_at_t
                        end
                    end
                end
                p_idx = p_idx + 1
            end

            # Cap strictly by station hardware ceiling
            if effective_limit_a > self.station_max_limit_a
                effective_limit_a = self.station_max_limit_a
            end

            # Convert to Watts if requested (3-phase active power P = 3 * V_LN * I)
            var final_limit = effective_limit_a
            if rate_unit == "W"
                final_limit = 3.0 * v_ln * effective_limit_a
            end

            # Merge periods if limit hasn't changed
            if math.abs(final_limit - last_limit) > 0.05
                composite_periods.push(SchedulePeriod(t_offset, final_limit, 3))
                last_limit = final_limit
            end

            idx = idx + 1
        end

        var result_list = []
        var r_idx = 0
        while r_idx < size(composite_periods)
            result_list.push(composite_periods[r_idx].to_map())
            r_idx = r_idx + 1
        end

        return {
            "startSchedule": q_start,
            "duration": dur,
            "chargingRateUnit": rate_unit,
            "chargingSchedulePeriod": result_list
        }
    end

    def _eval_profile_limit(prof, abs_time_epoch)
        var per_list = prof["periods"]
        if size(per_list) == 0 return nil end

        var target_sec = 0
        if prof["recurrence"] == "Daily"
            target_sec = abs_time_epoch % 86400
        else
            target_sec = abs_time_epoch
        end

        # Find the active period matching target_sec
        var active_lim = nil
        var j = 0
        while j < size(per_list)
            var p = per_list[j]
            if p.start_period_sec <= target_sec
                active_lim = p.limit_value
            end
            j = j + 1
        end
        return active_lim
    end
end

return {
    "SchedulePeriod": SchedulePeriod,
    "MultiTierCompositeScheduler": MultiTierCompositeScheduler
}
