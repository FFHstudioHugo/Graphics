Shader "Hidden/HDRP/TemporalAA"
{
    Properties
    {
        [HideInInspector] _StencilRef("_StencilRef", Int) = 2
        [HideInInspector] _StencilMask("_StencilMask", Int) = 2
    }

    HLSLINCLUDE

        #pragma target 4.5
        #pragma multi_compile_local_fragment _ ORTHOGRAPHIC
        #pragma multi_compile_local_fragment _ ENABLE_ALPHA
        #pragma multi_compile_local_fragment _ FORCE_BILINEAR_HISTORY
        #pragma multi_compile_local_fragment _ ENABLE_MV_REJECTION ENABLE_MV_REJECTION_OBJ_ONLY
        #pragma multi_compile_local_fragment _ ANTI_RINGING
        #pragma multi_compile_local_fragment _ DIRECT_STENCIL_SAMPLE
        #pragma multi_compile_local_fragment LOW_QUALITY MEDIUM_QUALITY HIGH_QUALITY TAA_UPSCALE POST_DOF

        #pragma editor_sync_compilation
        #pragma enable_d3d11_debug_symbols

        #pragma only_renderers d3d11 playstation xboxone xboxseries vulkan metal switch
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
        #include "Packages/com.unity.render-pipelines.high-definition/Runtime/Material/Builtin/BuiltinData.hlsl"
        #include "Packages/com.unity.render-pipelines.high-definition/Runtime/ShaderLibrary/ShaderVariables.hlsl"
        #include "Packages/com.unity.render-pipelines.high-definition/Runtime/PostProcessing/Shaders/PostProcessDefines.hlsl"


        // ---------------------------------------------------
        // Tier definitions
        // ---------------------------------------------------
        //  TODO: YCoCg gives better result in terms of ghosting reduction, but it also seems to let through
        //  some additional aliasing that is undesirable in some occasions. Would like to investigate better.
#ifdef LOW_QUALITY
    #define YCOCG 0
    #define HISTORY_SAMPLING_METHOD BILINEAR
    #define WIDE_NEIGHBOURHOOD 0
    #define NEIGHBOUROOD_CORNER_METHOD MINMAX
    #define CENTRAL_FILTERING NO_FILTERING
    #define HISTORY_CLIP SIMPLE_CLAMP
    #define ANTI_FLICKER 0
    #define VELOCITY_REJECTION (defined(ENABLE_MV_REJECTION) && 0)
    #define PERCEPTUAL_SPACE 0
    #define PERCEPTUAL_SPACE_ONLY_END 1 && (PERCEPTUAL_SPACE == 0)
    #define CLOSEST_VEL_SEARCH_WIDTH 1

#elif defined(MEDIUM_QUALITY)
    #define YCOCG 1
    #define HISTORY_SAMPLING_METHOD BICUBIC_5TAP
    #define WIDE_NEIGHBOURHOOD 0
    #define NEIGHBOUROOD_CORNER_METHOD VARIANCE
    #define CENTRAL_FILTERING NO_FILTERING
    #define HISTORY_CLIP DIRECT_CLIP
    #define ANTI_FLICKER 1
    #define ANTI_FLICKER_MV_DEPENDENT 0
    #define VELOCITY_REJECTION (defined(ENABLE_MV_REJECTION) && 0)
    #define PERCEPTUAL_SPACE 1
    #define PERCEPTUAL_SPACE_ONLY_END 0 && (PERCEPTUAL_SPACE == 0)
    #define CLOSEST_VEL_SEARCH_WIDTH 1

#elif defined(HIGH_QUALITY) // TODO: We can do better in term of quality here (e.g. subpixel changes etc) and can be optimized a bit more
    #define YCOCG 1
    #define HISTORY_SAMPLING_METHOD BICUBIC_5TAP
    #define WIDE_NEIGHBOURHOOD 1
    #define NEIGHBOUROOD_CORNER_METHOD VARIANCE
    #define CENTRAL_FILTERING SHARP_FILTER
    #define HISTORY_CLIP DIRECT_CLIP
    #define ANTI_FLICKER 1
    #define ANTI_FLICKER_MV_DEPENDENT 1
    #define VELOCITY_REJECTION defined(ENABLE_MV_REJECTION) || defined(ENABLE_MV_REJECTION_OBJ_ONLY)
    #define PERCEPTUAL_SPACE 1
    #define PERCEPTUAL_SPACE_ONLY_END 0 && (PERCEPTUAL_SPACE == 0)
    #define CLOSEST_VEL_SEARCH_WIDTH 2

#elif defined(TAA_UPSCALE)
    #define YCOCG 1
    #define HISTORY_SAMPLING_METHOD BICUBIC_5TAP
    #define WIDE_NEIGHBOURHOOD 1
    #define NEIGHBOUROOD_CORNER_METHOD VARIANCE
    #define CENTRAL_FILTERING SHARP_FILTER
    #define HISTORY_CLIP DIRECT_CLIP
    #define ANTI_FLICKER 1
    #define ANTI_FLICKER_MV_DEPENDENT 1
    #define VELOCITY_REJECTION defined(ENABLE_MV_REJECTION) || defined(ENABLE_MV_REJECTION_OBJ_ONLY)
    #define PERCEPTUAL_SPACE 1
    #define PERCEPTUAL_SPACE_ONLY_END 0 && (PERCEPTUAL_SPACE == 0)
    #define UPSCALE 
    #define CLOSEST_VEL_SEARCH_WIDTH 2

#elif defined(POST_DOF)
    #define YCOCG 1
    #define HISTORY_SAMPLING_METHOD BILINEAR
    #define WIDE_NEIGHBOURHOOD 0
    #define NEIGHBOUROOD_CORNER_METHOD VARIANCE
    #define CENTRAL_FILTERING NO_FILTERING
    #define HISTORY_CLIP DIRECT_CLIP
    #define ANTI_FLICKER 1
    #define ANTI_FLICKER_MV_DEPENDENT 1
    #define VELOCITY_REJECTION defined(ENABLE_MV_REJECTION) || defined(ENABLE_MV_REJECTION_OBJ_ONLY)
    #define PERCEPTUAL_SPACE 1
    #define PERCEPTUAL_SPACE_ONLY_END 0 && (PERCEPTUAL_SPACE == 0)
    #define CLOSEST_VEL_SEARCH_WIDTH 1

#endif

#ifndef CLOSEST_VEL_SEARCH_WIDTH
    #define CLOSEST_VEL_SEARCH_WIDTH 1
#endif


        #include "Packages/com.unity.render-pipelines.high-definition/Runtime/PostProcessing/Shaders/TemporalAntialiasing.hlsl"

        TEXTURE2D_X(_DepthTexture);
        TEXTURE2D_X(_InputTexture);
        TEXTURE2D_X(_InputHistoryTexture);
        #ifdef SHADER_API_PSSL
        RW_TEXTURE2D_X(CTYPE, _OutputHistoryTexture) : register(u0);
        #else
        RW_TEXTURE2D_X(CTYPE, _OutputHistoryTexture) : register(u1);
        #endif

        #if DIRECT_STENCIL_SAMPLE
        TEXTURE2D_X_UINT2(_StencilTexture);
        #endif

        float4 _TaaPostParameters;
        float4 _TaaPostParameters1;
        float4 _TaaHistorySize;
        float4 _TaaFilterInfo;

        #define _HistorySharpening _TaaPostParameters.x
        #define _AntiFlickerIntensity _TaaPostParameters.y
        #define _SpeedRejectionIntensity _TaaPostParameters.z
        #define _ContrastForMaxAntiFlicker _TaaPostParameters.w

        #define _BaseBlendFactor _TaaPostParameters1.x
        #define _CentralWeight _TaaPostParameters1.y
        #define _ExcludeTAABit (uint)_TaaPostParameters1.z

        #define _CentralFilterSharpness _TaaFilterInfo.x

        // TAAU specific
        float4 _TaauParameters;
        #define _TAAUFilterRcpSigma2 _TaauParameters.x
        #define _TAAUScale _TaauParameters.y
        #define _TAAUBoxConfidenceThresh _TaauParameters.z
        #define _TAAURenderScale _TaauParameters.w
        #define _InputSize _ScreenSize


        float4 _TaaScales;
        // NOTE: We need to define custom scales instead of using the default ones for several reasons.
        // 1- This shader is shared by TAA and Temporal Upscaling, having a single scale defined in C# instead helps readability.
        // 2- Especially with history, when doing temporal upscaling we have an unusal situation in which the history size doesn't match the input size.
        //    This in turns lead to some rounding issue (final viewport is not rounded, while the render target size is) that cause artifacts.
        //    To fix said artifacts we recompute manually the scales as we need them.
        #define _RTHandleScaleForTAAHistory _TaaScales.xy
        #define _RTHandleScaleForTAA _TaaScales.zw

        TEXTURE2D_X(_InputVelocityMagnitudeHistory);
        #ifdef SHADER_API_PSSL
        RW_TEXTURE2D_X(float2, _OutputVelocityMagnitudeHistory) : register(u1);
        #else
        RW_TEXTURE2D_X(float2, _OutputVelocityMagnitudeHistory) : register(u2);
        #endif

        struct Attributes
        {
            uint vertexID : SV_VertexID;
            UNITY_VERTEX_INPUT_INSTANCE_ID
        };

        struct Varyings
        {
            float4 positionCS : SV_POSITION;
            float2 texcoord   : TEXCOORD0;
            UNITY_VERTEX_OUTPUT_STEREO
        };

        Varyings Vert(Attributes input)
        {
            Varyings output;
            UNITY_SETUP_INSTANCE_ID(input);
            UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);
            output.positionCS = GetFullScreenTriangleVertexPosition(input.vertexID);
            output.texcoord = GetFullScreenTriangleTexCoord(input.vertexID);
            return output;
        }

    // ------------------------------------------------------------------

        void FragTAA(Varyings input, out CTYPE outColor : SV_Target0)
        {
            UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

            float sharpenStrength = _TaaFrameInfo.x;
            float2 jitter = _TaaJitterStrength.zw;

            float2 velocityUV = input.texcoord;

            #ifdef TAA_UPSCALE
            float2 outputPixInInput = input.texcoord * _InputSize.xy - _TaaJitterStrength.xy;
            velocityUV = input.positionCS.xy * _TAAURenderScale * _ScreenSize.zw;
            #endif

            // --------------- Get closest motion vector ---------------
            float2 motionVector;

            int2 samplePos = input.positionCS.xy;

#if ORTHOGRAPHIC
            float2 closestOffset = 0;
#else

#ifdef TAA_UPSCALE
            samplePos = outputPixInInput;
#endif

            float centerDepth, closestDepth;
            float2 closestOffset = GetClosestFragmentOffset(_DepthTexture, samplePos, CLOSEST_VEL_SEARCH_WIDTH, centerDepth, closestDepth);

#endif
            bool excludeTAABit = false;
#if DIRECT_STENCIL_SAMPLE
            uint stencil = GetStencilValue(LOAD_TEXTURE2D_X(_StencilTexture, samplePos));
            excludeTAABit = (stencil == _ExcludeTAABit);
#endif

            float lengthMV = 0;

            // Looks like the speed rejection wants to use not the expanded velocity, but the properly central one.
            // TODO: Investigate and if confirmed add option? I feel like the issue is somewhere else.
            DecodeMotionVector(SAMPLE_TEXTURE2D_X_LOD(_CameraMotionVectorsTexture, s_linear_clamp_sampler, ClampAndScaleUVForPoint(velocityUV + closestOffset * _InputSize.zw), 0), motionVector);
            // --------------------------------------------------------

            // --------------- Get resampled history ---------------
            float2 prevUV = input.texcoord - motionVector;

            CTYPE history = GetFilteredHistory(_InputHistoryTexture, prevUV, _HistorySharpening, _TaaHistorySize, _RTHandleScaleForTAAHistory);
            CTYPE unclampedH = history;
            bool offScreen = any(abs(prevUV * 2 - 1) >= (1.0f - (1.0 * _TaaHistorySize.zw)));
            history.xyz *= PerceptualWeight(history);



            float prevFactor = _InputVelocityMagnitudeHistory[COORD_TEXTURE2D_X(int2(input.positionCS.xy))].g;

            // -----------------------------------------------------

            // --------------- Gather neigbourhood data ---------------

            NeighbourhoodInfo samples;
            
            CTYPE filteredColor = GatherNeighbourhoodAndFilterColor(_InputTexture, input.positionCS.xy, _TaaJitterStrength.xy, _TAAURenderScale, _CentralFilterSharpness, samples);
            CTYPE color = filteredColor;
            float blendFactor = 0;

            float3 dbg = 0;

            if (!excludeTAABit)
            {
                // ------------------------------------------------------

                if (offScreen)
                    history = filteredColor;

                // --------------- Get neighbourhood information and clamp history ---------------
                float colorLuma = GetLuma(filteredColor);
                float historyLuma = GetLuma(history);

                float motionVectorLength = 0.0f;
                float motionVectorLenInPixels = 0.0f;

#if ANTI_FLICKER_MV_DEPENDENT || VELOCITY_REJECTION
                motionVectorLength = length(motionVector);
                motionVectorLenInPixels = motionVectorLength * length(_InputSize.xy);

#if VELOCITY_REJECTION
                bool skipRejection = false;

#ifdef ENABLE_MV_REJECTION_OBJ_ONLY
                // TODO: This is not possible to enable via UX because due to the fact that the recovered velocities are going to be aliased
                // we are going to have weird results at silhouettes.
                float2 cameraMV = GrabCameraMotionVec(velocityUV, centerDepth);
                float speedRejectionLen = length(motionVector - cameraMV);
#else
                float speedRejectionLen = motionVectorLength;
#endif

#endif

#endif

                ResolveNeighbourhoodCorners(samples, historyLuma, colorLuma, float2(_AntiFlickerIntensity, _ContrastForMaxAntiFlicker), motionVectorLenInPixels, _TAAURenderScale);

                history = GetClippedHistory(filteredColor, history, samples.minNeighbour, samples.maxNeighbour);
                filteredColor = SharpenColor(samples, filteredColor, sharpenStrength);
                // ------------------------------------------------------------------------------

                // --------------- Compute blend factor for history ---------------
                blendFactor = GetBlendFactor(colorLuma, historyLuma, GetLuma(samples.minNeighbour), GetLuma(samples.maxNeighbour), _BaseBlendFactor);
                // --------------------------------------------------------

                // ------------------- Alpha handling ---------------------------
#if defined(ENABLE_ALPHA)
                // Compute the antialiased alpha value
                filteredColor.w = lerp(history.w, filteredColor.w, blendFactor);
                // TAA should not overwrite pixels with zero alpha. This allows camera stacking with mixed TAA settings (bottom camera with TAA OFF and top camera with TAA ON).
                CTYPE unjitteredColor = Fetch4(_InputTexture, input.texcoord - color.w * jitter, 0.0, _RTHandleScale.xy).CTYPE_SWIZZLE;
                unjitteredColor = ConvertToWorkingSpace(unjitteredColor);
                unjitteredColor.xyz *= PerceptualWeight(unjitteredColor);
                filteredColor.xyz = lerp(unjitteredColor.xyz, filteredColor.xyz, filteredColor.w);
                blendFactor = color.w > 0 ? blendFactor : 1;
#endif
                // ---------------------------------------------------------------

                // --------------- Blend to final value and output ---------------

#if VELOCITY_REJECTION
                // The 10 multiplier serves a double purpose, it is an empirical scale value used to perform the rejection and it also helps with storing the value itself.
                lengthMV = speedRejectionLen * 10;
                if (!skipRejection)
                    blendFactor = ModifyBlendWithMotionVectorRejection(_InputVelocityMagnitudeHistory, lengthMV, prevUV, blendFactor, _SpeedRejectionIntensity, _RTHandleScaleForTAAHistory);
#endif

#ifdef TAA_UPSCALE
                // TODO_FCC: IMPORTANT BEFORE PR!! outputPixInInput - (floor(outputPixInInput) + 0.5f); rephrase this with new method.
                blendFactor *= GetUpsampleConfidence(outputPixInInput - (floor(outputPixInInput) + 0.5f), _TAAUBoxConfidenceThresh, _TAAUFilterRcpSigma2, _TAAUScale);
#endif
                blendFactor = max(blendFactor, 0.03);

                /////////////////////////////////////////////

               // blendFactor = lerp (_BaseBlendFactor, 1.0, prevFactor);

                CTYPE bhistory = unclampedH;

                const float clamping_event = length(max(0.0, max(bhistory - samples.maxNeighbour, samples.minNeighbour - bhistory)) / max(0.01, samples.moment1));

                float clampDist = (max(abs(historyLuma - GetLuma(samples.minNeighbour)), abs(historyLuma - GetLuma(samples.maxNeighbour))))
                    / max(historyLuma, 1e-5);

                float dist = DistanceToClamp(historyLuma, GetLuma(samples.minNeighbour), GetLuma(samples.maxNeighbour));
                blendFactor *= lerp(0.2, 1.0, smoothstep(0.0, 2.0, clampDist));


                const float initial_bclamp_amount = saturate(dot(
                    history - unclampedH, samples.filteredCentral - unclampedH)
                    / max(1e-5, length(history - unclampedH) * length(samples.filteredCentral - unclampedH)));

               // blendFactor =  prevFactor * lerp(0.1, 1.0f, saturate(10* clamping_event));

                dbg = initial_bclamp_amount* initial_bclamp_amount* initial_bclamp_amount * initial_bclamp_amount * initial_bclamp_amount;

#if ANTI_RINGING
                blendFactor = 1.0f - dbg.x;
                blendFactor = max(blendFactor, 0.03);
#endif
                //dbg = saturate(initial_bclamp_amount);
                _OutputVelocityMagnitudeHistory[COORD_TEXTURE2D_X(input.positionCS.xy)] = float2(lengthMV, blendFactor);

                /////////////////////////////////////////////


                CTYPE finalColor;

             //   filteredColor.xyz = samples.minNeighbour;
#if PERCEPTUAL_SPACE_ONLY_END
                finalColor.xyz = lerp(ReinhardToneMap(history).xyz, ReinhardToneMap(filteredColor).xyz, blendFactor);
                finalColor.xyz = InverseReinhardToneMap(finalColor).xyz;
#else
                finalColor.xyz = lerp(history.xyz, filteredColor.xyz, blendFactor);
                finalColor.xyz *= PerceptualInvWeight(finalColor);
#endif

                color.xyz = ConvertToOutputSpace(finalColor.xyz);
                color.xyz = clamp(color.xyz, 0, CLAMP_MAX);
#if defined(ENABLE_ALPHA)
                // Set output alpha to the antialiased alpha.
                color.w = filteredColor.w;
#endif

             //   dbg = blendFactor;
            }

            //if (dbg.x < 0.2)
            //    color.xyz += float3(10, 0, 0);

            _OutputHistoryTexture[COORD_TEXTURE2D_X(input.positionCS.xy)] = color.CTYPE_SWIZZLE;

            outColor = color.CTYPE_SWIZZLE;
          //  outColor = dbg;

#if VELOCITY_REJECTION && !defined(POST_DOF)
  //          _OutputVelocityMagnitudeHistory[COORD_TEXTURE2D_X(input.positionCS.xy)] = lengthMV;
#endif
            // -------------------------------------------------------------
        }

        void FragExcludedTAA(Varyings input, out CTYPE outColor : SV_Target0)
        {
            UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

            float2 jitter = _TaaJitterStrength.zw;
            float2 uv = input.texcoord - jitter;

            outColor = Fetch4(_InputTexture, uv, 0.0, _RTHandleScale.xy).CTYPE_SWIZZLE;
        }

        void FragCopyHistory(Varyings input, out CTYPE outColor : SV_Target0)
        {
            UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

            float2 jitter = _TaaJitterStrength.zw;
            float2 uv = input.texcoord;

#ifdef TAA_UPSCALE
            float2 outputPixInInput = input.texcoord * _InputSize.xy - _TaaJitterStrength.xy;

            uv = _InputSize.zw * (0.5f + floor(outputPixInInput));
#endif
            CTYPE color = Fetch4(_InputTexture, uv, 0.0, _RTHandleScaleForTAA).CTYPE_SWIZZLE;

            outColor = color;
        }

    ENDHLSL

    SubShader
    {
        Tags{ "RenderPipeline" = "HDRenderPipeline" }

        // TAA
        Pass
        {
            Stencil
            {
                ReadMask [_StencilMask]       // ExcludeFromTAA
                Ref [_StencilRef]          // ExcludeFromTAA
                Comp NotEqual
                Pass Keep
            }

            ZWrite Off ZTest Always Blend Off Cull Off

            HLSLPROGRAM
                #pragma vertex Vert
                #pragma fragment FragTAA
            ENDHLSL
        }

        // Excluded from TAA
        // Note: This is a straightup passthrough now, but it would be interesting instead to try to reduce history influence instead.
        Pass
        {
            Stencil
            {
                ReadMask [_StencilMask]
                Ref     [_StencilRef]
                Comp Equal
                Pass Keep
            }

            ZWrite Off ZTest Always Blend Off Cull Off

            HLSLPROGRAM
                #pragma vertex Vert
                #pragma fragment FragExcludedTAA
            ENDHLSL
        }

        Pass // TAAU
        {
            // We cannot stencil with TAAU, we will need to manually sample the texture.

            ZWrite Off ZTest Always Blend Off Cull Off

            HLSLPROGRAM
                #pragma vertex Vert
                #pragma fragment FragTAA
            ENDHLSL
        }

        Pass // Copy history
        {
            ZWrite Off ZTest Always Blend Off Cull Off

            HLSLPROGRAM
                #pragma vertex Vert
                #pragma fragment FragCopyHistory
            ENDHLSL
        }

    }
    Fallback Off
}
