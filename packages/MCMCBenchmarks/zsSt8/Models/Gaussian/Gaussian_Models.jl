@model AHMCGaussian(y, N) = begin
    mu ~ Normal(0, 1)
    sigma ~ Truncated(Cauchy(0, 5), 0, Inf)
    y ~ MvNormal(Fill(mu, N), sigma)  # use `Fill(mu, N)` is memory freiendly
end

AHMCconfig = Turing.NUTS(2000, 1000, .85)

CmdStanGaussian = "
data {
  int<lower=0> N;
  vector[N] y;
}
parameters {
  real mu;
  real<lower=0> sigma;
}
model {
  mu ~ normal(0,1);
  sigma ~ cauchy(0,5);
  y ~ normal(mu,sigma);
}
"

CmdStanConfig = Stanmodel(
  name = "CmdStanGaussian", model=CmdStanGaussian, nchains=1,
  Sample(
    num_samples=1000, num_warmup=1000, adapt=CmdStan.Adapt(delta=0.8),
    save_warmup=true
  )
)

struct GaussianProb{TY <: AbstractVector}
    "Observations."
    y::TY
end

function (problem::GaussianProb)(θ)
    @unpack y = problem   # extract the data
    @unpack mu, sigma = θ
    N = length(y)
    logpdf(MvNormal(Fill(mu, N), sigma), y) + logpdf(Normal(0, 1), mu) +
      logpdf(Truncated(Cauchy(0, 5), 0, Inf), sigma)
end

# Define problem with data and inits.
function sampleDHMC(obs,N,nsamples)
  p = GaussianProb(obs);
  p((mu=0.0, sigma=1.0))

  # Write a function to return properly dimensioned transformation.
  problem_transformation(p::GaussianProb) =
      as((mu=as(Real, -25, 25), sigma=asℝ₊), )

  # Use Flux for the gradient.

  P = TransformedLogDensity(problem_transformation(p), p)
  ∇P = LogDensityRejectErrors(ADgradient(:ForwardDiff, P));

  # FSample from the posterior.
  chain, NUTS_tuned = NUTS_init_tune_mcmc(∇P, 2000,report=ReportSilent());

  # Undo the transformation to obtain the posterior from the chain.
  posterior = TransformVariables.transform.(Ref(problem_transformation(p)), get_position.(chain));
  chns = nptochain(posterior, chain, NUTS_tuned)
  return chns
end

simulateGaussian(; μ=0, σ=1, Nd, kwargs...) = (y=rand(Normal(μ, σ), Nd), N=Nd)
