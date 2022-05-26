using System;
using System.Collections.Generic;
using System.Linq;
using Unity.Collections;
using Unity.Collections.LowLevel.Unsafe;
using UnityEngine.Experimental.Rendering;

namespace UnityEngine.Rendering.HighDefinition
{
    partial class HDDynamicShadowAtlas : HDShadowAtlas
    {
        NativeList<HDShadowResolutionRequestHandle>    m_ShadowResolutionRequests;
        NativeList<HDShadowRequestHandle>              m_MixedRequestsPendingBlits;

        float m_RcpScaleFactor = 1;
        HDShadowResolutionRequestHandle[] m_SortedRequestsCache;

        public HDDynamicShadowAtlas(HDShadowAtlasInitParameters atlaInitParams)
            : base(atlaInitParams)
        {
            m_SortedRequestsCache = new HDShadowResolutionRequestHandle[Mathf.CeilToInt(atlaInitParams.maxShadowRequests)];
        }

        public override void InitAtlas(HDShadowAtlasInitParameters initParams)
        {
            if (!m_ShadowResolutionRequests.IsCreated)
                m_ShadowResolutionRequests = new NativeList<HDShadowResolutionRequestHandle>(Allocator.Persistent);
            else
                m_ShadowResolutionRequests.Clear();

            if (!m_MixedRequestsPendingBlits.IsCreated)
                m_MixedRequestsPendingBlits = new NativeList<HDShadowRequestHandle>(Allocator.Persistent);
            else
                m_MixedRequestsPendingBlits.Clear();

            base.InitAtlas(initParams);
        }

        internal void ReserveResolution(HDShadowResolutionRequestHandle shadowRequest)
        {
            m_ShadowResolutionRequests.Add(shadowRequest);
        }

        // Stable (unlike List.Sort) sorting algorithm which, unlike Linq's, doesn't use JIT (lol).
        // Sorts in place. Very efficient (O(n)) for already sorted data.
        unsafe void InsertionSort(HDShadowResolutionRequestHandle[] array, NativeList<HDShadowResolutionRequest> requestStorage, int startIndex, int lastIndex)
        {
            ref UnsafeList<HDShadowResolutionRequest> resolutionRequests = ref *shadowResolutionRequestStorage.GetUnsafeList();

            int i = startIndex + 1;

            while (i < lastIndex)
            {
                var currHandle = array[i];
                ref var curr = ref resolutionRequests.ElementAt(currHandle.index);

                int j = i - 1;

                // Sort in descending order.
                while ((j >= 0) && ((curr.resolution.x > resolutionRequests.ElementAt(array[j].index).resolution.x) ||
                                    (curr.resolution.y > resolutionRequests.ElementAt(array[j].index).resolution.y)))
                {
                    array[j + 1] = array[j];
                    j--;
                }

                array[j + 1] = currHandle;
                i++;
            }
        }

        private unsafe bool AtlasLayout(bool allowResize, HDShadowResolutionRequestHandle[] fullShadowList, NativeList<HDShadowResolutionRequest> resolutionRequestStorage, int requestsCount)
        {
            ref UnsafeList<HDShadowResolutionRequest> resolutionRequests = ref *shadowResolutionRequestStorage.GetUnsafeList();

            float curX = 0, curY = 0, curH = 0, xMax = width, yMax = height;
            m_RcpScaleFactor = 1;
            for (int i = 0; i < requestsCount; ++i)
            {
                ref var shadowRequest = ref resolutionRequests.ElementAt(fullShadowList[i].index);
                // shadow atlas layouting
                Rect viewport = new Rect(Vector2.zero, shadowRequest.resolution);
                curH = Mathf.Max(curH, viewport.height);

                if (curX + viewport.width > xMax)
                {
                    curX = 0;
                    curY += curH;
                    curH = viewport.height;
                }
                if (curY + curH > yMax)
                {
                    if (allowResize)
                    {
                        LayoutResize();
                        return true;
                    }

                    return false;
                }
                viewport.x = curX;
                viewport.y = curY;
                shadowRequest.dynamicAtlasViewport = viewport;
                shadowRequest.resolution = viewport.size;
                curX += viewport.width;
            }

            return true;
        }

