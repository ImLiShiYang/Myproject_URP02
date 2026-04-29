Shader "Unlit/ReadMyCustomDepth_Shadow_Fixed"
{
    Properties
    {
        _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        _AmbientStrength("Ambient Strength", Range(0, 1)) = 0.25
        _DiffuseStrength("Diffuse Strength", Range(0, 1)) = 0.8

        [Enum(SampledDepth,0,LightUV,1,ReceiverDepth,2,DepthDifference,3,ShadowCompare,4)]
        _DebugMode("Debug Mode", Float) = 4

        _DepthBias("Depth Bias", Range(0, 0.05)) = 0.002
        _ShadowStrength("Shadow Strength", Range(0, 1)) = 0.6
        
//        _FlipShadowUVX("Flip Shadow UV X", Float) = 0
//        _FlipShadowUVY("Flip Shadow UV Y", Float) = 0
        
        _PCFRadius("PCF Radius", Range(0, 3)) = 1
        [Toggle] _UsePCF("Use PCF", Float) = 1
        
        _NormalBias("Normal Bias World", Range(0, 0.1)) = 0.005
        _SlopeDepthBias("Slope Depth Bias", Range(0, 0.01)) = 0.001
        
        [Toggle] _UsePCSS("Use PCSS", Float) = 0
        _PCSSLightSize("PCSS Light Size", Range(0, 40)) = 6
        _PCSSBlockerSearchRadius("PCSS Blocker Search Radius", Range(1, 16)) = 4
        _PCSSMaxFilterRadius("PCSS Max Filter Radius", Range(1, 32)) = 12
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
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_MyCustomDepthTexture);
            SAMPLER(sampler_MyCustomDepthTexture);

            float4x4 _WorldToLightUVMatrix;
            float4x4 _WorldToLightViewMatrix;
            float4 _CustomLightDepthParams;
            float4 _MyCustomDepthTexture_TexelSize;
            float3 _CustomLightDirectionWS;

            CBUFFER_START(UnityPerMaterial)
                float _AmbientStrength;
                float _DiffuseStrength;
            
                half4 _BaseColor;
                float _DebugMode;
                float _DepthBias;
                float _ShadowStrength;
            
                float _PCFRadius;
                float _UsePCF;
            
                // Use PCSS：是否开启 PCSS。
                float _UsePCSS;
                // PCSS Light Size：模拟光源尺寸，越大阴影越软。
                float _PCSSLightSize;
                // PCSS Blocker Search Radius：找遮挡物时搜索范围。
                float _PCSSBlockerSearchRadius;
                // PCSS Max Filter Radius：动态 PCF 最大半径，防止阴影糊成一片。
                float _PCSSMaxFilterRadius;
            
                float _NormalBias;
                float _SlopeDepthBias;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3 normalWS   : TEXCOORD1;
            };

            Varyings Vert(Attributes input)
            {
                Varyings output;

                VertexPositionInputs vertexInput =GetVertexPositionInputs(input.positionOS.xyz);
                    
                output.positionCS = vertexInput.positionCS;
                output.positionWS = vertexInput.positionWS;
                
                VertexNormalInputs normalInput =GetVertexNormalInputs(input.normalOS);
                output.normalWS = normalInput.normalWS;

                return output;
            }
            
            // 单点阴影比较。
            // 返回 0 = 不在阴影里。
            // 返回 1 = 在阴影里。
            float SampleShadowTap(float2 uv, float receiverDepth, float bias)
            {
                // 超出 shadow map 范围，认为没有阴影。
                if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0)
                {
                    return 0.0;
                }

                // 从自定义 shadow map 里读取深度。
                float d = SAMPLE_TEXTURE2D(_MyCustomDepthTexture, sampler_MyCustomDepthTexture, uv).r;

                // d 接近 1 表示这个 texel 是清屏值，没有 caster。
                // 没有 caster 就不产生阴影。
                if (d >= 0.999)
                {
                    return 0.0;
                }

                // receiverDepth 更远，说明光源先看到了 blocker，当前点在阴影里。
                return receiverDepth > d + bias ? 1.0 : 0.0;
            }
            
            // 带指定半径的 5x5 PCF。
            // radius 的单位是 shadow map texel 数量。
            // radius 越大，阴影边缘越软。
            float SampleShadowPCFRadius(float2 uv, float receiverDepth, float bias, float radius)
            {
                float2 texelSize = _MyCustomDepthTexture_TexelSize.xy * max(radius, 0.01);

                float shadow = 0.0;
                float weightSum = 0.0;

                // 5x5 tent filter。
                // 中心权重大，边缘权重小，比普通平均 5x5 更自然。
                [unroll]
                for (int y = -2; y <= 2; y++)
                {
                    [unroll]
                    for (int x = -2; x <= 2; x++)
                    {
                        float wx = 3.0 - abs((float)x);
                        float wy = 3.0 - abs((float)y);
                        float weight = wx * wy;

                        float2 sampleUV = uv + texelSize * float2(x, y);
                        shadow += SampleShadowTap(sampleUV, receiverDepth, bias) * weight;
                        weightSum += weight;
                    }
                }

                return shadow / weightSum;
            }

            // 普通 PCF。
            // 使用材质里的 _PCFRadius。
            float SampleShadowPCF(float2 uv, float receiverDepth, float bias)
            {
                return SampleShadowPCFRadius(uv, receiverDepth, bias, _PCFRadius);
            }

            // PCSS 第一步：搜索 blocker。
            // blocker 是比 receiver 更靠近光源的深度。
            // 返回平均 blocker 深度，输出 blockerCount。
            float FindAverageBlockerDepth(float2 uv, float receiverDepth, float bias, out float blockerCount)
            {
                float2 texelSize = _MyCustomDepthTexture_TexelSize.xy * _PCSSBlockerSearchRadius;

                float blockerDepthSum = 0.0;
                blockerCount = 0.0;

                // 这里用 5x5 搜索 blocker。
                // 搜索范围由 _PCSSBlockerSearchRadius 控制。
                [unroll]
                for (int y = -2; y <= 2; y++)
                {
                    [unroll]
                    for (int x = -2; x <= 2; x++)
                    {
                        float2 sampleUV = uv + texelSize * float2(x, y);

                        if (sampleUV.x < 0.0 || sampleUV.x > 1.0 || sampleUV.y < 0.0 || sampleUV.y > 1.0)
                        {
                            continue;
                        }

                        float d = SAMPLE_TEXTURE2D(_MyCustomDepthTexture, sampler_MyCustomDepthTexture, sampleUV).r;

                        // d < 0.999：这个 texel 里有 caster。
                        // d + bias < receiverDepth：这个 caster 比当前点更靠近光源，说明它可能遮挡当前点。
                        if (d < 0.999 && d + bias < receiverDepth)
                        {
                            blockerDepthSum += d;
                            blockerCount += 1.0;
                        }
                    }
                }

                // 没找到 blocker 时返回 1。
                // 1 表示清屏深度，不会产生阴影。
                return blockerCount > 0.5 ? blockerDepthSum / blockerCount : 1.0;
            }


            // PCSS 完整采样。
            // receiverDepth 是 0~1 线性深度。
            // receiverViewDepth 是光源相机 view space 下的真实线性深度。
            // nearPlane / farPlane 用来把 blocker 的 0~1 深度还原回 view depth。
            float SampleShadowPCSS(float2 uv, float receiverDepth, float receiverViewDepth, float nearPlane, float farPlane, float bias)
            {
                // 1. 搜索 blocker。
                float blockerCount = 0.0;
                float avgBlockerDepth01 = FindAverageBlockerDepth(uv, receiverDepth, bias, blockerCount);

                // 没找到 blocker，说明当前点没有被遮挡。
                if (blockerCount < 0.5)
                {
                    return 0.0;
                }

                // 2. 把 blocker 的 0~1 线性深度还原成 view space 深度。
                float blockerViewDepth = lerp(nearPlane, farPlane, avgBlockerDepth01);

                // 3. 根据 receiver 和 blocker 的距离估算半影大小。
                // receiver 离 blocker 越远，penumbraRatio 越大，阴影越软。
                float penumbraRatio = max(receiverViewDepth - blockerViewDepth, 0.0) / max(blockerViewDepth, 0.001);

                // 4. 把半影比例换成 shadow map 里的采样半径。
                // _PCSSLightSize 越大，软阴影越明显。
                float filterRadius = penumbraRatio * _PCSSLightSize;

                // 5. 限制半径，避免过小或过大。
                filterRadius = clamp(filterRadius, _PCFRadius, _PCSSMaxFilterRadius);

                // 6. 用动态半径做 PCF。
                return SampleShadowPCFRadius(uv, receiverDepth, bias, filterRadius);
            }
            
            float4 Frag(Varyings input) : SV_Target
            {
                
                float3 normalWS = normalize(input.normalWS);
                
                // 光线从光源射向场景。
                // 反方向就是“指向光源”的方向。
                float3 lightDirWS = normalize(_CustomLightDirectionWS);
                float3 toLightDirWS = -lightDirWS;
                
                // 沿法线把接收点稍微推出去，减少自身表面和 shadow map 深度几乎相等导致的 acne。
                float3 receiverPositionWS =input.positionWS + normalWS * _NormalBias;
                    
                float NoL = saturate(dot(normalWS, toLightDirWS));
                
                float3 ambient=SampleSH(normalWS)*_AmbientStrength*_BaseColor.rgb;
                float3 diffuse = NoL * _DiffuseStrength*_BaseColor.rgb;
                float3 unshadowedColor = saturate(ambient + diffuse);
                
                // 世界坐标 -> 光源 UV
                float4 lightUVH = mul(_WorldToLightUVMatrix,float4(receiverPositionWS, 1.0));
                

                float3 lightUVW = lightUVH.xyz / lightUVH.w;
                float2 lightUV = lightUVW.xy;


                // 当前像素在光源 View Space 中的深度
                float3 lightViewPos = mul(_WorldToLightViewMatrix,float4(receiverPositionWS, 1.0)).xyz;


                float viewDepth = -lightViewPos.z;

                float nearPlane = _CustomLightDepthParams.x;
                float farPlane  = _CustomLightDepthParams.y;

                // 注意：这里用 viewDepth 判断 near/far，不再用 lightUVW.z
                bool outside =
                    lightUV.x < 0.0 || lightUV.x > 1.0 ||
                    lightUV.y < 0.0 || lightUV.y > 1.0 ||
                    viewDepth < nearPlane ||
                    viewDepth > farPlane;

                // 临时调试：超出光源相机范围直接显示白色
                if (outside)
                {
                    return float4(unshadowedColor, 1);
                }

                float sampledDepth = SAMPLE_TEXTURE2D(_MyCustomDepthTexture,sampler_MyCustomDepthTexture,lightUV).r;

                float receiverDepth = saturate((viewDepth - nearPlane) * _CustomLightDepthParams.z );
                
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

                
                
                // 面越斜，bias 越大。
                // 正对光源时 NoL 接近 1，bias 小。
                // 掠射角时 NoL 接近 0，bias 大。
                float slopeBias = _SlopeDepthBias * (1.0 - NoL);

                float totalBias = _DepthBias + slopeBias;
                
                float shadow;
                // 优先级：PCSS > PCF > 单点硬阴影。
                // 开了 PCSS 时，PCSS 自己内部会动态决定 PCF 半径。
                if (_UsePCSS > 0.5)
                {
                    shadow = SampleShadowPCSS(lightUV, receiverDepth, viewDepth, nearPlane, farPlane, totalBias);
                }
                else if (_UsePCF > 0.5 && _PCFRadius > 0.0)
                {
                    shadow = SampleShadowPCF(lightUV, receiverDepth, totalBias);
                }
                else
                {
                    shadow = SampleShadowTap(lightUV, receiverDepth, totalBias);
                }


                float shadowFactor = lerp(1.0,1.0 - _ShadowStrength,shadow);
                
                

                float3 finalColor =saturate(ambient + diffuse * shadowFactor);

                return float4(finalColor, _BaseColor.a);
            }

            ENDHLSL
        }
    }
}