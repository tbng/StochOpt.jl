"""
### "Our Title", Othmane Sebbouh, Nidham Gazagnadou, Robert M. Gower (2019)

## --- EXPERIMENT 1.A ---
Goal: Testing the optimality of our optimal mini-batch size b* with m = n and corresponding step size gamma^*(b).

## --- THINGS TO CHANGE BEFORE RUNNING ---
- line XX: enter your full path to the "StochOpt.jl/" repository in the *path* variable

## --- HOW TO RUN THE CODE ---
To run this experiment, open a terminal, go into the "StochOpt.jl/" repository and run the following command:
>julia -p <number_of_processor_to_add> repeat_paper_experiments/repeat_theory_practice_SVRG_paper_experiment_1a.jl <boolean>
where <number_of_processor_to_add> has to be replaced by the user.
-If <boolean> == false, only the first problem (ijcnn1_full + column-scaling + lambda=1e-1) is launched
-Elseif <boolean> == true, all XX problems are launched

## --- EXAMPLE OF RUNNING TIME ---
Running time of the first problem only when adding XX processors on XXXX
XXXX, around XXmin
Running time of all problems when adding XX processors on XXXX
XXXX, around XXmin

## --- SAVED FILES ---
For each problem (data set + scaling process + regularization)
- the empirical total complexity v.s. mini-batch size plots are saved in ".pdf" format in the "./experiments/theory_practice_SVRG/exp1a/figures/" folder
- the results of the simulations (mini-batch grid, empirical complexities, optimal empirical mini-batch size, etc.) are saved in ".jld" format in the "./experiments/theory_practice_SVRG/exp1a/outputs/" folder
"""

## General settings
max_epochs = 10^8
max_time = 60.0*5.0 # 60.0*60.0*10.0
precision = 10.0^(-4) # 10.0^(-6)

## Bash input
# all_problems = parse(Bool, ARGS[1]) # run 1 (false) or all the 12 problems (true)
# problems = parse.(Int64, ARGS)
problems = [parse(Int64, ARGS[1])]
machine = ARGS[2]
println(machine)
println(problems)

using Distributed

@everywhere begin
    # path = "/home/nidham/phd/StochOpt.jl/" # Change the full path here
    if machine == "lame10"
        path = "/cal/homes/ngazagnadou/StochOpt.jl/"   # lame10
    elseif machine = "lame23"
        path = "/home/infres/ngazagnadou/StochOpt.jl/" # lame23
    end
    println(path)

    using JLD
    using Plots
    using StatsBase
    using Match
    using Combinatorics
    using Random
    using Printf
    using LinearAlgebra
    using Statistics
    using Base64
    using Formatting
    using SharedArrays

    include("$(path)src/StochOpt.jl")
    # gr()
    pyplot() # No problem with pyplot when called in @everywhere statement
end

## Create saving directories if not existing
save_path = "$(path)experiments/theory_practice_SVRG/"
#region
if !isdir(save_path)
    mkdir(save_path)
    mkdir("$(save_path)exp1a/")
end
save_path = "$(save_path)exp1a/"
if !isdir("$(save_path)data/")
    mkdir("$(save_path)data/")
end
if !isdir("$(save_path)figures/")
    mkdir("$(save_path)figures/")
end
if !isdir("$(save_path)outputs/")
    mkdir("$(save_path)outputs/")
end
#endregion

## Experiments settings
numsimu = 1 # number of runs of Free-SVRG for averaging the empirical complexity
# if all_problems
#     problems = 1:12
# else
#     problems = 1:1
# end

datasets = ["ijcnn1_full", "ijcnn1_full",                       # scaled,   n = 141,691, d =     22
            "YearPredictionMSD_full", "YearPredictionMSD_full", # scaled,   n = 515,345, d =     90
            "covtype_binary", "covtype_binary",                 # scaled,   n = 581,012, d =     54
            "slice", "slice",                                   # scaled,   n =  53,500, d =    384
            "real-sim", "real-sim",                             # unscaled, n =  72,309, d = 20,958
            "rcv1_full", "rcv1_full"]                           # unscaled, n = 697,641, d = 47,236

scalings = ["column-scaling", "column-scaling",
            "column-scaling", "column-scaling",
            "column-scaling", "column-scaling",
            "column-scaling", "column-scaling",
            "none", "none",
            "none", "none"]

lambdas = [10^(-1), 10^(-3),
           10^(-1), 10^(-3),
           10^(-1), 10^(-3),
           10^(-1), 10^(-3),
           10^(-1), 10^(-3),
           10^(-1), 10^(-3)]

## In the following table, set smaller values for finer estimations (yet, longer simulations)
skip_multipliers = [0.1,        # ijcnn1_full + scaled + 1e-1
                    1.0,        # ijcnn1_full + scaled + 1e-3
                    0.01,       # YearPredictionMSD_full + scaled + 1e-1
                    0.01,       # YearPredictionMSD_full + scaled + 1e-3
                    0.01,       # covtype_binary + scaled + 1e-1
                    0.01,       # covtype_binary + scaled + 1e-3
                    0.1,        # slice + scaled + 1e-1
                    1.0,        # slice + scaled + 1e-3
                    1.0,        # real-sim + unscaled + 1e-1
                    1.0,        # real-sim + unscaled + 1e-3
                    1.0,        # rcv1_full + unscaled + 1e-1
                    1.0]        # rcv1_full + unscaled + 1e-3

