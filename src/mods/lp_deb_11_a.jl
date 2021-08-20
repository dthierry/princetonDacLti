# vim: set wrap
#: by David Thierry 2021
#: Set all the eqns to hslice - 1
using JuMP
using Cbc
using DataFrames
using CSV

#: Data frames section
#: Load parameters

df_gas = DataFrame(CSV.File("../reg/gas_coeffs.csv"))
df_steam_full_power = DataFrame(CSV.File("../reg/steam_coeffs.csv"))
df_steam_full_steam = DataFrame(CSV.File("../reg/steam_coeffs_v3.csv"))

#: Load Prices
df_pow_c = DataFrame(CSV.File("../resources/FLECCSPriceSeriesData.csv"))
df_ng_c = DataFrame(CSV.File("../resources/natural_gas_price.csv"))



#: Assign parameters

#: Gas parameters
bPowGasTeLoad = df_gas[1, 2]
aPowGasTeLoad = df_gas[1, 3]

bFuelEload = df_gas[2, 2]
aFuelEload = df_gas[2, 3]
lbcoToTonneco = 0.4535924 / 1000
bEmissFactEload = df_gas[3, 2] * lbcoToTonneco
aEmissFactEload = df_gas[3, 3] * lbcoToTonneco

bPowHpEload = df_gas[4, 2] / 1000  #: To scale the kW to MW
aPowHpEload = df_gas[4, 3] / 1000

bPowIpEload = df_gas[5, 2] / 1000
aPowIpEload = df_gas[5, 3] / 1000

bAuxRateGas = df_gas[6, 2] / 1000
aAuxRateGas = df_gas[6, 3] / 1000

#: Steam params
bCcRebDutyEload = df_steam_full_steam[2, 2]
aCcRebDutyEload = df_steam_full_steam[2, 3]

#: Full power gives you the min steam
bDacSteaBaseEload = df_steam_full_power[3, 2]  
aDacSteaBaseEload = df_steam_full_power[3, 3]

bSideSteaEload = df_steam_full_steam[3, 2] - df_steam_full_power[3, 2]
aSideSteaEload = df_steam_full_steam[3, 3] - df_steam_full_power[3, 3]

bAuxRateStea = df_steam_full_power[4, 2] / 1000
aAuxRateStea = df_steam_full_power[4, 3] / 1000

aLpSteaToPow = 78.60233832  # MMBtu to kwh

kwhToMmbtu = 3412.1416416 / 1e+06
#aSteaUseRateDacAir = 1944 * kwhToMmbtu
#aSteaUseRateDacFlue = 1944 * kwhToMmbtu
# 7 GJ/tonneCO
aSteaUseRateDacAir = 5 * (7 * 1e+06 / 3600) * kwhToMmbtu
aSteaUseRateDacFlue = 5 * (7 * 1e+06 / 3600) * kwhToMmbtu

aPowUseRateDacAir = 500 / 1000
aPowUseRateDacFlue = 250 / 1000
# 1 mmol/gSorb #
# per gCo/gSorb
gCogSorbRatio = 1e-03 * 44.0095

aSorbCo2CapFlue = 1 * gCogSorbRatio
aSorbCo2CapAir = gCogSorbRatio
#aSorbAmountFreshFlue = 176. * 10  # Tonne sorb
#aSorbAmountFreshAir = 176. * 10  # Tonne sorb

aSorbAmountFreshFlue = 176. * 10   # Tonne sorb (Max. heat basis)
aSorbAmountFreshAir = 3162.18 - 176. * 10  # Tonne sorb (Max. heat basis)


aCapRatePcc = 0.97
# 2.4 MJ/kg (1,050 Btu/lb) CO2 page 379/
#aSteaUseRatePcc = aSteaUseRateDacFlue * 0.2
#aSteaUseRatePcc = 2.4 * 1000 * 1000 / 3600 * kwhToMmbtu 
#println(aSteaUseRatePcc)
# aPowUseRatePcc = 0.173514487  # MWh/tonneCoi2 (old)
aSteaUseRatePcc = 2.69 + 0.0218 + 0.00127 # MMBTU/tonne CO2 (trimeric)
println(aSteaUseRatePcc)
aPowUseRatePcc = 0.047 # MWh/tonne CO2 (trimeric)

#: Horizon Lenght
tHorz = 1000 - 1


#: Slices per hour
hSlice = 4  # the number of slices of a given hour
# There are tHorz - 1 slices
# Each slice has hSlice points, but only states have the 0th

# If there's several slices in an hour we kind of need to divide the
# hourly-based quantities :(
sliceFact = 1/hSlice

aPowGasTeLoad = aPowGasTeLoad * sliceFact
bPowGasTeLoad = bPowGasTeLoad * sliceFact
aFuelEload = aFuelEload * sliceFact
bFuelEload = bFuelEload * sliceFact
aEmissFactEload = aEmissFactEload * sliceFact
bEmissFactEload = bEmissFactEload * sliceFact
aAuxRateGas = aAuxRateGas * sliceFact
bAuxRateGas = bAuxRateGas * sliceFact
aPowHpEload = aPowHpEload * sliceFact
bPowHpEload = bPowHpEload * sliceFact
aPowIpEload = aPowIpEload * sliceFact
bPowIpEload = bPowIpEload * sliceFact
aCcRebDutyEload = aCcRebDutyEload * sliceFact
bCcRebDutyEload = bCcRebDutyEload * sliceFact
aDacSteaBaseEload = aDacSteaBaseEload * sliceFact
bDacSteaBaseEload = bDacSteaBaseEload * sliceFact
aSideSteaEload = aSideSteaEload * sliceFact
bSideSteaEload = bSideSteaEload * sliceFact
aAuxRateStea = aAuxRateStea * sliceFact
bAuxRateStea = bAuxRateStea * sliceFact


