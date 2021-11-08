#ifndef __PROBEVOLUME_HLSL__
#define __PROBEVOLUME_HLSL__

#include "Packages/com.unity.render-pipelines.core/Runtime/Lighting/ProbeVolume/ShaderVariablesProbeVolumes.cs.hlsl"

#ifndef DECODE_SH
#include "Packages/com.unity.render-pipelines.core/Runtime/Lighting/ProbeVolume/DecodeSH.hlsl"
#endif

#ifndef UNITY_SHADER_VARIABLES_INCLUDED
SAMPLER(s_linear_clamp_sampler);
SAMPLER(s_point_clamp_sampler);
#endif

struct APVResources
{
    StructuredBuffer<int> index;

    Texture3D L0_L1Rx;

    Texture3D L1G_L1Ry;
    Texture3D L1B_L1Rz;
    Texture3D L2_0;
    Texture3D L2_1;
    Texture3D L2_2;
    Texture3D L2_3;
    Texture3D Validity;
};

struct APVSample
{
    float3 L0;
    float3 L1_R;
    float3 L1_G;
    float3 L1_B;
#ifdef PROBE_VOLUMES_L2
    float4 L2_R;
    float4 L2_G;
    float4 L2_B;
    float3 L2_C;
#endif

#define APV_SAMPLE_STATUS_INVALID -1
#define APV_SAMPLE_STATUS_ENCODED 0
#define APV_SAMPLE_STATUS_DECODED 1

    int status;

    // Note: at the moment this is called at the moment the struct is built, but it is kept as a separate step
    // as ideally should be called as far as possible from sample to allow for latency hiding.
    void Decode()
    {
        if (status == APV_SAMPLE_STATUS_ENCODED)
        {
            L1_R = DecodeSH(L0.r, L1_R);
            L1_G = DecodeSH(L0.g, L1_G);
            L1_B = DecodeSH(L0.b, L1_B);
#ifdef PROBE_VOLUMES_L2
            float4 outL2_C = float4(L2_C, 0.0f);
            DecodeSH_L2(L0, L2_R, L2_G, L2_B, outL2_C);
            L2_C = outL2_C.xyz;
#endif

            status = APV_SAMPLE_STATUS_DECODED;
        }
    }
};

// Resources required for APV
StructuredBuffer<int> _APVResIndex;
StructuredBuffer<uint3> _APVResCellIndices;

TEXTURE3D(_APVResL0_L1Rx);

TEXTURE3D(_APVResL1G_L1Ry);
TEXTURE3D(_APVResL1B_L1Rz);

TEXTURE3D(_APVResL2_0);
TEXTURE3D(_APVResL2_1);
TEXTURE3D(_APVResL2_2);
TEXTURE3D(_APVResL2_3);
TEXTURE3D(_APVResValidity);


// -------------------------------------------------------------
// Indexing functions
// -------------------------------------------------------------

bool LoadCellIndexMetaData(int cellFlatIdx, out int chunkIndex, out int stepSize, out int3 minRelativeIdx, out int3 maxRelativeIdx)
{
    bool cellIsLoaded = false;
    uint3 metaData = _APVResCellIndices[cellFlatIdx];

    if (metaData.x != 0xFFFFFFFF)
    {
        chunkIndex = metaData.x & 0x1FFFFFFF;
        stepSize = pow(3, (metaData.x >> 29) & 0x7);

        minRelativeIdx.x = metaData.y & 0x3FF;
        minRelativeIdx.y = (metaData.y >> 10) & 0x3FF;
        minRelativeIdx.z = (metaData.y >> 20) & 0x3FF;

        maxRelativeIdx.x = metaData.z & 0x3FF;
        maxRelativeIdx.y = (metaData.z >> 10) & 0x3FF;
        maxRelativeIdx.z = (metaData.z >> 20) & 0x3FF;
        cellIsLoaded = true;
    }
    else
    {
        chunkIndex = -1;
        stepSize = -1;
        minRelativeIdx = -1;
        maxRelativeIdx = -1;
    }

    return cellIsLoaded;
}

