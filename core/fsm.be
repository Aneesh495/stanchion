# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Finite State Machine Engine with Guards, Transitions & History
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import collection as Col

var RingBuffer = Col["RingBuffer"]

class StateTransition
    var from_state
    var event_name
    var to_state
    var guard_fn
    var action_fn

    def init(from_state, event_name, to_state, guard_fn, action_fn)
        self.from_state = str(from_state)
        self.event_name = str(event_name)
        self.to_state = str(to_state)
        self.guard_fn = guard_fn
        self.action_fn = action_fn
    end

    def can_transition(context)
        if self.guard_fn == nil
            return true
        end
        try
            return bool(self.guard_fn(context))
        except .. as err
            return false
        end
    end
end

class FiniteStateMachine
    var name
    var current_state
    var initial_state
    var transitions
    var state_entry_actions
    var state_exit_actions
    var history
    var context

    def init(name, initial_state, context)
        self.name = str(name)
        self.initial_state = str(initial_state)
        self.current_state = str(initial_state)
        self.context = (context != nil) ? context : {}
        self.transitions = []
        self.state_entry_actions = {}
        self.state_exit_actions = {}
        self.history = RingBuffer(64)
    end

    def add_transition(from_state, event_name, to_state, guard_fn, action_fn)
        var tr = StateTransition(from_state, event_name, to_state, guard_fn, action_fn)
        self.transitions.push(tr)
    end

    def on_enter(state, action_fn)
        self.state_entry_actions[str(state)] = action_fn
    end

    def on_exit(state, action_fn)
        self.state_exit_actions[str(state)] = action_fn
    end

    def trigger(event_name, event_data)
        var ev = str(event_name)
        var cur = self.current_state

        for tr : self.transitions
            if (tr.from_state == cur || tr.from_state == "*") && tr.event_name == ev
                # Check guard
                if tr.can_transition(self.context)
                    self._execute_transition(tr, event_data)
                    return true
                end
            end
        end
        return false
    end

    def _execute_transition(tr, event_data)
        var old_state = self.current_state
        var new_state = tr.to_state

        # 1. Exit action of old state
        if self.state_exit_actions.contains(old_state)
            try
                self.state_exit_actions[old_state](self.context, event_data)
            except .. as err
                print("[FSM Exit Error] " + str(err))
            end
        end

        # 2. Transition action
        if tr.action_fn != nil
            try
                tr.action_fn(self.context, event_data)
            except .. as err
                print("[FSM Action Error] " + str(err))
            end
        end

        # 3. Update state
        self.current_state = new_state
        var record = {
            "from": old_state,
            "to": new_state,
            "event": tr.event_name,
            "data": event_data
        }
        self.history.push(record)

        # 4. Entry action of new state
        if self.state_entry_actions.contains(new_state)
            try
                self.state_entry_actions[new_state](self.context, event_data)
            except .. as err
                print("[FSM Entry Error] " + str(err))
            end
        end
    end

    def get_state()
        return self.current_state
    end

    def is_in_state(state)
        return self.current_state == str(state)
    end

    def reset()
        self.current_state = self.initial_state
        self.history.clear()
    end

    def get_history()
        return self.history.to_list()
    end
end

return FiniteStateMachine
