# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Enterprise Charging Policies for Commercial Depots, Transit & Workplaces
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import math
import math_ext as MathExt

# 1. School Bus Depot Policy
# Manages overnight fleet charging with V2G evening peak arbitrage
class SchoolBusDepotPolicy
    var morning_departure_hour # e.g. 6.5 (06:30)
    var afternoon_departure_hour # e.g. 13.5 (13:30)
    var min_v2g_reserve_soc_pct # Must retain at least 50% SoC for morning route
    var evening_peak_start_hour
    var evening_peak_end_hour

    def init()
        self.morning_departure_hour = 6.5
        self.afternoon_departure_hour = 13.5
        self.min_v2g_reserve_soc_pct = 50.0
        self.evening_peak_start_hour = 17.0 # 17:00
        self.evening_peak_end_hour = 20.0   # 20:00
    end

    def evaluate_bus_action(current_soc_pct, hour_of_day, spot_price_cents)
        var soc = real(current_soc_pct)
        var h = real(hour_of_day)
        var price = real(spot_price_cents)

        # During evening peak hours (17:00 - 20:00), if SoC > 50% and price > 25 c/kWh: V2G Export
        if h >= self.evening_peak_start_hour && h <= self.evening_peak_end_hour
            if soc > self.min_v2g_reserve_soc_pct && price >= 25.0
                var available_energy_pct = soc - self.min_v2g_reserve_soc_pct
                return {
                    "action": "V2G_DISCHARGE",
                    "discharge_power_kw": 22.0,
                    "target_soc": self.min_v2g_reserve_soc_pct,
                    "reason": "EveningPeakArbitrage"
                }
            end
        end

        # Overnight charging window (21:00 - 05:00)
        if h >= 21.0 || h <= 5.5
            return {
                "action": "CHARGE",
                "charge_power_kw": 11.0,
                "target_soc": 100.0,
                "reason": "OvernightFullCharge"
            }
        end

        return {"action": "IDLE", "charge_power_kw": 0.0, "target_soc": soc, "reason": "MiddayIdle"}
    end
end

# 2. Transit Bus Opportunity Charging Policy
# Manages high-power fast top-offs at transit route terminal layover points
class TransitBusOpportunityPolicy
    var max_opportunity_power_kw
    var max_layover_duration_sec

    def init()
        self.max_opportunity_power_kw = 450.0 # 450 kW pantograph charging
        self.max_layover_duration_sec = 360 # 6 minutes layover window
    end

    def calculate_burst_allocation(current_soc_pct, bus_priority, layover_remaining_sec)
        var soc = real(current_soc_pct)
        var prio = (bus_priority != nil) ? int(bus_priority) : 1
        var t_left = real(layover_remaining_sec)

        # Transit buses always receive maximum available capacity
        var pwr = self.max_opportunity_power_kw
        if soc >= 90.0
            pwr = 150.0 # Taper above 90%
        end

        return {
            "allocated_power_kw": pwr,
            "can_preempt_other_evses": (prio >= 2),
            "estimated_kwh_delivered": MathExt.round_to((pwr * (t_left / 3600.0)), 2),
            "status": "OPPORTUNITY_CHARGING"
        }
    end
end

