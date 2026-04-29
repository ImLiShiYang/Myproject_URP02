using UnityEngine;

/// <summary>
/// 让一个普通 Camera 作为“光源相机”使用。
///
/// 这个脚本挂在 Directional Light 物体上。
/// 它会把指定的 lightCamera 设置成正交相机，
/// 并根据当前光源 Transform 来同步光源相机的位置和旋转。
///
/// 用途：
/// 1. 用 LightCamera 渲染自定义深度图 / Shadow Map
/// 2. 让 LightCamera 跟随光源移动
/// 3. 后续可以让光源绕某个点旋转，从而让阴影跟着变化
/// </summary>
[RequireComponent(typeof(Light))]
[ExecuteAlways]
public class DirectionalLightCameraSetter : MonoBehaviour
{

    /// <summary>
    /// 用来渲染自定义深度图的光源相机。
    ///
    /// 注意：
    /// 这里要拖入你专门创建的 LightCamera，
    /// 不要拖 Main Camera。
    /// </summary>
    [Header("Light Camera Settings")]
    public Camera lightCamera;

    /// <summary>
    /// 正交相机的半高。
    ///
    /// 这个值决定 shadow map 覆盖的世界范围。
    ///
    /// 值越大：
    /// - 覆盖范围越大
    /// - 单位世界空间分到的 shadow map 像素越少
    /// - 阴影越容易糊
    ///
    /// 值越小：
    /// - 阴影越清晰
    /// - 但覆盖范围变小，物体可能超出 shadow map
    /// </summary>
    public float orthographicSize = 6f;

    /// <summary>
    /// 光源相机近裁剪面。
    ///
    /// 太小会浪费深度精度；
    /// 太大可能裁掉靠近相机的投影物。
    /// </summary>
    public float nearClipPlane = 0.3f;

    /// <summary>
    /// 光源相机远裁剪面。
    ///
    /// 要保证 caster 和 receiver 都在 near/far 范围内。
    /// 但 far 太大也会降低线性深度精度。
    /// </summary>
    public float farClipPlane = 20f;



    /// <summary>
    /// 是否让 LightCamera 的位置跟随当前 Light 的位置。
    ///
    /// 如果你想让光源绕某个点旋转，并且阴影跟着变化，
    /// 通常应该开启这个选项。
    /// </summary>
    [Header("Follow Light Transform")]
    public bool followLightPosition = true;

    /// <summary>
    /// 是否让 LightCamera 的旋转跟随当前 Light 的旋转。
    ///
    /// 如果关闭 lookAtShadowCenter，则通常开启它。
    /// </summary>
    public bool followLightRotation = true;



    /// <summary>
    /// 是否强制让 LightCamera 看向 shadowCenter。
    ///
    /// 开启后：
    /// - LightCamera 的位置仍然可以跟随 Light
    /// - 但旋转不再直接使用 Light 的 rotation
    /// - 而是自动朝向 shadowCenter
    ///
    /// 适合做“光源围绕中心点旋转并始终照向中心”的效果。
    /// </summary>
    [Header("Optional Look At")]
    public bool lookAtShadowCenter = false;

    /// <summary>
    /// 光源相机看向的中心点。
    ///
    /// 如果 lookAtShadowCenter = true，
    /// LightCamera 会始终朝向这个点。
    ///
    /// 例如：
    /// - 场景中心
    /// - 角色位置
    /// - 需要重点覆盖阴影的区域中心
    /// </summary>
    public Vector3 shadowCenter = Vector3.zero;

    /// <summary>
    /// 是否反转光源方向。
    ///
    /// 如果你发现：
    /// - cube 升高时阴影移动方向反了
    /// - 或者阴影投射方向和预期相反
    ///
    /// 可以切换这个开关。
    ///
    /// 注意：
    /// 这个开关只影响 LightCamera 朝向，
    /// 不负责修复 RenderTexture 的 UV 上下翻转。
    /// UV 翻转应该在你的矩阵或 shader 中处理。
    /// </summary>
    public bool invertLightDirection = false;


    /// <summary>
    /// 脚本启用时调用。
    ///
    /// ExecuteAlways 使它在编辑器模式下也会执行，
    /// 所以你拖动光源或修改参数时能实时更新 LightCamera。
    /// </summary>
    private void OnEnable()
    {
        SetupCamera();
    }