# USD/MWh
pow_price =(df_pow_c[!, "MiNg_150_ERCOT"])  # USD/MWh

# pow_price =(df_pow_c[!, "MiNg_150_PJM-W"])  # USD/MWh
#: Natural gas price
# 0.056 lb/cuft STP
#std_w_ng1000cuft = 0.056 * 1000
#cNgPerLbUsd = (3.5 / 1000) / 0.056

# Cost of natural gas
cNgPerMmbtu = 3.5

m = Model()

# aPowUseRateComp = 0.279751187  # MWh/tonneCo2
aPowUseRateComp = 0.076 # MWh/tonneCo2 (Trimeric)

# Other costs
cCostInvCombTurb = 1e+02
cCostInvSteaTurb = 1e+02
cCostInvTransInter = 1e+02
cCostInvPcc = 1e+02
cCostInvDac = 1e+03
cCostInvComp = 1e+01

# Cost parameters.
cEmissionPrice = 1.5e+02 # USD/tonne CO2
cCo2TranspPrice = 1e+00
pCo2Credit = 1e+00


#vCapCombTurb = 3.
vCapSteaTurb = 2.
vCapTransInter = 5.
vCapPcc = 20.
vCapComp = 1000.
# Capital Cost DAC USD/tCo2/yr 
cCostInvDacUsdtCo2yr = 750
cCostFixedDacUsdtCo2yr = 25
cCostVariableDacUsdtCo2yr = 12


@variable(m, 0 <= lambda0[0:tHorz, 0] <= 1) 
@variable(m, 0 <= lambda1[0:tHorz, 0:1] <= 1) # This has 2 points

@variable(m, y[0:tHorz, 0:1], Bin, start = 0)  # On and off

for i in 0:tHorz
    set_start_value(y[i, 0], 1)
end

@variable(m, xLoad[0:tHorz, 0:1])
@variable(m, z[0:tHorz, 0:1, 0:1], Bin)


@variable(m, 0 <= yGasTelecLoad[0:tHorz, 0:hSlice-1] <= 100)
@variable(m, 0 <= xPowGasTur[0:tHorz, 0:hSlice-1])
@variable(m, 0 <= xPowGross[0:tHorz, 0:hSlice-1])
@variable(m, 0 <= xPowOut[0:tHorz, 0:hSlice-1])

@variable(m, 0 <= xAuxPowGasT[0:tHorz, 0:hSlice-1])

# Steam Turbine
@variable(m, 0 <= xPowHp[0:tHorz, 0:hSlice-1])
@variable(m, 0 <= xPowIp[0:tHorz, 0:hSlice-1])
@variable(m, 0 <= xPowLp[0:tHorz, 0:hSlice-1])

@variable(m, 0 <= xFuel[0:tHorz, 0:hSlice-1])
@variable(m, 0 <= xCo2Fuel[0:tHorz, 0:hSlice-1])
@variable(m, 0 <= xDacSteaDuty[0:tHorz, 0:hSlice-1])


@variable(m, 0 <= xCcRebDuty[0:tHorz, 0:hSlice-1])
@variable(m, 0 <= xDacSteaBaseDuty[0:tHorz, 0:hSlice-1])

@variable(m, 0 <= xSideSteam[0:tHorz, 0:hSlice-1])
@variable(m, 0 <= xSteaPowLp[0:tHorz, 0:hSlice-1])
@variable(m, 0 <= xSideSteaDac[0:tHorz, 0:hSlice-1])

#
@variable(m, 0 <= xPowSteaTur[0:tHorz, 0:hSlice-1])
@variable(m, 0 <= xAuxPowSteaT[0:tHorz, 0:hSlice-1])

# Pcc
#@variable(m, 0 <= xCo2CapPcc[0:tHorz - 1] <= vCapPcc)
@variable(m, 0 <= xCo2CapPcc[0:tHorz, 0:hSlice-1])
@variable(m, 0 <= xSteaUsePcc[0:tHorz, 0:hSlice-1])
@variable(m, 0 <= xPowUsePcc[0:tHorz, 0:hSlice-1])
@variable(m, 0 <= xCo2PccOut[0:tHorz, 0:hSlice-1])
#@variable(m, 0 <= vCo2PccVent[0:tHorz - 1] <= 0.1)
@variable(m, 0 <= vCo2PccVent[0:tHorz, 0:hSlice-1])
#vCo2PccVent = 0.0
@variable(m, 0 <= xCo2DacFlueIn[0:tHorz, 0:hSlice-1])
@variable(m, 0 <= xPccSteaSlack[0:tHorz, 0:hSlice-1])

# Dac-Flue
@variable(m, 0 <= xA0Flue[0:tHorz, 0:hSlice-1]) # Kind of input 

@variable(m, 0 <= xA1Flue[0:tHorz, 0:hSlice]) # State


@variable(m, 0 <= xR0Flue[0:tHorz, 0:hSlice-1])  # Kind of input

@variable(m, 0 <= xR1Flue[0:tHorz, 0:hSlice])  # State
@variable(m, 0 <= xFflue[0:tHorz, 0:hSlice])  # State
@variable(m, 0 <= xSflue[0:tHorz, 0:hSlice])  # State


