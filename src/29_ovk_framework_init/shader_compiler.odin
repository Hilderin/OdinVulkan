package main

import "core:encoding/uuid"
import "core:fmt"
import "core:os"

compile_slang_shader :: proc(slang_path: string, entry_points: []string) -> ([]u8, bool) {
	vulkan_sdk, found := os.lookup_env("VULKAN_SDK", context.allocator)
	defer delete(vulkan_sdk)
	if !found || vulkan_sdk == "" {
		fmt.eprintln("VULKAN_SDK environment variable is not set; cannot locate slangc.")
		return nil, false
	}

	slangc_executable: string
	when ODIN_OS == .Windows {
		slangc_executable = "slangc.exe"
	} else {
		slangc_executable = "slangc"
	}
	slangc_path := fmt.tprintf("%s/bin/%s", vulkan_sdk, slangc_executable)

	// UUID v4 → unique temp filename per call.
	id := uuid.generate_v4()
	id_str := uuid.to_string(id, context.temp_allocator)
	temp_dir, _ := os.temp_dir(context.temp_allocator)
	spv_path := fmt.tprintf("%s/odin_shader_%s.spv", temp_dir, id_str)
	defer os.remove(spv_path)

	commands: [dynamic]string
	defer delete(commands)

	// Path of the slangc executable and the slang source file.
	append(&commands, slangc_path, slang_path)

	// Slangc arguments
	append(&commands, "-target", "spirv", "-profile", "spirv_1_4", "-emit-spirv-directly", "-fvk-use-entrypoint-name")

	for entry_point in entry_points {
		append(&commands, "-entry", entry_point)
	}

	// Output file...
	append(&commands, "-o", spv_path)

	desc := os.Process_Desc {
		command = commands[:],
	}

	state, stdout, stderr, err := os.process_exec(desc, context.allocator)
	defer delete(stdout)
	defer delete(stderr)
	if err != nil {
		fmt.eprintfln("Failed to run slangc: %s", os.error_string(err))
		return nil, false
	}
	if state.exit_code != 0 {
		fmt.eprintfln("slangc failed (exit code %d) for '%s':", state.exit_code, slang_path)
		if len(stderr) > 0 {
			fmt.eprintln(string(stderr))
		}
		if len(stdout) > 0 {
			fmt.eprintln(string(stdout))
		}
		return nil, false
	}

	spv, read_err := os.read_entire_file_from_path(spv_path, context.allocator)
	if read_err != nil {
		fmt.eprintfln("Failed to read compiled SPIR-V '%s': %s", spv_path, os.error_string(read_err))
		return nil, false
	}
	return spv, true
}