    /// <summary>
    /// Inspector 中修改参数时调用。
    ///
    /// 这样修改 orthographicSize、near/far 等参数后，
    /// LightCamera 会立刻同步。
    /// </summary>
    private void OnValidate()
    {
        SetupCamera();
    }

    /// <summary>
    /// 每帧后期更新。
    ///
    /// 用 LateUpdate 是为了尽量保证：
    /// 如果其他脚本在 Update 中移动/旋转了 Light，
    /// 这里可以拿到最终 Transform 状态。
    /// </summary>
    private void LateUpdate()
    {
        SetupCamera();
    }

    /// <summary>
    /// 设置 LightCamera 的核心函数。
    ///
    /// 主要做四件事：
    /// 1. 设置 LightCamera 为正交相机
    /// 2. 设置正交尺寸和裁剪面
    /// 3. 同步 LightCamera 的位置
    /// 4. 同步或计算 LightCamera 的旋转
    /// </summary>
    private void SetupCamera()
    {
        // 没有指定 LightCamera 时直接返回。
        // 避免空引用报错。
        if (lightCamera == null) 
            return;

        // ==========================================
        // 1. 设置光源相机的投影参数
        // ==========================================

        // Shadow map 通常使用正交投影。
        // 对 Directional Light 来说，光线近似平行，
        // 所以用 orthographic camera 更符合方向光阴影。
        lightCamera.orthographic = true;

        // 设置正交范围。
        lightCamera.orthographicSize = orthographicSize;

        // 设置 near/far。
        lightCamera.nearClipPlane = nearClipPlane;
        lightCamera.farClipPlane = farClipPlane;


        // ==========================================
        // 2. 同步 LightCamera 的位置
        // ==========================================

        if (followLightPosition)
        {
            // 让光源相机的位置等于当前 Light 物体的位置。
            //
            // 这样你移动 Light，或者让 Light 围绕某个点旋转时，
            // LightCamera 也会跟着移动。
            lightCamera.transform.position = transform.position;
        }


        // ==========================================
        // 3. 设置 LightCamera 的旋转
        // ==========================================

        if (lookAtShadowCenter)
        {
            // ------------------------------------------
            // 模式 A：
            // LightCamera 不直接使用 Light 的 rotation，
            // 而是从当前位置看向 shadowCenter。
            // ------------------------------------------

            // 从 LightCamera 指向 shadowCenter 的方向。
            Vector3 dir = shadowCenter - lightCamera.transform.position;

            // 如果阴影方向反了，可以反转这个方向。
            if (invertLightDirection)
            {
                dir = -dir;
            }

            // 避免 LightCamera 和 shadowCenter 重合。
            // 如果距离太近，LookRotation 会不稳定。
            if (dir.sqrMagnitude > 0.0001f)
            {
                dir.Normalize();

                // 计算一个稳定的 up 方向。
                //
                // Quaternion.LookRotation 需要两个方向：
                // - forward：相机看向哪里
                // - up：相机顶部朝哪里
                //
                // 这里把世界上方向 Vector3.up 投影到
                // “垂直于 dir 的平面”上。
                //
                // 这样得到的 up：
                // - 尽量接近世界上方向
                // - 同时又和 forward 垂直
                Vector3 up = Vector3.ProjectOnPlane(Vector3.up, dir);

                // 如果 dir 接近垂直方向，
                // Vector3.up 和 dir 可能几乎平行，
                // 此时投影结果会接近 0。
                //
                // 这时退回使用当前 Light 自身的 up。
                if (up.sqrMagnitude < 0.0001f)
                {
                    up = transform.up;
                }

                up.Normalize();

                // 让 LightCamera 朝向 dir。
                lightCamera.transform.rotation = Quaternion.LookRotation(dir, up);
            }
        }
        else if (followLightRotation)
        {
            // ------------------------------------------
            // 模式 B：
            // LightCamera 直接跟随 Light 的 rotation。
            // ------------------------------------------

            if (invertLightDirection)
            {
                // 反转 forward 方向。
                //
                // 注意：
                // 这里用 transform.up 作为 up 方向，
                // 保持相机的 roll 尽量跟随 Light。
                lightCamera.transform.rotation = Quaternion.LookRotation(
                    -transform.forward,
                    transform.up
                );
            }
            else
            {
                // 最直接的同步方式：
                // LightCamera 的旋转完全等于 Light 的旋转。
                lightCamera.transform.rotation = transform.rotation;
            }
        }
    }
    
}