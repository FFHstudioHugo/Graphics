using System;
using System.ComponentModel;
using System.Collections.Generic;
using UnityEditor;
using UnityEngine.Serialization;

namespace UnityEngine.Rendering.Universal
{
    /// <summary>
    /// Universal Render Pipeline's Global Settings.
    /// Global settings are unique per Render Pipeline type. In URP, Global Settings contain:
    /// - light layer names
    /// </summary>
    [URPHelpURL("urp-global-settings")]
    [DisplayInfo(name = "URP Global Settings Asset", order = CoreUtils.Sections.section4 + 2)]
    [SupportedOnRenderPipeline(typeof(UniversalRenderPipelineAsset))]
    [DisplayName("URP")]
    partial class UniversalRenderPipelineGlobalSettings : RenderPipelineGlobalSettings<UniversalRenderPipelineGlobalSettings, UniversalRenderPipeline>
    {
        [SerializeField] RenderPipelineGraphicsSettingsContainer m_Settings = new();
        protected override List<IRenderPipelineGraphicsSettings> settingsList => m_Settings.settingsList;

        #region Version system

        internal bool IsAtLastVersion() => k_LastVersion == m_AssetVersion;

        internal const int k_LastVersion = 6;

#pragma warning disable CS0414
        [SerializeField][FormerlySerializedAs("k_AssetVersion")]
        internal int m_AssetVersion = k_LastVersion;
#pragma warning restore CS0414

#if UNITY_EDITOR
        public static void UpgradeAsset(int assetInstanceID)
        {
            if (EditorUtility.InstanceIDToObject(assetInstanceID) is not UniversalRenderPipelineGlobalSettings asset)
                    return;

            int assetVersionBeforeUpgrade = asset.m_AssetVersion;

            if (asset.m_AssetVersion < 2)
            {
#pragma warning disable 618 // Obsolete warning
                // Renamed supportRuntimeDebugDisplay => m_StripDebugVariants, which results in inverted logic
                asset.m_StripDebugVariants = !asset.supportRuntimeDebugDisplay;
                asset.m_AssetVersion = 2;
#pragma warning restore 618 // Obsolete warning

                // For old test projects lets keep post processing stripping enabled, as huge chance they did not used runtime profile creating
#if UNITY_INCLUDE_TESTS
#pragma warning disable 618 // Obsolete warning
                asset.m_StripUnusedPostProcessingVariants = true;
#pragma warning restore 618 // Obsolete warning
#endif
            }

            if (asset.m_AssetVersion < 3)
            {
                int index = 0;
                asset.m_RenderingLayerNames = new string[8];
#pragma warning disable 618 // Obsolete warning
                asset.m_RenderingLayerNames[index++] = asset.lightLayerName0;
                asset.m_RenderingLayerNames[index++] = asset.lightLayerName1;
                asset.m_RenderingLayerNames[index++] = asset.lightLayerName2;
                asset.m_RenderingLayerNames[index++] = asset.lightLayerName3;
                asset.m_RenderingLayerNames[index++] = asset.lightLayerName4;
                asset.m_RenderingLayerNames[index++] = asset.lightLayerName5;
                asset.m_RenderingLayerNames[index++] = asset.lightLayerName6;
                asset.m_RenderingLayerNames[index++] = asset.lightLayerName7;
#pragma warning restore 618 // Obsolete warning
                asset.m_AssetVersion = 3;
                asset.UpdateRenderingLayerNames();
            }

            if (asset.m_AssetVersion < 4)
            {
#pragma warning disable 618 // Type or member is obsolete
                asset.m_ShaderStrippingSetting.exportShaderVariants                 = asset.m_ExportShaderVariants;
                asset.m_ShaderStrippingSetting.shaderVariantLogLevel                = asset.m_ShaderVariantLogLevel;
                asset.m_ShaderStrippingSetting.stripRuntimeDebugShaders             = asset.m_StripDebugVariants;
                asset.m_URPShaderStrippingSetting.stripScreenCoordOverrideVariants  = asset.m_StripScreenCoordOverrideVariants;
                asset.m_URPShaderStrippingSetting.stripUnusedPostProcessingVariants = asset.m_StripUnusedPostProcessingVariants;
                asset.m_URPShaderStrippingSetting.stripUnusedVariants               = asset.m_StripUnusedVariants;
#pragma warning restore 618

                asset.m_AssetVersion = 4;
            }

            if (asset.m_AssetVersion < 5)
            {
#pragma warning disable 618 // Type or member is obsolete
                asset.m_ObsoleteDefaultVolumeProfile = asset.GetOrCreateDefaultVolumeProfile(asset.m_ObsoleteDefaultVolumeProfile);
#pragma warning restore 618 // Type or member is obsolete
                asset.m_AssetVersion = 5;
            }

            if (asset.m_AssetVersion < 6)
            {
                MigrateToRenderPipelineGraphicsSettings(asset);
                asset.m_AssetVersion = 6;
            }

            // If the asset version has changed, means that a migration step has been executed
            if (assetVersionBeforeUpgrade != asset.m_AssetVersion)
                EditorUtility.SetDirty(asset);
        }

