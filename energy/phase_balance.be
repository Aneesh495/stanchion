# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# 3-Phase Dynamic Load Balancer & Single-Phase Asymmetry Mitigator
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import types as Types
import math
import math_ext as MathExt

class PhaseLoad
    var current_l1_a
    var current_l2_a
    var current_l3_a

    def init(l1, l2, l3)
        self.current_l1_a = (l1 != nil) ? real(l1) : 0.0
        self.current_l2_a = (l2 != nil) ? real(l2) : 0.0
        self.current_l3_a = (l3 != nil) ? real(l3) : 0.0
    end

    def max_phase_current()
        var m = self.current_l1_a
        if self.current_l2_a > m m = self.current_l2_a end
        if self.current_l3_a > m m = self.current_l3_a end
        return m
    end

    def min_phase_current()
        var m = self.current_l1_a
        if self.current_l2_a < m m = self.current_l2_a end
        if self.current_l3_a < m m = self.current_l3_a end
        return m
    end

    def get_unbalance_amps()
        return self.max_phase_current() - self.min_phase_current()
    end

    def get_unbalance_kva(voltage_ln_v)
        var unbalance_a = self.get_unbalance_amps()
        return (unbalance_a * real(voltage_ln_v)) / 1000.0
    end
end

class PhaseBalancer
    var max_allowed_unbalance_a
    var nominal_voltage_ln_v
    var phase_assignments # Map of evse_id -> "L1", "L2", "L3", or "L1_L2_L3"

    def init(max_unbalance_a, nominal_voltage_v)
        self.max_allowed_unbalance_a = (max_unbalance_a != nil) ? real(max_unbalance_a) : 20.0 # 4.6 kVA at 230V
        self.nominal_voltage_ln_v = (nominal_voltage_v != nil) ? real(nominal_voltage_v) : 230.0
        self.phase_assignments = {}
    end

    # Select the optimal phase for a newly connecting single-phase vehicle to minimize unbalance
    def select_optimal_phase(current_loads)
        # Find phase with lowest existing current
        var l1 = current_loads.current_l1_a
        var l2 = current_loads.current_l2_a
        var l3 = current_loads.current_l3_a

        if l1 <= l2 && l1 <= l3
            return Types.PHASE_1_L1
        elif l2 <= l1 && l2 <= l3
            return Types.PHASE_1_L2
        else
            return Types.PHASE_1_L3
        end
    end

    # Register an EVSE connection type (single-phase vs 3-phase)
    def assign_evse_phase(evse_id, phase_str)
        self.phase_assignments[int(evse_id)] = str(phase_str)
    end

    # Aggregate current per phase from list of active EVSE meter readings
    def aggregate_phase_loads(evse_readings_map)
        var total_l1 = 0.0
        var total_l2 = 0.0
        var total_l3 = 0.0

        for id : evse_readings_map.keys()
            var r = evse_readings_map[id]
            # r has "L1", "L2", "L3" currents
            if r.contains("L1") total_l1 = total_l1 + real(r["L1"]) end
            if r.contains("L2") total_l2 = total_l2 + real(r["L2"]) end
            if r.contains("L3") total_l3 = total_l3 + real(r["L3"]) end
        end

        return PhaseLoad(total_l1, total_l2, total_l3)
    end

    # Check whether aggregate phase unbalance exceeds statutory limits
    def is_unbalance_excessive(phase_load)
        return phase_load.get_unbalance_amps() > self.max_allowed_unbalance_a
    end

    # Determine curtailment reduction for single-phase EVSEs on the highest phase to restore balance
    def calculate_phase_curtailment(phase_load)
        var unbalance = phase_load.get_unbalance_amps()
        if unbalance <= self.max_allowed_unbalance_a
            return {"curtailment_required": false, "reduction_amps": 0.0, "congested_phase": nil}
        end

        var excess = unbalance - self.max_allowed_unbalance_a
        var max_cur = phase_load.max_phase_current()
        var congested = Types.PHASE_1_L1
        if phase_load.current_l2_a == max_cur
            congested = Types.PHASE_1_L2
        elif phase_load.current_l3_a == max_cur
            congested = Types.PHASE_1_L3
        end

        return {
            "curtailment_required": true,
            "reduction_amps": MathExt.round_to(excess, 2),
            "congested_phase": congested
        }
    end
end

var PhaseBalanceModule = {
    "PhaseLoad": PhaseLoad,
    "PhaseBalancer": PhaseBalancer
}

return PhaseBalanceModule
