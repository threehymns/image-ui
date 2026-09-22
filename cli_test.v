module main

import cli

fn noop_viewer(_cmd cli.Command) ! {
}

fn test_resolve_image_path_empty() {
	assert resolve_image_path([]) == ''
}

fn test_resolve_image_path_with_path() {
	assert resolve_image_path(['photo.png']) == 'photo.png'
	assert resolve_image_path(['/home/user/Pictures/sample.jpg']) == '/home/user/Pictures/sample.jpg'
}

fn test_cli_config_from_args() {
	assert cli_config_from_args([]).image_path == ''
	assert cli_config_from_args(['photo.png']).image_path == 'photo.png'
}

fn test_build_cli_command_metadata() {
	cmd := build_cli_command()
	assert cmd.name == 'image-ui'
	assert cmd.description == 'fast, lightweight desktop image viewer'
	assert cmd.version == app_version
	assert cmd.usage == '[path_to_image]'
	assert cmd.posix_mode == true
}

fn test_resolve_image_path_with_directory_path() {
	assert resolve_image_path(['/home/user/Pictures']) == '/home/user/Pictures'
}

fn test_resolve_image_path_with_program_and_image_path() {
	assert resolve_image_path(['image-ui', '/home/user/Pictures/sample.jpg'][1..]) == '/home/user/Pictures/sample.jpg'
}

fn test_cli_parse_no_positional_args() {
	mut cmd := build_cli_command()
	cmd.execute = noop_viewer
	cmd.setup()
	cmd.parse(['image-ui'])
	assert cmd.args == []
	assert resolve_image_path(cmd.args) == ''
	assert cli_config_from_args(cmd.args).image_path == ''
}

fn test_cli_parse_with_image_path() {
	mut cmd := build_cli_command()
	cmd.execute = noop_viewer
	cmd.setup()
	cmd.parse(['image-ui', 'photo.png'])
	assert cmd.args == ['photo.png']
	assert resolve_image_path(cmd.args) == 'photo.png'
}

fn test_cli_parse_with_absolute_image_path() {
	mut cmd := build_cli_command()
	cmd.execute = noop_viewer
	cmd.setup()
	cmd.parse(['image-ui', '/home/user/Pictures/sample.jpg'])
	assert cmd.args == ['/home/user/Pictures/sample.jpg']
	assert resolve_image_path(cmd.args) == '/home/user/Pictures/sample.jpg'
}

fn test_cli_help_message() {
	cmd := build_cli_command()
	help := cmd.help_message()
	assert help.contains('Usage: image-ui')
	assert help.contains('[path_to_image]')
	assert help.contains('fast, lightweight desktop image viewer')
}

fn test_cli_version() {
	cmd := build_cli_command()
	assert cmd.version() == 'image-ui version ${app_version}'
}
