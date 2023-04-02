module GrpCoh

using Oscar
import Oscar:action
import Oscar:GAPWrap, pc_group, direct_product, direct_sum
import AbstractAlgebra: Group, Module
import Base: parent

function __init__()
  Hecke.add_verbose_scope(:GroupCohomology)
  Hecke.add_assert_scope(:GroupCohomology)

  Hecke.add_verbose_scope(:GaloisCohomology)
  Hecke.add_assert_scope(:GaloisCohomology)
end

######################################################################
#
# to allow additive notation for multiplicative objects,
# eg 
# M = MultGrp(K::AnticNumberField) will result in 
# M(a) + M(b) = M(ab)
#
# since the Gmodule stuff is strictly additive.
#
struct MultGrp{T} <: Oscar.Hecke.GrpAb
  data::Any #should be like parent_type{T}
  elem_rep::T

  function MultGrp(L::S) where {S}
    return MultGrp(L, one(L))
  end
  function MultGrp(L, a::typ) where typ
    return new{typ}(L, a)
  end
end

function Base.show(io::IO, M::MultGrp)
  println(io, "multiplicative group of $(M.data)")
end

struct MultGrpElem{T} <: Oscar.Hecke.GrpAbElem
  data::T
  parent::MultGrp{T}
end

function Base.show(io::IO, m::MultGrpElem)
  print(io, "$(m.data)")
end

(M::MultGrp{T})(a::T) where {T}  = MultGrpElem{T}(a, M)

Oscar.parent(a::MultGrpElem) = a.parent
Oscar.elem_type(a::MultGrp{T}) where T = MultGrpElem{T}

import Base: ==, +, -, *

