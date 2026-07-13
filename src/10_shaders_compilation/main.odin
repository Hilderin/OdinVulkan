package main

import "core:fmt"
import "core:os"

main :: proc() {
	fmt.println("Shaders compilation")
	fmt.println("-------------------------------------------")

	fmt.println()
	fmt.println("Compiling...")
	spv, ok := compile_slang_shader("shader.slang", {"fragMain", "vertMain"})
	if !ok {
		fmt.eprintln("Shader compilation failed.")
		os.exit(1)
	}
	delete(spv)
	fmt.printfln("Shaders compiled with success! SPIR-V size: %d bytes", len(spv))

}
