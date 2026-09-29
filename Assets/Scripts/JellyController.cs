using UnityEngine;

public class JellyFinalController : MonoBehaviour
{
    public Material mat;
    public Rigidbody rb;
    public Renderer rend;

    [Header("Jelly Physics")]
    public float stiffness = 100f;
    public float damping = 5f;

    [Header("Scale-Based Squash & Stretch")]
    public bool UseScaleDeformation = false; // drives localScale from the same spring sim, independent of the shader - works on any material
    public Transform visualTransform;        // a CHILD mesh transform (not this object) that gets rotated/scaled - keeps the physics root's rotation untouched
    public float scaleDeformMultiplier = 1f; // tune deformation intensity
    public float maxSquash = 0.4f;           // clamps how far it can squash/stretch (0-1 range makes sense)

    private Vector3 baseVisualScale = Vector3.one;

    private Vector3 localInertia, inertiaVelocity, lastPos, lastVel;
    private int framesToSkip = 10; // Prevents the "Level Start Explosion"
    private bool activated = false;

    void Awake()
    {
        if (!activated) CheckActive();
    }

    void CheckActive()
    {
        if (rend == null || rb == null)
        {
            Invoke(nameof(CheckActive), .1f);
        }
        else if (!activated)
        {
            Activate();
        }
    }

    public void Activate()
    {
        mat = rend.material;
        lastPos = transform.position;
        activated = true;

        if (visualTransform != null)
            baseVisualScale = visualTransform.localScale;
    }

    void FixedUpdate()
    {
        if (!activated) return;
        if (rb.isKinematic) return;

        // Wait for the object to "land" in the scene before wobbling
        if (framesToSkip > 0)
        {
            lastPos = transform.position;
            framesToSkip--;
            return;
        }

        Vector3 velocity = (transform.position - lastPos) / Time.fixedDeltaTime;
        Vector3 accel = (velocity - lastVel) / Time.fixedDeltaTime;
        Vector3 force = -transform.InverseTransformDirection(accel);

        Vector3 springForce = force - (localInertia * stiffness) - (inertiaVelocity * damping);
        inertiaVelocity += springForce * Time.fixedDeltaTime;
        localInertia += inertiaVelocity * Time.fixedDeltaTime;

        lastPos = transform.position;
        lastVel = velocity;

        if (UseScaleDeformation && visualTransform != null)
        {
            ApplyScaleDeformation();
        }
        else
        {
            mat.SetVector("_Inertia", localInertia);
        }
    }

    private void ApplyScaleDeformation()
    {
        float mag = localInertia.magnitude;
        float squash = Mathf.Clamp(mag * scaleDeformMultiplier, 0f, maxSquash);
        float squashScale = 1f - squash;
        float stretchScale = 1f + squash * 0.5f;

        visualTransform.localScale = new Vector3(
            baseVisualScale.x * stretchScale,
            baseVisualScale.y * squashScale,
            baseVisualScale.z * stretchScale
        );
    }
}