uint GetIndexData(APVResources apvRes, float3 posWS)
{
    int3 cellPos = floor(posWS / _CellInMeters);
    float3 topLeftCellWS = cellPos * _CellInMeters;

    // Make sure we start from 0
    cellPos -= (int3)_MinCellPosition;

    int flatIdx = cellPos.z * (_CellIndicesDim.x * _CellIndicesDim.y) + cellPos.y * _CellIndicesDim.x + cellPos.x;

    int stepSize = 0;
    int3 minRelativeIdx, maxRelativeIdx;
    int chunkIdx = -1;
    bool isValidBrick = true;
    int locationInPhysicalBuffer = 0;
    if (LoadCellIndexMetaData(flatIdx, chunkIdx, stepSize, minRelativeIdx, maxRelativeIdx))
    {
        float3 residualPosWS = posWS - topLeftCellWS;
        int3 localBrickIndex = floor(residualPosWS / (_MinBrickSize * stepSize));

        // Out of bounds.
        if (any(localBrickIndex < minRelativeIdx || localBrickIndex >= maxRelativeIdx))
        {
            isValidBrick = false;
        }

        int3 sizeOfValid = maxRelativeIdx - minRelativeIdx;
        // Relative to valid region
        int3 localRelativeIndexLoc = (localBrickIndex - minRelativeIdx);
        int flattenedLocationInCell = localRelativeIndexLoc.z * (sizeOfValid.x * sizeOfValid.y) + localRelativeIndexLoc.x * sizeOfValid.y + localRelativeIndexLoc.y;

        locationInPhysicalBuffer = chunkIdx * _IndexChunkSize + flattenedLocationInCell;

    }
    else
    {
        isValidBrick = false;
    }

    return isValidBrick ? apvRes.index[locationInPhysicalBuffer] : 0xffffffff;
}

// -------------------------------------------------------------
// Loading functions
// -------------------------------------------------------------
APVResources FillAPVResources()
{
    APVResources apvRes;
    apvRes.index = _APVResIndex;

    apvRes.L0_L1Rx = _APVResL0_L1Rx;

    apvRes.L1G_L1Ry = _APVResL1G_L1Ry;
    apvRes.L1B_L1Rz = _APVResL1B_L1Rz;

    apvRes.L2_0 = _APVResL2_0;
    apvRes.L2_1 = _APVResL2_1;
    apvRes.L2_2 = _APVResL2_2;
    apvRes.L2_3 = _APVResL2_3;
    apvRes.Validity = _APVResValidity;

    return apvRes;
}

uint3 GetSampleOffset(uint i)
{
    return uint3(i, i >> 1, i >> 2) & 1;
}
///////////////////////
//
// These weighting here can be easily easily optimized. Now I optimize for readability until we have something working.
//
//////////////////////

void GetTrilinearWeights(float3 uvw, out float weights[8])
{
    float3 texelLocFloat = uvw * _PoolDim;
    float3 texFrac = frac(texelLocFloat);
    float3 oneMinTexFrac = 1.0f - texFrac;

    for (uint i = 0; i < 8; ++i)
    {
        uint3 offset = GetSampleOffset(i);
        weights[i] =
            ((offset.x == 1) ? texFrac.x : oneMinTexFrac.x) *
            ((offset.y == 1) ? texFrac.y : oneMinTexFrac.y) *
            ((offset.z == 1) ? texFrac.z : oneMinTexFrac.z);
    }
}

void GetValidityBasedWeights(APVResources apvRes, float3 uvw, out float weights[8])
{
    uint3 loc = floor(uvw * _PoolDim - 0.5);
    for (uint i = 0; i < 8; ++i)
    {
        uint3 offset = GetSampleOffset(i);
        uint3 sampleLoc = loc + offset;
        float validity = LOAD_TEXTURE3D(apvRes.Validity, sampleLoc).x;

        // Process validity?
        weights[i] = pow(1.0 - validity, 8.0);
    }
}

