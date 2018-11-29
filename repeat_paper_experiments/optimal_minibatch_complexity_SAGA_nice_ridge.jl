srand(1);

using JLD
using Plots
using StatsBase
using Match
using Combinatorics

include("./src/StochOpt.jl") # Be carefull about the path here


### LOADING DATA ###
data = "YearPredictionMSD"; # libsvm regression dataset | "gaussian", "diagonal" or "lone_eig_val" for artificaly generated data

# If probname="artificial", precise the number of features and data
numdata = 500;
numfeatures = 12; # useless for gen_diag_data

println("--- Loading data ---");
datasets = ["YearPredictionMSD", "abalone", "housing"];
#, "letter_scale", "heart", "phishing", "madelon", "a9a",
# "mushrooms", "phishing", "w8a", "gisette_scale",
if(data == "gaussian")
    ## Load artificial data
    X, y, probname = gen_gauss_data(numfeatures, numdata, lambda=0.0, err=0.001);
elseif(data == "diagonal")
    X, y, probname = gen_diag_data(numdata, lambda=0.0, Lmax=100);
elseif(data == "lone_eig_val")
    X, y, probname = gen_diag_lone_eig_data(numfeatures, numdata, lambda=0.0, a=100, err=0.001);
elseif(data in datasets)
    probname = data;
    ## Load truncated LIBSVM data
    X, y = loadDataset(probname);
    # X = X';
    # numfeatures = size(X)[1];
    # numdata = size(X)[2];
    # y = convert(Array{Float64}, 1:1:size(X)[2]) ; # 14 data taken from X instead of 690
else
    error("unkown problem name.");
end

### SETTING UP THE PROBLEM ###
println("\n--- Setting up the ridge regression problem ---");
options = set_options(max_iter=10^8, max_time=10.0, max_epocs=1000, repeat_stepsize_calculation=true, skip_error_calculation=51,
                      force_continue=true, initial_point="randn", batchsize=0);
prob = load_ridge_regression(X, y, probname, options, lambda=-1, scaling="none");  # Disabling scaling
# QUESTION: how is lambda selected?
n = prob.numdata;
d = prob.numfeatures;

### PLOTTING SETTINGS ###
println("\n--- Ploting upper bounds of the expected smoothness constant ---");
default_path = "./data/"; savename = replace(replace(prob.name, r"[\/]", "-"), ".", "_");
savenamecomp = string(savename);
fontsmll = 8; fontmed = 14; fontbig = 14;

### COMPUTING THE SMOOTHNESS CONSTANTS ###
# Compute the smoothness constants L, L_max, \cL, \bar{L}
datathreshold = 24; # if n is too large we do not compute the exact expected smoothness constant nor its relative quantities

mu = get_mu_str_conv(prob); # mu = minimum(sum(prob.X.^2, 1)) + prob.lambda;
L = get_LC(prob, collect(1:n)); # L = eigmax(prob.X*prob.X')/n + prob.lambda;
Li_s = get_Li(prob);
Lmax = maximum(Li_s); # Lmax = maximum(sum(prob.X.^2, 1)) + prob.lambda;
Lbar = mean(Li_s);


########################### EMPIRICAL UPPER BOUNDS OF THE EXPECTED SMOOTHNESS CONSTANT ###########################
#region
### COMPUTING THE BOUNDS
simplebound, bernsteinbound, heuristicbound, expsmoothcst = get_expected_smoothness_bounds(prob);

### PLOTING ###
println("\n--- Ploting upper bounds ---");
# PROBLEM: there is still a problem of ticking non integer on the xaxis
pyplot()
plot_expected_smoothness_bounds(prob, simplebound, bernsteinbound, heuristicbound, expsmoothcst);

# heuristic equals true expected smoothness constant for tau=1 and n as expected, else it is above as hoped
# heuristicbound .== expsmoothcst
# heuristicbound .> expsmoothcst
# simplebound[end] - heuristicbound[end]
# bernsteinbound[end] - simplebound[end]
#endregion
##################################################################################################################


##################################### EMPIRICAL UPPER BOUNDS OF THE STEPSIZES ####################################
#region
# TO BE DONE: implement grid-search for the stepsizes, i.e.
# 1) set a grid of stepsizes around 1/(4Lmax)
# 2) run several SAGA_nice on the same problem with different stepsize (average?)
# 3) pick the 'best' stepsize

