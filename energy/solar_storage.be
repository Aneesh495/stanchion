# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Microgrid Solar PV + Battery Energy Storage (BESS) Dispatch Optimizer
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import math_ext as MathExt

class SolarStorageOptimizer
    var solar_peak_kw
    var bess_capacity_kwh
    var bess_current_energy_kwh
    var bess_max_charge_kw
    var bess_max_discharge_kw
    var bess_min_soc_pct
    var bess_max_soc_pct
    var grid_export_allowed
    var last_solar_generation_kw

    def init(solar_peak_kw, bess_kwh, max_c_kw, max_d_kw)
        self.solar_peak_kw = (solar_peak_kw != nil) ? real(solar_peak_kw) : 100.0
        self.bess_capacity_kwh = (bess_kwh != nil) ? real(bess_kwh) : 200.0
        self.bess_current_energy_kwh = self.bess_capacity_kwh * 0.50 # Start at 50% SoC
        self.bess_max_charge_kw = (max_c_kw != nil) ? real(max_c_kw) : 50.0
        self.bess_max_discharge_kw = (max_d_kw != nil) ? real(max_d_kw) : 50.0
        self.bess_min_soc_pct = 15.0 # Reserve margin
        self.bess_max_soc_pct = 95.0 # Battery longevity margin
        self.grid_export_allowed = false
        self.last_solar_generation_kw = 0.0
    end

    def get_bess_soc_pct()
        if self.bess_capacity_kwh <= 0.0 return 0.0 end
        return MathExt.round_to((self.bess_current_energy_kwh / self.bess_capacity_kwh) * 100.0, 1)
    end

    # Optimize power flow between Solar PV, BESS, Grid, and EV charging demand
    # ev_demand_kw: aggregate power requested by all EVSEs
    # current_solar_kw: current real-time solar generation
    # delta_time_sec: elapsed time since last dispatch
    def dispatch(ev_demand_kw, current_solar_kw, delta_time_sec)
        ev_demand_kw = real(ev_demand_kw)
        current_solar_kw = real(current_solar_kw)
        self.last_solar_generation_kw = current_solar_kw
        var dt_hours = real(delta_time_sec) / 3600.0

        var solar_to_ev = 0.0
        var solar_to_bess = 0.0
        var solar_curtailed = 0.0
        var bess_discharge_to_ev = 0.0
        var grid_to_ev = 0.0

        # 1. Direct Solar to EV matching
        if current_solar_kw >= ev_demand_kw
            solar_to_ev = ev_demand_kw
            var surplus_solar = current_solar_kw - ev_demand_kw

            # 2. Store surplus solar into BESS
            var current_soc = self.get_bess_soc_pct()
            if current_soc < self.bess_max_soc_pct && surplus_solar > 0.0
                var max_absorb_kw = self.bess_max_charge_kw
                solar_to_bess = (surplus_solar < max_absorb_kw) ? surplus_solar : max_absorb_kw
                # Energy stored = power * time * round-trip efficiency (94%)
                self.bess_current_energy_kwh = self.bess_current_energy_kwh + (solar_to_bess * dt_hours * 0.94)
                surplus_solar = surplus_solar - solar_to_bess
            end

            # Any remaining surplus: either export to grid or curtail
            if surplus_solar > 0.0
                if !self.grid_export_allowed
                    solar_curtailed = surplus_solar
                end
            end
        else
            # Solar is less than EV demand
            solar_to_ev = current_solar_kw
            var deficit_kw = ev_demand_kw - solar_to_ev

            # 3. Discharge BESS to cover deficit (Peak Shaving)
            var current_soc = self.get_bess_soc_pct()
            if current_soc > self.bess_min_soc_pct && deficit_kw > 0.0
                var max_deliver_kw = self.bess_max_discharge_kw
                bess_discharge_to_ev = (deficit_kw < max_deliver_kw) ? deficit_kw : max_deliver_kw
                # Energy depleted = power * time / discharge efficiency (96%)
                self.bess_current_energy_kwh = self.bess_current_energy_kwh - (bess_discharge_to_ev * dt_hours / 0.96)
                deficit_kw = deficit_kw - bess_discharge_to_ev
            end

            # 4. Remaining deficit drawn from utility grid
            grid_to_ev = deficit_kw
        end

        # Clamp BESS energy
        var min_energy = self.bess_capacity_kwh * (self.bess_min_soc_pct / 100.0)
        var max_energy = self.bess_capacity_kwh * (self.bess_max_soc_pct / 100.0)
        self.bess_current_energy_kwh = MathExt.clamp(self.bess_current_energy_kwh, min_energy, max_energy)

        return {
            "ev_demand_kw": MathExt.round_to(ev_demand_kw, 2),
            "solar_generated_kw": MathExt.round_to(current_solar_kw, 2),
            "solar_to_ev_kw": MathExt.round_to(solar_to_ev, 2),
            "solar_to_bess_kw": MathExt.round_to(solar_to_bess, 2),
            "bess_discharge_to_ev_kw": MathExt.round_to(bess_discharge_to_ev, 2),
            "grid_import_kw": MathExt.round_to(grid_to_ev, 2),
            "solar_curtailed_kw": MathExt.round_to(solar_curtailed, 2),
            "bess_soc_pct": self.get_bess_soc_pct(),
            "renewable_fraction_pct": MathExt.round_to(((solar_to_ev + bess_discharge_to_ev) /
                ((ev_demand_kw > 0.001) ? ev_demand_kw : 1.0)) * 100.0, 1)
        }
    end
end

return SolarStorageOptimizer