void CombineWeightsWithTrilinear(float3 uvw, inout float weights[8])
{
    float _ProbeVolumeBilateralFilterWeight = _AntiLeakParams.y;

    float trilinearWeights[8];
    GetTrilinearWeights(uvw, trilinearWeights);

    float totalWeight = 0.0f;

    for (uint i = 0; i < 8; ++i)
    {
        weights[i] = max(0, lerp(trilinearWeights[i], trilinearWeights[i] * weights[i], _ProbeVolumeBilateralFilterWeight));
        totalWeight += weights[i];
    }

    totalWeight = max(totalWeight, 1e-3f);
    for (uint i = 0; i < 8; ++i)
    {
        weights[i] /= totalWeight;
    }
}


float3 ModifyUVWForLeak(APVResources apvRes, float3 uvw)
{
    if (_AntiLeakParams.x == 0)
        return uvw;

    float weights[8];
    GetValidityBasedWeights(apvRes, uvw, weights);
    CombineWeightsWithTrilinear(uvw, weights);
    if (_AntiLeakParams.x == 1)
    {
        GetTrilinearWeights(uvw, weights);
    }

    float3 newFrac = 0.0f;
    for (uint i = 0; i < 8; ++i)
    {
        uint3 o = GetSampleOffset(i);
        newFrac += (float3)o * weights[i];
    }
    float3 texelLocFloat = uvw * _PoolDim;
    texelLocFloat = texelLocFloat - frac(texelLocFloat) + newFrac;

    return texelLocFloat * rcp(_PoolDim);

    if (_AntiLeakParams.x > 1)
    {
        float3 texelLocFloat = uvw * _PoolDim;
        float3 texFrac = frac(texelLocFloat);


        float3 oneMinTexFrac = 1.0f - texFrac;


        float w000 = oneMinTexFrac.x * oneMinTexFrac.y * oneMinTexFrac.z;
        float w100 = texFrac.x * oneMinTexFrac.y * oneMinTexFrac.z;
        float w010 = oneMinTexFrac.x * texFrac.y * oneMinTexFrac.z;
        float w110 = texFrac.x * oneMinTexFrac.y * texFrac.z;

        float w001 = oneMinTexFrac.x * oneMinTexFrac.y * texFrac.z;
        float w101 = texFrac.x * oneMinTexFrac.y * texFrac.z;
        float w011 = oneMinTexFrac.x * texFrac.y * texFrac.z;
        float w111 = texFrac.x * texFrac.y * texFrac.z;


        float3 frac = 0;
        frac.x = w111 * rcp(w111 + w011);
        frac.y = w111 * rcp(w111 + w101);
        frac.z = (w111 * w111 + w011 * (w111 + w101) + w101 * w111) * rcp(w111);

        return (floor(texelLocFloat) + frac) * rcp(_PoolDim);

        return texelLocFloat * rcp(_PoolDim);
    }
    if (_AntiLeakParams.x > 0)
    {
        float3 texelLocFloat = uvw * _PoolDim;
        float3 texFrac = frac(texelLocFloat);

        float3 oneMinTexFrac = 1.0f - texFrac;

        ///// Trilinear weights
        float w000 = oneMinTexFrac.x * oneMinTexFrac.y * oneMinTexFrac.z;
        float w100 = texFrac.x * oneMinTexFrac.y * oneMinTexFrac.z;
        float w010 = oneMinTexFrac.x * texFrac.y * oneMinTexFrac.z;
        float w110 = texFrac.x * oneMinTexFrac.y * texFrac.z;

        float w001 = oneMinTexFrac.x * oneMinTexFrac.y * texFrac.z;
        float w101 = texFrac.x * oneMinTexFrac.y * texFrac.z;
        float w011 = oneMinTexFrac.x * texFrac.y * texFrac.z;
        float w111 = texFrac.x * texFrac.y * texFrac.z;

        //////////////////////

        // TODO_FCC: Add 0.5?
        float3 loc = floor(texelLocFloat);

        // TODO: If this is indeed what we go through, might be worth to precompute into a single texture (8 samples, in 64 bit we can have 64/8 = 8bit per channel)
       // float v LOAD_TEXTURE3D
        float _ProbeVolumeBilateralFilterWeightMin = 0;
        float v000 = LOAD_TEXTURE3D(apvRes.Validity, int3(loc.x + 0, loc.y + 0, loc.z + 0));
        float v100 = LOAD_TEXTURE3D(apvRes.Validity, int3(loc.x + 1, loc.y + 0, loc.z + 0));
        float v010 = LOAD_TEXTURE3D(apvRes.Validity, int3(loc.x + 0, loc.y + 1, loc.z + 0));
        float v110 = LOAD_TEXTURE3D(apvRes.Validity, int3(loc.x + 1, loc.y + 1, loc.z + 0));

        float v001 = LOAD_TEXTURE3D(apvRes.Validity, int3(loc.x + 0, loc.y + 0, loc.z + 1));
        float v101 = LOAD_TEXTURE3D(apvRes.Validity, int3(loc.x + 1, loc.y + 0, loc.z + 1));
        float v011 = LOAD_TEXTURE3D(apvRes.Validity, int3(loc.x + 0, loc.y + 1, loc.z + 1));
        float v111 = LOAD_TEXTURE3D(apvRes.Validity, int3(loc.x + 1, loc.y + 1, loc.z + 1));


        float _ProbeVolumeBilateralFilterWeight = _AntiLeakParams.y;

        float probeWeight000 = lerp(w000, w000 * v000, _ProbeVolumeBilateralFilterWeight);
        float probeWeight100 = lerp(w100, w100 * v100, _ProbeVolumeBilateralFilterWeight);
        float probeWeight010 = lerp(w010, w010 * v010, _ProbeVolumeBilateralFilterWeight);
        float probeWeight110 = lerp(w110, w110 * v110, _ProbeVolumeBilateralFilterWeight);

        float probeWeight001 = lerp(w001, w001 * v001, _ProbeVolumeBilateralFilterWeight);
        float probeWeight101 = lerp(w101, w101 * v101, _ProbeVolumeBilateralFilterWeight);
        float probeWeight011 = lerp(w011, w011 * v011, _ProbeVolumeBilateralFilterWeight);
        float probeWeight111 = lerp(w111, w111 * v111, _ProbeVolumeBilateralFilterWeight);

        float probeWeightTotal =
            probeWeight000 +
            probeWeight100 +
            probeWeight010 +
            probeWeight110 +
            probeWeight001 +
            probeWeight101 +
            probeWeight011 +
            probeWeight111;

        // Weights are enforced to be > 0.0 to guard against divide by zero.
        float probeWeightNormalization = 1.0 / probeWeightTotal;
        probeWeight000 *= probeWeightNormalization;
        probeWeight100 *= probeWeightNormalization;
        probeWeight010 *= probeWeightNormalization;
        probeWeight110 *= probeWeightNormalization;
        probeWeight001 *= probeWeightNormalization;
        probeWeight101 *= probeWeightNormalization;
        probeWeight011 *= probeWeightNormalization;
        probeWeight111 *= probeWeightNormalization;


        float3 probeVolumeTexel3DFrac =
            float3(0.0, 0.0, 0.0) * probeWeight000 +
            float3(1.0, 0.0, 0.0) * probeWeight100 +
            float3(0., 0., 1.) * probeWeight001 +
            float3(1., 0., 1) * probeWeight101 +
            float3(0., 1., 0.) * probeWeight010 +
            float3(1., 1., 0.) * probeWeight110 +
            float3(0., 1., 1.) * probeWeight011 +
            float3(1., 1., 1.) * probeWeight111;

        // Reconstruct frac pos.



        texelLocFloat = floor(texelLocFloat - 0.5) + probeVolumeTexel3DFrac;


        return texelLocFloat * rcp(_PoolDim);
    }

    return uvw;
}

