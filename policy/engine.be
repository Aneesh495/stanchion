# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Programmable Charging Policy Engine & Rule Evaluation Environment
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

class PolicyAction
    static var ALLOW_FULL_POWER = "AllowFullPower"
    static var THROTTLE_POWER   = "ThrottlePower"
    static var PAUSE_CHARGING   = "PauseCharging"
    static var PRIORITIZE       = "Prioritize"
    static var APPLY_SURCHARGE  = "ApplySurcharge"
end

class ChargingRule
    var name
    var priority
    var is_active
    var condition_fn
    var action_fn

    def init(name, priority, condition_fn, action_fn)
        self.name = str(name)
        self.priority = int(priority)
        self.is_active = true
        self.condition_fn = condition_fn
        self.action_fn = action_fn
    end

    def evaluate(context)
        if !self.is_active || self.condition_fn == nil
            return nil
        end
        try
            if self.condition_fn(context)
                if self.action_fn != nil
                    return self.action_fn(context)
                end
                return {"rule": self.name, "action": PolicyAction.ALLOW_FULL_POWER}
            end
        except .. as err
            print("[PolicyRule Error] " + self.name + ": " + str(err))
        end
        return nil
    end
end

class PolicyEngine
    var rules

    def init()
        self.rules = []
    end

    # Register a new charging policy rule
    def add_rule(name, priority, condition_fn, action_fn)
        var rule = ChargingRule(name, priority, condition_fn, action_fn)
        self.rules.push(rule)
        self._sort_rules()
        return rule
    end

    def _sort_rules()
        var n = self.rules.size()
        for i : 0 .. (n - 2)
            for j : 0 .. (n - 2 - i)
                # Higher priority number evaluates first
                if self.rules[j].priority < self.rules[j + 1].priority
                    var tmp = self.rules[j]
                    self.rules[j] = self.rules[j + 1]
                    self.rules[j + 1] = tmp
                end
            end
        end
    end

    # Evaluate context against all rules in priority order
    def evaluate_policies(context)
        var applied_actions = []
        for r : self.rules
            var res = r.evaluate(context)
            if res != nil
                res["rule_name"] = r.name
                res["priority"] = r.priority
                applied_actions.push(res)
            end
        end
        return applied_actions
    end

    def rule_count()
        return self.rules.size()
    end
end

return PolicyEngine
