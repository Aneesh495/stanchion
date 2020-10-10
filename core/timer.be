# Stanchion: Intelligent EV Charging Station Controller & Energy Management System
# Virtual Timekeeper, Discrete-Event Scheduler & Repeating Timers
#
# Copyright (c) 2026 Aneesh Krishna
# Licensed under the Apache License, Version 2.0

import collection as Col

var PriorityQueue = Col["PriorityQueue"]

class ScheduledTask
    var task_id
    var trigger_time_ms
    var interval_ms
    var is_repeating
    var callback
    var is_cancelled

    def init(task_id, trigger_time_ms, interval_ms, is_repeating, callback)
        self.task_id = int(task_id)
        self.trigger_time_ms = int(trigger_time_ms)
        self.interval_ms = (interval_ms != nil) ? int(interval_ms) : 0
        self.is_repeating = bool(is_repeating)
        self.callback = callback
        self.is_cancelled = false
    end
end

class VirtualScheduler
    var current_time_ms
    var task_queue
    var next_task_id
    var tasks_by_id

    def init(initial_time_ms)
        self.current_time_ms = (initial_time_ms != nil) ? int(initial_time_ms) : 0
        self.task_queue = PriorityQueue(true) # Min-heap by trigger_time_ms
        self.next_task_id = 1
        self.tasks_by_id = {}
    end

    # Schedule a one-shot timer after delay_ms
    def schedule_once(delay_ms, callback)
        var trigger = self.current_time_ms + int(delay_ms)
        var task = ScheduledTask(self.next_task_id, trigger, 0, false, callback)
        self.next_task_id = self.next_task_id + 1

        self.tasks_by_id[task.task_id] = task
        self.task_queue.push({"priority": trigger, "task": task})
        return task.task_id
    end

    # Schedule a repeating timer with initial delay and period
    def schedule_interval(delay_ms, interval_ms, callback)
        var trigger = self.current_time_ms + int(delay_ms)
        var task = ScheduledTask(self.next_task_id, trigger, interval_ms, true, callback)
        self.next_task_id = self.next_task_id + 1

        self.tasks_by_id[task.task_id] = task
        self.task_queue.push({"priority": trigger, "task": task})
        return task.task_id
    end

    # Cancel a scheduled timer
    def cancel(task_id)
        task_id = int(task_id)
        if self.tasks_by_id.contains(task_id)
            self.tasks_by_id[task_id].is_cancelled = true
            self.tasks_by_id.remove(task_id)
            return true
        end
        return false
    end

    # Advance virtual time by delta_ms and execute all due tasks
    def advance_time(delta_ms)
        delta_ms = int(delta_ms)
        if delta_ms < 0
            return 0
        end
        var target_time = self.current_time_ms + delta_ms
        var executed_count = 0

        while !self.task_queue.is_empty()
            var next_item = self.task_queue.peek()
            var due_time = next_item["priority"]
            if due_time > target_time
                break
            end

            # Pop the task
            self.task_queue.pop()
            var task = next_item["task"]

            if !task.is_cancelled
                self.current_time_ms = task.trigger_time_ms
                try
                    task.callback(self.current_time_ms)
                    executed_count = executed_count + 1
                except .. as err
                    print("[VirtualScheduler Error] Task " + str(task.task_id) + " raised: " + str(err))
                end

                if task.is_repeating && !task.is_cancelled
                    task.trigger_time_ms = task.trigger_time_ms + task.interval_ms
                    self.task_queue.push({"priority": task.trigger_time_ms, "task": task})
                else
                    self.tasks_by_id.remove(task.task_id)
                end
            end
        end

        self.current_time_ms = target_time
        return executed_count
    end

    def now_ms()
        return self.current_time_ms
    end

    def now_sec()
        return self.current_time_ms / 1000
    end

    def pending_tasks_count()
        return self.tasks_by_id.size()
    end
end

return VirtualScheduler