bool TryToGetPoolUVWAndSubdiv(APVResources apvRes, float3 posWS, float3 normalWS, float3 viewDirWS, out float3 uvw, out uint subdiv)
{
    uvw = 0;
    // Note: we could instead early return when we know we'll have invalid UVs, but some bade code gen on Vulkan generates shader warnings if we do.
    bool hasValidUVW = true;

    float4 posWSForSample = float4(posWS + normalWS * _NormalBias
        + viewDirWS * _ViewBias, 1.0);

    uint3 poolDim = (uint3)_PoolDim;

    // resolve the index
    float3 posRS = posWSForSample.xyz / _MinBrickSize;
    uint packed_pool_idx = GetIndexData(apvRes, posWSForSample.xyz);

    // no valid brick loaded for this index, fallback to ambient probe
    if (packed_pool_idx == 0xffffffff)
    {
        hasValidUVW = false;
    }

    // unpack pool idx
    // size is encoded in the upper 4 bits
    subdiv = (packed_pool_idx >> 28) & 15;
    float  cellSize = pow(3.0, subdiv);
    uint   flattened_pool_idx = packed_pool_idx & ((1 << 28) - 1);
    uint3  pool_idx;
    pool_idx.z = flattened_pool_idx / (poolDim.x * poolDim.y);
    flattened_pool_idx -= pool_idx.z * (poolDim.x * poolDim.y);
    pool_idx.y = flattened_pool_idx / poolDim.x;
    pool_idx.x = flattened_pool_idx - (pool_idx.y * poolDim.x);
    uvw = ((float3) pool_idx + 0.5) / _PoolDim;

    // calculate uv offset and scale
    float3 offset = frac(posRS / (float)cellSize);  // [0;1] in brick space
    //offset    = clamp( offset, 0.25, 0.75 );      // [0.25;0.75] in brick space (is this actually necessary?)
    offset *= 3.0 / _PoolDim;                       // convert brick footprint to texels footprint in pool texel space
    uvw += offset;                                  // add the final offset

    if (any(_AntiLeakParams !=0))
        uvw = ModifyUVWForLeak(apvRes, uvw);

    return hasValidUVW;
}

