function boot_CMcoord(prob::Prob,method::Method, options::MyOptions)
    # embeddim = convert(Int64,min(20,ceil(prob.numfeatures/2)));
    # embeddim = min(method.numinneriters,embeddim);
    # embeddim = convert(Int64,ceil(prob.numfeatures/1.0));
    # println("embeddim: ",embeddim)
    embeddim = convert(Int64, options.aux);
    method.S = zeros(embeddim);# contains current embedding matrix,
    method.diffpnt = zeros(prob.numfeatures);
    method.prevx = zeros(prob.numfeatures);
    # method.prevx = zeros(prob.numfeatures,embeddim+1);# 1st position contain previous outer iterate, the 2:embedded contain the previous embedding matrix
    method.H = zeros(embeddim,embeddim);  # Store the curvature matrix STHS
    method.HS = zeros(prob.numfeatures, embeddim);
    method.HSi = zeros(prob.numfeatures, embeddim);
    method.SHS = zeros(embeddim, embeddim);  # Store the local curvature matrix STHS
    method.name = string("CMcoord-", embeddim);#-",options.batchsize);
    method.gradsperiter = (embeddim + 2)*options.batchsize + (embeddim + 2)*prob.numdata/method.numinneriters + 1; #includes the cost of performing the Hessian vector product.
    method.stepmethod = descent_CMcoord;
    method.aux = zeros(embeddim);
    if(options.precondition)
        method.name = string(method.name, "-qN");
    end
    return method;
end