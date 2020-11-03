# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Real-Time Telemetry Ring Buffers, Rate-of-Change Analysis & Statistics
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import collection as Col
import math_ext as MathExt

var RingBuffer = Col["RingBuffer"]

class TelemetryChannel
    var name
    var buffer
    var capacity

    def init(name, capacity)
        self.name = str(name)
        self.capacity = (capacity != nil) ? int(capacity) : 60 # 60 samples default
        self.buffer = RingBuffer(self.capacity)
    end

    def record(val)
        self.buffer.push(real(val))
    end

    def mean()
        return MathExt.mean(self.buffer.to_list())
    end

    def stddev()
        return MathExt.stddev(self.buffer.to_list())
    end

    def min()
        var l = self.buffer.to_list()
        if l.size() == 0 return 0.0 end
        var m = l[0]
        for x : l if x < m m = x end end
        return m
    end

    def max()
        var l = self.buffer.to_list()
        if l.size() == 0 return 0.0 end
        var m = l[0]
        for x : l if x > m m = x end end
        return m
    end

    # Compute instantaneous derivative (d/dt) between latest two samples
    def derivative(dt_sec)
        var n = self.buffer.size()
        if n < 2 || dt_sec <= 0.0001
            return 0.0
        end
        var latest = self.buffer.latest()
        var prev = self.buffer.get(n - 2)
        return (latest - prev) / real(dt_sec)
    end
end

class StationTelemetry
    var power_channel
    var current_channel
    var voltage_channel
    var temp_channel
    var freq_channel

    def init(history_capacity)
        var cap = (history_capacity != nil) ? int(history_capacity) : 60
        self.power_channel = TelemetryChannel("Power_kW", cap)
        self.current_channel = TelemetryChannel("Current_A", cap)
        self.voltage_channel = TelemetryChannel("Voltage_V", cap)
        self.temp_channel = TelemetryChannel("Temperature_C", cap)
        self.freq_channel = TelemetryChannel("Frequency_Hz", cap)
    end

    def sample(kw, current_a, voltage_v, temp_c, freq_hz)
        self.power_channel.record(kw)
        self.current_channel.record(current_a)
        self.voltage_channel.record(voltage_v)
        self.temp_channel.record(temp_c)
        self.freq_channel.record(freq_hz)
    end

    def get_summary()
        return {
            "power_kw": {
                "current": self.power_channel.buffer.latest(),
                "mean": MathExt.round_to(self.power_channel.mean(), 2),
                "max": MathExt.round_to(self.power_channel.max(), 2)
            },
            "current_a": {
                "current": self.current_channel.buffer.latest(),
                "mean": MathExt.round_to(self.current_channel.mean(), 2),
                "max": MathExt.round_to(self.current_channel.max(), 2)
            },
            "voltage_v": {
                "current": self.voltage_channel.buffer.latest(),
                "mean": MathExt.round_to(self.voltage_channel.mean(), 2)
            },
            "temp_c": {
                "current": self.temp_channel.buffer.latest(),
                "max": MathExt.round_to(self.temp_channel.max(), 2)
            },
            "frequency_hz": {
                "current": self.freq_channel.buffer.latest(),
                "mean": MathExt.round_to(self.freq_channel.mean(), 2)
            }
        }
    end
end

return StationTelemetry