bool TryToGetPoolUVWAndSubdiv_(APVResources apvRes, float3 posWS, float3 normalWS, float3 viewDirWS, out float3 uvw, out uint subdiv)
{
    uvw = 0;
    // Note: we could instead early return when we know we'll have invalid UVs, but some bade code gen on Vulkan generates shader warnings if we do.
    bool hasValidUVW = true;

    float4 posWSForSample = float4(posWS + normalWS * _NormalBias
        + viewDirWS * _ViewBias, 1.0);

    uint3 poolDim = (uint3)_PoolDim;

    // resolve the index
    float3 posRS = posWSForSample.xyz / _MinBrickSize;
    uint packed_pool_idx = GetIndexData(apvRes, posWSForSample.xyz);

    // no valid brick loaded for this index, fallback to ambient probe
    if (packed_pool_idx == 0xffffffff)
    {
        hasValidUVW = false;
    }

    // unpack pool idx
    // size is encoded in the upper 4 bits
    subdiv = (packed_pool_idx >> 28) & 15;
    float  cellSize = pow(3.0, subdiv);
    uint   flattened_pool_idx = packed_pool_idx & ((1 << 28) - 1);
    uint3  pool_idx;
    pool_idx.z = flattened_pool_idx / (poolDim.x * poolDim.y);
    flattened_pool_idx -= pool_idx.z * (poolDim.x * poolDim.y);
    pool_idx.y = flattened_pool_idx / poolDim.x;
    pool_idx.x = flattened_pool_idx - (pool_idx.y * poolDim.x);
    uvw = ((float3) pool_idx + 0.5) / _PoolDim;

    // calculate uv offset and scale
    float3 offset = frac(posRS / (float)cellSize);  // [0;1] in brick space
    offset    = clamp( offset, 0.25, 0.75 );      // [0.25;0.75] in brick space (is this actually necessary?)
    offset *= 3.0 / _PoolDim;                       // convert brick footprint to texels footprint in pool texel space
    uvw += offset;                                  // add the final offset

    //if (any(_AntiLeakParams !=0))
    //    uvw = ModifyUVWForLeak(apvRes, uvw);

    return hasValidUVW;
}

