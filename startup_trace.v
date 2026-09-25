module main

import time
import ui2

pub const startup_phases = [
	ui2.StartupPhase.process_launch,
	ui2.StartupPhase.window_creation,
	ui2.StartupPhase.font_work,
	ui2.StartupPhase.ui2_setup,
	ui2.StartupPhase.gpu_context_initialization,
	ui2.StartupPhase.first_content,
	ui2.StartupPhase.first_input,
	ui2.StartupPhase.directory_completion,
]

pub struct StartupPhaseMark {
pub:
	phase        ui2.StartupPhase
	monotonic_ns u64
	elapsed_ns   i64
	order        int
}

pub struct StartupPhaseTrace {
pub mut:
	launch_ns u64
	last_ns   u64
	marks     []StartupPhaseMark
	seen      map[ui2.StartupPhase]bool
}

pub fn new_startup_phase_trace(launch_ns u64) StartupPhaseTrace {
	actual_launch := if launch_ns > 0 { launch_ns } else { time.sys_mono_now() }
	return StartupPhaseTrace{
		launch_ns: actual_launch
		last_ns:   actual_launch
		marks:     []StartupPhaseMark{}
		seen:      map[ui2.StartupPhase]bool{}
	}
}

pub fn (mut trace StartupPhaseTrace) mark_at(phase ui2.StartupPhase, at_ns u64) bool {
	if phase in trace.seen || at_ns < trace.launch_ns {
		return false
	}
	if trace.marks.len > 0 && at_ns <= trace.last_ns {
		return false
	}
	trace.marks << StartupPhaseMark{
		phase:        phase
		monotonic_ns: at_ns
		elapsed_ns:   i64(at_ns - trace.launch_ns)
		order:        trace.marks.len
	}
	trace.seen[phase] = true
	trace.last_ns = at_ns
	return true
}

pub fn (mut trace StartupPhaseTrace) mark_now(phase ui2.StartupPhase) bool {
	return trace.mark_at(phase, time.sys_mono_now())
}

pub fn (trace &StartupPhaseTrace) mark_for(phase ui2.StartupPhase) ?StartupPhaseMark {
	for mark in trace.marks {
		if mark.phase == phase {
			return mark
		}
	}
	return none
}

pub fn (trace &StartupPhaseTrace) elapsed_ns(phase ui2.StartupPhase) i64 {
	if mark := trace.mark_for(phase) {
		return mark.elapsed_ns
	}
	return -1
}

pub fn (trace &StartupPhaseTrace) ordered_phases() []ui2.StartupPhase {
	mut phases := []ui2.StartupPhase{}
	for mark in trace.marks {
		phases << mark.phase
	}
	return phases
}

pub fn (trace &StartupPhaseTrace) ordered_phase_names() []string {
	mut phases := []string{}
	for mark in trace.marks {
		phases << ui2.startup_phase_name(mark.phase)
	}
	return phases
}

pub fn (trace &StartupPhaseTrace) is_monotonic() bool {
	for index, mark in trace.marks {
		if index == 0 {
			if mark.monotonic_ns < trace.launch_ns {
				return false
			}
			continue
		}
		if mark.monotonic_ns <= trace.marks[index - 1].monotonic_ns {
			return false
		}
	}
	return true
}

pub fn (trace &StartupPhaseTrace) has_all_startup_phases() bool {
	for phase in startup_phases {
		if trace.mark_for(phase) == none {
			return false
		}
	}
	return true
}

pub fn startup_phase_names() []string {
	mut names := []string{}
	for phase in startup_phases {
		names << ui2.startup_phase_name(phase)
	}
	return names
}
