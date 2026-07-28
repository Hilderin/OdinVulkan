package ovk

import "core:strings"

import vk "vendor:vulkan"


Graphics_Pipeline :: struct {
	device:             ^Device,
	vk_pipeline:        vk.Pipeline,
	vk_pipeline_layout: vk.PipelineLayout,
}

Create_Graphics_Pipeline_Args :: struct {
	device:                   ^Device,
	shader:                   ^Shader,
	vertex_entry_point:       string,
	fragment_entry_point:     string,
	swap_chain_format:        vk.Format,
	descriptor_set_layout:    ^Descriptor_Set_Layout,
	vertex_attributes_stride: u32,
	vertex_attributes:        []vk.VertexInputAttributeDescription,
	depth_format:             vk.Format,
	samples:                  vk.SampleCountFlags,
}

// Create a graphics pipeline
create_graphics_pipeline :: proc(args: Create_Graphics_Pipeline_Args) -> (pipeline: Graphics_Pipeline, err: Error) {

	// -----------------------------------
	// Shaders
	// Shader entrypoints
	vertex_entry_cstr := strings.clone_to_cstring(args.vertex_entry_point)
	defer delete(vertex_entry_cstr)
	fragment_entry_cstr := strings.clone_to_cstring(args.fragment_entry_point)
	defer delete(fragment_entry_cstr)

	// Shaders create info. One per entrypoint.
	shaders_create_info := []vk.PipelineShaderStageCreateInfo {
		{sType = .PIPELINE_SHADER_STAGE_CREATE_INFO, stage = {.VERTEX}, module = args.shader.vk_shader_module, pName = vertex_entry_cstr},
		{sType = .PIPELINE_SHADER_STAGE_CREATE_INFO, stage = {.FRAGMENT}, module = args.shader.vk_shader_module, pName = fragment_entry_cstr},
	}

	// -----------------------------------
	// Dynamic state - Defines what can be dynamic in the pipeline
	dynamic_states := []vk.DynamicState{.VIEWPORT, .SCISSOR}
	dynamic_state_create_info := vk.PipelineDynamicStateCreateInfo {
		sType             = .PIPELINE_DYNAMIC_STATE_CREATE_INFO,
		dynamicStateCount = u32(len(dynamic_states)),
		pDynamicStates    = raw_data(dynamic_states),
	}

	// -----------------------------------
	// Vertex input
	// Configure the format of the buffer where the vertices are stored.
	binding_description := vk.VertexInputBindingDescription{}
	binding_description.binding = 0
	binding_description.stride = args.vertex_attributes_stride
	binding_description.inputRate = .VERTEX

	vertex_input_create_info := vk.PipelineVertexInputStateCreateInfo {
		sType                           = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
		vertexBindingDescriptionCount   = 1,
		pVertexBindingDescriptions      = &binding_description,
		vertexAttributeDescriptionCount = u32(len(args.vertex_attributes)),
		pVertexAttributeDescriptions    = raw_data(args.vertex_attributes),
	}

	// -----------------------------------
	// Input assembly
	// Configure topology and if primitive restart should be enabled.
	input_assembly_create_info := vk.PipelineInputAssemblyStateCreateInfo {
		sType                  = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
		topology               = .TRIANGLE_LIST,
		primitiveRestartEnable = false,
	}

	// No need to specify the pViewports and pScissors because they are dynamic due to the dynamic_states above.
	viewport_state_create_info := vk.PipelineViewportStateCreateInfo {
		sType         = .PIPELINE_VIEWPORT_STATE_CREATE_INFO,
		viewportCount = 1,
		scissorCount  = 1,
	}


	// -----------------------------------
	// Rasterizer
	rasterizer_create_info := vk.PipelineRasterizationStateCreateInfo {
		sType                   = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
		depthClampEnable        = false,
		rasterizerDiscardEnable = false,
		polygonMode             = .FILL,
		cullMode                = {.BACK},
		frontFace               = .COUNTER_CLOCKWISE,
		depthBiasEnable         = false,
		lineWidth               = 1,
	}

	// -----------------------------------
	// Multisampling
	// Disabled for now. We will enable it in a later chapter.
	multisampling_create_info := vk.PipelineMultisampleStateCreateInfo {
		sType                 = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
		sampleShadingEnable   = false,
		rasterizationSamples  = args.samples,
		minSampleShading      = 1,
		pSampleMask           = nil,
		alphaToCoverageEnable = false,
		alphaToOneEnable      = false,
	}

	// -----------------------------------
	// Depth and stencil testing
	depth_stencil := vk.PipelineDepthStencilStateCreateInfo {
		depthTestEnable       = true,
		depthWriteEnable      = true,
		depthCompareOp        = .LESS,
		depthBoundsTestEnable = false,
		stencilTestEnable     = false,
	}

	// -----------------------------------
	// Color blending
	// This per-framebuffer struct allows you to configure the first way of color blending. The operations that will be performed are best demonstrated using the following pseudocode:
	//      if (blendEnable) {
	//          finalColor.rgb = (srcColorBlendFactor * newColor.rgb) <colorBlendOp> (dstColorBlendFactor * oldColor.rgb)
	//          finalColor.a = (srcAlphaBlendFactor * newColor.a) <alphaBlendOp> (dstAlphaBlendFactor * oldColor.a)
	//      } else {
	//          finalColor = newColor
	//      }
	//      finalColor = finalColor & colorWriteMask

	// Activating alpha blending where we want the new color to be blended with the old color based on its opacity
	// The finalColor should then be computed as follows:
	//      finalColor.rgb = newAlpha * newColor + (1 - newAlpha) * oldColor;
	//      finalColor.a = newAlpha.a;

	color_blend_attachment := vk.PipelineColorBlendAttachmentState {
		blendEnable         = true,
		srcColorBlendFactor = .SRC_ALPHA,
		dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA,
		colorBlendOp        = .ADD,
		srcAlphaBlendFactor = .ONE,
		dstAlphaBlendFactor = .ZERO,
		alphaBlendOp        = .ADD,
		colorWriteMask      = {.R, .G, .B, .A},
	}

	color_blend_create_info := vk.PipelineColorBlendStateCreateInfo {
		sType           = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
		logicOpEnable   = false,
		logicOp         = .COPY,
		attachmentCount = 1,
		pAttachments    = &color_blend_attachment,
	}

	// -----------------------------------
	// Pipeline layout
	pipeline_layout_create_info := vk.PipelineLayoutCreateInfo {
		sType                  = .PIPELINE_LAYOUT_CREATE_INFO,
		setLayoutCount         = 1,
		pSetLayouts            = &args.descriptor_set_layout.vk_descriptor_set_layout,
		pushConstantRangeCount = 0,
		pPushConstantRanges    = nil,
	}

	check(vk.CreatePipelineLayout(args.device.vk_device, &pipeline_layout_create_info, nil, &pipeline.vk_pipeline_layout), "Failed to create pipeline layout!") or_return

	// -----------------------------------
	// Pipeline Rendering Create Info
	// To use dynamic rendering, we need to specify the formats of the attachments that will be used during rendering.
	format := args.swap_chain_format
	pipeline_rendering_create_info := vk.PipelineRenderingCreateInfo {
		sType                   = .PIPELINE_RENDERING_CREATE_INFO,
		colorAttachmentCount    = 1,
		pColorAttachmentFormats = &format,
		depthAttachmentFormat   = args.depth_format,
	}

	// -----------------------------------
	// Graphics Pipeline
	// Finally!! We create the pipeline that will be used to render!
	pipeline_create_info := vk.GraphicsPipelineCreateInfo {
		sType               = .GRAPHICS_PIPELINE_CREATE_INFO,
		stageCount          = 2,
		pStages             = raw_data(shaders_create_info),
		pVertexInputState   = &vertex_input_create_info,
		pInputAssemblyState = &input_assembly_create_info,
		pViewportState      = &viewport_state_create_info,
		pRasterizationState = &rasterizer_create_info,
		pMultisampleState   = &multisampling_create_info,
		pColorBlendState    = &color_blend_create_info,
		pDynamicState       = &dynamic_state_create_info,
		layout              = pipeline.vk_pipeline_layout,
		renderPass          = 0, // must be null for dynamic rendering
		pDepthStencilState  = &depth_stencil,
		pNext               = &pipeline_rendering_create_info,
	}

	check(vk.CreateGraphicsPipelines(args.device.vk_device, 0, 1, &pipeline_create_info, nil, &pipeline.vk_pipeline), "Failed to create graphics pipeline!") or_return

	// Complete the struct
	pipeline.device = args.device

	return

}

// Destroy a graphics pipeline
destroy_graphics_pipeline :: proc(pipeline: ^Graphics_Pipeline) {
	if pipeline == nil || pipeline.device == nil {
		return
	}

	if pipeline.vk_pipeline_layout != 0 {
		vk.DestroyPipelineLayout(pipeline.device.vk_device, pipeline.vk_pipeline_layout, nil)
	}
	if pipeline.vk_pipeline != 0 {
		vk.DestroyPipeline(pipeline.device.vk_device, pipeline.vk_pipeline, nil)
	}

}
