---
title: 36 - Timeline Semaphores
nav_order: 38
---

# 36 - Timeline Semaphores

Since step 15, the frame in flight synchronization has been a pair of binary semaphores plus a fence. It works, but it takes three objects to do a simple job: the acquire semaphore says "an image is ready to render", the submit semaphore says "the frame is ready to present", and the fence says "the GPU is done with this frame slot" so the host can safely reuse it.

A **timeline semaphore** replaces the fence with a semaphore that carries a 64-bit counter instead of a boolean. You signal it to a value, and you can wait for that value from the host or from another queue. No reset, no pairing. This step adds timeline semaphores to `ovk`, then swaps the frame-in-flight fences in `Swap_Chain_Helper` for a single timeline semaphore behind a `use_timeline` flag. The rest of the app doesn't change.

The full source for this step lives in [src/36_timeline_semaphores/main.odin](https://github.com/Hilderin/OdinVulkan/blob/main/src/36_timeline_semaphores/main.odin) and the changed library files are [libs/ovk/semaphore.odin](https://github.com/Hilderin/OdinVulkan/blob/main/libs/ovk/semaphore.odin), [libs/ovk/command_buffer.odin](https://github.com/Hilderin/OdinVulkan/blob/main/libs/ovk/command_buffer.odin), [libs/ovk/swap_chain.odin](https://github.com/Hilderin/OdinVulkan/blob/main/libs/ovk/swap_chain.odin), [libs/ovk/swap_chain_helper.odin](https://github.com/Hilderin/OdinVulkan/blob/main/libs/ovk/swap_chain_helper.odin), [libs/ovk/logical_device.odin](https://github.com/Hilderin/OdinVulkan/blob/main/libs/ovk/logical_device.odin) and [libs/ovk/physical_device.odin](https://github.com/Hilderin/OdinVulkan/blob/main/libs/ovk/physical_device.odin).

References:
- [Timeline semaphores introduction](https://docs.vulkan.org/tutorial/latest/Synchronization/Timeline_Semaphores/01_introduction.html) - the official tutorial's timeline semaphore chapter, with the concepts in more depth.
- [Synchronization guide](https://docs.vulkan.org/guide/latest/synchronization.html) - the Vulkan guide chapter comparing fences, semaphores and events.
- [Swapchain semaphore reuse](https://docs.vulkan.org/guide/latest/swapchain_semaphore_reuse.html) - why the present wait semaphores are indexed per swap chain image, the pattern `ovk` already follows.

---

## Objectives

- Let `create_semaphore` build timeline semaphores, not just binary ones.
- Enable the `timelineSemaphore` feature at device creation.
- Let `submit_command_buffer` signal and wait on specific values.
- Replace the per-frame fences in `Swap_Chain_Helper` with a single timeline semaphore and a monotonic counter, behind a `use_timeline` flag.

---

## Concepts

### Why binary semaphores and fences are annoying

A binary semaphore is a boolean. A signal sets it, a wait unsets it, and the spec forces them into strict 1:1 pairs: between two waits, the semaphore must be signaled again. A fence is the host-side sibling - the host can wait on it, but a queue can't use it to order work, and you have to reset it before re-submitting.

So a frame needs both: the queue-to-queue ordering uses binary semaphores, and the host-to-GPU "is the frame slot free" check uses a fence. Three objects, two kinds of reset, and the classic race of resetting a fence before the driver is done with it.

### A timeline semaphore is a counter

A timeline semaphore replaces the boolean with a monotonically increasing 64-bit value. A signal operation sets the counter to a value (it only grows), and a wait operation blocks until the counter reaches at least the requested value. Two consequences fall out of that:

- **A wait doesn't consume anything.** The counter stays where it is. You can wait on a value that was already passed, and the call returns immediately. There is no reset, no pairing, no re-signal dance.
- **The host can wait on it.** `vkWaitSemaphores` works on timeline semaphores, which is exactly what makes them able to replace a fence. The same object handles queue-to-queue ordering and host-to-GPU synchronization.

A timeline semaphore also survives multiple waiters: several queues (or threads) can wait on the same value at the same time, something that is undefined behavior for a binary semaphore.

### The swapchain only accepts binary semaphores

There is one hard restriction worth knowing before getting excited: the semaphores used to acquire and present images must be binary. The spec states it directly - the acquire semaphore must have a type of `VK_SEMAPHORE_TYPE_BINARY` (`VUID-vkAcquireNextImageKHR-semaphore-03265`), and so must every semaphore in `VkPresentInfoKHR::pWaitSemaphores` (`VUID-vkQueuePresentKHR-pWaitSemaphores-03267`).

That means the timeline semaphore can't replace the acquire or the present semaphore. It replaces the **fence** - the part of the equation the host cares about. The binary semaphores stay exactly where they are.

### The counter scheme

The frame loop uses one timeline semaphore and one counter, shared by all frames in flight. Each submit signals the semaphore to `frame_counter` and then bumps it. Before reusing a frame slot, the host waits on the value that the previous use of that slot was signaled with.

With two frames in flight:

- Frame 1 (slot 0): wait for 0 - the counter starts at 0, so this returns immediately. Submit signals 1.
- Frame 2 (slot 1): wait for 0. Submit signals 2.
- Frame 3 (slot 0): wait for `2 - 2 + 1 = 1`. Frame 1 signaled 1, so the GPU is done with slot 0 and we can reuse it.
- Frame 4 (slot 1): wait for `3 - 2 + 1 = 2`.

The `+ 1` matters: slot 0 is used by frames 1, 3, 5 and so on. The previous use of the slot is always `nb_frames_in_flight` submits behind, and the submit that signalled that slot did so to its own counter value. Waiting on `counter - nb_frames + 1` lands exactly on that value.

---

## Implementation

### `libs/ovk/semaphore.odin`

The `Create_Semaphores_Args` struct gains a `semaphore_type` field. The default is `.BINARY`, which is also the zero value, so every existing call site - `{device = ...}` - still creates a binary semaphore without changing a single line.

Inside `create_semaphore` (`libs/ovk/semaphore.odin:17`), a `SemaphoreTypeCreateInfo` is chained to the creation info. It carries the type and the initial counter value, which we set to 0:

```c
semaphore_type_create_info := vk.SemaphoreTypeCreateInfo {
    sType         = .SEMAPHORE_TYPE_CREATE_INFO,
    semaphoreType = args.semaphore_type,
    initialValue  = 0,
}

semaphore_create_info := vk.SemaphoreCreateInfo {
    sType = .SEMAPHORE_CREATE_INFO,
    flags = {},
    pNext = &semaphore_type_create_info,
}
```

The struct also stores the type back on the `Semaphore` wrapper, so the rest of the library can branch on it if it ever needs to.

The new `wait_for_semaphore` (`libs/ovk/semaphore.odin:75`) is the host-side wait that replaces `wait_for_fence`. It builds a `SemaphoreWaitInfo` with a single value and calls `vkWaitSemaphores` with an infinite timeout:

```c
wait_for_semaphore :: proc(semaphore: ^Semaphore, value: u64) -> (err: Error) {
    local_value := value

    wait_info := vk.SemaphoreWaitInfo {
        sType          = .SEMAPHORE_WAIT_INFO,
        semaphoreCount = 1,
        pSemaphores    = &semaphore.vk_semaphore,
        pValues        = &local_value,
    }

    check(vk.WaitSemaphores(semaphore.device.vk_device, &wait_info, max(u64)), "Failed to wait for semaphore!") or_return

    return
}
```

The last helper, `get_semaphore_counter_value` (`libs/ovk/semaphore.odin:93`), reads the current value of the counter back from the device with `vkGetSemaphoreCounterValue`. Useful for debugging - you can check that the counter is actually growing, or spot a wait that will never be satisfied:

```c
get_semaphore_counter_value :: proc(semaphore: ^Semaphore) -> (value: u64, err: Error) {
    check(vk.GetSemaphoreCounterValue(semaphore.device.vk_device, semaphore.vk_semaphore, &value), "Failed to get the semaphore counter value!") or_return
    return
}
```

### Enabling the feature

Timeline semaphores are core since Vulkan 1.2, so no extension to enable - but the `timelineSemaphore` feature must be turned on at device creation, otherwise creating a timeline semaphore is a spec violation. The project requires Vulkan 1.4 hardware (`libs/ovk/physical_device.odin:145`), so the feature is almost certainly there, but the code checks it like it checks every other feature it relies on.

In `create_logical_device`, a `PhysicalDeviceVulkan12Features` struct is inserted in the `pNext` chain, between the Vulkan 1.1 and 1.3 features:

```c
device_feature_vulkan12 := vk.PhysicalDeviceVulkan12Features {
    sType             = .PHYSICAL_DEVICE_VULKAN_1_2_FEATURES,
    timelineSemaphore = true,
    pNext             = &device_feature_vulkan13,
}
```

On the query side, `get_device_features` (`libs/ovk/physical_device.odin:103`) returns the Vulkan 1.2 features as well, and `score_device` rejects the device if `timelineSemaphore` is false. If you forget this, the validation layers will tell you with `VUID-VkSemaphoreTypeCreateInfo-timelineSemaphore-03252`, and some drivers will just create the semaphore anyway and behave unpredictably later.

### `libs/ovk/command_buffer.odin`

`Submit_Command_Buffer_Args` (`libs/ovk/command_buffer.odin:14`) gains `wait_values` and `signal_values`, two `[]u64` slices parallel to the semaphore arrays. The `SemaphoreSubmitInfo` struct already has a `value` field - it's what makes timeline semaphores work natively in `vkQueueSubmit2` - and the submit loop now fills it:

```c
for signal_semaphore, i in args.signal_semaphores {
    signal_value: u64 = 0
    if i < len(args.signal_values) {
        signal_value = args.signal_values[i]
    }
    signal_semaphore_infos[i] = vk.SemaphoreSubmitInfo {
        sType     = .SEMAPHORE_SUBMIT_INFO,
        semaphore = signal_semaphore.vk_semaphore,
        value     = signal_value,
        stageMask = {.ALL_COMMANDS},
    }
}
```

The default is 0, which is what a binary semaphore must carry. So existing callers pass no values and get binary behavior; a timeline caller passes the value it wants to signal or wait on. The wait loop works the same way.

### `libs/ovk/swap_chain.odin`

The frame in flight wait used to be baked into `acquire_next_image`: wait for the fence, acquire, reset the fence. That worked as long as the only way to guard a frame slot was a fence. To let the timeline path reuse the same proc, `draw_fence` is now optional - `nil` means the caller handles the synchronization itself, the same way `submit_command_buffer` already treats its fence:

```c
acquire_next_image :: proc(swap_chain: ^Swap_Chain, draw_fence: ^Fence, acquire_semaphore: ^Semaphore) -> (swapchain_image_index: u32, needs_recreation: bool, err: Error) {
    if draw_fence != nil {
        wait_for_fence(draw_fence)
    }

    result := vk.AcquireNextImageKHR(swap_chain.device.vk_device, swap_chain.vk_swap_chain,
                                     max(u64), acquire_semaphore.vk_semaphore, 0, &swapchain_image_index)
    if result == .SUBOPTIMAL_KHR || result == .ERROR_OUT_OF_DATE_KHR {
        needs_recreation = true
        return
    } else if result != .SUCCESS {
        err = check(result, "Failed to acquire next image!")
        return
    }

    if draw_fence != nil {
        reset_fence(draw_fence)
    }
    return
}
```

When a fence is passed, behavior is identical to before. When it's `nil`, the proc only calls `vkAcquireNextImageKHR` and reports the recreation case - the timeline semaphore replaces the fence, so there is nothing to wait on or reset here. Step 31 still calls this proc with a fence, so its source is untouched.

### `libs/ovk/swap_chain_helper.odin`

The `Swap_Chain_Helper` struct and its creation args gain a `use_timeline` flag. On create, the helper builds either the per-frame fences or a single timeline semaphore:

```c
if args.use_timeline {
    swap_chain_helper.frame_timeline = create_semaphore({device = swap_chain_helper.device, semaphore_type = .TIMELINE}) or_return
} else {
    swap_chain_helper.draw_fences = create_fences({device = swap_chain_helper.device, flags = {.SIGNALED}}, swap_chain_helper.nb_frames_in_flight) or_return
}
```

The struct also carries `frame_counter`, the monotonic counter for the timeline. Everything else - acquire semaphores, submit semaphores, the color/depth images - is created the same way in both modes.

At acquire time (`libs/ovk/swap_chain_helper.odin:94`), the two modes wait differently. The timeline path waits on the host for the previous use of the slot, then calls `acquire_next_image` with a nil fence. The fence path just passes the frame fence and lets `acquire_next_image` do the wait and reset:

```c
if swap_chain_helper.use_timeline {
    nb_frames := u64(swap_chain_helper.nb_frames_in_flight)
    if swap_chain_helper.frame_counter >= nb_frames {
        wait_value := swap_chain_helper.frame_counter - nb_frames + 1
        wait_for_semaphore(&swap_chain_helper.frame_timeline, wait_value) or_return
    }

    // No fence: the timeline semaphore handles the frame in flight synchronization.
    swap_chain_helper.image_index, recreation_needed = acquire_next_image(
        &swap_chain_helper.swap_chain,
        nil,
        &swap_chain_helper.acquire_semaphores[swap_chain_helper.frame_index],
    ) or_return
} else {
    // Wait for the frame fence and reset it after a successful acquire, inside acquire_next_image.
    swap_chain_helper.image_index, recreation_needed = acquire_next_image(
        &swap_chain_helper.swap_chain,
        &swap_chain_helper.draw_fences[swap_chain_helper.frame_index],
        &swap_chain_helper.acquire_semaphores[swap_chain_helper.frame_index],
    ) or_return
}
```

The guard on the first `nb_frames` frames is the timeline equivalent of the fences being created in the signaled state: a frame slot has no previous use until it has been rendered `nb_frames_in_flight` times, so the wait is simply skipped. No hidden no-op wait on value 0 - if there is nothing to wait for, we don't call `vkWaitSemaphores` at all.

At submit time (`libs/ovk/swap_chain_helper.odin:131`), the timeline path signals two semaphores: the timeline semaphore with the next counter value, and the binary submit semaphore that the present call waits on:

{% raw %}
```c
swap_chain_helper.frame_counter += 1

submit_command_buffer(
    {
        command_buffer = command_buffer,
        queue = &swap_chain_helper.device.graphics_queue,
        wait_semaphores = {&swap_chain_helper.acquire_semaphores[swap_chain_helper.frame_index]},
        wait_dest_stages = {{.COLOR_ATTACHMENT_OUTPUT}},
        signal_semaphores = {&swap_chain_helper.frame_timeline, &swap_chain_helper.submit_semaphores[swap_chain_helper.image_index]},
        signal_values = {swap_chain_helper.frame_counter, 0},
    },
) or_return
```
{% endraw %}

The `0` in `signal_values` is the binary submit semaphore's value. The fence path is untouched, so steps that don't set `use_timeline` keep the exact behavior from before.

### `src/36_timeline_semaphores/main.odin`

The new step is a copy of step 35 with one meaningful change in `init_app` (`src/36_timeline_semaphores/main.odin:91`):

```c
app.swap_chain = ovk.create_swap_chain_helper(
    {swap_chain_args = {device = &app.device, window = &app.window}, samples = app.samples, depth_format = app.depth_format, use_timeline = true},
) or_return
```

That's the whole switch. The helper hides the counter math, so the frame loop reads exactly like step 35.

The one addition to the loop is a debug print. Right after the submit, `run_app` reads the counter back from the GPU and prints it once every 60 frames (`src/36_timeline_semaphores/main.odin:405`). Printing every frame would bury the console in output, so the modulo keeps it to about once a second:

```c
// Debug: print the timeline semaphore counter once in a while to see it grow.
if counter_value, counter_err := ovk.get_semaphore_counter_value(&app.swap_chain.frame_timeline); counter_err == nil {
    if counter_value % 60 == 0 {
        fmt.printfln("Timeline semaphore counter: {}", counter_value)
    }
}
```

This is purely diagnostic. The error is ignored on purpose - a failed counter read shouldn't take down the render loop.

---

## Results

The app runs exactly as before: same viking room, same rotation. The visible behavior is identical because this step only changes how the frame slots are synchronized, not what gets rendered.

The console shows the timeline counter growing over time:

```
Timeline semaphore counter: 60
Timeline semaphore counter: 180
Timeline semaphore counter: 300
```

The values jump because only every 60th frame is printed, and the counter increments once per submitted frame. It's monotonic, which is the whole point of a timeline semaphore: a binary semaphore would flip between two states, a timeline just counts up.

To check the timeline path is really taken, put a breakpoint or a `fmt.println` in `wait_for_semaphore` - it doesn't fire on the first two frames (with `nb_frames_in_flight` of 2, there is nothing to wait for), and from the third frame onwards it fires and blocks until the previous use of the slot is signaled. Or use RenderDoc and look at the timeline: every submitted frame signals the semaphore to the next counter value.

Validation layers should report nothing new. If you see `VUID-VkSemaphoreTypeCreateInfo-timelineSemaphore-03252`, the `timelineSemaphore` feature isn't enabled at device creation - check that the `PhysicalDeviceVulkan12Features` struct is chained in `create_logical_device`.

Backward compatibility is preserved: every step that uses `Swap_Chain_Helper` without `use_timeline` (31 to 35) compiles and runs unchanged. Step 31 calls `acquire_next_image` with a fence, which takes the exact same code path as before - the fence is only skipped when the caller passes nil.
