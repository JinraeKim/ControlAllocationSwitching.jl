# ControlAllocationSwitching
- A repository for the codes used in the paper,
**Jinrae Kim et al., "Control Allocation Switching Scheme for Fault Tolerant Control of Hexacopter", presented in [2021 Asia-Pacific International Symposium on Aerospace Technology (APISAT2021), Jeju, Korea](https://apisat2021.org/)**.
# Notes
## Dependencies
- [Julia](https://julialang.org/) v1.6.2
- Others will automatically be installed via `Project.toml`.

# How to reproduce the simulation result?
## Case configuration
- In `src/simulation.jl`, comment out an undesirable fault case.
For example, to perform the case of moderate actuator faults,
```julia
# case 1: actuator saturated
# faults = FaultSet(
#                   LoE(3.0, 1, 0.3),  # t, index, level
#                   LoE(5.0, 3, 0.1),
#                  )  # Note: antisymmetric configuration of faults can cause undesirable control allocation; sometimes it is worse than multiple faults of rotors in symmetric configuration.
# case 2: actuator not saturated
faults = FaultSet(
        LoE(3.0, 1, 0.5),  # t, index, level
        LoE(5.0, 3, 0.5),
        )  # Note: antisymmetric configuration of faults can cause undesirable control allocation; sometimes it is worse than multiple faults of rotors in symmetric configuration.
```
and the case of severe actuator faults,
```julia
# case 1: actuator saturated
faults = FaultSet(
                  LoE(3.0, 1, 0.3),  # t, index, level
                  LoE(5.0, 3, 0.1),
                 )  # Note: antisymmetric configuration of faults can cause undesirable control allocation; sometimes it is worse than multiple faults of rotors in symmetric configuration.
# case 2: actuator not saturated
# faults = FaultSet(
#         LoE(3.0, 1, 0.5),  # t, index, level
#         LoE(5.0, 3, 0.5),
#         )  # Note: antisymmetric configuration of faults can cause undesirable control allocation; sometimes it is worse than multiple faults of rotors in symmetric configuration.
```

## Run
Run the function `main()` in `main.jl`.
## Saved data and figures
- See `data` for time response plots and `figures` for illustrations.
### Note
- Once simulation data are saved in `data`, running simulation simply reuse the saved data to draw figures.
To perform a new simulation, please remove the saved data.

## Examples
- Hexacopter description

![ex_screenshot](./figures/hexacopter_description.png)

- Top view

![ex_screenshot](./figures/topview.png)

- Problem description

![ex_screenshot](./figures/prob_description.png)

- Scheme description

![ex_screenshot](./figures/scheme_description.png)