        public static void MigrateToRenderPipelineGraphicsSettings(UniversalRenderPipelineGlobalSettings data)
        {
            MigrateToShaderStrippingSetting(data);
            MigrateToURPShaderStrippingSetting(data);
            MigrateDefaultVolumeProfile(data);
            MigrateToRenderGraphSettings(data);
        }

        private static T GetOrCreateGraphicsSettings<T>(UniversalRenderPipelineGlobalSettings data)
            where T : class, IRenderPipelineGraphicsSettings, new()
        {
            T settings;

            if (data.TryGet(typeof(T), out var baseSettings))
            {
                settings = baseSettings as T;
            }
            else
            {
                settings = new T();
                data.Add(settings);
            }

            return settings;
        }

        static void MigrateToShaderStrippingSetting(UniversalRenderPipelineGlobalSettings data)
        {
            var shaderStrippingSetting = GetOrCreateGraphicsSettings<ShaderStrippingSetting>(data);

#pragma warning disable 618 // Type or member is obsolete
            shaderStrippingSetting.shaderVariantLogLevel    = data.m_ShaderStrippingSetting.shaderVariantLogLevel;
            shaderStrippingSetting.exportShaderVariants     = data.m_ShaderStrippingSetting.exportShaderVariants;
            shaderStrippingSetting.stripRuntimeDebugShaders = data.m_ShaderStrippingSetting.stripRuntimeDebugShaders;
#pragma warning restore 618
        }

        static void MigrateToRenderGraphSettings(UniversalRenderPipelineGlobalSettings data)
        {
            var rgSettings = GetOrCreateGraphicsSettings<RenderGraphSettings>(data);

#pragma warning disable 618 // Type or member is obsolete
            rgSettings.useRenderGraph = data.m_EnableRenderGraph;
#pragma warning restore 618
        }

        static void MigrateToURPShaderStrippingSetting(UniversalRenderPipelineGlobalSettings data)
        {
            var urpShaderStrippingSetting = GetOrCreateGraphicsSettings<URPShaderStrippingSetting>(data);

#pragma warning disable 618 // Type or member is obsolete
            urpShaderStrippingSetting.stripScreenCoordOverrideVariants  = data.m_URPShaderStrippingSetting.stripScreenCoordOverrideVariants;
            urpShaderStrippingSetting.stripUnusedPostProcessingVariants = data.m_URPShaderStrippingSetting.stripUnusedPostProcessingVariants;
            urpShaderStrippingSetting.stripUnusedVariants               = data.m_URPShaderStrippingSetting.stripUnusedVariants;
#pragma warning restore 618
        }

        static void MigrateDefaultVolumeProfile(UniversalRenderPipelineGlobalSettings data)
        {
#pragma warning disable 618 // Type or member is obsolete
            var defaultVolumeProfileSettings = GetOrCreateGraphicsSettings<URPDefaultVolumeProfileSettings>(data);
            defaultVolumeProfileSettings.volumeProfile = data.m_ObsoleteDefaultVolumeProfile;
            data.m_ObsoleteDefaultVolumeProfile = null; // Discard old reference after it is migrated
#pragma warning restore 618 // Type or member is obsolete
        }

#endif // #if UNITY_EDITOR

