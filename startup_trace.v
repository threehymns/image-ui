module main

import time

pub const startup_phase_names = [
	'process_launch',
	'window_creation',
	'font_work',
	'ui2_setup',
	'gpu_setup',
	'first_content',
	'first_input',
	'directory_completion',
]

pub struct StartupPhaseMark {
pub:
	phase        string
	monotonic_ns u64
	elapsed_ns   i64
	order        int
}

pub struct StartupPhaseTrace {
pub mut:
	launch_ns u64
	last_ns   u64
	marks     []StartupPhaseMark
	seen      map[string]bool
}

pub fn new_startup_phase_trace(launch_ns u64) StartupPhaseTrace {
	actual_launch := if launch_ns > 0 { launch_ns } else { time.sys_mono_now() }
	return StartupPhaseTrace{
		launch_ns: actual_launch
		last_ns:   actual_launch
		marks:     []StartupPhaseMark{}
		seen:      map[string]bool{}
	}
}

pub fn (mut trace StartupPhaseTrace) mark_at(phase string, at_ns u64) bool {
	if phase.len == 0 || phase in trace.seen {
		return false
	}
	monotonic_ns := if at_ns < trace.last_ns { trace.last_ns } else { at_ns }
	trace.marks << StartupPhaseMark{
		phase:        phase
		monotonic_ns: monotonic_ns
		elapsed_ns:   i64(monotonic_ns - trace.launch_ns)
		order:        trace.marks.len
	}
	trace.seen[phase] = true
	trace.last_ns = monotonic_ns
	return true
}

pub fn (mut trace StartupPhaseTrace) mark_now(phase string) bool {
	return trace.mark_at(phase, time.sys_mono_now())
}

pub fn (trace &StartupPhaseTrace) mark_for(phase string) ?StartupPhaseMark {
	for mark in trace.marks {
		if mark.phase == phase {
			return mark
		}
	}
	return none
}

pub fn (trace &StartupPhaseTrace) elapsed_ns(phase string) i64 {
	if mark := trace.mark_for(phase) {
		return mark.elapsed_ns
	}
	return -1
}

pub fn (trace &StartupPhaseTrace) ordered_phases() []string {
	mut phases := []string{}
	for mark in trace.marks {
		phases << mark.phase
	}
	return phases
}

pub fn (trace &StartupPhaseTrace) is_monotonic() bool {
	mut previous := trace.launch_ns
	for mark in trace.marks {
		if mark.monotonic_ns < previous {
			return false
		}
		previous = mark.monotonic_ns
	}
	return true
}

pub fn (trace &StartupPhaseTrace) has_all_startup_phases() bool {
	for phase in startup_phase_names {
		if trace.mark_for(phase) == none {
			return false
		}
	}
	return true
}