        internal bool Layout(bool allowResize = true)
        {
            int n = m_ShadowResolutionRequests.Length;
            int i = 0;
            for (; i < m_ShadowResolutionRequests.Length; ++i)
            {
                m_SortedRequestsCache[i] = m_ShadowResolutionRequests[i];
            }

            InsertionSort(m_SortedRequestsCache, shadowResolutionRequestStorage, 0, i);

            return AtlasLayout(allowResize, m_SortedRequestsCache, shadowResolutionRequestStorage, requestsCount: i);
        }

        unsafe void LayoutResize()
        {
            int index = 0;
            float currentX = 0;
            float currentY = 0;
            float currentMaxY = 0;
            float currentMaxX = 0;

            ref UnsafeList<HDShadowResolutionRequest> resolutionRequests = ref *shadowResolutionRequestStorage.GetUnsafeList();

            // Place shadows in a square shape
            while (index < m_ShadowResolutionRequests.Length)
            {
                float y = 0;
                float currentMaxXCache = currentMaxX;
                do
                {
                    var resolutionRequestHandle = m_ShadowResolutionRequests[index];
                    ref var resolutionRequest = ref resolutionRequests.ElementAt(resolutionRequestHandle.index);
                    Rect r = new Rect(Vector2.zero, resolutionRequest.resolution);
                    r.x = currentMaxX;
                    r.y = y;
                    y += r.height;
                    currentY = Mathf.Max(currentY, y);
                    currentMaxXCache = Mathf.Max(currentMaxXCache, currentMaxX + r.width);
                    resolutionRequest.dynamicAtlasViewport = r;
                    index++;
                } while (y < currentMaxY && index < m_ShadowResolutionRequests.Length);
                currentMaxY = Mathf.Max(currentMaxY, currentY);
                currentMaxX = currentMaxXCache;
                if (index >= m_ShadowResolutionRequests.Length)
                    continue;
                float x = 0;
                float currentMaxYCache = currentMaxY;
                do
                {
                    var resolutionRequestHandle = m_ShadowResolutionRequests[index];
                    ref var resolutionRequest = ref resolutionRequests.ElementAt(resolutionRequestHandle.index);
                    Rect r = new Rect(Vector2.zero, resolutionRequest.resolution);
                    r.x = x;
                    r.y = currentMaxY;
                    x += r.width;
                    currentX = Mathf.Max(currentX, x);
                    currentMaxYCache = Mathf.Max(currentMaxYCache, currentMaxY + r.height);
                    resolutionRequest.dynamicAtlasViewport = r;
                    index++;
                } while (x < currentMaxX && index < m_ShadowResolutionRequests.Length);
                currentMaxX = Mathf.Max(currentMaxX, currentX);
                currentMaxY = currentMaxYCache;
            }

            float maxResolution = Math.Max(currentMaxX, currentMaxY);
            Vector4 scale = new Vector4(width / maxResolution, height / maxResolution, width / maxResolution, height / maxResolution);
            m_RcpScaleFactor = Mathf.Min(scale.x, scale.y);

            // Scale down every shadow rects to fit with the current atlas size
            foreach (var handle in m_ShadowResolutionRequests)
            {
                ref var r = ref resolutionRequests.ElementAt(handle.index);
                Vector4 s = new Vector4(r.dynamicAtlasViewport.x, r.dynamicAtlasViewport.y, r.dynamicAtlasViewport.width, r.dynamicAtlasViewport.height);
                Vector4 reScaled = Vector4.Scale(s, scale);

                r.dynamicAtlasViewport = new Rect(reScaled.x, reScaled.y, reScaled.z, reScaled.w);
                r.resolution = r.dynamicAtlasViewport.size;
            }
        }

        public void DisplayAtlas(RTHandle atlasTexture, CommandBuffer cmd, Material debugMaterial, Rect atlasViewport, float screenX, float screenY, float screenSizeX, float screenSizeY, float minValue, float maxValue, MaterialPropertyBlock mpb)
        {
            base.DisplayAtlas(atlasTexture, cmd, debugMaterial, atlasViewport, screenX, screenY, screenSizeX, screenSizeY, minValue, maxValue, mpb, m_RcpScaleFactor);
        }

