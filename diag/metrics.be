# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# In-Memory Telemetry Metrics Registry & Prometheus Formatter
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import math_ext as MathExt

class Counter
    var name
    var value
    var description

    def init(name, desc)
        self.name = str(name)
        self.value = 0.0
        self.description = (desc != nil) ? str(desc) : ""
    end

    def inc(amount)
        var inc_val = (amount != nil) ? real(amount) : 1.0
        if inc_val > 0.0
            self.value = self.value + inc_val
        end
    end

    def get()
        return self.value
    end
end

class Gauge
    var name
    var value
    var description

    def init(name, desc)
        self.name = str(name)
        self.value = 0.0
        self.description = (desc != nil) ? str(desc) : ""
    end

    def set(val)
        self.value = real(val)
    end

    def inc(amount)
        var inc_val = (amount != nil) ? real(amount) : 1.0
        self.value = self.value + inc_val
    end

    def dec(amount)
        var dec_val = (amount != nil) ? real(amount) : 1.0
        self.value = self.value - dec_val
    end

    def get()
        return self.value
    end
end

class MetricsRegistry
    var counters
    var gauges

    def init()
        self.counters = {}
        self.gauges = {}
        self._init_standard_metrics()
    end

    def _init_standard_metrics()
        self.register_counter("stanchion_charging_sessions_total", "Total sessions initiated")
        self.register_counter("stanchion_energy_kwh_total", "Cumulative energy delivered in kWh")
        self.register_counter("stanchion_safety_trips_total", "Total hardware safety trip events")
        self.register_counter("stanchion_ocpp_messages_total", "Total OCPP messages processed")

        self.register_gauge("stanchion_grid_power_kw", "Instantaneous active grid power in kW")
        self.register_gauge("stanchion_active_chargers_count", "Number of EVSEs actively delivering power")
        self.register_gauge("stanchion_bess_soc_percent", "Stationary BESS battery state of charge")
    end

    def register_counter(name, desc)
        var c = Counter(name, desc)
        self.counters[name] = c
        return c
    end

    def register_gauge(name, desc)
        var g = Gauge(name, desc)
        self.gauges[name] = g
        return g
    end

    def get_counter(name)
        if self.counters.contains(name) return self.counters[name] end
        return nil
    end

    def get_gauge(name)
        if self.gauges.contains(name) return self.gauges[name] end
        return nil
    end

    # Export metrics into Prometheus text representation
    def export_prometheus_text()
        var text = ""
        for name : self.counters.keys()
            var c = self.counters[name]
            text = text + "# HELP " + name + " " + c.description + "\n"
            text = text + "# TYPE " + name + " counter\n"
            text = text + name + " " + str(c.get()) + "\n"
        end
        for name : self.gauges.keys()
            var g = self.gauges[name]
            text = text + "# HELP " + name + " " + g.description + "\n"
            text = text + "# TYPE " + name + " gauge\n"
            text = text + name + " " + str(g.get()) + "\n"
        end
        return text
    end
end

return MetricsRegistry