# 3. Worksite Solar-Only Policy
# Guarantees zero grid draw by strictly tracking real-time rooftop solar surplus
class WorksiteSolarOnlyPolicy
    var solar_buffer_margin_kw
    var emergency_override_active

    def init()
        self.solar_buffer_margin_kw = 2.0 # 2 kW buffer to prevent grid import spikes
        self.emergency_override_active = false
    end

    def calculate_worksite_limits(total_solar_kw, base_building_kw, connected_ev_count)
        var p_solar = real(total_solar_kw)
        var p_bldg = real(base_building_kw)
        var n_ev = (connected_ev_count > 0) ? int(connected_ev_count) : 1

        var net_surplus_kw = p_solar - p_bldg - self.solar_buffer_margin_kw
        if net_surplus_kw < 0.0
            net_surplus_kw = 0.0
        end

        var per_ev_kw = net_surplus_kw / real(n_ev)
        var per_ev_amps = (per_ev_kw * 1000.0) / (3.0 * 230.0)

        # IEC 61851-1 minimum charging threshold is 6A. If per_ev_amps < 6A, pause charging
        var is_charging_active = (per_ev_amps >= 6.0)
        if !is_charging_active
            per_ev_amps = 0.0
        end

        return {
            "net_surplus_solar_kw": MathExt.round_to(net_surplus_kw, 2),
            "per_ev_amps": MathExt.round_to(per_ev_amps, 1),
            "is_active": is_charging_active,
            "grid_import_prevented": true
        }
    end
end

# 4. Highway Fast Charge Corridor Policy
# Enforces an 80% SoC cap to optimize plaza throughput
class HighwayCorridorPolicy
    var max_recommended_soc_pct
    var congested_occupancy_threshold

    def init()
        self.max_recommended_soc_pct = 80.0
        self.congested_occupancy_threshold = 0.75 # 75% plaza occupancy
    end

    def evaluate_session_limits(current_soc_pct, plaza_occupancy_ratio)
        var soc = real(current_soc_pct)
        var occ = real(plaza_occupancy_ratio)

        if soc >= self.max_recommended_soc_pct
            if occ >= self.congested_occupancy_threshold
                return {
                    "action": "TERMINATE_SESSION",
                    "reason": "80PctCapEnforcedCongestion",
                    "charge_allowed": false,
                    "auto_unlock": true
                }
            else
                return {
                    "action": "TAPER_POWER",
                    "reason": "PlazaNotCongestedAllowSlowCharge",
                    "charge_allowed": true,
                    "auto_unlock": false
                }
            end
        end

        return {
            "action": "FAST_CHARGE",
            "reason": "Below80PctSoC",
            "charge_allowed": true,
            "auto_unlock": false
        }
    end
end

# 5. Shared Residential Condo Policy
# Ensures fair-share rotating overnight charging for 16 apartments on a shared 100A service
class SharedCondoPolicy
    var service_capacity_amps
    var target_energy_kwh

    def init(panel_amps)
        self.service_capacity_amps = (panel_amps != nil) ? real(panel_amps) : 100.0
        self.target_energy_kwh = 20.0 # 20 kWh overnight guarantee
    end

    def distribute_condo_power(active_vehicles_map)
        var n = size(active_vehicles_map)
        if n == 0
            return {}
        end

        var alloc = {}
        # Count vehicles that still need energy
        var needing_energy = []
        for id : active_vehicles_map.keys()
            var v = active_vehicles_map[id]
            if v["kwh_delivered"] < self.target_energy_kwh
                needing_energy.push(id)
            end
        end

        var target_list = (size(needing_energy) > 0) ? needing_energy : []
        if size(target_list) == 0
            for id : active_vehicles_map.keys()
                target_list.push(id)
            end
        end

        var share_a = self.service_capacity_amps / real(size(target_list))
        if share_a > 32.0 share_a = 32.0 end
        if share_a < 6.0 share_a = 0.0 end

        for id : active_vehicles_map.keys()
            var is_target = false
            var i = 0
            while i < size(target_list)
                if target_list[i] == id
                    is_target = true
                    break
                end
                i = i + 1
            end
            alloc[id] = is_target ? MathExt.round_to(share_a, 1) : 0.0
        end

        return alloc
    end
end

return {
    "SchoolBusDepotPolicy": SchoolBusDepotPolicy,
    "TransitBusOpportunityPolicy": TransitBusOpportunityPolicy,
    "WorksiteSolarOnlyPolicy": WorksiteSolarOnlyPolicy,
    "HighwayCorridorPolicy": HighwayCorridorPolicy,
    "SharedCondoPolicy": SharedCondoPolicy
}
