# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Structured Logging Framework with Log Levels, ANSI Color & Memory Sinks
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import string
import collection as Col

var RingBuffer = Col["RingBuffer"]

class LogLevel
    static var TRACE    = 10
    static var DEBUG    = 20
    static var INFO     = 30
    static var WARN     = 40
    static var ERROR    = 50
    static var CRITICAL = 60

    static def name(lvl)
        lvl = int(lvl)
        if lvl <= 10 return "TRACE"
        elif lvl <= 20 return "DEBUG"
        elif lvl <= 30 return "INFO"
        elif lvl <= 40 return "WARN"
        elif lvl <= 50 return "ERROR"
        else return "CRIT"
        end
    end

    static def color(lvl)
        lvl = int(lvl)
        if lvl <= 10 return "\033[90m"     # Gray
        elif lvl <= 20 return "\033[36m"   # Cyan
        elif lvl <= 30 return "\033[32m"   # Green
        elif lvl <= 40 return "\033[33m"   # Yellow
        elif lvl <= 50 return "\033[31m"   # Red
        else return "\033[1;31m"           # Bold Red
        end
    end

    static var RESET = "\033[0m"
end

class Logger
    var name
    var min_level
    var use_colors
    var memory_sink

    def init(name, min_level, memory_capacity)
        self.name = (name != nil) ? str(name) : "stanchion"
        self.min_level = (min_level != nil) ? int(min_level) : LogLevel.INFO
        self.use_colors = true
        var cap = (memory_capacity != nil) ? int(memory_capacity) : 256
        self.memory_sink = RingBuffer(cap)
    end

    def set_level(lvl)
        self.min_level = int(lvl)
    end

    def log(level, message, context_map)
        level = int(level)
        if level < self.min_level
            return
        end

        var entry = {
            "level": LogLevel.name(level),
            "level_num": level,
            "module": self.name,
            "message": str(message),
            "context": (context_map != nil) ? context_map : {}
        }
        self.memory_sink.push(entry)

        var lvl_str = LogLevel.name(level)
        var formatted = ""
        if self.use_colors
            var col = LogLevel.color(level)
            var reset = LogLevel.RESET
            formatted = string.format("%s[%-5s]%s [%s] %s", col, lvl_str, reset, self.name, str(message))
        else
            formatted = string.format("[%-5s] [%s] %s", lvl_str, self.name, str(message))
        end

        if context_map != nil && context_map.size() > 0
            formatted = formatted + " | ctx=" + str(context_map)
        end

        print(formatted)
    end

    def trace(msg, ctx)
        self.log(LogLevel.TRACE, msg, ctx)
    end

    def debug(msg, ctx)
        self.log(LogLevel.DEBUG, msg, ctx)
    end

    def info(msg, ctx)
        self.log(LogLevel.INFO, msg, ctx)
    end

    def warn(msg, ctx)
        self.log(LogLevel.WARN, msg, ctx)
    end

    def error(msg, ctx)
        self.log(LogLevel.ERROR, msg, ctx)
    end

    def critical(msg, ctx)
        self.log(LogLevel.CRITICAL, msg, ctx)
    end

    def get_recent_logs()
        return self.memory_sink.to_list()
    end
end

return Logger