### COMPUTING THE UPPER-BOUNDS OF THE STEPSIZES ###
simplestepsize, bernsteinstepsize, heuristicstepsize, expsmoothstepsize = get_stepsize_bounds(prob, simplebound, bernsteinbound, heuristicbound, expsmoothcst);

### PLOTING ###
println("\n--- Ploting stepsizes ---");
# PROBLEM: there is still a problem of ticking non integer on the xaxis
pyplot()
plot_stepsize_bounds(prob, simplestepsize, bernsteinstepsize, heuristicstepsize, expsmoothstepsize);
#endregion
##################################################################################################################


###################################### THEORETICAL OPTIMAL MINI-BATCH SIZES ######################################
#region
## Compute optimal mini-batch size
if typeof(expsmoothcst)==Array{Float64,2}
    LHS = 4*(1:n).*(expsmoothcst+prob.lambda)./mu;
    RHS = n + (n-(1:n)) .* (4*(Lmax+prob.lambda)/((n-1)*mu));
    exacttotalcplx = max.(LHS, RHS);
    _, opt_minibatch_exact = findmin(exacttotalcplx);
else
    opt_minibatch_exact = nothing;
end
## WARNING: Verify computations : should we add lambda????
opt_minibatch_simple = round(Int, 1 + (mu*(n-1))/(4*Lbar)); # One should not add again lambda since it is already taken into account in Lbar
opt_minibatch_bernstein = max(1, round(Int, 1 + (mu*(n-1))/(8*L) - (4/3)*log(d)*((n-1)/n)*(Lmax/(2*L)) )); ## WARNING: Verify computations : should we add lambda????
opt_minibatch_heuristic = round(Int, 1 + (mu*(n-1))/(4*L));
#endregion
##################################################################################################################


# ########################################### SAVNG RESULTS ########################################################
# save_SAGA_nice_constants(prob, data, simplebound, bernsteinbound, heuristicbound, expsmoothcst, 
#                          simplestepsize, bernsteinstepsize, heuristicstepsize, expsmoothstepsize,
#                          opt_minibatch_simple, opt_minibatch_bernstein, opt_minibatch_heuristic, 
#                          opt_minibatch_exact);
# ##################################################################################################################


######################################## EMPIRICAL OPTIMAL MINIBATCH SIZE ########################################
## Empirical stepsizes returned by optimal mini-batch SAGa with line searchs
# if(n <= datathreshold)
#     minibatchlist = 1:n;
# elseif(opt_minibatch_simple>2)
#     minibatchlist = [1; opt_minibatch_simple; opt_minibatch_heuristic; round(Int, (opt_minibatch_simple+n)/2); round(Int, sqrt(n)); n]#[collect(1:(opt_minibatch_simple+1)); n];
# else
#     minibatchlist = [collect(1:(opt_minibatch_heuristic+1)); round(Int, sqrt(n)); n];
# end

## For abalone dataset
# minibatchlist = [collect(1:10); 50; 100];
# minibatchlist = collect(1:8);

## For n=24
# minibatchlist = [collect(1:6); 12; 24];

## For n=5000
# minibatchlist = [1; 5; 10; 50; 100; 200; 1000; 5000];

## For n=500
# minibatchlist = collect(1:10);

## For YearPredictionMSD
minibatchlist = [1, 2, 3, 5, 10, 20, 50];
# minibatchlist = [10, 50, 100, 1000];


# minibatchlist = [100];
# minibatchlist = [1, 10, 50];
# minibatchlist = [50, 10, 1];

minibatchlist = [1];
# minibatchlist = [5, 1];
# minibatchlist = 5:-1:1;
# minibatchlist = [1];


# srand(1234);

numsimu = 1; # number of runs of mini-batch SAGA for averaging the empirical complexity

tic();
OUTPUTS, itercomplex = simulate_SAGA_nice(prob, minibatchlist, numsimu, tolerance=10.0^(-1));
toc();

## Checking that all simulations reached tolerance
fails = [OUTPUTS[i].fail for i=1:length(minibatchlist)*numsimu];
if all(s->(string(s)=="tol-reached"), fails)
    println("Tolerance always reached")
end

## Plotting one SAGA-nice simulation for each mini-batch size
if(numsimu==1)
    gr()
    # pyplot()
    plot_outputs_Plots(OUTPUTS, prob, options); # Plot and save output
