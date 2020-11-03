# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Central Station Orchestrator, Multi-EVSE Coordination & Grid Safety Governor
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import types as Types
import evse as EVSEChannel
import dlm as DynamicLoadManager
import phase_balance as PhaseBalanceModule
import auth as AuthManager
import config as StationConfig
import math_ext as MathExt

var PhaseBalancer = PhaseBalanceModule["PhaseBalancer"]
var PhaseLoad = PhaseBalanceModule["PhaseLoad"]

class StationController
    var config
    var evse_channels
    var dlm
    var phase_balancer
    var auth_manager
    var emergency_stop_active
    var total_grid_power_kw
    var current_step_time_sec

    def init(station_cfg)
        self.config = (station_cfg != nil) ? station_cfg : StationConfig()
        self.evse_channels = {}
        self.emergency_stop_active = false
        self.total_grid_power_kw = 0.0
        self.current_step_time_sec = 0

        # Initialize EVSE Channels
        var count = self.config.evse_count
        for i : 1 .. count
            self.evse_channels[i] = EVSEChannel(i, 32.0)
        end

        # Initialize DLM and Phase Balancer
        self.dlm = DynamicLoadManager(self.config.max_grid_current_a, "EqualShare")
        self.phase_balancer = PhaseBalancer(20.0, self.config.nominal_voltage_v)
        self.auth_manager = AuthManager(self.config.default_auth_cache_ttl_sec)
    end

    # Step entire station control loop
    def step(timestamp_sec)
        self.current_step_time_sec = int(timestamp_sec)

        if self.emergency_stop_active
            for id : self.evse_channels.keys()
                self.evse_channels[id].safety.press_emergency_stop()
                self.evse_channels[id].step(timestamp_sec)
            end
            return
        end

        # 1. Update DLM requests for all active/preparing EVSEs
        for id : self.evse_channels.keys()
            var ch = self.evse_channels[id]
            if ch.fsm.is_in_state(Types.STATE_CHARGING) || ch.fsm.is_in_state(Types.STATE_PREPARING)
                var req_a = ch.connector.max_current_a
                var cable_a = (ch.pilot.cable_capacity_a > 0.0) ? ch.pilot.cable_capacity_a : req_a
                self.dlm.update_request(id, req_a, cable_a, 10)
            else
                self.dlm.remove_request(id)
            end
        end

        # 2. Solve dynamic current allocation across EVSEs
        var allocations = self.dlm.solve_allocation()
        for id : allocations.keys()
            if self.evse_channels.contains(id)
                self.evse_channels[id].set_allocated_amps(allocations[id])
            end
        end

        # 3. Step individual EVSE channels
        var total_kw = 0.0
        for id : self.evse_channels.keys()
            var ch = self.evse_channels[id]
            ch.step(timestamp_sec)
            total_kw = total_kw + ch.meter.get_total_active_power_kw()
        end
        self.total_grid_power_kw = total_kw
    end

    def press_emergency_stop()
        self.emergency_stop_active = true
        for id : self.evse_channels.keys()
            self.evse_channels[id].safety.press_emergency_stop()
            self.evse_channels[id].contactor.open(0)
            self.evse_channels[id].fsm.trigger("FAULT", "EmergencyStop")
        end
    end

    def release_emergency_stop()
        self.emergency_stop_active = false
        for id : self.evse_channels.keys()
            self.evse_channels[id].safety.release_emergency_stop()
            self.evse_channels[id].safety.clear_trips_technician()
            self.evse_channels[id].fsm.trigger("RESET", nil)
        end
    end

    def unlock_connector(evse_id)
        if self.evse_channels.contains(evse_id)
            return self.evse_channels[evse_id].lock.unlock()
        end
        return false
    end

    def set_availability(evse_id, is_operative)
        if evse_id == 0
            # Entire station
            for id : self.evse_channels.keys()
                self.evse_channels[id].connector.set_operational_status(is_operative ? "Operative" : "Inoperative")
            end
        elif self.evse_channels.contains(evse_id)
            self.evse_channels[evse_id].connector.set_operational_status(is_operative ? "Operative" : "Inoperative")
        end
    end

    def trigger_soft_reset()
        print("[StationController] Triggering soft reset...")
        for id : self.evse_channels.keys()
            self.evse_channels[id].fsm.reset()
        end
    end

    def trigger_hard_reset()
        print("[StationController] Triggering hard reset...")
        for id : self.evse_channels.keys()
            self.evse_channels[id].contactor.open(0)
            self.evse_channels[id].lock.unlock()
            self.evse_channels[id].fsm.reset()
        end
    end

    def get_evse(evse_id)
        if self.evse_channels.contains(evse_id)
            return self.evse_channels[evse_id]
        end
        return nil
    end

    def get_total_power_kw()
        return self.total_grid_power_kw
    end
end

return StationController