@variable(m, 0 <= xCo2CapDacFlue[0:tHorz, 0:hSlice-1])
@variable(m, 0 <= xSteaUseDacFlue[0:tHorz, 0:hSlice-1])
@variable(m, 0 <= xPowUseDacFlue[0:tHorz, 0:hSlice-1])
@variable(m, 0 <= xCo2DacVentFlue[0:tHorz, 0:hSlice-1])

# Dac-Air
@variable(m, 0 <= xA0Air[0:tHorz, 0:hSlice-1]) # Kind of input

@variable(m, 0 <= xA1Air[0:tHorz, 0:hSlice]) # State
@variable(m, 0 <= xA2Air[0:tHorz, 0:hSlice]) # State

@variable(m, 0 <= xR0Air[0:tHorz, 0:hSlice-1])  # Kind of input

@variable(m, 0 <= xR1Air[0:tHorz, 0:hSlice])  # State
@variable(m, 0 <= xFair[0:tHorz, 0:hSlice])  # State
@variable(m, 0 <= xSair[0:tHorz, 0:hSlice])  # State


@variable(m, 0 <= xCo2CapDacAir[0:tHorz, 0:hSlice-1])
@variable(m, 0 <= xSteaUseDacAir[0:tHorz, 0:hSlice-1])
@variable(m, 0 <= xPowUseDacAir[0:tHorz, 0:hSlice-1])

@variable(m, 0 <= xDacSteaSlack[0:tHorz, 0:hSlice-1])
# DAC hourly capacity
#



# CO2 compression
@variable(m, 0 <= xCo2Comp[0:tHorz, 0:hSlice-1])
@variable(m, 0 <= xPowUseComp[0:tHorz, 0:hSlice-1])
#@variable(m, 0 <= vCapComp)
@variable(m, xCo2Vent[0:tHorz, 0:hSlice-1])  # This used to be only positive.

@variable(m, 0 <= xAuxPow[0:tHorz, 0:hSlice-1])

# Constraints
# Op mode
# Down times
# Up times

# Disjunction 0 (off)

extreme_d_0 = [0]

@constraint(m, cconvx0[i = 0:tHorz],
    sum(lambda0[i, k] * extreme_d_0[k + 1] for k in 0) ==
    xLoad[i, 0]  # There is only a single extreme
    )

@constraint(m, slambda0[i = 0:tHorz],
    sum(lambda0[i, k] for k in 0) == y[i, 0]
    )

@constraint(m, bm0[i = 0:tHorz],
    xLoad[i, 0] <= 100 * y[i, 0]
    )



# Disjunction 1 (on)

extreme_d_1 = [60.0, 100.0]

@constraint(m, cconvx1[i = 0:tHorz],
    sum(lambda1[i, k] * extreme_d_1[k + 1] for k in 0:1) ==
    xLoad[i, 1]
    )

@constraint(m, slambda1[i = 0:tHorz],
    sum(lambda1[i, k] for k in 0:1) == y[i, 1]
    )

@constraint(m, bm1[i = 0:tHorz],
    xLoad[i, 1] <= 100 * y[i, 1]
    )


# Overall Disjunction


@constraint(m, spr[i = 0:tHorz],
    yGasTelecLoad[i, 0] == sum(xLoad[i, k] for k in 0:1)
    )


@constraint(m, sy[i = 0:tHorz],
    sum(y[i, k] for k in 0:1) == 1
    )

# Switch

@constraint(m, switchc[i = 1:tHorz],
    z[i, 0, 1] - z[i, 1, 0] == y[i, 1] - y[i-1, 1])

KminOffOn = 24
@constraint(m, minstay[i = (KminOffOn-1):tHorz],
    y[i, 1] >= sum(z[i - k, 0, 1] for k in 0:(KminOffOn-1))
    )


# Gas Turbine
@constraint(m, powGasTur[i = 0:tHorz, j = 0:hSlice-1], 
            xPowGasTur[i, j] == (aPowGasTeLoad * yGasTelecLoad[i, j] 
            + bPowGasTeLoad)
           )
# 
@constraint(m, fuelEq[i = 0:tHorz, j = 0:hSlice-1], 
            xFuel[i, j] == aFuelEload * yGasTelecLoad[i, j] 
            + bFuelEload
           )
# 
@constraint(m, co2FuelEq[i = 0:tHorz, j = 0:hSlice-1], 
            xCo2Fuel[i, j] == aEmissFactEload * yGasTelecLoad[i, j] 
            + bEmissFactEload
           )

@constraint(m, auxPowGasT[i = 0:tHorz, j = 0:hSlice-1],
            xAuxPowGasT[i, j] == aAuxRateGas * yGasTelecLoad[i, j] 
            + bAuxRateGas
           )
# 
# Steam
# 
@constraint(m, powHpEq[i = 0:tHorz, j = 0:hSlice-1], 
            xPowHp[i, j] == aPowHpEload * yGasTelecLoad[i, j] 
            + bPowHpEload
           )
# 
@constraint(m, powIpEq[i = 0:tHorz, j = 0:hSlice-1], 
            xPowIp[i, j] == aPowIpEload * yGasTelecLoad[i, j] 
            + bPowIpEload
           )

# 
@constraint(m, powLpEq[i = 0:tHorz, j = 0:hSlice-1], 
#            xPowLp[i] == aPowLpEload * yGasTelecLoad[i] + bPowLpEload
            xPowLp[i, j] == xSteaPowLp[i, j] * aLpSteaToPow / 1000
           )
