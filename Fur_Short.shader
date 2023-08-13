Shader "Century/Fur_Short"
{
    Properties
    {
        [Enum(UnityEngine.Rendering.CullMode)]_Cull("Cull", Float) = 2.0
        [Enum(UnityEngine.Rendering.BlendMode)]_SrcBlend("SrcBlend", Float) = 5.0
        [Enum(UnityEngine.Rendering.BlendMode)]_DstBlend("DstBlend", Float) = 10.0
        [Enum(Off, 0, On, 1)]_ZWrite("ZWrite", Float) = 1.0
        [Enum(UnityEngine.Rendering.CompareFunction)]_ZTest("ZTest", Float) = 4.0
        
        [Space(20)]
        [MainTexture]_BaseMap("BaseMap", 2D) = "white" {}
        [HDR]_FurColor("毛发颜色(FurColor)", Color) = (1, 1, 1, 1)

        [Space(5)]
        _RootColor("遮蔽颜色(RootColor)", Color) = (0.6, 0.5, 0.5, 1)
        _FurShadow("遮蔽比例(FurShadowIntensity)", Range(0.05, 2)) = 0.4

        [Space(30)]
        _FurTex("毛发分布贴图(FurPattern)", 2D) = "white" {}
        _FurLength("毛发长度(FurLength)", Range(0.0,0.05)) = 0.005

        [Space(15)]
        [Toggle(VERTEX_DIR)]_OpenVertexDir("打开顶点色控制毛发方向(VERTEX_DIR)", float) = 1.0
        [Toggle(TEXSHIFT)]_OpenTexShift("贴图偏移还是顶点偏移(TEXSHIFT)", float) = 1.0
        _FurDirScale("毛发偏向程度(FurDirScale)", Range(-1,1)) = 0

        [Space(30)]
        _DiffShift("漫反射偏移(DiffShift)", Range(0, 3)) = 0

        [Space(15)]
        _RimPow("边缘光范围(RimPow)", Range(0.5, 10)) = 2.0
        [HDR]_RimColor("边缘光(RimColor)", Color) = (0, 0, 0, 1)

        [Space(15)]
        [HDR]_AbsorbCol("毛发垂直颜色(AbsorbCol)", Color) = (0, 0, 0, 1)
        _Absorb("垂直颜色范围(Absorb)", Range(0, 1)) = 1
        
        _FurDirNormalStrength("计算垂直的法线偏向程度(FurDirNormalStrength)", Range(0.01,1)) = 0.56

        [Space(30)]
        [KeywordEnum(CLIP,BLEND)]_AlphaType("毛发软硬(AphaType)",Float)= 0.0
        _AlphaValue("毛发密度(AlphaValue)", Range(0,1)) = 0.0

        [Space(10)]
        [Toggle(SCRIPTINS)]_OpenScriptIns("实例化用代码实现的话需要打开(SCRIPTINS)", float) = 1.0
    }
    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline" "Queue" = "Transparent" "UniversalMaterialType" = "Lit" "IgnoreProjector" = "True" }
        LOD 100

        Pass
        {
            Tags{"LightMode" = "UniversalForward"}

            Blend[_SrcBlend][_DstBlend]
            ZWrite[_ZWrite]
            Cull[_Cull]

            HLSLPROGRAM

            #pragma target 3.0

            #pragma multi_compile_instancing
            #pragma instancing_options renderinglayer
            
            #pragma shader_feature_local VERTEX_DIR
            #pragma shader_feature_local_fragment _ALPHATYPE_CLIP _ALPHATYPE_BLEND
            #pragma shader_feature_local SCRIPTINS
            #pragma shader_feature_local TEXSHIFT

            #pragma shader_feature_local _NORMALMAP

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN

            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "./FuncLib.hlsl"
            
            #pragma vertex LitPassVertex
            #pragma fragment LitPassFragment

            struct Attributes
            {
                float4 positionOS   : POSITION;
                float3 normalOS     : NORMAL;
                float4 tangentOS    : TANGENT;
                float2 texcoord     : TEXCOORD0;

                float2 flowDir      : COLOR;

                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float2 uv                       : TEXCOORD0;
                float3 positionWS               : TEXCOORD1;

                float3 normalWS                 : TEXCOORD2;
                half4 tangentWS                 : TEXCOORD3;    // xyz: tangent, w: sign

                float3 vertexLight              : TEXCOORD4;
                float2 toFragValue              : TEXCOORD5;   //x:absprb y:rootAO

                float2 flowDir                  : TEXCOORD6;

                float4 positionCS               : SV_POSITION;

                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            TEXTURE2D(_FurTex);  SAMPLER(sampler_FurTex);

            float4 _FurTex_ST;

            float3 _FurColor, _RootColor;
            float _FurLength, _FurShadow, _FurDirScale, _FurDirNormalStrength;

            float3 _RimColor, _AbsorbCol;
            float _DiffShift, _Absorb, _RimPow;

            float _AlphaValue;

#if UNITY_ANY_INSTANCING_ENABLED
    #if SCRIPTINS
            float3 _LayerOffset[30];

            #define GETLAYOUTOFFSET(input, defaultValue) _LayerOffset[UNITY_GET_INSTANCE_ID(input)]
    #else
            float _LayerOffset;

            UNITY_INSTANCING_BUFFER_START(Props)
                UNITY_DEFINE_INSTANCED_PROP(float, _LayerOffset)
            UNITY_INSTANCING_BUFFER_END(Props)

            #define GETLAYOUTOFFSET(input, defaultValue) UNITY_ACCESS_INSTANCED_PROP(Props, _LayerOffset)
    #endif
#else
            #define GETLAYOUTOFFSET(input, defaultValue) defaultValue
#endif

            Varyings LitPassVertex(Attributes input)
            {
                Varyings output = (Varyings)0;

                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);

                float layerOffset = GETLAYOUTOFFSET(input, 0);
                float layerOffset2 = layerOffset * layerOffset;

                float sign = input.tangentOS.w * GetOddNegativeScale();
                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);
                float3 tangentWS = float3(TransformObjectToWorldDir(input.tangentOS.xyz));
                float3 bitangentWS = float3(cross(normalWS, tangentWS)) * sign;
                float3x3 tangentToWorld = float3x3(tangentWS, bitangentWS, normalWS);
#if VERTEX_DIR
                float2 flowDir = input.flowDir * 2 - 1;
#else
                float2 flowDir = float2(0.3, 0.7);
#endif
               
                float3 offsetVertex = input.positionOS.xyz + input.normalOS * layerOffset * _FurLength;
                float3 positionWS = TransformObjectToWorld(offsetVertex);

#if !TEXSHIFT
                float2 vertexFlowDir = flowDir;
                float3 furFlowDirTS = float3(vertexFlowDir, 0);
                furFlowDirTS = normalize(furFlowDirTS);

                float3 furFlowDirWS = TransformTangentToWorld(furFlowDirTS, tangentToWorld);

                positionWS += lerp(0, furFlowDirWS * _FurDirScale * 0.1f, layerOffset2);
#endif

                flowDir = normalize(flowDir) * _FurDirScale;

                float4 positionCS = TransformWorldToHClip(positionWS);
                output.flowDir = flowDir; 
                output.uv = input.texcoord; 
                output.positionWS = positionWS; 
                output.normalWS = normalWS; 
                output.tangentWS = float4(tangentWS, sign);
                output.positionCS = positionCS;

                float3 lightDirectionWS = _MainLightPosition.xyz; 
                float3 lightColor = _MainLightColor.rgb; 
                float3 viewDirWS = GetWorldSpaceNormalizeViewDir(positionWS);
     
                float NoL = saturate(dot(normalWS, lightDirectionWS));
                float NoV = saturate(dot(normalWS, viewDirWS));
                float LoV = saturate(dot(lightDirectionWS, viewDirWS));

                float3 diffuse = lightColor * WrapLighting(NoL, _DiffShift);

                float fresnel = 1 - NoV;
                float nLoV = saturate(-dot(lightDirectionWS, viewDirWS));
                float3 rimLight = pow(fresnel, _RimPow) * layerOffset2 * nLoV; // * abs(LoV * 0.5 - 0.5)
                rimLight *= rimLight * _RimColor;

                float3 ambient = max(half3(0, 0, 0), SampleSH(normalWS));

                output.vertexLight = ambient + diffuse + rimLight;

#if VERTEX_DIR
                float3 normalTS = float3(0, 0, 1);
                normalTS.xy += flowDir;
                normalTS.z *= _FurDirNormalStrength;
                normalTS = normalize(normalTS);

                float3 shiftNormalWS = TransformTangentToWorld(normalTS, tangentToWorld);
                //half sNoL = saturate(dot(shiftNormalWS, lightDirectionWS));

                half sNoV = saturate(dot(shiftNormalWS, viewDirWS));

                float NoVWeaken = saturate(sNoV);
#else
                float NoVWeaken = saturate(NoV);
#endif

                //float LoVWeaken = saturate(LoV);
                //float NoLWeaken2 = NoLWeaken * NoLWeaken; 
                //float LoVWeaken2 = LoVWeaken * LoVWeaken;

                float NoVWeaken2 = NoVWeaken * NoVWeaken;
                //NoLWeaken2 * NoLWeaken2 * LoVWeaken2 * LoVWeaken2
                output.toFragValue.x = saturate(NoVWeaken2 - _Absorb) / (1 - _Absorb);
                output.toFragValue.y = saturate(pow(saturate(layerOffset), _FurShadow));

                return output;
            }

            half4 LitPassFragment (Varyings i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);

                float layerOffset = GETLAYOUTOFFSET(i, 0);

                float2 furColUV = i.uv;
#if TEXSHIFT
                furColUV -= lerp(0, i.flowDir * 0.1f, layerOffset);
#endif
                furColUV = TRANSFORM_TEX(furColUV, _FurTex);

                float3 furCol = SAMPLE_TEXTURE2D(_FurTex, sampler_FurTex, furColUV).rgb;


                float alpha = 1;

#if _ALPHATYPE_CLIP
                float alphaCutoff = lerp(0.4f, 0.02f, _AlphaValue);
                float alphaValue = furCol.r * (1.0f - layerOffset);
                float clipValue = lerp(1, alphaValue - alphaCutoff, step(0.01f, layerOffset));
                clip(clipValue);
#elif _ALPHATYPE_BLEND
                float alphaOffset = lerp(0.1f, 0.8f, _AlphaValue);
                alpha = saturate(furCol.r - layerOffset * layerOffset + alphaOffset);
                alpha = lerp(1 , alpha, step(0.01f, layerOffset));
#endif

                float2 albedoUV = i.uv;
#if TEXSHIFT
                albedoUV -= lerp(0, i.flowDir * 0.1f, layerOffset);
#endif
                albedoUV = TRANSFORM_TEX(albedoUV, _BaseMap);

                float3 albedo = SampleAlbedoAlpha(albedoUV, TEXTURE2D_ARGS(_BaseMap, sampler_BaseMap)).rgb * _FurColor;

                float absorbLerp = i.toFragValue.x; 
                float3 furColBlendAbsorb = i.vertexLight * albedo;
                furColBlendAbsorb = lerp(furColBlendAbsorb, _AbsorbCol, absorbLerp);

                float aoLerp = i.toFragValue.y;

                float3 rootColor = _RootColor * albedo;
                float3 furColBlendA0 = lerp(rootColor, furColBlendAbsorb, aoLerp);

                half4 color = float4(0, 0, 0, alpha);
                color.rgb += furColBlendA0;

                return color;
            }

            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags{"LightMode" = "ShadowCaster"}

            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull[_Cull]

            HLSLPROGRAM
            #pragma exclude_renderers gles gles3 glcore
            #pragma target 4.5

            // -------------------------------------
            // Material Keywords
            #pragma shader_feature_local_fragment _ALPHATEST_ON
            #pragma shader_feature_local_fragment _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A

            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing
            #pragma multi_compile _ DOTS_INSTANCING_ON

            // -------------------------------------
            // Universal Pipeline keywords

            // This is used during shadow map generation to differentiate between directional and punctual light shadows, as they use different formulas to apply Normal Bias
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment

            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags{"LightMode" = "DepthOnly"}

            ZWrite On
            ColorMask 0
            Cull[_Cull]

            HLSLPROGRAM
            #pragma exclude_renderers gles gles3 glcore
            #pragma target 4.5

            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment

            // -------------------------------------
            // Material Keywords
            #pragma shader_feature_local_fragment _ALPHATEST_ON
            #pragma shader_feature_local_fragment _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A

            //--------------------------------------
            // GPU Instancing
            #pragma multi_compile_instancing
            #pragma multi_compile _ DOTS_INSTANCING_ON

            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/DepthOnlyPass.hlsl"
            ENDHLSL
        }
    }
}
