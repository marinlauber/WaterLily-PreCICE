import WaterLily: AbstractBody,measure,sdf
"""
    Bodies(bodies, ops::AbstractVector)

  - `bodies::Vector{AutoBody}`: Vector of `AutoBody`
  - `ops::Vector{Function}`: Vector of operators for the superposition of multiple `AutoBody`s

Superposes multiple `body::AutoBody` objects together according to the operators `ops`.
While this can be manually performed by the operators implemented for `AutoBody`, adding too many
bodies can yield a recursion problem of the `sdf` and `map` functions not fitting in the stack.
This type implements the superposition of bodies by iteration instead of recursion, and the reduction of the `sdf` and `map`
functions is done on the `mesure` function, and not before.
The operators vector `ops` specifies the operation to call between two consecutive `AutoBody`s in the `bodies` vector.
Note that `+` (or the alias `∪`) is the only operation supported between `Bodies`.
"""
struct AbsBodies <: AbstractBody
    bodies::Vector{AbstractBody}
    ops::Vector{Function}
    function AbsBodies(bodies, ops::AbstractVector)
        all(x -> x==Base.:+ || x==Base.:- || x==Base.:∩ || x==Base.:∪, ops) &&
            ArgumentError("Operations array `ops` not supported. Use only `ops ∈ [+,-,∩,∪]`")
        length(bodies) != length(ops)+1 && ArgumentError("length(bodies) != length(ops)+1")
        new(bodies,ops)
    end
end
AbsBodies(bodies) = AbsBodies(bodies,repeat([+],length(bodies)-1))
AbsBodies(bodies, op::Function) = AbsBodies(bodies,repeat([op],length(bodies)-1))
Base.:+(a::AbsBodies, b::AbsBodies) = AbsBodies(vcat(a.bodies, b.bodies), vcat(a.ops, b.ops))
Base.:∪(a::AbsBodies, b::AbsBodies) = a+b
Base.copy(b::AbsBodies) = AbsBodies(copy(b.bodies),copy(b.ops))

"""
    d = sdf(a::Bodies,x,t)

Computes distance for `Bodies` type.
"""
function sdf(b::AbsBodies,x,t;kwargs...)
    d₁ = sdf(b.bodies[1],x,t;kwargs...)
    for i in 2:length(b.bodies)
        d₁ = reduce_d(d₁,sdf(b.bodies[i],x,t;kwargs...),b.ops[i-1])
    end
    return d₁
end
"""
    reduce_d(d₁,d₂,op)

Reduces two different `d` value depending on the `op` between them.
"""
function reduce_d(d₁,d₂,op)
    (Base.:+ == op || Base.:∪ == op) && return min(d₁,d₂)
    Base.:- == op && return max(d₁,-d₂)
    Base.:∩ == op && return max(d₁,d₂)
    return d₁
end

using ForwardDiff
"""
    d,n,V = measure(body::AutoBody||Bodies,x,t;fastd²=Inf)

Determine the implicit geometric properties from the `sdf` and `map`.
The gradient of `d=sdf(map(x,t))` is used to improve `d` for pseudo-sdfs.
The velocity is determined _solely_ from the optional `map` function.
Skips the `n,V` calculation when `d²>fastd²`.
"""
function measure(body::AbsBodies,x,t;fastd²=Inf)
    d,n,V = measure(body.bodies[1],x,t;fastd²)
    for i in 2:length(body.bodies)
        dᵢ,nᵢ,Vᵢ = measure(body.bodies[i],x,t;fastd²)
        d,n,V = reduce_bodies(d,n,V,dᵢ,nᵢ,Vᵢ,body.ops[i-1])
    end
    return d,n,V
end
"""
    reduce_bodies(d₁,n₁,v₁,d₂,n₂,v₂,op)

Reduces two different `d`, `n` and `v` values depending on the operation applied between them.
"""
function reduce_bodies(d₁,n₁,v₁,d₂,n₂,v₂,op)
    (Base.:+ == op || Base.:∪ == op) && d₁ > d₂ && return (d₂,n₂,v₂)
    Base.:- == op && d₁ < -d₂ && return (-d₂,-n₂,v₂) # velocity is not inverted
    Base.:∩ == op && d₁ < d₂ && return (d₂,n₂,v₂)
    return d₁,n₁,v₁
end
