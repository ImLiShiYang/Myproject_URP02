Shader "Unlit/ReadMyCustomDepth_Shadow_Fixed"
{
    Properties
    {
        _BaseColor("Base Color", Color) = (1, 1, 1, 1)

        [Enum(SampledDepth,0,LightUV,1,ReceiverDepth,2,DepthDifference,3,ShadowCompare,4)]
        _DebugMode("Debug Mode", Float) = 4

        _DepthBias("Depth Bias", Range(0, 0.05)) = 0.002
        _ShadowStrength("Shadow Strength", Range(0, 1)) = 0.6
        
//        _FlipShadowUVX("Flip Shadow UV X", Float) = 0
//        _FlipShadowUVY("Flip Shadow UV Y", Float) = 0
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline"="UniversalPipeline"
            "RenderType"="Opaque"
            "Queue"="Geometry"
        }

        Pass
        {
            Name "UniversalForward"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE2D(_MyCustomDepthTexture);
            SAMPLER(sampler_MyCustomDepthTexture);

            float4x4 _WorldToLightUVMatrix;
            float4x4 _WorldToLightViewMatrix;
            float4 _CustomLightDepthParams;
            float4 _MyCustomDepthTexture_TexelSize;

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                float _DebugMode;
                float _DepthBias;
                float _ShadowStrength;
                // float _FlipShadowUVX;
                // float _FlipShadowUVY;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
            };

            Varyings Vert(Attributes input)
            {
                Varyings output;

                VertexPositionInputs vertexInput =
                    GetVertexPositionInputs(input.positionOS.xyz);

                output.positionCS = vertexInput.positionCS;
                output.positionWS = vertexInput.positionWS;

                return output;
            }

            half4 Frag(Varyings input) : SV_Target
            {
                // 世界坐标 -> 光源 UV
                float4 lightUVH = mul(
                    _WorldToLightUVMatrix,
                    float4(input.positionWS, 1.0)
                );

                float3 lightUVW = lightUVH.xyz / lightUVH.w;
                float2 lightUV = lightUVW.xy;

                // if (_FlipShadowUVX > 0.5)
                // {
                //     lightUV.x = 1.0 - lightUV.x;
                // }
                //
                // if (_FlipShadowUVY > 0.5)
                // {
                //     lightUV.y = 1.0 - lightUV.y;
                // }

                // 当前像素在光源 View Space 中的深度
                float3 lightViewPos = mul(
                    _WorldToLightViewMatrix,
                    float4(input.positionWS, 1.0)
                ).xyz;

                float viewDepth = -lightViewPos.z;

                float nearPlane = _CustomLightDepthParams.x;
                float farPlane  = _CustomLightDepthParams.y;

                // 注意：这里用 viewDepth 判断 near/far，不再用 lightUVW.z
                bool outside =
                    lightUV.x < 0.0 || lightUV.x > 1.0 ||
                    lightUV.y < 0.0 || lightUV.y > 1.0 ||
                    viewDepth < nearPlane ||
                    viewDepth > farPlane;

                // 临时调试：超出光源相机范围直接显示蓝色
                if (outside)
                {
                    return half4(0, 0, 1, 1);
                }

                float sampledDepth = SAMPLE_TEXTURE2D(
                    _MyCustomDepthTexture,
                    sampler_MyCustomDepthTexture,
                    lightUV
                ).r;

                float receiverDepth = saturate(
                    (viewDepth - nearPlane) * _CustomLightDepthParams.z
                );

                // sampledDepth 接近 1 说明这个位置基本是清屏区域，没有 caster
                float hasCaster = sampledDepth < 0.999;

                // 0: 采样到的 shadow map 深度
                if (_DebugMode < 0.5)
                {
                    return half4(sampledDepth.xxx, 1);
                }

                // 1: 光源 UV
                if (_DebugMode < 1.5)
                {
                    return half4(lightUV.x, lightUV.y, 0, 1);
                }

                // 2: 当前像素自身在光源视角下的线性深度
                if (_DebugMode < 2.5)
                {
                    return half4(receiverDepth.xxx, 1);
                }

                float diff = receiverDepth - sampledDepth;

                // 3: 深度差
                if (_DebugMode < 3.5)
                {
                    // 如果没有 caster，直接显示黑色
                    // 这样你就不会被 clear=1 的区域干扰
                    if (!hasCaster)
                    {
                        return half4(1, 0, 0, 1);
                    }

                    // 越亮表示 receiverDepth 比 sampledDepth 更远
                    // 也就是越可能在阴影里
                    float vis = saturate(diff * 50.0);
                    return half4(vis.xxx, 1);
                }

                // 4: Shadow Compare
                if (!hasCaster)
                {
                    return half4(_BaseColor.rgb, _BaseColor.a);
                }

                float inShadow = receiverDepth > sampledDepth + _DepthBias? 1.0: 0.0;

                float shadowFactor = lerp(1.0,1.0 - _ShadowStrength,inShadow);

                half3 finalColor = _BaseColor.rgb * shadowFactor;

                return half4(finalColor, _BaseColor.a);
            }

            ENDHLSL
        }
    }
}