module main

pub struct CliConfig {
pub:
	image_path string
	show_help  bool
}

// parse_cli_args parses command-line arguments for image-ui.
// Usage: `image-ui [path]`
pub fn parse_cli_args(args []string) !CliConfig {
	mut actual_args := args.clone()
	if actual_args.len > 0 && (actual_args[0] == 'image-ui' || actual_args[0].ends_with('/image-ui') || actual_args[0].ends_with('\\image-ui')) {
		actual_args = actual_args[1..].clone()
	}

	if actual_args.len == 0 {
		return CliConfig{
			image_path: ''
			show_help:  false
		}
	}

	for arg in actual_args {
		if arg == '-h' || arg == '--help' {
			return CliConfig{
				image_path: ''
				show_help:  true
			}
		}
	}

	return CliConfig{
		image_path: actual_args[0]
		show_help:  false
	}
}
