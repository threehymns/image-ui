module main

fn test_startup_phase_trace_records_required_phases_with_strict_monotonic_values() {
	mut trace := new_startup_phase_trace(100)
	mut at := u64(100)
	for phase in startup_phases {
		assert trace.mark_at(phase, at)
		at += 10
	}
	assert trace.ordered_phases() == startup_phases
	assert trace.ordered_phase_names() == startup_phase_names()
	assert trace.is_monotonic()
	assert trace.has_all_startup_phases()
	assert trace.elapsed_ns(.first_content) == 50
}

fn test_startup_phase_trace_rejects_duplicate_coalesced_and_regressed_marks() {
	mut trace := new_startup_phase_trace(100)
	assert trace.mark_at(.process_launch, 100)
	assert !trace.mark_at(.process_launch, 200)
	assert !trace.mark_at(.window_creation, 100)
	assert !trace.mark_at(.window_creation, 90)
	assert trace.mark_at(.window_creation, 101)
	assert trace.ordered_phases() == [.process_launch, .window_creation]
	assert trace.is_monotonic()
}

fn test_startup_phase_trace_preserves_directory_completion_before_input() {
	mut trace := new_startup_phase_trace(100)
	assert trace.mark_at(.process_launch, 100)
	assert trace.mark_at(.ui2_setup, 110)
	assert trace.mark_at(.window_creation, 120)
	assert trace.mark_at(.gpu_context_initialization, 130)
	assert trace.mark_at(.directory_completion, 140)
	assert trace.mark_at(.first_content, 150)
	assert trace.mark_at(.first_input, 160)
	assert trace.ordered_phases() == [.process_launch, .ui2_setup, .window_creation,
		.gpu_context_initialization, .directory_completion, .first_content, .first_input]
}