# 
@constraint(m, powerSteaEq[i = 0:tHorz, j = 0:hSlice-1], 
            xPowSteaTur[i, j] == 
            xPowHp[i, j] + xPowIp[i, j] + xPowLp[i, j]
           )

@constraint(m, ccRebDutyEq[i = 0:tHorz, j = 0:hSlice-1],
            xCcRebDuty[i, j] == 
            aCcRebDutyEload * yGasTelecLoad[i, j] 
            + bCcRebDutyEload
           )

@constraint(m, dacSteaDutyEq[i = 0:tHorz, j = 0:hSlice-1],
            xDacSteaBaseDuty[i, j] == aDacSteaBaseEload * yGasTelecLoad[i, j] 
            + bDacSteaBaseEload
           )


@constraint(m, sideSteaEloadEq[i = 0:tHorz, j = 0:hSlice-1],
            xSideSteam[i, j] == aSideSteaEload * yGasTelecLoad[i, j] 
            + bSideSteaEload
           )

@constraint(m, sideSteaRatioEq[i = 0:tHorz, j = 0:hSlice-1],
            xSideSteam[i, j] == xSideSteaDac[i, j] + xSteaPowLp[i, j]
           )

@constraint(m, availSteaDacEq[i = 0:tHorz, j = 0:hSlice-1],
            xDacSteaDuty[i, j] == xDacSteaBaseDuty[i, j] + xSideSteaDac[i, j]
           )

@constraint(m, auxPowSteaTEq[i = 0:tHorz, j = 0:hSlice-1],
            xAuxPowSteaT[i, j] == aAuxRateStea * yGasTelecLoad[i, j] 
            + bAuxRateStea 
           )

# PCC
# 
#@constraint(m, co2CapPccEq[i = 0:tHorz - 1], 
#xCo2CapPcc[i] == aCo2PccCapRate * xCo2Fuel[i])
@constraint(m, co2CapPccEq[i = 0:tHorz, j = 0:hSlice-1], 
            xCo2CapPcc[i, j] == aCapRatePcc * xCo2Fuel[i, j])
# 
@constraint(m, co2PccOutEq[i = 0:tHorz, j = 0:hSlice-1], 
            xCo2PccOut[i, j] == xCo2Fuel[i, j] - xCo2CapPcc[i, j])
# 
@constraint(m, co2DacFlueInEq[i = 0:tHorz, j = 0:hSlice-1], 
            xCo2DacFlueIn[i, j] == xCo2PccOut[i, j] - vCo2PccVent[i, j])
# 
# @constraint(m, co2CapPccIn[i = 0:tHorz - 1], xCo2CapPcc[i] <= vCapPcc)
# Dav: Sometimes there is not enough steam, so we have to relax this constraint 
@constraint(m, steamUsePccEq[i = 0:tHorz, j = 0:hSlice-1], 
            xSteaUsePcc[i, j] <= aSteaUseRatePcc * xCo2CapPcc[i, j])
# 
@constraint(m, powerUsePccEq[i = 0:tHorz, j = 0:hSlice-1], 
            xPowUsePcc[i, j] == aPowUseRatePcc * xCo2CapPcc[i, j]
           )

@constraint(m, pccSteaSlack[i = 0:tHorz, j = 0:hSlice-1], 
            xPccSteaSlack[i, j] == xCcRebDuty[i, j] - xSteaUsePcc[i, j])

# DAC-Flue
# Flue gas takes 15 minutes to saturation?
#: "State equation"
@constraint(m, a1dFlueEq[i = 0:tHorz, j=1:hSlice], 
            xA1Flue[i, j] == xA0Flue[i, j-1]
           )


#: "State equation"
@constraint(m, aRdFlueEq[i = 0:tHorz, j=1:hSlice], 
            xR1Flue[i, j] == xR0Flue[i, j-1]
           )
#: "State equation"
@constraint(m, storeFflueeq[i = 0:tHorz, j = 1:hSlice], 
            xFflue[i, j] == xFflue[i, j-1] - xA0Flue[i, j-1] + xR1Flue[i, j-1]
           )
#: "State equation"
@constraint(m, storeSflueeq[i = 0:tHorz, j = 1:hSlice], 
            xSflue[i, j] == xSflue[i, j-1] - xR0Flue[i, j-1] + xA1Flue[i, j-1]
           )
# Initial conditions
@constraint(m, icXa1FlueEq, xA1Flue[0, 0] == 0.)
@constraint(m, icAR1FlueEq, xR1Flue[0, 0] == 0.)
@constraint(m, capDacFlueEq, xFflue[0, 0] == aSorbAmountFreshFlue)
@constraint(m, icSsFlueEq, xSflue[0, 0] == 0.)
# End-point constraints we need to get rid of them and then put them back
@constraint(m, endXa1FlueEq, xA1Flue[tHorz, hSlice] == 0.)
@constraint(m, endAR1FlueEq, xR1Flue[tHorz, hSlice] == 0.)
@constraint(m, endDacFlueEq, xFflue[tHorz, hSlice] == aSorbAmountFreshFlue)
@constraint(m, endSsFlueEq, xSflue[tHorz, hSlice] == 0.)

#
#These dac related variables must start at 0 and end at 1-hslice
@constraint(m, co2CapDacFlueEq[i = 0:tHorz, j = 0:hSlice-1], 
            xCo2CapDacFlue[i, j] == 
            #aSorbCo2CapFlue * xR1Flue[i, j]
            aSorbCo2CapFlue * xA1Flue[i, j]
           )
