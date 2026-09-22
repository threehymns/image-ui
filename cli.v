module main

import cli

// app_version mirrors the version in v.mod.
// It is wired into the root cli.Command so `--version` and the
// `version` subcommand stay in sync with the packaged version.
pub const app_version = '0.1.0'

// CliConfig carries the resolved viewer launch configuration.
// Flag handling (`--help`, `--man`, `--version`) is owned by the
// `cli` module; only the optional positional image path remains here.
pub struct CliConfig {
pub:
	image_path string
}

// build_cli_command creates the root `image-ui` command per
// https://modules.vlang.io/cli.html.
// The optional image to display on launch is a positional argument:
// `image-ui [path_to_image]`. Help, man page, and version output are
// generated automatically by the `cli` module.
pub fn build_cli_command() cli.Command {
	return cli.Command{
		name:        'image-ui'
		description: 'fast, lightweight desktop image viewer'
		version:     app_version
		usage:       '[path_to_image]'
		posix_mode:  true
		examples:    [
			'\$ image-ui photo.png',
		]
		execute:     run_viewer
	}
}

// resolve_image_path returns the positional image path from parsed
// command args. Empty when the viewer should start without an image.
pub fn resolve_image_path(args []string) string {
	if args.len == 0 {
		return ''
	}
	return args[0]
}

// cli_config_from_args builds a CliConfig from parsed command args.
pub fn cli_config_from_args(args []string) CliConfig {
	return CliConfig{
		image_path: resolve_image_path(args)
	}
}

// run_viewer is the root command callback. It resolves the positional
// image path and boots the desktop viewer.
fn run_viewer(cmd cli.Command) ! {
	launch_viewer(resolve_image_path(cmd.args))
}
