# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# ISO 8601 Timestamp Parsing, Interval Arithmetic & Epoch Synchronization
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import string
import math

class TimeUtil
    # Check if a given year is a leap year in Gregorian calendar
    static def is_leap_year(year)
        year = int(year)
        if year % 400 == 0
            return true
        end
        if year % 100 == 0
            return false
        end
        return (year % 4 == 0)
    end

    # Return number of days in a given month of a given year
    static def days_in_month(year, month)
        year = int(year)
        month = int(month)
        if month < 1 || month > 12
            return 0
        end
        var days = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        if month == 2 && TimeUtil.is_leap_year(year)
            return 29
        end
        return days[month - 1]
    end

    # Convert year/month/day/hour/minute/second UTC components into Unix epoch seconds
    static def to_epoch_seconds(year, month, day, hour, min, sec)
        year = int(year)
        month = int(month)
        day = int(day)
        hour = int(hour)
        min = int(min)
        sec = int(sec)

        # Days since 1970-01-01
        var days = 0
        for y : 1970 .. (year - 1)
            if TimeUtil.is_leap_year(y)
                days = days + 366
            else
                days = days + 365
            end
        end

        for m : 1 .. (month - 1)
            days = days + TimeUtil.days_in_month(year, m)
        end

        days = days + (day - 1)
        var total_sec = days * 86400 + hour * 3600 + min * 60 + sec
        return total_sec
    end

    # Break Unix epoch seconds into a structured map: year, month, day, hour, min, sec, weekday
    static def from_epoch_seconds(epoch_sec)
        epoch_sec = int(epoch_sec)
        var sec_in_day = epoch_sec % 86400
        if sec_in_day < 0
            sec_in_day = sec_in_day + 86400
        end
        var days = (epoch_sec - sec_in_day) / 86400

        var hour = sec_in_day / 3600
        var rem = sec_in_day % 3600
        var min = rem / 60
        var sec = rem % 60

        # Weekday: 1970-01-01 was Thursday (index 4: 0=Sunday, 1=Monday, ..., 4=Thursday)
        var weekday = (days + 4) % 7
        if weekday < 0
            weekday = weekday + 7
        end

        var year = 1970
        while true
            var days_in_cur_year = TimeUtil.is_leap_year(year) ? 366 : 365
            if days >= days_in_cur_year
                days = days - days_in_cur_year
                year = year + 1
            elif days < 0
                year = year - 1
                days = days + (TimeUtil.is_leap_year(year) ? 366 : 365)
            else
                break
            end
        end

        var month = 1
        while month <= 12
            var dim = TimeUtil.days_in_month(year, month)
            if days >= dim
                days = days - dim
                month = month + 1
            else
                break
            end
        end
        var day = days + 1

        return {
            "year": year,
            "month": month,
            "day": day,
            "hour": hour,
            "min": min,
            "sec": sec,
            "weekday": weekday
        }
    end

    # Format 2-digit zero-padded number
    static def pad2(val)
        val = int(val)
        if val < 10 && val >= 0
            return "0" + string.format("%d", val)
        end
        return string.format("%d", val)
    end

    # Format epoch seconds into ISO 8601 string: YYYY-MM-DDTHH:MM:SSZ
    static def to_iso8601(epoch_sec)
        var dt = TimeUtil.from_epoch_seconds(epoch_sec)
        var s = string.format("%d-%s-%sT%s:%s:%sZ",
            dt["year"],
            TimeUtil.pad2(dt["month"]),
            TimeUtil.pad2(dt["day"]),
            TimeUtil.pad2(dt["hour"]),
            TimeUtil.pad2(dt["min"]),
            TimeUtil.pad2(dt["sec"])
        )
        return s
    end

    # Parse ISO 8601 string (e.g. "2026-03-15T08:30:00Z" or "2026-03-15T08:30:00") into epoch seconds
    static def parse_iso8601(iso_str)
        if iso_str == nil || string.count(iso_str, "-") < 2
            return 0
        end

        # Clean trailing 'Z' if present
        var cleaned = iso_str
        if string.endswith(cleaned, "Z")
            cleaned = string.split(cleaned, "Z")[0]
        end

        var parts = string.split(cleaned, "T")
        if parts.size() < 2
            parts = string.split(cleaned, " ")
        end
        if parts.size() < 2
            return 0
        end

        var date_parts = string.split(parts[0], "-")
        var time_parts = string.split(parts[1], ":")

        if date_parts.size() < 3 || time_parts.size() < 2
            return 0
        end

        var year = int(date_parts[0])
        var month = int(date_parts[1])
        var day = int(date_parts[2])

        var hour = int(time_parts[0])
        var min = int(time_parts[1])
        var sec = 0
        if time_parts.size() >= 3
            # Strip subsecond decimals if present
            var sec_part = string.split(time_parts[2], ".")[0]
            sec = int(sec_part)
        end

        return TimeUtil.to_epoch_seconds(year, month, day, hour, min, sec)
    end

    # Check whether two time intervals [start1, end1] and [start2, end2] overlap
    static def intervals_overlap(start1, end1, start2, end2)
        var s1 = int(start1)
        var e1 = int(end1)
        var s2 = int(start2)
        var e2 = int(end2)
        return (s1 <= e2) && (s2 <= e1)
    end

    # Calculate overlap duration in seconds between two intervals
    static def overlap_duration(start1, end1, start2, end2)
        var s1 = int(start1)
        var e1 = int(end1)
        var s2 = int(start2)
        var e2 = int(end2)
        var max_start = (s1 > s2) ? s1 : s2
        var min_end = (e1 < e2) ? e1 : e2
        if max_start < min_end
            return min_end - max_start
        end
        return 0
    end
end

return TimeUtil
