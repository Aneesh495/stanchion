# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Terminal Dashboard Visualizer & HMI Status Monitor
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import string
import math_ext as MathExt

class StationHMI
    static def render_bar(current_val, max_val, width)
        var pct = (max_val > 0.001) ? (real(current_val) / real(max_val)) : 0.0
        pct = MathExt.clamp(pct, 0.0, 1.0)
        var filled = int(pct * real(width))
        var bar = ""
        for i : 1 .. filled bar = bar + "#" end
        for i : (filled + 1) .. width bar = bar + "-" end
        return bar
    end

    static def render_dashboard(station_controller, current_time_sec)
        print("================================================================================")
        print("  STANCHION EV CHARGING DEPOT CONTROLLER | SYSTEM TELEMETRY MONITOR")
        print("================================================================================")
        var total_kw = station_controller.get_total_power_kw()
        var max_kw = station_controller.config.max_grid_power_kw
        var grid_bar = StationHMI.render_bar(total_kw, max_kw, 25)

        print(string.format("  Grid Capacity: [%s] %5.1f / %5.1f kW (%3.0f%%)",
            grid_bar, total_kw, max_kw, (total_kw / max_kw) * 100.0))
        print("--------------------------------------------------------------------------------")
        print("  EVSE | Status       | Pilot | Allocated | Actual kW | Total kWh | Lock   | Cont")
        print("--------------------------------------------------------------------------------")

        for id : station_controller.evse_channels.keys()
            var ch = station_controller.evse_channels[id]
            var kw = ch.meter.get_total_active_power_kw()
            var kwh = ch.meter.energy_import_total_kwh
            var lock_s = ch.lock.is_connector_locked() ? "LOCKED" : "UNLOCKED"
            var cont_s = ch.contactor.is_closed() ? "CLOSED" : "OPEN"

            print(string.format("  #%02d  | %-12s | %-5s | %5.1f A   | %6.2f kW | %7.3f   | %-6s | %-6s",
                id, ch.get_state(), ch.pilot.get_state(), ch.current_allocated_amps, kw, kwh, lock_s, cont_s))
        end
        print("================================================================================")
    end
end

return StationHMI