        public void AddRequestToPendingBlitFromCache(HDShadowRequestHandle request, bool isMixedCache)
        {
            if (isMixedCache)
                m_MixedRequestsPendingBlits.Add(request);
        }

        public static void AddRequestToPendingBlitFromCache(ref HDDynamicShadowAtlasUnmanaged shadowAtlas, HDShadowRequestHandle request, bool isMixedCache)
        {
            if (isMixedCache)
                shadowAtlas.mixedRequestsPendingBlits.Add(request);
        }

        public void ClearPendingBlitsRequests()
        {
            m_MixedRequestsPendingBlits.Clear();
        }

        public bool HasPendingBlitsRequests()
        {
            return m_MixedRequestsPendingBlits.Length > 0;
        }

        internal void GetUnmanageDataForShadowRequestJobs(ref HDDynamicShadowAtlasUnmanaged unmanagedData)
        {
            unmanagedData.shadowRequests = m_ShadowRequests;
            unmanagedData.shadowResolutionRequests = m_ShadowResolutionRequests;
            unmanagedData.mixedRequestsPendingBlits = m_MixedRequestsPendingBlits;
        }

        internal struct ShadowBlitParameters
        {
            public NativeList<HDShadowRequestHandle> requestsWaitingBlits;
            public Material              blitMaterial;
            public MaterialPropertyBlock blitMaterialPropertyBlock;
            public Vector2Int            cachedShadowAtlasSize;

        }

        internal ShadowBlitParameters PrepareShadowBlitParameters(HDCachedShadowAtlas cachedAtlas, Material blitMaterial, MaterialPropertyBlock blitMpb)
        {
            ShadowBlitParameters parameters = new ShadowBlitParameters();
            parameters.requestsWaitingBlits = m_MixedRequestsPendingBlits;
            parameters.blitMaterial = blitMaterial;
            parameters.blitMaterialPropertyBlock = blitMpb;
            parameters.cachedShadowAtlasSize = new Vector2Int(cachedAtlas.width, cachedAtlas.height);
            return parameters;
        }

        static internal unsafe void BlitCachedIntoAtlas(in ShadowBlitParameters parameters, RTHandle dynamicTexture, RTHandle cachedTexture, CommandBuffer cmd)
        {
            NativeList<HDShadowRequest> requestStorage = HDLightRenderDatabase.instance.hdShadowRequestStorage;
            ref UnsafeList<HDShadowRequest> requestStorageUnsafe = ref *requestStorage.GetUnsafeList();
            foreach (var requestHandle in parameters.requestsWaitingBlits)
            {
                ref var request = ref requestStorageUnsafe.ElementAt(requestHandle.storageIndexForShadowRequest);
                cmd.SetRenderTarget(dynamicTexture);

                cmd.SetViewport(request.dynamicAtlasViewport);

                Vector4 sourceScaleBias = new Vector4(request.cachedAtlasViewport.width / parameters.cachedShadowAtlasSize.x,
                    request.cachedAtlasViewport.height / parameters.cachedShadowAtlasSize.y,
                    request.cachedAtlasViewport.x / parameters.cachedShadowAtlasSize.x,
                    request.cachedAtlasViewport.y / parameters.cachedShadowAtlasSize.y);

                parameters.blitMaterialPropertyBlock.SetTexture(HDShaderIDs._CachedShadowmapAtlas, cachedTexture);
                parameters.blitMaterialPropertyBlock.SetVector(HDShaderIDs._BlitScaleBias, sourceScaleBias);
                CoreUtils.DrawFullScreen(cmd, parameters.blitMaterial, parameters.blitMaterialPropertyBlock, 0);
            }

            parameters.requestsWaitingBlits.Clear();
        }

        public override void Clear()
        {
            base.Clear();
            m_ShadowResolutionRequests.Clear();
            m_MixedRequestsPendingBlits.Clear();
        }

        public override void Dispose()
        {
            if (m_ShadowResolutionRequests.IsCreated)
            {
                m_ShadowResolutionRequests.Dispose();
                m_ShadowResolutionRequests = default;
            }

            if (m_MixedRequestsPendingBlits.IsCreated)
            {
                m_MixedRequestsPendingBlits.Dispose();
                m_MixedRequestsPendingBlits = default;
            }

            base.Dispose();
        }
    }
}

