module ControlAllocationSwitching

using FlightSims
const FS = FlightSims
using FaultTolerantControl
const FTC = FaultTolerantControl
using Plots
using LinearAlgebra
using Transducers
using DifferentialEquations
using UnPack
using ReferenceFrameRotations
using JLD2, FileIO
using Printf
using NumericalIntegration


export draw_figures
export simulation


include("figures.jl")
include("simulation.jl")


end
