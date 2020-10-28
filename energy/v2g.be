# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Vehicle-to-Grid (V2G) Bidirectional Power Router & Battery Reserve Guard
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import math_ext as MathExt

class V2GSession
    var evse_id
    var ev_battery_capacity_kwh
    var current_soc_pct
    var user_min_soc_pct
    var max_discharge_rate_kw
    var energy_discharged_kwh
    var is_v2g_enabled

    def init(evse_id, batt_kwh, current_soc, min_soc, max_d_kw)
        self.evse_id = int(evse_id)
        self.ev_battery_capacity_kwh = real(batt_kwh)
        self.current_soc_pct = real(current_soc)
        self.user_min_soc_pct = (min_soc != nil) ? real(min_soc) : 40.0 # Never drain below 40%
        self.max_discharge_rate_kw = (max_d_kw != nil) ? real(max_d_kw) : 11.0 # 11 kW AC/DC V2G
        self.energy_discharged_kwh = 0.0
        self.is_v2g_enabled = true
    end

    # Calculate maximum discharge power allowed at this moment without violating user minimum SoC
    def get_available_discharge_power_kw()
        if !self.is_v2g_enabled || self.current_soc_pct <= self.user_min_soc_pct
            return 0.0
        end
        return self.max_discharge_rate_kw
    end

    # Apply discharge power for delta_time_sec and update vehicle battery SoC
    def execute_discharge(power_kw, delta_time_sec)
        power_kw = real(power_kw)
        if power_kw <= 0.0 || self.current_soc_pct <= self.user_min_soc_pct
            return 0.0
        end

        var max_kw = self.get_available_discharge_power_kw()
        var actual_kw = (power_kw < max_kw) ? power_kw : max_kw
        var dt_hours = real(delta_time_sec) / 3600.0
        var energy_kwh = actual_kw * dt_hours

        # Update battery SoC
        var delta_soc = (energy_kwh / self.ev_battery_capacity_kwh) * 100.0
        self.current_soc_pct = self.current_soc_pct - delta_soc
        if self.current_soc_pct < self.user_min_soc_pct
            self.current_soc_pct = self.user_min_soc_pct
        end

        self.energy_discharged_kwh = self.energy_discharged_kwh + energy_kwh
        return actual_kw
    end
end

class V2GRouter
    var active_v2g_sessions

    def init()
        self.active_v2g_sessions = {}
    end

    def register_vehicle(evse_id, batt_kwh, cur_soc, min_soc, max_d_kw)
        var s = V2GSession(evse_id, batt_kwh, cur_soc, min_soc, max_d_kw)
        self.active_v2g_sessions[int(evse_id)] = s
    end

    def unregister_vehicle(evse_id)
        evse_id = int(evse_id)
        if self.active_v2g_sessions.contains(evse_id)
            self.active_v2g_sessions.remove(evse_id)
        end
    end

    # Aggregate total V2G discharge capacity across all plugged-in bidirectional vehicles
    def get_total_v2g_capacity_kw()
        var total = 0.0
        for id : self.active_v2g_sessions.keys()
            total = total + self.active_v2g_sessions[id].get_available_discharge_power_kw()
        end
        return total
    end

    # Dispatch reverse power flow from available vehicles to shave local grid peaks
    def dispatch_v2g(required_support_kw, delta_time_sec)
        required_support_kw = real(required_support_kw)
        var sessions = []
        for id : self.active_v2g_sessions.keys()
            sessions.push(self.active_v2g_sessions[id])
        end

        var delivered = 0.0
        var remaining = required_support_kw

        for s : sessions
            if remaining <= 0.01 break end
            var act = s.execute_discharge(remaining, delta_time_sec)
            delivered = delivered + act
            remaining = remaining - act
        end

        return MathExt.round_to(delivered, 2)
    end
end

var V2GModule = {
    "V2GSession": V2GSession,
    "V2GRouter": V2GRouter
}

return V2GModule
