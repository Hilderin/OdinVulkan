package ovk

import "core:encoding/uuid"
import "core:fmt"
import "core:os"

// Compile a slang shader
compile_slang_shader :: proc(slang_path: string, entry_points: []string) -> (spv: []u8, err: Error) {
	vulkan_sdk, found := os.lookup_env("VULKAN_SDK", context.allocator)
	defer delete(vulkan_sdk)
	if !found || vulkan_sdk == "" {
		err = General_Error{"VULKAN_SDK environment variable is not set; cannot locate slangc."}
		return
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

	state, stdout, stderr, err_exec := os.process_exec(desc, context.allocator)
	defer delete(stdout)
	defer delete(stderr)
	if err_exec != nil {
		err = General_Error{fmt.tprintf("Failed to run slangc: %s", os.error_string(err_exec))}
		return
	}
	if state.exit_code != 0 {
		err = General_Error{fmt.tprintf("slangc failed (exit code %d) for '%s': %s %s", state.exit_code, slang_path, string(stderr), string(stdout))}
		return
	}

	read_err: os.Error
	spv, read_err = os.read_entire_file_from_path(spv_path, context.allocator)
	if read_err != nil {
		err = General_Error{fmt.tprintf("Failed to read compiled SPIR-V '%s': %s", spv_path, os.error_string(read_err))}
		return
	}

	return
}
