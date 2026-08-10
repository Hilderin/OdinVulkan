struct VSInput {
    float3 inPosition;
    float3 inColor;
    float2 inTexCoord;
    float3 inNormal;
};

struct UniformBuffer {
    float4x4 model;
    float4x4 view;
    float4x4 proj;
    float4 lightDirection;
    float4 lightColor;
    float4 ambientColor;
    float4 lightSettings;
    float4 cameraPosition;
};
ConstantBuffer<UniformBuffer> ubo;
Sampler2D texture;

struct VSOutput
{
    float4 pos : SV_Position;
    float3 worldPosition;
    float3 normal;
    float3 color;
    float2 fragTexCoord;
};

[shader("vertex")]
VSOutput vertMain(VSInput input) {
    VSOutput output;
    float4 worldPosition = mul(ubo.model, float4(input.inPosition, 1.0));
    output.pos = mul(ubo.proj, mul(ubo.view, worldPosition));
    output.worldPosition = worldPosition.xyz;
    output.normal = normalize(mul((float3x3)ubo.model, input.inNormal));
    output.color = input.inColor;
    output.fragTexCoord = input.inTexCoord;
    return output;
}

[shader("fragment")]
float4 fragMain(VSOutput vertIn) : SV_TARGET {
    float3 normal = normalize(vertIn.normal);
    float3 toLight = normalize(-ubo.lightDirection.xyz);
    float diffuse = max(dot(normal, toLight), 0.0);

    float3 toCamera = normalize(ubo.cameraPosition.xyz - vertIn.worldPosition);
    float3 reflected = reflect(-toLight, normal);
    float specular = pow(max(dot(toCamera, reflected), 0.0), ubo.lightSettings.z) * ubo.lightSettings.y;

    float3 albedo = texture.Sample(vertIn.fragTexCoord).rgb * vertIn.color;
    float3 ambient = albedo * ubo.lightSettings.x * ubo.ambientColor.rgb;
    float3 lighting = ambient + albedo * diffuse * ubo.lightColor.rgb + specular * ubo.lightColor.rgb;
    return float4(lighting, 1.0);
}
