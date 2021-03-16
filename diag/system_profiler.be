# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Real-Time Subsystem Latency Profiler & Percentile Statistics
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import math
import math_ext as MathExt
import time
import string

# Performance Metric Bucket for a specific operation
class OperationMetric
    var op_name
    var sla_limit_ms
    var samples
    var max_samples
    var sla_breach_count
    var total_elapsed_ms

    def init(name, sla_ms, capacity)
        self.op_name = str(name)
        self.sla_limit_ms = (sla_ms != nil) ? real(sla_ms) : 20.0
        self.samples = []
        self.max_samples = (capacity != nil) ? int(capacity) : 500
        self.sla_breach_count = 0
        self.total_elapsed_ms = 0.0
    end

    def record_latency(duration_ms)
        var d = real(duration_ms)
        if d < 0.0 d = 0.0 end

        if d > self.sla_limit_ms
            self.sla_breach_count = self.sla_breach_count + 1
        end

        self.total_elapsed_ms = self.total_elapsed_ms + d

        if size(self.samples) >= self.max_samples
            # Evict oldest sample
            self.samples.remove(0)
        end
        self.samples.push(d)
    end

    def get_count()
        return size(self.samples)
    end

    def get_mean_ms()
        if size(self.samples) == 0 return 0.0 end
        return self.total_elapsed_ms / real(size(self.samples))
    end

    # Calculate percentiles (p50, p95, p99)
    def get_percentiles()
        if size(self.samples) == 0
            return {"min": 0.0, "p50": 0.0, "p95": 0.0, "p99": 0.0, "max": 0.0}
        end

        var sorted_s = MathExt.sort_numeric(self.samples)
        var n = size(sorted_s)

        var min_val = sorted_s[0]
        var max_val = sorted_s[n - 1]

        var idx_50 = int(0.50 * real(n - 1))
        var idx_95 = int(0.95 * real(n - 1))
        var idx_99 = int(0.99 * real(n - 1))

        return {
            "min": MathExt.round_to(min_val, 3),
            "p50": MathExt.round_to(sorted_s[idx_50], 3),
            "p95": MathExt.round_to(sorted_s[idx_95], 3),
            "p99": MathExt.round_to(sorted_s[idx_99], 3),
            "max": MathExt.round_to(max_val, 3)
        }
    end
end

# System Profiler Manager
class SystemProfiler
    var metrics

    def init()
        self.metrics = {}
        # Register standard critical path operations
        self.register_operation("SAFETY_LOOP", 10.0)      # 10 ms SLA for safety
        self.register_operation("DLM_SOLVE", 20.0)        # 20 ms SLA for DLM water-filling
        self.register_operation("METER_POLL", 5.0)        # 5 ms SLA for ADC sampling
        self.register_operation("OCPP_DISPATCH", 50.0)    # 50 ms SLA for RPC parsing
        self.register_operation("CAN_DIAGNOSTICS", 15.0)  # 15 ms SLA for CAN frames
    end

    def register_operation(name, sla_ms)
        self.metrics[str(name)] = OperationMetric(name, sla_ms, 500)
    end

    def record(name, duration_ms)
        var n = str(name)
        if !self.metrics.contains(n)
            self.register_operation(n, 20.0)
        end
        self.metrics[n].record_latency(duration_ms)
    end

    def get_summary(name)
        var n = str(name)
        if self.metrics.contains(n)
            var m = self.metrics[n]
            var p = m.get_percentiles()
            return {
                "operation": n,
                "count": m.get_count(),
                "mean_ms": MathExt.round_to(m.get_mean_ms(), 3),
                "min_ms": p["min"],
                "p50_ms": p["p50"],
                "p95_ms": p["p95"],
                "p99_ms": p["p99"],
                "max_ms": p["max"],
                "sla_limit_ms": m.sla_limit_ms,
                "sla_breaches": m.sla_breach_count
            }
        end
        return nil
    end

    # Render formatted ASCII latency matrix
    def render_report()
        var out = "--------------------------------------------------------------------------------\n"
        out = out + "  OPERATION       | SAMPLES | MEAN ms | P50 ms  | P95 ms  | P99 ms  | SLA BREACH\n"
        out = out + "--------------------------------------------------------------------------------\n"

        for k : self.metrics.keys()
            var s = self.get_summary(k)
            var line = string.format("  %-15s | %7d | %7.3f | %7.3f | %7.3f | %7.3f | %10d\n",
                s["operation"], s["count"], s["mean_ms"], s["p50_ms"], s["p95_ms"], s["p99_ms"], s["sla_breaches"])
            out = out + line
        end
        out = out + "--------------------------------------------------------------------------------"
        return out
    end
end

return {
    "OperationMetric": OperationMetric,
    "SystemProfiler": SystemProfiler
}
