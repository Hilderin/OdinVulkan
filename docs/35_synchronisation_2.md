---
title: 35 - Synchronisation 2
nav_order: 37
---

# 35 - Synchronisation 2

This step is a bit different from the others: nothing changes in the main.odin. The work happened inside `libs/ovk`, where the last two legacy synchronization calls were replaced with their modern `*2` versions.

The codebase was already using `vkCmdPipelineBarrier2` for image layout transitions since step 13, and `synchronization2 = true` was enabled at device creation. But two functions still spoke Vulkan 1.0: `cmd_generate_mipmaps` recorded `vkCmdPipelineBarrier`, and `submit_command_buffer` called `vkQueueSubmit`. This step migrates both to `vkCmdPipelineBarrier2` and `vkQueueSubmit2`.

The full source for this step lives in [src/35_synchronisation_2/main.odin](https://github.com/Hilderin/OdinVulkan/blob/main/src/35_synchronisation_2/main.odin) and the changed library files are [libs/ovk/commands.odin](https://github.com/Hilderin/OdinVulkan/blob/main/libs/ovk/commands.odin) and [libs/ovk/command_buffer.odin](https://github.com/Hilderin/OdinVulkan/blob/main/libs/ovk/command_buffer.odin).

References:
- [Synchronization introduction](https://docs.vulkan.org/tutorial/latest/Synchronization/introduction.html) - the official tutorial's synchronization chapter, with the concepts in more depth.
- [Vulkan SDK offers developers a smooth transition path to synchronization 2](https://www.khronos.org/blog/vulkan-sdk-offers-developers-a-smooth-transition-path-to-synchronization2) - Khronos blog post explaining why the new API exists.

---

## Objectives

- Explain what synchronization 2 is and why it exists.
- Replace `vkCmdPipelineBarrier` with `vkCmdPipelineBarrier2` in `cmd_generate_mipmaps`.
- Replace `vkQueueSubmit` with `vkQueueSubmit2` in `submit_command_buffer`.

---

## Concepts

### The two problems with the original synchronization API

The barrier and submit functions from Vulkan 1.0 do the job, but two design decisions make them clumsy.

**Stages are a property of the whole barrier call.** `vkCmdPipelineBarrier` takes a single `srcStageMask` and `dstStageMask` shared by every barrier listed in the call. The access masks are per-barrier, but the stages are not. When you want two barriers in one call to run at different stages, you widen the masks to cover both cases. That synchronizes more than needed, and the more barriers you lump together, the more you over-sync.

**The submit has no signal stage.** `vkQueueSubmit` lets you say which stage waits on each semaphore, but a signaled semaphore has no stage of its own. That is fine for binary semaphores used as "the frame is done" flags, but it is vague when you want finer ordering, and it is part of why timeline semaphores were awkward to bolt on.

### What synchronization 2 changes

`VK_KHR_synchronization2`, core since Vulkan 1.3, reworks both calls (see the [References](#references) above for background). The short version:

- `vkCmdPipelineBarrier2` takes a `VkDependencyInfo`, and every `VkImageMemoryBarrier2` / `VkBufferMemoryBarrier2` / `VkMemoryBarrier2` inside it carries its own stage and access masks. The dependency is complete in one struct: "these stages, with these accesses, must wait for those stages, with those accesses." No common denominator.

- `vkQueueSubmit2` takes a `VkSubmitInfo2` in which each semaphore - wait or signal - is a `VkSemaphoreSubmitInfo` with its own `stageMask`. Signal semaphores get a stage too. The same struct has a `value` field, which is what makes timeline semaphores work natively.

### Why it's worth the migration

- **Precision.** You describe exactly what must happen, so the driver can overlap more work. Over-synchronization is the classic Vulkan performance trap, and the old API pushed you toward it.
- **Readability.** The sync for a dependency lives on the barrier itself. You don't have to mentally pair a global stage mask with the right barrier in a list.
- **It's the base for what's next.** Timeline semaphores, the natural evolution of the fence + binary semaphore combos used so far, build directly on the submit2 structures.

One rule of thumb: the old and new functions can coexist in a command buffer, but there's no reason to mix them once the device exposes synchronization 2.

---

## Implementation

### `libs/ovk/commands.odin` - `cmd_generate_mipmaps`

Before, the loop recorded the old form. Stage masks went on the command, access masks on the barrier:

```c
vk.CmdPipelineBarrier(command_buffer, {.TRANSFER}, {.TRANSFER}, {}, 0, nil, 0, nil, 1, &barrier)
```

After, the barrier carries everything, and one `DependencyInfo` is reused for all the transitions:

{% raw %}
```c
barrier := vk.ImageMemoryBarrier2 {
    sType               = .IMAGE_MEMORY_BARRIER_2,
    image               = image.vk_image,
    srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
    dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
    subresourceRange    = {{.COLOR}, 0, 1, 0, 1},
}

dependency_info := vk.DependencyInfo {
    sType                   = .DEPENDENCY_INFO,
    imageMemoryBarrierCount = 1,
    pImageMemoryBarriers    = &barrier,
}

for i in 1 ..< mip_levels {
    barrier.subresourceRange.baseMipLevel = i - 1
    barrier.oldLayout = .TRANSFER_DST_OPTIMAL
    barrier.newLayout = .TRANSFER_SRC_OPTIMAL
    barrier.srcStageMask = {.TRANSFER}
    barrier.dstStageMask = {.TRANSFER}
    barrier.srcAccessMask = {.TRANSFER_WRITE}
    barrier.dstAccessMask = {.TRANSFER_READ}

    vk.CmdPipelineBarrier2(command_buffer.vk_command_buffer, &dependency_info)
    // ... blit from mip i-1 to mip i ...
    vk.CmdBlitImage(command_buffer.vk_command_buffer, image.vk_image, .TRANSFER_SRC_OPTIMAL, image.vk_image, .TRANSFER_DST_OPTIMAL, 1, &blit, .LINEAR)

    barrier.oldLayout = .TRANSFER_SRC_OPTIMAL
    barrier.newLayout = .SHADER_READ_ONLY_OPTIMAL
    barrier.srcStageMask = {.TRANSFER}
    barrier.dstStageMask = {.FRAGMENT_SHADER}
    barrier.srcAccessMask = {.TRANSFER_READ}
    barrier.dstAccessMask = {.SHADER_READ}

    vk.CmdPipelineBarrier2(command_buffer.vk_command_buffer, &dependency_info)
}
```
{% endraw %}

The stage masks that used to sit on the `CmdPipelineBarrier` call moved into the barrier itself. The `dependency_info` is built once and reused, since only the barrier's fields change between calls.

The migration also fixed a small wart: the old code set `srcQueueFamilyIndex` and `dstQueueFamilyIndex` to `0` with a comment claiming `VK_QUEUE_FAMILY_IGNORED`. Zero is the real queue family zero, not "ignored". Now it's the actual constant.

### `libs/ovk/command_buffer.odin` - `submit_command_buffer`

Before, semaphores were flat arrays and the wait stage was a separate pointer:

```c
submit_info := vk.SubmitInfo {
    // ...
    pWaitSemaphores   = raw_data(vk_wait_semaphores),
    pWaitDstStageMask = raw_data(args.wait_dest_stages),
    pCommandBuffers   = &args.command_buffer.vk_command_buffer,
    pSignalSemaphores = raw_data(vk_signal_semaphores),
}
vk.QueueSubmit(args.queue.vk_queue, 1, &submit_info, fence)
```

After, each semaphore gets its own `SemaphoreSubmitInfo`, and the command buffer gets a `CommandBufferSubmitInfo`:

```c
for wait_semaphore, i in args.wait_semaphores {
    wait_semaphore_infos[i] = vk.SemaphoreSubmitInfo {
        sType     = .SEMAPHORE_SUBMIT_INFO,
        semaphore = wait_semaphore.vk_semaphore,
        stageMask = args.wait_dest_stages[i],
    }
}
for signal_semaphore, i in args.signal_semaphores {
    signal_semaphore_infos[i] = vk.SemaphoreSubmitInfo {
        sType     = .SEMAPHORE_SUBMIT_INFO,
        semaphore = signal_semaphore.vk_semaphore,
        stageMask = {.ALL_COMMANDS},
    }
}

command_buffer_info := vk.CommandBufferSubmitInfo {
    sType         = .COMMAND_BUFFER_SUBMIT_INFO,
    commandBuffer = args.command_buffer.vk_command_buffer,
}

submit_info := vk.SubmitInfo2 {
    sType                    = .SUBMIT_INFO_2,
    waitSemaphoreInfoCount   = u32(len(wait_semaphore_infos)),
    pWaitSemaphoreInfos      = raw_data(wait_semaphore_infos),
    commandBufferInfoCount   = 1,
    pCommandBufferInfos      = &command_buffer_info,
    signalSemaphoreInfoCount = u32(len(signal_semaphore_infos)),
    pSignalSemaphoreInfos    = raw_data(signal_semaphore_infos),
}
vk.QueueSubmit2(args.queue.vk_queue, 1, &submit_info, fence)
```

Signal semaphores now carry a stage too. `{.ALL_COMMANDS}` is the conservative choice: "signal once everything above has finished", which is exactly what the old call meant implicitly.

The only signature change is `wait_dest_stages`, which went from `[]vk.PipelineStageFlags` to `[]vk.PipelineStageFlags2`. The callers didn't have to change: `swap_chain_helper_submit_and_queue_present` passes {% raw %}`{{.COLOR_ATTACHMENT_OUTPUT}}`{% endraw %}, and that bit has the same value in both enums, so the literal still compiles as-is.

---

## Results

The app runs exactly as before: same viking room, same rotation. This step exercises the new code on two paths without touching it directly:

- Every frame, `swap_chain_helper_submit_and_queue_present` goes through the rewritten `submit_command_buffer`, so `vkQueueSubmit2` is on the hot path from the first frame.
- At startup, `create_image_from_file` calls the rewritten `cmd_generate_mipmaps`, so `vkCmdPipelineBarrier2` handles every layout transition and per-level barrier in the mip chain.

Validation layers report nothing new. The `synchronization2` feature has been required and enabled since step 13, so nothing had to change in device creation for these calls to work.

That's it. Synchronization was the last piece of the codebase still speaking Vulkan 1.0, and the whole library is now consistently on the modern API.
