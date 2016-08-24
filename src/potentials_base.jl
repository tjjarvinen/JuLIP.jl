


# ===========================================================================
#     implement some fun little macros for easier access
#     to the potentials
# ===========================================================================

# Julia 0.4 version:
# call(pp::Potential, varargs...) = evaluate(pp, varargs...)
# call(pp::Potential, ::Type{Val{:D}}, varargs...) = evaluate_d(pp, varargs...)
# call(pp::Potential, ::Type{Val{:DD}}, varargs...) = evaluate_dd(pp, varargs...)
# call(pp::Potential, ::Type{Val{:GRAD}}, varargs...) = grad(pp, varargs...)

# unfortunately, in 0.5 `call` doesn't take an abstract argument anymore,
# which means that we need to specify for every potential how to
# create this syntactic sugar. This is what `@pot` is for.

"""
Annotate a type decaration with `@pot` to setup the syntax sugar
for `evaluate, evaluate_d, evaluate_dd, grad`.

## Usage:

The declaration
```julia
@pot type LennardJonesPotential <: PairPotential
   r0::Float64
end
```
creates the following aliases:
```julia
lj = LennardJonesPotential(1.0)
lj(args...) = evaluate(lj, args...)
@D lj(args...) = evaluate_d(lj, args...)
@DD lj(args...) = evaluate_dd(lj, args...)
@GRAD lj(args...) = grad(lj, args...)
```
"""
macro pot(fsig)
   @assert fsig.head == :type
   tname, tparams = t_info(fsig.args[2])
   tname = esc(tname)
   for n = 1:length(tparams)
      tparams[n] = esc(tparams[n])
   end
   sym = esc(:x)
   return quote
      $(esc(fsig))
      ($sym::$tname){$(tparams...)}(args...) = evaluate($sym, args...)
      ($sym::$tname){$(tparams...)}(::Type{Val{:D}}, args...) = evaluate_d($sym, args...)
      ($sym::$tname){$(tparams...)}(::Type{Val{:DD}}, args...) = evaluate_dd($sym, args...)
      ($sym::$tname){$(tparams...)}(::Type{Val{:GRAD}}, args...) = grad($sym, args...)
   end
end


# t_info extracts type name as symbol and type parameters as an array
t_info(ex::Symbol) = (ex, tuple())
t_info(ex::Expr) = ex.head == :(<:) ? t_info(ex.args[1]) : (ex, ex.args[2:end])

# --------------------------------------------------------------------------

# next create macros that translate
"""
`@D`: Use to evaluate the derivative of a potential. E.g., to compute the
Lennard-Jones potential,
```julia
lj = LennardJonesPotential()
r = 1.0 + rand(10)
ϕ = lj(r)
ϕ' = @D lj(r)
```
see also `@DD`.
"""
macro D(fsig::Expr)
    @assert fsig.head == :call
    insert!(fsig.args, 2, Val{:D})
    for n = 1:length(fsig.args)
        fsig.args[n] = esc(fsig.args[n])
    end
    return fsig
end

"`@DD` : analogous to `@D`"
macro DD(fsig::Expr)
    @assert fsig.head == :call
    for n = 1:length(fsig.args)
        fsig.args[n] = esc(fsig.args[n])
    end
    insert!(fsig.args, 2, Val{:DD})
    return fsig
end

"`@GRAD` : analogous to `@D`, but escapes to `grad`"
macro GRAD(fsig::Expr)
    @assert fsig.head == :call
    for n = 1:length(fsig.args)
        fsig.args[n] = esc(fsig.args[n])
    end
    insert!(fsig.args, 2, Val{:GRAD})
    return fsig
end



# ===============================
#    Potential Arithmetic

# TODO: revisit this idea:
# # scalars as potentials
# evaluate(x::Real, r::Float64) = x
# evaluate_d(x::Real, r::Float64) = 0.0
#
#
# "basic building block to generate potentials"
# type r_Pot <: PairPotential end
# evaluate(p::r_Pot, r) = r
# evaluate_d(p::r_Pot, r) = 1


# "sum of two pair potentials"
@pot type SumPot{P1, P2}
   p1::P1
   p2::P2
end
import Base.+
+(p1::PairPotential, p2::PairPotential) = SumPot(p1, p2)
evaluate(p::SumPot, r) = p.p1(r) + p.p2(r)
evaluate_d(p::SumPot, r) = (@D p.p1(r)) + (@D p.p2(r))
cutoff(p::SumPot) = max(cutoff(p.p1), cutoff(p.p2))
function Base.print(io::Base.IO, p::SumPot)
   print(io, p.p1)
   print(io, " + ")
   print(io, p.p2)
end

# "product of two pair potentials"
@pot type ProdPot{P1, P2} <: PairPotential
   p1::P1
   p2::P2
end
import Base.*
*(p1::PairPotential, p2::PairPotential) = ProdPot(p1, p2)
evaluate(p::ProdPot, r) = p.p1(r) * p.p2(r)
evaluate_d(p::ProdPot, r) = (p.p1(r) * (@D p.p2(r)) + (@D p.p1(r)) * p.p2(r))
cutoff(p::ProdPot) = min(cutoff(p.p1), cutoff(p.p2))
function Base.print(io::Base.IO, p::ProdPot)
   print(io, p.p1)
   print(io, " * ")
   print(io, p.p2)
end

# expand usage of prodpot to be useful for TB
evaluate{P1,P2}(p::ProdPot{P1,P2}, r, R) = p.p1(r, R) * p.p2(r, R)
evaluate_d(p::ProdPot, r, R) = (p.p1(r, R) * (@D p.p2(r, R)) + (@D p.p1(r, R)) * p.p2(r, R))