#
@constraint(m, steamUseDacFlueEq[i = 0:tHorz, j = 0:hSlice-1], 
            xSteaUseDacFlue[i, j] == 
            #aSteaUseRateDacFlue * xCo2CapDacFlue[i, j]
            aSteaUseRateDacFlue * aSorbCo2CapFlue * xR1Flue[i, j]
           )
#
@constraint(m, powUseDacFlueEq[i = 0:tHorz, j = 0:hSlice-1], 
            xPowUseDacFlue[i, j] == aPowUseRateDacFlue * xCo2CapDacFlue[i, j]
           )
# Equal to the amount vented, at least in flue mode.
@constraint(m, co2DacFlueVentEq[i = 0:tHorz, j = 0:hSlice-1], 
            xCo2DacVentFlue[i, j] == xCo2DacFlueIn[i, j] - xCo2CapDacFlue[i, j]
           )

# DAC-Air
# Bluntly assume we can just take CO2 from air in pure form.
# "State equation"
@constraint(m, a1dAirEq[i = 0:tHorz, j = 1:hSlice], 
            xA1Air[i, j] == xA0Air[i, j - 1]
           )
# "State equation"
@constraint(m, a2dAirEq[i = 0:tHorz, j = 1:hSlice], 
            xA2Air[i, j] == xA1Air[i, j - 1]
           )
# "State equation"
@constraint(m, aRdAirEq[i = 0:tHorz, j = 1:hSlice], 
            xR1Air[i, j] == xR0Air[i, j - 1]
           )
# "State equation"
@constraint(m, storeFairEq[i = 0:tHorz, j = 1:hSlice], 
            xFair[i, j] == xFair[i, j-1] - xA0Air[i, j-1] + xR1Air[i, j-1]
           )
# "State equation"
@constraint(m, storeSaireq[i = 0:tHorz, j = 1:hSlice], 
            xSair[i, j] == xSair[i, j-1] - xR0Air[i, j-1] + xA2Air[i, j-1]
           )

# Initial conditions - Air
#@constraint(m, capDacAirEq, xFair[0] == xSorbFreshAir)
@constraint(m, capDacAirEq, xFair[0, 0] == aSorbAmountFreshAir)
@constraint(m, icA1AirEq, xA1Air[0, 0] == 0.)
@constraint(m, icA2AirEq, xA2Air[0, 0] == 0.)
@constraint(m, icAR1AirEq, xR1Air[0, 0] == 0.)
@constraint(m, icSsAirEq, xSair[0, 0] == 0.)
# End-point conditions - Air

@constraint(m, endDacAirEq, xFair[tHorz, hSlice] == aSorbAmountFreshAir)
@constraint(m, endA1AirEq, xA1Air[tHorz, hSlice] == 0.)
@constraint(m, endA2AirEq, xA2Air[tHorz, hSlice] == 0.)
@constraint(m, endAR1AirEq, xR1Air[tHorz, hSlice] == 0.)
@constraint(m, endSsAirEq, xSair[tHorz, hSlice] == 0.)

#@constraint(m, endDacAirEq, xFair[0] == xSorbFreshAir)
#@constraint(m, endDacAirEq, xFair[0, 0] == aSorbAmountFreshAir)
#@constraint(m, endA1AirEq, xA1Air[0, 0] == 0.)
#@constraint(m, endA2AirEq, xA2Air[0, 0] == 0.)
#@constraint(m, endAR1AirEq, xR1Air[0, 0] == 0.)
#@constraint(m, endSsAirEq, xSair[0, 0] == 0.)

#
# Money, baby.
@constraint(m, co2CapDacAirEq[i = 0:tHorz, j=0:hSlice-1], 
            xCo2CapDacAir[i, j] == 
            #aSorbCo2CapAir * xR1Air[i, j]
            (aSorbCo2CapAir * xA1Air[i, j]/2 + aSorbCo2CapAir * xA2Air[i, j]/2)
           )
# 
@constraint(m, steamUseDacAirEq[i = 0:tHorz, j=0:hSlice-1], 
            xSteaUseDacAir[i, j] == 
            #aSteaUseRateDacAir * xCo2CapDacAir[i, j]
            aSteaUseRateDacAir * aSorbCo2CapAir * xR1Air[i, j]
           )
# 
@constraint(m, powUseDacAirEq[i = 0:tHorz, j=0:hSlice-1], 
            xPowUseDacAir[i, j] == aPowUseRateDacAir * xCo2CapDacAir[i, j]
           )


@constraint(m, dacSteaSlackEq[i = 0:tHorz, j=0:hSlice-1], 
            xDacSteaSlack[i, j] == xDacSteaDuty[i, j] 
            - xSteaUseDacFlue[i, j] 
            - xSteaUseDacAir[i, j]
           )


# Co2 Compression
# 
@constraint(m, co2CompEq[i = 0:tHorz, j = 0:hSlice-1], 
            xCo2Comp[i, j] == xCo2CapPcc[i, j] 
            + xCo2CapDacFlue[i, j] 
            + xCo2CapDacAir[i, j]

           )
# 
@constraint(m, powUseCompEq[i = 0:tHorz, j = 0:hSlice-1], 
            xPowUseComp[i, j] == aPowUseRateComp * xCo2Comp[i, j]
           )