@time begin
@sync @distributed for idx_prob in problems
    data = datasets[idx_prob];
    scaling = scalings[idx_prob];
    lambda = lambdas[idx_prob];
    println("EXPERIMENT : ", idx_prob, " over ", length(problems))
    @printf "Inputs: %s + %s + %1.1e \n" data scaling lambda;

    Random.seed!(1)

    ## Loading the data
    println("--- Loading data ---")
    data_path = "$(path)data/";
    X, y = loadDataset(data_path, data)

    ## Setting up the problem
    println("\n--- Setting up the selected problem ---")
    options = set_options(tol=precision, max_iter=10^8,
                          max_epocs=max_epochs,
                          max_time=max_time,
                          skip_error_calculation=10^4,
                          batchsize=1,
                          regularizor_parameter = "normalized",
                          initial_point="zeros", # is fixed not to add more randomness
                          force_continue=false) # force continue if diverging or if tolerance reached
    u = unique(y)
    if length(u) < 2
        error("Wrong number of possible outputs")
    elseif length(u) == 2
        println("Binary output detected: the problem is set to logistic regression")
        prob = load_logistic_from_matrices(X, y, data, options, lambda=lambda, scaling=scaling)
    else
        println("More than three modalities in the outputs: the problem is set to ridge regression")
        prob = load_ridge_regression(X, y, data, options, lambda=lambda, scaling=scaling)
    end

    X = nothing
    y = nothing

    n = prob.numdata
    d = prob.numfeatures
    mu = prob.mu
    Lmax = prob.Lmax
    L = prob.L

    ## Computing theoretical optimal mini-batch size for b-nice sampling with inner loop size m = n
    b_theoretical = optimal_minibatch_Free_SVRG_nice(n, n, mu, L, Lmax) # optimal b for Free-SVRG when m=n

    ## Computing the empirical mini-batch size over a grid
    # minibatchgrid = vcat(2 .^ collect(0:7), 2 .^ collect(8:2:floor(Int, log2(n))))
    # if data == "covtype_binary"
    #     minibatchgrid = [2^0, 2^1, 2^2, 2^3, 2^4, 2^5, 2^6, 2^7, 2^8, 2^10, 2^12, 2^14, 2^16, 2^18, n]
    # elseif data == "ijcnn1_full" && lambda == 10^(-1)
    #     minibatchgrid = [2^0, 2^1, 2^2, 2^3, 2^4, 2^5, 2^6, 2^7, 2^8, 2^10, 2^12, 2^14, 2^16, n]
    # elseif data == "real-sim"
    #     minibatchgrid = [2^0, 2^1, 2^2, 2^3, 2^4, 2^5, 2^6, 2^7, 2^8, 2^10, 2^12, 2^14, 2^16]
    # else
    #     minibatchgrid = [2^0, 2^1, 2^2, 2^3, 2^4, 2^5, 2^6, 2^7, 2^8, 2^10, 2^12, 2^14]
    # end

    ## Try first a unique grid
    # minibatchgrid = [2^0, 2^1, 2^2]
    minibatchgrid = [2^0, 2^1, 2^2, 2^3, 2^4, 2^5, 2^6, 2^7, 2^8, 2^10, 2^12, 2^14]

    println("---------------------------------- MINI-BATCH GRID ------------------------------------------")
    println(minibatchgrid)
    println("---------------------------------------------------------------------------------------------")

    OUTPUTS, itercomplex = simulate_Free_SVRG_nice(prob, minibatchgrid, options, numsimu=numsimu, skip_multiplier=skip_multipliers[idx_prob], path=save_path)

    ## Checking that all simulations reached tolerance
    fails = [OUTPUTS[i].fail for i=1:length(minibatchgrid)*numsimu]
    if all(s->(string(s)=="tol-reached"), fails)
        println("Tolerance always reached")
    else
        println("Some total complexities might be threshold because of reached maximal time")
    end

    ## Computing the empirical complexity
    empcomplex = reshape([OUTPUTS[i].epochs[end] for i=1:length(minibatchgrid)*numsimu], length(minibatchgrid)) # number of stochastic gradients computed
    min_empcomplex, idx_min = findmin(empcomplex)
    b_empirical = minibatchgrid[idx_min]

    ## Saving the result of the simulations
    probname = replace(replace(prob.name, r"[\/]" => "-"), "." => "_")
    savename = string(probname, "-exp1a-$(machine)-", numsimu, "-avg")
    savename = string(savename, "_skip_mult_", replace(string(skip_multipliers[idx_prob]), "." => "_")) # Extra suffix to check which skip values to keep
    if numsimu == 1
        save("$(save_path)data/$(savename).jld",
        "options", options, "minibatchgrid", minibatchgrid,
        "itercomplex", itercomplex, "empcomplex", empcomplex,
        "b_theoretical", b_theoretical, "b_empirical", b_empirical)
    end

    ## Plotting total complexity vs mini-batch size
    legendpos = :topleft
    pyplot()
    exp_number = 1 # grid of mini-batch sizes
    plot_empirical_complexity_Free_SVRG(prob, exp_number, minibatchgrid, empcomplex, b_theoretical, b_empirical, save_path, skip_multiplier=skip_multipliers[idx_prob], legendpos=legendpos, suffix="-$(machine)")

    println("Theoretical optimal mini-batch = ", b_theoretical)
    println("Empirical optimal mini-batch = ", b_empirical, "\n\n")
end
end

println("\n\n--- EXPERIMENT 1A FINISHED ---")