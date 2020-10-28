# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Dynamic Time-of-Use Tariffs, Spot Price Feeds & Carbon Intensity Analytics
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import time_util as TimeUtil
import math_ext as MathExt

class TariffTier
    static var OFF_PEAK      = "OffPeak"
    static var MID_PEAK      = "MidPeak"
    static var ON_PEAK       = "OnPeak"
    static var CRITICAL_PEAK = "CriticalPeak"
end

class TariffEngine
    var currency
    var off_peak_rate_kwh
    var mid_peak_rate_kwh
    var on_peak_rate_kwh
    var critical_peak_rate_kwh
    var base_session_fee
    var idle_fee_per_min
    var spot_prices_by_hour
    var carbon_intensity_by_hour

    def init(currency_str)
        self.currency = (currency_str != nil) ? str(currency_str) : "USD"
        # Standard TOU price rates per kWh
        self.off_peak_rate_kwh = 0.12      # 12 cents/kWh (Night: 23:00 - 07:00)
        self.mid_peak_rate_kwh = 0.24      # 24 cents/kWh (Day: 07:00 - 16:00, 21:00 - 23:00)
        self.on_peak_rate_kwh = 0.48       # 48 cents/kWh (Evening: 16:00 - 21:00)
        self.critical_peak_rate_kwh = 0.95 # 95 cents/kWh (Grid stress event)
        self.base_session_fee = 1.50       # $1.50 connection fee
        self.idle_fee_per_min = 0.50       # 50 cents/min after charging complete
        self.spot_prices_by_hour = {}
        self.carbon_intensity_by_hour = {}
        self._init_default_curves()
    end

    def _init_default_curves()
        # Default 24-hour carbon intensity profile in g CO2 / kWh
        # Solar midday dips carbon intensity down to 120 g, nighttime coal/gas baseline ~450 g
        var default_carbon = [
            450, 440, 430, 420, 410, 400, # 00:00 - 05:00
            380, 320, 250, 180, 140, 120, # 06:00 - 11:00 (Solar ramp)
            110, 115, 130, 190, 280, 390, # 12:00 - 17:00 (Solar peak to afternoon drop)
            460, 480, 470, 460, 450, 450  # 18:00 - 23:00 (Evening demand peak)
        ]
        for h : 0 .. 23
            self.carbon_intensity_by_hour[h] = default_carbon[h]
            # Default spot price curve ($/kWh)
            if h >= 16 && h <= 20
                self.spot_prices_by_hour[h] = 0.45
            elif h >= 7 && h <= 22
                self.spot_prices_by_hour[h] = 0.22
            else
                self.spot_prices_by_hour[h] = 0.11
            end
        end
    end

    # Determine tariff tier from timestamp
    def get_tier_at_time(epoch_sec)
        var dt = TimeUtil.from_epoch_seconds(epoch_sec)
        var hour = dt["hour"]
        var weekday = dt["weekday"]

        # Weekends (0=Sun, 6=Sat) enjoy Off-Peak rates all day
        if weekday == 0 || weekday == 6
            return TariffTier.OFF_PEAK
        end

        # Weekday schedule
        if hour >= 16 && hour < 21
            return TariffTier.ON_PEAK
        elif (hour >= 7 && hour < 16) || (hour >= 21 && hour < 23)
            return TariffTier.MID_PEAK
        else
            return TariffTier.OFF_PEAK
        end
    end

    # Get active electricity price per kWh at given epoch timestamp
    def get_price_per_kwh(epoch_sec)
        var tier = self.get_tier_at_time(epoch_sec)
        if tier == TariffTier.ON_PEAK
            return self.on_peak_rate_kwh
        elif tier == TariffTier.MID_PEAK
            return self.mid_peak_rate_kwh
        elif tier == TariffTier.CRITICAL_PEAK
            return self.critical_peak_rate_kwh
        else
            return self.off_peak_rate_kwh
        end
    end

    # Get carbon intensity in g CO2 / kWh at given epoch timestamp
    def get_carbon_intensity(epoch_sec)
        var dt = TimeUtil.from_epoch_seconds(epoch_sec)
        var hour = dt["hour"]
        if self.carbon_intensity_by_hour.contains(hour)
            return self.carbon_intensity_by_hour[hour]
        end
        return 350.0
    end

    # Calculate full session financial receipt
    def calculate_session_cost(energy_kwh, start_epoch, end_epoch, idle_duration_min, is_vip)
        var energy = real(energy_kwh)
        var rate = self.get_price_per_kwh(start_epoch)
        var energy_cost = energy * rate

        # Connection fee (waived for VIP)
        var conn_fee = (is_vip) ? 0.0 : self.base_session_fee

        # Overstay / Idle fee (first 15 minutes grace period free)
        var idle_cost = 0.0
        var idle_min = (idle_duration_min != nil) ? int(idle_duration_min) : 0
        if idle_min > 15
            idle_cost = real(idle_min - 15) * self.idle_fee_per_min
        end

        var subtotal = conn_fee + energy_cost + idle_cost
        var tax = subtotal * 0.0825 # 8.25% sales tax
        var total = subtotal + tax

        return {
            "currency": self.currency,
            "energy_kwh": MathExt.round_to(energy, 3),
            "rate_per_kwh": MathExt.round_to(rate, 4),
            "energy_cost": MathExt.round_to(energy_cost, 2),
            "connection_fee": MathExt.round_to(conn_fee, 2),
            "idle_fee": MathExt.round_to(idle_cost, 2),
            "tax": MathExt.round_to(tax, 2),
            "total_cost": MathExt.round_to(total, 2)
        }
    end
end

return TariffEngine