end

## Computing the empirical complexity
# itercomplex -= 1; #-> should we remove 1 from itercomplex?
empcomplex = reshape(minibatchlist.*itercomplex, length(minibatchlist)); # tau times number of iterations
opt_minibatch_emp = minibatchlist[indmin(empcomplex)];

pyplot()
plot_empirical_complexity(prob, minibatchlist, empcomplex, 
                          opt_minibatch_simple, opt_minibatch_bernstein, 
                          opt_minibatch_heuristic, opt_minibatch_emp);


######################################### PRINTING CONSTANTS AND RESULTS #########################################
println("\nPROBLEM DIMENSIONS:");
println("   Number of datapoints = ", n); # n in the paper notation
println("   Number of features = ", d); # d in the paper notation

println("\nSimple optimal tau = ", opt_minibatch_simple);
println("Bernstein optimal tau = ", opt_minibatch_bernstein);
println("Heuristic optimal tau = ", opt_minibatch_heuristic);
println("The empirical optimal tau = ", opt_minibatch_emp);

# println("List of mini-batch sizes = ", minibatchlist);
println("\nEmpirical complexity = ", empcomplex);

# println("\nSMOOTHNESS CONSTANTS:");
# println("   Lmax = ", Lmax);
# println("   L = ", L);
# println("Li_s = ", Li_s);
# println("   Lbar = ", Lbar);
##################################################################################################################

















## DRAFTS ##

############################## AVERAGE ITERATION COMPLEXITIES THROUGH FITTING CURVES #############################
#region Extracting the average iteration complexity through average angle between the tolerance horizontal line and a fitted affine curve
# withintercept = true; # if true, then an intercept is fitted, else, there it is set to 0 
# itercomplex2 = [];
# if withintercept
#     alphahat = []; # value of the intercept 
# else
#     alphahat = zeros(length(minibatchlist)*numsimu); # null intercept
# end
# betahat = [];
# # betahat = Array{Float64, 2}(length(minibatchlist), numsimu);
# for i=1:length(minibatchlist)
#     println("Tau: ", minibatchlist[i]);
#     intercept = [];
#     slope = [];
#     for j=1:numsimu
#         output = OUTPUTS[(i-1)*numsimu+j];
#         xout = skipped_errors.*[0:(length(output.fs)-1);];
#         logyout = log.((output.fs'.-prob.fsol)./(output.fs[1].-prob.fsol));
#         logyout = reshape(logyout, size(logyout, 1));
#         # slope = [slope; sum(xout.*logyout)/sum(xout.^2)];
#         if withintercept
#             a, b = linreg(xout, logyout); # Linear regresion using OLS : y = a + b*x
#             intercept = [intercept; a];
#             slope = [slope; b];
#         else
#             ## Fitting a line without the intercept term with OLS
#             ## https://en.wikipedia.org/wiki/Simple_linear_regression#Simple_linear_regression_without_the_intercept_term_(single_regressor)
#             slope = [slope; sum(xout.*logyout)/sum(xout.^2)];
#         end
#     end
#     ## Storring the list of the intercepts (if not null) and slopes
#     if withintercept
#         alphahat = [alphahat; intercept];
#         betahat = [betahat; slope];
#     else
#         betahat = [betahat; slope];
#     end
#     # betahat = [betahat; slope];

#     ## Estimation of the iteration complexity
#     if withintercept
#         alphaavg = mean(alphahat);
#         betaavg = mean(betahat);
#         itercomplex2 = [itercomplex2; ceil((log(tolerance)-alphaavg)/betaavg)];
#     else
#         thetahat = sum(atan.(slope))/numsimu; # Obtaining the average theta (theta_i = tan(slope_i))
#         itercomplex2 = [itercomplex2; ceil(log(tolerance)/tan(thetahat))];
#     end
#     # thetahat = sum(atan.(slope))/numsimu;
#     # itercomplex2 = [itercomplex2; ceil(log(tolerance)/tan(thetahat))];
# end
# itercomplex2 = reshape(itercomplex2, (length(minibatchlist), 1) );
# println("Fitted line complexity: ", itercomplex2);
# println("Classical average complexity: ", itercomplex);
#endregion

