Shader "Custom/JellyFusionFinalTransparent"
{
    Properties
    {
        _Color ("Color", Color) = (1,1,1,0.7) // Default alpha set to 0.7
        _Glossiness ("Smoothness", Range(0,1)) = 0.5
        _Metallic ("Metallic", Range(0,1)) = 0.0
        _Inertia ("Inertia Vector", Vector) = (0,0,0,0)
        _OpponentPos ("Opponent Local Pos", Vector) = (0,0,0,0)
        _FusionAmount ("Fusion Amount", Range(0,2)) = 0
    }

    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent" "RenderPipeline"="UniversalPipeline" "IgnoreProjector"="True" }
        LOD 200

        Blend SrcAlpha OneMinusSrcAlpha
        ZWrite Off
        Cull Back

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

        CBUFFER_START(UnityPerMaterial)
            float4 _Color;
            half _Glossiness;
            half _Metallic;
            float4 _Inertia;
            float4 _OpponentPos;
            float _FusionAmount;
        CBUFFER_END

        // Same jelly displacement math as the original surf shader's vert(), unchanged.
        void ApplyJellyDisplacement(inout float3 vPos, float3 vNormal)
        {
            if (_FusionAmount > 0)
            {
                float3 dirToOpp = _OpponentPos.xyz - vPos;
                float dist = length(dirToOpp);

                float facing = saturate(dot(vNormal, normalize(_OpponentPos.xyz)));

                float pull = pow(saturate(2.0 - dist), 2.0) * _FusionAmount * facing;
                vPos += normalize(dirToOpp) * pull * 0.15;
            }

            float squash = _Inertia.y;
            float heightWeight = vPos.y + 0.5;

            vPos.x += _Inertia.x * heightWeight;
            vPos.z += _Inertia.z * heightWeight;
            vPos.y += squash * heightWeight;

            float volumeFix = 1.0 - (squash * 0.5);
            vPos.xz *= lerp(1.0, volumeFix, heightWeight);
        }
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile_fragment _ _FORWARD_PLUS
            #pragma multi_compile_fog
            #pragma multi_compile_instancing

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3 normalWS   : TEXCOORD1;
                float2 uv         : TEXCOORD2;
                float fogCoord    : TEXCOORD3;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings vert(Attributes IN)
            {
                Varyings OUT = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_TRANSFER_INSTANCE_ID(IN, OUT);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(OUT);

                float3 vPos = IN.positionOS.xyz;
                ApplyJellyDisplacement(vPos, IN.normalOS);

                VertexPositionInputs positions = GetVertexPositionInputs(vPos);
                OUT.positionCS = positions.positionCS;
                OUT.positionWS = positions.positionWS;
                OUT.normalWS = TransformObjectToWorldNormal(IN.normalOS);
                OUT.uv = IN.uv;
                OUT.fogCoord = ComputeFogFactor(positions.positionCS.z);
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(IN);

                float3 normalWS = normalize(IN.normalWS);
                float3 viewDirWS = GetWorldSpaceNormalizeViewDir(IN.positionWS);

                BRDFData brdfData;
                InitializeBRDFData(_Color.rgb, _Metallic, half3(0, 0, 0), _Glossiness, _Color.a, brdfData);

                float4 shadowCoord = TransformWorldToShadowCoord(IN.positionWS);
                Light mainLight = GetMainLight(shadowCoord);

                half3 color = LightingPhysicallyBased(brdfData, mainLight, normalWS, viewDirWS);

                #ifdef _ADDITIONAL_LIGHTS
                uint pixelLightCount = GetAdditionalLightsCount();
                for (uint lightIndex = 0u; lightIndex < pixelLightCount; lightIndex++)
                {
                    Light light = GetAdditionalLight(lightIndex, IN.positionWS);
                    color += LightingPhysicallyBased(brdfData, light, normalWS, viewDirWS);
                }
                #endif

                // Ambient/GI, matching Standard's baked+reflection-probe contribution.
                float3 bakedGI = SampleSH(normalWS);
                color += bakedGI * brdfData.diffuse;

                float3 reflectVector = reflect(-viewDirWS, normalWS);
                half3 indirectSpecular = GlossyEnvironmentReflection(reflectVector, IN.positionWS, 1.0 - _Glossiness, 1.0, 0);
                color += indirectSpecular * brdfData.specular;

                // Same emission term as the original surf(): _Color * _FusionAmount * 0.2
                color += _Color.rgb * _FusionAmount * 0.2;

                color = MixFog(color, IN.fogCoord);

                return half4(color, _Color.a);
            }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }

            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull Back

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #pragma multi_compile_instancing

            float3 _LightDirection;
            float3 _LightPosition;

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
            };

            Varyings vert(Attributes IN)
            {
                Varyings OUT = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(IN);

                float3 vPos = IN.positionOS.xyz;
                ApplyJellyDisplacement(vPos, IN.normalOS);

                float3 positionWS = TransformObjectToWorld(vPos);
                float3 normalWS = TransformObjectToWorldNormal(IN.normalOS);

                #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                    float3 lightDirectionWS = normalize(_LightPosition - positionWS);
                #else
                    float3 lightDirectionWS = _LightDirection;
                #endif

                float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS));

                #if UNITY_REVERSED_Z
                    positionCS.z = min(positionCS.z, positionCS.w * UNITY_NEAR_CLIP_VALUE);
                #else
                    positionCS.z = max(positionCS.z, positionCS.w * UNITY_NEAR_CLIP_VALUE);
                #endif

                OUT.positionCS = positionCS;
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                return 0;
            }
            ENDHLSL
        }
    }
}
