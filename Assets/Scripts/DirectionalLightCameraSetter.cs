using UnityEngine;

[RequireComponent(typeof(Light))]
[ExecuteAlways]
public class DirectionalLightCameraSetter : MonoBehaviour
{
    [Header("Light Camera Settings")]
    public Camera lightCamera;

    public float orthographicSize = 6f;
    public float nearClipPlane = 0.3f;
    public float farClipPlane = 20f;

    [Header("Directional Shadow Placement")]
    public Vector3 shadowCenter = Vector3.zero;
    public float shadowCameraDistance = 10f;

    [Tooltip("如果 cube 升高时阴影方向反了，就切换这个开关。")]
    public bool invertLightDirection = false;

    private void OnEnable()
    {
        SetupCamera();
    }

    private void OnValidate()
    {
        SetupCamera();
    }

    private void LateUpdate()
    {
        SetupCamera();
    }

    private void SetupCamera()
    {
        if (lightCamera == null) return;

        lightCamera.orthographic = true;
        lightCamera.orthographicSize = orthographicSize;
        lightCamera.nearClipPlane = nearClipPlane;
        lightCamera.farClipPlane = farClipPlane;

        // 关键：明确当前自定义阴影系统使用哪个方向作为“光线方向”
        Vector3 lightDir = invertLightDirection
            ? -transform.forward
            : transform.forward;

        lightDir.Normalize();

        // 避免 LookRotation 的 up 和 forward 太接近
        Vector3 up = Vector3.ProjectOnPlane(Vector3.up, lightDir);
        if (up.sqrMagnitude < 0.0001f)
        {
            up = transform.up;
        }

        up.Normalize();

        // Camera 放在 shadowCenter 的反方向，看向 shadowCenter
        lightCamera.transform.position = shadowCenter - lightDir * shadowCameraDistance;
        lightCamera.transform.rotation = Quaternion.LookRotation(lightDir, up);
    }
}