#region Plotting the simualtions and the fitted lines for a chosen mini-batch size
# tauidx = 1;
# ## FindinLongest simulation x-axis
# longetsxout = [0];
# for j=1:numsimu
#     output = OUTPUTS[(tauidx-1)*numsimu+j];
#     xout = skipped_errors.*[0:(length(output.fs)-1);];
#     if xout[end] > longetsxout[end]
#         longetsxout = xout
#     end
# end
# pyplot()
# output = OUTPUTS[(tauidx-1)*numsimu+1];
# xout = skipped_errors.*[0:(length(output.fs)-1);];
# logyout = log.((output.fs'.-prob.fsol)./(output.fs[1].-prob.fsol));
# colorlist = distinguishable_colors(7);
# p = plot(xout, logyout, line=(2,:dash), label="simu #1", c=colorlist[1], legend=:topright);
# plot!(p, longetsxout, alphahat[(tauidx-1)*numsimu+1] + betahat[(tauidx-1)*numsimu+1].*longetsxout, 
#           line=(4,:solid), c=colorlist[1], label="lin approx #1", xlabel="iterations", 
#           ylabel="log(residual)", title=string("\$", output.name, "\$"));
# for j=2:numsimu
#     println(j);
#     output = OUTPUTS[(tauidx-1)*numsimu+j];
#     xout = skipped_errors.*[0:(length(output.fs)-1);];
#     logyout = log.((output.fs'.-prob.fsol)./(output.fs[1].-prob.fsol));
#     ## Plotting the SAGA-nice simulation
#     plot!(p, xout, logyout, line=(2,:dash), c=colorlist[j], label=string("simu #", j));
#     ## Plotting the corresponding fitted line
#     plot!(p, longetsxout, alphahat[(tauidx-1)*numsimu+j] + betahat[(tauidx-1)*numsimu+j].*longetsxout, 
#           line=(4,:solid), c=colorlist[j], label=string("lin approx #", j));
# end
# plot!(p, longetsxout, fill(log(tolerance), length(xout)), line=(2,:dot), c=:black, label="tol");
# xlims!((0, 1.4*longetsxout[end]));
# display(p);

# empcomplex2 = minibatchlist.*itercomplex2; # average angle version
#endregion
##################################################################################################################



################ ITERATION COMPLEXITIES THROUGH AVERAGED SIGNALS OF DIFFERENT SIZE (PB: FLAT TAIL) ###############
#region
# rel_loss_avg = [];
# for i=1:length(minibatchlist)
#     rel_loss_array = [];
#     for j=1:numsimu
#         # println("idx:", (i-1)*numsimu+j);
#         # println(OUTPUTS[(i-1)*numsimu+j].fs[1]);
#         rel_loss_array = [rel_loss_array; [(OUTPUTS[(i-1)*numsimu+j].fs'.-prob.fsol)./(OUTPUTS[(i-1)*numsimu+j].fs[1].-prob.fsol)]];
#     end

#     maxlength = maximum([length(rel_loss_array[j]) for j=1:numsimu]);
#     tmp = similar(rel_loss_array[1], maxlength, 0);
#     for j=1:numsimu
#         # resize vector Maybe 0 or NA instead of tolerance
#         tmp = hcat(tmp, vcat(rel_loss_array[j], fill(tolerance, maxlength-length(rel_loss_array[j]), 1)));
#     end
#     tmp = mean(tmp, 2);
#     rel_loss_avg = [rel_loss_avg; [tmp]];
# end

# output = OUTPUTS[1];
# epocsperiters = [OUTPUTS[i].epocsperiter for i=1:numsimu:length(OUTPUTS)];
# lfs = [length(rel_loss_avg[i]) for i=1:length(rel_loss_avg)];
# iterations = lfs.-1;
# datapassbnds = iterations.*epocsperiters;
# x_val = datapassbnds.*([collect(1:lfs[i]) for i=1:length(minibatchlist)])./lfs;
# x_val *= options.skip_error_calculation; # skipping error calculation changes the epochs scale

