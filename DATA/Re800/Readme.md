zx

| Item / Setting                  | Re800                                            |
| ------------------------------- | ------------------------------------------------ |
| Case folder                     | `cylinderTRUE_Re800_yplusWallKick_20260818_0202` |
| Reynolds number                 | **800**                                          |
| Cylinder diameter D             | **0.001 m**                                      |
| Cylinder radius R               | **0.0005 m**                                     |
| Free-stream velocity U∞         | **0.015 m/s**                                    |
| Kinematic viscosity ν           | **1.875e-08 m²/s**                               |
| Reynolds formula                | `0.015 × 0.001 / 1.875e-08 = 800`                |
| Flow type                       | 2D high-Re laminar-like                          |
| Strict turbulence?              | **No**                                           |
| Momentum transport model        | **laminar**                                      |
| Laminar stress model            | **Stokes**                                       |
| Solver                          | `foamRun -solver incompressibleFluid`            |
| Time scheme                     | **Euler**                                        |
| Pressure–velocity coupling      | **PIMPLE**                                       |
| Base mesh                       | 成功 Re200 的 body-fitted `blockMesh`               |
| Mesh type                       | `blockMesh` + wall-layer refinement              |
| Base cell count                 | **5388**                                         |
| Wall-layer refinement           | `refineWallLayer ×2`                             |
| Expected cells after refinement | approx **5548**                                  |
| First-layer height ratio        | approx **1/4 of Re200**                          |
| Domain                          | `-0.1 to 0.1 m`                                  |
| Domain in D                     | approx `-100D to 100D`                           |
| Cylinder centre                 | `(0,0)`                                          |
| Simulation time                 | **0–10 s**                                       |
| Final simulated time            | **10.0 s**                                       |
| `deltaT`                        | **1e-5 s**                                       |
| `maxDeltaT`                     | **1e-5 s**                                       |
| `maxCo` setting                 | **0.3**                                          |
| Adaptive time stepping          | **yes**                                          |
| Actual final mean Co            | **3.8217466e-05**                                |
| Actual final max Co             | **0.0071669481**                                 |
| Output interval                 | **0.05 s**                                       |
| Saved time folders              | `0, 0.05, …, 10`                                 |
| Saved time levels               | approx **201**                                   |
| Initial base velocity           | `U=(0.015,0,0)`                                  |
| Local perturbation velocity     | `U=(0.015,0.006,0)`                              |
| Perturbation strength           | **v/U∞ = 40%**                                   |
| Perturbation box                | `x=0.0006 to 0.004, y=0.00005 to 0.0005`         |
| Inlet velocity BC               | `u=0.015, v=0`                                   |
| Outlet velocity BC              | `zeroGradient`                                   |
| Cylinder velocity BC            | no-slip, `u=v=0`                                 |
| Inlet pressure BC               | `zeroGradient`                                   |
| Outlet pressure BC              | `p=0`                                            |
| Cylinder pressure BC            | `zeroGradient`                                   |
| Cylinder wall faces             | **80**                                           |
| yPlus min                       | **0.00024496881**                                |
| yPlus mean                      | **0.009451419075**                               |
| yPlus max                       | **0.018264272**                                  |
| Near-wall resolution            | **y+ <<1**                               |
| PINN input, single Re           | `x, y, t`                                        |
| PINN input, multi-Re            | `x, y, t, Re` 或 `x, y, t, ν`                     |
| PINN output                     | `u, v, p`                                        |
| Pressure unit                   | **m²/s²**                                        |
| Validation                      | `CD, CL, St, u, v, p`                            |
| Strouhal definition             | `St = fD/U∞`                                     |
| Important note                  | Re800 已完成到 **10 s**；近壁和时间分辨率都非常保守                |
