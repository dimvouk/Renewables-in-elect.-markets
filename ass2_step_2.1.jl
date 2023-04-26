#Import libraries
using JuMP
using Gurobi
using Printf
using CSV, DataFrames


#**************************************************
#Get Data
include("ass2.1_data.jl")

#**************************************************

# Conventional Generator Set [24:12]
G = 8

# Demand set [24 : 17]
D = 4

# Node set
N = 6

# Sucseptance
B = 50

#**************************************************
# MODEL
Step_2_1=Model(Gurobi.Optimizer)

#**************************************************

#Variables - power in MW
@variable(Step_2_1,pg[g=1:G] >=0)      #Hourly power generation - Conventional generator g (MW)
@variable(Step_2_1,pd[d=1:D] >=0)      #Hourly power demand (MW)
@variable(Step_2_1,theta[n=1:N])      #Voltage angle of node n at time t

#**************************************************

#Objective function
@objective(Step_2_1, Max, 
sum(demand_bid[d] * pd[d] for d=1:D)                 #Total offer value 
-sum(gen_cost[g] * pg[g] for g=1:G)                #Total value of generator production       
)

# Capacity constraints
@constraint(Step_2_1,[d=1:D], 0 <= pd[d] <= demand_cons[d] )               # Capacity for demand (MW)
@constraint(Step_2_1,[g=1:G], 0 <= pg[g] <= gen_cap[g] )                   # Capacity for generator (MW)


# Transmission capacity constraint
#= For sensitivity analysis, change to transm_capacity_sensitivity
for t=1:T
    for n=1:N
        for m=1:N   
            if transm_capacity[n,m] != 0
                @constraint(Step3Nodal,
                -transm_capacity[n,m] <= B * (theta[t, n] - theta[t, m]) <= transm_capacity[n,m])
            end
        end
    end
end
=#
#@constraint(Step3Nodal, transcap[t=1:T,n=1:N,m=1:N], -transm_capacity[n,m] <= B * (theta[t, n] - theta[t, m]) <= transm_capacity[n,m])

# Voltage angle constraint
@constraint(Step_2_1, [n=1:N], -pi <= theta[n] <= pi)

# Reference constraintnode
@constraint(Step_2_1, theta[1] == 0)

# Create a function that returns the connected nodes in an ingoing and outgoing direction
connections = length(transm_connections)
function connected_nodes(node)
    outgoing = []
    ingoing = []
    for i=1:connections
        if node == transm_connections[i][1]
            push!(outgoing, transm_connections[i][2])
        elseif node == transm_connections[i][2]
            push!(ingoing, transm_connections[i][1])
        end
    end
    return(outgoing, ingoing)
end

# Elasticity constraint, balancing supply and demand
@constraint(Step_2_1, powerbalance[n=1:N],
                0 == sum(pd[d] for d in node_dem[n]) + # Demand
                sum(B * (theta[n] - theta[m]) for m in connected_nodes(n)[2]) - # Ingoing transmission lines
                sum(B * (theta[m] - theta[n]) for m in connected_nodes(n)[1]) - # Outgoing transmission lines
                sum(pg[g] for g in node_gen[n]) # Conventional generator production
                )


#************************************************************************
# Solve
solution = optimize!(Step_2_1)
#**************************************************

# Constructing outputs:
market_price = zeros(N)
system_demand = zeros(D)

#Check if optimal solution was found
if termination_status(Step_2_1) == MOI.OPTIMAL
    println("Optimal solution found")

    market_price = dual.(powerbalance[:])
    system_demand = value.(pd[:])

    # Print objective value
    println("Objective value: ", objective_value(Step_2_1))

    #= Remove comment to print market clearing price and power flow in transmission lines .
    
    # Print hourly market price in each node
    println("Hourly Market clearing price")
    market_price = dual.(powerbalance[:])
    for t = 1:T
        for n=1:N
            println("t$t, n$n: ", dual(powerbalance[t,n]))
        end
    end
    Print power flow in each transmission line
    println("Power flow in transmission lines")
    for t = 1:T
    for n=1:N
            for m=1:N
                if transm_capacity[n,m] != 0
                    println("t$t, n$n, m$m: ", B*value(theta[t, n] - theta[t, m]))
                end
            end
        end
    end
=# 

else 
    println("No optimal solution found")
end