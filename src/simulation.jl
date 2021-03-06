function run_sim(method, dir_log, file_name="switching.jld2")
    mkpath(dir_log)
    file_path = joinpath(dir_log, file_name)
    saved_data = nothing
    data_exists = isfile(file_path)
    if !data_exists
        _multicopter = LeeHexacopterEnv()
        u_max = (1/3) * _multicopter.m * _multicopter.g * ones(_multicopter.dim_input)
        multicopter = LeeHexacopterEnv(u_max=u_max)
        @unpack m, B, u_min, dim_input = multicopter
        τ = 0.2
        fdi = DelayFDI(τ)
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
        plant = FTC.DelayFDI_Plant(multicopter, fdi, faults)
        @unpack multicopter = plant
        pos_cmd_func = (t) -> [2, 1, -3]
        controller = BacksteppingPositionControllerEnv(m; pos_cmd_func=pos_cmd_func)
        # optimisation-based allocators
        # allocator = PseudoInverseAllocator(B)  # deprecated; it does not work when failures occur. I guess it's due to Moore-Penrose pseudo inverse.
        allocator = ConstrainedAllocator(B, u_min, u_max)
        control_system_optim = FTC.BacksteppingControl_StaticAllocator_ControlSystem(controller, allocator)
        env_optim = FTC.DelayFDI_Plant_BacksteppingControl_StaticAllocator_ControlSystem(plant, control_system_optim)
        # adaptive allocators
        allocator = AdaptiveAllocator(B)
        control_system_adaptive = FTC.BacksteppingControl_AdaptiveAllocator_ControlSystem(controller, allocator)
        env_adaptive = FTC.DelayFDI_Plant_BacksteppingControl_AdaptiveAllocator_ControlSystem(plant, control_system_adaptive)
        p0, x0 = nothing, nothing
        if method == :adaptive || method == :adaptive2optim
            p0 = :adaptive
            x0 = State(env_adaptive)()  # start with adaptive CA
        elseif method == :optim
            p0 = :optim
            x0 = State(env_optim)()  # start with optim CA
        else
            error("Invalid method")
        end
        @Loggable function dynamics!(dx, x, p, t)
            @log method = p
            if p == :adaptive
                @nested_log Dynamics!(env_adaptive)(dx, x, p, t)
            elseif p == :optim
                @nested_log Dynamics!(env_optim)(dx, x, p, t)
            else
                error("Invalid method")
            end
        end
        __log_indicator__ = __LOG_INDICATOR__()
        affect! = (integrator) -> error("Invalid method")
        if method == :adaptive2optim
            affect! = (integrator) -> integrator.p = :optim
        elseif method == :adaptive || method == :optim
            affect! = (integrator) -> nothing
        end
        condition = function (x, t, integrator)
            p = integrator.p
            if p == :adaptive
                x = copy(x)
                dict = Dynamics!(env_adaptive)(zero.(x), x, p, t, __log_indicator__)
                u_actual = dict[:plant][:input][:u_actual]
                is_switched = any(u_actual .>= u_max) || any(u_actual .<= u_min)
                return is_switched
            elseif p == :optim
                return false
            else
                error("Invalid method")
            end
        end
        cb_switch = DiscreteCallback(condition, affect!)
        cb = CallbackSet(cb_switch)
        # sim
        tf = 15.0
        @time prob, df = sim(
                             x0,
                             dynamics!,
                             p0;
                             tf=tf,
                             savestep=0.01,
                             callback=cb,
                            )
        FileIO.save(file_path, Dict("df" => df,
                                    "dim_input" => dim_input,
                                    "u_max" => u_max,
                                    "u_min" => u_min,
                                    "pos_cmd_func" => pos_cmd_func,
                                   ))
    end
    saved_data = JLD2.load(file_path)
end

