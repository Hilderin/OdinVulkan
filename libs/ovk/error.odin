package ovk

import "base:runtime"
import "core:fmt"
import "core:reflect"

import vk "vendor:vulkan"

General_Error :: struct {
	message: string,
}

Vulkan_Error :: struct {
	result:  vk.Result,
	message: string,
	loc:     runtime.Source_Code_Location,
}

Assert_Error :: struct {
	message: string,
	loc:     runtime.Source_Code_Location,
}


Error :: union {
	General_Error,
	Vulkan_Error,
	Assert_Error,
}


// Check if a result from a Vulkan API call is a success and returns an error struct otherwise.
check :: proc(result: vk.Result, operation: string, loc := #caller_location) -> (err: Error) {
	if result == .SUCCESS {
		return
	}

	err = Vulkan_Error{result, fmt.tprint(operation, reflect.enum_string(result)), loc}
	return
}

// Assert a condition and return an error when the condition is not true.
assert :: proc(condition: bool, message: string, args: ..any, loc := #caller_location) -> (err: Error) {
	if condition {
		return
	}

	err = Assert_Error{fmt.tprintf(message, args), loc}
	return
}