        #endregion

        /// <summary>Default name when creating an URP Global Settings asset.</summary>
        public const string defaultAssetName = "UniversalRenderPipelineGlobalSettings";

#if UNITY_EDITOR
        internal static string defaultPath => $"Assets/{defaultAssetName}.asset";

        //Making sure there is at least one UniversalRenderPipelineGlobalSettings instance in the project
        internal static UniversalRenderPipelineGlobalSettings Ensure(bool canCreateNewAsset = true)
        {
            UniversalRenderPipelineGlobalSettings currentInstance = GraphicsSettings.
                GetSettingsForRenderPipeline<UniversalRenderPipeline>() as UniversalRenderPipelineGlobalSettings;

            if (RenderPipelineGlobalSettingsUtils.TryEnsure<UniversalRenderPipelineGlobalSettings, UniversalRenderPipeline>(ref currentInstance, defaultPath, canCreateNewAsset))
            {
                if (currentInstance != null && currentInstance.m_AssetVersion != k_LastVersion)
                {
                    UpgradeAsset(currentInstance.GetInstanceID());
                    AssetDatabase.SaveAssetIfDirty(currentInstance);
                }

                return currentInstance;
            }

            return null;
        }

        public override void Initialize(RenderPipelineGlobalSettings source = null)
        {
            if (source is UniversalRenderPipelineGlobalSettings globalSettingsSource)
                Array.Copy(globalSettingsSource.m_RenderingLayerNames, m_RenderingLayerNames, globalSettingsSource.m_RenderingLayerNames.Length);

            // Note: RenderPipelineGraphicsSettings are not populated yet when the global settings asset is being
            // initialized, so create the setting before using it
            var defaultVolumeProfileSettings = GetOrCreateGraphicsSettings<URPDefaultVolumeProfileSettings>(this);
            defaultVolumeProfileSettings.volumeProfile = GetOrCreateDefaultVolumeProfile(defaultVolumeProfileSettings.volumeProfile);
        }

#endif // #if UNITY_EDITOR

        /// <inheritdoc/>
        public override void Reset()
        {
            base.Reset();
            UpdateRenderingLayerNames();
        }

        internal VolumeProfile GetOrCreateDefaultVolumeProfile(VolumeProfile defaultVolumeProfile)
        {
#if UNITY_EDITOR
            if (defaultVolumeProfile == null || defaultVolumeProfile.Equals(null))
            {
                const string k_DefaultVolumeProfileName = "DefaultVolumeProfile";
                const string k_DefaultVolumeProfilePath = "Assets/" + k_DefaultVolumeProfileName + ".asset";

                defaultVolumeProfile = CreateInstance<VolumeProfile>();
                Debug.Assert(defaultVolumeProfile);

                defaultVolumeProfile.name = k_DefaultVolumeProfileName;
                AssetDatabase.CreateAsset(defaultVolumeProfile, k_DefaultVolumeProfilePath);

                AssetDatabase.SaveAssetIfDirty(defaultVolumeProfile);
                AssetDatabase.Refresh();

                if (VolumeManager.instance.isInitialized && RenderPipelineManager.currentPipeline is UniversalRenderPipeline)
                    VolumeManager.instance.SetGlobalDefaultProfile(defaultVolumeProfile);
            }
#endif
            return defaultVolumeProfile;
        }

        [SerializeField, FormerlySerializedAs("m_DefaultVolumeProfile")]
        [Obsolete("Kept For Migration. #from(2023.3)")]
        internal VolumeProfile m_ObsoleteDefaultVolumeProfile;

        [SerializeField]
        string[] m_RenderingLayerNames = new string[] { "Default" };
        string[] renderingLayerNames
        {
            get
            {
                if (m_RenderingLayerNames == null)
                    UpdateRenderingLayerNames();
                return m_RenderingLayerNames;
            }
        }
        [System.NonSerialized]
        string[] m_PrefixedRenderingLayerNames;
        string[] prefixedRenderingLayerNames
        {
            get
            {
                if (m_PrefixedRenderingLayerNames == null)
                    UpdateRenderingLayerNames();
                return m_PrefixedRenderingLayerNames;
            }
        }
        /// <summary>Names used for display of rendering layer masks.</summary>
        public string[] renderingLayerMaskNames => renderingLayerNames;
        /// <summary>Names used for display of rendering layer masks with a prefix.</summary>
        public string[] prefixedRenderingLayerMaskNames => prefixedRenderingLayerNames;