*(a::Integer, b::MultGrpElem{T}) where T = MultGrpElem{T}(b.data^a, parent(b))
*(a::ZZRingElem, b::MultGrpElem{T}) where T = MultGrpElem{T}(b.data^a, parent(b))
+(a::MultGrpElem{T}, b::MultGrpElem{T}) where T = MultGrpElem{T}(a.data*b.data, parent(a))
-(a::MultGrpElem{T}, b::MultGrpElem{T}) where T = MultGrpElem{T}(a.data//b.data, parent(a))
-(a::MultGrpElem{T}) where T = MultGrpElem{T}(inv(a.data), parent(a))
==(a::MultGrpElem{T}, b::MultGrpElem{T}) where T = a.data == b.data
Base.hash(a::MultGrpElem, u::UInt = UInt(1235)) = hash(a.data. u)


##############################################################
#
# basic G-Modules:
# 
# a fin. gen group G acting on some module M 
# the action is given via maps (should be automorphisms of M)
#
# very little assumptions in general.
#
@attributes mutable struct GModule{gT,mT}
  G::gT
  M::mT
  ac::Vector{Map} # automorphisms of M, one for each generator of G

  function GModule(M, G::T, ac::Vector{<:Map}) where {T <: Oscar.GAPGroup}
    r = new{T,typeof(M)}()
    r.G = G
    r.ac = ac
    r.M = M
    @assert all(x -> domain(x) == codomain(x) == r.M, ac)
    @hassert :GroupCohomology 1 is_consistent(r)
    return r
  end


  function GModule(G::T, ac::Vector{<:Map}) where {T <: Oscar.GAPGroup}
    return GModule(domain(ac[1]), G, ac)
  end

  F::Group # G as an Fp-group (if set)
  mF::GAPGroupHomomorphism  # F -> G, maps F[i] to G[i]

  iac::Vector{Map} # the inverses of ac
end

function Base.show(io::IO, C::GModule)
  print(io, C.G, " acting on ", C.M, "\nvia: ", C.ac)
end

"""
Given an automorphism of some module for each generator of the
group `H`, return the `ZZ[H]` module.

Note: we do not check that this defined indeed a `ZZ[H]` module.
"""
function gmodule(H::Oscar.GAPGroup, ac::Vector{<:Map})
  return GModule(H, ac)
end

#in case the group is trivial, (ngens == 0), then length(ac)=0
#and the modules cannot be inferred. Thus a version with the
#module...
function gmodule(M, H::Oscar.GAPGroup, ac::Vector{<:Map})
  return GModule(M, H, ac)
end

"""
Checks if the action maps satisfy the same relations 
as the generators of `G`.
"""  
function is_consistent(M::GModule)
  G, mG = fp_group(M)
  V = Module(M)
  R = relators(G)
  for r = R
    w = word(r)
    a = action(M, mG(w[1]< 0 ? inv(gen(G, -w[1])) : gen(G, w[1])))
    for i=2:length(w)
      a = a* action(M, mG(w[i]< 0 ? inv(gen(G, -w[i])) : gen(G, w[i])))
    end
    all(x->a(x) == x, gens(V)) || (@show r; return false)
  end

  return true
end
##########################################################
#
# Basics for gmodules
#
# access and action
#
AbstractAlgebra.Group(C::GModule) = C.G
AbstractAlgebra.Module(C::GModule) = C.M
action(C::GModule) = C.ac

function inv_action(C::GModule)
  if !isdefined(C, :iac)
    C.iac = map(inv, C.ac)
  end
  return C.iac
end

function fp_group(C::GModule)
  #TODO: better for PcGroup!!!
  if !isdefined(C, :F)
    if order(Group(C)) == 1
      C.F = free_group(0)
      C.mF = hom(C.F, Group(C), gens(C.F), elem_type(Group(C))[])
    else
      C.F, C.mF = fp_group(gens(Group(C)))
    end
  end
  return C.F, C.mF
end

#TODO? have a GModuleElem and action via ^?
"""
For an array of objects in the module, compute the image under the 
action of `g`, ie. an array where each entry is mapped.
"""
function action(C::GModule, g, v::Array)
  @assert parent(g) == Group(C)

  ac = action(C)
  f = findfirst(isequal(g), gens(Group(C)))
  if f !== nothing
    return map(ac[f], v)
  end

  iac = inv_action(C)
  f = findfirst(isequal(inv(g)), gens(Group(C)))
  if f !== nothing
    return map(iac[f], v)
  end

  F, mF = fp_group(C)
  for i = word(preimage(mF, g))
    if i > 0
      v = map(ac[i], v)
    else
      v = map(iac[-i], v)
    end
  end
  return v
end

"""
The image of `v` under `g`
"""
function action(C::GModule, g, v)
  return action(C, g, [v])[1]
end

"""
The operation of `g` on the module as an automorphism.
"""
function action(C::GModule, g)
  @assert parent(g) == Group(C)

  ac = action(C)
  G = Group(C)
  f = findfirst(isequal(g), gens(G))
  if f !== nothing
    return ac[f]
  end
  iac = inv_action(C)
  f = findfirst(isequal(inv(g)), gens(G))
  if f !== nothing
    return iac[f]
  end

  F, mF = fp_group(C)
  h = id_hom(C.M)
  for i = word(preimage(mF, g))
    if i > 0
      h = h*ac[i]
#      v = map(ac[i], v)
    else
      h = h*iac[-i]
#      v = map(iac[-i], v)
    end
  end
  return h
end


"""
For a Z[U]-Module C and a map U->G, compute the induced module:
    ind_U^G(C) = C otimes Z[G]
where the tensor product is over Z[U].
The induced module is returned as a product of copies of C. it also returns
  - the transversal used
  - the projections
  - the injections

  If D and mDC are given then mDC: D -> C.M has to be a Z[U] linear
homomorphism. I this case a Z[G] linear map to the induced module
is returned.
"""
function induce(C::GModule, h::Map, D = nothing, mDC = nothing)
  U = domain(h)
  G = codomain(h)
  @assert U == C.G
  @assert D === nothing || mDC !== nothing
  @assert D === nothing || (domain(mDC) == D.M && codomain(mDC) == C.M &&
                            D.G == codomain(h))
  iU = image(h)[1]

# ra = right_coset_action(G, image(h)[1]) # will not always match 
# the transversal, so cannot use. There is a PR in Gap to return "both"
  g = right_transversal(G, iU)
  S = symmetric_group(length(g))
  ra = hom(G, S, [S([findfirst(x->x*inv(z*y) in iU, g) for z = g]) for y in gens(G)])

  #= C is Z[U] module, we needd
    C otimes Z[G]

    any pure tensor c otimes g can be "normalised" g = u*g_i for one of the 
    reps fixed above, so c otimes g = c otimes u g_i == cu otimes g_i

    For the G-action we thus get
    (c otimes g_i)g = c otimes g_i g = c otimes u_i g_j (where the j comes
                                                         from the coset action)
                    = cu_i otimes g_j
  =#                  

  @assert isdefined(C.M, :hnf)
  indC, pro, inj = direct_product([C.M for i=1:length(g)]..., task = :both)
  @assert isdefined(indC, :hnf)
  AbstractAlgebra.set_attribute!(indC, :induce => (h, g))
  ac = []
  iac = []
  for s = gens(G)
    sigma = ra(s)
    u = [ g[i]*s*g[i^sigma]^-1 for i=1:length(g)]
    @assert all(x->x in iU, u)
    im_q = []
    for q = gens(indC)
      push!(im_q, sum(inj[i^sigma](action(C, preimage(h, u[i]), pro[i](q))) for i=1:length(g)))
    end
    push!(ac, hom(indC, indC, [x for x = im_q]))

    s = inv(s)
    sigma = ra(s)
    u = [ g[i]*s*g[i^sigma]^-1 for i=1:length(g)]
    @assert all(x->x in iU, u)
    im_q = []
    for q = gens(indC)
      push!(im_q, sum(inj[i^sigma](action(C, preimage(h, u[i]), pro[i](q))) for i=1:length(g)))
    end
    push!(iac, hom(indC, indC, [x for x = im_q]))

  end
  iC = GModule(G, [x for x = ac])
  iC.iac = [x for x = iac]
  if D === nothing
    return iC, g, pro, inj
  end
  #= for a Z[G]-modul D s.th. D has a Z[U]-lin embedding into C,
    compute the Z[G]-lin embedding into the induced module.
    a -> sum a g_i^-1 otimes g_i
    works (direct computation with reps and cosets)
  =#
  h = hom(D.M, iC.M, [sum(inj[i](mDC(action(D, inv(g[i]), h))) for i=1:length(g)) for h = gens(D.M)])
  return iC, h    
end

function Oscar.quo(C::GModule, mDC::Map{GrpAbFinGen, GrpAbFinGen})
  q, mq = Oscar.quo(C.M, image(mDC)[1])
  S = GModule(C.G, [GrpAbFinGenMap(pseudo_inv(mq)*x*mq) for x = C.ac])
  if isdefined(C, :iac)
    S.iac = [GrpAbFinGenMap(pseudo_inv(mq)*x*mq) for x = C.iac]
  end
  return S, mq
end

function Oscar.direct_product(C::GModule...; task::Symbol = :none)
  @assert task in [:sum, :prod, :both, :none]
  G = C[1].G
  @assert all(x->x.G == G, C)
  mM, pro, inj = direct_product([x.M for x = C]..., task = :both)

  mC = gmodule(G, [direct_sum(mM, mM, [action(C[i], g) for i=1:length(C)]) for g = gens(G)])
  mC.iac = [direct_sum(mM, mM, [action(C[i], inv(g)) for i=1:length(C)]) for g = gens(G)]

  if task == :none
    return mC
  elseif task == :sum
    return mC, inj
  elseif task == :prod
    return mC, pro
  else
    return mC, pro, inj
  end
end

function Oscar.restrict(C::GModule, U::Oscar.GAPGroup)
  fl, m = is_subgroup(U, C.G)
  @assert fl
  return gmodule(U, [action(C, m(g)) for g = gens(U)])
end
function Oscar.restrict(C::GModule, m::Map)
  U, mU = image(m)
  return gmodule(U, [action(C, mU(g)) for g = gens(U)])
end

function Oscar.inflate(C::GModule, h)
  G = domain(h)
  U = codomain(h)
  @assert U == group(C)
  return gmodule(G, [action(C, h(g)) for g = gens(G)])
end

export GModule, gmodule, word, fp_group, confluent_fp_group, induce,
       action, cohomology_group, extension, pc_group,
       induce


Oscar.dim(C::GModule) = rank(C.M)
Oscar.base_ring(C::GModule) = base_ring(C.M)
Oscar.group(C::GModule) = C.G

###########################################################
#
# Supporting group theory
# To be moved and revised eventually
###########################################################

"""
Compute an fp-presentation of the group generated by 'g'
and returns both the group and the map from the new group to the
parent of the generators.
"""
function fp_group(g::Vector{<:Oscar.GAPGroupElem})
  G = parent(g[1])
  @assert all(x->parent(x) == G, g)
  X = GAP.Globals.IsomorphismFpGroupByGenerators(G.X, GAPWrap.GeneratorsOfGroup(G.X))
  F = FPGroup(GAPWrap.Range(X))
  return F, GAPGroupHomomorphism(F, G, GAP.Globals.InverseGeneralMapping(X))
end

"""
For an element of an fp-group, return a corresponding word as a sequence
of integers. A positive integers indicates the corresponding generator, 
a negative one the inverse.
"""
function word(y::FPGroupElem)
  # TODO: get rid of this
  return letters(y)
end

"""
The relations defining 'F' as an array of pairs.
"""
function Oscar.relations(F::FPGroup)
  R = relators(F)
  z = one(free_group(F))
  return [(x, z) for x = R]
end

function Oscar.relations(G::Oscar.GAPGroup)
   f = GAP.Globals.IsomorphismFpGroupByGenerators(G.X, GAPWrap.GeneratorsOfGroup(G.X))
   f !=GAP.Globals.fail || throw(ArgumentError("Could not convert group into a group of type FPGroup"))
   H = FPGroup(GAPWrap.Image(f))
   return relations(H)
end

function Oscar.relations(G::PcGroup)
   f = GAP.Globals.IsomorphismFpGroupByPcgs(GAP.Globals.FamilyPcgs(G.X), GAP.Obj("g"))
   f !=GAP.Globals.fail || throw(ArgumentError("Could not convert group into a group of type FPGroup"))
   H = FPGroup(GAPWrap.Image(f))
   return relations(H)
end

######################################################
#
#
# Main goal: cohomology computations.
#
# So "empty" structure for parent of co-chains and a co-chain.
# currently co-chains are dumb: the values need to all be known
# on creation. They should support lazy filling.
# Also possibly they should be "modules", ie. inherit addition
# and scalar multiplication (and possibly? the G-operation)
#

struct AllCoChains{N, G, M} #Int (dim), Group(elem), Module(elem)
end

struct CoChain{N, G, M}
  C::GModule
  d::Dict{NTuple{N, G}, M} 
end

function Base.show(io::IO, C::CoChain{N}) where {N}
  print(io, "$N-cochain with values in ", C.C.M)
end

Oscar.Nemo.elem_type(::AllCoChains{N,G,M}) where {N,G,M} = CoChain{N,G,M}
Oscar.Nemo.elem_type(::Type{AllCoChains{N,G,M}}) where {N,G,M} = CoChain{N,G,M}
Oscar.Nemo.parent_type(::CoChain{N,G,M})  where {N,G,M}= AllCoChains{N,G,M}
Oscar.parent(::CoChain{N,G,M}) where {N, G, M} = AllCoChains{N, G, M}()

"""
Evaluate a 0-cochain
"""
(C::CoChain{0})() = first(values(C.d))

#TODO: should this rather be a map from a 1-tuple of group elements?
"""
Evaluate a 1-cochain, a 1-cochain is a map from the group into the
module
"""
function (C::CoChain{1})(g::Oscar.BasicGAPGroupElem)
  if haskey(C.d, (g,))
    return C.d[(g,)]
  end
  F, mF = fp_group(C.C)
  G = parent(g)
  @assert G == group(C.C)
  @assert ngens(F) == ngens(G)
  @assert all(i->mF(gen(F, i)) == gen(G, i), 1:ngens(G))
  w = word(preimage(mF, g))
  t = zero(Module(C.C))
  ac = action(C.C)
  iac = inv_action(C.C)
  G = Group(C.C)
  #TODO: build up the group element step by step
  #      and store the values: (use Dimino code in Hecke)
  #XXX: this is wrong!, compare to the H_one code below
  # problem is that F and G might have different gens
  # needs different Gap code: write g as a word in the
  # generators of G and use this.
  # also inverses are more complicated.
  for i = w
    if i > 0
      t = ac[i](t)+C.d[(gen(G, i),)]
    else
      t = iac[-i](t-C.d[(gen(G, -i),)])
    end
  end
  C.d[(g,)] = t
  return t
end
(C::CoChain{1})(g::NTuple{1, <:Oscar.BasicGAPGroupElem}) = C(g[1])

#should support lazy via call-back.
"""
Evaluate a 2-cochain, a 2-cochain is a map from pairs of group elements
into the module
"""
function (C::CoChain{2})(g::Oscar.BasicGAPGroupElem, h::Oscar.BasicGAPGroupElem)
  if haskey(C.d, (g,h))
    return C.d[(g,h)]
  end
end
(C::CoChain{2})(g::NTuple{2, <:Oscar.BasicGAPGroupElem}) = C(g[1], g[2])

#TODO: re-write to get the maps! To support Q/Z as well
"""
  H^0(G, M)

Returns a module (same type as M) that abstractly represent
the 0-cohomology group as well as a map realizing this via explicit
co-chains
"""
function H_zero(C::GModule)
  z = get_attribute(C, :H_zero)
  if z !== nothing
    return domain(z), z
  end
  G = Group(C)
  M = Module(C)
  id = hom(M, M, gens(M))
  ac = action(C)
  k = kernel(id - ac[1])[1]
  for i=2:length(ac)
    k = intersect(k, kernel(id - ac[i])[1])
  end
  #this is fix, now it "should" be mod by norm?
  z = MapFromFunc(x->CoChain{0,elem_type(G),elem_type(M)}(C, Dict(() => x)), y->y(), k, AllCoChains{0,elem_type(G),elem_type(M)}())
  set_attribute!(C, :H_zero => z)
  return k, z
end

function H_zero_tate(C::GModule)
  z = get_attribute(C, :H_zero_tate)
  if z !== nothing
    return domain(z), z
  end
  G = Group(C)
  M = Module(C)
  #fix under action modulo norm (trace) = sum over all elem in group

  id = hom(M, M, gens(M))
  ac = action(C)
  k = kernel(id - ac[1])[1]
  for i=2:length(ac)
    k = intersect(k, kernel(id - ac[i])[1])
  end
  N = sum(action(C, g) for g = group(C))

  i = image(N)[1]
  fl, inj = is_subgroup(i, k)
  q, mq = quo(k, image(inj)[1])

  z = MapFromFunc(x->CoChain{0,elem_type(G),elem_type(M)}(C, Dict(() => x)), y->y(), q, AllCoChains{0,elem_type(G),elem_type(M)}())
  set_attribute!(C, :H_zero_tate => z)

  if isfinite(G) && isa(q, GrpAbFinGen)
    q.exponent = order(G)
  end

  return q, z
end


#= TODO
 - break out coboundaries and cochains
 - depending on the module type:
   - intersect yields an embedding (Z-module) or not GrpAb
   - make sure that image/ kernel are consistent
   - preimage 
   - issubset yields (for GrpAb) only true/ false, not the map
   - is_subgroup cannot apply to modules
   - quo does ONLY work if B is a direct submodule of A (Z-modules)
   - mat or matrix is used to get "the matrix" from a hom
   - zero_hom/ zero_obj/ identity_hom is missing
   - Janko-Module-Homs have different types, they probably need to
     come under a common abstract type or be more selective
=#


"""
Code of the H^1(G, M) computation:
returns homomorphisms A and B s.th.

   M_1 -A-> M_2 -B-> M_3
  
satisfies
  
  H^1 = kern(B)/image(A)

Or, kern(B) are the 1-co-chains, image(A) the 1-co-boundaries.

If M is a free abelian group (Z^n), then this is used in the solvable
quotient to compute the H^1 of Q^n/Z^n via duality.
"""
function H_one_maps(C::GModule; task::Symbol = :maps)
  @assert task in [:maps, :all]
  #= idea, after Holt:
  H^1 = crossed homs. due to action on the right
  f(ab) = f(a)^b + f(b)
  if G=<g_1, ..., g_r | r_1, ..., r_l>
  then X in H^1 iff X(r_i) = 0 for all i
  X:G->M is given as X in M^r, where X(g_i) = X[i]
  X(r_i) corresponds to some map phi_i : M^r -> M
  phi_i = oplus h_j M for some homs h_j coming from the word in r
  so, a kernel computation again
  =#

  G = Group(C)
  n = ngens(G)
  M = Module(C)
  D, pro, inj = direct_product([M for i=1:n]..., task = :both)

  F, mF = fp_group(C)
  @assert ngens(F) == ngens(G)
  @assert all(i->mF(gen(F, i)) == gen(G, i), 1:ngens(G))

  R = relators(F)
#  @assert G == F

  K = D
  ac = action(C)
  iac = inv_action(C)
  idM = hom(M, M, gens(M)) #identity map to start with
                           #TODO: require an identity_hom constructor

  Kr, pKr, iKr = direct_product([M for i=R]..., task = :both)
  gg = nothing
  i = 1
  for r = R
    W = word(r)
    g = idM
    P = hom(D, M, [zero(M) for i=1:ngens(D)])
    for w in W
      if w < 0
        #by above: f(ab) = f(a)^b + f(b)
        #thus      0 = f(1) = f(a a^-1) = f(a)^(a^-1) + f(a^-1)
        P = P*iac[-w]-pro[-w]*iac[-w]
        g = g*iac[-w]
      else
        P = P*ac[w]+pro[w]
        g = g*ac[w]
      end
    end
    @assert all(x -> x == g(x), gens(M))
    if gg === nothing
      gg = P*iKr[i]
    else
      gg += P*iKr[i]
    end
    i += 1
  end
  #K is Z[1]  - the co-cycles
  #TODO: is kernel(g) directly faster than the method above (H_zero)
  #      where kernel(g) is computed slice by slice?
  #TODO: cache the expensive objects!!!

  g = sum((ac[i] - idM)*inj[i] for i=1:n)
  if task == :all
    return g, gg, pro, inj, mF
  else
    return g, gg
  end
end

"""
  H^1(G, M)

Returns an abstract module (of the same type as M) describing the
first co-homology group. Furthermore, the second return value
is a map realising elements of H^1 as explicit co-cycles.
"""
function H_one(C::GModule)
  z = get_attribute(C, :H_one)
  if z !== nothing
    return domain(z), z
  end

  g, gg, pro, inj, mF = H_one_maps(C, task = :all)

  K = kernel(gg)[1]
  D = domain(gg)
  lf, lft = is_subgroup(K, D)
  @assert lf

  Q, mQ = quo(K, image(g)[1])

  M = Module(C)
  G = group(C)

  z = MapFromFunc(
    x->CoChain{1,elem_type(G),elem_type(M)}(C, Dict([(gen(G, i),) => pro[i](lft(preimage(mQ, x))) for i=1:ngens(G)])),
    y->mQ(preimage(lft, sum(inj[i](y(gen(G, i))) for i=1:n))), Q, AllCoChains{1, elem_type(G), elem_type(M)}())

  set_attribute!(C, :H_one => z)
  return Q, z    
  #need to ALSO return the coboundary(s)
end


function confluent_fp_group_pc(G::Oscar.GAPGroup)
   g = isomorphism(PcGroup, G)
   P = codomain(g)
   f = GAP.Globals.IsomorphismFpGroupByPcgs(GAP.Globals.FamilyPcgs(P.X), GAP.Obj("g"))
   f !=GAP.Globals.fail || throw(ArgumentError("Could not convert group into a group of type FPGroup"))
   H = FPGroup(GAPWrap.Image(f))
   R = relations(H)
   ru = Vector{Tuple{Vector{Int}, Vector{Int}}}()
   for r = R
     push!(ru, (map(Int, GAP.Globals.LetterRepAssocWord(r[1].X)), 
                map(Int, GAP.Globals.LetterRepAssocWord(r[2].X))))
  end
  i = 0
  ex = []
  for r = ru
    i += 1
    @assert length(r[2]) == 0
    if r[1][1] == r[1][2] #order relation!
      j = 3
      while j <= length(r[1]) && r[1][j] == r[1][1]
        j += 1
      end
      ru[i] = (r[1][1:j-1], -1 .* reverse(r[1][j:end]))
      r = ru[i]
      push!(ex, ([-r[1][1]], [r[1][1] for i=2:length(r[1])]))
    else #conjugator rel
      @assert r[1][1] < 0 && -r[1][1] == r[1][3]
      @assert r[1][2] < 0 && -r[1][2] == r[1][4]
      ru[i] = ([r[1][3], r[1][4]], vcat([r[1][4], r[1][3]], -1 .* reverse(r[1][5:end])))
    end
  end
  append!(ru, ex)

  return H, GAPGroupHomomorphism(H, P, GAP.Globals.InverseGeneralMapping(f))*inv(g), ru
end


"""
Computes an isomorphic fp-group and a confluent system of
relations given as pairs of words.

Returns the new group, the isomorphism and the confluent relations.
"""
function confluent_fp_group(G::Oscar.GAPGroup)
  C = GAP.Globals.ConfluentMonoidPresentationForGroup(G.X)
  #has different generators than G! So the action will have to
  #be adjusted to those words. I do not know if a RWS (Confluent) can
  #just be changed...
  k = C.monhom #[2] #hopefully the monhom entry in 4.12 it will be the name
  M = GAPWrap.Range(k)
  g = [GAP.Globals.PreImageElm(k, x) for x = GAP.Globals.GeneratorsOfMonoid(M)]
  g = map(GAPWrap.UnderlyingElement, g)
  g = map(GAP.Globals.LetterRepAssocWord, g)
  @assert all(x->length(x) == 1, g)
  g = map(x->Int(x[1]), g)
  R = GAP.Globals.RelationsOfFpMonoid(M)

  ru = Vector{Tuple{Vector{Int}, Vector{Int}}}()
  for r = R
    push!(ru, (map(x->g[Int(x)], GAP.Globals.LetterRepAssocWord(r[1])), 
               map(x->g[Int(x)], GAP.Globals.LetterRepAssocWord(r[2]))))
  end

  #now to express the new gens as words in the old ones:
  
  Fp = FPGroup(GAPWrap.Range(C.fphom))
  return Fp, GAPGroupHomomorphism(Fp, G, GAP.Globals.InverseGeneralMapping(C.fphom)), ru
end


#############################
#
# H^2
#
# Thought of as group extensions given via a rewriting system.
# so we need collection...
#
mutable struct CollectCtx
  r::Vector{Tuple{Vector{Int}, Vector{Int}}} #the rules, RWS

  d1::Dict{Int, Int} #rules where lhs has length 1

  d2::Dict{Tuple{Int, Int}, Vector{Int}} # length 2 prefixes

  f::Function #(w::Vector{Int}, r::Int, p::Int)
              #to be called in addition (to play with the tail(s))
              #w the word, to be "reduced" using rule no r at pos p

  T::Any
  function CollectCtx(R::Vector{Tuple{Vector{Int}, Vector{Int}}})
    n = new()
    n.r = R
    n.d1 = Dict{Int, Int}()
    n.d2 = Dict{Tuple{Int, Int}, Vector{Int}}()
    for i = 1:length(R)
      r = R[i]
      if length(r[1]) == 1
        #still confused about that one...
        # but I have a rule [-1] -> [1, 2]
#        @assert length(r[2]) == 1
        n.d1[r[1][1]] = i
        continue
      end
      @assert length(r[1]) > 1
      p = (r[1][1], r[1][2])
      if Base.haskey(n.d2, p)
        push!(n.d2[p], i)
      else
        n.d2[p] = [i]
      end
    end
    for p = keys(n.d2)
      sort!(n.d2[p], lt = (a,b) -> isless(R[a], R[b]))
    end
    return n
  end
end

function Base.collect(w::Vector{Int}, C::CollectCtx)
  d1 = C.d1
  d2 = C.d2
  R = C.r
  do_f = isdefined(C, :f)

  nc = 0
  i = 1
  while true
    nc += 1
    if i>length(w)
      return w
    end
    if haskey(d1, w[i])
      if do_f
        C.f(C, w, d1[w[i]], i)
      end
      w = vcat(w[1:i-1], R[d1[w[i]]][2], w[i+1:end])
      i = 1
      continue
    end

    if i>=length(w)
      return w
    end


    if haskey(d2, (w[i], w[i+1]))
      for r = d2[(w[i], w[i+1])]
        if length(R[r][1]) + i-1 <= length(w) &&
           R[r][1] == w[i:i+length(R[r][1])-1]
          if do_f
            C.f(C, w, r, i)
          end
          w = vcat(w[1:i-1], R[r][2], w[i+length(R[r][1]):end])
          i = 0
          break
        end
      end
    end
    i += 1
  end
  return w
end

#= Hulpke-Dietrich:
UNIVERSAL COVERS OF FINITE GROUPS
https://arxiv.org/pdf/1910.11453.pdf
almost the same as Holt
=#
function H_two(C::GModule; force_rws::Bool = false, redo::Bool = false)
  z = get_attribute(C, :H_two)
  if !redo && z !== nothing
    return domain(z[1]), z[1], z[2]
  end

  G = Group(C)
  M = Module(C)

  @vprint :GroupCohomology 1 "starting H^2 for group of size $(order(G)) and module with $(ngens(M)) gens\n"

  id = hom(M, M, gens(M), check = false)
  F, mF = fp_group(C) #mF: F -> G

  if !force_rws && (isa(G, PcGroup) || is_solvable(G))
    @vprint :GroupCohomology 2 "using pc-presentation ...\n"
    FF, mFF, R = confluent_fp_group_pc(G) #mFF: FF -> G
    use_pc = true
  else
    @vprint :GroupCohomology 2 "using generic rws ...\n"
    FF, mFF, R = confluent_fp_group_pc(G) #mFF: FF -> G
    FF, mFF, R = confluent_fp_group(G) #mFF: FF -> G
    use_pc = false
  end
  #now map the action generators (for gens(G)) to the gens for the RWS
  ac = []
  iac = []
  @vprint :GroupCohomology 2 "computing action for the gens in the rws..\n"
  @vtime :GroupCohomology 2 for g = gens(FF)
    f = action(C, mFF(g))
    push!(ac, f)
    #should we inv(f) or build inv f as a product as above???
    @vtime :GroupCohomology 3 push!(iac, inv(f))
  end

  c = CollectCtx(R)

  #rules with length(LHS) == 1 and rules of the form
  # [a a^-1] -> [], [a^-1 a] -> [] do not get tails
  pos = Vector{Int}()
  n = 0
  for i = 1:length(R)
    r = R[i]
    if length(r[1]) == 1
      push!(pos, 0)
      continue
    end
    if length(r[1]) == 2 && length(r[2]) == 0 && r[1][1] == -r[1][2]
      push!(pos, 0)
      continue
    end
    n += 1
    push!(pos, n)
  end

  @vprint :GroupCohomology 1 "need $n tails\n"

  if n == 0
    D = sub(M, elem_type(M)[])[1]
    pro = []
    inj = []
  else
    D, pro, inj = direct_product([M for i=1:n]..., task = :both)
  end
  

  #when collecting (i.e. applying the RWS we need to also
  #use the tails:  g v h -> gh h(v) 
  #and if [gh] -> [x] with tail t, then
  #       gh -> x t, so 
  #       g v h -> gh h(v) -> x t+h(v)
  # Hulpke calls this the normal version: reduced group word
  # at the beginning, module at the end, the tail.
  # collect will call the extra function c.f if set in the
  # CollectCtx
  # if use_rws we investigate all overlaps
  # otherwise, we know it a pc-presentation and thus fewer tests
  # are needed.
  function symbolic_collect(C::CollectCtx, w::Vector{Int}, r::Int, p::Int)
    #w = ABC and B == r[1], B -> r[2] * tail[r]
    # -> A r[2] C C(tail)
    # C = c1 c2 ... C(tail):
    @assert w[p:p+length(R[r][1])-1] == R[r][1]

    if pos[r] == 0
      return
    end
    T = pro[pos[r]]
    for i=w[p+length(R[r][1]):end]
      if i < 0
        T = T*iac[-i]
      else
        T = T*ac[i]
      end
    end
    C.T += T
  end
  c.f = symbolic_collect

  E = D
  all_T = []
  #need zero hom this is too slow
  Z = hom(D, M, [M[0] for i=1:ngens(D)], check = false)

  @vprint :GroupCohomology 2 "building relations...\n"
  for i = 1:length(R)
    r = R[i]
    for j=1:length(R)
#      i == j && continue
      s = R[j]
      #we want overlaps, all of them:
      #r[1] = AB, s[1] = BC this is what we need to find...
      #(then we call collect on r[2]C and As[2] they should agree)
      #if use_pc, then l can only be 1:
      #From Holt: those are the r[1] we need
      # (i i .. i)
      #   (i .. i i) 
      # (i .. i)
      #      (i j)
      # (i j)
      #  ( j ... j)
      # (i j)
      #   (j i)
      if use_pc
        l_max = 1
      else
        l_max = min(length(s[1]), length(r[1]))
      end

      for l=1:l_max
        if r[1][end-l+1:end] == s[1][1:l]
          #TODO  AB    -> Ss  s,t are tails
          #       BC   -> Tt
          #      (AB)C -> SsC -> SC C(s)
          #      A(BC) -> ATt -> AT t
          if pos[i] > 0 
            c.T = pro[pos[i]]
            for h = s[1][l+1:end]
              if h < 0
                c.T = c.T * iac[-h]
              else
                c.T = c.T * ac[h]
              end
            end
          else
            c.T = Z
          end
          z1 = collect(vcat(r[2], s[1][l+1:end]), c)
          T = c.T
          c.T = Z
          z2 = collect(vcat(r[1][1:end-l], s[2]), c)
          if pos[j] > 0
            c.T += pro[pos[j]]
          end
          @hassert :GroupCohomology 1 z1 == z2
          push!(all_T, T-c.T)
        end
      end
    end
  end

  @vprint :GroupCohomology 2 "found $(length(all_T)) relations\n"

  if length(all_T) == 0
    Q = sub(M, elem_type(M)[])[1]
    jinj = hom(M, Q, elem_type(Q)[Q[0] for m = gens(M)])
  else
    Q, jinj = direct_product([M for i in all_T]..., task = :sum)
  end
  if length(all_T) == 0
    mm = hom(D, Q, elem_type(Q)[Q[0] for i=1:ngens(D)], check = false)
  else
    mm = sum(all_T[i]*jinj[i] for i = 1:length(all_T))
  end
  @vprint :GroupCohomology 2 "computing 2-cycles...\n"
#  return mm;
  @vtime :GroupCohomology 2 E, mE = kernel(mm)
  @hassert :GroupCohomology 1 all(x->all(y->iszero(y(mE(x))), all_T), gens(E))
  @hassert :GroupCohomology 1 all(x->iszero(mm(mE(x))), gens(E))


  if length(ac) == 0
    B = sub(M, elem_type(M)[])[1]
    B_pro = []
    B_inj = []
  else
    B, B_pro, B_inj = direct_product([M for i=1:length(ac)]..., task = :both)
  end
  CC = hom(B, D, elem_type(D)[zero(D) for i=1:ngens(B)], check = false)
  for i=1:length(R)
    if pos[i] == 0
      continue
    end
    r = R[i]
    if false && length(r[1]) == 1
      continue
    end
    #we have words r[1] and r[2] of shape g_1 g_2 .... 
    #they need to be replaced by g_1 pro[1] g_2 pro[2]
    #and then sorted: g_1 pro[1] g_2 pro[2] ... ->
    #                 g_1 g_2 (pro[1] * g_2 + pro[2]) ...
    if r[1][1] < 0
      T = -B_pro[-r[1][1]]*iac[-r[1][1]]
    else
      T = B_pro[r[1][1]]
    end
    for j=2:length(r[1])
      if r[1][j] < 0
        T = (T-B_pro[-r[1][j]])*iac[-r[1][j]] 
      else
        T = T*ac[r[1][j]] + B_pro[r[1][j]]
      end
    end

    if length(r[2]) == 0
      S = hom(B, M, [M[0] for g = gens(B)], check = false)
    elseif r[2][1] < 0
      S = -B_pro[-r[2][1]]*iac[-r[2][1]]
    else
      S = B_pro[r[2][1]]
    end
    for j=2:length(r[2])
      if r[2][j] < 0
        S = (S-B_pro[-r[2][j]])*iac[-r[2][j]]
      else
        S = S*ac[r[2][j]] + B_pro[r[2][j]]
      end
    end

#    @assert issubset(image((T-S)*inj[pos[i]])[1], E)

    CC += (T-S)*inj[pos[i]]
  end
  @vprint :GroupCohomology 2 "now the 2-boundaries...\n"
  @vtime :GroupCohomology 2 i, mi = image(CC)
  @vprint :GroupCohomology 2 "and the quotient...\n"
  @vtime :GroupCohomology 2 H2, mH2 = quo(E, i)
  if isfinite(G) && isa(H2, GrpAbFinGen)
    H2.exponent = order(G)
  end
  #we know |G| is an exponent - this might help

  function TailFromCoChain(cc::CoChain{2})
    #for all tails, ie. rules with pos[r]>0, we need to use
    #the 2-chain to compute inv(r[2])*r[1]
    #rule with tail: r[1] = r[2]*t, so t = r[2]^-1*r[1]
    T = zero(D)
    for r=1:length(pos)
      if pos[r] == 0
        continue
      end
      t1 = zero(M)
      g1 = one(G)
      w = R[r][1]
      for i=1:length(w)
        if w[i] > 0
          t1 = ac[w[i]](t1)+cc(g1, mFF(gen(FF, w[i])))
          g1 = g1*mFF(gen(FF, w[i]))
        else
          #need to mult by (w, 0)^-1 = (w^-1, -cc(w, w^-1))
          #so (g, t) (w, 0)^-1 = (g w^-1, t^w^-1 - cc(w, w^-1) + cc(g, w^-1)
          t1 = iac[-w[i]](t1)-cc(mFF(gen(FF, -w[i])), inv(mFF(gen(FF, -w[i]))))+cc(g1, inv(mFF(gen(FF, -w[i]))))
          g1 = g1*mFF(inv(gen(FF, -w[i])))
        end
      end

      t2 = zero(M)
      g2 = one(G)
      w = R[r][2]
      for i=1:length(w)
        if w[i] > 0
          t2 = ac[w[i]](t2)+cc(g2, mFF(gen(FF, w[i])))
          g2 = g2*mFF(gen(FF, w[i]))
        else
          #need to mult by (w, 0)^-1 = (w^-1, -cc(w, w^-1))
          #so (g, t) (w, 0)^-1 = (g w^-1, t^w^-1 - cc(w, w^-1) + cc(g, w^-1)
          t2 = iac[-w[i]](t2)-cc(mFF(gen(FF, -w[i])), inv(mFF(gen(FF, -w[i]))))+cc(g2, inv(mFF(gen(FF, -w[i]))))
          g2 = g2*mFF(inv(gen(FF, -w[i])))
        end
      end
      @assert g1 == g2

      #=
      w = [-x for x = reverse(R[r][2])]
      append!(w, R[r][1])
      #w is inv(r[2])*r[1]

      t = zero(M)
      g = one(G)
      for i=1:length(w)
        if w[i] > 0
          t = ac[w[i]](t)+cc(g, mFF(gen(FF, w[i])))
          g = g*mFF(gen(FF, w[i]))
        else
          #need to mult by (w, 0)^-1 = (w^-1, -cc(w, w^-1))
          #so (g, t) (w, 0)^-1 = (g w^-1, t^w^-1 - cc(w, w^-1) + cc(g, w^-1)
          t = iac[-w[i]](t)-cc(mFF(gen(FF, -w[i])), inv(mFF(gen(FF, -w[i]))))+cc(g, inv(mFF(gen(FF, -w[i]))))
          g = g*inv(gen(G, -w[i]))
        end
      end
      #= Maybe? Not clear what I actually want/ need here, darn
      wrong currently...
      if length(R[r][2]) > 0
        r2 = R[r][2][1] < 0 ? inv(gen(FF, -R[r][2][1])) : gen(FF, R[r][2][1])
        for i=2:length(R[r][2])
          r2 *= R[r][2][i] < 0 ? inv(gen(FF, -R[r][2][i])) : gen(FF, R[r][2][i])
        end
      else
        r2 = one(FF)
      end
      @show r2, mFF(r2)
      t = t + cc(mFF(inv(r2)), mFF(r2))
      =#
      =#
      T += inj[pos[r]](t1-t2)
    end
    return T
  end

  function TailToCoChain(t)
    c.f = function(C::CollectCtx, w::Vector{Int}, r::Int, p::Int)
      #w = ABC and B == r[1], B -> r[2] * tail[r]
      # -> A r[2] C C(tail)
      # C = c1 c2 ... C(tail):
      @assert w[p:p+length(R[r][1])-1] == R[r][1]

      if pos[r] == 0
        return
      end
      T = pro[pos[r]](t)
      for i=w[p+length(R[r][1]):end]
        if i < 0
          T = iac[-i](T)
        else
          T = ac[i](T)
        end
      end
      C.T += T
    end

    di = Dict{NTuple{2, elem_type(G)}, elem_type(M)}()
    #= if I figure out how to extend from generators
    w = [word(order(G) == 1 ? one(domain(mFF)) : preimage(mFF, g)) for g = gens(G)]
    for i=1:ngens(G)
      for j=1:ngens(G)
        c.T = zero(M)
        collect(vcat(w[i], w[j]), c)
        di[(gen(G, i), gen(G, j))] = c.T
      end
    end
    =#
    for g = G
      for h = G
        c.T = zero(M)
        if order(G) > 1
          gg = collect(word(preimage(mFF, g)), c)
          hh = collect(word(preimage(mFF, h)), c)
          c.T = zero(M)
          d = collect(vcat(gg, hh), c)
        end
        di[(g, h)] = c.T
      end
    end
    return CoChain{2,elem_type(G),elem_type(M)}(C, di)
  end

  symbolic_chain = function(g, h)
    c.f = symbolic_collect
    if order(G) == 1
      w = word(preimage(mFF, one(G)))
    else
      c.T = Z
      wg = collect(word(preimage(mFF, g)), c)
      wh = collect(word(preimage(mFF, h)), c)
      w = vcat(wg, wh)
    end
    c.T = Z
    @assert is_zero(Z)
    w = collect(w, c)
    return mE*c.T, w
  end

  set_attribute!(C, :H_two_symbolic_chain => (symbolic_chain, mH2))
  set_attribute!(C, :H_two_maps => (CC, mm))

  function is_coboundary(cc::CoChain{2})
    t = TailFromCoChain(cc)
    fl, b = haspreimage(CC, t)
    if !fl
      return false, nothing
    end
    d = Dict{Tuple{elem_type(G), }, elem_type(M)}()
    # t gives, directly, the images of the generators (of FF)
    im_g = [B_pro[i](b) for i=1:ngens(FF)]
    # otherwise: sigma(g, h) + sigma(gh) = sigma(g)^h + sigma(h)
    # this gives the images for the inverses, and then for everything
    im_gi = [cc((mFF(gen(FF, i)), mFF(inv(gen(FF, i))))) - iac[i](im_g[i]) for i=1:ngens(FF)]
    @assert domain(mFF) == FF
    @assert codomain(mFF) == G == group(cc.C)
    for g = G
      m = zero(M)
      h = one(G)
      w = word(preimage(mFF, g))

      for i=1:length(w)
        if w[i] < 0
          m = iac[-w[i]](m)+im_gi[-w[i]]-cc((h, mFF(inv(gen(FF, -w[i])))))
          h = h*mFF(inv(gen(FF, -w[i])))
        else
          m = ac[w[i]](m)+im_g[w[i]]-cc((h, mFF(gen(FF, w[i]))))
          h = h*mFF(gen(FF, w[i]))
        end
      end
      d[(g,)] = m
      @assert g == h
    end
    return true, CoChain{1,elem_type(G),elem_type(M)}(C, d)
  end

  z2 = function(y)
    T = TailFromCoChain(y)
    return mH2(preimage(mE, T))
  end

  z = (MapFromFunc(x->TailToCoChain(mE(preimage(mH2, x))), 
                  z2, H2, AllCoChains{2,elem_type(G),elem_type(M)}()),
#                         y->TailFromCoChain(y), D, AllCoChains{2,elem_type(G),elem_type(M)}()),
             is_coboundary)
  set_attribute!(C, :H_two => z)
  return H2, z[1], z[2]
  #now the rest...
  #(g, m)*(h, n) = (gh, m^h+n+gamma(g, h)) where gamma is "the" 2-cocycle
  #using tails:
  # gmhn -> gh h(m)+n -> x t+h(m) + n where x is the reduced
  #                                   word under collection and t is the 
  #                                   "tail"
  # so gamma(g, h) = t
  # given gamma need the tails:
  # need to implement the group operation for the extension
  # (g, v)(h, u) -> (gh, v^h + u + gamma(g, h))
  # then the rules with tails need to be evaluated at
  # the group generators (g_i, 0) 
  # r -> s gives a relation r s^-1 which should evaluate, using gamma
  # to (0, t) where t is the tail for this rule
end

function istwo_cocycle(c::CoChain{2})
  C = c.C
  G = C.G
  for g = G
    for h = G
      for k = G
        #= if (g*h)(x) = h(g(x)), then the cocycle should be
             X[(g*h, k)] X[(g, h)] == mA(g)(X[(h, k)]) X[(g, hk)]
           if (g*h)(x) = h(g(x)) then we should get
             X[(g, hk)] X[(h, k)]  == mA(k)(X[(g, h)]) X[(gh, k)]

             (Debeerst, PhD, (1.1) & (1.2))

             However, if we mix the conventions, all bets are off...
        =#       
        a = c.d[(g, h*k)] + c.d[(h, k)] - action(C, k, c.d[(g, h)])- c.d[(g*h, k)]
#        @show a, iszero(a) || valuation(a)
iszero(a) || (@show g, h, k, a ; return false)
        @assert iszero(a) # only for local stuff...|| valuation(a) > 20
      end
    end
  end
  return true
end

"""
For a gmodule `C` compute the `i`-th cohomology group
  where `i` can be `0`, `1` or `2`.
Together with the abstract module, a map is provided that will 
  produce explicit cochains.
"""
function cohomology_group(C::GModule{PermGroup,GrpAbFinGen}, i::Int; Tate::Bool = false)
  #should also allow modules...
  if Tate
    @assert is_finite(group(C))
  end
  if i==0
    if Tate
      return H_zero_tate(C)
    else
      return H_zero(C)
    end
  elseif i==1
    return H_one(C)
  elseif i==2
    return H_two(C)
  end
  error("only H^0, H^1 and H^2 are supported")
end

"""
For a fin. presented abelian group, return an isomorphic fp-group as well
as the map between the 2 groups
"""
function fp_group(M::GrpAbFinGen)
  mp = inv(isomorphism(FPGroup, M))
  return domain(mp), mp
end


#########################################################
#XXX: should be in AA and supplemented by a proper quo
function Oscar.issubset(M::AbstractAlgebra.FPModule{T}, N::AbstractAlgebra.FPModule{T}) where T<:RingElement 
  fl = is_submodule(N, M)
  if fl
    return fl, hom(M, N, elem_type(N)[N(m) for m = gens(M)])
  else
    return fl, hom(M, N, elem_type(N)[zero(N) for m = gens(M)])
  end
end

function Oscar.hom(V::Module, W::Module, v::Vector{<:ModuleElem}; check::Bool = true)
  if ngens(V) == 0
    return Generic.ModuleHomomorphism(V, W, zero_matrix(base_ring(V), ngens(V), ngens(W)))
  end
  return Generic.ModuleHomomorphism(V, W, vcat([x.v for x = v]))
end
function Oscar.hom(V::Module, W::Module, v::MatElem; check::Bool = true)
  return Generic.ModuleHomomorphism(V, W, v)
end
function Oscar.inv(M::Generic.ModuleHomomorphism)
  return hom(codomain(M), domain(M), inv(mat(M)))
end

function Oscar.direct_product(M::Module...; task::Symbol = :none)
  D, inj, pro = direct_sum(M...)
  if task == :none
    return D
  elseif task == :both
    return D, pro, inj
  elseif task == :sum
    return D, inj
  elseif task == :prod
    return D, pro
  end
  error("illegal task")
end

Base.:+(a::Generic.ModuleHomomorphism, b::Generic.ModuleHomomorphism) = hom(domain(a), codomain(a), mat(a) + mat(b))
Base.:-(a::Generic.ModuleHomomorphism, b::Generic.ModuleHomomorphism) = hom(domain(a), codomain(a), mat(a) - mat(b))
Base.:-(a::Generic.ModuleHomomorphism) = hom(domain(a), codomain(a), -mat(a))

function Oscar.mat(M::FreeModuleHom{FreeMod{QQAbElem}, FreeMod{QQAbElem}})
  return M.matrix
end

function Oscar.id_hom(A::Generic.FreeModule)
  return Generic.ModuleIsomorphism(A, A, identity_matrix(base_ring(A), ngens(A)))
end
###########################################################

#=
function get_collector(G::GAP.GapObj)
  @show G
  return GAP.evalstr("x -> FamilyObj(x.1)!.rewritingSystem")(G)
end
=#

"""
Compute an isomorphic pc-group (and the isomorphism). If `refine` is true,
the pc-generators will all have prime relative order, thus the
group should be safe to use.
If `refine` is false, then the relative orders are just used from the hnf
of the relation matrix.
"""
function pc_group(M::GrpAbFinGen; refine::Bool = true)
  @assert is_finite(M)
  R = rels(M)
  h = hnf(R)
  if nrows(h) > ncols(h)
    h = view(h, 1:ncols(h), :)
  end
  @assert nrows(h) == ncols(h)
  if refine
    r = sparse_matrix(ZZ)
    ng = 1
    gp = []
    hm = elem_type(M)[]
    for i=1:nrows(h)
      lf = factor(h[i,i]).fac
      for (p,k) = lf
        v = divexact(h[i,i], p^k)*M[i]
        for j=1:k-1
          push!(r, sparse_row(ZZ, [ng, ng+1], [p, ZZRingElem(-1)]))
          push!(hm, v)
          v *= p
          ng += 1
        end
        push!(r, sparse_row(ZZ, [ng], [p]))
        push!(gp, ng)
        push!(hm, v)
        ng += 1
      end
    end
    for i=1:nrows(h)
      for j=i+1:ncols(h)
        if !iszero(h[i,j])
          push!(r.rows[gp[i]], gp[j])
          push!(r.values(gp[i], h[i,j]))
        end
      end
    end
    MM = abelian_group(matrix(r))
    h = hom(MM, M, hm)
    M = MM
    mM = h
  else
    mM = hom(M, M, gens(M))
  end

  G = free_group(ngens(M))
  h = rels(M)
  @assert !any(x->h[x,x] == 1, 1:ncols(h))

  C = GAP.Globals.SingleCollector(G.X, GAP.Obj([h[i,i] for i=1:nrows(h)], recursive = true))
  F = GAP.Globals.FamilyObj(GAP.Globals.Identity(G.X))

  for i=1:ngens(M)-1
    r = ZZRingElem[]
    for j=i+1:ngens(M)
      push!(r, j)
      push!(r, -h[i, j])
      GAP.Globals.SetConjugate(C, j, i, gen(G, j).X)
    end
    rr = GAP.Globals.ObjByExtRep(F, GAP.Obj(r, recursive = true))
    GAP.Globals.SetPower(C, i, rr)
  end

  B = PcGroup(GAP.Globals.GroupByRws(C))
  FB = GAP.Globals.FamilyObj(GAP.Globals.Identity(B.X))

  Julia_to_gap = function(a::GrpAbFinGenElem)
    r = ZZRingElem[]
    for i=1:ngens(M)
      if !iszero(a[i])
        push!(r, i)
        push!(r, a[i])
      end
    end
    return GAP.Globals.ObjByExtRep(FB, GAP.Obj(r, recursive = true))
  end

  gap_to_julia = function(a::GAP.GapObj)
    e = GAPWrap.ExtRepOfObj(a)
    z = zeros(ZZRingElem, ngens(M))
    for i=1:2:length(e)
      if !iszero(e[i+1])
        z[e[i]] = e[i+1]
      end
    end
    return M(z)
  end

  @assert is_isomorphic(B, fp_group(M)[1])

  return B, MapFromFunc(
    x->image(mM, gap_to_julia(x.X)),
    y->PcGroupElem(B, Julia_to_gap(preimage(mM, y))),
    B, codomain(mM))
end

function fp_group(::Type{PcGroup}, M::GrpAbFinGen; refine::Bool = true)
  return pc_group(M)
end

function (k::Nemo.fpField)(a::Vector)
  @assert length(a) == 1
  return k(a[1])
end

function (k::fqPolyRepField)(a::Vector)
  return k(polynomial(GF(Int(characteristic(k))), a))
end

function Oscar.order(F::Generic.FreeModule{<:FinFieldElem})
  return order(base_ring(F))^dim(F)
end

function pc_group(M::Generic.FreeModule{<:FinFieldElem}; refine::Bool = true)
  k = base_ring(M)
  p = characteristic(k)

  G = free_group(degree(k)*dim(M))

  C = GAP.Globals.CombinatorialCollector(G.X, 
                  GAP.Obj([p for i=1:ngens(G)], recursive = true))
  F = GAP.Globals.FamilyObj(GAP.Globals.Identity(G.X))

  B = PcGroup(GAP.Globals.GroupByRws(C))
  FB = GAP.Globals.FamilyObj(GAP.Globals.Identity(B.X))

  function Julia_to_gap(a::Generic.FreeModuleElem{<:Union{fpFieldElem, FpFieldElem}})
    r = ZZRingElem[]
    for i=1:ngens(M)
      if !iszero(a[i])
        push!(r, i)
        push!(r, lift(a[i]))
      end
    end
    g = GAP.Globals.ObjByExtRep(FB, GAP.Obj(r, recursive = true))
    return g
  end

  function Julia_to_gap(a::Generic.FreeModuleElem{<:Union{FqPolyRepFieldElem, fqPolyRepFieldElem}})
    r = ZZRingElem[]
    for i=1:ngens(M)
      if !iszero(a[i])
        for j=0:degree(k)-1
          if !iszero(coeff(a[i], j))
            push!(r, (i-1)*degree(k)+j+1)
            push!(r, ZZ(coeff(a[i], j)))
          end
        end
      end
    end
    g = GAP.Globals.ObjByExtRep(FB, GAP.Obj(r, recursive = true))
    return g
  end


  gap_to_julia = function(a::GAP.GapObj)
    e = GAPWrap.ExtRepOfObj(a)
    z = zeros(ZZRingElem, ngens(M)*degree(k))
    for i=1:2:length(e)
      if !iszero(e[i+1])
        z[e[i]] = e[i+1]
      end
    end
    c = elem_type(k)[]
    for i=1:dim(M)
      push!(c, k(z[(i-1)*degree(k)+1:i*degree(k)]))
    end
    return M(c)
  end

  for i=1:ngens(M)-1
    r = ZZRingElem[]
    for j=i+1:ngens(M)
      GAP.Globals.SetConjugate(C, j, i, gen(G, j).X)
    end
    GAP.Globals.SetPower(C, i, GAP.Globals.Identity(F))
  end
  @assert is_abelian(B)
  @assert order(B) == order(M)

  return B, MapFromFunc(
    x->gap_to_julia(x.X),
    y->PcGroupElem(B, Julia_to_gap(y)),
    B, M)
end


function underlying_word(g::FPGroupElem)
  return FPGroupElem(free_group(parent(g)), GAPWrap.UnderlyingElement(g.X))
end

"""
Given a 2-cocycle, return the corresponding group extension, ie. the large
group, the injection of the abelian group and the quotient as well as a map
that given a tuple of elements in the group and the abelian group returns
the corresponding elt in the extension. 

If the gmodule is defined via a pc-group and the 1st argument is the 
`Type{PcGroup}`, the resulting group is also pc.
"""
function extension(c::CoChain{2,<:Oscar.GAPGroupElem})
  C = c.C
  G = Group(C)
  F, mF = fp_group(gens(G))
  M = Module(C)
  ac = action(C)
  iac = inv_action(C)
  fM, mfM = fp_group(M)
  N = free_group(ngens(G) + ngens(fM))
  function fMtoN(g)
    return reduce(*, [gen(N, ngens(G)+abs(w))^sign(w) for w = word(g)], init = one(N))
  end
  #TODO: this "loop" has been implemented several times....
  s = map(fMtoN, relators(fM))
  for R = relators(F)
    t = zero(M)
    g = one(G)
    r = one(N)
    for w = word(R)
      if w > 0
        t = ac[w](t) + c(g, gen(G, w))
        g = g*gen(G, w)
        r = r*gen(N, w)
      else
        t = iac[-w](t) + c(g, inv(gen(G, -w))) - c(gen(G, -w), inv(gen(G, -w)))
        g = g*inv(gen(G, -w))
        r = r*inv(gen(N, -w))
      end
    end
    push!(s, r*inv(fMtoN(preimage(mfM, t))))
  end
  for i=1:ngens(G)
    for j=1:ngens(fM)
      #m[j]*g[i] = g[i] m[j]^g[i]
      t = preimage(mfM, ac[i](gen(M, j)))
      push!(s, gen(N, ngens(G)+j)*gen(N, i)*inv(fMtoN(t)) * inv(gen(N, i)))
    end
  end
  Q, mQ = quo(N, s)
  @assert ngens(Q) == ngens(N)
  MtoQ = hom(fM, Q, gens(fM), gens(Q)[ngens(G)+1:end])
  QtoG = hom(Q, G, gens(Q), vcat(gens(G), [one(G) for i=1:ngens(fM)]))
  @assert domain(mfM) ==fM 
  @assert codomain(mfM) == M

  function GMtoQ(g::GAPGroupElem, m)
    @assert parent(m) == M
    @assert parent(g) == G
    h1 = hom(free_group(G), N, gens(free_group(G)), [N[i] for i=1:ngens(G)])
    h2 = hom(free_group(fM), N, gens(free_group(fM)), [N[i+ngens(G)] for i=1:ngens(fM)])
    return mQ(h1(underlying_word(g))*h2(underlying_word(preimage(mfM, m))))
  end

  return Q, inv(mfM)*MtoQ, QtoG, GMtoQ
end

function extension(::Type{PcGroup}, c::CoChain{2,<:Oscar.PcGroupElem})
  C = c.C
  G = Group(C)
  @assert isa(G, PcGroup)
  M = Module(C)
  ac = action(C)
  iac = inv_action(C)
  fM, mfM = pc_group(M)

  N = free_group(ngens(G) + ngens(fM))
  Gp = GAP.Globals.Pcgs(G.X)
  @assert length(Gp) == ngens(G)
#  @assert all(x->Gp[x] == gen(G, x).X, 1:ngens(G))
  Go = GAP.Globals.RelativeOrders(Gp)

  Mp = GAP.Globals.Pcgs(fM.X)
  @assert length(Mp) == ngens(fM) == ngens(M)
#  @assert all(x->Mp[x] == gen(fM, x).X, 1:ngens(M))
  Mo = GAP.Globals.RelativeOrders(Mp)

  CN = GAP.Globals.SingleCollector(N.X, GAP.Globals.Concatenation(Go, Mo))
  FN = GAP.Globals.FamilyObj(N[1].X)

  for i=1:ngens(fM)
    lp = deepcopy(GAPWrap.ExtRepOfObj(Mp[i]^Mo[i]))
    for k=1:2:length(lp)
      lp[k] += ngens(G)
    end
    m = GAP.Globals.ObjByExtRep(FN, lp)
    GAP.Globals.SetPower(CN, i+ngens(G), m)
    for j=i+1:ngens(fM)
      p = Mp[j]^Mp[i]
      @assert p == Mp[j]
      lp = deepcopy(GAPWrap.ExtRepOfObj(p))
      for k=1:2:length(lp)
        lp[k] += ngens(G)
      end
      GAP.Globals.SetConjugate(CN, j+ngens(G), i+ngens(G), GAP.Globals.ObjByExtRep(FN, lp))
    end
  end

  fMtoN = function(x)
    lp = deepcopy(GAPWrap.ExtRepOfObj(x.X))
    for k=1:2:length(lp)
      @assert lp[k] > 0
      lp[k] += ngens(G)
    end
    return GAP.Globals.ObjByExtRep(FN, lp)
  end

  word = function(y)
    z = GAPWrap.UnderlyingElement(y)
    return map(Int, GAP.Globals.LetterRepAssocWord(z))
  end

  #for W = (w1, ... w_n) compute ((w1, 0), ..., (wn, 0))
  #and return the tail only.
  word_to_elem = function(W)
    t = zero(M)
    g = one(G)
    r = one(N)
    for w = W
      if w > 0
        t = ac[w](t) + c(g, gen(G, w))
        g = g*gen(G, w)
        r = r*gen(N, w)
      else
        t = iac[-w](t) + c(g, inv(gen(G, -w))) - c(gen(G, -w), inv(gen(G, -w)))
        g = g*inv(gen(G, -w))
        r = r*inv(gen(N, -w))
      end
    end
    return t
    return fMtoN(preimage(mfM, t))
  end

  #to lift the pc-relations:
  # F^p = w (order relation)
  #  compute (F, 0)^p = (?, t) = (?, 0)(1, t)
  #  compute (w, 0)   = (?, s) = (?, 0)(1, s)
  #  so (?, 0) = (w, 0)(1,s)^-1= (w, 0)(1,-s) if chain is normalised
  #  thus (F, 0)^p = (?, 0)(1, t) = (w, 0)(1,-s)(1, t)
  #  the ? should be identical, namely the collected version of w
  #  then (F, 0)^p = (w, t-s) might be the answer
  # F^G = w (conjugate relation): same
  #  (F, 0)^(G, 0) = (?, t) = (?, 0)(1, t)
  #  (w, 0)        = (?, s) = (?, 0)(1, s)
  #  thus (F, 0)^(G, 0) = (w, t-s)
  for i=1:ngens(G)
    p = Gp[i]^Go[i]
    pp = GAP.Globals.ObjByExtRep(FN, GAPWrap.ExtRepOfObj(p))
    m = fMtoN(preimage(mfM, word_to_elem([i for k=1:Go[i]])-word_to_elem(word(p))))
    GAP.Globals.SetPower(CN, i, pp*m)
    for j=i+1:ngens(G)
      p = Gp[j]^Gp[i]
      m = fMtoN(preimage(mfM, word_to_elem([-i, j, i])-word_to_elem(word(p))))
      pp = GAP.Globals.ObjByExtRep(FN, GAPWrap.ExtRepOfObj(p))
      GAP.Globals.SetConjugate(CN, j, i, pp*m)
    end
    for j=1:ngens(fM)
      m = fMtoN(preimage(mfM, action(C, gen(G, i), mfM(gen(fM, j)))))
      GAP.Globals.SetConjugate(CN, j+ngens(G), i, m)
    end
  end

#  l = GAP.Obj([])
#  GAP.Globals.FinitePolycyclicCollector_IsConfluent(CN, l)
#  @show l

#  z = GAP.Globals.GroupByRwsNC(CN)
#  s = GAP.Globals.GapInputPcGroup(z, GAP.Obj("Z"))
#  @show GAP.gap_to_julia(s)
  Q = PcGroup(GAP.Globals.GroupByRws(CN))
  fQ = GAP.Globals.FamilyObj(one(Q).X)
  mQ = hom(N, Q, gens(N), gens(Q))

  @assert ngens(Q) == ngens(N)
  MtoQ = hom(fM, Q, gens(fM), gens(Q)[ngens(G)+1:end])
  QtoG = hom(Q, G, gens(Q), vcat(gens(G), [one(G) for i=1:ngens(fM)]))
  @assert domain(mfM) ==fM 
  @assert codomain(mfM) == M
#  @assert is_surjective(QtoG)
#  @assert is_injective(MtoQ)

  mfG = epimorphism_from_free_group(G)
  mffM = epimorphism_from_free_group(fM)

  function GMtoQ(wg, m)
    wm = GAP.gap_to_julia(GAPWrap.ExtRepOfObj(preimage(mffM, preimage(mfM, m)).X))
    for i=1:2:length(wm)
      push!(wg, wm[i]+ngens(G))
      push!(wg, wm[i+1])
    end
    return mQ(FPGroupElem(N, GAP.Globals.ObjByExtRep(FN, GAP.Obj(wg))))
  end

  return Q, inv(mfM)*MtoQ, QtoG, GMtoQ
end

function fp_group(c::CoChain{2})
  return extension(c)[1]
end

function pc_group(c::CoChain{2, <:Oscar.PcGroupElem})
  return extension(PcGroup, c)[1]
end

end #module

using .GrpCoh

export gmodule, GModule, fp_group, pc_group, induce, cohomology_group

module GaloisCohomology_Mod
using Oscar
import Oscar: GrpCoh
import Oscar.GrpCoh: CoChain, MultGrpElem, MultGrp, GModule, is_consistent, 
                     Group
import Base: parent
import Oscar: direct_sum
export is_coboundary, idel_class_gmodule


Oscar.elem_type(::Type{Hecke.NfMorSet{T}}) where {T <: Hecke.LocalField} = Hecke.LocalFieldMor{T, T}
parent(f::Hecke.LocalFieldMor) = Hecke.NfMorSet(domain(f))

function Oscar.automorphism_group(::Type{PermGroup}, k)
  G, mG = automorphism_group(k)
  H = symmetric_group(degree(k))
  gens(G) #to make sure gens are actually there...
  H = sub(H, [H(G.mult_table[:, i]) for i=G.gens])[1]

  function HtoG(p::PermGroupElem)
    m = [i^p for i=1:degree(k)]
    i = Base.findfirst(x->G.mult_table[:, x] == m, 1:degree(k))
    return mG(GrpGenElem(G, i))
  end

  function GtoH(a::NfToNfMor)
    g = preimage(mG, a)
    return H(G.mult_table[:, g.i])
  end

  return H, MapFromFunc(HtoG, GtoH, H, codomain(mG))
end

function Oscar.automorphism_group(::Type{PermGroup}, K, k)
  G, mG = automorphism_group(K, k)
  H = symmetric_group(length(G))
  gens(G) #to make sure gens are actually there...
  H = sub(H, [H(G.mult_table[:, i]) for i=G.gens])[1]

  function HtoG(p::PermGroupElem)
    m = [i^p for i=1:length(G)]
    i = Base.findfirst(x->G.mult_table[:, x] == m, 1:length(G))
    return mG(GrpGenElem(G, i))
  end

  function GtoH(a::NfToNfMor)
    g = preimage(mG, a)
    return H(G.mult_table[:, g.i])
  end

  return H, MapFromFunc(HtoG, GtoH, H, codomain(mG))
end


"""
The natural `ZZ[H]` module where `H`, a subgroup of the
  automorphism group acts on the ray class group.
"""
function Oscar.gmodule(H::PermGroup, mR::MapRayClassGrp, mG = automorphism_group(PermGroup, k)[2])
  k = nf(order(codomain(mR)))
  G = domain(mG)

  ac = Hecke.induce_action(mR, [image(mG, G(g)) for g = gens(H)])
  return GModule(H, ac)
end

"""
The natural `ZZ[G]` module where `G`, the
  automorphism group, acts on the ideal group defining the class field.
"""
function Oscar.gmodule(R::ClassField, mG = automorphism_group(PermGroup, k)[2])
  k = base_field(R)
  G = domain(mG)
  mR = R.rayclassgroupmap
  mq = R.quotientmap

  ac = Hecke.induce_action(mR, [image(mG, g) for g = gens(G)], mq)
  return GModule(G, ac)
end

"""
The natural `ZZ[H]` module where `H`, a subgroup of the 
  automorphism group, acts on the ideal group defining the class field.
"""
function Oscar.gmodule(H::PermGroup, R::ClassField, mG = automorphism_group(PermGroup, k))
  k = base_field(R)
  G = domain(mG)
  mR = R.rayclassgroupmap
  mq = R.quotientmap

  ac = Hecke.induce_action(mR, [image(mG, G(g)) for g = gens(H)], mq)
  #TODO: think about adding a restriction map?
  return GModule(G, ac)
end

#TODO: think: this should probably all use MultGrpElem???
#      NO, the "module" is the abstract abelian group
function _gmodule(k::AnticNumberField, H::PermGroup, mu::Map{GrpAbFinGen, FacElemMon{AnticNumberField}}, mG = automorphism_group(PermGroup, k)[2])
  u = domain(mu)
  U = [mu(g) for g = gens(u)]
  G = domain(mG)
  ac = [hom(u, u, [preimage(mu, mG(G(g))(x)) for x = U]) for g = gens(H)]
  return gmodule(H, ac)
end

function Oscar.gmodule(H::PermGroup, mu::Map{GrpAbFinGen, FacElemMon{AnticNumberField}}, mG = automorphism_group(PermGroup, base_ring(codomain(mu)))[2])
  return _gmodule(base_ring(codomain(mu)), H, mu, mG)
end

function Oscar.gmodule(H::PermGroup, mu::Hecke.MapUnitGrp{NfOrd}, mG = automorphism_group(PermGroup, k)[2])
  #TODO: preimage for sunits can fail (inf. loop) if
  # (experimentally) the ideals in S are not coprime or include 1
  # or if the s-unit is not in the image (eg. action and not closed set S)
  u = domain(mu)
  U = [mu(g) for g = gens(u)]
  zk = codomain(mu)
  k = nf(zk)
  G = domain(mG)
  ac = [hom(u, u, [preimage(mu, zk(mG(G(g))(k(x)))) for x = U]) for g = gens(H)]
  return gmodule(H, ac)
end

function Oscar.gmodule(H::PermGroup, mu::Map{GrpAbFinGen, AnticNumberField})
  return _gmodule(codomain(mu), H, mu)
end

function is_coboundary(c::CoChain{2,PermGroupElem,MultGrpElem{nf_elem}})
  @vprint :GaloisCohomology 1 "testing if 2-chain is a boundary\n"

  zk = maximal_order(parent(first(values(c.d)).data))
  @vprint :GaloisCohomology 2 ".. gathering primes in the support ..\n"
  cp = coprime_base(vcat([numerator(norm(x.data*denominator(x.data))) for x = values(c.d)],
                         map(x->denominator(x.data), values(c.d))))
  s = Set(reduce(vcat, [collect(keys(factor(x).fac)) for x = cp], init = [1]))
  while 1 in s
    pop!(s, 1)
  end

  @vprint :GaloisCohomology 2 ".. class group ..\n"
  Cl, mCl = class_group(zk)
  if length(s) == 0
    S = Set{NfOrdIdl}()
  else
    S = Set(reduce(vcat, [[x[1] for x = prime_decomposition(zk, p)] for p = s]))
  end
  
  @vprint :GaloisCohomology 2 ".. enlarge primes ..\n"
  q, mq = quo(Cl, [preimage(mCl, x) for x = S])
  p = 2
  while order(q) > 1
    p = next_prime(p)
    if p in s
      continue
    end
    lp = prime_decomposition(zk, p)
    cP = [mq(preimage(mCl, x[1])) for x= lp]
    if all(iszero, cP)
      continue
    end
    S = union(S, Set([x[1] for x = lp]))
    q, mmq = quo(q, cP)
    mq = mq*mmq
  end

  @vprint :GaloisCohomology 2 ".. S-units ..\n"
  if length(S) == 0
    u, mu = Hecke.unit_group_fac_elem(zk)
  else
    u, mu = Hecke.sunit_group_fac_elem(collect(S))
  end
  C = gmodule(Group(c.C), mu)

  @vprint :GaloisCohomology 2 ".. cohomology ..\n"
  H2, _, z = cohomology_group(C, 2)
  @vprint :GaloisCohomology 2 ".. map to abstract chain ..\n"
  cc = CoChain{2,PermGroupElem,GrpAbFinGenElem}(C, Dict((h, preimage(mu, FacElem(v.data))) for (h,v) = c.d))
  @vprint :GaloisCohomology 2 ".. test for boundary ..\n"
  fl, d = z(cc)
  if !fl
    @vprint :GaloisCohomology 2 ".. no boundary\n"
    return fl, d
  end
  @vprint :GaloisCohomology 2 ".. explicit boundary\n"
  MK = MultGrp(number_field(zk))
  return fl, CoChain{1,PermGroupElem,elem_type(MK)}(c.C, Dict((h, MK(evaluate(mu(v)))) for (h,v) = d.d))
end

function isunramified(p::NfOrdIdl)
  return ramification_index(p) == 1
end


"""
For a completion C of a number field K, implicitly given as the map
    mK:  K -> C
And the automorphism group G of K given via
    mG:  G -> aut(K)
and the automorphism group Gp of Kp, given via
    mGp: Gp -> Aut(Kp)
Find the embedding of Gp -> G, realizing the local automorphism group
as a subgroup of the global one.
"""
function Oscar.decomposition_group(K::AnticNumberField, mK::Map, mG::Map = automorphism_group(K)[2], mGp::Map = automorphism_group(codomain(mK), prime_field(codomain(mK))))
  Kp = codomain(mK)
  @assert domain(mK) == K

  Gp = domain(mGp)
  G = domain(mG)

  im = elem_type(G)[]
  elG = [g for g = G]
  imK = [mK(mG(g)(gen(K))) for g = elG]
  for s = gens(Gp)
    h = mGp(s)(mK(gen(K)))
    z = findall(isequal(h), imK)
    if length(z) == 0
      z = argmax([valuation(h-x) for x = imK], dims = 1)
    end
    @assert length(z) == 1
    push!(im, elG[z[1]])
  end
  return hom(Gp, G, im)
end

"""
  For a real or complex embedding `emb`, find the unique automorphism
  that acts on this embedding as complex conjugation.
"""
function Oscar.decomposition_group(K::AnticNumberField, emb::Hecke.NumFieldEmb, mG::Map = automorphism_group(K)[2])
  G = domain(mG)
  if is_real(emb)
    return sub(G, [one(G)])[2]
  end
  g = gen(K)
  lG = [g for g  = G]
  l = findall(x->overlaps(conj(emb(g)), emb(mG(x)(g))), lG)
  @assert length(l) == 1
  sigma = lG[l[1]]
  return sub(G, [sigma])[2]
end

#= TODO
 - (DONE) induce a gmodule into a larger group
 - (DONE) direct sum/prod of gmodules
 - maps (a pair of G->H and N -> M or so)?
 - quotient?
 - the local/ global fund class, ie. normalize the cochain
 - map a local chain into a ray class group
=#

"""
For a local field extension K/k, return a gmodule for the multiplicative
group of K as a Gal(K/k) module.

Returns: 
 - the gmodule
 - the map from G = Gal(K/k) -> Set of actual automorphisms
 - the map from the module into K
"""
function Oscar.gmodule(K::Hecke.LocalField, k::Union{Hecke.LocalField, FlintPadicField, FlintQadicField} = base_field(K); Sylow::Int = 0, full::Bool = false)

  #if K/k is unramified, then the units are cohomological trivial,
  #   so Z (with trivial action) is correct for the gmodule
  #if K/k is tame, then the 1-units are cohomologycal trivial, hence
  #   Z time k^* is enough...

  e = divexact(absolute_ramification_index(K), absolute_ramification_index(k))
  f = divexact(absolute_degree(K), e)
  @vprint :GaloisCohomology 1 "the local mult. group as a Z[G] module for e=$e and f = $f\n"
  @vprint :GaloisCohomology 2 " .. the automorphism group ..\n"

  G, mG = automorphism_group(PermGroup, K, k)

  if e == 1 && !full
    @vprint :GaloisCohomology 2 " .. unramified, only the free part ..\n"
#    @show :unram
    A = abelian_group([0])
    Hecke.assure_has_hnf(A)
    pi = uniformizer(K)
    return gmodule(G, [hom(A, A, [A[1]]) for g = gens(G)]),
      mG,
      MapFromFunc(x->pi^x[1], y->Int(e*valuation(y))*A[1], A, K)
  end

  if e % prime(K) != 0 && !full #tame!
    @vprint :GaloisCohomology 2 " .. tame, no 1-units ..\n"
#    @show :tame
    k, mk = residue_field(K)
    u, mu = unit_group(k)
    pi = uniformizer(K)
    # move to a Teichmueller lift?
    gk = preimage(mk, mu(u[1]))
    pr = precision(gk)
    gkk = setprecision(gk^order(k), pr)
    while !iszero(gkk - gk)
      gk = gkk
      gkk = setprecision(gk^order(k), pr)
    end
    A = abelian_group([0, order(u)])
    Hecke.assure_has_hnf(A)
    h = Map[]
    for g = gens(G)
      im = [A[1]+preimage(mu, mk(mG(g)(pi)*inv(pi)))[1]*A[2], preimage(mu, mk(mG(g)(gk)))[1]*A[2]]
      push!(h, hom(A, A, im))
    end
    return gmodule(G, h),
      mG,
      MapFromFunc(x->pi^x[1] * gk^x[2],
        function(y)
          v = Int(e*valuation(y))
          y *= pi^-v
          return v*A[1] + preimage(mu, mk(y))[1]*A[2]
        end, A, K)
  end
 
#  @show :wild
  @vprint :GaloisCohomology 2 " .. wild case (or requested), unit group ..\n"
  U, mU = unit_group(K)
  n = divexact(absolute_degree(K), absolute_degree(k))
  @assert order(G) == n

  @vprint :GaloisCohomology 2 " .. find lattice (normal basis) ..\n"
  b = absolute_basis(K)
  # need a normal basis for K/k, so the elements need to be k-lin. indep
  local o, best_o
  cnt = 0
  while true
    a = sum(b[i]*rand(-5:5) for i=1:length(b))
    o = [mG(g)(a) for g = G]
    m = matrix(k, n, n, vcat([coordinates(x, k) for x = o]...))
    dm = det(m)
    cnt += 1
    if cnt > 10
      error("dnw")
    end
    if iszero(dm) #|| valuation(dm) > 5
      continue
    else
      break
    end
  end

  #o needs to be expanded to be an absolute basis
  b = absolute_basis(k)
  o = [x*y for x = b for y = o]


  @vprint :GaloisCohomology 2 " .. quotient ..\n"
  Q, mQ = quo(U, [preimage(mU, 1+prime(k)^4*x) for x = o])
  S, mS = snf(Q)
  Q = S
  mQ = mQ*inv(mS)

  if Sylow > 0
    @assert isprime(Sylow)
    G, mS = sylow_subgroup(G, Sylow)
    mG = mS*mG
  end

  @vprint :GaloisCohomology 2 " .. the module ..\n"
  hh = [hom(Q, Q, [mQ(preimage(mU, mG(i)(mU(preimage(mQ, g))))) for g = gens(Q)]) for i=gens(G)]
  Hecke.assure_has_hnf(Q)
  return gmodule(G, hh), mG, pseudo_inv(mQ)*mU
end

#=  Not used
function one_unit_cohomology(K::Hecke.LocalField, k::Union{Hecke.LocalField, FlintPadicField, FlintQadicField} = base_field(K))

  U, mU = Hecke.one_unit_group(K)
  G, mG = automorphism_group(PermGroup, K, k)

  b = absolute_basis(K)
  local o
  while true
    a = uniformizer(K)^30*sum(b[i]*rand(-5:5) for i=1:length(b))
    o = [mG(g)(a) for g = G]
    if length(Set(o)) == order(G)
      break
    end
  end

  S, mS = sub(U, [preimage(mU, 1+x) for x = o])
  Q, mQ = quo(U, S)
  hh = [hom(Q, Q, [mQ(preimage(mU, mG(i)(mU(preimage(mQ, g))))) for g = gens(Q)]) for i=gens(G)]
  return gmodule(G, hh)
end

=#
#= TODO
 - (DONE) induce a gmodule into a larger group
 - (DONE) direct sum/prod of gmodules
 - maps (a pair of G->H and N -> M or so)?
 - quotient?
 - the local/ global fund class, ie. normalize the cochain
 - map a local chain into a ray class group
=#

export GModule
export action
export cohomology_group
export confluent_fp_group
export extension
export fp_group
export gmodule
export induce
export is_coboundary
export pc_group
export word

#= TODO
  for Z, Z/nZ, F_p and F_q moduln -> find Fp-presentation
  for finite Z, Z/nZ, F_p and F_q moduln -> find pc-presentation
  #done: for GrpAbFinGen          -> find Fp-presentation
  #done: for GrpAbFinGen          -> find pc-presentation
  #done: for a in H^2 find Fp-presentation
  #done: for a in H^2 find pc-presentation
  for a in H^2 find (low degree) perm group using the perm group we have?
  Magma's DistinctExtensions
  probably aut(GrpAb), ...

Sort: 
 - move the additional GrpAbFinGenMap stuff elsewhere
 - move (and fix) the ModuleHom stuff
 - add proper quo for Modules (done)
 - split generic coho/ gmodule and number theory  (partly done)

  features   
   - inflation (done), restriction (done), long exact sequence  
   - induction (done)/ coinduction ...
   - restriction (of gmodules to Sylow subgroups)
   - think about Debeerst: if P, Q are above the some prime then
     Ind_G_P^G L_P = Ing_G_Q^G L_Q??? (no - aprently yes)
   - use prod_Q|P L_Q rather than prod Ind...  

  dreams
   - we we extend to H^-1, ^-2?
   - H^3 (in some cases)
   - cup products
   - the relative cohomology
     https://arxiv.org/pdf/1809.01209.pdf
     https://doi.org/10.1017/S2040618500033050

  GModule for 
    - (done for mult grp) local field (add (trivial) and mult)
    - (done) (S-)units
    - (done) Ali's stuff.... (in progress: see Hecke/src/LocalField/neq.jl)
    - local field (add (trivial) and mult)
    - (S-)units
=#    

#TODO: what do we need to return?
# - mG (if we cache this in the field, not necessary)
# - the local stuff?
# - the S-Units?
# - ???
# - a different type containing all this drivel? (probably)
#    YES - need to have maps to and from local stuff
#    use Klueners/ Acciaro to map arbitrary local into idel
#    use ...               to project to ray class
# - a magic(?) function to get idel-approximations in and out?

"""
M has to be a torsion free Z module with a C_2 action by sigma.
Returns data for the decomposition into indecomposables.
They will be of type
 - Z with trivial and non-trivial action
 - Z[C_2]

Two arrays are returned:
 - generators for the 1-dim modules
 - C_2 generators for the 2-dim ones

Follows Debeerst rather closely...

(Helper for the idel-class stuff)
"""
function debeerst(M::GrpAbFinGen, sigma::Map{GrpAbFinGen, GrpAbFinGen})
  @assert domain(sigma) == codomain(sigma) == M
  @assert all(x->sigma(sigma(x)) == x, gens(M))
  @assert is_free(M) && rank(M) == ngens(M)

  K, mK = kernel(id_hom(M)+sigma)
  fl, mX = has_complement(mK)
  @assert fl
  X = domain(mX)
  _X, _mX = snf(X)

  S, mS = image(sigma -id_hom(M))
  fl, mSK = is_subgroup(S, K)
  @assert fl


  _K, _mK = snf(K)
  _S, _mS = snf(S)
  @assert istrivial(_S) || rank(_S) == ngens(_S) 
  @assert rank(_K) == ngens(_K) 

  m = matrix(GrpAbFinGenMap(_mS * mSK * inv((_mK))))
  # elt in S * m = elt in K
  # so
  # elt in S * U^-1 U m V V^-1 = elt_in K
  # elt in S * U^-1 snf = elt_in * V
  s, U, V = snf_with_transform(m)
  if istrivial(S)
    r = 0
  else
    r = maximum(findall(x->isone(s[x,x]), 1:ngens(_S)))
  end

  mu = hom(_S, _S, inv(U))
  mv = hom(_K, _K, V)
  @assert istrivial(S) || all(i-> M(_mS(mu(gen(_S, i)))) == s[i,i] * M(_mK(mv(gen(_K, i)))), 1:ngens(S))
  b = [_mK(mv(x)) for x = gens(_K)]

  Q, mQ = quo(S, image(sigma -id_hom(M), K)[1])
  B, mB = sub(Q,  [mQ(preimage(mSK, x)) for x = b[1:r]])
  @assert order(B) == order(Q)

  phi = GrpAbFinGenMap(_mX*mX*(sigma -id_hom(M))*pseudo_inv(mS)*mQ)
  @assert is_surjective(phi)
  A = vcat([preimage(mB, phi(k)).coeff for k = gens(_X)]...)
  h, t = hnf_with_transform(A)
  #t*A = h = diag(1) vcat 0
  x = [sum(t[i,j]*_X[j] for j=1:ngens(_X)) for i=1:ngens(_X)]
  sm1 = sigma - id_hom(M)
  sm1_K = hom(K, M, [sm1(mK(x)) for x= gens(K)])
  lambda = vcat([preimage(sm1_K, sm1(mX(_mX(x[i]))) - mK(b[i])) for i=1:r],
                [preimage(sm1_K, sm1(mX(_mX(x[i])))) for i=r+1:length(x)])
  x = map(_mX*mX, x)
  lambda = map(mK, lambda)
  y = x .- lambda
  b = map(mK, b)

  #just checking the action on the 2-dim stuff. magic.
  #= (s-1)x = b + (s-1)l  1..r
     y = x-l
     s(y) = s(x) - s(l) = s(x)-x + x - s(l) + l - l
           = (s-1)x + x -(s-1)l -l
           = b + (s-1)l + x -(s-1)l - l = b + x-l = b + y
  =#        
  #=
  h2 = []
  for i=1:r
    a = abelian_group([0,0])
    push!(h2, (hom(a, M, [b[i], y[i]]), -y[i]-b[i]))
  end
  h_minus = []
  for i=r+1:length(b)
    a = abelian_group([0])
    push!(h_minus, (hom(a, M, [b[i]]), b[i]))
  end
  h_plus = []
  for i=r+1:length(y)
    a = abelian_group([0])
    push!(h_plus, (hom(a, M, [y[i]]), y[i]))
  end
  =#

  return vcat(b[r+1:end], y[r+1:end]), [-y[i] - b[i] for i=1:r]
end

function (G::GrpAbFinGen)(x::GrpAbFinGenElem)
  fl, m = is_subgroup(parent(x), G)
  @assert fl
  return m(x)
end

function Hecke.extend_easy(m::Hecke.CompletionMap, L::FacElemMon{AnticNumberField})
  k = base_ring(L)
  @assert k == domain(m)

  #want a map: L-> codomain(m)
  function to(a::FacElem{nf_elem})
    return prod(m(k)^v for (k,v) = a.fac)
  end
  function from(a::Hecke.LocalFieldElem)
    return FacElem(preimage(m, a))
  end
  return MapFromFunc(to, from, L, codomain(m))
end

function Hecke.extend_easy(m::Hecke.CompletionMap, mu::Map, L::FacElemMon{AnticNumberField})
  k = base_ring(L)
  @assert k == domain(m)
  @assert codomain(mu) == codomain(m)

  cache = Dict{nf_elem, GrpAbFinGenElem}()
  #want a map: L-> codomain(m) -> domain(mu)
  function to(a::FacElem{nf_elem})
    s = domain(mu)[0]
    for (k,v) = a.fac
      if haskey(cache, k)
        s += v*cache[k]
      else
        kk = preimage(mu, m(k))
        cache[k] = kk
        s += v*kk
      end
    end
    return s
  end
  function from(a::Hecke.LocalFieldElem)
    return FacElem(preimage(m, mu(a)))
  end
  return MapFromFunc(to, from, L, domain(mu))
end


mutable struct IdelParent
  k::AnticNumberField
  mG::Map # AutGrp -> Automorohisms
  S::Vector{NfAbsOrdIdl} # for each prime number ONE ideal above
  C::Vector{Map} # the completions at S
  D::Vector{Map} # Gp -> Aut
  L::Vector{Map} # the mult. group map at C

  #for P in S the modules used actually is
  #    Ind_G_p^G L[P]
  #        = sum L[P] otimes s_i
  # (for s_i a fixed system of coset reps G//G_P)
  # L[P] otimes s_i "should be" the completion data at P^s_i - one of the other ideals
  # should be L[P] ni l -> C[P] -> k -> inv(s_i)(..) to get a proper rep in k
  # completion at P^s is C[P] but with the map twisted by s

  mU::Map #S-unit group map
  M::GrpAbFinGen  # the big module, direct product from
    # infinite gmodule x finite ones
  mq::Map # "projection" of M -> the acutal module in the end

  data

  function IdelParent()
    return new()
  end
end

"""
Following Debeerst:
  Algorithms for Tamagawa Number Conjectures. Dissertation, University of Kassel, June 2011.
or Ali, 

Find a gmodule C s.th. C is cohomology-equivalent to the cohomology
of the idel-class group.
"""
function idel_class_gmodule(k::AnticNumberField, s::Vector{Int} = Int[])
  @vprint :GaloisCohomology 1 "Ideal class group cohomology for $k\n"
  I = IdelParent()
  I.k = k
  G, mG = automorphism_group(PermGroup, k)
  I.mG = mG

  zk = maximal_order(k)

  sf = subfields(k)
  sf = [x[1] for x = sf if degree(x[1]) > 1]
  zf = map(maximal_order, sf)
  cf = map(class_group, zf)
  cf = Tuple{GrpAbFinGen, <:Map}[x for x = cf]

  @vprint :GaloisCohomology 2 " .. gathering primes ..\n"
  s = push!(Set{ZZRingElem}(s), Set{ZZRingElem}(keys(factor(discriminant(zk)).fac))...)
  for i=1:length(sf)
    l = factor(prod(s)*zf[i])
    q, mq = quo(cf[i][1], [preimage(cf[i][2], P) for P = keys(l)])
    cf[i] = (q, pseudo_inv(mq)*cf[i][2])
  end

  #think: does the quotient have to be trivial - or coprime to |G|?
  #coprime should be enough

  for p = PrimesSet(2, -1)
    p in s && continue
    all(x->order(x[1]) == 1, cf) && break
    new = false
    for i=1:length(sf)
      l = factor(p*zf[i])
      q, mq = quo(cf[i][1], [preimage(cf[i][2], P) for P = keys(l)])
      if order(q) != order(cf[i][1])
        new = true
      end
      cf[i] = (q, pseudo_inv(mq)*cf[i][2])
    end
    if new
      push!(s, p)
    end
  end

  S = collect(keys(factor(prod(s)*zk)))
  @vprint :GaloisCohomology 2 " .. need $(length(S)) prime ideals ..\n"

  s = [findfirst(x->minimum(x) == t, S) for t = s]
  @vprint :GaloisCohomology 2 " .. split into $(length(s)) G-orbits ..\n"

  @vprint :GaloisCohomology 2 " .. S-units (for all) ..\n"
  U, mU = sunit_group_fac_elem(S)
  I.mU = mU
  z = MapFromFunc(x->evaluate(x), y->FacElem(y), codomain(mU), k)
  E = gmodule(G, mU, mG)
  Hecke.assure_has_hnf(E.M)
  @hassert :GaloisCohomology -1 is_consistent(E)

  if is_totally_real(k)
    @vprint :GaloisCohomology 2 " .. real field, easy case ..\n"
    mG_inf = Oscar.decomposition_group(k, real_embeddings(k)[1], mG)
    G_inf = domain(mG_inf)
    Et = gmodule(G_inf, mU, mG)
    @hassert :GaloisCohomology 1 is_consistent(Et)
    iEt = Oscar.GrpCoh.induce(Et, mG_inf, E, id_hom(U))
  else
    @vprint :GaloisCohomology 2 " .. complex field, hard case ..\n"
    mG_inf = Oscar.decomposition_group(k, complex_embeddings(k)[1], mG)
    G_inf = domain(mG_inf)
    sigma = action(E, mG_inf(G_inf[1]))
    @assert order(G_inf[1]) == 2 == order(G_inf)

    @assert order(U[1]) >0
    q, mq = quo(U, [U[1]]) 
    q, _mq = snf(q)
    mq = mq*pseudo_inv(_mq)
    sigma_q = hom(q, q, [mq(sigma(preimage(mq, x))) for x = gens(q)])
    x, y = debeerst(q, sigma_q)
    # just to verify... Gunter Malle: the C_2 modules are visible over GF(2)...
    _M = gmodule(GF(2), gmodule(G_inf, [sigma_q]))
    _i = indecomposition(_M)
    @assert length(findall(x->dim(x[1]) == 2, _i)) == length(y)
    @assert length(findall(x->dim(x[1]) == 1, _i)) == length(x)
      #possibly: now the H^2 is correct, but the H^1 is not...
      # x^8 - 12*x^7 + 44*x^6 - 24*x^5 - 132*x^4 + 120*x^3 + 208*x^2 - 528*x + 724

    #theta:
    theta = U[1] #should be a generator for torsion, torsion is even,
                 #hence this elem cannot be a square
    T = abelian_group([order(U[1]), 0])             
    ac_T = hom(T, T, [sigma(U[1])[1]*T[1], T[1]+T[2]])

    x = [preimage(mq, i) for i = x]
    y = [preimage(mq, i) for i = y]

    z, mz = sub(U, [sigma(U[1]) - U[1]])
    theta_i = [sigma(t)-t for t = x]
    inv = Int[]
    not_inv = Int[]
    for i=1:length(x)
      w = theta_i[i]
      fl, pe = haspreimage(mz, w)
      if fl
        push!(inv, i)
        zz = mq(x[i])
        x[i] -= pe[1]*U[1]
        @assert zz == mq(x[i])
        theta_i[i] = sigma(x[i]) - x[i]
        @assert iszero(theta_i[i])
      else
        push!(not_inv, i)
      end
    end
    
    @assert length(not_inv) > 0
    @assert length(not_inv) + length(inv) == length(x)
    x = vcat(x[not_inv], x[inv]) #reordering
    theta_i = vcat(theta_i[not_inv], theta_i[inv])
    
    U_t, mU_t = sub(U, [U[1]])
    sm1 = hom(U_t, U, [sigma(mU_t(g)) - mU_t(g) for g = gens(U_t)])
    eta_i = [preimage(sm1, theta - theta_i[i]) for i=1:length(not_inv)]

    eta_i = map(mU_t, eta_i)
    V = abelian_group(elementary_divisors(U))
    im_psi = [U[1], x[1]+ eta_i[1]]
    for i=2:length(not_inv)
      push!(im_psi, x[i] - x[1] + eta_i[i] - eta_i[1])
      #should be chosen to be pos. at place, flip signs...
    end
    for i=length(not_inv)+1:length(x)
      push!(im_psi, x[i])
      #should be chosen to be pos. at place, flip signs...
    end
    for i=1:length(y)
      push!(im_psi, y[i])
      push!(im_psi, sigma(y[i]))
    end
    psi = hom(V, U, im_psi)
    @assert is_bijective(psi)
    F = abelian_group([0 for i=2:length(x)])
    Hecke.assure_has_hnf(F)
    W, pro, inj = direct_product(V, F, task = :both)
    @assert isdefined(W, :hnf)

    ac = GrpAbFinGenMap(pro[1]*psi*sigma*pseudo_inv(psi)*inj[1])+ GrpAbFinGenMap(pro[2]*hom(F, W, [inj[1](preimage(psi, x[i])) - inj[2](F[i-1]) for i=2:length(x)]))
    Et = gmodule(G_inf, [ac])
    @assert is_consistent(Et)
    mq = pseudo_inv(psi)*inj[1]
    iEt = Oscar.GrpCoh.induce(Et, mG_inf, E, mq)
  end
  #test if the G-action is the same:
  # induce returns a map U -> E that should be a Z[G]-hom
  function is_G_lin(U, E, mUE, acU)
    G = E.G
    for g = gens(G)
      for u = gens(U)
        a = mUE(u)
        b = mUE(acU(g)(u))
        @assert b == action(E, g, a)
      end
    end
    return true
  end
  @hassert :GaloisCohomology 1 is_G_lin(U, iEt[1], iEt[2], g->action(E, g))
  @hassert :GaloisCohomology 1 is_consistent(iEt[1])
  
  S = S[s]
  I.S = S

  #TODO: precision: for some examples the default is too small
  @vprint :GaloisCohomology 2 " .. gathering the completions ..\n"
  Hecke.pushindent()
  L = [completion(k, x, 40*ramification_index(x)) for x = S]
  I.C = [x[2] for x = L]
  Hecke.popindent()
  @vprint :GaloisCohomology 2 " .. gathering the local modules ..\n"
  Hecke.pushindent()
  C = [gmodule(x[1], prime_field(x[1])) for x = L];
  I.D = [x[2] for x = C]
  I.L = [x[3] for x = C]
  @hassert :GaloisCohomology 1 all(x->is_consistent(x[1]), C)
  D = [Oscar.GrpCoh.induce(C[i][1], Oscar.decomposition_group(k, L[i][2], mG, C[i][2]), E, (mU*Hecke.extend_easy(L[i][2], C[i][3], codomain(mU)))) for i=1:length(S)]
  @hassert :GaloisCohomology 1 all(x->is_consistent(x[1]), D)
  @hassert :GaloisCohomology 1 all(x->is_G_lin(U, D[x][1], D[x][2], g->action(E, g)), 1:length(D))
  Hecke.popindent()
  @vprint :GaloisCohomology 2 " .. the big product and the quotient\n"
  @assert isdefined(iEt[1].M, :hnf)
  @assert all(x->isdefined(x[1].M, :hnf), D)

  F = direct_product(iEt[1], [x[1] for x = D]..., task = :both)
  I.M = F[1].M
  I.data = F[1]

  @hassert :GaloisCohomology 1 is_consistent(F[1])

  h = iEt[2]*F[3][1]+sum(D[i][2]*F[3][i+1] for i=1:length(S));
  @vtime :GaloisCohomology 2 q, mq = quo(F[1], h)
  @hassert :GaloisCohomology 1 is_consistent(q)
  @vtime :GaloisCohomology 2 q, _mq = simplify(q)
  @vtime :GaloisCohomology 2 mq = GrpAbFinGenMap(mq * pseudo_inv(_mq))
  @hassert :GaloisCohomology 1 is_consistent(q)
  I.mq = mq
  function idel(a::GrpAbFinGenElem)
    a = preimage(mq, a) # in F
    u = F[2][1](a) #in iEt need to get to the S-Unit somehow, maybe
    v = [m(a) for m = F[2][2:end]] #in the induced GModules
    #= TODO
     - the induced stuff is equivalent to doing all completions:
       for infinite places, same as finite ones over the same prime
       Galois operates transitive, and the :induce has coset reps
       -> sort places against coset reps
       -> sort primes against coset reps
       return a dictionary where keys are the 
         places, prime ideals
       and values are
         s.th. for the infinite places, for the reals we need the sign?
         elements in the completion for the prime ideals
         (think: nf_elem as the completions do not exist? only in 
           spirit via the cosets?)

     - we need also the inverse operation...
     =#
    return u, v
  end

  return q, idel, I
end

function Oscar.components(A::GrpAbFinGen)
  return get_attribute(A, :direct_product)
end

function Oscar.completion(I::IdelParent, P::NfAbsOrdIdl)
  s = [minimum(x) for x = I.S]
  p = findfirst(isequal(minimum(P)), s)
  @assert p !== nothing

  mKp = I.C[p]
  Kp = codomain(mKp)
  mUp = I.L[p]
  mGp = I.D[p]

  inj = Hecke.canonical_injection(I.M, p+1) #units are first
  pro = Hecke.canonical_projection(I.M, p+1)


  @assert domain(inj) == codomain(pro)

  J = components(I.M)[p+1]
  if mKp.P == P #easy case
    return Kp, mKp, mGp, mUp,  pro * Hecke.canonical_projection(J, 1) ,  Hecke.canonical_injection(J, 1)*inj
  end

  prm = get_attribute(J, :induce)[2]
  mG = I.mG

  z = findall(pr -> mG(pr)(mKp.P) == P, prm)
  pr = inv(prm[z[1]])
  
  nKp = MapFromFunc(x->mKp(mG(pr)(x)), y->mG(inv(pr))(preimage(mKp, y)), I.k, Kp)

  return Kp, nKp, mGp, mUp, pro * Hecke.canonical_projection(J, z[1]), Hecke.canonical_injection(J, z[1])*inj 
end

function Oscar.map_entries(mp::Map, C::GrpCoh.CoChain{N, G, M}; parent::GModule) where {N, G, M}
  d = Dict( k=> mp(v) for (k,v) = C.d)
  return GrpCoh.CoChain{N, G, elem_type(codomain(mp))}(parent, d)
end

function serre(C::GModule, A::IdelParent, P::NfAbsOrdIdl)
  Kp, mKp, mGp, mUp, pro, inj = completion(A, P)
  mp = decomposition_group(A.k, mKp, A.mG, mGp)
  qr = restrict(C, mp)
  s = Hecke.Hecke.local_fundamental_class_serre(Kp, prime_field(Kp))
#  Oscar.GModuleFromGap.istwo_cocycle(Dict( (g, h) => s(mGp(g), mGp(h)) for g = domain(mGp) for h = domain(mGp)), mGp)

  z = gmodule(domain(mGp), [hom(domain(mUp), domain(mUp), [preimage(mUp, mGp(g)(mUp(u))) for u = gens(domain(mUp))]) for g = gens(domain(mGp))])

  c = CoChain{2, PermGroupElem, GrpAbFinGenElem}(z, Dict{NTuple{2, PermGroupElem}, GrpAbFinGenElem}((g, h) => preimage(mUp, s(mGp(g), mGp(h))) for g = domain(mGp) for h = domain(mGp)))

  @assert Oscar.GrpCoh.istwo_cocycle(c)

  return c
end

function serre(C::GModule, A::IdelParent, P::Union{Integer, ZZRingElem})
  t = findfirst(isequal(ZZ(P)), [minimum(x) for x = A.S])
  Inj = Hecke.canonical_injection(A.M, t+1)
  Pro = Hecke.canonical_projection(A.M, t+1)

  inj = Hecke.canonical_injection(domain(Inj), 1)
  pro = Hecke.canonical_projection(domain(Inj), 1)

  Kp, mKp, mGp, mUp, _, _ = completion(A, A.S[t])
  @assert domain(inj) == domain(mUp) 
  mp = decomposition_group(A.k, mKp, A.mG, mGp)
 
  tt = serre(C, A, A.S[t])
  @assert tt.C.G == domain(mGp)

  I = domain(Inj)    
  zz = gmodule(C.G, [Inj * action(A.data, g) * Pro for g = gens(C.G)])
  mu = cohomology_group(zz, 2)
  q, mq = snf(mu[1])
  g = mu[2](mq(q[1]))
  hg = map_entries(Inj*A.mq, g, parent = C)
  gg = map_entries(pro, g, parent = tt.C)
  gg = Oscar.GrpCoh.CoChain{2, PermGroupElem, GrpAbFinGenElem}(tt.C, Dict( (g, h) => gg.d[mp(g), mp(h)] for g = tt.C.G for h = tt.C.G))

  nu = cohomology_group(tt.C, 2)
  ga = preimage(nu[2], gg)
  ta = preimage(nu[2], tt)
  return findfirst(x->x*ga == ta, 1:order(tt.C.G)), hg
  #so i*hg should restrict to the local fund class...
end


function global_fundamental_class(C::GModule, A::IdelParent)
  d = lcm([ramification_index(P) * inertia_degree(P) for P = A.S])
  G = C.G
  if d != order(G)
    error("sorry - no can do(yet)")
  end

  z = cohomology_group(C, 2)

  q, mq = snf(z[1])
  @assert ngens(q) == 1
  g = z[2](mq(gen(q, 1))) # to get a 2-CoCycle
  @assert Oscar.GrpCoh.istwo_cocycle(g)

  scale = []

  for P = A.S
    s = serre(C, A, minimum(P))
    push!(scale, s)
  end
  #put to gether..
  return scale, z, mq 
end

function Oscar.orbit(C::GModule{PermGroup, GrpAbFinGen}, o::GrpAbFinGenElem)
  or = Set([o])
  done = false
  while !done
    sz = length(or)
    done = true
    for f = C.ac
      while true
        or = union(or, [f(x) for x = or])
        if length(or) == sz
          break
        end
        done = false
        sz = length(or)
      end
    end
  end
  return collect(or)
end

"""
    shrink(C::GModule{PermGroup, GrpAbFinGen}, attempts::Int = 10)

Tries to find cohomologically trivial submodules to factor out.
Returns a cohomologically equivalent module with fewer generators and
the quotient map.
"""
function shrink(C::GModule{PermGroup, GrpAbFinGen}, attempts::Int = 10)
  local mq
  q = C
  first = true
  while true
    prog = false
    for i=1:attempts
      o = Oscar.orbit(q, rand(gens(q.M)))
      if length(o) == order(group(q))
        s, ms = sub(q.M, o)
        if rank(s) == length(o)
          q, _mq = quo(q, ms)
          if first
            mq = _mq
            first = false
          else
            mq = mq*_mq
          end
          q, _mq = simplify(q)
          mq = mq*inv(_mq)
          prog = true
          break
        end
      end
    end
    prog || return q, mq
  end
end

function Oscar.direct_sum(G::GrpAbFinGen, H::GrpAbFinGen, V::Vector{<:Map{GrpAbFinGen, GrpAbFinGen}})
  dG = get_attribute(G, :direct_product)
  dH = get_attribute(H, :direct_product)

  if dG === nothing || dH === nothing
    error("both groups need to be direct products")
  end
  @assert length(V) == length(dG) == length(dH)

  @assert all(i -> domain(V[i]) == dG[i] && codomain(V[i]) == dH[i], 1:length(V))
  h = hom(G, H, cat([matrix(V[i]) for i=1:length(V)]..., dims=(1,2)), check = !true)
  return h

end

function Oscar.simplify(C::GModule{PermGroup, GrpAbFinGen})
  s, ms = snf(C.M)
  S = GModule(s, C.G, [GrpAbFinGenMap(ms*x*pseudo_inv(ms)) for x = C.ac])
  if isdefined(C, :iac)
    S.iac = [GrpAbFinGenMap(ms*x*pseudo_inv(ms)) for x = C.iac]
  end
  return S, ms
end

function Base.show(io::IO, I::IdelParent)
  print(io, "Idel-group for $(I.k) using $(sort(collect(Set(minimum(x) for x = I.S)))) as places")
end

end # module GrpCoh

using .GaloisCohomology_Mod
export is_coboundary, idel_class_gmodule


#=
x^4 - 60*x^2 + 16

=#
