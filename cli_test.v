module main

fn test_cli_empty_args() {
	config := parse_cli_args([]) or { panic(err) }
	assert config.image_path == ''
	assert config.show_help == false
}

fn test_cli_with_program_name_only() {
	config := parse_cli_args(['image-ui']) or { panic(err) }
	assert config.image_path == ''
	assert config.show_help == false
}

fn test_cli_with_program_path_only() {
	config := parse_cli_args(['/usr/local/bin/image-ui']) or { panic(err) }
	assert config.image_path == ''
	assert config.show_help == false
}

fn test_cli_with_image_path() {
	config := parse_cli_args(['photo.png']) or { panic(err) }
	assert config.image_path == 'photo.png'
	assert config.show_help == false
}

fn test_cli_with_directory_path() {
	config := parse_cli_args(['/home/user/Pictures']) or { panic(err) }
	assert config.image_path == '/home/user/Pictures'
	assert config.show_help == false
}

fn test_cli_with_program_and_image_path() {
	config := parse_cli_args(['image-ui', '/home/user/Pictures/sample.jpg']) or { panic(err) }
	assert config.image_path == '/home/user/Pictures/sample.jpg'
	assert config.show_help == false
}

fn test_cli_help_flag() {
	config1 := parse_cli_args(['--help']) or { panic(err) }
	assert config1.show_help == true

	config2 := parse_cli_args(['-h']) or { panic(err) }
	assert config2.show_help == true

	config3 := parse_cli_args(['image-ui', '--help']) or { panic(err) }
	assert config3.show_help == true
}