bool TryToGetPoolUVW(APVResources apvRes, float3 posWS, float3 normalWS, float3 viewDir, out float3 uvw)
{
    uint unusedSubdiv;
    return TryToGetPoolUVWAndSubdiv(apvRes, posWS, normalWS, viewDir, uvw, unusedSubdiv);
}

float3 GetManuallyFilteredL0(APVResources apvRes, float3 uvw)
{
    float3 total = 0.0f;
    float3 texCoordFloat = uvw * _PoolDim - .5f;
    int3 texCoordInt = texCoordFloat;
    float3 texFrac = frac(texCoordFloat);

    float _ProbeVolumeBilateralFilterWeight = _AntiLeakParams.y;

    total = 0;
    float3 oneMinTexFrac = 1.0f - texFrac;
    float totalWeight = 0;
    for (uint i = 0; i < 8; ++i)
    {
        uint3 offset = GetSampleOffset(i);
        float w =
            ((offset.x == 1) ? texFrac.x : oneMinTexFrac.x) *
            ((offset.y == 1) ? texFrac.y : oneMinTexFrac.y) *
            ((offset.z == 1) ? texFrac.z : oneMinTexFrac.z);

        float vW = LOAD_TEXTURE3D(apvRes.Validity, texCoordInt + offset).x;
        vW = all(_AntiLeakParams == 0) ? 1 : pow(1.0 - vW, 128);
        float finalW = lerp(w, w * vW, _ProbeVolumeBilateralFilterWeight);
        total += finalW * LOAD_TEXTURE3D(apvRes.L0_L1Rx, texCoordInt + offset).xyz;

        totalWeight += finalW;
    }

    totalWeight = max(1e-3f, totalWeight);

    return total / totalWeight;
}

APVSample SampleAPV(APVResources apvRes, float3 uvw)
{
    APVSample apvSample;
    float4 L0_L1Rx = SAMPLE_TEXTURE3D_LOD(apvRes.L0_L1Rx, s_linear_clamp_sampler, uvw, 0).rgba;
    float4 L1G_L1Ry = SAMPLE_TEXTURE3D_LOD(apvRes.L1G_L1Ry, s_linear_clamp_sampler, uvw, 0).rgba;
    float4 L1B_L1Rz = SAMPLE_TEXTURE3D_LOD(apvRes.L1B_L1Rz, s_linear_clamp_sampler, uvw, 0).rgba;

    apvSample.L0 = GetManuallyFilteredL0(apvRes, uvw);// L0_L1Rx.xyz;
    apvSample.L1_R = float3(L0_L1Rx.w, L1G_L1Ry.w, L1B_L1Rz.w);
    apvSample.L1_G = L1G_L1Ry.xyz;
    apvSample.L1_B = L1B_L1Rz.xyz;

#ifdef PROBE_VOLUMES_L2
    apvSample.L2_R = SAMPLE_TEXTURE3D_LOD(apvRes.L2_0, s_linear_clamp_sampler, uvw, 0).rgba;
    apvSample.L2_G = SAMPLE_TEXTURE3D_LOD(apvRes.L2_1, s_linear_clamp_sampler, uvw, 0).rgba;
    apvSample.L2_B = SAMPLE_TEXTURE3D_LOD(apvRes.L2_2, s_linear_clamp_sampler, uvw, 0).rgba;
    apvSample.L2_C = SAMPLE_TEXTURE3D_LOD(apvRes.L2_3, s_linear_clamp_sampler, uvw, 0).rgb;
#endif

    apvSample.status = APV_SAMPLE_STATUS_ENCODED;


    // TODO_FCC: TMP STUFF
    float validity = SAMPLE_TEXTURE3D_LOD(apvRes.Validity, s_linear_clamp_sampler, uvw, 0).r;
    apvSample.L0 += validity * 0.0001f;

    return apvSample;
}

