using UnityEngine.TestTools.Graphics;

namespace UnityEngine.VFX.Test
{
    public class VFXGraphicsTestSettings : GraphicsTestSettings
    {
        static public readonly int defaultCaptureFrameRate = 20;
        static public readonly float defaultFixedTimeStepScale = 1.0f;
        static public readonly float defaultCapturePeriod = 1.0f / (float)defaultCaptureFrameRate;
        static public readonly float defaultSimulateTime = 6.0f - defaultCapturePeriod;
        static public readonly float defaultAverageCorrectnessThreshold = 5e-4f;

        public int captureFrameRate = defaultCaptureFrameRate;
        public float fixedTimeStepScale = defaultFixedTimeStepScale;
        public float simulateTime = defaultSimulateTime;

        public bool xrCompatible = true;

        VFXGraphicsTestSettings()
        {
            base.ImageComparisonSettings.AverageCorrectnessThreshold = defaultAverageCorrectnessThreshold;
        }
    }
}