function plot_figures(method, dir_log, saved_data)
    @unpack df, dim_input, u_max, u_min, pos_cmd_func = saved_data
    # data
    ts = df.time
    poss = df.sol |> Map(datum -> datum.plant.state.p) |> collect
    xs = poss |> Map(pos -> pos[1]) |> collect
    ys = poss |> Map(pos -> pos[2]) |> collect
    zs = poss |> Map(pos -> pos[3]) |> collect
    poss_desired = ts |> Map(pos_cmd_func) |> collect
    xs_des = poss_desired |> Map(pos -> pos[1]) |> collect
    ys_des = poss_desired |> Map(pos -> pos[2]) |> collect
    zs_des = poss_desired |> Map(pos -> pos[3]) |> collect
    us_cmd = df.sol |> Map(datum -> datum.plant.input.u_cmd) |> collect
    us_actual = df.sol |> Map(datum -> datum.plant.input.u_actual) |> collect
    us_saturated = df.sol |> Map(datum -> datum.plant.input.u_saturated) |> collect
    us_cmd_faulted = df.sol |> Map(datum -> datum.plant.FDI.Λ * datum.plant.input.u_cmd) |> collect
    νs = df.sol |> Map(datum -> datum.plant.input.ν) |> collect
    Fs = νs |> Map(ν -> ν[1]) |> collect
    Ms = νs |> Map(ν -> ν[2:4]) |> collect
    νds = df.sol |> Map(datum -> datum.νd) |> collect
    Fds = νds |> Map(ν -> ν[1]) |> collect
    Mds = νds |> Map(ν -> ν[2:4]) |> collect
    Λs = df.sol |> Map(datum -> datum.plant.FDI.Λ) |> collect
    Λ̂s = df.sol |> Map(datum -> datum.plant.FDI.Λ̂) |> collect
    _Λs = Λs |> Map(diag) |> collect
    _Λ̂s = Λ̂s |> Map(diag) |> collect
    _method_dict = Dict(:adaptive => 0, :optim => 1)
    _methods = df.sol |> Map(datum -> _method = datum.method == :adaptive ? _method_dict[:adaptive] : _method_dict[:optim]) |> collect
    control_squares = us_actual |> Map(u -> norm(u, 2)^2) |> collect
    control_inf_norms = us_actual |> Map(u -> norm(u, Inf)) |> collect
    _∫control_squares = cumul_integrate(ts, control_squares)  # ∫ u' * u
    ∫control_squares = _∫control_squares .- _∫control_squares[1]  # to make the first element 0
    _∫control_inf_norms = cumul_integrate(ts, control_inf_norms)  # ∫ u' * u
    ∫control_inf_norms = _∫control_inf_norms .- _∫control_inf_norms[1]
    @show ∫control_squares[end]
    @show ∫control_inf_norms[end]
    # plots
    ts_tick = ts[1:100:end]
    tstr = ts_tick |> Map(t -> @sprintf("%0.0f", t)) |> collect
    tstr_empty = ts_tick |> Map(t -> "") |> collect
    # background color
    ts_from_fault1_to_fault2 = 3:0.01:5
    ts_from_fault2_to_end = 5:0.01:15
    ## pos
    ylim_p_pos = (-4, 6)
    p_pos = plot(;
                 title="position",
                 legend=:topleft,
                 ylabel="position (m)",
                 ylim=ylim_p_pos,
                )
    xticks!(ts_tick, tstr_empty)
    plot!(p_pos, ts, xs;
          label="x",
          color=1,  # i'th default color
         )
    plot!(p_pos, ts, ys;
          label="y",
          color=2,  # i'th default color
         )
    plot!(p_pos, ts, zs;
          label="z",
          color=3,  # i'th default color
         )
    plot!(p_pos, ts, xs_des;
          label=nothing, ls=:dash,
          color=1,  # i'th default color
         )
    plot!(p_pos, ts, ys_des;
          label=nothing, ls=:dash,
          color=2,  # i'th default color
         )
    plot!(p_pos, ts, zs_des;
          label=nothing, ls=:dash,
          color=3,  # i'th default color
         )
    plot!(p_pos,
          ts_from_fault1_to_fault2, 0.5*(ylim_p_pos[2]+ylim_p_pos[1])*ones(size(ts_from_fault1_to_fault2));  # time period until fault 1
          ribbon=0.5*(ylim_p_pos[2]-ylim_p_pos[1])*ones(size(ts_from_fault1_to_fault2)),
          color=:transparent,
          fillalpha=0.1,
          fillcolor=:orange,
          label=nothing,
         )
    plot!(p_pos,
          ts_from_fault2_to_end, 0.5*(ylim_p_pos[2]+ylim_p_pos[1])*ones(size(ts_from_fault2_to_end));  # time period until fault 1
          ribbon=0.5*(ylim_p_pos[2]-ylim_p_pos[1])*ones(size(ts_from_fault2_to_end)),
          color=:transparent,
          fillalpha=0.1,
          fillcolor=:red,
          label=nothing,
         )
    ## Λ
    ylim_p__Λ = (-0.1, 1.1)
    p__Λ = plot(ts, hcat(_Λ̂s...)'; title="effectiveness vector",
                ylim=(-0.1, 1.1),
                label=["estimated" fill(nothing, dim_input-1)...],
                ylabel="diag(Λ)",
                color=:black,
         )
    xticks!(ts_tick, tstr_empty)
    plot!(p__Λ, ts, hcat(_Λs...)';
                label=["true" fill(nothing, dim_input-1)...],
                color=:red,
                ls=:dash,
                legend=:right,
               )
    plot!(p__Λ,
          ts_from_fault1_to_fault2, 0.5*(ylim_p__Λ[2]+ylim_p__Λ[1])*ones(size(ts_from_fault1_to_fault2));  # time period until fault 1
          ribbon=0.5*(ylim_p__Λ[2]-ylim_p__Λ[1])*ones(size(ts_from_fault1_to_fault2)),
          color=:transparent,
          fillalpha=0.1,
          fillcolor=:orange,
          label=nothing,
         )
    plot!(p__Λ,
          ts_from_fault2_to_end, 0.5*(ylim_p__Λ[2]+ylim_p__Λ[1])*ones(size(ts_from_fault2_to_end));  # time period until fault 1
          ribbon=0.5*(ylim_p__Λ[2]-ylim_p__Λ[1])*ones(size(ts_from_fault2_to_end)),
          color=:transparent,
          fillalpha=0.1,
          fillcolor=:red,
          label=nothing,
         )
    ## method
    p_method = plot(;
                    title="method (adaptive: $(_method_dict[:adaptive]), optim: $(_method_dict[:optim]))",
                    legend=:topleft,
                   )
    ylim_p_method = (-0.1, 1.1)
    plot!(p_method, ts, hcat(_methods...)';
          label="",
          color=:black,
          ylabel="method",
          xlabel="t (s)",
          ylim=ylim_p_method,
         )
    xticks!(ts_tick, tstr)
    plot!(p_method,
          ts_from_fault1_to_fault2, 0.5*(ylim_p_method[2]+ylim_p_method[1])*ones(size(ts_from_fault1_to_fault2));  # time period until fault 1
          ribbon=0.5*(ylim_p_method[2]-ylim_p_method[1])*ones(size(ts_from_fault1_to_fault2)),
          color=:transparent,
          fillalpha=0.1,
          fillcolor=:orange,
          label=nothing,
         )
    plot!(p_method,
          ts_from_fault2_to_end, 0.5*(ylim_p_method[2]+ylim_p_method[1])*ones(size(ts_from_fault2_to_end));  # time period until fault 1
          ribbon=0.5*(ylim_p_method[2]-ylim_p_method[1])*ones(size(ts_from_fault2_to_end)),
          color=:transparent,
          fillalpha=0.1,
          fillcolor=:red,
          label=nothing,
         )
    ### states
    p_state = plot(p_pos, p__Λ, p_method;
                   link=:x,  # aligned x axes
                   layout=(3, 1), size=(600, 600),
                  )
    savefig(p_state, joinpath(dir_log, "state.pdf"))
    ## u
    p_u = plot(;
               title="rotor input",
               legend=:topleft,
               ylabel="rotor force (N)",
               xlabel="t (s)",
              )
    # xticks!(ts_tick, tstr_empty)  # to remove xticks
    ylim_p_u = (minimum(u_min)-1, maximum(u_max)+5)
    plot!(p_u, ts, hcat(us_actual...)';
          # ylim=(-0.1*maximum(u_max), 1.1*maximum(u_max)),
          label=["input" fill(nothing, dim_input-1)...],
          color=:black,
          ylim=ylim_p_u,
         )
    plot!(p_u, ts, maximum(u_max)*ones(size(ts));
          label="input min/max",
          ls=:dash,
          color=:red,
         )
    plot!(p_u, ts, minimum(u_min)*ones(size(ts));
          label=nothing,
          ls=:dash,
          color=:red,
         )
    plot!(p_u,
          ts_from_fault1_to_fault2, 0.5*(ylim_p_u[2]+ylim_p_u[1])*ones(size(ts_from_fault1_to_fault2));  # time period until fault 1
          ribbon=0.5*(ylim_p_u[2]-ylim_p_u[1])*ones(size(ts_from_fault1_to_fault2)),
          color=:transparent,
          fillalpha=0.1,
          fillcolor=:orange,
          label=nothing,
         )
    plot!(p_u,
          ts_from_fault2_to_end, 0.5*(ylim_p_u[2]+ylim_p_u[1])*ones(size(ts_from_fault2_to_end));  # time period until fault 1
          ribbon=0.5*(ylim_p_u[2]-ylim_p_u[1])*ones(size(ts_from_fault2_to_end)),
          color=:transparent,
          fillalpha=0.1,
          fillcolor=:red,
          label=nothing,
         )
    ## ν
    # legend_ν = method == :adaptive ? :topleft : :left
    legend_ν = :bottomleft
    # force
    p_F = plot(;
               title="force",
               ylabel="F (N)",
               ylim=(0, 60),
               legend=:bottomleft,
              )
    xticks!(ts_tick, tstr_empty)
    plot!(p_F, ts, hcat(Fs...)';
          label=["actual force" fill(nothing, 4-1)...],
          color=:black,
         )
    plot!(p_F, ts, hcat(Fds...)';
          label=["desired force" fill(nothing, 4-1)...],
          color=:red,
          ls=:dash,
         )
    # moment
    p_M = plot(;
               title="moment",
               ylabel="M (N⋅m)",
               xlabel="t (s)",
               ylim=(-100, 100),
               legend=:bottomleft,
              )
    xticks!(ts_tick, tstr)
    plot!(p_M, ts, hcat(Ms...)';
          label=["actual moment" fill(nothing, 4-1)...],
          color=:black,
         )
    plot!(p_M, ts, hcat(Mds...)';
          label=["desired moment" fill(nothing, 4-1)...],
          color=:red,
          ls=:dash,
         )
    ## figure zoom
    if method != :adaptive
        # fault 1
        t1_min, t1_max = 2, 4
        idx1 = findall(t -> t > t1_min && t < t1_max, ts)
        ts_idx1 = ts[idx1]
        Ms_idx1 = Ms[idx1]
        Mds_idx1 = Mds[idx1]
        plot!(p_M, [ts_idx1 ts_idx1], [hcat(Ms_idx1...)' hcat(Mds_idx1...)'];
              inset = (1, bbox(0.1, 0.05, 0.3, 0.3)), subplot=2,
              ylim=(-5, 5), bg_inside=nothing, label=nothing,
              color=[:black :red], linestyle=[:solid :dash],
             )
        # fault 2
        t2_min, t2_max = 4, 6
        idx2 = findall(t -> t > t2_min && t < t2_max, ts)
        ts_idx2 = ts[idx2]
        Ms_idx2 = Ms[idx2]
        Mds_idx2 = Mds[idx2]
        plot!(p_M, [ts_idx2 ts_idx2], [hcat(Ms_idx2...)' hcat(Mds_idx2...)'];
              inset = (1, bbox(0.5, 0.05, 0.3, 0.3)), subplot=3,
              ylim=(-5, 5), bg_inside=nothing, label=nothing,
              color=[:black :red], linestyle=[:solid :dash],
             )
    end
    ### inputs
    # p_input = plot(p_u, p_F, p_M;
    #                link=:x,  # aligned x axes
    #                layout=(3, 1), size=(600, 600),
    #               )
    p_input = plot(p_u; size=(600, 600),)
    savefig(p_input, joinpath(dir_log, "input.pdf"))
end

function simulation()
    dir_log = "data"
    mkpath(dir_log)
    methods = [:adaptive, :optim, :adaptive2optim]
    @show methods
    for method in methods
        @show method
        _dir_log = joinpath(dir_log, String(method))
        saved_data = run_sim(method, _dir_log)
        plot_figures(method, _dir_log, saved_data)
    end
end
