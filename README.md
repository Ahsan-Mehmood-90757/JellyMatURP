# JellyMatURP

A Unity URP prototype exploring soft-body-style "jelly" deformation entirely in a custom shader, driven by physics feedback from a simple spring controller — no mesh skinning or physics engine soft bodies involved.

## How it works

- **[JellyController.cs](Assets/Scripts/JellyController.cs)** watches a `Rigidbody`'s velocity/acceleration each `FixedUpdate` and runs a lightweight spring-damper simulation (`stiffness` / `damping`) to produce an "inertia" vector — how much the ball should squash, stretch, and lag behind its own motion.
- That inertia vector is pushed straight into the material via `mat.SetVector("_Inertia", ...)`, or alternatively applied as non-uniform scale on a child visual transform (`UseScaleDeformation`), so the effect works even on stock/imported materials without a custom shader.
- **[JellyTest.shader](Assets/JellyBall/JellyTest.shader)** is a hand-written URP HLSL shader (`Custom/JellyFusionFinalTransparent`) that displaces vertices in the vertex stage based on `_Inertia`, with volume conservation (squashing on one axis compensates by stretching the others) so the mesh doesn't just flatten. It also supports a `_FusionAmount` / `_OpponentPos` pull effect for merging two jelly bodies together, and casts shadows that match the deformed geometry (not the rest-pose mesh).
- Originally written as a Built-in Render Pipeline surface shader, it's been ported to hand-written URP HLSL (main light + additional lights + shadows + ambient/reflection-probe GI) so it renders correctly under URP instead of falling back to the pink error shader.

## Project info

- Unity **6000.3.8f1**, Universal Render Pipeline (URP) 17.3.0
- Status: early prototype — the shader/controller pair is the focus so far; the rest of the project is still the default URP template scene

## Media

_Screenshot/recording coming soon._

## Requirements

- Unity Hub with editor version `6000.3.8f1` (or compatible 6000.3.x)