# pyplot()
# p = plot(x_val[1], rel_loss_avg[1],
#         # ylim = (minimum(collect(Iterators.flatten(rel_loss_avg))), 10*maximum(collect(Iterators.flatten(rel_loss_avg))));
#         xlabel="epochs", ylabel="residual", yscale=:log10, label=output.name,
#         linestyle=:auto, tickfont=font(fontsmll), guidefont=font(fontbig), legendfont=font(fontmed), 
#         markersize=6, linewidth=4, marker=:auto, grid=false); # getting error with "marker=:auto"
# for i=2:length(minibatchlist)
#     println(i);
#     output = OUTPUTS[1+(i-1)*numsimu];
#     plot!(p, x_val[i], rel_loss_avg[i],
#         xlabel="epochs", ylabel="residual", yscale=:log10, label=output.name,
#         linestyle=:auto, tickfont=font(fontsmll), guidefont=font(fontbig), legendfont=font(fontmed), 
#         markersize=6, linewidth=4, grid=false)
# end
# display(p)
# savenameempcomplex = string(savenamecomp, "epoc-rel-loss-$(numsimu)-avg");
# savefig("./figures/$(savenameempcomplex).pdf");
#endregion
##################################################################################################################

############################################ THEORETICAL COMPLEXITIES ############################################
#region

#===
### CREATING THE MINI-BATCH SIZE SEQUENCE ###
# tauseq = collect(1:14);
# tauseq = [1, 2, 3, 4, 5, 14];
# tauseq = cat(1, 1:4, 14);
# tauseq = [1, 2, 3, 3, 3, 4, 5, 5, 14]; # test uniqueness
# tauseq = [1, 5, 4, 3, 2, 14]; # test sorting

# tauseq = [1, 2, 3, numdata];
tauseq = [1, 2, 3, 4, 5];

# Sanity checks
tauseq = unique(sort(tauseq));
n = prob.numdata;
numtau = length(tauseq);
if(minimum(tauseq) < 1 || maximum(tauseq) > n)
    error("values of tauseq are out of range.");
end
println("\n--- Mini-batch sequence ---");
println(tauseq);

### COMPUTE SAGA-NICE THEORETIDCAL COMPLEXITIES ###
println("\n--- Compute SAGA-nice theoretical complexities (iteration and total) ---");
default_path = "./data/"; savename = replace(replace(prob.name, r"[\/]", "-"), ".", "_");
savenamecompperso = string(savename,"-complexities-nidham");
itercomp = 0.0; Lsides = 0.0; Rsides = 0.0;
try
    itercomp, Lsides, Rsides = load("$(default_path)$(savenamecompperso).jld", "itercomp", "Lsides", "Rsides");
    println("found ", "$(default_path)$(savenamecompperso).jld with itercomp\n", itercomp);
catch loaderror   # Calculate iteration complexity for all minibatchsizes
    println(loaderror);
    itercomp, Lsides, Rsides = calculate_complex_SAGA_nice(prob, options, tauseq);
    # L = eigmax(prob.X*prob.X')/prob.numdata+prob.lambda;
    # save("$(default_path)$(savenamecompperso).jld", "itercomp", itercomp, "Lsides", Lsides, "Rsides", Rsides);
end

println("Mini-batch size sequence:\n", tauseq)

## Total complexity equals the iteration complexity times the size of the batch
# totcomp = (itercomp').*(1:prob.numdata);
totcomp = (itercomp').*tauseq;

### PLOTING ###
println("\n--- Ploting complexities ??? ---");
pyplot() # pyplot
fontsmll = 8; fontmed = 14; fontbig = 14;
plot(tauseq, [totcomp itercomp'], label=["total complex" "iter complex"],
    linestyle=:auto, xlabel="batchsize", ylabel="complexity", tickfont=font(fontsmll),
    guidefont=font(fontbig), legendfont=font(fontmed), markersize=6, linewidth=4, marker=:auto,
    grid=false, ylim=(0, maximum(totcomp)+minimum(itercomp)), xticks=tauseq)
   ylim=(minimum(itercomp), maximum(totcomp)+minimum(itercomp))
# savefig("./figures/$(savenamecompperso).pdf");

# Comparing only the iteration complexities
## WARNING: Lsides is not exactly the expected smoothness cosntant but 4*\cL/mu !!
plot(tauseq, Lsides', ylabel="expected smoothness", xlabel="batchsize", tickfont=font(fontsmll),
    guidefont=font(fontbig), markersize=6, linewidth=4, marker=:auto, grid=false, legend=false,
    xticks=tauseq)
savenameexpsmooth = string(savenamecompperso, "-expsmooth");
# savefig("./figures/$(savenameexpsmooth).pdf");
===#
#endregion
##################################################################################################################