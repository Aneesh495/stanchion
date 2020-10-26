# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Multi-EVSE Dynamic Load Management (DLM) & Capacity Allocation Optimizer
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import types as Types
import math_ext as MathExt

class DLMStrategy
    static var EQUAL_SHARE       = "EqualShare"
    static var PROPORTIONAL      = "Proportional"
    static var PRIORITY_WEIGHTED = "PriorityWeighted"
end

class EVSEAllocationRequest
    var evse_id
    var requested_amps
    var max_cable_amps
    var priority_weight
    var is_active
    var allocated_amps
    var is_paused

    def init(evse_id, req_amps, cable_amps, prio)
        self.evse_id = int(evse_id)
        self.requested_amps = real(req_amps)
        self.max_cable_amps = (cable_amps != nil) ? real(cable_amps) : 32.0
        self.priority_weight = (prio != nil) ? int(prio) : 10 # Default standard priority
        self.is_active = true
        self.allocated_amps = 0.0
        self.is_paused = false
    end
end

class DynamicLoadManager
    var total_grid_capacity_amps
    var strategy
    var requests
    var min_current_per_evse_a
    var last_allocation_summary

    def init(total_capacity_a, strategy)
        self.total_grid_capacity_amps = (total_capacity_a != nil) ? real(total_capacity_a) : 100.0
        self.strategy = (strategy != nil) ? str(strategy) : DLMStrategy.EQUAL_SHARE
        self.requests = {}
        self.min_current_per_evse_a = Types.MIN_CHARGING_CURRENT_A # 6.0 A
        self.last_allocation_summary = {}
    end

    def set_grid_capacity(capacity_a)
        self.total_grid_capacity_amps = real(capacity_a)
    end

    def set_strategy(strat)
        self.strategy = str(strat)
    end

    # Register or update an EVSE charging request
    def update_request(evse_id, requested_amps, cable_amps, priority)
        evse_id = int(evse_id)
        var req = EVSEAllocationRequest(evse_id, requested_amps, cable_amps, priority)
        self.requests[evse_id] = req
    end

    # Remove an EVSE when session completes
    def remove_request(evse_id)
        evse_id = int(evse_id)
        if self.requests.contains(evse_id)
            self.requests.remove(evse_id)
        end
    end

    # Compute optimal current allocation across all active EVSEs
    def solve_allocation()
        var active_evses = []
        for id : self.requests.keys()
            var req = self.requests[id]
            if req.is_active
                active_evses.push(req)
            end
        end

        var n = active_evses.size()
        if n == 0
            self.last_allocation_summary = {}
            return {}
        end

        var allocations = {}

        if self.strategy == DLMStrategy.EQUAL_SHARE
            allocations = self._solve_equal_share(active_evses)
        elif self.strategy == DLMStrategy.PROPORTIONAL
            allocations = self._solve_proportional(active_evses)
        elif self.strategy == DLMStrategy.PRIORITY_WEIGHTED
            allocations = self._solve_priority_weighted(active_evses)
        else
            allocations = self._solve_equal_share(active_evses)
        end

        self.last_allocation_summary = allocations
        return allocations
    end

    def _solve_equal_share(active_evses)
        var allocations = {}
        var remaining_capacity = self.total_grid_capacity_amps
        var remaining_evses = []

        for req : active_evses
            remaining_evses.push(req)
            allocations[req.evse_id] = 0.0
        end

        # Iterative water-filling algorithm to respect maximum cable caps
        while remaining_evses.size() > 0 && remaining_capacity > 0.01
            var share = remaining_capacity / real(remaining_evses.size())
            var capped_any = false
            var next_round = []

            for req : remaining_evses
                var cap = (req.requested_amps < req.max_cable_amps) ? req.requested_amps : req.max_cable_amps
                if share >= cap
                    allocations[req.evse_id] = cap
                    remaining_capacity = remaining_capacity - cap
                    capped_any = true
                else
                    next_round.push(req)
                end
            end

            if !capped_any
                # No more caps hit: assign share directly to remaining EVSEs
                for req : next_round
                    allocations[req.evse_id] = share
                end
                break
            end
            remaining_evses = next_round
        end

        # Enforce minimum charging current (6A): if share < 6A, pause EVSE to prevent IEC violation
        for req : active_evses
            var val = allocations[req.evse_id]
            if val < self.min_current_per_evse_a
                allocations[req.evse_id] = 0.0
                req.is_paused = true
            else
                req.is_paused = false
                allocations[req.evse_id] = MathExt.round_to(val, 2)
            end
            req.allocated_amps = allocations[req.evse_id]
        end

        return allocations
    end

    def _solve_proportional(active_evses)
        var total_requested = 0.0
        for req : active_evses
            var cap = (req.requested_amps < req.max_cable_amps) ? req.requested_amps : req.max_cable_amps
            total_requested = total_requested + cap
        end

        var allocations = {}
        if total_requested <= self.total_grid_capacity_amps
            # Entire demand can be met
            for req : active_evses
                var cap = (req.requested_amps < req.max_cable_amps) ? req.requested_amps : req.max_cable_amps
                allocations[req.evse_id] = cap
                req.allocated_amps = cap
                req.is_paused = false
            end
        else
            # Scale proportionally
            var ratio = self.total_grid_capacity_amps / total_requested
            for req : active_evses
                var cap = (req.requested_amps < req.max_cable_amps) ? req.requested_amps : req.max_cable_amps
                var scaled = cap * ratio
                if scaled < self.min_current_per_evse_a
                    scaled = 0.0
                    req.is_paused = true
                else
                    req.is_paused = false
                end
                allocations[req.evse_id] = MathExt.round_to(scaled, 2)
                req.allocated_amps = allocations[req.evse_id]
            end
        end
        return allocations
    end

    def _solve_priority_weighted(active_evses)
        # Sort active EVSEs by priority weight descending
        var n = active_evses.size()
        for i : 0 .. (n - 2)
            for j : 0 .. (n - 2 - i)
                if active_evses[j].priority_weight < active_evses[j + 1].priority_weight
                    var tmp = active_evses[j]
                    active_evses[j] = active_evses[j + 1]
                    active_evses[j + 1] = tmp
                end
            end
        end

        var allocations = {}
        var remaining = self.total_grid_capacity_amps

        for req : active_evses
            var cap = (req.requested_amps < req.max_cable_amps) ? req.requested_amps : req.max_cable_amps
            if remaining >= cap
                allocations[req.evse_id] = cap
                remaining = remaining - cap
                req.is_paused = false
            elif remaining >= self.min_current_per_evse_a
                allocations[req.evse_id] = MathExt.round_to(remaining, 2)
                remaining = 0.0
                req.is_paused = false
            else
                allocations[req.evse_id] = 0.0
                req.is_paused = true
            end
            req.allocated_amps = allocations[req.evse_id]
        end
        return allocations
    end

    def get_total_allocated_amps()
        var total = 0.0
        for id : self.last_allocation_summary.keys()
            total = total + self.last_allocation_summary[id]
        end
        return total
    end
end

return DynamicLoadManager