APVSample SampleAPV(APVResources apvRes, float3 posWS, float3 biasNormalWS, float3 viewDir)
{
    APVSample outSample;

    float3 pool_uvw;
    if (TryToGetPoolUVW(apvRes, posWS, biasNormalWS, viewDir, pool_uvw))
    {
        outSample = SampleAPV(apvRes, pool_uvw);
    }
    else
    {
        ZERO_INITIALIZE(APVSample, outSample);
        outSample.status = APV_SAMPLE_STATUS_INVALID;
    }

    return outSample;
}


APVSample SampleAPV(float3 posWS, float3 biasNormalWS, float3 viewDir)
{
    APVResources apvRes = FillAPVResources();
    return SampleAPV(apvRes, posWS, biasNormalWS, viewDir);
}

///////////////////////
//
// test manual sampling
//
//////////////////////




// -------------------------------------------------------------
// Internal Evaluation functions (avoid usage in caller code outside this file)
// -------------------------------------------------------------
float3 EvaluateAPVL0(APVSample apvSample)
{
    return apvSample.L0;
}

void EvaluateAPVL1(APVSample apvSample, float3 N, out float3 diffuseLighting)
{
    diffuseLighting = SHEvalLinearL1(N, apvSample.L1_R, apvSample.L1_G, apvSample.L1_B);
}

#ifdef PROBE_VOLUMES_L2
void EvaluateAPVL1L2(APVSample apvSample, float3 N, out float3 diffuseLighting)
{
    EvaluateAPVL1(apvSample, N, diffuseLighting);
    diffuseLighting += SHEvalLinearL2(N, apvSample.L2_R, apvSample.L2_G, apvSample.L2_B, float4(apvSample.L2_C, 0.0f));
}
#endif


// -------------------------------------------------------------
// "Public" Evaluation functions, the one that callers outside this file should use
// -------------------------------------------------------------
void EvaluateAdaptiveProbeVolume(APVSample apvSample, float3 normalWS, float3 backNormalWS, out float3 bakeDiffuseLighting, out float3 backBakeDiffuseLighting)
{
    if (apvSample.status != APV_SAMPLE_STATUS_INVALID)
    {
        apvSample.Decode();
//
//#ifdef PROBE_VOLUMES_L1
//        EvaluateAPVL1(apvSample, normalWS, bakeDiffuseLighting);
//        EvaluateAPVL1(apvSample, backNormalWS, backBakeDiffuseLighting);
//#elif PROBE_VOLUMES_L2
//        EvaluateAPVL1L2(apvSample, normalWS, bakeDiffuseLighting);
//        EvaluateAPVL1L2(apvSample, backNormalWS, backBakeDiffuseLighting);
//#endif
//
        bakeDiffuseLighting = 0;
        backBakeDiffuseLighting = 0;
        bakeDiffuseLighting += apvSample.L0;
        backBakeDiffuseLighting += apvSample.L0;
    }
    else
    {
        // no valid brick, fallback to ambient probe
        bakeDiffuseLighting = EvaluateAmbientProbe(normalWS);
        backBakeDiffuseLighting = EvaluateAmbientProbe(backNormalWS);
    }
}

void EvaluateAdaptiveProbeVolume(in float3 posWS, in float3 normalWS, in float3 backNormalWS, in float3 reflDir, in float3 viewDir,
    in float2 positionSS, out float3 bakeDiffuseLighting, out float3 backBakeDiffuseLighting, out float3 lightingInReflDir)
{
    APVResources apvRes = FillAPVResources();

    if (_PVSamplingNoise > 0)
    {
        float noise1D_0 = (InterleavedGradientNoise(positionSS, 0) * 2.0f - 1.0f) * _PVSamplingNoise;
        posWS += noise1D_0;
    }

    APVSample apvSample = SampleAPV(posWS, normalWS, viewDir);

    if (apvSample.status != APV_SAMPLE_STATUS_INVALID)
    {
        apvSample.Decode();

//#ifdef PROBE_VOLUMES_L1
//        EvaluateAPVL1(apvSample, normalWS, bakeDiffuseLighting);
//        EvaluateAPVL1(apvSample, backNormalWS, backBakeDiffuseLighting);
//        EvaluateAPVL1(apvSample, reflDir, lightingInReflDir);
//#elif PROBE_VOLUMES_L2
//        EvaluateAPVL1L2(apvSample, normalWS, bakeDiffuseLighting);
//        EvaluateAPVL1L2(apvSample, backNormalWS, backBakeDiffuseLighting);
//        EvaluateAPVL1L2(apvSample, reflDir, lightingInReflDir);
//#endif

        bakeDiffuseLighting = apvSample.L0;
        backBakeDiffuseLighting = apvSample.L0;
        lightingInReflDir = apvSample.L0;
    }
    else
    {
        bakeDiffuseLighting = EvaluateAmbientProbe(normalWS);
        backBakeDiffuseLighting = EvaluateAmbientProbe(backNormalWS);
        lightingInReflDir = -1;
    }
}

