module main

fn test_startup_phase_trace_records_required_order_with_monotonic_values() {
	mut trace := new_startup_phase_trace(100)
	mut at := u64(100)
	for phase in startup_phase_names {
		assert trace.mark_at(phase, at)
		at += 10
	}
	assert trace.ordered_phases() == startup_phase_names
	assert trace.is_monotonic()
	assert trace.has_all_startup_phases()
	assert trace.elapsed_ns('first_content') == 50
}

fn test_startup_phase_trace_clamps_regressions_and_ignores_duplicates() {
	mut trace := new_startup_phase_trace(100)
	assert trace.mark_at('process_launch', 100)
	assert !trace.mark_at('process_launch', 200)
	assert trace.mark_at('window_creation', 90)
	assert trace.elapsed_ns('window_creation') == 0
	assert trace.is_monotonic()
	assert trace.ordered_phases() == ['process_launch', 'window_creation']
}