# 
# @constraint(m, powUseCompIn[i = 0:tHorz - 1], xPowUseComp[i] <= vCapComp)

# @constraint(m, co2VentEq[i = 0:tHorz - 1], 
# xCo2Vent[i] == vCo2PccVent[i] + xCo2DacVentFlue[i])
@constraint(m, co2VentEq[i = 0:tHorz, j = 0:hSlice-1], 
            xCo2Vent[i, j] == vCo2PccVent[i, j] 
            + (xCo2DacVentFlue[i, j] - xCo2CapDacAir[i, j])
           )

## Overall

#
@constraint(m, powGrossEq[i = 0:tHorz, j = 0:hSlice-1], 
            xPowGross[i, j] == xPowGasTur[i, j] + xPowSteaTur[i, j]
           )
@constraint(m, auxPowEq[i = 0:tHorz, j = 0:hSlice-1],
            xAuxPow[i, j] == xAuxPowGasT[i, j] + xAuxPowSteaT[i, j])

@constraint(m, powOutEq[i = 0:tHorz, j = 0:hSlice-1], 
            xPowOut[i, j] == xPowGross[i, j] 
            - xPowUsePcc[i, j]
            - xPowUseDacFlue[i, j] 
            - xPowUseDacAir[i, j] 
            - xPowUseComp[i, j] 
            - xAuxPow[i, j]
           )

# Piece-wise constant DOF
@constraint(m, pwleq[i = 0:tHorz, j = 1:hSlice-1],
            yGasTelecLoad[i, 0] == yGasTelecLoad[i, j]
           )
@constraint(m, pwssd[i = 0:tHorz, j = 1:hSlice-1],
           xSideSteaDac[i, 0] == xSideSteaDac[i, j]  
           )
@constraint(m, pwco2vent[i = 0:tHorz, j = 1:hSlice-1],
            vCo2PccVent[i, 0] == vCo2PccVent[i, j]
           )

# Continuity of states
@constraint(m, 
            contxfflue[i = 1:tHorz], xFflue[i, 0] == xFflue[i - 1, hSlice])
@constraint(m, 
            conta1flue[i = 1:tHorz], xA1Flue[i, 0] == xA1Flue[i - 1, hSlice])


@constraint(m, 
            contcxsflue[i = 1:tHorz], xSflue[i, 0] == xSflue[i - 1, hSlice])
@constraint(m, 
            contr1flue[i = 1:tHorz], xR1Flue[i, 0] == xR1Flue[i - 1, hSlice])

@constraint(m, 
            contxfair[i = 1:tHorz], xFair[i, 0] == xFair[i - 1, hSlice])
@constraint(m, 
            conta1air[i = 1:tHorz], xA1Air[i, 0] == xA1Air[i - 1, hSlice])
@constraint(m, 
            conta2air[i = 1:tHorz], xA2Air[i, 0] == xA2Air[i - 1, hSlice])
@constraint(m, 
            contcxsair[i = 1:tHorz], xSair[i, 0] == xSair[i - 1, hSlice])
@constraint(m, 
            contr1air[i = 1:tHorz], xR1Air[i, 0] == xR1Air[i - 1, hSlice])

# Objective function expression
@expression(m, eObjfExpr, 
    sum(cNgPerMmbtu * sum(xFuel[i, j] for j in 0:hSlice-1)
        + cEmissionPrice * sum(xCo2Vent[i, j] for j in 0:hSlice-1) 
        + cCo2TranspPrice * sum(xCo2Comp[i, j] for j in 0:hSlice-1)
        - pow_price[i + 1] * sum(xPowOut[i, j] for j in 0:hSlice-1)
        for i in 0:tHorz)
        )

@objective(m, Min, eObjfExpr)

print("The number of variables\t")
println(num_variables(m))
print("The number of constraints\n")

n = 0
for i in list_of_constraint_types(m)
    global n
    println(num_constraints(m, i[1], i[2]))
    n += num_constraints(m, i[1], i[2])
end


println()

# Set optimizer options
set_optimizer(m, Cbc.Optimizer)
set_optimizer_attribute(m, "LogLevel", 3)
#set_optimizer_attribute(m, "PresolveType", 1)

optimize!(m)
println(termination_status(m))

#f = open("model.lp", "w")
#print(f, m)
#close(f)

#write_to_file(m, "lp_mk0.mps")
#write_to_file(m, "lp_mk10.lp", format=MOI.FileFormats.FORMAT_LP)

#format::MOI.FileFormats.FileFormat = MOI.FileFormats.FORMAT_AUTOMATIC

# Co2 Data Frame
df_co = DataFrame(Symbol("Co2Fuel") => Float64[], # Pairs.
                  Symbol("Co2CapPcc") => Float64[],
                  Symbol("Co2PccOut") => Float64[],
                  Symbol("vCo2PccVent") => Float64[],
                  Symbol("Co2DacFlueIn") => Float64[],
                  Symbol("Co2CapDacFlue") => Float64[],
                  Symbol("Co2CapDacAir") => Float64[],
                  Symbol("Co2DacVentFlue") => Float64[],
                  Symbol("Co2Vent") => Float64[],
                 )