        [SerializeField]
        uint m_ValidRenderingLayers;
        /// <summary>Valid rendering layers that can be used by graphics. </summary>
        public uint validRenderingLayers {
            get
            {
                if (m_PrefixedRenderingLayerNames == null)
                    UpdateRenderingLayerNames();

                return m_ValidRenderingLayers;
            }
        }

        /// <summary>Regenerate Rendering Layer names and their prefixed versions.</summary>
        internal void UpdateRenderingLayerNames()
        {
            // Update prefixed
            if (m_PrefixedRenderingLayerNames == null)
                m_PrefixedRenderingLayerNames = new string[32];
            for (int i = 0; i < m_PrefixedRenderingLayerNames.Length; ++i)
            {
                uint renderingLayer = (uint)(1 << i);

                m_ValidRenderingLayers = i < m_RenderingLayerNames.Length ? (m_ValidRenderingLayers | renderingLayer) : (m_ValidRenderingLayers & ~renderingLayer);
                m_PrefixedRenderingLayerNames[i] = i < m_RenderingLayerNames.Length ? m_RenderingLayerNames[i] : $"Unused Layer {i}";
            }

            // Update decals
            DecalProjector.UpdateAllDecalProperties();
        }

        /// <summary>
        /// Names used for display of light layers with Layer's index as prefix.
        /// For example: "0: Light Layer Default"
        /// </summary>
        [Obsolete("This is obsolete, please use prefixedRenderingLayerMaskNames instead.", true)]
        public string[] prefixedLightLayerNames => new string[0];


        #region Light Layer Names [3D]

        /// <summary>Name for light layer 0.</summary>
        [Obsolete("This is obsolete, please use renderingLayerMaskNames instead.", false)]
        public string lightLayerName0;
        /// <summary>Name for light layer 1.</summary>
        [Obsolete("This is obsolete, please use renderingLayerMaskNames instead.", false)]
        public string lightLayerName1;
        /// <summary>Name for light layer 2.</summary>
        [Obsolete("This is obsolete, please use renderingLayerMaskNames instead.", false)]
        public string lightLayerName2;
        /// <summary>Name for light layer 3.</summary>
        [Obsolete("This is obsolete, please use renderingLayerMaskNames instead.", false)]
        public string lightLayerName3;
        /// <summary>Name for light layer 4.</summary>
        [Obsolete("This is obsolete, please use renderingLayerMaskNames instead.", false)]
        public string lightLayerName4;
        /// <summary>Name for light layer 5.</summary>
        [Obsolete("This is obsolete, please use renderingLayerMaskNames instead.", false)]
        public string lightLayerName5;
        /// <summary>Name for light layer 6.</summary>
        [Obsolete("This is obsolete, please use renderingLayerMaskNames instead.", false)]
        public string lightLayerName6;
        /// <summary>Name for light layer 7.</summary>
        [Obsolete("This is obsolete, please use renderingLayerNames instead.", false)]
        public string lightLayerName7;

        /// <summary>
        /// Names used for display of light layers.
        /// </summary>
        [Obsolete("This is obsolete, please use renderingLayerMaskNames instead.", false)]
        public string[] lightLayerNames => new string[0];

        internal void ResetRenderingLayerNames()
        {
            m_RenderingLayerNames = new string[] { "Default"};
        }

        #endregion

#pragma warning disable 618
#pragma warning disable 612
        #region APV
        // This is temporarily here until we have a core place to put it shared between pipelines.
        [SerializeField]
        internal ProbeVolumeSceneData apvScenesData;

        internal ProbeVolumeSceneData GetOrCreateAPVSceneData()
        {
            if (apvScenesData == null)
                apvScenesData = new ProbeVolumeSceneData(this);

            apvScenesData.SetParentObject(this);
            return apvScenesData;
        }
#pragma warning restore 612
#pragma warning restore 618

        #endregion
    }
}
