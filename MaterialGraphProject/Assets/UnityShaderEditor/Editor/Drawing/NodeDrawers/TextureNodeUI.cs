using System;
using UnityEditor.Graphing;
using UnityEditor.Graphing.Drawing;
using UnityEngine;
using UnityEngine.MaterialGraph;

namespace UnityEditor.MaterialGraph
{
    [CustomNodeUI(typeof(TextureNode))]
    public class TextureNodeUI : AbstractMaterialNodeUI
    {   
        public override float GetNodeUiHeight(float width)
        {
            return base.GetNodeUiHeight(width) + EditorGUIUtility.singleLineHeight * 2;
        }

        private string[] m_TextureTypeNames;
        private string[] textureTypeNames 
        {
            get
            {
                if (m_TextureTypeNames == null)
                    m_TextureTypeNames = Enum.GetNames(typeof(TextureType));
                return m_TextureTypeNames;
            }
        }

        public override GUIModificationType Render(Rect area)
        {
            var node = m_Node as TextureNode;
            if (node == null)
                return base.Render(area);

            if (m_Node == null)
                return GUIModificationType.None;

            EditorGUI.BeginChangeCheck();
            node.defaultTexture = EditorGUI.MiniThumbnailObjectField(new Rect(area.x, area.y, area.width, EditorGUIUtility.singleLineHeight), new GUIContent("Texture"), node.defaultTexture, typeof(Texture2D), null) as Texture2D;
            var texureChanged = EditorGUI.EndChangeCheck();
            area.y += EditorGUIUtility.singleLineHeight;
            area.height -= EditorGUIUtility.singleLineHeight;

            EditorGUI.BeginChangeCheck();
            node.textureType = (TextureType)EditorGUI.Popup(new Rect(area.x, area.y, area.width, EditorGUIUtility.singleLineHeight), (int)node.textureType, textureTypeNames, EditorStyles.popup);
            var typeChanged = EditorGUI.EndChangeCheck();
            
            var toReturn = GUIModificationType.None;
            if (typeChanged)
            {
                toReturn |= GUIModificationType.DataChanged;
            }

            if (texureChanged)
                toReturn |= GUIModificationType.Repaint;
            
            area.y += EditorGUIUtility.singleLineHeight;
            area.height -= EditorGUIUtility.singleLineHeight;
            toReturn |= base.Render(area);
            return toReturn;
        }
    }
}
