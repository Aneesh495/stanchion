# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Connector Overstay & Escalating Idle Fee Policy Engine
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import math
import math_ext as MathExt

# Overstay Session Tracking & Idle Fee Calculator
class OverstaySession
    var evse_id
    var transaction_id
    var id_token
    var charge_complete_epoch_sec
    var unplug_epoch_sec
    var is_active

    def init(evse_num, tx_id, token_str, complete_epoch)
        self.evse_id = int(evse_num)
        self.transaction_id = str(tx_id)
        self.id_token = str(token_str)
        self.charge_complete_epoch_sec = int(complete_epoch)
        self.unplug_epoch_sec = nil
        self.is_active = true
    end

    def close(unplug_epoch)
        self.unplug_epoch_sec = int(unplug_epoch)
        self.is_active = false
    end
end

class OverstayManager
    var grace_period_sec
    var tier1_rate_per_min
    var tier2_rate_per_min
    var tier2_threshold_sec
    var max_idle_fee_cap
    var auto_unlock_enabled
    var active_sessions

    def init()
        self.grace_period_sec = 900 # 15 minutes grace period
        self.tier1_rate_per_min = 0.50 # $0.50 per minute (15 - 45 min)
        self.tier2_rate_per_min = 1.00 # $1.00 per minute (> 45 min)
        self.tier2_threshold_sec = 2700 # 45 minutes
        self.max_idle_fee_cap = 100.00 # $100 cap
        self.auto_unlock_enabled = true
        self.active_sessions = {}
    end

    def register_charge_complete(evse_id, tx_id, id_token, complete_epoch_sec)
        var sess = OverstaySession(evse_id, tx_id, id_token, complete_epoch_sec)
        self.active_sessions[int(evse_id)] = sess
        return sess
    end

    def register_unplug(evse_id, unplug_epoch_sec)
        var id = int(evse_id)
        if self.active_sessions.contains(id)
            var sess = self.active_sessions[id]
            sess.close(unplug_epoch_sec)
            return sess
        end
        return nil
    end

    # Calculate accrued idle fee given current time and station occupancy ratio
    def calculate_idle_fee(evse_id, current_epoch_sec, station_occupancy_ratio)
        var id = int(evse_id)
        if !self.active_sessions.contains(id)
            return {"fee": 0.0, "status": "NoOverstaySession"}
        end

        var sess = self.active_sessions[id]
        var end_t = (sess.unplug_epoch_sec != nil) ? sess.unplug_epoch_sec : int(current_epoch_sec)
        var elapsed_sec = end_t - sess.charge_complete_epoch_sec
        if elapsed_sec < 0 elapsed_sec = 0 end

        # 1. Grace Period check
        if elapsed_sec <= self.grace_period_sec
            var remaining_grace_min = (self.grace_period_sec - elapsed_sec) / 60.0
            return {
                "fee": 0.0,
                "status": "GRACE_PERIOD",
                "idle_minutes": MathExt.round_to(elapsed_sec / 60.0, 1),
                "remaining_grace_min": MathExt.round_to(remaining_grace_min, 1),
                "auto_unlock_triggered": false
            }
        end

        # 2. Billable idle duration calculation
        var billable_sec = elapsed_sec - self.grace_period_sec
        var tier1_duration_sec = 0
        var tier2_duration_sec = 0

        var tier1_limit_sec = self.tier2_threshold_sec - self.grace_period_sec # 1800 sec (30 mins)

        if billable_sec <= tier1_limit_sec
            tier1_duration_sec = billable_sec
            tier2_duration_sec = 0
        else
            tier1_duration_sec = tier1_limit_sec
            tier2_duration_sec = billable_sec - tier1_limit_sec
        end

        var fee1 = (tier1_duration_sec / 60.0) * self.tier1_rate_per_min
        var fee2 = (tier2_duration_sec / 60.0) * self.tier2_rate_per_min
        var raw_fee = fee1 + fee2

        # 3. Congestion Multiplier (doubles if station occupancy >= 80%)
        var occ = (station_occupancy_ratio != nil) ? real(station_occupancy_ratio) : 0.5
        var multiplier = (occ >= 0.80) ? 2.0 : 1.0
        var total_fee = raw_fee * multiplier

        # 4. Cap check
        if total_fee > self.max_idle_fee_cap
            total_fee = self.max_idle_fee_cap
        end

        var auto_unlock = (self.auto_unlock_enabled && elapsed_sec > self.grace_period_sec)

        return {
            "fee": MathExt.round_to(total_fee, 2),
            "status": "IDLE_FEE_ACCRUING",
            "idle_minutes": MathExt.round_to(elapsed_sec / 60.0, 1),
            "congestion_multiplier": multiplier,
            "auto_unlock_triggered": auto_unlock
        }
    end
end

return {
    "OverstaySession": OverstaySession,
    "OverstayManager": OverstayManager
}