# Co2 / hSlice
for i in 0:tHorz
    co2fuel = 0
    co2pcc = 0
    co2pccout = 0
    co2pccvent = 0
    co2dacfluein = 0
    co2dacflue = 0
    co2dacair = 0
    co2dacventflue = 0
    co2vent = 0
    for j in 0:hSlice-1
        co2fuel += value(xCo2Fuel[i, j])
        co2pcc += value(xCo2CapPcc[i, j])
        co2pccout += value(xCo2PccOut[i, j])
        co2pccvent += value(vCo2PccVent[i, j])
        co2dacfluein += value(xCo2DacFlueIn[i, j])
        co2dacflue += value(xCo2CapDacFlue[i, j])
        co2dacair += value(xCo2CapDacAir[i, j])
        co2dacventflue += value(xCo2DacVentFlue[i, j])
        co2vent += value(xCo2Vent[i, j])
        #=push!(df_co, (
            value(xCo2Fuel[i, j]),
            value(xCo2CapPcc[i, j]),
            value(xCo2PccOut[i, j]), 
            value(vCo2PccVent[i, j]), 
            value(xCo2DacFlueIn[i, j]), 
            value(xCo2CapDacFlue[i, j]), 
            value(xCo2CapDacAir[i, j]), 
            value(xCo2DacVentFlue[i, j]), 
            value(xCo2Vent[i, j])))=#
    end
    push!(df_co,(
        value(co2fuel),
        value(co2pcc),
        value(co2pccout),
        value(co2pccvent),
        value(co2dacfluein),
        value(co2dacflue),
        value(co2dacair),
        value(co2dacventflue),
        value(co2vent),
        ))
end

# Power Data Frame.
df_pow = DataFrame(
                  Symbol("PowGasTur") => Float64[], # Pairs.
                  Symbol("PowSteaTurb") => Float64[],
                  Symbol("PowHp") => Float64[],
                  Symbol("PowIp") => Float64[],
                  Symbol("PowLp") => Float64[],
                  Symbol("PowUsePcc") => Float64[],
                  Symbol("PowUseDacFlue") => Float64[],
                  Symbol("PowUseDacAir") => Float64[],
                  Symbol("PowUseComp") => Float64[],
                  Symbol("AuxPowGasT") => Float64[],
                  Symbol("AuxPowSteaT") => Float64[],
                  Symbol("PowGross") => Float64[],
                  Symbol("PowOut") => Float64[],
                  Symbol("yGasTelecLoad") => Float64[],
                 )


# Pow / hSlice
for i in 0:tHorz
    powgastur = 0
    powsteatur = 0
    powhp = 0
    powip = 0
    powlp = 0
    powusepcc = 0
    powusedacflue = 0
    powusedacair = 0
    powusecomp = 0
    auxpowgast = 0
    auxpowsteat = 0
    powgross = 0
    powout = 0
    ygastelecload = value(yGasTelecLoad[i, hSlice-1])
    for j in 0:hSlice-1
        powgastur += value(xPowGasTur[i, j])
        powsteatur += value(xPowSteaTur[i, j])
        powhp += value(xPowHp[i, j])
        powip += value(xPowIp[i, j])
        powlp += value(xPowLp[i, j])
        powusepcc += value(xPowUsePcc[i, j])
        powusedacflue += value(xPowUseDacFlue[i, j])
        powusedacair += value(xPowUseDacAir[i, j])
        powusecomp += value(xPowUseComp[i, j])
        auxpowgast += value(xAuxPowGasT[i, j])
        auxpowsteat += value(xAuxPowSteaT[i, j])
        powgross += value(xPowGross[i, j])
        powout += value(xPowOut[i, j])
        #ygastelecload += value(yGasTelecLoad[i, j])
    #=push!(df_pow, (
            value(xPowGasTur[i, j]),
            value(xPowSteaTur[i, j]),
            value(xPowHp[i, j]), 
            value(xPowIp[i, j]), 
            value(xPowLp[i, j]), 
            value(xPowUsePcc[i, j]), 
            value(xPowUseDacFlue[i, j]), 
            value(xPowUseDacAir[i, j]), 
            value(xPowUseComp[i, j]),
            value(xAuxPowGasT[i, j]),
            value(xAuxPowSteaT[i, j]),
            value(xPowGross[i, j]),
            value(xPowOut[i, j]),
            value(yGasTelecLoad[i, j]),
                  ))=#
    end
    push!(df_pow, (
        powgastur,
        powsteatur,
        powhp,
        powip,
        powlp,
        powusepcc,
        powusedacflue,
        powusedacair,
        powusecomp,
        auxpowgast,
        auxpowsteat,
        powgross,
        powout,
        ygastelecload
        ))
end


# Steam DataFrame
df_steam = DataFrame(
                     Symbol("CcRebDuty") => Float64[],
                     Symbol("SteaUsePcc") => Float64[],
                     Symbol("PccSteaSlack") => Float64[],
                     Symbol("DacSteaDuty") => Float64[],
                     Symbol("SteaUseDacFlue") => Float64[],
                     Symbol("SteaUseDacAir") => Float64[],
                     Symbol("DacSteaSlack") => Float64[],
                     Symbol("SideStea") => Float64[],
                     Symbol("DacSteaBaseDuty") => Float64[],
                     Symbol("SideSteaDac") => Float64[],
                     Symbol("Fuel") => Float64[]
                    )

