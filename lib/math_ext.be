# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Advanced Mathematical Extensions, Numerical Analysis & Linear Interpolation
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import math

class MathExt
    # Compute the arithmetic mean of a numeric list
    static def mean(values)
        if values == nil || values.size() == 0
            return 0.0
        end
        var total = 0.0
        for v : values
            total = total + real(v)
        end
        return total / real(values.size())
    end

    # Compute sample variance
    static def variance(values)
        if values == nil || values.size() < 2
            return 0.0
        end
        var avg = MathExt.mean(values)
        var sum_sq = 0.0
        for v : values
            var diff = real(v) - avg
            sum_sq = sum_sq + (diff * diff)
        end
        return sum_sq / real(values.size() - 1)
    end

    # Compute sample standard deviation
    static def stddev(values)
        var var_val = MathExt.variance(values)
        return math.sqrt(var_val)
    end

    # Clamp a value between min_val and max_val inclusive
    static def clamp(val, min_val, max_val)
        val = real(val)
        min_val = real(min_val)
        max_val = real(max_val)
        if val < min_val
            return min_val
        elif val > max_val
            return max_val
        end
        return val
    end

    # 1D Piecewise Linear Interpolation
    # x_points: sorted list of X coordinates
    # y_points: list of corresponding Y values
    # query_x: target X coordinate
    static def lerp_1d(x_points, y_points, query_x)
        var n = x_points.size()
        if n == 0
            return 0.0
        end
        if n == 1 || query_x <= x_points[0]
            return real(y_points[0])
        end
        if query_x >= x_points[n - 1]
            return real(y_points[n - 1])
        end

        # Binary search for interval
        var low = 0
        var high = n - 1
        while low <= high
            var mid = (low + high) / 2
            if x_points[mid] <= query_x && (mid == n - 1 || query_x < x_points[mid + 1])
                var x0 = real(x_points[mid])
                var x1 = real(x_points[mid + 1])
                var y0 = real(y_points[mid])
                var y1 = real(y_points[mid + 1])
                if x1 == x0
                    return y0
                end
                var t = (query_x - x0) / (x1 - x0)
                return y0 + t * (y1 - y0)
            elif x_points[mid] > query_x
                high = mid - 1
            else
                low = mid + 1
            end
        end
        return real(y_points[0])
    end

    # Moving average filter over a sliding window
    static def moving_average(values, window_size)
        if window_size <= 0 || values.size() == 0
            return []
        end
        var result = []
        var window_sum = 0.0
        var count = 0
        var n = values.size()

        for i : 0 .. (n - 1)
            window_sum = window_sum + real(values[i])
            count = count + 1
            if count > window_size
                window_sum = window_sum - real(values[i - window_size])
                count = window_size
            end
            result.push(window_sum / real(count))
        end
        return result
    end

    # Exponential Moving Average (EMA)
    # alpha: smoothing factor between 0.0 and 1.0
    static def exponential_moving_average(values, alpha)
        if values.size() == 0
            return []
        end
        var result = []
        var current_ema = real(values[0])
        result.push(current_ema)

        for i : 1 .. (values.size() - 1)
            current_ema = alpha * real(values[i]) + (1.0 - alpha) * current_ema
            result.push(current_ema)
        end
        return result
    end

    # Round a float to a specified number of decimal places
    static def round_to(val, decimals)
        var factor = math.pow(10.0, real(decimals))
        var v = real(val) * factor
        var rounded = 0.0
        if v >= 0.0
            rounded = math.floor(v + 0.5)
        else
            rounded = math.ceil(v - 0.5)
        end
        return rounded / factor
    end

    # Approximate root-mean-square (RMS) of discrete waveform samples
    static def rms(samples)
        if samples.size() == 0
            return 0.0
        end
        var sum_sq = 0.0
        for s : samples
            var val = real(s)
            sum_sq = sum_sq + (val * val)
        end
        return math.sqrt(sum_sq / real(samples.size()))
    end

    # Apparent power (kVA) from active power P (kW) and reactive power Q (kVAR)
    static def apparent_power(active_kw, reactive_kvar)
        var p = real(active_kw)
        var q = real(reactive_kvar)
        return math.sqrt(p * p + q * q)
    end

    # Power factor calculation: P / S
    static def power_factor(active_kw, reactive_kvar)
        var s = MathExt.apparent_power(active_kw, reactive_kvar)
        if s <= 0.0001
            return 1.0
        end
        return MathExt.clamp(real(active_kw) / s, -1.0, 1.0)
    end

    # Calculate 3-phase line current given 3-phase active power and line-to-line voltage
    static def three_phase_current(active_power_kw, line_voltage_v, pf)
        if line_voltage_v <= 0.0 || pf <= 0.0
            return 0.0
        end
        var sqrt3 = 1.7320508
        var current = (real(active_power_kw) * 1000.0) / (sqrt3 * real(line_voltage_v) * real(pf))
        return current
    end
end

return MathExt
