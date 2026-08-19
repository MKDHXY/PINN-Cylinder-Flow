zx
| **Item**                     | **Symbol / Setting** | **RE800 Value**                                                     | **Notes for PINN**                                            |
| ---------------------------- | -------------------: | ------------------------------------------------------------------- | ------------------------------------------------------------- |
| Reynolds number              |                 (Re) | **800**                                                             | Target Reynolds number                                        |
| Cylinder diameter            |                  (D) | **0.001 m**                                                         | Geometric/reference length scale                              |
| Free-stream velocity         |           (U_\infty) | **0.015 m/s**                                                       | Reference velocity and inlet velocity                         |
| Kinematic viscosity          |                (\nu) | **1.875 × 10⁻⁸ m²/s**                                               | **Use this value in the dimensional PINN physics loss**       |
| Reynolds-number definition   |  (Re=U_\infty D/\nu) | **800**                                                             | (0.015\times0.001/(1.875\times10^{-8})=800)                   |
| Flow type                    |                    — | **2D, incompressible, transient, laminar**                          | No turbulence model is active                                 |
| OpenFOAM version             |                    — | **OpenFOAM 14**                                                     | CFD data source                                               |
| CFD solver                   |                    — | `foamRun` + `incompressibleFluid`                                   | Incompressible transient solver                               |
| Pressure–velocity coupling   |                    — | **PIMPLE**                                                          | Transient pressure–velocity coupling                          |
| Cylinder centre              |          ((x_c,y_c)) | **(0, 0)**                                                          | Cylinder location                                             |
| Computational domain         |              ((x,y)) | **−0.1 to 0.1 m**                                                   | Approximately ((-100D)) to ((100D))                           |
| Domain bounding box          |                    — | **((-0.1,-0.1,-0.0005)) to ((0.1,0.1,0.0005))**                     | From OpenFOAM `checkMesh`                                     |
| Mesh size                    |                    — | **5548 cells**                                                      | Wall-layer refined Re800 mesh                                 |
| Mesh points                  |                    — | **11334 points**                                                    | From OpenFOAM `checkMesh`                                     |
| Mesh faces                   |                    — | **22311 faces**                                                     | From OpenFOAM `checkMesh`                                     |
| Cell type                    |                    — | **5548 hexahedra**                                                  | No prisms, wedges, pyramids, tetrahedra, or polyhedra         |
| Mesh dimensionality          |                    — | **2D**                                                              | One cell in spanwise direction; front/back are `empty`        |
| Mesh quality                 |                    — | **Mesh OK**                                                         | Passed OpenFOAM `checkMesh`                                   |
| Max aspect ratio             |                    — | **47.461502**                                                       | Mesh-quality reference                                        |
| Max non-orthogonality        |                    — | **41.662428°**                                                      | Average = **6.7978557°**                                      |
| Max skewness                 |                    — | **0.86685071**                                                      | Mesh-quality reference                                        |
| Cylinder (y^+)               |                    — | min **0.00024496881**, mean **0.009451419075**, max **0.018264272** | Evaluated at (t=10,s), cylinder patch, 80 wall faces          |
| Simulation time              |                  (t) | **0–10 s**                                                          | Full CFD simulation interval used for current export          |
| Maximum CFD time step        |    (\Delta t_{\max}) | **1 × 10⁻⁵ s**                                                      | Internal CFD time step / `maxDeltaT`                          |
| Adaptive time stepping       |                    — | **Yes**                                                             | Controlled by Courant number                                  |
| Maximum Courant number       |          (Co_{\max}) | **0.3**                                                             | CFD stability control                                         |
| CFD output interval          |                    — | **0.05 s**                                                          | Interval between saved CFD fields                             |
| Number of saved time steps   |                    — | **201**                                                             | (t=0,0.05,0.10,\dots,10.00)                                   |
| PINN inputs                  |                    — | **x, y, t**                                                         | Neural-network inputs                                         |
| PINN outputs                 |                    — | **u, v, p**                                                         | Predicted flow variables                                      |
| ((x,y)) units                |                    — | **m**                                                               | Dimensional coordinates                                       |
| (t) unit                     |                    — | **s**                                                               | Physical time                                                 |
| ((u,v)) units                |                    — | **m/s**                                                             | Velocity components                                           |
| **Pressure (p) unit**        |                    — | **m²/s²**                                                           | **Kinematic pressure, NOT pressure in Pa**                    |
| Inlet velocity BC            |                    — | (u=0.015,\ v=0)                                                     | `fixedValue`                                                  |
| Outlet velocity BC           |                    — | (\partial U/\partial n=0)                                           | `zeroGradient`                                                |
| Cylinder velocity BC         |                    — | (u=v=0)                                                             | No-slip wall                                                  |
| Inlet pressure BC            |                    — | (\partial p/\partial n=0)                                           | `zeroGradient`                                                |
| Outlet pressure BC           |                    — | **(p=0)**                                                           | Pressure reference                                            |
| Cylinder pressure BC         |                    — | (\partial p/\partial n=0)                                           | `zeroGradient`                                                |
| Base initial velocity        |                    — | (U=(0.015,0,0)) m/s                                                 | Initial flow condition                                        |
| Vortex-shedding perturbation |                    — | (U=(0.015,0.006,0)) m/s                                             | Local transverse perturbation used to break symmetry          |
| PINN mapping                 |                    — | **((x,y,t)\rightarrow(u,v,p))**                                     | Main learning problem                                         |
| Dataset file                 |                    — | `Re800_0_10_xytuvp.mat`                                             | Full-field CFD dataset converted from CSV                     |
| CSV source file              |                    — | `Re800_0_10_xytuvp.csv`                                             | Columns are `x,y,t,u,v,p`                                     |
| Dataset rows                 |                    — | **1,115,148 rows**                                                  | (5548) cells × (201) saved time steps                         |
| Dataset location             |                    — | `DATA/RE800/PINN_READY/`                                            | Recommended data location                                     |
| Normalisation                |                    — | **Do not assume nondimensionalised**                                | Any normalisation must be explicitly defined in the PINN code |
| Main validation quantities   |                    — | (C_D,\ C_L(t),\ f,\ St,\ u,\ v,\ p)                                 | CFD–PINN comparison                                           |
| Strouhal number              |                 (St) | (St=fD/U_\infty)                                                    | Vortex-shedding frequency metric                              |