# Steam / hSlice
for i in 0:tHorz
    ccrebduty = 0
    steausepcc = 0
    pccsteaslack = 0
    dacsteaduty = 0
    steausedacflue = 0
    steausedacair = 0
    dacsteaslack = 0
    sidesteam = 0
    dacsteabaseduty = 0
    sidesteadac = 0
    xfuel = 0
    for j in 0:hSlice-1
        ccrebduty += value(xCcRebDuty[i, j])
        steausepcc += value(xSteaUsePcc[i, j])
        pccsteaslack += value(xPccSteaSlack[i, j])
        dacsteaduty += value(xDacSteaDuty[i, j])
        steausedacflue += value(xSteaUseDacFlue[i, j])
        steausedacair += value(xSteaUseDacAir[i, j])
        dacsteaslack += value(xDacSteaSlack[i, j])
        sidesteam += value(xSideSteam[i, j])
        dacsteabaseduty += value(xDacSteaBaseDuty[i, j])
        sidesteadac += value(xSideSteaDac[i, j])
        xfuel += value(xFuel[i, j])
    end
    #=push!(df_steam, (
            value(xCcRebDuty[i, j]),
            value(xSteaUsePcc[i, j]),
            value(xPccSteaSlack[i, j]),
            value(xDacSteaDuty[i, j]),
            value(xSteaUseDacFlue[i, j]),
            value(xSteaUseDacAir[i, j]),
            value(xDacSteaSlack[i, j]),
            value(xSideSteam[i, j]),
            value(xDacSteaBaseDuty[i, j]),
            value(xSideSteaDac[i, j]),
            value(xFuel[i, j])
                    ),
         )=#
    push!(df_steam, 
        (
            ccrebduty,
            steausepcc,
            pccsteaslack,
            dacsteaduty,
            steausedacflue,
            steausedacair,
            dacsteaslack,
            sidesteam,
            dacsteabaseduty,
            sidesteadac,
            xfuel
            ))
end

# DAC-flue DataFrame
df_dac_flue = DataFrame(
    :time => Float64[],
    :xFflue => Float64[],
    :xSflue => Float64[],
    :xA0Flue => Float64[],
    :xA1Flue => Float64[],
    :xR0Flue => Float64[],
    :xR1Flue => Float64[]
    )


for i in 0:tHorz
    for j in 0:hSlice-1
        currtime = i + j * sliceFact
        push!(df_dac_flue,(
            currtime,
            value(xFflue[i, j]), 
            value(xSflue[i, j]),
            value(xA0Flue[i, j]), 
            value(xA1Flue[i, j]), 
            value(xR0Flue[i, j]), 
            value(xR1Flue[i, j]))
        )
    end
end

# DAC-air DataFrame
df_dac_air = DataFrame(
    :time => Float64[],
    :xFair => Float64[],
    :xSair => Float64[],
    :xA0Air => Float64[],
    :xA1Air => Float64[],
    :xA2Air => Float64[],
    :xR0Air => Float64[],
    :xR1Air => Float64[])

for i in 0:tHorz
    for j in 0:hSlice-1
        currtime = i + j * sliceFact
        push!(df_dac_air,(
            currtime,
            value(xFair[i, j]), 
            value(xSair[i, j]),
            value(xA0Air[i, j]), 
            value(xA1Air[i, j]), 
            value(xA2Air[i, j]),
            value(xR0Air[i, j]), 
            value(xR1Air[i, j])))
    end
end


df_pow_price = DataFrame(
                         price = Float64[]
                        )
for i in 0:tHorz
    push!(df_pow_price, (pow_price[i + 1],))
end



# Cost DataFrame
df_cost = DataFrame(
                    cNG = Float64[],
                    cCo2Em = Float64[],
                    cTransp = Float64[],
                    PowSales = Float64[]
                   )

for i in 0:tHorz
    cng = 0
    cco = 0
    ctr = 0
    cpow = 0
    for j in 0:hSlice-1
        cng += cNgPerMmbtu * value(xFuel[i, j])
        cco += cEmissionPrice * value(xCo2Vent[i, j])
        ctr += cCo2TranspPrice * value(xCo2Comp[i, j])
        cpow += pow_price[i + 1] * value(xPowOut[i, j])
    end
    push!(df_cost, (cng, cco, ctr, cpow))
end

df_time_slice = DataFrame(:time => Float64[])

for i in 0:tHorz
    for j in 0:hSlice-1
        currtime = i + j * sliceFact
        push!(df_time_slice, (currtime, ))
    end
end


df_binary = DataFrame(
    :yoff => Float64[],
    :yon => Float64[],
    :zoffon => Float64[],
    :zonoff => Float64[],
    )

for i in 0:tHorz
    push!(df_binary, 
        (
            value(y[i, 0]),
            value(y[i, 1]),
            value(z[i, 0, 1]),
            value(z[i, 1, 0]),
        ))
end

df_pr = DataFrame(
    :load0 => Float64[], 
    :load1 => Float64[], 
    :lambda0 => Float64[], 
    :lambda10 => Float64[],
    :lambda11 => Float64[]
    )

for i in 0:tHorz
    push!(df_pr, (
        value(xLoad[i, 0]), 
        value(xLoad[i, 1]), 
        value(lambda0[i, 0]), 
        value(lambda1[i, 0]),
        value(lambda1[i, 1])
        ))
end

# Write CSV
CSV.write("df_co.csv", df_co)
CSV.write("df_pow.csv", df_pow)
CSV.write("df_steam.csv", df_steam)
CSV.write("df_dac_flue.csv", df_dac_flue)
CSV.write("df_dac_air.csv", df_dac_air)
CSV.write("df_pow_price.csv", df_pow_price)
CSV.write("df_cost.csv", df_cost)
CSV.write("df_time_slice.csv", df_time_slice)
CSV.write("df_binary.csv", df_binary)
CSV.write("df_pr.csv", df_pr)
