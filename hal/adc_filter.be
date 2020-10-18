# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# ADC Analog Signal Conditioning, Anti-Aliasing & Noise Rejection Filters
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import collection as Col
import math_ext as MathExt

var RingBuffer = Col["RingBuffer"]

class ADCFilter
    var channel_name
    var window_size
    var buffer
    var alpha_ema
    var ema_value
    var last_filtered_value
    var debounce_count
    var debounce_threshold

    def init(name, window_size, alpha_ema)
        self.channel_name = str(name)
        self.window_size = (window_size != nil) ? int(window_size) : 8
        self.buffer = RingBuffer(self.window_size)
        self.alpha_ema = (alpha_ema != nil) ? real(alpha_ema) : 0.25
        self.ema_value = nil
        self.last_filtered_value = 0.0
        self.debounce_count = 0
        self.debounce_threshold = 3
    end

    # Feed a raw ADC sample into the filter pipeline
    def update(raw_sample)
        var val = real(raw_sample)
        self.buffer.push(val)

        # 1. Update Exponential Moving Average (EMA)
        if self.ema_value == nil
            self.ema_value = val
        else
            self.ema_value = self.alpha_ema * val + (1.0 - self.alpha_ema) * self.ema_value
        end

        # 2. Compute trimmed mean (rejecting highest and lowest outlier if buffer is full)
        var samples = self.buffer.to_list()
        var filtered = 0.0

        if samples.size() >= 4
            # Bubble sort samples to trim min and max
            var n = samples.size()
            for i : 0 .. (n - 2)
                for j : 0 .. (n - 2 - i)
                    if samples[j] > samples[j + 1]
                        var tmp = samples[j]
                        samples[j] = samples[j + 1]
                        samples[j + 1] = tmp
                    end
                end
            end
            # Sum middle elements
            var sum_mid = 0.0
            for i : 1 .. (n - 2)
                sum_mid = sum_mid + samples[i]
            end
            filtered = sum_mid / real(n - 2)
        else
            filtered = MathExt.mean(samples)
        end

        self.last_filtered_value = filtered
        return filtered
    end

    # State debounce: requires reading to stay in a given band for N consecutive cycles
    def debounce_in_band(min_val, max_val)
        min_val = real(min_val)
        max_val = real(max_val)
        var v = self.last_filtered_value
        if v >= min_val && v <= max_val
            self.debounce_count = self.debounce_count + 1
            if self.debounce_count >= self.debounce_threshold
                return true
            end
        else
            self.debounce_count = 0
        end
        return false
    end

    def get_filtered()
        return self.last_filtered_value
    end

    def get_ema()
        return (self.ema_value != nil) ? self.ema_value : 0.0
    end

    def reset()
        self.buffer.clear()
        self.ema_value = nil
        self.last_filtered_value = 0.0
        self.debounce_count = 0
    end
end

return ADCFilter
