# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Fleet Depot Charging Schedule Optimizer & Transformer Load Leveller
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import math_ext as MathExt

class FleetVehicle
    var vehicle_id
    var battery_capacity_kwh
    var current_soc_pct
    var target_soc_pct
    var arrival_epoch_sec
    var departure_epoch_sec
    var charger_max_power_kw
    var assigned_evse_id
    var scheduled_start_epoch_sec

    def init(vid, capacity, cur_soc, target_soc, arr_epoch, dep_epoch, max_kw)
        self.vehicle_id = str(vid)
        self.battery_capacity_kwh = real(capacity)
        self.current_soc_pct = real(cur_soc)
        self.target_soc_pct = (target_soc != nil) ? real(target_soc) : 85.0
        self.arrival_epoch_sec = int(arr_epoch)
        self.departure_epoch_sec = int(dep_epoch)
        self.charger_max_power_kw = (max_kw != nil) ? real(max_kw) : 22.0
        self.assigned_evse_id = nil
        self.scheduled_start_epoch_sec = nil
    end

    # Energy required to hit target SoC in kWh
    def energy_needed_kwh()
        if self.current_soc_pct >= self.target_soc_pct
            return 0.0
        end
        var delta_soc = (self.target_soc_pct - self.current_soc_pct) / 100.0
        return self.battery_capacity_kwh * delta_soc
    end

    # Minimum charging duration in seconds at maximum power
    def min_charge_duration_sec()
        var needed_kwh = self.energy_needed_kwh()
        if needed_kwh <= 0.0
            return 0
        end
        var hours = needed_kwh / self.charger_max_power_kw
        return int(hours * 3600.0)
    end

    # Latest epoch time by which charging MUST start to meet departure deadline
    def latest_start_epoch_sec()
        return self.departure_epoch_sec - self.min_charge_duration_sec()
    end

    # Laxity (slack time) in seconds: how long vehicle can wait before it must charge
    def laxity_sec(current_epoch_sec)
        return self.latest_start_epoch_sec() - int(current_epoch_sec)
    end
end

class FleetScheduler
    var depot_max_power_kw
    var vehicles
    var active_schedule

    def init(depot_max_kw)
        self.depot_max_power_kw = (depot_max_kw != nil) ? real(depot_max_kw) : 150.0
        self.vehicles = []
        self.active_schedule = []
    end

    def add_vehicle(vehicle)
        self.vehicles.push(vehicle)
    end

    # Least-Laxity-First (LLF) scheduling algorithm
    # Prioritizes vehicles with smallest slack time before departure deadline
    def solve_schedule(current_epoch_sec)
        current_epoch_sec = int(current_epoch_sec)
        var n = self.vehicles.size()
        if n == 0 return [] end

        # Sort vehicles by latest start time ascending (Least Laxity First)
        for i : 0 .. (n - 2)
            for j : 0 .. (n - 2 - i)
                if self.vehicles[j].latest_start_epoch_sec() > self.vehicles[j + 1].latest_start_epoch_sec()
                    var tmp = self.vehicles[j]
                    self.vehicles[j] = self.vehicles[j + 1]
                    self.vehicles[j + 1] = tmp
                end
            end
        end

        var schedule = []
        var remaining_depot_power = self.depot_max_power_kw

        for v : self.vehicles
            var p_needed = v.charger_max_power_kw
            var allocated_power = 0.0
            var status = "Deferred"

            if remaining_depot_power >= p_needed
                allocated_power = p_needed
                remaining_depot_power = remaining_depot_power - p_needed
                status = "Charging"
            elif remaining_depot_power >= 6.0 # Minimum 6 kW
                allocated_power = remaining_depot_power
                remaining_depot_power = 0.0
                status = "Throttled"
            else
                status = "Queued"
            end

            schedule.push({
                "vehicle_id": v.vehicle_id,
                "status": status,
                "allocated_power_kw": MathExt.round_to(allocated_power, 2),
                "energy_needed_kwh": MathExt.round_to(v.energy_needed_kwh(), 2),
                "departure_sec": v.departure_epoch_sec,
                "laxity_minutes": int(v.laxity_sec(current_epoch_sec) / 60)
            })
        end

        self.active_schedule = schedule
        return schedule
    end

    def get_schedule()
        return self.active_schedule
    end
end

var FleetSchedulerModule = {
    "Vehicle": FleetVehicle,
    "Scheduler": FleetScheduler
}

return FleetSchedulerModule