void EvaluateAdaptiveProbeVolume(in float3 posWS, in float3 normalWS, in float3 backNormalWS, in float3 viewDir,
    in float2 positionSS, out float3 bakeDiffuseLighting, out float3 backBakeDiffuseLighting)
{
    bakeDiffuseLighting = float3(0.0, 0.0, 0.0);
    backBakeDiffuseLighting = float3(0.0, 0.0, 0.0);

    if (_PVSamplingNoise > 0)
    {
        float noise1D_0 = (InterleavedGradientNoise(positionSS, 0) * 2.0f - 1.0f) * _PVSamplingNoise;
        posWS += noise1D_0;
    }

    APVSample apvSample = SampleAPV(posWS, normalWS, viewDir);
    EvaluateAdaptiveProbeVolume(apvSample, normalWS, backNormalWS, bakeDiffuseLighting, backBakeDiffuseLighting);
}

void EvaluateAdaptiveProbeVolume(in float3 posWS, in float2 positionSS, out float3 bakeDiffuseLighting)
{
    APVResources apvRes = FillAPVResources();

    if (_PVSamplingNoise > 0)
    {
        float noise1D_0 = (InterleavedGradientNoise(positionSS, 0) * 2.0f - 1.0f) * _PVSamplingNoise;
        posWS += noise1D_0;
    }

    float3 uvw;
    if (TryToGetPoolUVW(apvRes, posWS, 0, 0, uvw))
    {
        bakeDiffuseLighting = SAMPLE_TEXTURE3D_LOD(apvRes.L0_L1Rx, s_linear_clamp_sampler, uvw, 0).rgb;
    }
    else
    {
        bakeDiffuseLighting = EvaluateAmbientProbe(0);
    }
}

// -------------------------------------------------------------
// Reflection Probe Normalization functions
// -------------------------------------------------------------
// Same idea as in Rendering of COD:IW [Drobot 2017]

float EvaluateReflectionProbeSH(float3 sampleDir, float4 reflProbeSHL0L1, float4 reflProbeSHL2_1, float reflProbeSHL2_2)
{
    float outFactor = 0;
    float L0 = reflProbeSHL0L1.x;
    float L1 = dot(reflProbeSHL0L1.yzw, sampleDir);

    outFactor = L0 + L1;

#ifdef PROBE_VOLUMES_L2

    // IMPORTANT: The encoding is unravelled C# side before being sent

    float4 vB = sampleDir.xyzz * sampleDir.yzzx;
    // First 4 coeff.
    float L2 = dot(reflProbeSHL2_1, vB);
    float vC = sampleDir.x * sampleDir.x - sampleDir.y * sampleDir.y;
    L2 += reflProbeSHL2_2 * vC;

    outFactor += L2;
#endif

    return outFactor;
}

float GetReflectionProbeNormalizationFactor(float3 lightingInReflDir, float3 sampleDir, float4 reflProbeSHL0L1, float4 reflProbeSHL2_1, float reflProbeSHL2_2)
{
    float refProbeNormalization = EvaluateReflectionProbeSH(sampleDir, reflProbeSHL0L1, reflProbeSHL2_1, reflProbeSHL2_2);
    float localNormalization = Luminance(lightingInReflDir);

    return SafeDiv(localNormalization, refProbeNormalization);
}

#endif // __PROBEVOLUME_HLSL__
