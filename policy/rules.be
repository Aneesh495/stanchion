# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Standard Charging Policy Rule Library & Fleet Automation Hooks
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import engine as PolicyEngine
import types as Types

class StandardRules
    # Rule 1: Fleet Departure Guarantee
    # If vehicle has a departure deadline within 2 hours and SoC is below target 85%,
    # elevate to emergency priority and bypass all throttling
    static def fleet_departure_guarantee()
        return {
            "name": "FleetDepartureGuarantee",
            "priority": 1000,
            "condition": def(ctx)
                if !ctx.contains("departure_epoch_sec") || !ctx.contains("current_epoch_sec")
                    return false
                end
                var time_left_sec = int(ctx["departure_epoch_sec"]) - int(ctx["current_epoch_sec"])
                var soc = ctx.contains("current_soc_pct") ? real(ctx["current_soc_pct"]) : 100.0
                # Less than 2 hours left (7200s) and battery < 85%
                return (time_left_sec <= 7200 && time_left_sec > 0 && soc < 85.0)
            end,
            "action": def(ctx)
                return {
                    "action": "Prioritize",
                    "override_amps": 32.0,
                    "reason": "Fleet vehicle departure deadline imminent"
                }
            end
        }
    end

    # Rule 2: Employee Priority during Business Hours
    # During 08:00 - 17:00, employees get priority over public guest users
    static def employee_priority()
        return {
            "name": "EmployeePriority",
            "priority": 500,
            "condition": def(ctx)
                var group = ctx.contains("user_group") ? str(ctx["user_group"]) : "Public"
                var hour = ctx.contains("hour_of_day") ? int(ctx["hour_of_day"]) : 12
                return (group == "Employee" && hour >= 8 && hour < 17)
            end,
            "action": def(ctx)
                return {
                    "action": "Prioritize",
                    "priority_weight": 50,
                    "reason": "Employee badge priority during business hours"
                }
            end
        }
    end

    # Rule 3: Green Power Only (Eco Mode)
    # If user selected Eco Mode, cap charging to current renewable solar availability
    static def green_power_only()
        return {
            "name": "GreenPowerOnly",
            "priority": 300,
            "condition": def(ctx)
                return ctx.contains("eco_mode") && bool(ctx["eco_mode"]) == true
            end,
            "action": def(ctx)
                var solar_kw = ctx.contains("available_solar_kw") ? real(ctx["available_solar_kw"]) : 0.0
                var max_solar_a = (solar_kw * 1000.0) / (1.7320508 * 400.0)
                if max_solar_a < Types.MIN_CHARGING_CURRENT_A
                    return {
                        "action": "PauseCharging",
                        "reason": "Eco Mode active: Insufficient local solar generation"
                    }
                else
                    return {
                        "action": "ThrottlePower",
                        "max_amps": max_solar_a,
                        "reason": "Eco Mode active: Throttled to match solar generation"
                    }
                end
            end
        }
    end

    # Rule 4: Peak Demand Avoidance
    # During Critical Peak pricing periods (> 80c/kWh), throttle non-VIP charging to minimum 6A
    static def peak_demand_avoidance()
        return {
            "name": "PeakDemandAvoidance",
            "priority": 700,
            "condition": def(ctx)
                var tariff_rate = ctx.contains("current_tariff_rate") ? real(ctx["current_tariff_rate"]) : 0.0
                var is_vip = ctx.contains("is_vip") ? bool(ctx["is_vip"]) : false
                return (tariff_rate >= 0.80 && !is_vip)
            end,
            "action": def(ctx)
                return {
                    "action": "ThrottlePower",
                    "max_amps": Types.MIN_CHARGING_CURRENT_A,
                    "reason": "Critical peak pricing in effect: Throttled to minimum current"
                }
            end
        }
    end

    # Rule 5: Overstay Fee Enforcement
    # If battery has reached 100% and vehicle remains plugged in > 15 minutes
    static def overstay_fee_enforcement()
        return {
            "name": "OverstayFeeEnforcement",
            "priority": 200,
            "condition": def(ctx)
                var soc = ctx.contains("current_soc_pct") ? real(ctx["current_soc_pct"]) : 0.0
                var idle_min = ctx.contains("idle_duration_min") ? int(ctx["idle_duration_min"]) : 0
                return (soc >= 99.5 && idle_min > 15)
            end,
            "action": def(ctx)
                var idle_min = int(ctx["idle_duration_min"])
                return {
                    "action": "ApplySurcharge",
                    "fee_per_min": 0.50,
                    "chargeable_minutes": idle_min - 15,
                    "reason": "Overstay fee applied after 15 min grace period"
                }
            end
        }
    end
end

return StandardRules
