# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Solar Photovoltaic Irradiance, Cloud Attenuation & Inverter Model
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import math
import math_ext as MathExt

# Solar PV simulation model for microgrid-tied EV charging depots.
# Implements solar zenith angle kinematics, clear-sky Haurwitz/ASHRAE model,
# cloud cover transients, and inverter thermal derating.
class SolarPVModel
    var peak_dc_capacity_kw
    var array_tilt_deg
    var array_azimuth_deg
    var inverter_rating_kw
    var inverter_efficiency
    var latitude_deg
    var ambient_temp_c
    var inverter_temp_c
    var cloud_factor
    var total_energy_yield_kwh

    def init(peak_dc_kw, inverter_kw, lat_deg)
        self.peak_dc_capacity_kw = (peak_dc_kw != nil) ? real(peak_dc_kw) : 50.0
        self.inverter_rating_kw = (inverter_kw != nil) ? real(inverter_kw) : 45.0
        self.array_tilt_deg = 30.0
        self.array_azimuth_deg = 180.0 # Due South
        self.inverter_efficiency = 0.972 # 97.2% CEC weighted efficiency
        self.latitude_deg = (lat_deg != nil) ? real(lat_deg) : 37.77 # San Francisco default
        self.ambient_temp_c = 22.0
        self.inverter_temp_c = 28.0
        self.cloud_factor = 1.0 # 1.0 = clear sky, 0.2 = heavy overcast
        self.total_energy_yield_kwh = 0.0
    end

    def set_cloud_factor(cf)
        var val = real(cf)
        if val < 0.05
            val = 0.05
        elif val > 1.0
            val = 1.0
        end
        self.cloud_factor = val
    end

    # Approximate solar position and clear-sky irradiance
    # day_of_year: 1..365
    # hour_of_day: 0.0..23.99
    def compute_solar_irradiance_w_m2(day_of_year, hour_of_day)
        var d = real(day_of_year)
        var h = real(hour_of_day)

        # Solar declination angle delta (Spencer/Cooper formula in radians)
        var b_deg = 360.0 * (284.0 + d) / 365.0
        var b_rad = b_deg * (math.pi / 180.0)
        var decl_rad = (23.45 * (math.pi / 180.0)) * math.sin(b_rad)

        # Hour angle omega (15 degrees per hour from solar noon at 12:00)
        var omega_deg = (h - 12.0) * 15.0
        var omega_rad = omega_deg * (math.pi / 180.0)

        var phi_rad = self.latitude_deg * (math.pi / 180.0)

        # Cosine of zenith angle: cos(theta_z) = sin(phi)*sin(delta) + cos(phi)*cos(delta)*cos(omega)
        var cos_zenith = math.sin(phi_rad) * math.sin(decl_rad) + math.cos(phi_rad) * math.cos(decl_rad) * math.cos(omega_rad)

        if cos_zenith <= 0.001
            # Sun is below horizon (night)
            return 0.0
        end

        # Clear-sky Global Horizontal Irradiance (GHI) model
        var solar_constant = 1361.0 # W/m^2 extraterrestrial
        var air_mass = 1.0 / (cos_zenith + 0.0001)
        if air_mass > 30.0
            air_mass = 30.0
        end

        # Atmospheric transmittance approximation (Meinel & Meinel)
        var transmittance = math.pow(0.7, math.pow(air_mass, 0.678))
        var direct_normal = solar_constant * transmittance
        var ghi = direct_normal * cos_zenith * self.cloud_factor

        if ghi < 0.0
            ghi = 0.0
        elif ghi > 1100.0
            ghi = 1100.0
        end

        return ghi
    end

    # Step simulation interval and compute output AC generation
    def step_solar(day_of_year, hour_of_day, delta_time_sec)
        var ghi = self.compute_solar_irradiance_w_m2(day_of_year, hour_of_day)
        var standard_test_conditions_irradiance = 1000.0 # 1000 W/m^2 STC

        # DC power from panels
        var dc_power_kw = (ghi / standard_test_conditions_irradiance) * self.peak_dc_capacity_kw

        # Cell temperature calculation: T_cell = T_amb + (NOCT - 20) * (GHI / 800)
        var noct = 45.0
        var cell_temp_c = self.ambient_temp_c + (noct - 20.0) * (ghi / 800.0)

        # Temperature coefficient: -0.38% per degree C above 25 C STC
        var temp_derating = 1.0 - 0.0038 * (cell_temp_c - 25.0)
        if temp_derating < 0.70
            temp_derating = 0.70
        elif temp_derating > 1.05
            temp_derating = 1.05
        end
        dc_power_kw = dc_power_kw * temp_derating

        # Inverter conversion and clipping
        var ac_power_kw = dc_power_kw * self.inverter_efficiency
        var is_clipping = false
        if ac_power_kw > self.inverter_rating_kw
            ac_power_kw = self.inverter_rating_kw
            is_clipping = true
        end

        # Inverter thermal dissipation: heat loss is (1 - efficiency) * ac_power_kw
        var thermal_losses_kw = ac_power_kw * (1.0 - self.inverter_efficiency)
        self.inverter_temp_c = self.ambient_temp_c + (thermal_losses_kw * 12.0)
        if self.inverter_temp_c > 65.0
            # Thermal safety throttle
            var throttle = 1.0 - 0.05 * (self.inverter_temp_c - 65.0)
            if throttle < 0.4
                throttle = 0.4
            end
            ac_power_kw = ac_power_kw * throttle
        end

        var dt_hours = real(delta_time_sec) / 3600.0
        var energy_generated_kwh = ac_power_kw * dt_hours
        self.total_energy_yield_kwh = self.total_energy_yield_kwh + energy_generated_kwh

        return {
            "ghi_w_m2": MathExt.round_to(ghi, 1),
            "dc_power_kw": MathExt.round_to(dc_power_kw, 2),
            "ac_power_kw": MathExt.round_to(ac_power_kw, 2),
            "cell_temp_c": MathExt.round_to(cell_temp_c, 1),
            "inverter_temp_c": MathExt.round_to(self.inverter_temp_c, 1),
            "is_clipping": is_clipping,
            "energy_yield_kwh": MathExt.round_to(self.total_energy_yield_kwh, 3)
        }
    end
end

return SolarPVModel
